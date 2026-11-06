//
//  SiteEntryTimeZoneSyncPolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/12.
//

import Foundation

struct SiteEntryTimeZoneLocalSnapshot: Equatable {
    let siteId: String
    let values: SitePropsValues
    let lastUpdate: Int64
    let lastUploadCloudTimestamp: Int64?
    let pending: SitePropsPendingState

    var timezone: SiteTimeZoneValue? { values.timezone }
}

enum SiteEntryGatewaySummary: Equatable {
    case noGateways
    case pending(Int)
    case inSync
    case unavailable
}

/// One comparison instant, shared by the entry result, header and review route.
/// A missing Site offset is not evidence that a Gateway needs another TimeSet.
struct SiteEntryGatewayEvaluation: Equatable {
    let targetOffsetMinutes: Int?
    let targets: [SiteGatewayCloudTimeZoneTarget]
    let pendingGatewayIDs: Set<String>
    let summary: SiteEntryGatewaySummary

    init(
        targetOffsetMinutes: Int?,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        localByGatewayID: [String: SiteGatewayCloudTimeZoneLocalSnapshot] = [:],
        confirmedOffsetMinutesByGatewayID: [String: Int] = [:],
        requiredGatewayIDs: Set<String>? = nil
    ) {
        self.targetOffsetMinutes = targetOffsetMinutes
        targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: targetOffsetMinutes,
            remote: remote,
            localByGatewayID: localByGatewayID,
            confirmedOffsetMinutesByGatewayID: confirmedOffsetMinutesByGatewayID
        )
        let requiredIDs = requiredGatewayIDs.map { Set($0.compactMap(SiteGatewayAccessScope.normalize)) }
        if targets.isEmpty {
            pendingGatewayIDs = []
            summary = .noGateways
        } else if targetOffsetMinutes == nil {
            pendingGatewayIDs = []
            summary = .unavailable
        } else {
            pendingGatewayIDs = Set(targets.filter {
                $0.requiresSync && (requiredIDs?.contains($0.id) ?? true)
            }.map(\.id))
            summary = pendingGatewayIDs.isEmpty ? .inSync : .pending(pendingGatewayIDs.count)
        }
    }
}

enum SiteGatewayReviewUnavailableReason: Equatable {
    case missingSnapshot
    case changedContext
    case offsetUnavailable
    case missingNetwork
    case missingNavigation
}

enum SiteGatewayReviewRouteDecision: Equatable {
    case ready
    case noPending
    case unavailable(SiteGatewayReviewUnavailableReason)

    static func decide(
        evaluation: SiteEntryGatewayEvaluation,
        hasMeshNetwork: Bool,
        hasNavigationController: Bool
    ) -> Self {
        guard evaluation.summary != .unavailable else { return .unavailable(.offsetUnavailable) }
        guard !evaluation.pendingGatewayIDs.isEmpty else { return .noPending }
        guard hasMeshNetwork else { return .unavailable(.missingNetwork) }
        guard hasNavigationController else { return .unavailable(.missingNavigation) }
        return .ready
    }
}

enum SiteTimeZoneReviewState: Equatable {
    case hidden
    case review(
        serverTimezone: SiteTimeZoneValue,
        gatewayCount: Int
    )
    var displayOffset: String? {
        guard case .review(let timezone, _) = self else { return nil }
        return timezone.displayOffset
    }

}

enum SiteEntryTimeZoneDecision: Equatable {
    case noAction
    case showGatewayStatus(
        timezone: SiteTimeZoneValue,
        gateway: SiteEntryGatewaySummary
    )
    case useRemote(
        timezone: SiteTimeZoneValue,
        remoteTimestamp: Int64,
        gateway: SiteEntryGatewaySummary
    )
    case useLocal(snapshot: SitePropsUpdateSnapshot, gateway: SiteEntryGatewaySummary)
    case useVisitorRemote(state: SitePropsLocalState)
}

enum SiteEntryTimeZoneSiteResult: Equatable {
    case alreadyInSync
    case updatedFromServer
    case updatedToServer
    case failedToUpdateServer
}

struct SiteEntryTimeZoneResult: Equatable {
    let timezone: SiteTimeZoneValue
    let site: SiteEntryTimeZoneSiteResult
    let gateway: SiteEntryGatewaySummary

    var shouldPresent: Bool {
        guard site == .alreadyInSync else { return true }
        switch gateway {
        case .pending, .unavailable: return true
        case .noGateways, .inSync: return false
        }
    }
}

enum SiteEntryTimeZoneSyncPolicy {

    static func reviewState(
        remote: SiteEntryTimeZoneRemoteSnapshot,
        localDirtyOffsetMinutesByGatewayID: [String: Int] = [:]
    ) -> SiteTimeZoneReviewState? {
        guard let serverTimezone = validated(remote.timezone) else {
            return nil
        }
        return reviewState(
            remote: remote,
            serverTimezone: serverTimezone,
            localDirtyOffsetMinutesByGatewayID: localDirtyOffsetMinutesByGatewayID
        )
    }

    static func reviewState(
        remote: SiteEntryTimeZoneRemoteSnapshot,
        serverTimezone: SiteTimeZoneValue,
        localDirtyOffsetMinutesByGatewayID: [String: Int] = [:]
    ) -> SiteTimeZoneReviewState {
        let gateway = gatewaySummary(
            remote: remote,
            targetOffsetMinutes: serverTimezone.offsetMinutes,
            localDirtyOffsetMinutesByGatewayID: localDirtyOffsetMinutesByGatewayID
        )
        guard case let .pending(count) = gateway else {
            return .hidden
        }
        return .review(
            serverTimezone: serverTimezone,
            gatewayCount: count
        )
    }

