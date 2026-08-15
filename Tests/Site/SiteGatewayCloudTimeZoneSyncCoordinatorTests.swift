import Foundation

@main
struct SiteGatewayCloudTimeZoneSyncCoordinatorTests {

    @MainActor
    static func main() async {
        await testNoRequestMACsReturnsWithoutCallingAPI()
        await testFirstPollWaitsForPollInterval()
        await testRequestedStatusContinuesPolling()
        await testStatusFailureContinuesPolling()
        await testPartialTerminalStatusPublishesAndContinues()
        await testAllTerminalStatusesFinishImmediately()
        await testSubmitFailureFailsEveryPushingRow()
        await testInvalidSubmitResponseFailureFailsEveryPushingRow()
        await testDeadlineStartsAfterValidRequestID()
        await testTimeoutTaskFailsRemainingPushingRows()
        await testBackgroundDeadlineCrossingDoesNotRequestStatus()
        await testResponseArrivingAfterDeadlineCannotSucceed()
        await testCancelReturnsNilAndLateSubmitCannotUpdate()
        await testCallerCancellationReturnsNil()
        await testLateStatusResponseCannotContinueInsideActiveNewRun()
        await testLateSubmitResponseCannotStartPollingInsideActiveNewRun()
        await testOverflowingDeadlineSaturatesSafely()
        print("SiteGatewayCloudTimeZoneSyncCoordinatorTests passed")
    }

    @MainActor
    private static func testNoRequestMACsReturnsWithoutCallingAPI() async {
        let api = FakeAPI()
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let initialState = batch([target("already", requiresSync: false)])
        var updates = [SiteGatewayCloudTimeZoneBatchState]()

        let result = await coordinator.run(siteID: "site", initialState: initialState) {
            updates.append($0)
        }

        require(result == initialState, "A terminal initial batch must return unchanged")
        require(updates.isEmpty, "A terminal initial batch must not publish a redundant update")
        require(api.submitCalls.isEmpty, "A batch without request MACs must not submit")
        require(api.statusCalls.isEmpty, "A batch without request MACs must not poll")
    }

    @MainActor
    private static func testFirstPollWaitsForPollInterval() async {
        let api = FakeAPI(statusPlans: [.result(.success([snapshot("one", .succeed)]))])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitUntil("submit and poll sleeps must start") {
            api.submitCalls.count == 1
                && timing.sleepCount(nanoseconds: 3_000_000_000) == 1
        }
        timing.advance(by: 2_999_999_999)
        await settle()
        require(api.statusCalls.isEmpty, "The first status request must not happen before three seconds")

        timing.advance(by: 1)
        let result = await task.value
        require(api.statusCalls == [101], "The first status request must use the submitted request ID")
        require(statuses(result) == [.synced], "The terminal status must complete the row")
    }

    @MainActor
    private static func testRequestedStatusContinuesPolling() async {
        let api = FakeAPI(statusPlans: [
            .result(.success([snapshot("one", .requested)])),
            .result(.success([snapshot("one", .succeed)]))
        ])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let task = Task { @MainActor in
            await coordinator.run(siteID: "site", initialState: batch([target("one")])) {
                updates.append($0)
            }
        }

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        await waitForPollSleep(api: api, timing: timing, count: 2)
        require(api.statusCalls.count == 1, "Requested must leave the row pending and schedule another poll")
        require(updates.isEmpty, "Requested must not publish an unchanged state")

        timing.advance(by: 3_000_000_000)
        let result = await task.value
        require(api.statusCalls.count == 2, "Requested must be followed by another status request")
        require(statuses(result) == [.synced], "The later terminal response must complete the run")
        require(updates.map(statuses) == [[.synced]], "Only a real row change may publish an update")
    }

    @MainActor
    private static func testStatusFailureContinuesPolling() async {
        let api = FakeAPI(statusPlans: [
            .result(.failure(.statusUnavailable)),
            .result(.success([snapshot("one", .succeed)]))
        ])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        await waitForPollSleep(api: api, timing: timing, count: 2)
        require(api.statusCalls.count == 1, "A single status failure must schedule another poll")

        timing.advance(by: 3_000_000_000)
        let result = await task.value
        require(api.statusCalls.count == 2, "Polling must continue after a transient status failure")
        require(statuses(result) == [.synced], "A later success must still finish the run")
    }

