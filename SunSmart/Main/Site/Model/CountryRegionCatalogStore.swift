import Foundation

/// Process-owned request; all state/observers are main-thread confined, disk work is serialized.
final class CountryRegionCatalogStore {
    enum Phase { case notStarted, loadingCache, requesting, succeeded, failed }
    typealias Fetch = (@escaping (Result<[String: Any], Error>) -> Void) -> Void

    private(set) var catalog: CountryRegionCatalog?
    private(set) var phase: Phase = .notStarted
    private let readCache: () throws -> Data?
    private let writeCache: (Data) throws -> Void
    private let fetch: Fetch
    private let queue = DispatchQueue(label: "com.sunricher.site-country-catalog", qos: .userInitiated)
    private var observers: [UUID: () -> Void] = [:]
    private var receivedResponse = false
    private var requestID: UUID?

    init(readCache: @escaping () throws -> Data?, writeCache: @escaping (Data) throws -> Void, fetch: @escaping Fetch) {
        self.readCache = readCache
        self.writeCache = writeCache
        self.fetch = fetch
    }

    func observe(_ callback: @escaping () -> Void) -> UUID {
        precondition(Thread.isMainThread)
        let id = UUID()
        observers[id] = callback
        return id
    }

    func removeObserver(_ id: UUID) {
        precondition(Thread.isMainThread)
        observers.removeValue(forKey: id)
    }

    func startIfNeeded() {
        precondition(Thread.isMainThread)
        guard phase == .notStarted else { return }
        phase = .loadingCache
        notifyObservers()
        queue.async {
            let cached = (try? self.readCache()).flatMap { try? CountryRegionCatalog(data: $0) }
            DispatchQueue.main.async {
                self.catalog = cached
                self.beginRequest()
            }
        }
    }

    /// Only an explicit input tap may retry a failed request with no usable snapshot.
    func retryIfUnavailable() {
        precondition(Thread.isMainThread)
        guard phase == .failed, catalog == nil else { return }
        beginRequest()
    }

    private func beginRequest() {
        let id = UUID()
        requestID = id
        receivedResponse = false
        phase = .requesting
        notifyObservers()
        // Marked before fetch: reentrant page/observer calls join the current attempt.
        fetch { result in
            DispatchQueue.main.async { self.receive(result, requestID: id) }
        }
    }

    private func receive(_ result: Result<[String: Any], Error>, requestID id: UUID) {
        guard requestID == id, phase == .requesting, !receivedResponse else { return }
        receivedResponse = true
        queue.async {
            let parsed = result.flatMap { response in Result { try CountryRegionCatalog(response: response) } }
            if case .success(let catalog) = parsed {
                do { try self.writeCache(catalog.cacheData(fetchedAt: Date())) }
                catch {
                    #if DEBUG
                    print("[CountryCatalog] Persisting the refreshed catalog failed; using memory for this process.")
                    #endif
                }
            }
            DispatchQueue.main.async {
                guard self.requestID == id else { return }
                switch parsed {
                case .success(let catalog):
                    self.catalog = catalog // Complete replacement, never a merge with old entries.
                    self.phase = .succeeded
                case .failure:
                    self.phase = .failed // Preserve the last valid snapshot, if one exists.
                }
                self.notifyObservers()
            }
        }
    }

    private func notifyObservers() {
        for callback in Array(observers.values) { callback() }
    }
}

struct CountryRegionCatalogCache {
    let url: URL

    func read() throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return nil
        }
    }

    func write(_ data: Data) throws {
        var directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        try data.write(to: url, options: .atomic)
    }
}
