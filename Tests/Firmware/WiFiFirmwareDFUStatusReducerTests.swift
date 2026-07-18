import Foundation

@main
struct WiFiFirmwareDFUStatusReducerTests {
    static func snapshot(
        otaID: UInt64 = 7,
        stage: WiFiFirmwareDFUStatusStage,
        percent: Int,
        firmwareID: String? = "0.4.0",
        moduleVersion: String? = nil,
        failure: WiFiFirmwareDFUFailureCategory = .none,
        codeIdentifier: String = "none"
    ) -> WiFiFirmwareDFUStatusSnapshot {
        .init(
            otaID: otaID,
            stage: stage,
            percent: percent,
            failureCategory: failure,
            codeIdentifier: codeIdentifier,
            firmwareID: firmwareID,
            moduleVersion: moduleVersion
        )
    }

    static func main() {
        testIdentityAndOrdering()
        testCancellationAndTerminalLock()
        testSkippedStagesAndRestore()
        testInvalidIdentity()
        testPendingStartRecoveryIdentity()
        testPendingStartRecoveryQueriesOnce()
        testTimingConstants()
        testStateMapping()
        testSessionStoreUsesV19KeyAndRemovesLegacyData()
        print("WiFiFirmwareDFUStatusReducerTests passed")
    }

