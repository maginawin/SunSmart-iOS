//
//  SiteEntryTimeZoneSyncCoordinator.swift
//  SunSmart
//
//  Created by One on 2026/8/12.
//

import Foundation

@MainActor
protocol SiteEntryTimeZoneSyncStore: AnyObject {
    func currentState() -> SitePropsLocalState
    func persistState(_ state: SitePropsLocalState) -> Bool
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}

protocol SiteEntryTimeZoneSyncSleeping {
    func sleep(nanoseconds: UInt64) async throws
}

private struct SiteEntryTimeZoneSystemSleeper: SiteEntryTimeZoneSyncSleeping {
    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }
}

@MainActor
final class SiteEntryTimeZoneSyncCoordinator {

    nonisolated static let minimumDisplayNanoseconds: UInt64 = 1_000_000_000
    nonisolated static let timeoutNanoseconds: UInt64 = 30_000_000_000

    private struct ActiveRun {
        let token: UUID
        let continuation: CheckedContinuation<SiteEntryTimeZoneResult, Never>
        let failureResult: SiteEntryTimeZoneResult
        var minimumElapsed: Bool
        var businessResult: SiteEntryTimeZoneResult?
    }

    private let store: SiteEntryTimeZoneSyncStore
    private let sleeper: SiteEntryTimeZoneSyncSleeping
    private let minimumDisplayNanoseconds: UInt64
    private let timeoutNanoseconds: UInt64
    private var activeRun: ActiveRun?
    private var minimumTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var businessTask: Task<Void, Never>?

    private(set) var hasConsumedEntryResponse = false

