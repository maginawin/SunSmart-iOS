import Foundation

@main
struct SiteEntryTimeZoneSyncCoordinatorTests {

    @MainActor
    static func main() async {
        await requireSingleConsumption()
        await requireGatewayOnlyWaitsWithoutMutatingStore()
        requireVisitorRemotePersistsSilently()
        requireVisitorPersistenceFailureKeepsLocalState()
        await requireFastSuccessWaitsMinimumDuration()
        await requireSlowSuccessPublishesAfterCompletion()
        await requireTimeoutWinsRaceAndLateSuccessKeepsPending()
        await requireCallerCancellationReturnsImmediately()
        await requireRemotePersistenceDoesNotUpload()
        await requireLocalUploadSuccessClearsOnlyTimezonePending()
        await requireLocalUploadFailureKeepsPending()
        print("SiteEntryTimeZoneSyncCoordinatorTests passed")
    }

    @MainActor
    private static func requireGatewayOnlyWaitsWithoutMutatingStore() async {
        let store = FakeStore(state: localState(timezone: singapore))
        let coordinator = makeCoordinator(
            store: store,
            minimum: 60_000_000,
            timeout: 500_000_000
        )
        let start = Date()
        let result = await coordinator.run(.showGatewayStatus(
            timezone: singapore,
            gateway: .pending(1)
        ))

        require(Date().timeIntervalSince(start) >= 0.05, "Gateway-only status must keep the minimum display duration")
        require(result.site == .alreadyInSync, "Gateway-only status must report Site already in sync")
        require(result.gateway == .pending(1), "Gateway-only status must preserve the pending count")
        require(store.persistCallCount == 0, "Gateway-only status must not persist")
        require(store.submitCallCount == 0, "Gateway-only status must not upload")
    }

    @MainActor
    private static func requireVisitorRemotePersistsSilently() {
        let original = localState(
            timezone: singapore,
            lastUpdate: 200,
            pending: SitePropsPendingState(fields: [.siteName, .timezone], timestamp: 200)
        )
        let remote = SitePropsLocalState(
            values: SitePropsValues(siteName: "Cloud Site", imageId: 9, timezone: utc),
            lastUpdate: 100,
            lastUploadCloudTimestamp: 100,
            pending: SitePropsPendingState(fields: [], timestamp: nil)
        )
        let store = FakeStore(state: original)
        let coordinator = makeCoordinator(store: store)

        require(
            coordinator.applySilent(.useVisitorRemote(state: remote)),
            "Visitor cloud state must persist silently"
        )
        require(store.state == remote, "Visitor must adopt complete cloud Site props and timestamp")
        require(store.persistCallCount == 1, "Visitor silent flow must persist exactly once")
        require(store.submitCallCount == 0, "Visitor silent flow must never upload")
        require(
            !coordinator.applySilent(.noAction),
            "Only the Visitor remote decision may use the silent path"
        )
        require(store.persistCallCount == 1, "Rejected silent decisions must not persist")
    }

    @MainActor
    private static func requireVisitorPersistenceFailureKeepsLocalState() {
        let original = localState(timezone: singapore, lastUpdate: 200)
        let remote = localState(timezone: utc, lastUpdate: 100)
        let store = FakeStore(state: original)
        store.persistSucceeds = false
        let coordinator = makeCoordinator(store: store)

        require(
            !coordinator.applySilent(.useVisitorRemote(state: remote)),
            "Visitor silent persistence failure must be observable"
        )
        require(store.state == original, "Failed Visitor persistence must retain the App state")
        require(store.persistCallCount == 1, "Visitor persistence must be attempted once")
        require(store.submitCallCount == 0, "Failed Visitor persistence must not upload")
    }

    private static let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!
    private static let utc = SiteTimeZoneValue(
        ianaId: "Etc/UTC",
        rawUTCOffset: "+00:00"
    )!

    @MainActor
    private static func requireSingleConsumption() async {
        let store = FakeStore(state: localState(timezone: singapore))
        let coordinator = makeCoordinator(store: store)
        let local = localSnapshot(from: store.state)
        let remote = remoteSnapshot(timezone: utc, timestamp: 101)

        let first = coordinator.prepare(local: local, remote: remote, now: 200)
        let second = coordinator.prepare(local: local, remote: remote, now: 200)

        require(coordinator.hasConsumedEntryResponse, "The first successful response must be consumed")
        require(isRemote(first), "The first response must be evaluated")
        require(second == .noAction, "Later refreshes must not repeat entry sync")
    }

