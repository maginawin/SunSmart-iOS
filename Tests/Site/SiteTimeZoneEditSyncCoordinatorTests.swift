import Foundation

@main
struct SiteTimeZoneEditSyncCoordinatorTests {

    private static let singapore = SiteTimeZoneValue(
        ianaId: "Asia/Singapore",
        rawUTCOffset: "+08:00"
    )!

    @MainActor
    static func main() async {
        await testSnapshotWithoutTimeZoneFieldDoesNotStart()
        await testSubmitFailureKeepsSiteSavedAndFailsPendingGateways()
        await testEmptyLocalTargetsCompleteWithoutGatewayAPI()
        await testLocalTargetsAreSubmittedWithoutRemoteSnapshot()
        await testCancellationRejectsLateGatewayUpdates()
        print("SiteTimeZoneEditSyncCoordinatorTests passed")
    }

    @MainActor
    private static func testSnapshotWithoutTimeZoneFieldDoesNotStart() async {
        let submitter = EditFakeSubmitter(results: [])
        let api = EditFakeGatewayAPI()
        let targets = EditTargetsProbe()
        let coordinator = makeCoordinator(
            submitter: submitter,
            api: api,
            targets: targets
        )
        let snapshot = SitePropsUpdateSnapshot(
            siteId: "site-1",
            fields: [.siteName],
            values: SitePropsValues(
                siteName: "Renamed Site",
                imageId: 1,
                timezone: singapore
            ),
            timestamp: 2
        )
        var updates = [SiteTimeZoneSyncPresentationState]()

        let outcome = await coordinator.run(snapshot: snapshot) {
            updates.append($0)
        }

        require(outcome == .siteFailed, "A snapshot without timezone must not start")
        require(updates.isEmpty, "An invalid snapshot must not present working state")
        require(submitter.snapshots.isEmpty, "An invalid snapshot must not submit Site")
        require(targets.timeZones.isEmpty, "An invalid snapshot must not read local Gateways")
        require(api.submitCalls.isEmpty, "An invalid snapshot must not call Gateway API")
    }

    @MainActor
    private static func testSubmitFailureKeepsSiteSavedAndFailsPendingGateways() async {
        let submitter = EditFakeSubmitter(results: [false])
        let api = EditFakeGatewayAPI()
        let targets = EditTargetsProbe(result: [
            target("already", requiresSync: false),
            target("gateway-1")
        ])
        let coordinator = makeCoordinator(
            submitter: submitter,
            api: api,
            targets: targets
        )
        var updates = [SiteTimeZoneSyncPresentationState]()

        let outcome = await coordinator.run(snapshot: updateSnapshot()) {
            updates.append($0)
        }

        guard case .completed(let result)? = outcome else {
            fatalError("A failed cloud submit must still complete the locally saved Edit flow")
        }
        require(targets.timeZones == [singapore], "A cloud failure must still classify local Gateways")
        require(
            result.terminalState.items.map(\.status) == [.synced, .failed],
            "A cloud failure must fail only pending Gateways"
        )
        require(
            result.reviewContext?.failedGatewayIDs == ["gateway-1"],
            "Failed Gateways must remain available for Review sync"
        )
        require(api.submitCalls.isEmpty, "A failed Site submit must not call Gateway API")
        require(
            updates.first == .working(.savingSite) &&
                updates.last == .result(
                    site: .savedSuccessfully,
                    gateways: .batch(result.terminalState)
                ),
            "A cloud failure must retain local Site success and publish terminal Gateway failures"
        )
    }

    @MainActor
    private static func testEmptyLocalTargetsCompleteWithoutGatewayAPI() async {
        let submitter = EditFakeSubmitter(results: [true])
        let api = EditFakeGatewayAPI()
        let targets = EditTargetsProbe(result: [])
        let coordinator = makeCoordinator(
            submitter: submitter,
            api: api,
            targets: targets
        )
        var updates = [SiteTimeZoneSyncPresentationState]()

        let outcome = await coordinator.run(snapshot: updateSnapshot()) {
            updates.append($0)
        }

        guard case .completed(let result)? = outcome else {
            fatalError("An empty local target run must complete")
        }
        require(targets.timeZones == [singapore], "Targets must use the edited timezone")
        require(result.initialState.items.isEmpty, "No local targets must produce an empty batch")
        require(api.submitCalls.isEmpty && api.statusCalls.isEmpty, "An empty batch must not call Gateway API")
        require(
            updates.last == .result(
                site: .savedSuccessfully,
                gateways: .batch(result.initialState)
            ),
            "The UI must retain Site success with an empty local Gateway batch"
        )
    }

    @MainActor
    private static func testLocalTargetsAreSubmittedWithoutRemoteSnapshot() async {
        let submitter = EditFakeSubmitter(results: [true])
        let api = EditFakeGatewayAPI(
            statusPlans: [[
                SiteGatewayCloudTimeZoneRemoteStatusSnapshot(
                    id: "gateway-1",
                    statuses: [.succeed]
                )
            ]]
        )
        let timing = EditFakeTiming()
        let targets = EditTargetsProbe(result: [target("gateway-1")])
        let coordinator = makeCoordinator(
            submitter: submitter,
            api: api,
            timing: timing,
            targets: targets
        )
        var updates = [SiteTimeZoneSyncPresentationState]()
        let task = Task { @MainActor in
            await coordinator.run(snapshot: updateSnapshot()) {
                updates.append($0)
            }
        }

        await waitUntil("Gateway submit and poll delay must start") {
            api.submitCalls.count == 1 && timing.sleepCount(nanoseconds: 3) == 1
        }
        require(
            api.submitCalls.first?.siteID == "site-1" &&
                api.submitCalls.first?.gatewayMACs == ["gateway-1"],
            "Edit must submit only locally prepared pending Gateway MACs"
        )
        timing.advance(by: 3)
        let outcome = await task.value

        guard case .completed(let result)? = outcome else {
            fatalError("A successful local Gateway session must complete")
        }
        require(result.terminalState.items.map(\.status) == [.synced], "The Gateway must finish synced")
        require(
            updates.last == .result(
                site: .savedSuccessfully,
                gateways: .batch(result.terminalState)
            ),
            "Terminal local Gateway state must reach the unified Edit UI"
        )
    }

