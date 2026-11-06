import Foundation

@MainActor final class ProbeStore: SiteEntryTimeZoneSyncStore {
    var state: SitePropsLocalState
    var writes = 0
    var uploads = 0
    init(_ state: SitePropsLocalState) { self.state = state }
    func currentState() -> SitePropsLocalState { state }
    func persistState(_ state: SitePropsLocalState) -> Bool { writes += 1; self.state = state; return true }
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool { uploads += 1; return true }
}

actor ProbeSleeper: SiteEntryTimeZoneSyncSleeping {
    var minimum: CheckedContinuation<Void, Never>?
    func sleep(nanoseconds: UInt64) async throws {
        if nanoseconds == SiteEntryTimeZoneSyncCoordinator.minimumDisplayNanoseconds {
            await withCheckedContinuation { minimum = $0 }
        } else {
            try await Task.sleep(nanoseconds: nanoseconds)
        }
    }
    func isWaiting() -> Bool { minimum != nil }
    func release() { minimum?.resume(); minimum = nil }
}

@main struct SiteEntryGatewayEvaluationTests {
    static func checkEvaluationAndRouting(_ remote: SiteEntryTimeZoneRemoteSnapshot) {
        let unknown = SiteEntryGatewayEvaluation(targetOffsetMinutes: nil, remote: remote)
        precondition(unknown.summary == .unavailable && unknown.pendingGatewayIDs.isEmpty)
        precondition(SiteGatewayReviewRouteDecision.decide(evaluation: unknown, hasMeshNetwork: true, hasNavigationController: true) == .unavailable(.offsetUnavailable))
        let same = SiteEntryGatewayEvaluation(targetOffsetMinutes: -300, remote: remote)
        precondition(SiteGatewayReviewRouteDecision.decide(evaluation: same, hasMeshNetwork: false, hasNavigationController: true) == .noPending)
        let different = SiteEntryGatewayEvaluation(targetOffsetMinutes: -240, remote: remote)
        precondition(different.summary == .pending(1))
        precondition(SiteGatewayReviewRouteDecision.decide(evaluation: different, hasMeshNetwork: true, hasNavigationController: true) == .ready)
        precondition(SiteGatewayReviewRouteDecision.decide(evaluation: different, hasMeshNetwork: false, hasNavigationController: true) == .unavailable(.missingNetwork))
        precondition(SiteGatewayReviewRouteDecision.decide(evaluation: different, hasMeshNetwork: true, hasNavigationController: false) == .unavailable(.missingNavigation))
        let confirmed = SiteEntryGatewayEvaluation(targetOffsetMinutes: -240, remote: remote,
            localByGatewayID: ["synthetic-gateway": .init(displayName: "Gateway", dirtyOffsetMinutes: -360)],
            confirmedOffsetMinutesByGatewayID: ["SYNTHETIC-GATEWAY": -240])
        precondition(confirmed.summary == .inSync)
        let dirty = SiteEntryGatewayEvaluation(targetOffsetMinutes: -240, remote: remote,
            localByGatewayID: ["synthetic-gateway": .init(displayName: "Gateway", dirtyOffsetMinutes: -240)])
        precondition(dirty.summary == .inSync)
        let forced = SiteEntryGatewayEvaluation(targetOffsetMinutes: -300, remote: remote,
            requiredGatewayIDs: ["synthetic-gateway"])
        if !forced.pendingGatewayIDs.isEmpty {
            print("FAIL: Explicit retry candidates must not resync an already matching effective offset"); exit(1)
        }
        let requiredMismatch = SiteEntryGatewayEvaluation(targetOffsetMinutes: -240, remote: remote,
            requiredGatewayIDs: ["synthetic-gateway"])
        precondition(requiredMismatch.summary == .pending(1))
        let missing = SiteEntryTimeZoneRemoteSnapshot(role: .editor, values: remote.values, timestamp: 100,
            spaces: [.init(role: .editor, gatewayId: "missing")], gateways: [])
        precondition(SiteEntryGatewayEvaluation(targetOffsetMinutes: -300, remote: missing).summary == .pending(1))
        let visitor = SiteEntryTimeZoneRemoteSnapshot(role: .visitor, values: remote.values, timestamp: 100,
            spaces: [], gateways: remote.gateways)
        precondition(SiteEntryGatewayEvaluation(targetOffsetMinutes: nil, remote: visitor).summary == .noGateways)
        let conflict = SiteEntryTimeZoneRemoteSnapshot(role: .owner, values: remote.values, timestamp: 100,
            spaces: [], gateways: [.init(id: "duplicate", offsetMinutes: -300), .init(id: "duplicate", offsetMinutes: -240)])
        precondition(SiteEntryGatewayEvaluation(targetOffsetMinutes: -300, remote: conflict).summary == .pending(1))
        precondition(SiteEntryTimeZoneResult(timezone: remote.timezone!, site: .updatedFromServer, gateway: .inSync).shouldPresent)
    }

