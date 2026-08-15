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
}

enum SiteTimeZoneReviewState: Equatable {
    case hidden
    case review(
        serverTimezone: SiteTimeZoneValue,
        gatewayCount: Int
    )
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
        func summary(targetOffsetMinutes: Int) -> SiteEntryGatewaySummary {
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
            guard case .pending = gateway else { return .noAction }
            return .showGatewayStatus(timezone: target, gateway: gateway)
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

    private static func gatewaySummary(
        remote: SiteEntryTimeZoneRemoteSnapshot,
        targetOffsetMinutes: Int,
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
        let targets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: targetOffsetMinutes,
            remote: remote,
            localByGatewayID: localTargets
        )
        guard !targets.isEmpty else { return .noGateways }
        let pendingCount = targets.filter(\.requiresSync).count
        return pendingCount > 0 ? .pending(pendingCount) : .inSync
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
        guard let value, TimeZone(identifier: value.ianaId) != nil else {
            return nil
        }
        return value
    }
}