    @MainActor
    private static func testCancellationRejectsLateGatewayUpdates() async {
        let submitter = EditFakeSubmitter(results: [true])
        let api = EditFakeGatewayAPI(suspendSubmit: true)
        let targets = EditTargetsProbe(result: [target("gateway-1")])
        let coordinator = makeCoordinator(
            submitter: submitter,
            api: api,
            targets: targets
        )
        var updates = [SiteTimeZoneSyncPresentationState]()
        let task = Task { @MainActor in
            await coordinator.run(snapshot: updateSnapshot()) {
                updates.append($0)
            }
        }

        await waitUntil("Gateway submit must suspend") { api.submitCalls.count == 1 }
        coordinator.cancel()
        api.resumeSubmit(with: 101)
        let outcome = await task.value

        require(outcome == nil, "An explicitly cancelled Edit run must return nil")
        require(
            updates.count == 2 && updates.first == .working(.savingSite),
            "Cancellation must reject late Gateway terminal updates"
        )
        require(api.statusCalls.isEmpty, "A late cancelled submit must not poll")
    }

    @MainActor
    private static func makeCoordinator(
        submitter: EditFakeSubmitter,
        api: EditFakeGatewayAPI,
        timing: EditFakeTiming = EditFakeTiming(),
        targets: EditTargetsProbe
    ) -> SiteTimeZoneEditSyncCoordinator {
        SiteTimeZoneEditSyncCoordinator(
            siteID: "site-1",
            submitter: submitter,
            gatewaySession: SiteGatewayCloudTimeZoneSessionCoordinator(
                syncCoordinator: SiteGatewayCloudTimeZoneSyncCoordinator(
                    api: api,
                    timing: timing,
                    pollIntervalNanoseconds: 3,
                    timeoutNanoseconds: 100
                )
            ),
            makeTargets: { timeZone in
                targets.make(timeZone: timeZone)
            }
        )
    }

    private static func updateSnapshot() -> SitePropsUpdateSnapshot {
        SitePropsUpdateSnapshot(
            siteId: "site-1",
            fields: [.timezone],
            values: SitePropsValues(
                siteName: "Site",
                imageId: 1,
                timezone: singapore
            ),
            timestamp: 2
        )
    }

    private static func target(
        _ id: String,
        requiresSync: Bool = true
    ) -> SiteGatewayCloudTimeZoneTarget {
        SiteGatewayCloudTimeZoneTarget(
            id: id,
            requestMAC: id,
            displayName: id,
            remoteOrder: 0,
            effectiveOffsetMinutes: requiresSync ? 0 : singapore.offsetMinutes,
            requiresSync: requiresSync
        )
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
}

@MainActor
private final class EditFakeSubmitter: SiteTimeZoneEditSubmitting {
    private(set) var snapshots = [SitePropsUpdateSnapshot]()
    private var results: [Bool]

    init(results: [Bool]) {
        self.results = results
    }

    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool {
        snapshots.append(snapshot)
        guard !results.isEmpty else { fatalError("Missing Site submit result") }
        return results.removeFirst()
    }
}

@MainActor
private final class EditTargetsProbe {
    private(set) var timeZones = [SiteTimeZoneValue]()
    private let result: [SiteGatewayCloudTimeZoneTarget]

    init(result: [SiteGatewayCloudTimeZoneTarget] = []) {
        self.result = result
    }

    func make(timeZone: SiteTimeZoneValue) -> [SiteGatewayCloudTimeZoneTarget] {
        timeZones.append(timeZone)
        return result
    }
}

@MainActor
private final class EditFakeGatewayAPI: SiteGatewayCloudTimeZoneAPI {
    private(set) var submitCalls = [(siteID: String, gatewayMACs: [String])]()
    private(set) var statusCalls = [Int64]()
    private var statusPlans: [[SiteGatewayCloudTimeZoneRemoteStatusSnapshot]]
    private let suspendSubmit: Bool
    private var submitContinuation: CheckedContinuation<Int64, Error>?

    init(
        statusPlans: [[SiteGatewayCloudTimeZoneRemoteStatusSnapshot]] = [],
        suspendSubmit: Bool = false
    ) {
        self.statusPlans = statusPlans
        self.suspendSubmit = suspendSubmit
    }

    func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64 {
        submitCalls.append((siteID, gatewayMACs))
        if suspendSubmit {
            return try await withCheckedThrowingContinuation { continuation in
                submitContinuation = continuation
            }
        }
        return 101
    }

    func resumeSubmit(with requestID: Int64) {
        submitContinuation?.resume(returning: requestID)
        submitContinuation = nil
    }

    func statuses(
        requestID: Int64
    ) async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot] {
        statusCalls.append(requestID)
        guard !statusPlans.isEmpty else { fatalError("Missing Gateway status plan") }
        return statusPlans.removeFirst()
    }
}

private final class EditFakeTiming: SiteGatewayCloudTimeZoneTiming, @unchecked Sendable {
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
            return dueIDs.compactMap {
                waiters.removeValue(forKey: $0)?.continuation
            }
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

private func require(
    _ condition: @autoclosure () -> Bool,
    _ message: String
) {
    guard condition() else { fatalError(message) }
}