    static func decide(
        local: SiteEntryTimeZoneLocalSnapshot,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        now: Int64,
        localDirtyOffsetMinutesByGatewayID: [String: Int] = [:]
    ) -> SiteEntryTimeZoneDecision {
        let scope = SiteGatewayAccessScope.resolve(remote: remote)
        let localTimezone = validated(local.timezone)
        let remoteTimezone = validated(remote.timezone)
        func summary(targetOffsetMinutes: Int?) -> SiteEntryGatewaySummary {
            gatewaySummary(
                remote: remote,
                targetOffsetMinutes: targetOffsetMinutes,
                localDirtyOffsetMinutesByGatewayID: localDirtyOffsetMinutesByGatewayID
            )
        }

        if case .visitor = scope {
            return visitorDecision(
                local: local,
                remote: remote,
                remoteTimezone: remoteTimezone
            )
        }

        if localTimezone == remoteTimezone {
            guard let target = localTimezone else { return .noAction }
            let gateway = summary(targetOffsetMinutes: target.offsetMinutes)
            switch gateway {
            case .pending, .unavailable:
                return .showGatewayStatus(timezone: target, gateway: gateway)
            case .noGateways, .inSync:
                return .noAction
            }
        }

        switch (localTimezone, remoteTimezone) {
        case let (nil, remoteTimezone?):
            return .useRemote(
                timezone: remoteTimezone,
                remoteTimestamp: remote.timestamp,
                gateway: summary(targetOffsetMinutes: remoteTimezone.offsetMinutes)
            )

        case let (localTimezone?, nil):
            return localDecision(
                local: local,
                timezone: localTimezone,
                remoteTimestamp: remote.timestamp,
                now: now,
                gateway: summary(targetOffsetMinutes: localTimezone.offsetMinutes)
            )

        case let (localTimezone?, remoteTimezone?):
            if remote.timestamp > local.lastUpdate {
                return .useRemote(
                    timezone: remoteTimezone,
                    remoteTimestamp: remote.timestamp,
                    gateway: summary(targetOffsetMinutes: remoteTimezone.offsetMinutes)
                )
            }
            return localDecision(
                local: local,
                timezone: localTimezone,
                remoteTimestamp: remote.timestamp,
                now: now,
                gateway: summary(targetOffsetMinutes: localTimezone.offsetMinutes)
            )

        case (nil, nil):
            return .noAction
        }
    }

    private static func visitorDecision(
        local: SiteEntryTimeZoneLocalSnapshot,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        remoteTimezone: SiteTimeZoneValue?
    ) -> SiteEntryTimeZoneDecision {
        guard let remoteTimezone else { return .noAction }
        let values = SitePropsValues(
            siteName: remote.values.siteName,
            imageId: remote.values.imageId,
            timezone: remoteTimezone
        )
        let state = SitePropsLocalState(
            values: values,
            lastUpdate: remote.timestamp,
            lastUploadCloudTimestamp: remote.timestamp,
            pending: SitePropsPendingState(fields: [], timestamp: nil)
        )
        let current = SitePropsLocalState(
            values: local.values,
            lastUpdate: local.lastUpdate,
            lastUploadCloudTimestamp: local.lastUploadCloudTimestamp,
            pending: local.pending
        )
        return state == current ? .noAction : .useVisitorRemote(state: state)
    }

    static func gatewaySummary(
        remote: SiteEntryTimeZoneRemoteSnapshot,
        targetOffsetMinutes: Int?,
        localDirtyOffsetMinutesByGatewayID: [String: Int]
    ) -> SiteEntryGatewaySummary {
        let localTargets = localDirtyOffsetMinutesByGatewayID.reduce(
            into: [String: SiteGatewayCloudTimeZoneLocalSnapshot]()
        ) { result, pair in
            result[pair.key] = SiteGatewayCloudTimeZoneLocalSnapshot(
                displayName: "",
                dirtyOffsetMinutes: pair.value
            )
        }
        return SiteEntryGatewayEvaluation(
            targetOffsetMinutes: targetOffsetMinutes,
            remote: remote,
            localByGatewayID: localTargets
        ).summary
    }

    private static func localDecision(
        local: SiteEntryTimeZoneLocalSnapshot,
        timezone: SiteTimeZoneValue,
        remoteTimestamp: Int64,
        now: Int64,
        gateway: SiteEntryGatewaySummary
    ) -> SiteEntryTimeZoneDecision {
        let currentTimestamp = max(local.lastUpdate, remoteTimestamp)
        let timestamp = SitePropsEditPolicy.nextTimestamp(
            now: now,
            current: currentTimestamp
        )
        let values = SitePropsValues(
            siteName: local.values.siteName,
            imageId: local.values.imageId,
            timezone: timezone
        )
        return .useLocal(
            snapshot: SitePropsUpdateSnapshot(
                siteId: local.siteId,
                fields: [.timezone],
                values: values,
                timestamp: timestamp
            ),
            gateway: gateway
        )
    }

    private static func validated(_ value: SiteTimeZoneValue?) -> SiteTimeZoneValue? {
        guard let value else {
            return nil
        }
        return value
    }
}
