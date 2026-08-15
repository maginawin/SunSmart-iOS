//
//  SiteGatewayCloudTimeZoneSyncCoordinator.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import Foundation
import Darwin

protocol SiteGatewayCloudTimeZoneAPI {
    func submit(siteID: String, gatewayMACs: [String]) async throws -> Int64
    func statuses(
        requestID: Int64
    ) async throws -> [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]
}

protocol SiteGatewayCloudTimeZoneTiming {
    var nowNanoseconds: UInt64 { get }
    func sleep(nanoseconds: UInt64) async throws
}

struct SiteGatewayCloudTimeZoneContinuousTiming: SiteGatewayCloudTimeZoneTiming {
    private let origin = mach_continuous_time()

    private static let timebase: mach_timebase_info_data_t = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return info
    }()

    var nowNanoseconds: UInt64 {
        let current = mach_continuous_time()
        guard current >= origin else { return 0 }
        return Self.nanoseconds(fromMachTicks: current - origin)
    }

    func sleep(nanoseconds: UInt64) async throws {
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private static func nanoseconds(fromMachTicks ticks: UInt64) -> UInt64 {
        let numerator = UInt64(timebase.numer)
        let denominator = UInt64(timebase.denom)
        guard denominator > 0 else { return 0 }

        let wholeTicks = ticks / denominator
        let remainingTicks = ticks % denominator
        let (wholeNanoseconds, multiplicationOverflow) = wholeTicks.multipliedReportingOverflow(
            by: numerator
        )
        guard !multiplicationOverflow else { return UInt64.max }

        let fractionalNanoseconds = remainingTicks * numerator / denominator
        return Self.saturatedAdd(wholeNanoseconds, fractionalNanoseconds)
    }

    private static func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : result
    }
}

@MainActor
final class SiteGatewayCloudTimeZoneSyncCoordinator {

    nonisolated static let pollIntervalNanoseconds: UInt64 = 3_000_000_000
    nonisolated static let timeoutNanoseconds: UInt64 = 180_000_000_000

    private struct ActiveRun {
        let token: UUID
        let continuation: CheckedContinuation<SiteGatewayCloudTimeZoneBatchState?, Never>
        var state: SiteGatewayCloudTimeZoneBatchState
        let onUpdate: @MainActor (SiteGatewayCloudTimeZoneBatchState) -> Void
    }

    private let api: SiteGatewayCloudTimeZoneAPI
    private let timing: SiteGatewayCloudTimeZoneTiming
    private let pollIntervalNanoseconds: UInt64
    private let timeoutNanoseconds: UInt64
    private var activeRun: ActiveRun?
    private var submitTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?

    init(
        api: SiteGatewayCloudTimeZoneAPI,
        timing: SiteGatewayCloudTimeZoneTiming,
        pollIntervalNanoseconds: UInt64 = pollIntervalNanoseconds,
        timeoutNanoseconds: UInt64 = timeoutNanoseconds
    ) {
        self.api = api
        self.timing = timing
        self.pollIntervalNanoseconds = pollIntervalNanoseconds
        self.timeoutNanoseconds = timeoutNanoseconds
    }

