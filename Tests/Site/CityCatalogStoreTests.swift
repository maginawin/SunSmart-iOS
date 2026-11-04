import Foundation

@main enum CityCatalogStoreTests {
    enum Failure: Error { case network, disk }
    final class Network {
        var calls: [String] = []
        var replies: [(Result<[String: Any], Error>) -> Void] = []
        func fetch(_ code: String, completion: @escaping (Result<[String: Any], Error>) -> Void) {
            precondition(Thread.isMainThread); calls.append(code); replies.append(completion)
        }
    }
    static func response(_ id: Int? = 1) -> [String: Any] {
        let rows: [[String: Any]] = id.map { [["id": $0, "name": "Raw", "names_json": ["en": "English"],
                                              "latitude": "0", "longitude": "1", "timezone": "Etc/UTC"]] } ?? []
        return ["code": 200, "data": rows]
    }
    static func drain(_ condition: () -> Bool) {
        let until = Date().addingTimeInterval(5)
        while !condition(), Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        precondition(condition(), "City store operation did not settle")
    }
    static func main() throws {
        try replacementAndRestart()
        try coldRetriesAndLateResponses()
        try evictionAndWriteFailure()
        print("PASS: per-country lifecycle, cache replacement/empty success, cold retries, detached observers, stale callbacks, LRU and write failure")
    }
    static func replacementAndRestart() throws {
        var disk: [String: Data] = ["US": try CityCatalog(response: response(1), countryCode: "US").cacheData(fetchedAt: Date())]
        let network = Network()
        let store = CityCatalogStore(readCache: { disk[$0] }, writeCache: { disk[$0] = $1 }, fetch: network.fetch)
        var observed = 0
        let observation = store.observe(countryCode: "US") { precondition(Thread.isMainThread); observed += 1 }
        for _ in 0..<10 { store.startIfNeeded(countryCode: "US"); store.retryIfUnavailable(countryCode: "US") }
        drain { network.calls == ["US"] }
        precondition(store.catalog(countryCode: "US")?.entry(id: "geonames:1") != nil)
        let oldRevision = store.revision(countryCode: "US")
        store.removeObserver(observation)
        let detached = observed
        network.replies[0](.success(response(2)))
        drain { store.phase(countryCode: "US") == .succeeded }
        precondition(observed == detached)
        precondition(store.catalog(countryCode: "US")?.entry(id: "geonames:1") == nil)
        precondition(store.catalog(countryCode: "US")?.entry(id: "geonames:2") != nil)
        precondition(store.revision(countryCode: "US") != oldRevision)
        for _ in 0..<10 { store.startIfNeeded(countryCode: "US"); store.retryIfUnavailable(countryCode: "US") }
        precondition(network.calls == ["US"])
        let nextNetwork = Network()
        let next = CityCatalogStore(readCache: { disk[$0] }, writeCache: { disk[$0] = $1 }, fetch: nextNetwork.fetch)
        next.startIfNeeded(countryCode: "US")
        drain { nextNetwork.calls == ["US"] }
        precondition(next.catalog(countryCode: "US")?.entry(id: "geonames:2") != nil)
        nextNetwork.replies[0](.failure(Failure.network))
        drain { next.phase(countryCode: "US") == .failed }
        for _ in 0..<5 { next.retryIfUnavailable(countryCode: "US"); next.startIfNeeded(countryCode: "US") }
        precondition(nextNetwork.calls == ["US"] && next.catalog(countryCode: "US") != nil)
        // A successful empty directory is also a cache: it must replace old rows and suppress retries.
        store.startIfNeeded(countryCode: "FR")
        drain { network.calls.count == 2 }
        network.replies[1](.success(response(nil)))
        drain { store.phase(countryCode: "FR") == .succeeded }
        precondition(store.catalog(countryCode: "FR")?.entries.isEmpty == true)
        store.retryIfUnavailable(countryCode: "FR")
        precondition(network.calls.count == 2)
    }
    static func coldRetriesAndLateResponses() throws {
        let network = Network()
        var writes: [String] = []
        let store = CityCatalogStore(readCache: { _ in Data("broken".utf8) },
                                     writeCache: { code, _ in writes.append(code) }, fetch: network.fetch)
        for bad in ["../US", "us", "legacy country", ""] { store.startIfNeeded(countryCode: bad) }
        precondition(network.calls.isEmpty)
        store.startIfNeeded(countryCode: "US"); store.startIfNeeded(countryCode: "CN")
        drain { network.calls.count == 2 }
        let us = network.calls.firstIndex(of: "US")!, cn = network.calls.firstIndex(of: "CN")!
        network.replies[us](.failure(Failure.network))
        network.replies[cn](.success(response(3)))
        drain { store.phase(countryCode: "US") == .failed && store.phase(countryCode: "CN") == .succeeded }
        for _ in 0..<10 { store.retryIfUnavailable(countryCode: "US") }
        precondition(network.calls.count == 3)
        network.replies[us](.success(response(99))) // Old timeout must not complete the retry or write disk.
        network.replies[2](.success(["code": 200, "data": NSNull()]))
        drain { store.phase(countryCode: "US") == .failed }
        precondition(store.catalog(countryCode: "US") == nil && writes == ["CN"])
        store.retryIfUnavailable(countryCode: "US")
        network.replies[3](.success(response(4)))
        drain { store.phase(countryCode: "US") == .succeeded }
        network.replies[2](.failure(Failure.network)); network.replies[us](.success(response(99)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        precondition(store.catalog(countryCode: "US")?.entry(id: "geonames:4") != nil && writes == ["CN", "US"])
    }
    static func evictionAndWriteFailure() throws {
        var disk: [String: Data] = [:]
        var reads: [String] = []
        let network = Network()
        let store = CityCatalogStore(readCache: { reads.append($0); return disk[$0] }, writeCache: { code, data in
            if code == "JP" { throw Failure.disk }; disk[code] = data
        }, fetch: network.fetch)
        let pin = store.observe(countryCode: "US") {}
        for code in ["US", "JP", "CN", "FR"] {
            store.startIfNeeded(countryCode: code)
            drain { network.calls.last == code }
            network.replies.last!(.success(response(7)))
            drain { store.phase(countryCode: code) == .succeeded }
        }
        precondition(store.catalog(countryCode: "US") != nil, "Visible country's snapshot stays retained")
        precondition(store.catalog(countryCode: "JP") != nil, "Failed persistence must not lose the only valid snapshot")
        store.removeObserver(pin)
        // Touch CN and FR so US becomes a disk-only snapshot.
        for code in ["CN", "FR"] {
            store.startIfNeeded(countryCode: code)
            drain { store.catalog(countryCode: code) != nil }
        }
        precondition(store.catalog(countryCode: "US") == nil)
        store.startIfNeeded(countryCode: "US")
        drain { store.catalog(countryCode: "US") != nil }
        precondition(reads.filter { $0 == "US" }.count == 2 && network.calls.count == 4)
        store.retryIfUnavailable(countryCode: "JP")
        precondition(network.calls.count == 4 && store.catalog(countryCode: "JP") != nil)
        // Evicted cache subsequently disappears: no new automatic attempt or retry privilege.
        for code in ["CN", "FR"] {
            store.startIfNeeded(countryCode: code)
            drain { store.catalog(countryCode: code) != nil }
        }
        disk["US"] = nil
        store.startIfNeeded(countryCode: "US")
        drain { !store.isLoading(countryCode: "US") }
        store.retryIfUnavailable(countryCode: "US"); store.startIfNeeded(countryCode: "US")
        precondition(store.catalog(countryCode: "US") == nil && network.calls.count == 4)
    }
}
