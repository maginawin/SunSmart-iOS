import Foundation

@main
struct SyncGatewaysCloudBridgeTests {

    static func main() {
        testBatchDeduplicatesAndRefreshesOnce()
        testNewExplicitBatchCanRefreshAgain()
        testDeviceSuccessAdvancesGenerationButRetryDoesNot()
        testDirtyTimeOverrideSelection()
        print("SyncGatewaysCloudBridgeTests passed")
    }

    private static func testBatchDeduplicatesAndRefreshesOnce() {
        var batch = SyncGatewaysCloudBatchState()
        require(batch.register(gatewayID: "a"), "First Gateway must enter the batch")
        require(!batch.register(gatewayID: "a"), "Duplicate Gateway must not increase pending work")
        require(batch.register(gatewayID: "b"), "Second Gateway must enter the batch")
        require(!batch.settle(gatewayID: "a"), "Partial settlement must not refresh Site")
        require(batch.settle(gatewayID: "b"), "Last terminal Gateway must request one refresh")
        require(!batch.settle(gatewayID: "b"), "Duplicate terminal callback must not refresh again")
        require(!batch.register(gatewayID: "c"), "Closed page batch must reject later registration until explicitly reset")
    }

    private static func testNewExplicitBatchCanRefreshAgain() {
        var batch = SyncGatewaysCloudBatchState()
        require(batch.register(gatewayID: "a"), "Expected first batch registration")
        require(batch.settle(gatewayID: "a"), "Expected first batch refresh")
        require(batch.resetForNextBatch(), "A terminal batch must allow explicit reset")
        require(batch.register(gatewayID: "a"), "New batch may register the same Gateway")
        require(batch.settle(gatewayID: "a"), "New batch may refresh once independently")
    }

    private static func testDeviceSuccessAdvancesGenerationButRetryDoesNot() {
        require(
            SyncGatewaysCloudEnqueuePolicy.generation(
                for: .deviceSuccess,
                now: 100,
                current: 100,
                uploaded: 100
            ) == 101,
            "A new BLE-confirmed mutation must advance generation"
        )
        require(
            SyncGatewaysCloudEnqueuePolicy.generation(
                for: .dirtyRetry,
                now: 999,
                current: 101,
                uploaded: 100
            ) == 101,
            "Retrying an existing dirty mutation must reuse its generation"
        )
    }

    private static func testDirtyTimeOverrideSelection() {
        let overrides = SyncGatewaysDirtyTimeOverridePolicy.capture(
            targetOffsetMinutes: 480,
            candidates: [
                .init(id: " AA:BB ", isCloudDirty: true, localTimestamp: 10, localOffsetMinutes: 480, remoteOffsetMinutes: 0),
                .init(id: "clean", isCloudDirty: false, localTimestamp: 11, localOffsetMinutes: 480, remoteOffsetMinutes: 0),
                .init(id: "zero-time", isCloudDirty: true, localTimestamp: 0, localOffsetMinutes: 480, remoteOffsetMinutes: 0),
                .init(id: "wrong-local", isCloudDirty: true, localTimestamp: 12, localOffsetMinutes: 0, remoteOffsetMinutes: 0),
                .init(id: "converged", isCloudDirty: true, localTimestamp: 13, localOffsetMinutes: 480, remoteOffsetMinutes: 480),
                .init(id: nil, isCloudDirty: true, localTimestamp: 14, localOffsetMinutes: 480, remoteOffsetMinutes: 0)
            ]
        )

        require(overrides == ["aa:bb": .init(timestamp: 10, offsetMinutes: 480)], "Only stale-cloud dirty local target values may survive Site import")
        require(
            SyncGatewaysDirtyTimeOverridePolicy.capture(
                targetOffsetMinutes: 0,
                candidates: [
                    .init(id: "aa:bb", isCloudDirty: true, localTimestamp: 10, localOffsetMinutes: 480, remoteOffsetMinutes: 0)
                ]
            ).isEmpty,
            "A changed Site target must invalidate the old local override"
        )
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