    func run(
        siteID: String,
        initialState: SiteGatewayCloudTimeZoneBatchState,
        onUpdate: @escaping @MainActor (SiteGatewayCloudTimeZoneBatchState) -> Void
    ) async -> SiteGatewayCloudTimeZoneBatchState? {
        cancel()
        let requestMACs = initialState.requestMACs
        guard !requestMACs.isEmpty else { return initialState }

        let token = UUID()
        return await withTaskCancellationHandler(operation: {
            await withCheckedContinuation { continuation in
                activeRun = ActiveRun(
                    token: token,
                    continuation: continuation,
                    state: initialState,
                    onUpdate: onUpdate
                )
                submitTask = Task { [weak self] in
                    guard let self else { return }
                    do {
                        let requestID = try await self.api.submit(
                            siteID: siteID,
                            gatewayMACs: requestMACs
                        )
                        self.handleSubmitResponse(requestID: requestID, token: token)
                    } catch {
                        self.handleSubmitFailure(token: token)
                    }
                }
            }
        }, onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel(token: token)
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
        activeRun.continuation.resume(returning: nil)
    }

    private func cancel(token: UUID) {
        guard activeRun?.token == token else { return }
        cancel()
    }

    private func handleSubmitResponse(requestID: Int64, token: UUID) {
        guard activeRun?.token == token else { return }
        guard requestID > 0 else {
            handleSubmitFailure(token: token)
            return
        }

        let deadlineNanoseconds = Self.saturatedAdd(
            timing.nowNanoseconds,
            timeoutNanoseconds
        )
        timeoutTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.timing.sleep(nanoseconds: self.timeoutNanoseconds)
            } catch {
                return
            }
            self.timeout(token: token)
        }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.poll(
                requestID: requestID,
                deadlineNanoseconds: deadlineNanoseconds,
                token: token
            )
        }
    }

    private func handleSubmitFailure(token: UUID) {
        failPushingAndFinish(token: token)
    }

    private func poll(
        requestID: Int64,
        deadlineNanoseconds: UInt64,
        token: UUID
    ) async {
        while isActive(token: token) {
            do {
                try await timing.sleep(nanoseconds: pollIntervalNanoseconds)
            } catch {
                return
            }

            guard isActive(token: token) else { return }
            guard timing.nowNanoseconds < deadlineNanoseconds else {
                failPushingAndFinish(token: token)
                return
            }

            let snapshots: [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]
            do {
                guard timing.nowNanoseconds < deadlineNanoseconds else {
                    failPushingAndFinish(token: token)
                    return
                }
                snapshots = try await api.statuses(requestID: requestID)
            } catch {
                guard isActive(token: token) else { return }
                guard timing.nowNanoseconds < deadlineNanoseconds else {
                    failPushingAndFinish(token: token)
                    return
                }
                continue
            }

            guard isActive(token: token) else { return }
            guard timing.nowNanoseconds < deadlineNanoseconds else {
                failPushingAndFinish(token: token)
                return
            }
            apply(snapshots, token: token)
        }
    }

    private func apply(
        _ snapshots: [SiteGatewayCloudTimeZoneRemoteStatusSnapshot],
        token: UUID
    ) {
        guard var activeRun, activeRun.token == token else { return }
        let previousState = activeRun.state
        activeRun.state.apply(snapshots)
        let state = activeRun.state
        self.activeRun = activeRun

        if state != previousState {
            activeRun.onUpdate(state)
        }
        guard state.canDismiss else { return }
        finish(token: token, result: state)
    }

    private func timeout(token: UUID) {
        guard isActive(token: token) else { return }
        failPushingAndFinish(token: token)
    }

    private func failPushingAndFinish(token: UUID) {
        guard var activeRun, activeRun.token == token else { return }
        let previousState = activeRun.state
        activeRun.state.failPushing()
        let state = activeRun.state
        self.activeRun = activeRun

        if state != previousState {
            activeRun.onUpdate(state)
        }
        finish(token: token, result: state)
    }

    private func finish(
        token: UUID,
        result: SiteGatewayCloudTimeZoneBatchState
    ) {
        guard let activeRun, activeRun.token == token else { return }
        self.activeRun = nil
        cancelTasks()
        activeRun.continuation.resume(returning: result)
    }

    private func isActive(token: UUID) -> Bool {
        activeRun?.token == token
    }

    private func cancelTasks() {
        submitTask?.cancel()
        pollTask?.cancel()
        timeoutTask?.cancel()
        submitTask = nil
        pollTask = nil
        timeoutTask = nil
    }

    private nonisolated static func saturatedAdd(_ lhs: UInt64, _ rhs: UInt64) -> UInt64 {
        let (result, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? UInt64.max : result
    }
}
