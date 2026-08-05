import Dispatch
import Foundation

private struct CacheRecord: Equatable, Sendable {
    let id: Int
    let revision: Int
}

@main
struct DeviceEmerFireCacheTests {

    static func main() {
        testReplaceReturnsIndependentSnapshot()
        testMergeReplacesMatchingAndAppendsNewRecords()
        testRemoveAllRemovesOnlyMatchingRecords()
        testConcurrentMergesKeepOneRecordPerIdentifier()
        print("DeviceEmerFireCacheTests passed")
    }

    private static func testReplaceReturnsIndependentSnapshot() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        var source = [CacheRecord(id: 1, revision: 10)]
        cache.replace(with: source)
        source.append(CacheRecord(id: 2, revision: 20))

        precondition(cache.snapshot() == [CacheRecord(id: 1, revision: 10)])
    }

    private static func testMergeReplacesMatchingAndAppendsNewRecords() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        cache.replace(with: [CacheRecord(id: 1, revision: 10)])
        cache.merge([
            CacheRecord(id: 1, revision: 11),
            CacheRecord(id: 2, revision: 20),
        ]) { existing, incoming in
            existing.id == incoming.id
        }

        precondition(cache.snapshot() == [
            CacheRecord(id: 1, revision: 11),
            CacheRecord(id: 2, revision: 20),
        ])
    }

    private static func testRemoveAllRemovesOnlyMatchingRecords() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        cache.replace(with: [
            CacheRecord(id: 1, revision: 10),
            CacheRecord(id: 2, revision: 20),
            CacheRecord(id: 3, revision: 30),
        ])
        cache.removeAll { $0.id.isMultiple(of: 2) }

        precondition(cache.snapshot() == [
            CacheRecord(id: 1, revision: 10),
            CacheRecord(id: 3, revision: 30),
        ])
    }

    private static func testConcurrentMergesKeepOneRecordPerIdentifier() {
        let cache = DeviceEmerFireCache<CacheRecord>()
        cache.replace(with: (0..<64).map { CacheRecord(id: $0, revision: 0) })
        let group = DispatchGroup()

        for worker in 0..<32 {
            DispatchQueue.global().async(group: group) {
                for iteration in 0..<2_000 {
                    let id = (worker + iteration) % 64
                    cache.merge([CacheRecord(id: id, revision: worker * 2_000 + iteration)]) {
                        $0.id == $1.id
                    }
                    _ = cache.snapshot()
                }
            }
        }

        group.wait()
        let snapshot = cache.snapshot()
        precondition(snapshot.count == 64)
        precondition(Set(snapshot.map(\.id)) == Set(0..<64))
    }
}
