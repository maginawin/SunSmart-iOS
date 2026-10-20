import Foundation

@main enum HDBLightingZoneExecutorTests {
    static func main() {
        let lane = SyncSessionTransportLane()
        let uuid = UUID()
        let target = HDBModelTarget(elementAddress: 1, modelIdentifier: 0x1000, companyIdentifier: nil)
        func op(_ zone: Int, _ reset: Bool, _ node: UUID = uuid) -> HDBZoneOperation {
            let plan = HDBZonePlan(nodeUuid: node, nodeAddress: 1, zones: [.init(zoneId: zone, groupAddress: UInt16(0xC000 + zone))], sensorGroupId: nil, targets: [target], sensorTargets: [], broadcastTargets: [], broadcastId: 0xFEFD)
            return .init(plan: plan, stage: reset ? .reset : .add,
                subscriptions: [.init(target: target, command: reset ? .deleteAll : .add, address: reset ? 0 : UInt16(0xC000 + zone))], isLast: !reset)
        }
        var acknowledgements = HDBZoneAcknowledgements(operation: op(1, true))
        precondition(!acknowledgements.successful)
        acknowledgements.receive(target: target, nodeAddress: 1, groupAddress: 0, successful: true)
        precondition(acknowledgements.successful)
        acknowledgements.receive(target: target, nodeAddress: 1, groupAddress: 0xC002, successful: true)
        precondition(!acknowledgements.successful)
        var callbacks: [(HDBZoneOperation, (HDBZoneReceipt) -> Void)] = []
        var receipts: [HDBZoneReceipt] = []
        var stopped = 0, completed = 0
        let executor = HDBLightingZoneExecutor(lane: lane, send: { callbacks.append(($0, $1)) }, stop: { stopped += 1; $0() }, isCurrent: { true }, persist: { receipts.append($0) })
        let removal = op(1, true), addition = op(9, false), other = op(2, false, UUID())
        executor.start([removal, addition, other]) { completed += 1 }
        callbacks[0].1(.init(operation: removal, successful: false))
        precondition(callbacks.count == 2 && callbacks[1].0 == other)
        callbacks[0].1(.init(operation: removal, successful: true))
        precondition(receipts.count == 1)
        callbacks[1].1(.init(operation: other, successful: true))
        precondition(completed == 1 && receipts.count == 2)
        executor.start([addition]) { completed += 1 }
        let late = callbacks.last!
        let waiter = HDBLightingZoneExecutor(lane: lane, send: { _,_ in fatalError("waiting owner sent") }, stop: { _ in fatalError("waiting owner stopped another transport") }, isCurrent: { true }, persist: { _ in })
        waiter.start([addition]) {}
        waiter.cancel()
        executor.cancel()
        late.1(.init(operation: addition, successful: true))
        precondition(receipts.count == 2 && stopped == 1)
        let failing = HDBLightingZoneExecutor(lane: lane, send: { op, done in done(.init(operation: op, successful: true)) }, stop: { $0() }, isCurrent: { true }, persist: { _ in throw HDBConfigurationError.persistenceFailed })
        failing.start([addition]) {}
        precondition(failing.error != nil && !failing.isRunning)
        print("PASS: failed stage blocks the remaining device stages, other nodes proceed, cancellation/late receipts/lane ownership/persistence failure")
    }
}
