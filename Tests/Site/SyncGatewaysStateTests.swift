import Foundation

@main
struct SyncGatewaysStateTests {

    static func main() {
        testSectionProjectionAndSingleSyncExclusion()
        testFailureRetryAndSignalTransitions()
        testSyncedRSSIAndCloudStateAreOrthogonal()
        testUnavailableTargetCannotSync()
        print("SyncGatewaysStateTests passed")
    }

    private static func testSectionProjectionAndSingleSyncExclusion() {
        var state = SyncGatewaysState(targets: makeFourTargets())
        require(state.nearbyItems.isEmpty, "No advertisement means Nearby starts empty")
        require(state.otherItems.map(\.id) == ["a", "b", "c", "d"], "No-signal targets must retain remote order in Other")
        require(state.progress == .init(updated: 0, total: 4), "Progress total must contain only task targets")

        state.receiveAdvertisement(id: "b", rssi: -45)
        state.receiveAdvertisement(id: "a", rssi: -60)
        require(state.nearbyItems.map(\.id) == ["a", "b"], "Nearby must use remote order, not discovery order")

        let attempt = state.beginSync(id: "a")
        require(attempt != nil, "A nearby pending Gateway must start syncing")
        require(state.action(for: "a") == .syncing, "Current Gateway must expose Syncing")
        require(state.action(for: "b") == .disabledSync, "Only one Gateway may sync at a time")
        require(state.beginSync(id: "b") == nil, "A second attempt must be rejected")

        state.finishSync(id: "a", attemptID: attempt!, result: .success)
        require(state.progress == .init(updated: 1, total: 4), "Successful Device sync must advance progress immediately")
        require(state.nearbyItems.map(\.id) == ["b"], "Synced Gateway must leave Nearby")
        require(state.otherItems.map(\.id) == ["c", "d", "a"], "Pending Other Gateways must sort before synced Gateways")
        require(state.action(for: "a") == .synced, "Successful Gateway must remain Synced independently of cloud")
    }

    private static func testFailureRetryAndSignalTransitions() {
        var state = SyncGatewaysState(targets: makeFourTargets())
        state.receiveAdvertisement(id: "b", rssi: -50)
        let attempt = state.beginSync(id: "b")!
        state.finishSync(id: "b", attemptID: attempt, result: .failure)

        require(state.action(for: "b") == .retry, "Failed nearby Gateway must expose Retry")
        state.advanceActiveScan(by: 14.9)
        require(state.nearbyItems.map(\.id) == ["b"], "Signal must remain nearby before 15 active seconds")
        state.advanceActiveScan(by: 0.1)
        require(state.nearbyItems.isEmpty, "Failed Gateway must move to Other after 15 active seconds")
        require(state.action(for: "b") == .unavailable, "No-signal Gateway must not expose Retry")

        state.receiveAdvertisement(id: "b", rssi: -42)
        require(state.nearbyItems.map(\.id) == ["b"], "A new advertisement must move failed Gateway back to Nearby")
        require(state.action(for: "b") == .retry, "Rediscovered failed Gateway must expose Retry again")

        let retry = state.beginSync(id: "b")!
        state.finishSync(id: "b", attemptID: UUID(), result: .success)
        require(state.action(for: "b") == .syncing, "A stale attempt result must not settle the active Retry")
        state.advanceActiveScan(by: 100)
        require(state.nearbyItems.map(\.id) == ["b"], "Syncing Gateway must stay fixed in Nearby while scan is paused")
        state.finishSync(id: "b", attemptID: retry, result: .failure)
    }

    private static func testSyncedRSSIAndCloudStateAreOrthogonal() {
        var state = SyncGatewaysState(targets: makeFourTargets())
        state.receiveAdvertisement(id: "a", rssi: -60)
        let attempt = state.beginSync(id: "a")!
        state.finishSync(id: "a", attemptID: attempt, result: .success)
        state.setCloudState(id: "a", state: .failed)

        require(state.progress == .init(updated: 1, total: 4), "Cloud failure must not reduce Device progress")
        require(state.action(for: "a") == .synced, "Cloud failure must not turn Synced into Retry")
        require(state.item(id: "a")?.cloud == .failed, "Cloud state must still report its own failure")

        state.receiveAdvertisement(id: "a", rssi: -35)
        require(state.item(id: "a")?.rssi == -35, "Synced Gateway RSSI must continue updating")
        require(state.otherItems.last?.id == "a", "Synced Gateway must remain in Other even with signal")
        state.advanceActiveScan(by: 15)
        require(state.item(id: "a")?.isNoSignal == true, "Synced Gateway must become No signal after timeout")
        require(state.action(for: "a") == .synced, "Signal timeout must not clear Synced state")

        for id in ["b", "c", "d"] {
            state.receiveAdvertisement(id: id, rssi: -40)
            let next = state.beginSync(id: id)!
            state.finishSync(id: id, attemptID: next, result: .success)
        }
        require(state.progress == .init(updated: 4, total: 4), "All Device successes must complete progress")
        require(state.attentionCount == 0, "All synced Gateways must hide the attention message")
    }

    private static func testUnavailableTargetCannotSync() {
        var targets = makeFourTargets()
        targets.append(.init(
            id: "e",
            displayName: nil,
            remoteOrder: 4,
            initialOffsetMinutes: nil,
            isSyncable: false
        ))
        var state = SyncGatewaysState(targets: targets)
        state.receiveAdvertisement(id: "e", rssi: -30)

        require(state.beginSync(id: "e") == nil, "Missing local binding must never start an attempt")
        require(state.action(for: "e") == .unavailable, "Missing local binding must render unavailable")
    }

    private static func makeFourTargets() -> [SyncGatewayTargetDescriptor] {
        ["a", "b", "c", "d"].enumerated().map { index, id in
            SyncGatewayTargetDescriptor(
                id: id,
                displayName: "Gateway \(id.uppercased())",
                remoteOrder: index,
                initialOffsetMinutes: 0,
                isSyncable: true
            )
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
