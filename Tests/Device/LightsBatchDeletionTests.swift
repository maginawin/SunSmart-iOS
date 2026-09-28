import Foundation

@main
struct LightsBatchDeletionTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func node(_ id: String, _ address: UInt16, group: UInt16? = nil,
                     subscriptions: Set<UInt16> = [], capable: Bool = true) -> LightsBatchDeletionPlan.Node {
        .init(id: id, address: address, vendorAddress: capable ? address : nil,
              businessGroup: group, subscriptions: subscriptions, groupStateKnown: true)
    }
    @MainActor static func main() async {
        let nodes = [
            node("a", 1, group: 0xC001, subscriptions: [0xC001]),
            node("b", 2, group: 0xC001, subscriptions: [0xC001]),
            node("c", 3, group: 0xC001),
            node("p", 4, group: 0xC002, subscriptions: [0xC002]),
            node("d", 5, group: 0xC002, subscriptions: [0xC002]),
            node("outside", 6)
        ]
        let plan = LightsBatchDeletionPlan.make(nodes: nodes, selected: ["a","b","c","p","d"],
                                               allowBroadcast: false, proxyID: "p")
        expect(plan.tasks.map(\.destination) == [0xC001, 3, 0xC002], "unsubscribed member falls back; whole Proxy task last")
        expect(plan.tasks.map(\.repetitions) == [2,1,2], "group and unicast repetitions")
        let unsafe = nodes + [node("other", 7, subscriptions: [0xC001])]
        let limited = LightsBatchDeletionPlan.make(nodes: unsafe, selected: ["a","b","c"], allowBroadcast: false, proxyID: nil)
        expect(limited.tasks.allSatisfy { $0.repetitions == 1 }, "outside subscriber forbids group deletion")
        let unknown = LightsBatchDeletionPlan.Node(id: "unknown", address: 8, vendorAddress: 8,
            businessGroup: 0xC005, subscriptions: [], groupStateKnown: false)
        let uncertain = LightsBatchDeletionPlan.make(nodes: nodes + [unknown], selected: ["a","b","c"],
            allowBroadcast: false, proxyID: "unknown")
        expect(uncertain.tasks.allSatisfy { $0.isUnicast }, "unknown outside subscriber forbids multicast and protects Proxy")
        let all = LightsBatchDeletionPlan.make(nodes: nodes, selected: Set(nodes.map(\.id)), allowBroadcast: true, proxyID: "p")
        expect(all.tasks.count == 1 && all.tasks[0].destination == 0xFFFF, "explicit full coverage broadcasts")
        let hidden = LightsBatchDeletionPlan.make(nodes: nodes, selected: ["a","b","c","p","d"], allowBroadcast: true, proxyID: "p")
        expect(!hidden.tasks.contains { $0.destination == 0xFFFF }, "hidden receiver prevents broadcast")
        let secondary = LightsBatchDeletionPlan.Node(id: "secondary", address: 10, vendorAddress: 11,
            businessGroup: nil, subscriptions: [], groupStateKnown: true)
        let multiElement = LightsBatchDeletionPlan.make(nodes: [node("a",1), secondary], selected: ["a","secondary"],
            allowBroadcast: true, proxyID: nil)
        expect(multiElement.tasks.map(\.destination) == [1,11], "All Nodes must not assume a secondary-only Vendor receives it")
        let partial = LightsBatchDeletionPlan.make(nodes: nodes, selected: ["a"], allowBroadcast: false, proxyID: nil)
        expect(partial.tasks.map(\.destination) == [1], "partial business group stays unicast")
        let overlapNodes = [
            node("a",1,group:0xC001,subscriptions:[0xC001]),
            node("p",2,group:0xC001,subscriptions:[0xC001,0xC002]),
            node("b",3,group:0xC002,subscriptions:[0xC002])
        ]
        let overlap = LightsBatchDeletionPlan.make(nodes: overlapNodes, selected: ["a","p","b"], allowBroadcast: false, proxyID: "p")
        expect(overlap.tasks.last?.members.contains("p") == true &&
               !overlap.tasks.dropLast().contains { $0.members.contains("p") }, "overlap never hits Proxy early")
        let unsupported = LightsBatchDeletionPlan.make(nodes: [node("x",9,capable:false)], selected:["x"], allowBroadcast:true,proxyID:nil)
        expect(unsupported.tasks.isEmpty && unsupported.unsendable == ["x"], "unsupported is failure, never SIG reset")

        var now: TimeInterval = 0
        var submitted: [(UInt16,TimeInterval)] = []
        var receipts = Set<String>()
        let executor = LightsBatchDeletionExecutor(now: { now }, sleep: { now += $0 })
        let result = await executor.run(plan: plan, isCurrent: { true }, send: { task in
            now += 0.1 // CoreBluetooth backpressure; gaps must start AFTER this.
            submitted.append((task.destination, now))
            if task.destination == 3 {
                executor.receive(source: 3, parameters: Data([0x48,0x04,0]))
                executor.receive(source: 99, parameters: Data([0x48,0x02,0]))
                executor.receive(source: 3, parameters: Data([0x48,0x02,0]))
            }
            return true
        }, record: { ids, _ in receipts.formUnion(ids); return ids })
        expect(submitted.map { $0.0 } == [0xC001,0xC001,3,0xC002,0xC002], "tasks cannot interleave")
        let expected: [Double] = [0.1,1.2,2.3,2.6,3.7]
        expect(zip(submitted.map { $0.1 },expected).allSatisfy { abs($0-$1)<0.0001 }, "gaps measured from actual submission")
        expect(abs(now-6.7)<0.001, "last group final barrier is 3 seconds, not 4")
        expect(result.succeeded == ["a","b","c","p","d"] && result.failed.isEmpty && receipts == result.succeeded, "only receipted success")

        now = 0
        let single = LightsBatchDeletionPlan.make(nodes: [node("a",1),node("b",2)], selected:["a","b"], allowBroadcast:false,proxyID:nil)
        var count = 0
        let timeout = await executor.run(plan: single, isCurrent: { true }, send: { task in
            count += 1
            if task.destination == 1 { executor.receive(source: 1, parameters: Data([0x48,0x02,1])) }
            return true
        }, record: { ids, _ in ids })
        expect(count == 2 && timeout.failed == ["a","b"], "negative ACK and timeout fail; no retransmission")
        expect(now >= 10.2, "ACK deadline can extend beyond final 3 seconds")
        now = 0; count = 0
        let interrupted = await executor.run(plan: all, isCurrent: { count < 1 }, send: { _ in count += 1; return true }, record: { ids,_ in ids })
        expect(count == 1 && interrupted.succeeded.isEmpty && now >= 3, "partial broadcast remains uncertain and still waits")
        now = 0
        _ = await executor.run(plan: all, isCurrent: { false }, send: { _ in preconditionFailure("no send") }, record: { ids,_ in ids })
        expect(now == 0, "no packets means no artificial final delay")
        print("LightsBatchDeletionTests passed")
    }
}
