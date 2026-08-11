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
            scope: SiteGatewayAccessScope.resolve(remote: remote),
            gateways: remote.gateways,
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
                scope: scope,
                gateways: remote.gateways,
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
        scope: SiteGatewayAccessScope,
        gateways: [SiteEntryGatewayTimeZoneSnapshot],
        targetOffsetMinutes: Int,
        localDirtyOffsetMinutesByGatewayID: [String: Int]
    ) -> SiteEntryGatewaySummary {
        let dirtyOffsets = localDirtyOffsetMinutesByGatewayID.reduce(into: [String: Int]()) {
            result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key) else { return }
            result[id] = pair.value
        }
        let totalCount: Int
        let pendingCount: Int

        switch scope {
        case .visitor:
            return .noGateways

        case .editor(let gatewayIds):
            totalCount = gatewayIds.count
            pendingCount = gatewayIds.reduce(into: 0) { count, id in
                if let dirtyOffset = dirtyOffsets[id] {
                    if dirtyOffset != targetOffsetMinutes { count += 1 }
                    return
                }
                let matches = gateways.filter { normalized($0.id) == id }
                if matches.isEmpty || matches.contains(where: { $0.offsetMinutes != targetOffsetMinutes }) {
                    count += 1
                }
            }

        case .owner:
            var identified: [String: [SiteEntryGatewayTimeZoneSnapshot]] = [:]
            var anonymous: [SiteEntryGatewayTimeZoneSnapshot] = []
            gateways.forEach { gateway in
                if let id = normalized(gateway.id) {
                    identified[id, default: []].append(gateway)
                } else {
                    anonymous.append(gateway)
                }
            }
            totalCount = identified.count + anonymous.count
            pendingCount = identified.reduce(into: 0) { count, entry in
                if let dirtyOffset = dirtyOffsets[entry.key] {
                    if dirtyOffset != targetOffsetMinutes { count += 1 }
                } else if entry.value.contains(where: { $0.offsetMinutes != targetOffsetMinutes }) {
                    count += 1
                }
            } + anonymous.filter { $0.offsetMinutes != targetOffsetMinutes }.count
        }

        guard totalCount > 0 else { return .noGateways }
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

    private static func normalized(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return value.isEmpty ? nil : value
    }
}