    @MainActor static func waitUntil(_ condition: () -> Bool) async {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { await Task.yield() }
        precondition(condition(), "Asynchronous boundary did not complete")
    }

    @MainActor static func checkPreparationFailureRetryAndCancellation(
        remote: SiteEntryTimeZoneRemoteSnapshot, local: SiteEntryTimeZoneLocalSnapshot
    ) async {
        var callbacks: [(Result<[String: Any], Error>) -> Void] = []
        let timeStore = SiteTimeZoneStore(read: { _ in nil }, write: { _, _ in }) { _, _, completion in
            callbacks.append(completion)
        }
        SiteTimeZoneValue.snapshotProvider = { id, _ in timeStore.snapshot(for: id) }
        let zone = remote.timezone!
        let store = ProbeStore(.init(values: remote.values, lastUpdate: 100,
            lastUploadCloudTimestamp: 100, pending: .init(fields: [], timestamp: nil)))
        let coordinator = SiteEntryTimeZoneSyncCoordinator(store: store, minimumDisplayNanoseconds: 0)
        let decision = coordinator.prepare(local: local, remote: remote, now: 100)
        let task = Task { @MainActor in
            await coordinator.run(decision, prepareTimeZone: { value in
                await withCheckedContinuation { continuation in
                    timeStore.refresh(identifier: value.ianaId) { _ in continuation.resume() }
                }
            }, evaluateGateways: { value in
                SiteEntryGatewayEvaluation(targetOffsetMinutes: value.offsetMinutes, remote: remote).summary
            })
        }
        await waitUntil { callbacks.count == 1 }
        callbacks.removeFirst()(.failure(NSError(domain: "test", code: 1)))
        let failed = await task.value
        precondition(failed.site == .alreadyInSync && failed.gateway == .unavailable && failed.shouldPresent)
        // An explicit refresh retries the real Store; it must not repeat Site arbitration.
        var retryFinished = false
        timeStore.refresh(identifier: zone.ianaId) { _ in retryFinished = true }
        await waitUntil { callbacks.count == 1 }
        callbacks.removeFirst()(.success(["code": 200, "data": ["is_dst": false,
            "current_offset": "UTC-05:00", "next_switch": NSNull(), "switches_to": NSNull()]]))
        await waitUntil { retryFinished }
        precondition(SiteEntryGatewayEvaluation(targetOffsetMinutes: zone.offsetMinutes, remote: remote).summary == .inSync)
        precondition(coordinator.prepare(local: local, remote: remote, now: 100) == .noAction)
        precondition(store.writes == 0 && store.uploads == 0)

        // A value becoming ready between prepare and presentation must also replace
        // the earlier unavailable summary, independent of observer delivery.
        let afterPrepare = await coordinator.run(decision, evaluateGateways: { value in
            SiteEntryGatewayEvaluation(targetOffsetMinutes: value.offsetMinutes, remote: remote).summary
        })
        precondition(afterPrepare.gateway == .inSync && !afterPrepare.shouldPresent)

        var releasePreparation: CheckedContinuation<Void, Never>?
        var evaluations = 0
        let cancelled = Task { @MainActor in
            await coordinator.run(decision, prepareTimeZone: { _ in
                await withCheckedContinuation { releasePreparation = $0 }
            }, evaluateGateways: { _ in evaluations += 1; return .pending(1) })
        }
        await waitUntil { releasePreparation != nil }
        cancelled.cancel()
        _ = await cancelled.value
        releasePreparation?.resume()
        for _ in 0..<10 { await Task.yield() }
        precondition(evaluations == 0 && store.writes == 0 && store.uploads == 0,
            "Cancelled preparation must not publish a late gateway result or mutate Site")

        let now = Date()
        let expired = try! SiteTimeZoneSnapshot(identifier: zone.ianaId, response: ["code": 200,
            "data": ["is_dst": true, "current_offset": "UTC-04:00",
                "next_switch": SiteTimeZoneSnapshot.requestDateString(now.addingTimeInterval(-10)),
                "switches_to": "UTC-05:00"]], requestedAt: now.addingTimeInterval(-60))
        SiteTimeZoneValue.snapshotProvider = { _, _ in expired }
        precondition(zone.offsetMinutes == nil)
        precondition(SiteEntryGatewayEvaluation(targetOffsetMinutes: zone.offsetMinutes, remote: remote).summary == .unavailable)
        print("PASS: preparation failure/retry, pre-presentation refresh, cancellation and DST expiry")
    }