    @MainActor
    private static func testPartialTerminalStatusPublishesAndContinues() async {
        let api = FakeAPI(statusPlans: [
            .result(.success([snapshot("one", .succeed), snapshot("two", .requested)])),
            .result(.success([snapshot("two", .failed)]))
        ])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let task = Task { @MainActor in
            await coordinator.run(
                siteID: "site",
                initialState: batch([target("one"), target("two")])
            ) {
                updates.append($0)
            }
        }

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        await waitForPollSleep(api: api, timing: timing, count: 2)
        require(updates.map(statuses) == [[.synced, .pushing]], "A partial terminal response must publish changed rows")

        timing.advance(by: 3_000_000_000)
        let result = await task.value
        require(statuses(result) == [.synced, .failed], "The second terminal response must finish the remaining row")
        require(
            updates.map(statuses) == [[.synced, .pushing], [.synced, .failed]],
            "Each changed batch state must be published in order"
        )
    }

    @MainActor
    private static func testAllTerminalStatusesFinishImmediately() async {
        let api = FakeAPI(statusPlans: [
            .result(.success([snapshot("one", .succeed), snapshot("two", .expired)]))
        ])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let task = runTask(
            coordinator,
            initialState: batch([target("one"), target("two")])
        )

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        let result = await task.value
        timing.advance(by: 180_000_000_000)
        await settle()

        require(statuses(result) == [.synced, .failed], "All terminal statuses must finish immediately")
        require(api.statusCalls.count == 1, "A terminal batch must cancel future polls")
    }

    @MainActor
    private static func testSubmitFailureFailsEveryPushingRow() async {
        let api = FakeAPI(submitPlans: [.result(.failure(.submitUnavailable))])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()

        let result = await coordinator.run(
            siteID: "site",
            initialState: batch([target("synced", requiresSync: false), target("pending")])
        ) {
            updates.append($0)
        }

        require(statuses(result) == [.synced, .failed], "Submit failure must fail only pushing rows")
        require(updates.map(statuses) == [[.synced, .failed]], "Submit failure must publish its terminal state once")
        require(api.statusCalls.isEmpty, "Submit failure must not start polling")
    }

    @MainActor
    private static func testInvalidSubmitResponseFailureFailsEveryPushingRow() async {
        let api = FakeAPI(submitPlans: [.result(.failure(.invalidResponse))])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let result = await coordinator.run(
            siteID: "site",
            initialState: batch([target("one"), target("two")]),
            onUpdate: { _ in }
        )

        require(statuses(result) == [.failed, .failed], "An invalid submit response thrown by the API must fail the batch")
        require(api.statusCalls.isEmpty, "An invalid submit response must not start polling")
    }

    @MainActor
    private static func testDeadlineStartsAfterValidRequestID() async {
        let api = FakeAPI(
            submitPlans: [.suspended],
            statusPlans: [.result(.success([snapshot("one", .succeed)]))]
        )
        let timing = FakeTiming()
        let coordinator = makeCoordinator(
            api: api,
            timing: timing,
            pollInterval: 3,
            timeout: 10
        )
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitUntil("submit must suspend") { api.submitCalls.count == 1 }
        timing.setNow(1_000)
        api.resumeSubmit(call: 0, with: .success(101))
        await waitForPollSleep(api: api, timing: timing, count: 1, pollInterval: 3)
        timing.advance(by: 3)
        let result = await task.value

        require(api.statusCalls == [101], "Submit waiting time must not consume the post-request polling window")
        require(statuses(result) == [.synced], "The deadline must start after the valid request ID")
    }

    @MainActor
    private static func testTimeoutTaskFailsRemainingPushingRows() async {
        let api = FakeAPI()
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let task = Task { @MainActor in
            await coordinator.run(siteID: "site", initialState: batch([target("one")])) {
                updates.append($0)
            }
        }

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.setNow(180_000_000_000)
        require(
            timing.resumeOneSleep(nanoseconds: 180_000_000_000),
            "The timeout task sleep must be registered"
        )
        let result = await task.value

        require(statuses(result) == [.failed], "The timeout task must fail every remaining pushing row")
        require(updates.map(statuses) == [[.failed]], "Timeout must publish one final state")
        require(api.statusCalls.isEmpty, "A timeout that wins must cancel polling before a status request")
    }

    @MainActor
    private static func testBackgroundDeadlineCrossingDoesNotRequestStatus() async {
        let api = FakeAPI()
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.setNow(181_000_000_000)
        require(
            timing.resumeOneSleep(nanoseconds: 3_000_000_000),
            "The first poll sleep must be registered"
        )
        let result = await task.value

        require(api.statusCalls.isEmpty, "A foreground resume beyond the continuous deadline must not request status")
        require(statuses(result) == [.failed], "Crossing the continuous deadline must fail pending rows")
    }