    init(
        store: SiteEntryTimeZoneSyncStore,
        sleeper: SiteEntryTimeZoneSyncSleeping = SiteEntryTimeZoneSystemSleeper(),
        minimumDisplayNanoseconds: UInt64 = SiteEntryTimeZoneSyncCoordinator.minimumDisplayNanoseconds,
        timeoutNanoseconds: UInt64 = SiteEntryTimeZoneSyncCoordinator.timeoutNanoseconds
    ) {
        self.store = store
        self.sleeper = sleeper
        self.minimumDisplayNanoseconds = minimumDisplayNanoseconds
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func prepare(
        local: SiteEntryTimeZoneLocalSnapshot,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        now: Int64,
        localDirtyOffsetMinutesByGatewayID: [String: Int] = [:]
    ) -> SiteEntryTimeZoneDecision {
        guard !hasConsumedEntryResponse else { return .noAction }
        hasConsumedEntryResponse = true
        return SiteEntryTimeZoneSyncPolicy.decide(
            local: local,
            remote: remote,
            now: now,
            localDirtyOffsetMinutesByGatewayID: localDirtyOffsetMinutesByGatewayID
        )
    }

    func consumeWithoutAction() {
        guard !hasConsumedEntryResponse else { return }
        hasConsumedEntryResponse = true
    }

    @discardableResult
    func applySilent(
        _ decision: SiteEntryTimeZoneDecision
    ) -> Bool {
        guard case let .useVisitorRemote(state) = decision else {
            return false
        }
        return store.persistState(state)
    }

    func run(
        _ decision: SiteEntryTimeZoneDecision
    ) async -> SiteEntryTimeZoneResult {
        guard let context = resultContext(for: decision) else {
            preconditionFailure("A no-action decision must not start entry sync")
        }

        cancel()
        let token = UUID()
        let failure = SiteEntryTimeZoneResult(
            timezone: context.timezone,
            site: .failedToUpdateServer,
            gateway: context.gateway
        )

        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                activeRun = ActiveRun(
                    token: token,
                    continuation: continuation,
                    failureResult: failure,
                    minimumElapsed: false,
                    businessResult: nil
                )

                minimumTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.sleeper.sleep(nanoseconds: self.minimumDisplayNanoseconds)
                    } catch {
                        return
                    }
                    self.markMinimumElapsed(token: token)
                }
                timeoutTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        try await self.sleeper.sleep(nanoseconds: self.timeoutNanoseconds)
                    } catch {
                        return
                    }
                    self.finish(token: token, result: failure)
                }
                businessTask = Task { [weak self] in
                    guard let self else { return }
                    let result = await self.perform(decision)
                    self.markBusinessFinished(
                        token: token,
                        decision: decision,
                        result: result
                    )
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        })
    }

    func cancel() {
        guard let activeRun else {
            cancelTasks()
            return
        }
        self.activeRun = nil
        cancelTasks()
        activeRun.continuation.resume(returning: activeRun.failureResult)
    }

    private func perform(
        _ decision: SiteEntryTimeZoneDecision
    ) async -> SiteEntryTimeZoneResult {
        switch decision {
        case .noAction:
            preconditionFailure("A no-action decision must not be performed")
        case let .showGatewayStatus(timezone, gateway):
            return SiteEntryTimeZoneResult(
                timezone: timezone,
                site: .alreadyInSync,
                gateway: gateway
            )

        case let .useRemote(timezone, remoteTimestamp, gateway):
            let current = store.currentState()
            let remainingFields = current.pending.fields.subtracting(.timezone)
            let state = SitePropsLocalState(
                values: SitePropsValues(
                    siteName: current.values.siteName,
                    imageId: current.values.imageId,
                    timezone: timezone
                ),
                lastUpdate: max(current.lastUpdate, remoteTimestamp),
                lastUploadCloudTimestamp: maxTimestamp(
                    current.lastUploadCloudTimestamp,
                    remoteTimestamp
                ),
                pending: SitePropsPendingState(
                    fields: remainingFields,
                    timestamp: remainingFields.isEmpty ? nil : current.pending.timestamp
                )
            )
            let result: SiteEntryTimeZoneSiteResult = store.persistState(state)
                ? .updatedFromServer
                : .failedToUpdateServer
            return SiteEntryTimeZoneResult(
                timezone: timezone,
                site: result,
                gateway: gateway
            )

        case let .useLocal(snapshot, gateway):
            guard let timezone = snapshot.values.timezone else {
                preconditionFailure("A local decision requires a valid timezone")
            }
            let current = store.currentState()
            let state = SitePropsLocalState(
                values: SitePropsValues(
                    siteName: current.values.siteName,
                    imageId: current.values.imageId,
                    timezone: timezone
                ),
                lastUpdate: snapshot.timestamp,
                lastUploadCloudTimestamp: current.lastUploadCloudTimestamp,
                pending: SitePropsPendingState(
                    fields: current.pending.fields.union(.timezone),
                    timestamp: snapshot.timestamp
                )
            )
            guard store.persistState(state) else {
                return SiteEntryTimeZoneResult(
                    timezone: timezone,
                    site: .failedToUpdateServer,
                    gateway: gateway
                )
            }

            let success = await store.submit(snapshot)
            return SiteEntryTimeZoneResult(
                timezone: timezone,
                site: success ? .updatedToServer : .failedToUpdateServer,
                gateway: gateway
            )

        case .useVisitorRemote:
            preconditionFailure("A Visitor decision must use the silent path")
        }
    }

    private func markMinimumElapsed(token: UUID) {
        guard var activeRun, activeRun.token == token else { return }
        activeRun.minimumElapsed = true
        self.activeRun = activeRun
        finishIfReady(token: token)
    }

    private func markBusinessFinished(
        token: UUID,
        decision: SiteEntryTimeZoneDecision,
        result: SiteEntryTimeZoneResult
    ) {
        guard var activeRun, activeRun.token == token else {
            restorePendingAfterLateSuccess(decision: decision, result: result)
            return
        }
        activeRun.businessResult = result
        self.activeRun = activeRun
        finishIfReady(token: token)
    }

    private func finishIfReady(token: UUID) {
        guard
            let activeRun,
            activeRun.token == token,
            activeRun.minimumElapsed,
            let result = activeRun.businessResult
        else {
            return
        }
        finish(token: token, result: result)
    }

    private func finish(token: UUID, result: SiteEntryTimeZoneResult) {
        guard let activeRun, activeRun.token == token else { return }
        self.activeRun = nil
        cancelTasks()
        activeRun.continuation.resume(returning: result)
    }

    private func cancelTasks() {
        minimumTask?.cancel()
        timeoutTask?.cancel()
        businessTask?.cancel()
        minimumTask = nil
        timeoutTask = nil
        businessTask = nil
    }

    private func restorePendingAfterLateSuccess(
        decision: SiteEntryTimeZoneDecision,
        result: SiteEntryTimeZoneResult
    ) {
        guard
            result.site == .updatedToServer,
            case let .useLocal(snapshot, _) = decision,
            let timezone = snapshot.values.timezone
        else {
            return
        }

        let current = store.currentState()
        guard
            current.lastUpdate == snapshot.timestamp,
            current.values.timezone == timezone,
            !current.pending.fields.contains(.timezone)
        else {
            return
        }
        let restored = SitePropsLocalState(
            values: current.values,
            lastUpdate: current.lastUpdate,
            lastUploadCloudTimestamp: current.lastUploadCloudTimestamp,
            pending: SitePropsPendingState(
                fields: current.pending.fields.union(.timezone),
                timestamp: snapshot.timestamp
            )
        )
        _ = store.persistState(restored)
    }

    private func resultContext(
        for decision: SiteEntryTimeZoneDecision
    ) -> (timezone: SiteTimeZoneValue, gateway: SiteEntryGatewaySummary)? {
        switch decision {
        case .noAction:
            return nil
        case let .showGatewayStatus(timezone, gateway):
            return (timezone, gateway)
        case let .useRemote(timezone, _, gateway):
            return (timezone, gateway)
        case let .useLocal(snapshot, gateway):
            guard let timezone = snapshot.values.timezone else { return nil }
            return (timezone, gateway)
        case .useVisitorRemote:
            return nil
        }
    }

    private func maxTimestamp(_ current: Int64?, _ remote: Int64) -> Int64 {
        guard let current else { return remote }
        return max(current, remote)
    }
}
