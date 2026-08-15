import Foundation

@main
struct SiteGatewayCloudTimeZoneSessionCoordinatorTests {

    private static let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!

    @MainActor
    static func main() async {
        await testBuildsTargetsPublishesInitialStateAndConfirmsSuccessfulPush()
        await testNoPendingTargetsReturnsWithoutCallingAPI()
        await testFailureProducesReviewContext()
        await testCancelReturnsNil()
        await testSecondRunRejectsLateFirstRunCallbacks()
        await testVisitorHasNoTargetsAndDoesNotCallAPI()
        print("SiteGatewayCloudTimeZoneSessionCoordinatorTests passed")
    }

    @MainActor
    private static func testBuildsTargetsPublishesInitialStateAndConfirmsSuccessfulPush() async {
        let api = SessionFakeAPI(
            statusPlans: [.result(.success([snapshot("pending-mac", .succeed)]))]
        )
        let timing = SessionFakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let input = SiteGatewayCloudTimeZoneSessionInput(
            siteID: "site-1",
            targetTimeZone: singapore,
            remoteSnapshot: remote(
                role: .owner,
                gateways: [
                    gateway("existing-mac", offsetMinutes: 0),
                    gateway("pending-mac", offsetMinutes: 0)
                ]
            ),
            localSnapshotsByID: [:],
            confirmedOffsetMinutesByGatewayID: ["existing-mac": 480]
        )
        let task = Task { @MainActor in
            await coordinator.run(input: input) { updates.append($0) }
        }

        await waitUntil("submit and polling must start") {
            api.submitCalls.count == 1 && timing.sleepCount(nanoseconds: 3) == 1
        }
        require(
            updates.first?.items.map(\.status) == [.synced, .pushing],
            "The session must immediately publish the target builder's initial state"
        )
        require(
            api.submitCalls.first?.siteID == "site-1" &&
                api.submitCalls.first?.gatewayMACs == ["pending-mac"],
            "Only pending request MACs must be submitted for the input Site"
        )

        timing.advance(by: 3)
        let result = await task.value

        require(
            result?.initialState.items.map(\.status) == [.synced, .pushing],
            "The result must retain the exact initial batch"
        )
        require(
            result?.terminalState.items.map(\.status) == [.synced, .synced],
            "A successful poll must produce a fully synced terminal batch"
        )
        require(
            result?.confirmedOffsetMinutesByGatewayID == [
                "existing-mac": 480,
                "pending-mac": 480
            ],
            "The full confirmation snapshot must retain valid input confirmations and add newly synced pending targets"
        )
        require(result?.reviewContext == nil, "A successful terminal batch must not require Review sync")
    }

    @MainActor
    private static func testNoPendingTargetsReturnsWithoutCallingAPI() async {
        let api = SessionFakeAPI()
        let timing = SessionFakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let input = SiteGatewayCloudTimeZoneSessionInput(
            siteID: "site-1",
            targetTimeZone: singapore,
            remoteSnapshot: remote(
                role: .owner,
                gateways: [gateway("already-synced", offsetMinutes: 0)]
            ),
            localSnapshotsByID: [
                "already-synced": SiteGatewayCloudTimeZoneLocalSnapshot(
                    displayName: "Local Gateway",
                    dirtyOffsetMinutes: 480
                )
            ],
            confirmedOffsetMinutesByGatewayID: [:]
        )

        let result = await coordinator.run(input: input) { updates.append($0) }

        require(updates.map(statuses) == [[.synced]], "A no-request run must still publish its initial UI state")
        require(result?.initialState == result?.terminalState, "A no-request run must finish from its initial state")
        require(api.submitCalls.isEmpty, "A no-request run must not call submit")
        require(api.statusCalls.isEmpty, "A no-request run must not poll")
    }

    @MainActor
    private static func testFailureProducesReviewContext() async {
        let api = SessionFakeAPI(
            submitPlans: [.result(.failure(.submitUnavailable))]
        )
        let timing = SessionFakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let input = SiteGatewayCloudTimeZoneSessionInput(
            siteID: "site-1",
            targetTimeZone: singapore,
            remoteSnapshot: remote(
                role: .owner,
                gateways: [gateway("failed-mac", offsetMinutes: 0)]
            ),
            localSnapshotsByID: [:],
            confirmedOffsetMinutesByGatewayID: [:]
        )

        let result = await coordinator.run(input: input) { updates.append($0) }

        require(
            updates.map(statuses) == [[.pushing], [.failed]],
            "A submit failure must publish the initial and terminal states in order"
        )
        require(
            result?.reviewContext == SiteGatewayTimeZoneReviewContext(
                targetTimeZone: singapore,
                failedGatewayIDs: ["failed-mac"]
            ),
            "Failed targets must produce an explicit Review context"
        )
        require(
            result?.confirmedOffsetMinutesByGatewayID.isEmpty == true,
            "A failed pending target must not become confirmed"
        )
    }