    @MainActor static func main() async throws {
        let zone = SiteTimeZoneValue(storageValue: "America/New_York")!
        let date = Date()
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let cache = SiteTimeZoneCache(directory: cacheURL)
        let snapshot = try SiteTimeZoneSnapshot(identifier: zone.ianaId, response: ["code": 200,
            "data": ["is_dst": false, "current_offset": "UTC-05:00", "next_switch": NSNull(), "switches_to": NSNull()]], requestedAt: date)
        try cache.write(zone.ianaId, data: JSONEncoder().encode(SiteTimeZoneCache.Envelope(version: 1, snapshot: snapshot)))
        let releaseDisk = DispatchSemaphore(value: 0)
        var fetchCount = 0
        let timeStore = SiteTimeZoneStore(read: { id in
            releaseDisk.wait()
            return try cache.read(id)
        }, write: cache.write, fetch: { _, _, _ in fetchCount += 1 })
        SiteTimeZoneValue.snapshotProvider = { id, _ in timeStore.snapshot(for: id) }
        defer { SiteTimeZoneValue.snapshotProvider = { _, _ in nil } }

        // Use the real parser, including encoded timezoneOffset=44 from the supplied log.
        let remote = SiteEntryTimeZoneSyncResponseParser.parse(siteData: [
            "siteName": "Synthetic Site", "imageId": 3, "role": "owner", "updateTimestamp": 100,
            "timezone": zone.storageValue, "spaces": [],
            "gateways": [["macAddress": "SYNTHETIC-GATEWAY", "timezoneOffset": 44]]
        ])!
        let local = SiteEntryTimeZoneLocalSnapshot(siteId: "synthetic", values: remote.values,
            lastUpdate: 100, lastUploadCloudTimestamp: 100, pending: .init(fields: [], timestamp: nil))
        let store = ProbeStore(.init(values: remote.values, lastUpdate: 100, lastUploadCloudTimestamp: 100,
            pending: .init(fields: [], timestamp: nil)))
        let sleeper = ProbeSleeper()
        let coordinator = SiteEntryTimeZoneSyncCoordinator(store: store, sleeper: sleeper)
        var checking = true
        var notificationsDuringChecking = 0
        let observation = timeStore.observe(identifier: zone.ianaId) {
            // UIKit host's checking-state branch is not executed by this Foundation probe.
            // Record that production cache delivery falls inside that branch's window.
            if checking { notificationsDuringChecking += 1 }
        }
        defer { timeStore.removeObserver(observation) }
        timeStore.refresh(identifier: zone.ianaId)
        precondition(zone.offsetMinutes == nil)
        let decision = coordinator.prepare(local: local, remote: remote, now: 100)
        if case .showGatewayStatus(_, .pending) = decision { print("FAIL: Unavailable Site offset must not report gateways pending"); exit(1) }
        precondition(decision == .showGatewayStatus(timezone: zone, gateway: .unavailable))
        let running = Task { @MainActor in
            await coordinator.run(decision, prepareTimeZone: { value in
                await withCheckedContinuation { continuation in
                    timeStore.refresh(identifier: value.ianaId) { _ in continuation.resume() }
                }
            }, evaluateGateways: { value in
                SiteEntryTimeZoneSyncPolicy.gatewaySummary(remote: remote,
                    targetOffsetMinutes: value.offsetMinutes, localDirtyOffsetMinutesByGatewayID: [:])
            })
        }
        while !(await sleeper.isWaiting()) { await Task.yield() }
        releaseDisk.signal()
        let deadline = Date().addingTimeInterval(5)
        while timeStore.snapshot(for: zone.ianaId) == nil && Date() < deadline { await Task.yield() }
        precondition(zone.offsetMinutes == -300 && notificationsDuringChecking == 1)
        await sleeper.release()
        let result = await running.value
        checking = false
        precondition(result.gateway == .inSync && !result.shouldPresent)
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(targetOffsetMinutes: zone.offsetMinutes,
            remote: remote, localByGatewayID: [:])
        let descriptors = SyncGatewayRuntimeDescriptorPolicy.make(candidates: targets.map {
            .init(id: $0.id, displayName: $0.displayName, remoteOrder: $0.remoteOrder,
                  effectiveOffsetMinutes: $0.effectiveOffsetMinutes, requiresSync: $0.requiresSync)
        }, localAvailabilityByGatewayID: ["synthetic-gateway": .init(hasGatewayModel: true, hasNode: true)])
        precondition(descriptors.isEmpty)
        precondition(SiteEntryTimeZoneSyncPolicy.reviewState(remote: remote) == .hidden)
        precondition(fetchCount == 0 && store.writes == 0 && store.uploads == 0)
        print("CACHE DURING CHECKING: offset=-300, notifications=1, HTTP=0")
        print("PASS: disk restore during checking yields inSync, no result alert, zero route targets")
        let warm = SiteEntryTimeZoneSyncCoordinator(store: store)
        precondition(warm.prepare(local: local, remote: remote, now: 100) == .noAction)
        print("WARM REENTRY: decision=noAction")
        let mismatch = SiteEntryTimeZoneRemoteSnapshot(role: remote.role, values: remote.values, timestamp: 100,
            spaces: [], gateways: [.init(id: "synthetic-gateway", offsetMinutes: -240)])
        precondition(SiteEntryTimeZoneSyncPolicy.gatewaySummary(remote: mismatch, targetOffsetMinutes: zone.offsetMinutes,
            localDirtyOffsetMinutesByGatewayID: [:]) == .pending(1))
        print("REAL MISMATCH CONTROL: gateway=-240, target=-300, pending=1")
        SiteTimeZoneValue.snapshotProvider = { _, _ in nil }
        let unknown = SiteEntryTimeZoneSyncPolicy.decide(local: local, remote: remote, now: 100)
        guard case .showGatewayStatus(_, .unavailable) = unknown else { fatalError("Unavailable offset must remain unknown") }
        print("PASS: unavailable offset never reports pending or inSync")
        checkEvaluationAndRouting(remote)
        await checkPreparationFailureRetryAndCancellation(remote: remote, local: local)
        print("SiteEntryGatewayEvaluationTests passed")
    }
}