    @MainActor
    private static func testResponseArrivingAfterDeadlineCannotSucceed() async {
        let api = FakeAPI(statusPlans: [.suspended])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        await waitUntil("status response must suspend") { api.statusCalls.count == 1 }
        timing.setNow(181_000_000_000)
        api.resumeStatus(call: 0, with: .success([snapshot("one", .succeed)]))
        let result = await task.value

        require(statuses(result) == [.failed], "A response received beyond the deadline must not apply success")
    }

    @MainActor
    private static func testCancelReturnsNilAndLateSubmitCannotUpdate() async {
        let api = FakeAPI(submitPlans: [.suspended])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var updates = [SiteGatewayCloudTimeZoneBatchState]()
        let task = Task { @MainActor in
            await coordinator.run(siteID: "site", initialState: batch([target("one")])) {
                updates.append($0)
            }
        }

        await waitUntil("submit must suspend") { api.submitCalls.count == 1 }
        coordinator.cancel()
        let result = await task.value
        api.resumeSubmit(call: 0, with: .success(101))
        await settle()

        require(result == nil, "Explicit cancellation must return nil")
        require(updates.isEmpty, "A late submit response must not update an ended run")
        require(api.statusCalls.isEmpty, "A late submit response must not start polling")
    }

    @MainActor
    private static func testCallerCancellationReturnsNil() async {
        let api = FakeAPI(submitPlans: [.suspended])
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitUntil("submit must suspend") { api.submitCalls.count == 1 }
        task.cancel()
        let result = await task.value

        require(result == nil, "Caller Task cancellation must be forwarded to coordinator cancellation")
        api.resumeSubmit(call: 0, with: .success(101))
        await settle()
    }

    @MainActor
    private static func testLateStatusResponseCannotContinueInsideActiveNewRun() async {
        let api = FakeAPI(
            submitPlans: [.result(.success(101)), .result(.success(202))],
            statusPlans: [.suspended, .suspended]
        )
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var oldUpdates = [SiteGatewayCloudTimeZoneBatchState]()
        var newUpdates = [SiteGatewayCloudTimeZoneBatchState]()
        let oldTask = Task { @MainActor in
            await coordinator.run(siteID: "old-site", initialState: batch([target("old")])) {
                oldUpdates.append($0)
            }
        }

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        await waitUntil("old status response must suspend") { api.statusCalls == [101] }

        let newTask = Task { @MainActor in
            await coordinator.run(siteID: "new-site", initialState: batch([target("new")])) {
                newUpdates.append($0)
            }
        }
        let oldResult = await oldTask.value
        require(oldResult == nil, "Starting a new run must cancel the old status continuation owner")

        await waitForPollSleep(api: api, timing: timing, count: 2)
        timing.advance(by: 3_000_000_000)
        await waitUntil("new status response must suspend") { api.statusCalls == [101, 202] }

        api.resumeStatus(call: 0, with: .success([snapshot("new", .failed)]))
        await settle()
        timing.advance(by: 3_000_000_000)
        await settle()

        require(api.statusCalls == [101, 202], "A late old status must not continue polling request 101 inside the new run")
        require(oldUpdates.isEmpty, "The cancelled old run must not publish updates")
        require(newUpdates.isEmpty, "A late old status must not update or complete the active new run")

        api.resumeStatus(call: 1, with: .success([snapshot("new", .succeed)]))
        let newResult = await newTask.value
        require(statuses(newResult) == [.synced], "The new run must complete from its own status response")
        require(newUpdates.map(statuses) == [[.synced]], "Only the new request may update the new run")
    }

