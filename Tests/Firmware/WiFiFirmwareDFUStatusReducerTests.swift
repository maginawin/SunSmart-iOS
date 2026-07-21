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
        testSessionCancelStateMigrationAndPersistence()
        testPageRecoveryRequiresAuthoritativeQuery()
        testAuthoritativeRecoveryPolicy()
        testCancelAuthoritativeRecoveryPolicy()
        testInitialLoadGateWaitsForBothRequirements()
        testInitialLoadGateRejectsDuplicateAndStaleCompletions()
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

        var cancellation = WiFiFirmwareDFUStatusReducer(targetFirmwareID: "0.4.0")
        precondition(cancellation.reduce(snapshot(stage: .verifying, percent: 100), source: .event) == .accepted)
        precondition(cancellation.reduce(snapshot(stage: .cancelled, percent: 100), source: .cancellation) == .accepted)
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

    private static func testSessionCancelStateMigrationAndPersistence() {
        struct LegacySession: Codable {
            let targetFirmwareID: String
            let otaID: UInt64?
            let lastStatus: WiFiFirmwareDFUStatusSnapshot?
            let lastState: WiFiFirmwareUpdatingState?
            let terminalConsumed: Bool
            let requiresAuthoritativeQuery: Bool
        }

        let legacy = LegacySession(
            targetFirmwareID: "0.4.0",
            otaID: 7,
            lastStatus: snapshot(stage: .downloading, percent: 20),
            lastState: .init(kind: .downloading, percent: 20),
            terminalConsumed: false,
            requiresAuthoritativeQuery: true
        )
        let legacyData = try! JSONEncoder().encode(legacy)
        let migrated = try! JSONDecoder().decode(
            WiFiFirmwareDFUSession.self,
            from: legacyData
        )
        precondition(migrated.cancelState == .init())

        let unknown = WiFiFirmwareDFUSession(
            targetFirmwareID: "0.4.0",
            otaID: 7,
            lastStatus: snapshot(stage: .verifying, percent: 100),
            lastState: .init(kind: .updating, percent: 100),
            terminalConsumed: false,
            requiresAuthoritativeQuery: true,
            cancelState: .init(
                phase: .unknown,
                sawVerifyingWhilePending: true,
                recoveryQueryCount: 3
            )
        )
        let encoded = try! JSONEncoder().encode(unknown)
        precondition(
            try! JSONDecoder().decode(WiFiFirmwareDFUSession.self, from: encoded) == unknown
        )
        precondition(unknown.isStatusQueryEligible)
    }

    private static func testPageRecoveryRequiresAuthoritativeQuery() {
        var nonterminal = session(
            status: snapshot(stage: .downloading, percent: 20),
            state: .init(kind: .downloading, percent: 20)
        )
        nonterminal.prepareForPageRecovery()
        precondition(nonterminal.requiresAuthoritativeQuery)
        precondition(nonterminal.isStatusQueryEligible)

        var failed = session(
            status: snapshot(
                stage: .failed,
                percent: 25,
                failure: .other,
                codeIdentifier: "internalError:0x0C"
            ),
            state: .init(kind: .upgradeFailed, percent: 25)
        )
        precondition(!failed.isStatusQueryEligible)
        failed.prepareForPageRecovery()
        precondition(failed.requiresAuthoritativeQuery)
        precondition(failed.isStatusQueryEligible)

        var success = session(
            status: snapshot(
                stage: .success,
                percent: 100,
                moduleVersion: "0.4.0"
            ),
            state: .init(kind: .upgradeComplete, percent: 100)
        )
        precondition(!success.isStatusQueryEligible)
        success.prepareForPageRecovery()
        precondition(success.requiresAuthoritativeQuery)
        precondition(success.isStatusQueryEligible)

        var consumed = session(
            status: snapshot(
                stage: .success,
                percent: 100,
                moduleVersion: "0.4.0"
            ),
            state: .init(kind: .upgradeComplete, percent: 100),
            terminalConsumed: true
        )
        consumed.prepareForPageRecovery()
        precondition(!consumed.requiresAuthoritativeQuery)
        precondition(!consumed.isStatusQueryEligible)
    }

    private static func testAuthoritativeRecoveryPolicy() {
        let active = session(
            status: snapshot(stage: .downloading, percent: 20),
            state: .init(kind: .downloading, percent: 20),
            requiresAuthoritativeQuery: true
        )
        let terminal = session(
            status: snapshot(
                stage: .failed,
                percent: 25,
                failure: .other,
                codeIdentifier: "internalError:0x0C"
            ),
            state: .init(kind: .upgradeFailed, percent: 25),
            requiresAuthoritativeQuery: true
        )

        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: active,
                candidate: snapshot(stage: .verifying, percent: 100)
            ) == .acceptStatus
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: terminal,
                candidate: snapshot(stage: .success, percent: 100, moduleVersion: "0.4.0")
            ) == .acceptStatus
        )

        let idle = snapshot(
            otaID: 0,
            stage: .idle,
            percent: 0,
            firmwareID: nil
        )
        let otherOTA = snapshot(otaID: 8, stage: .downloading, percent: 10)
        let otherFirmware = snapshot(
            stage: .downloading,
            percent: 10,
            firmwareID: "0.5.0"
        )
        for candidate in [idle, otherOTA, otherFirmware] {
            precondition(
                WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                    session: terminal,
                    candidate: candidate
                ) == .clearStaleTerminal
            )
            precondition(
                WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                    session: active,
                    candidate: candidate
                ) == .retainSession
            )
        }

        let consumed = session(
            status: snapshot(
                stage: .success,
                percent: 100,
                moduleVersion: "0.4.0"
            ),
            state: .init(kind: .upgradeComplete, percent: 100),
            terminalConsumed: true,
            requiresAuthoritativeQuery: true
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: consumed,
                candidate: snapshot(stage: .success, percent: 100, moduleVersion: "0.4.0")
            ) == .retainSession
        )
    }

    private static func testCancelAuthoritativeRecoveryPolicy() {
        let idle = snapshot(
            otaID: 0,
            stage: .idle,
            percent: 0,
            firmwareID: nil
        )
        let otherOTA = snapshot(otaID: 8, stage: .downloading, percent: 10)

        let pending = session(
            status: snapshot(stage: .downloading, percent: 20),
            state: .init(kind: .downloading, percent: 20),
            requiresAuthoritativeQuery: true,
            cancelState: .init(phase: .pending)
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: pending,
                candidate: snapshot(stage: .verifying, percent: 100)
            ) == .acceptStatus
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: pending,
                candidate: idle
            ) == .retainSession
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: pending,
                candidate: otherOTA
            ) == .retainSession
        )

        let unknown = session(
            status: snapshot(stage: .verifying, percent: 100),
            state: .init(kind: .updating, percent: 100),
            requiresAuthoritativeQuery: true,
            cancelState: .init(phase: .unknown, recoveryQueryCount: 3)
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: unknown,
                candidate: idle
            ) == .clearStaleTerminal
        )
        precondition(
            WiFiFirmwareDFUAuthoritativeRecoveryPolicy.decision(
                session: unknown,
                candidate: otherOTA
            ) == .retainSession
        )
    }

    private static func testInitialLoadGateWaitsForBothRequirements() {
        var currentFirst = WiFiFirmwareInitialLoadGate()
        let currentFirstGeneration = currentFirst.begin()
        precondition(
            !currentFirst.complete(
                .currentVersion,
                generation: currentFirstGeneration
            )
        )
        precondition(
            currentFirst.complete(
                .cloudFirmware,
                generation: currentFirstGeneration
            )
        )

        var cloudFirst = WiFiFirmwareInitialLoadGate()
        let cloudFirstGeneration = cloudFirst.begin()
        precondition(
            !cloudFirst.complete(
                .cloudFirmware,
                generation: cloudFirstGeneration
            )
        )
        precondition(
            cloudFirst.complete(
                .currentVersion,
                generation: cloudFirstGeneration
            )
        )
    }

    private static func testInitialLoadGateRejectsDuplicateAndStaleCompletions() {
        var gate = WiFiFirmwareInitialLoadGate()
        let staleGeneration = gate.begin()
        precondition(
            !gate.complete(.currentVersion, generation: staleGeneration)
        )

        let activeGeneration = gate.begin()
        precondition(
            !gate.complete(.cloudFirmware, generation: staleGeneration)
        )
        precondition(
            !gate.complete(.currentVersion, generation: activeGeneration)
        )
        precondition(
            gate.complete(.cloudFirmware, generation: activeGeneration)
        )
        precondition(
            !gate.complete(.cloudFirmware, generation: activeGeneration)
        )

        let cancelledGeneration = gate.begin()
        gate.cancel()
        precondition(
            !gate.complete(.currentVersion, generation: cancelledGeneration)
        )
        precondition(
            !gate.complete(.cloudFirmware, generation: cancelledGeneration)
        )
    }

    private static func session(
        status: WiFiFirmwareDFUStatusSnapshot,
        state: WiFiFirmwareUpdatingState,
        terminalConsumed: Bool = false,
        requiresAuthoritativeQuery: Bool = false,
        cancelState: WiFiFirmwareDFUCancelState = .init()
    ) -> WiFiFirmwareDFUSession {
        WiFiFirmwareDFUSession(
            targetFirmwareID: "0.4.0",
            otaID: 7,
            lastStatus: status,
            lastState: state,
            terminalConsumed: terminalConsumed,
            requiresAuthoritativeQuery: requiresAuthoritativeQuery,
            cancelState: cancelState
        )
    }
}
