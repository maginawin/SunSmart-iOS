import Foundation

/// Main-thread request ownership; snapshot reads are safe from Mesh send queues.
final class SiteTimeZoneStore {
    typealias Completion = (SiteTimeZoneSnapshot?) -> Void
    typealias Fetch = (String, Date, @escaping (Result<[String: Any], Error>) -> Void) -> Void
    private final class State {
        var loaded = false
        var loading = false
        var requestID: UUID?
        var completions: [Completion] = []
        var lastAttemptBoundary: String?
        var lastObservedBoundary: String?
    }
    private let now: () -> Date
    private let read: (String) throws -> Data?
    private let write: (String, Data) throws -> Void
    private let fetch: Fetch
    private let io = DispatchQueue(label: "com.sunricher.site-time-zone-cache", qos: .userInitiated)
    private let lock = NSLock()
    private var snapshots: [String: SiteTimeZoneSnapshot] = [:]
    private var states: [String: State] = [:]
    private var observers: [UUID: (String, () -> Void)] = [:]
    private var pending: [String] = []
    private var activeCount = 0

    init(now: @escaping () -> Date = Date.init, read: @escaping (String) throws -> Data?,
         write: @escaping (String, Data) throws -> Void, fetch: @escaping Fetch) {
        self.now = now; self.read = read; self.write = write; self.fetch = fetch
    }
    func snapshot(for identifier: String) -> SiteTimeZoneSnapshot? {
        lock.lock(); defer { lock.unlock() }; return snapshots[identifier]
    }
    func usableSnapshot(for identifier: String, at date: Date? = nil) -> SiteTimeZoneSnapshot? {
        guard let snapshot = snapshot(for: identifier), snapshot.isUsable(at: date ?? now()) else { return nil }
        return snapshot
    }
    @discardableResult func observe(identifier: String, callback: @escaping () -> Void) -> UUID {
        precondition(Thread.isMainThread)
        let token = UUID(); observers[token] = (identifier, callback); return token
    }
    func removeObserver(_ token: UUID) {
        precondition(Thread.isMainThread)
        guard let id = observers.removeValue(forKey: token)?.0 else { return }
        if !observers.values.contains(where: { $0.0 == id }), states[id]?.completions.isEmpty == true {
            pending.removeAll { $0 == id }
        }
    }
    /// Explicit appearances/actions retry failures; passive clock ticks do not spin a retry loop.
    func refresh(identifier: String, retry: Bool = true, completion: Completion? = nil) {
        precondition(Thread.isMainThread)
        guard SiteTimeZoneValue(storageValue: identifier)?.ianaId == identifier else { completion?(nil); return }
        let state = states[identifier] ?? State(); states[identifier] = state
        if let completion { state.completions.append(completion) }
        guard !state.loading, state.requestID == nil, !pending.contains(identifier) else { return }
        if !state.loaded {
            state.loading = true
            io.async {
                let decoded = (try? self.read(identifier)).flatMap { try? JSONDecoder().decode(SiteTimeZoneCache.Envelope.self, from: $0) }
                let cached = decoded.flatMap { $0.version == 1 && $0.snapshot.identifier == identifier ? $0.snapshot : nil }
                DispatchQueue.main.async {
                    state.loading = false; state.loaded = true
                    if let cached { self.publish(cached); self.notify(identifier) }
                    self.refresh(identifier: identifier, retry: retry)
                }
            }
            return
        }
        let date = now()
        if let snapshot = snapshot(for: identifier), !snapshot.needsRefresh(at: date) { finish(identifier); return }
        let boundary = attemptBoundary(identifier, at: date)
        guard retry || state.lastAttemptBoundary != boundary else { finish(identifier); return }
        if completion != nil || !state.completions.isEmpty { pending.insert(identifier, at: 0) }
        else { pending.append(identifier) }
        drain()
    }
    func refreshObserved(retry: Bool = false) {
        precondition(Thread.isMainThread)
        for identifier in Set(observers.values.map(\.0)) {
            let boundary = attemptBoundary(identifier, at: now())
            if let state = states[identifier], state.lastObservedBoundary != boundary {
                state.lastObservedBoundary = boundary; notify(identifier)
            }
            refresh(identifier: identifier, retry: retry)
        }
    }
    private func drain() {
        while activeCount < 3, !pending.isEmpty {
            let identifier = pending.removeFirst()
            guard let state = states[identifier], state.requestID == nil else { continue }
            let requestedAt = now(), requestID = UUID()
            state.requestID = requestID
            state.lastAttemptBoundary = attemptBoundary(identifier, at: requestedAt)
            activeCount += 1
            fetch(identifier, requestedAt) { result in
                DispatchQueue.main.async {
                    guard state.requestID == requestID else { return }
                    // Claim once, including while parsing/persisting on the serial I/O queue.
                    state.requestID = nil; state.loading = true
                    self.io.async {
                        let snapshot = try? result.get()
                        let parsed = snapshot.flatMap { try? SiteTimeZoneSnapshot(identifier: identifier, response: $0, requestedAt: requestedAt) }
                        if let parsed {
                            do { try self.write(identifier, JSONEncoder().encode(SiteTimeZoneCache.Envelope(version: 1, snapshot: parsed))) }
                            catch {
                                #if DEBUG
                                print("[SiteTimeZone] cache write failed; retaining memory snapshot")
                                #endif
                            }
                        }
                        DispatchQueue.main.async {
                            state.loading = false; self.activeCount -= 1
                            if let parsed { self.publish(parsed) }
                            self.finish(identifier)
                            self.notify(identifier)
                            self.drain()
                        }
                    }
                }
            }
        }
    }
    private func publish(_ snapshot: SiteTimeZoneSnapshot) {
        lock.lock(); snapshots[snapshot.identifier] = snapshot; lock.unlock()
    }
    private func finish(_ identifier: String) {
        let callbacks = states[identifier]?.completions ?? []
        states[identifier]?.completions.removeAll()
        let value = usableSnapshot(for: identifier)
        callbacks.forEach { $0(value) }
    }
    private func notify(_ identifier: String) {
        let callbacks = observers.filter { $0.value.0 == identifier }
        for (token, value) in callbacks where observers[token] != nil { value.1() }
    }
    private func attemptBoundary(_ identifier: String, at date: Date) -> String {
        let snapshot = snapshot(for: identifier)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: (snapshot?.offsetMinutes ?? 0) * 60)!
        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let expired = snapshot?.nextSwitchDate.map { date >= $0 } ?? false
        return "\(day.year ?? 0)-\(day.month ?? 0)-\(day.day ?? 0)-\(expired)-\(date < (snapshot?.requestedAt ?? .distantPast))"
    }
}

struct SiteTimeZoneCache {
    struct Envelope: Codable { let version: Int; let snapshot: SiteTimeZoneSnapshot }
    let directory: URL
    private func url(_ identifier: String) -> URL {
        let key = Data(identifier.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent(key + ".json")
    }
    func read(_ identifier: String) throws -> Data? {
        let file = url(identifier)
        return FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : nil
    }
    func write(_ identifier: String, data: Data) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url(identifier), options: .atomic)
    }
}