    @MainActor
    private static func testCancelReturnsNil() async {
        let api = SessionFakeAPI(submitPlans: [.suspended])
        let timing = SessionFakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let task = Task { @MainActor in
            await coordinator.run(input: pendingInput(siteID: "cancelled-site", gatewayID: "cancelled")) {
                updates.append($0)
            }
        }

        await waitUntil("submit must suspend") { api.submitCalls.count == 1 }
        coordinator.cancel()
        let result = await task.value
        api.resumeSubmit(call: 0, with: .success(101))
        await settle()

        require(result == nil, "Explicit cancellation must return nil")
        require(updates.map(statuses) == [[.pushing]], "Cancellation must not invent a terminal update")
        require(api.statusCalls.isEmpty, "A late cancelled submit response must not start polling")
    }

    @MainActor
    private static func testSecondRunRejectsLateFirstRunCallbacks() async {
        let api = SessionFakeAPI(submitPlans: [.suspended])
        let timing = SessionFakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var oldUpdates = [SiteGatewayCloudTimeZoneBatchState]()
        var newUpdates = [SiteGatewayCloudTimeZoneBatchState]()
        let oldTask = Task { @MainActor in
            await coordinator.run(input: pendingInput(siteID: "old-site", gatewayID: "old")) {
                oldUpdates.append($0)
            }
        }
        await waitUntil("old submit must suspend") { api.submitCalls.count == 1 }

        let newResult = await coordinator.run(
            input: SiteGatewayCloudTimeZoneSessionInput(
                siteID: "new-site",
                targetTimeZone: singapore,
                remoteSnapshot: remote(
                    role: .owner,
                    gateways: [gateway("new", offsetMinutes: 480)]
                ),
                localSnapshotsByID: [:],
                confirmedOffsetMinutesByGatewayID: [:]
            )
        ) { newUpdates.append($0) }
        let oldResult = await oldTask.value
        api.resumeSubmit(call: 0, with: .success(101))
        timing.advance(by: 3)
        await settle()

        require(oldResult == nil, "Starting a second run must cancel the first result owner")
        require(oldUpdates.map(statuses) == [[.pushing]], "A late first response must not reach the old callback")
        require(newUpdates.map(statuses) == [[.synced]], "The second run must own its own updates")
        require(newResult?.terminalState.items.map(\.id) == ["new"], "The second result must contain only second-run targets")
        require(api.statusCalls.isEmpty, "A late first submit response must not poll inside the second run")
    }

    @MainActor
    private static func testVisitorHasNoTargetsAndDoesNotCallAPI() async {
        let api = SessionFakeAPI()
        let timing = SessionFakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let input = SiteGatewayCloudTimeZoneSessionInput(
            siteID: "visitor-site",
            targetTimeZone: singapore,
            remoteSnapshot: remote(
                role: .visitor,
                gateways: [gateway("visitor-gateway", offsetMinutes: 0)]
            ),
            localSnapshotsByID: [:],
            confirmedOffsetMinutesByGatewayID: [:]
        )

        let result = await coordinator.run(input: input) { updates.append($0) }

        require(updates.first?.items.isEmpty == true, "Visitor must receive an empty initial target state")
        require(result?.terminalState.items.isEmpty == true, "Visitor must finish without Gateway targets")
        require(api.submitCalls.isEmpty && api.statusCalls.isEmpty, "Visitor must never call the Gateway Cloud API")
    }

    @MainActor
    private static func makeCoordinator(
        api: SessionFakeAPI,
        timing: SessionFakeTiming
    ) -> SiteGatewayCloudTimeZoneSessionCoordinator {
        SiteGatewayCloudTimeZoneSessionCoordinator(
            syncCoordinator: SiteGatewayCloudTimeZoneSyncCoordinator(
                api: api,
                timing: timing,
                pollIntervalNanoseconds: 3,
                timeoutNanoseconds: 100
            )
        )
    }

    private static func pendingInput(
        siteID: String,
        gatewayID: String
    ) -> SiteGatewayCloudTimeZoneSessionInput {
        SiteGatewayCloudTimeZoneSessionInput(
            siteID: siteID,
            targetTimeZone: singapore,
            remoteSnapshot: remote(
                role: .owner,
                gateways: [gateway(gatewayID, offsetMinutes: 0)]
            ),
            localSnapshotsByID: [:],
            confirmedOffsetMinutesByGatewayID: [:]
        )
    }