    @MainActor
    private static func requireFastSuccessWaitsMinimumDuration() async {
        let store = FakeStore(state: localState(timezone: singapore))
        let coordinator = makeCoordinator(store: store, minimum: 60_000_000, timeout: 500_000_000)
        let start = Date()
        let result = await coordinator.run(.useRemote(
            timezone: utc,
            remoteTimestamp: 101,
            gateway: .inSync
        ))

        require(Date().timeIntervalSince(start) >= 0.05, "Fast success must keep checking visible for the minimum duration")
        require(result.site == .updatedFromServer, "Expected a server update result")
    }

    @MainActor
    private static func requireSlowSuccessPublishesAfterCompletion() async {
        let store = FakeStore(state: localState(timezone: singapore))
        store.submitDelayNanoseconds = 90_000_000
        let coordinator = makeCoordinator(store: store, minimum: 20_000_000, timeout: 500_000_000)
        let decision = localDecision(timestamp: 101)
        let start = Date()
        let result = await coordinator.run(decision)

        require(Date().timeIntervalSince(start) >= 0.08, "Slow success must wait for the business operation")
        require(result.site == .updatedToServer, "Expected a successful upload result")
    }

    @MainActor
    private static func requireTimeoutWinsRaceAndLateSuccessKeepsPending() async {
        let store = FakeStore(state: localState(timezone: singapore))
        store.suspendSubmit = true
        let coordinator = makeCoordinator(store: store, minimum: 10_000_000, timeout: 50_000_000)
        let decision = localDecision(timestamp: 101)
        let result = await coordinator.run(decision)

        require(result.site == .failedToUpdateServer, "Thirty-second timeout must publish failure")
        require(store.state.pending.fields.contains(.timezone), "Timeout must retain timezone pending")

        store.resumeSuspendedSubmit(success: true)
        try? await Task.sleep(nanoseconds: 20_000_000)
        require(store.state.pending.fields.contains(.timezone), "Late success must not clear timezone pending")
    }

    @MainActor
    private static func requireCallerCancellationReturnsImmediately() async {
        let store = FakeStore(state: localState(timezone: singapore))
        store.suspendSubmit = true
        let coordinator = makeCoordinator(
            store: store,
            minimum: 10_000_000,
            timeout: 500_000_000
        )
        let task = Task {
            await coordinator.run(localDecision(timestamp: 101))
        }
        try? await Task.sleep(nanoseconds: 20_000_000)

        let start = Date()
        task.cancel()
        let result = await task.value

        require(Date().timeIntervalSince(start) < 0.1, "Caller cancellation must not wait for timeout")
        require(result.site == .failedToUpdateServer, "Cancelled work returns an ignored failure sentinel")
    }

    @MainActor
    private static func requireRemotePersistenceDoesNotUpload() async {
        let store = FakeStore(state: localState(timezone: singapore, lastUpdate: 200))
        let coordinator = makeCoordinator(store: store)
        let result = await coordinator.run(.useRemote(
            timezone: utc,
            remoteTimestamp: 100,
            gateway: .noGateways
        ))

        require(result.site == .updatedFromServer, "Expected remote persistence result")
        require(store.state.values.timezone == utc, "Expected the remote timezone locally")
        require(store.state.lastUpdate == 200, "An older remote version must not regress local lastUpdate")
        require(store.submitCallCount == 0, "Using server data must never upload")
    }

    @MainActor
    private static func requireLocalUploadSuccessClearsOnlyTimezonePending() async {
        let pending = SitePropsPendingState(fields: [.imageId], timestamp: 90)
        let store = FakeStore(state: localState(timezone: singapore, pending: pending))
        let coordinator = makeCoordinator(store: store)
        let result = await coordinator.run(localDecision(timestamp: 101))

        require(result.site == .updatedToServer, "Expected successful local upload")
        require(store.state.pending.fields == [.imageId], "Success must clear only timezone pending")
        require(store.state.pending.timestamp == 101, "Remaining pending fields keep the unified version")
    }

