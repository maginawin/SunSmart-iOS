import Foundation
@main struct GattWriteReceiptTests {
    static func main() {
        let queue = GattWriteReceiptQueue()
        var events: [String] = []
        queue.append([Data([9])])
        let first = queue.append([Data([1]),Data([2])], completion: { events.append($0 ? "first-ok" : "first-fail") })
        let second = queue.append([Data([3])], completion: { events.append($0 ? "second-ok" : "second-fail") })
        let ordinary = queue.pop()!
        queue.didWrite(ordinary)?()
        precondition(events.isEmpty, "other traffic cannot confirm our batch")
        queue.didWrite(queue.pop()!)?()
        precondition(events.isEmpty, "one fragment cannot confirm a multi-fragment write")
        queue.cancel(second)?()
        precondition(events == ["second-fail"] && queue.count == 1, "cancel only own queued fragments")
        queue.didWrite(queue.pop()!)?()
        precondition(events == ["second-fail","first-ok"], "confirm only after final write")
        queue.cancel(first)?()
        precondition(events.count == 2, "completion exactly once")
        _ = queue.append([Data([4])], completion: { events.append($0 ? "bad" : "disconnect") })
        queue.removeAll().forEach { $0() }
        precondition(queue.count == 0 && events.last == "disconnect", "disconnect fails pending receipts")
        let inFlight = queue.append([Data([5]), Data([6])], completion: { events.append($0 ? "late-ok" : "cancelled") })
        let popped = queue.pop()!
        queue.cancel(inFlight)?()
        queue.didWrite(popped)?()
        precondition(events.last == "cancelled" && queue.count == 0, "late write cannot revive a cancelled receipt")
        var current = true
        let guarded = queue.append([Data([7])], canWrite: { current }) { events.append($0 ? "stale-write" : "stale-cancel") }
        let guardedPacket = queue.pop()!
        precondition(queue.allowsWriting(guardedPacket))
        current = false
        precondition(!queue.allowsWriting(guardedPacket), "context rechecked just before each actual write")
        queue.cancel(guarded)?()
        precondition(!queue.allowsWriting(guardedPacket), "cancelled popped packet is not ordinary traffic")
        print("GattWriteReceiptTests passed")
    }
}