    private static func testIdentityAndOrdering() {
        var reducer = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(reducer.reduce(snapshot(stage: .preparing, percent: 0), source: .event) == .accepted)
        precondition(reducer.boundOTAID == 7)
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 40), source: .event) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 40), source: .event) == .ignored(.duplicate))
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 35), source: .event) == .ignored(.downloadProgressRegressed))
        precondition(reducer.reduce(snapshot(stage: .preparing, percent: 0), source: .event) == .ignored(.stageRegressed))
        precondition(reducer.reduce(snapshot(otaID: 8, stage: .downloading, percent: 50), source: .event) == .ignored(.identityMismatch))
        precondition(reducer.reduce(snapshot(stage: .downloading, percent: 50, firmwareID: "0.5.0"), source: .event) == .ignored(.identityMismatch))
    }

    private static func testCancellationAndTerminalLock() {
        var reducer = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(reducer.reduce(snapshot(stage: .verifying, percent: 100), source: .event) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .cancelled, percent: 100), source: .event) == .ignored(.cancelledRequiresQuery))
        precondition(reducer.reduce(snapshot(stage: .cancelled, percent: 100), source: .query) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .success, percent: 100), source: .query) == .ignored(.terminalLocked))

        var firstTerminal = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(firstTerminal.reduce(snapshot(stage: .cancelled, percent: 15), source: .event) == .accepted)
    }

    private static func testSkippedStagesAndRestore() {
        var reducer = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(reducer.reduce(snapshot(stage: .preparing, percent: 0), source: .event) == .accepted)
        precondition(reducer.reduce(snapshot(stage: .versionCheck, percent: 100), source: .event) == .accepted)

        var restored = WiFiFirmwareDFUStatusReducer(
            targetFirmwareID: "0.4.0",
            boundOTAID: reducer.boundOTAID,
            lastAcceptedStatus: reducer.lastAcceptedStatus
        )
        precondition(restored.reduce(snapshot(stage: .recovering, percent: 100), source: .query) == .ignored(.stageRegressed))
        precondition(restored.reduce(snapshot(stage: .success, percent: 100, moduleVersion: "0.4.0"), source: .query) == .accepted)
    }

    private static func testInvalidIdentity() {
        var idle = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(idle.reduce(snapshot(otaID: 0, stage: .idle, percent: 0, firmwareID: nil), source: .query) == .ignored(.invalidIdle))

        var zeroOTAID = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(zeroOTAID.reduce(snapshot(otaID: 0, stage: .downloading, percent: 1), source: .query) == .ignored(.identityMismatch))

        var missingFirmware = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(missingFirmware.reduce(snapshot(stage: .downloading, percent: 1, firmwareID: nil), source: .query) == .ignored(.identityMismatch))
    }

    private static func testPendingStartRecoveryIdentity() {
        var recovery = WiFiFirmwareDFUStartRecovery(otaID: 7, firmwareID: "0.4.0")
        precondition(
            recovery.record(
                snapshot(otaID: 8, stage: .preparing, percent: 0),
                source: .event
            ) == false
        )
        precondition(
            recovery.record(
                snapshot(stage: .preparing, percent: 0, firmwareID: "0.5.0"),
                source: .event
            ) == false
        )
        precondition(
            recovery.record(
                snapshot(otaID: 0, stage: .idle, percent: 0, firmwareID: nil),
                source: .event
            ) == false
        )

        let matching = snapshot(stage: .preparing, percent: 0)
        precondition(recovery.record(matching, source: .event))
        precondition(recovery.nextAfterMissingRET() == .established(matching))
    }

    private static func testPendingStartRecoveryQueriesOnce() {
        var recovery = WiFiFirmwareDFUStartRecovery(otaID: 7, firmwareID: "0.4.0")
        precondition(recovery.nextAfterMissingRET() == .queryOnce)
        precondition(recovery.nextAfterMissingRET() == .unknown)

        var queryRecovery = WiFiFirmwareDFUStartRecovery(otaID: 7, firmwareID: "0.4.0")
        precondition(queryRecovery.nextAfterMissingRET() == .queryOnce)
        let matching = snapshot(stage: .downloading, percent: 18)
        precondition(queryRecovery.record(matching, source: .query))
        precondition(queryRecovery.nextAfterMissingRET() == .established(matching))
    }

    private static func testTimingConstants() {
        precondition(WiFiFirmwareDFUQueryTiming.statusTimeout == 3)
        precondition(WiFiFirmwareDFUQueryTiming.quietQueryInterval == 10)
        precondition(WiFiFirmwareDFUQueryTiming.unknownThreshold == 30)
        precondition(WiFiFirmwareDFUQueryTiming.unknownQueryInterval == 30)
    }

    private static func testStateMapping() {
        precondition(
            WiFiFirmwareDFUStateMapper.map(
                status: snapshot(stage: .preparing, percent: 0)
            ) == .init(kind: .downloading, percent: 0)
        )
        precondition(
            WiFiFirmwareDFUStateMapper.map(
                status: snapshot(stage: .cancelled, percent: 50)
            ) == .init(kind: .cancelled, percent: 50)
        )
        precondition(
            WiFiFirmwareDFUStateMapper.map(
                status: snapshot(stage: .failed, percent: 25, failure: .download)
            ) == .init(kind: .downloadFailed, percent: 25)
        )
        precondition(
            WiFiFirmwareDFUStateMapper.map(
                status: snapshot(stage: .failed, percent: 25, failure: .other)
            ) == .init(kind: .upgradeFailed, percent: 25)
        )
        precondition(
            WiFiFirmwareDFUStateMapper.map(
                status: snapshot(stage: .success, percent: 100, moduleVersion: "0.4.0")
            ) == .init(kind: .upgradeComplete, percent: 100)
        )
        precondition(
            WiFiFirmwareDFUStateMapper.map(
                status: snapshot(otaID: 0, stage: .idle, percent: 0, firmwareID: nil)
            ) == nil
        )
    }

    private static func testSessionStoreUsesV19KeyAndRemovesLegacyData() {
        let suiteName = "WiFiFirmwareDFUStatusReducerTests.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Unable to create test UserDefaults")
        }
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let networkUUID = UUID()
        let nodeAddress: UInt16 = 0x0123
        let legacyKey = "wifi_firmware_dfu_session.\(networkUUID.uuidString).\(nodeAddress)"
        let v19Key = "wifi_firmware_dfu_session.v19.\(networkUUID.uuidString).\(nodeAddress)"
        defaults.set(Data([0x01]), forKey: legacyKey)

        let status = snapshot(stage: .downloading, percent: 20)
        let session = WiFiFirmwareDFUSession(
            targetFirmwareID: "0.4.0",
            otaID: 7,
            lastStatus: status,
            lastState: .init(kind: .downloading, percent: 20),
            terminalConsumed: false,
            requiresAuthoritativeQuery: true
        )
        let store = WiFiFirmwareDFUSessionStore(defaults: defaults)
        store.save(session, networkUUID: networkUUID, nodeAddress: nodeAddress)
        precondition(defaults.data(forKey: v19Key) != nil)
        precondition(store.load(networkUUID: networkUUID, nodeAddress: nodeAddress) == session)
        precondition(defaults.object(forKey: legacyKey) == nil)

        store.remove(networkUUID: networkUUID, nodeAddress: nodeAddress)
        precondition(defaults.object(forKey: v19Key) == nil)
    }
}