    private static func remote(
        role: SiteEntryRole,
        gateways: [SiteEntryGatewayTimeZoneSnapshot]
    ) -> SiteEntryTimeZoneRemoteSnapshot {
        SiteEntryTimeZoneRemoteSnapshot(
            role: role,
            values: SitePropsValues(siteName: "Site", imageId: 1, timezone: singapore),
            timestamp: 1,
            spaces: [],
            gateways: gateways
        )
    }

    private static func gateway(
        _ id: String,
        offsetMinutes: Int?
    ) -> SiteEntryGatewayTimeZoneSnapshot {
        SiteEntryGatewayTimeZoneSnapshot(
            id: id,
            requestMAC: id,
            offsetMinutes: offsetMinutes
        )
    }

    private static func snapshot(
        _ id: String,
        _ status: SiteGatewayCloudTimeZoneRemoteStatus
    ) -> SiteGatewayCloudTimeZoneRemoteStatusSnapshot {
        SiteGatewayCloudTimeZoneRemoteStatusSnapshot(id: id, statuses: [status])
    }

    private static func statuses(
        _ state: SiteGatewayCloudTimeZoneBatchState
    ) -> [SiteGatewayCloudTimeZoneItemStatus] {
        state.items.map(\.status)
    }

    @MainActor
    private static func waitUntil(
        _ message: String,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        fatalError(message)
    }

    private static func settle() async {
        for _ in 0..<30 {
            await Task.yield()
        }
    }
}

@MainActor
private final class SessionFakeAPI: SiteGatewayCloudTimeZoneAPI {
    enum SubmitPlan {
        case result(Result<Int64, SessionTestError>)
        case suspended
    }

    enum StatusPlan {
        case result(Result<[SiteGatewayCloudTimeZoneRemoteStatusSnapshot], SessionTestError>)
    }

    private(set) var submitCalls = [(siteID: String, gatewayMACs: [String])]()
    private(set) var statusCalls = [Int64]()
    private var submitPlans: [SubmitPlan]
    private var statusPlans: [StatusPlan]
    private var submitContinuations = [Int: CheckedContinuation<Result<Int64, SessionTestError>, Never>]()

    init(
        submitPlans: [SubmitPlan] = [.result(.success(101))],
        statusPlans: [StatusPlan] = []
    ) {
        self.submitPlans = submitPlans
        self.statusPlans = statusPlans
    }

    func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64 {
        let call = submitCalls.count
        submitCalls.append((siteID, gatewayMACs))
        guard !submitPlans.isEmpty else { throw SessionTestError.missingPlan }
        let result: Result<Int64, SessionTestError>
        switch submitPlans.removeFirst() {
        case .result(let plannedResult):
            result = plannedResult
        case .suspended:
            result = await withCheckedContinuation { continuation in
                submitContinuations[call] = continuation
            }
        }
        return try result.get()
    }

    func statuses(
        requestID: Int64
    ) async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot] {
        statusCalls.append(requestID)
        guard !statusPlans.isEmpty else { throw SessionTestError.missingPlan }
        switch statusPlans.removeFirst() {
        case .result(let result):
            return try result.get()
        }
    }

    func resumeSubmit(call: Int, with result: Result<Int64, SessionTestError>) {
        guard let continuation = submitContinuations.removeValue(forKey: call) else {
            fatalError("No suspended submit call \(call)")
        }
        continuation.resume(returning: result)
    }
}

private enum SessionTestError: Error {
    case submitUnavailable
    case missingPlan
}

private final class SessionFakeTiming: SiteGatewayCloudTimeZoneTiming, @unchecked Sendable {
    private struct Waiter {
        let deadline: UInt64
        let duration: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentNanoseconds: UInt64 = 0
    private var waiters = [UUID: Waiter]()
    private var sleepDurations = [UInt64]()

    var nowNanoseconds: UInt64 {
        lock.withLock { currentNanoseconds }
    }

    func sleep(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    sleepDurations.append(nanoseconds)
                    waiters[id] = Waiter(
                        deadline: currentNanoseconds + nanoseconds,
                        duration: nanoseconds,
                        continuation: continuation
                    )
                }
            }
        }, onCancel: {
            let continuation = self.lock.withLock {
                self.waiters.removeValue(forKey: id)?.continuation
            }
            continuation?.resume(throwing: CancellationError())
        })
    }

    func sleepCount(nanoseconds: UInt64) -> Int {
        lock.withLock { sleepDurations.filter { $0 == nanoseconds }.count }
    }

    func advance(by nanoseconds: UInt64) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            currentNanoseconds += nanoseconds
            let dueIDs = waiters.compactMap { pair in
                pair.value.deadline <= currentNanoseconds ? pair.key : nil
            }
            return dueIDs.compactMap { waiters.removeValue(forKey: $0)?.continuation }
        }
        continuations.forEach { $0.resume() }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}