    @MainActor
    private static func requireLocalUploadFailureKeepsPending() async {
        let store = FakeStore(state: localState(timezone: singapore))
        store.submitSucceeds = false
        let coordinator = makeCoordinator(store: store)
        let result = await coordinator.run(localDecision(timestamp: 101))

        require(result.site == .failedToUpdateServer, "Expected upload failure")
        require(store.state.pending.fields.contains(.timezone), "Upload failure must retain timezone pending")
    }

    @MainActor
    private static func makeCoordinator(
        store: FakeStore,
        minimum: UInt64 = 1_000_000,
        timeout: UInt64 = 500_000_000
    ) -> SiteEntryTimeZoneSyncCoordinator {
        SiteEntryTimeZoneSyncCoordinator(
            store: store,
            minimumDisplayNanoseconds: minimum,
            timeoutNanoseconds: timeout
        )
    }

    private static func localDecision(timestamp: Int64) -> SiteEntryTimeZoneDecision {
        .useLocal(
            snapshot: SitePropsUpdateSnapshot(
                siteId: "site-id",
                fields: [.timezone],
                values: SitePropsValues(siteName: "Site", imageId: 1, timezone: singapore),
                timestamp: timestamp
            ),
            gateway: .inSync
        )
    }

    private static func localState(
        timezone: SiteTimeZoneValue,
        lastUpdate: Int64 = 100,
        pending: SitePropsPendingState = SitePropsPendingState(fields: [], timestamp: nil)
    ) -> SitePropsLocalState {
        SitePropsLocalState(
            values: SitePropsValues(siteName: "Site", imageId: 1, timezone: timezone),
            lastUpdate: lastUpdate,
            lastUploadCloudTimestamp: 80,
            pending: pending
        )
    }

    private static func localSnapshot(from state: SitePropsLocalState) -> SiteEntryTimeZoneLocalSnapshot {
        SiteEntryTimeZoneLocalSnapshot(
            siteId: "site-id",
            values: state.values,
            lastUpdate: state.lastUpdate,
            lastUploadCloudTimestamp: state.lastUploadCloudTimestamp,
            pending: state.pending
        )
    }

    private static func remoteSnapshot(
        timezone: SiteTimeZoneValue,
        timestamp: Int64
    ) -> SiteEntryTimeZoneRemoteSnapshot {
        SiteEntryTimeZoneRemoteSnapshot(
            role: .owner,
            values: SitePropsValues(siteName: "Cloud Site", imageId: 2, timezone: timezone),
            timestamp: timestamp,
            spaces: [],
            gateways: [.init(id: "gateway", offsetMinutes: timezone.offsetMinutes)]
        )
    }

    private static func isRemote(_ decision: SiteEntryTimeZoneDecision) -> Bool {
        if case .useRemote = decision { return true }
        return false
    }

    private static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }
}

@MainActor
private final class FakeStore: SiteEntryTimeZoneSyncStore {
    var state: SitePropsLocalState
    var persistSucceeds = true
    var submitSucceeds = true
    var submitDelayNanoseconds: UInt64 = 0
    var suspendSubmit = false
    private var suspendedSubmitContinuation: CheckedContinuation<Bool, Never>?
    private(set) var submitCallCount = 0
    private(set) var persistCallCount = 0

    init(state: SitePropsLocalState) {
        self.state = state
    }

    func currentState() -> SitePropsLocalState {
        state
    }

    func persistState(_ state: SitePropsLocalState) -> Bool {
        persistCallCount += 1
        guard persistSucceeds else { return false }
        self.state = state
        return true
    }

    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool {
        submitCallCount += 1
        let succeeds: Bool
        if suspendSubmit {
            succeeds = await withCheckedContinuation { continuation in
                suspendedSubmitContinuation = continuation
            }
        } else {
            if submitDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: submitDelayNanoseconds)
            }
            succeeds = submitSucceeds
        }

        guard succeeds else { return false }
        state = SitePropsEditPolicy.localStateAfterSuccessfulUpdate(
            current: state,
            request: snapshot
        )
        return true
    }

    func resumeSuspendedSubmit(success: Bool) {
        suspendedSubmitContinuation?.resume(returning: success)
        suspendedSubmitContinuation = nil
    }
}