    @MainActor
    private static func testLateSubmitResponseCannotStartPollingInsideActiveNewRun() async {
        let api = FakeAPI(
            submitPlans: [.suspended, .result(.success(202))],
            statusPlans: [
                .suspended,
                .result(.success([snapshot("new", .failed)]))
            ]
        )
        let timing = FakeTiming()
        let coordinator = makeCoordinator(api: api, timing: timing)
        var oldUpdates = [SiteGatewayCloudTimeZoneBatchState]()
        var newUpdates = [SiteGatewayCloudTimeZoneBatchState]()
        let oldTask = Task { @MainActor in
            await coordinator.run(siteID: "old-site", initialState: batch([target("old")])) {
                oldUpdates.append($0)
            }
        }
        await waitUntil("old submit must suspend") { api.submitCalls.count == 1 }

        let newTask = Task { @MainActor in
            await coordinator.run(siteID: "new-site", initialState: batch([target("new")])) {
                newUpdates.append($0)
            }
        }
        let oldResult = await oldTask.value
        require(oldResult == nil, "Starting a new run must cancel the old continuation")

        await waitForPollSleep(api: api, timing: timing, count: 1)
        timing.advance(by: 3_000_000_000)
        await waitUntil("new status response must suspend") { api.statusCalls == [202] }

        api.resumeSubmit(call: 0, with: .success(101))
        await settle()
        timing.advance(by: 3_000_000_000)
        await settle()

        require(api.statusCalls == [202], "A late old submit must not start polling request 101 inside the new run")
        require(oldUpdates.isEmpty, "A late old submit must not publish into the old callback")
        require(newUpdates.isEmpty, "A late old submit must not update or complete the active new run")

        api.resumeStatus(call: 0, with: .success([snapshot("new", .succeed)]))
        let newResult = await newTask.value
        require(statuses(newResult) == [.synced], "The new token must own its own terminal result")
        require(newUpdates.map(statuses) == [[.synced]], "Only the new run may publish its state")
        require(api.statusCalls == [202], "The old request ID must never enter the new session")
    }

    @MainActor
    private static func testOverflowingDeadlineSaturatesSafely() async {
        let api = FakeAPI(statusPlans: [.result(.success([snapshot("one", .succeed)]))])
        let timing = FakeTiming(nowNanoseconds: UInt64.max - 5)
        let coordinator = makeCoordinator(
            api: api,
            timing: timing,
            pollInterval: 1,
            timeout: 10
        )
        let task = runTask(coordinator, initialState: batch([target("one")]))

        await waitForPollSleep(api: api, timing: timing, count: 1, pollInterval: 1)
        timing.advance(by: 1)
        let result = await task.value

        require(api.statusCalls == [101], "A saturated deadline must not wrap below the current clock")
        require(statuses(result) == [.synced], "Work before the saturated deadline must remain eligible to succeed")
    }

    @MainActor
    private static func makeCoordinator(
        api: FakeAPI,
        timing: FakeTiming,
        pollInterval: UInt64 = 3_000_000_000,
        timeout: UInt64 = 180_000_000_000
    ) -> SiteGatewayCloudTimeZoneSyncCoordinator {
        SiteGatewayCloudTimeZoneSyncCoordinator(
            api: api,
            timing: timing,
            pollIntervalNanoseconds: pollInterval,
            timeoutNanoseconds: timeout
        )
    }

    @MainActor
    private static func runTask(
        _ coordinator: SiteGatewayCloudTimeZoneSyncCoordinator,
        initialState: SiteGatewayCloudTimeZoneBatchState
    ) -> Task<SiteGatewayCloudTimeZoneBatchState?, Never> {
        Task { @MainActor in
            await coordinator.run(siteID: "site", initialState: initialState, onUpdate: { _ in })
        }
    }

    @MainActor
    private static func waitForPollSleep(
        api: FakeAPI,
        timing: FakeTiming,
        count: Int,
        pollInterval: UInt64 = 3_000_000_000
    ) async {
        await waitUntil("poll sleep \(count) must start") {
            api.submitCalls.count >= 1
                && timing.sleepCount(nanoseconds: pollInterval) >= count
        }
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

    private static func batch(
        _ targets: [SiteGatewayCloudTimeZoneTarget]
    ) -> SiteGatewayCloudTimeZoneBatchState {
        SiteGatewayCloudTimeZoneBatchState(targets: targets)
    }

    private static func target(
        _ id: String,
        requiresSync: Bool = true
    ) -> SiteGatewayCloudTimeZoneTarget {
        SiteGatewayCloudTimeZoneTarget(
            id: id,
            requestMAC: id.uppercased(),
            displayName: id,
            remoteOrder: 0,
            effectiveOffsetMinutes: requiresSync ? 0 : 480,
            requiresSync: requiresSync
        )
    }

    private static func snapshot(
        _ id: String,
        _ status: SiteGatewayCloudTimeZoneRemoteStatus
    ) -> SiteGatewayCloudTimeZoneRemoteStatusSnapshot {
        SiteGatewayCloudTimeZoneRemoteStatusSnapshot(id: id, statuses: [status])
    }

    private static func statuses(
        _ state: SiteGatewayCloudTimeZoneBatchState?
    ) -> [SiteGatewayCloudTimeZoneItemStatus] {
        state?.items.map(\.status) ?? []
    }

    private static func statuses(
        _ state: SiteGatewayCloudTimeZoneBatchState
    ) -> [SiteGatewayCloudTimeZoneItemStatus] {
        state.items.map(\.status)
    }
}

@MainActor
private final class FakeAPI: SiteGatewayCloudTimeZoneAPI {
    enum SubmitPlan {
        case result(Result<Int64, TestError>)
        case suspended
    }

