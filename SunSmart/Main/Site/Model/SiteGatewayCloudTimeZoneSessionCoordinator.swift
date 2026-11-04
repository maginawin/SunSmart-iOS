//
//  SiteGatewayCloudTimeZoneSessionCoordinator.swift
//  SunSmart
//
//  Created by One on 2026/8/16.
//

import Foundation

struct SiteGatewayCloudTimeZoneSessionInput: Equatable {
    let siteID: String
    let targetTimeZone: SiteTimeZoneValue
    let targetOffsetMinutes: Int?
    let targets: [SiteGatewayCloudTimeZoneTarget]
    let confirmedOffsetMinutesByGatewayID: [String: Int]

    init(
        siteID: String,
        targetTimeZone: SiteTimeZoneValue,
        targets: [SiteGatewayCloudTimeZoneTarget],
        confirmedOffsetMinutesByGatewayID: [String: Int]
    ) {
        self.siteID = siteID
        self.targetTimeZone = targetTimeZone
        self.targetOffsetMinutes = targetTimeZone.offsetMinutes
        self.targets = targets
        self.confirmedOffsetMinutesByGatewayID =
            confirmedOffsetMinutesByGatewayID
    }

    init(
        siteID: String,
        targetTimeZone: SiteTimeZoneValue,
        remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot,
        localSnapshotsByID: [String: SiteGatewayCloudTimeZoneLocalSnapshot],
        confirmedOffsetMinutesByGatewayID: [String: Int]
    ) {
        self.init(
            siteID: siteID,
            targetTimeZone: targetTimeZone,
            targets: SiteGatewayCloudTimeZoneTargetBuilder.build(
                targetOffsetMinutes: targetTimeZone.offsetMinutes,
                remote: remoteSnapshot,
                localByGatewayID: localSnapshotsByID,
                confirmedOffsetMinutesByGatewayID:
                    confirmedOffsetMinutesByGatewayID
            ),
            confirmedOffsetMinutesByGatewayID:
                confirmedOffsetMinutesByGatewayID
        )
    }
}

struct SiteGatewayCloudTimeZoneSessionResult: Equatable {
    let initialState: SiteGatewayCloudTimeZoneBatchState
    let terminalState: SiteGatewayCloudTimeZoneBatchState
    let confirmedOffsetMinutesByGatewayID: [String: Int]
    let reviewContext: SiteGatewayTimeZoneReviewContext?
}

@MainActor
final class SiteGatewayCloudTimeZoneSessionCoordinator {

    private let syncCoordinator: SiteGatewayCloudTimeZoneSyncCoordinator
    private var activeToken: UUID?

    init(syncCoordinator: SiteGatewayCloudTimeZoneSyncCoordinator) {
        self.syncCoordinator = syncCoordinator
    }

    func run(
        input: SiteGatewayCloudTimeZoneSessionInput,
        onUpdate: @escaping @MainActor (SiteGatewayCloudTimeZoneBatchState) -> Void
    ) async -> SiteGatewayCloudTimeZoneSessionResult? {
        let token = UUID()
        cancel()
        activeToken = token
        defer {
            if activeToken == token {
                activeToken = nil
            }
        }

        let initialState = SiteGatewayCloudTimeZoneBatchState(
            targets: input.targets
        )
        onUpdate(initialState)
        guard activeToken == token else { return nil }

        var terminalState: SiteGatewayCloudTimeZoneBatchState
        if input.targetOffsetMinutes == nil {
            terminalState = initialState
            terminalState.failPushing()
        } else if initialState.requestMACs.isEmpty {
            terminalState = initialState
        } else {
            guard let result = await syncCoordinator.run(
                siteID: input.siteID,
                initialState: initialState,
                onUpdate: { [weak self] state in
                    guard self?.activeToken == token else { return }
                    onUpdate(self?.validated(state, input: input) ?? state)
                }
            ), activeToken == token else {
                return nil
            }
            terminalState = result
        }

        terminalState = validated(terminalState, input: input)
        return SiteGatewayCloudTimeZoneSessionResult(
            initialState: initialState,
            terminalState: terminalState,
            confirmedOffsetMinutesByGatewayID: confirmations(
                input: input,
                initialState: initialState,
                terminalState: terminalState
            ),
            reviewContext: SiteGatewayTimeZoneReviewContext.make(
                targetTimeZone: input.targetTimeZone,
                terminalState: terminalState
            )
        )
    }

    private func validated(_ state: SiteGatewayCloudTimeZoneBatchState,
                           input: SiteGatewayCloudTimeZoneSessionInput) -> SiteGatewayCloudTimeZoneBatchState {
        guard input.targetTimeZone.offsetMinutes != input.targetOffsetMinutes else { return state }
        var current = state
        current.invalidate(ids: Set(state.items.map(\.id)))
        return current
    }

    func cancel() {
        activeToken = nil
        syncCoordinator.cancel()
    }

    private func confirmations(
        input: SiteGatewayCloudTimeZoneSessionInput,
        initialState: SiteGatewayCloudTimeZoneBatchState,
        terminalState: SiteGatewayCloudTimeZoneBatchState
    ) -> [String: Int] {
        guard let targetOffset = input.targetOffsetMinutes,
              input.targetTimeZone.offsetMinutes == targetOffset else { return input.confirmedOffsetMinutesByGatewayID }
        let initiallyPushingIDs = Set(
            initialState.items
                .filter { $0.status == .pushing }
                .map(\.id)
        )
        var confirmed = input.confirmedOffsetMinutesByGatewayID
        terminalState.items.forEach { item in
            guard initiallyPushingIDs.contains(item.id),
                  item.status == .synced else {
                return
            }
            confirmed[item.id] = targetOffset
        }
        return confirmed
    }
}
