import Foundation

@main enum CountryRegionCatalogStoreTests {
    enum Failure: Error { case network, disk }

    final class Network {
        var calls = 0
        var completion: ((Result<[String: Any], Error>) -> Void)?
        func fetch(_ completion: @escaping (Result<[String: Any], Error>) -> Void) {
            precondition(Thread.isMainThread)
            calls += 1
            self.completion = completion
        }
    }

    static func response(_ codes: [String]) -> [String: Any] {
        ["code": 200, "message": "success", "data": codes.map { ["code": $0, "name": "Country " + $0] }]
    }

    static func drain(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "Async operation did not settle")
    }

    static func main() throws {
        try testReplacementAndRelaunch()
        try testFailureAndInvalidResponses()
        try testMissingAndCorruptCache()
        try testWriteFailure()
        try testExplicitColdRetryAndLateResponses()
        print("PASS: country catalog bounded refresh and explicit cold-retry lifecycle, full replacement, cache recovery, persistence and detached observers")
    }

    static func testReplacementAndRelaunch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cache = CountryRegionCatalogCache(url: root.appendingPathComponent("countries-v1.json"))
        try cache.write(CountryRegionCatalog(response: response(["CN", "US"])).cacheData(fetchedAt: Date()))
        let network = Network()
        let store = CountryRegionCatalogStore(readCache: cache.read, writeCache: cache.write, fetch: network.fetch)
        var notifications = 0
        let observation = store.observe { precondition(Thread.isMainThread); notifications += 1 }
        for _ in 0..<20 { store.startIfNeeded(); store.retryIfUnavailable() }
        drain { network.calls == 1 }
        precondition(store.catalog?.entries.map(\.code) == ["CN", "US"], "Cache must be usable during refresh")
        store.removeObserver(observation)
        let detachedCount = notifications
        // The process owns the request: removing the last page cannot cancel it.
        DispatchQueue.global().async { network.completion?(.success(response(["FR"]))) }
        drain { store.phase == .succeeded }
        precondition(store.catalog?.entries.map(\.code) == ["FR"], "Refresh must replace, never merge old countries")
        precondition(store.catalog?.entry(code: "US") == nil)
        precondition(notifications == detachedCount, "Detached page must not receive late results")
        for _ in 0..<20 { store.startIfNeeded(); store.retryIfUnavailable() }
        precondition(network.calls == 1)
        let disk = try CountryRegionCatalog(data: cache.read()!)
        precondition(disk.entries.map(\.code) == ["FR"], "Persisted cache must also discard old countries")

        let nextNetwork = Network()
        let nextProcess = CountryRegionCatalogStore(readCache: cache.read, writeCache: cache.write, fetch: nextNetwork.fetch)
        nextProcess.startIfNeeded()
        drain { nextNetwork.calls == 1 }
        precondition(nextProcess.catalog?.entries.map(\.code) == ["FR"])
        nextNetwork.completion?(.failure(Failure.network))
        drain { nextProcess.phase == .failed }
        precondition(nextProcess.catalog?.entries.map(\.code) == ["FR"])
    }

    static func testFailureAndInvalidResponses() throws {
        let old = try CountryRegionCatalog(response: response(["CN", "US"])).cacheData(fetchedAt: Date())
        let outcomes: [Result<[String: Any], Error>] = [
            .failure(Failure.network), .success(response([])), .success(response(["CN", "CN"])),
            .success(["code": 500, "data": [["code": "FR", "name": "France"]]]),
            .success(["code": 200, "data": [["code": "FR", "name": 42]]])
        ]
        for outcome in outcomes {
            let network = Network()
            let store = CountryRegionCatalogStore(readCache: { old }, writeCache: { _ in preconditionFailure("Invalid result must not overwrite disk") }, fetch: network.fetch)
            store.startIfNeeded()
            drain { network.calls == 1 }
            network.completion?(outcome)
            drain { store.phase == .failed }
            precondition(store.catalog?.entries.map(\.code) == ["CN", "US"])
            for _ in 0..<20 { store.startIfNeeded(); store.retryIfUnavailable() }
            precondition(network.calls == 1, "Failure consumes the only attempt, too")
        }
    }

    static func testMissingAndCorruptCache() throws {
        for bytes in [nil, Data("broken".utf8)] as [Data?] {
            let network = Network()
            let store = CountryRegionCatalogStore(readCache: {
                precondition(!Thread.isMainThread)
                return bytes
            }, writeCache: { _ in precondition(!Thread.isMainThread) }, fetch: network.fetch)
            store.startIfNeeded()
            drain { network.calls == 1 }
            precondition(store.catalog == nil)
            network.completion?(.success(response(["FR"])))
            drain { store.phase == .succeeded }
            precondition(store.catalog?.entries.map(\.code) == ["FR"])
        }
        let network = Network()
        let store = CountryRegionCatalogStore(readCache: { nil }, writeCache: { _ in }, fetch: network.fetch)
        store.startIfNeeded()
        drain { network.calls == 1 }
        network.completion?(.failure(Failure.network))
        drain { store.phase == .failed }
        store.startIfNeeded()
        precondition(store.catalog == nil && network.calls == 1, "Page entry must not invent a fallback or automatically retry")
    }

    static func testWriteFailure() throws {
        let old = try CountryRegionCatalog(response: response(["CN"])).cacheData(fetchedAt: Date())
        let network = Network()
        let store = CountryRegionCatalogStore(readCache: { old }, writeCache: { _ in throw Failure.disk }, fetch: network.fetch)
        store.startIfNeeded()
        drain { network.calls == 1 }
        network.completion?(.success(response(["FR"])))
        drain { store.phase == .succeeded }
        precondition(store.catalog?.entries.map(\.code) == ["FR"], "Disk failure must not block this process's valid new data")
        store.startIfNeeded()
        store.retryIfUnavailable()
        precondition(network.calls == 1)
    }

    static func testExplicitColdRetryAndLateResponses() throws {
        for bytes in [nil, Data("broken".utf8)] as [Data?] {
            let network = Network()
            let store = CountryRegionCatalogStore(readCache: { bytes }, writeCache: { _ in }, fetch: network.fetch)
            store.startIfNeeded()
            for _ in 0..<20 { store.retryIfUnavailable() }
            drain { network.calls == 1 }
            let first = network.completion!
            first(.failure(Failure.network))
            drain { store.phase == .failed }
            for _ in 0..<20 { store.startIfNeeded() }
            precondition(network.calls == 1, "Reentering/resuming must not retry automatically")

            store.retryIfUnavailable()
            precondition(network.calls == 2 && store.phase == .requesting, "An explicit tap retries a cold failure")
            let second = network.completion!
            for _ in 0..<20 { store.retryIfUnavailable(); store.startIfNeeded() }
            precondition(network.calls == 2, "Concurrent taps join the in-flight request")
            // A timed-out first request must not win against the second attempt.
            first(.success(response(["US"])))
            second(.success(response([])))
            drain { store.phase != .requesting }
            precondition(store.phase == .failed && store.catalog == nil, "Old success cannot overwrite a newer failed attempt")

            store.retryIfUnavailable()
            precondition(network.calls == 3, "Each new tap can retry another cold failure")
            let third = network.completion!
            second(.failure(Failure.network))
            third(.success(response(["FR"])))
            drain { store.phase != .requesting }
            precondition(store.phase == .succeeded && store.catalog?.entries.map(\.code) == ["FR"], "Late errors cannot fail a new attempt")
            for _ in 0..<20 { store.retryIfUnavailable(); store.startIfNeeded() }
            precondition(network.calls == 3, "After success, further taps must use memory")
        }
    }
}