    enum StatusPlan {
        case result(Result<[SiteGatewayCloudTimeZoneRemoteStatusSnapshot], TestError>)
        case suspended
    }

    private(set) var submitCalls = [(siteID: String, gatewayMACs: [String])]()
    private(set) var statusCalls = [Int64]()
    private var submitPlans: [SubmitPlan]
    private var statusPlans: [StatusPlan]
    private var submitContinuations = [Int: CheckedContinuation<Result<Int64, TestError>, Never>]()
    private var statusContinuations = [Int: CheckedContinuation<Result<[SiteGatewayCloudTimeZoneRemoteStatusSnapshot], TestError>, Never>]()

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
        guard !submitPlans.isEmpty else { throw TestError.missingPlan }
        let plan = submitPlans.removeFirst()
        let result: Result<Int64, TestError>
        switch plan {
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
        let call = statusCalls.count
        statusCalls.append(requestID)
        guard !statusPlans.isEmpty else { throw TestError.missingPlan }
        let plan = statusPlans.removeFirst()
        let result: Result<[SiteGatewayCloudTimeZoneRemoteStatusSnapshot], TestError>
        switch plan {
        case .result(let plannedResult):
            result = plannedResult
        case .suspended:
            result = await withCheckedContinuation { continuation in
                statusContinuations[call] = continuation
            }
        }
        return try result.get()
    }

    func resumeSubmit(call: Int, with result: Result<Int64, TestError>) {
        guard let continuation = submitContinuations.removeValue(forKey: call) else {
            fatalError("No suspended submit call \(call)")
        }
        continuation.resume(returning: result)
    }

    func resumeStatus(
        call: Int,
        with result: Result<[SiteGatewayCloudTimeZoneRemoteStatusSnapshot], TestError>
    ) {
        guard let continuation = statusContinuations.removeValue(forKey: call) else {
            fatalError("No suspended status call \(call)")
        }
        continuation.resume(returning: result)
    }
}

private enum TestError: Error {
    case submitUnavailable
    case statusUnavailable
    case invalidResponse
    case missingPlan
}

private final class FakeTiming: SiteGatewayCloudTimeZoneTiming, @unchecked Sendable {
    private struct Waiter {
        let duration: UInt64
        let deadline: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var currentNanoseconds: UInt64
    private var waiters = [UUID: Waiter]()
    private var sleepDurations = [UInt64]()

    init(nowNanoseconds: UInt64 = 0) {
        currentNanoseconds = nowNanoseconds
    }

    var nowNanoseconds: UInt64 {
        lock.withLock { currentNanoseconds }
    }

    func sleep(nanoseconds: UInt64) async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                let shouldResume = lock.withLock { () -> Bool in
                    sleepDurations.append(nanoseconds)
                    let deadline = saturatedAdd(currentNanoseconds, nanoseconds)
                    guard currentNanoseconds < deadline else { return true }
                    waiters[id] = Waiter(
                        duration: nanoseconds,
                        deadline: deadline,
                        continuation: continuation
                    )
                    return false
                }
                if shouldResume {
                    continuation.resume()
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

    func setNow(_ nanoseconds: UInt64) {
        lock.withLock {
            currentNanoseconds = nanoseconds
        }
    }

    func advance(by nanoseconds: UInt64) {
        let continuations = lock.withLock { () -> [CheckedContinuation<Void, Error>] in
            currentNanoseconds = saturatedAdd(currentNanoseconds, nanoseconds)
            let dueIDs = waiters.compactMap { pair in
                pair.value.deadline <= currentNanoseconds ? pair.key : nil
            }
            return dueIDs.compactMap { waiters.removeValue(forKey: $0)?.continuation }
        }
        continuations.forEach { $0.resume() }
    }

    @discardableResult
    func resumeOneSleep(nanoseconds: UInt64) -> Bool {
        let continuation = lock.withLock { () -> CheckedContinuation<Void, Error>? in
            guard let pair = waiters.first(where: { $0.value.duration == nanoseconds }) else {
                return nil
            }
            return waiters.removeValue(forKey: pair.key)?.continuation
        }
        continuation?.resume()
        return continuation != nil
    }

    private func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : result
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
