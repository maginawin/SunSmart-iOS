import Foundation

/// Process-owned attempts are independent of snapshot eviction. All public access is on the main thread.
final class CityCatalogStore {
    enum Phase { case notStarted, loadingCache, requesting, succeeded, failed }
    typealias Fetch = (String, @escaping (Result<[String: Any], Error>) -> Void) -> Void
    private final class State {
        var phase: Phase = .notStarted
        var catalog: CityCatalog?
        var revision: UInt64 = 0
        var hasSnapshot = false
        var persisted = false
        var diskAvailable = false
        var loadingDisk = false
        var requestID: UUID?
        var receivedResponse = false
    }
    private let readCache: (String) throws -> Data?
    private let writeCache: (String, Data) throws -> Void
    private let fetch: Fetch
    private let queue = DispatchQueue(label: "com.sunricher.site-city-catalog", qos: .userInitiated)
    private var states: [String: State] = [:]
    private var recent: [String] = []
    private var observers: [UUID: (code: String, callback: () -> Void)] = [:]

    init(readCache: @escaping (String) throws -> Data?, writeCache: @escaping (String, Data) throws -> Void,
         fetch: @escaping Fetch) {
        self.readCache = readCache; self.writeCache = writeCache; self.fetch = fetch
    }

    func catalog(countryCode: String) -> CityCatalog? {
        precondition(Thread.isMainThread)
        let catalog = states[countryCode]?.catalog
        if catalog != nil { touch(countryCode) }
        return catalog
    }
    func phase(countryCode: String) -> Phase { states[countryCode]?.phase ?? .notStarted }
    func revision(countryCode: String) -> UInt64 { states[countryCode]?.revision ?? 0 }
    func isLoading(countryCode: String) -> Bool {
        states[countryCode]?.loadingDisk == true || phase(countryCode: countryCode) == .requesting
    }

    func observe(countryCode: String, _ callback: @escaping () -> Void) -> UUID {
        precondition(Thread.isMainThread)
        let id = UUID(); observers[id] = (countryCode, callback); return id
    }
    func removeObserver(_ id: UUID) {
        precondition(Thread.isMainThread)
        observers.removeValue(forKey: id); trimSnapshots()
    }

    func startIfNeeded(countryCode code: String) {
        precondition(Thread.isMainThread)
        guard CityCatalog.isValidCountryCode(code) else { return }
        let state = states[code] ?? State()
        states[code] = state
        if state.catalog != nil { touch(code) }
        guard !state.loadingDisk else { return }
        let firstAttempt = state.phase == .notStarted
        guard firstAttempt || (state.catalog == nil && state.hasSnapshot && state.diskAvailable) else { return }
        state.loadingDisk = true
        if firstAttempt { state.phase = .loadingCache }
        notify(code)
        queue.async {
            let cached = (try? self.readCache(code)).flatMap { try? CityCatalog(data: $0, countryCode: code) }
            DispatchQueue.main.async {
                state.loadingDisk = false
                state.diskAvailable = cached != nil
                if let cached {
                    state.catalog = cached; state.hasSnapshot = true; state.persisted = true
                    state.revision &+= 1; self.touch(code)
                }
                if firstAttempt { self.beginRequest(code, state: state) }
                else { self.notify(code) }
            }
        }
    }

    /// Only explicit input taps call this; a lost evicted disk file does not grant another HTTP attempt.
    func retryIfUnavailable(countryCode code: String) {
        precondition(Thread.isMainThread)
        guard let state = states[code], state.phase == .failed, !state.hasSnapshot else { return }
        beginRequest(code, state: state)
    }

    private func beginRequest(_ code: String, state: State) {
        let id = UUID()
        state.requestID = id; state.receivedResponse = false; state.phase = .requesting
        notify(code)
        fetch(code) { result in
            DispatchQueue.main.async { self.receive(result, code: code, requestID: id) }
        }
    }

    private func receive(_ result: Result<[String: Any], Error>, code: String, requestID: UUID) {
        guard let state = states[code], state.requestID == requestID,
              state.phase == .requesting, !state.receivedResponse else { return }
        state.receivedResponse = true
        queue.async {
            let parsed = result.flatMap { response in Result { try CityCatalog(response: response, countryCode: code) } }
            var persisted = false
            if case .success(let catalog) = parsed {
                do { try self.writeCache(code, catalog.cacheData(fetchedAt: Date())); persisted = true }
                catch {
                    #if DEBUG
                    print("[CityCatalog] Persisting \(code) failed; retaining the refreshed snapshot in memory.")
                    #endif
                }
            }
            let saved = persisted
            DispatchQueue.main.async {
                guard state.requestID == requestID else { return }
                switch parsed {
                case .success(let catalog):
                    state.catalog = catalog; state.hasSnapshot = true
                    state.persisted = saved; state.diskAvailable = saved
                    state.revision &+= 1; state.phase = .succeeded; self.touch(code)
                case .failure:
                    state.phase = .failed // An old valid snapshot, including an empty one, survives.
                }
                self.notify(code)
            }
        }
    }

    private func touch(_ code: String) {
        recent.removeAll { $0 == code }; recent.insert(code, at: 0); trimSnapshots()
    }
    private func trimSnapshots() {
        let pinned = Set(observers.values.map(\.code))
        let keep = Set(recent.prefix(2)).union(pinned)
        for code in recent where !keep.contains(code) {
            if let state = states[code], state.persisted { state.catalog = nil }
        }
        recent.removeAll { states[$0]?.catalog == nil }
    }
    private func notify(_ code: String) {
        let callbacks = observers.filter { $0.value.code == code }
        for (id, observer) in callbacks where observers[id] != nil { observer.callback() }
    }
}
