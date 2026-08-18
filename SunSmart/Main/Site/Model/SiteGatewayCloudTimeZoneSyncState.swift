//
//  SiteGatewayCloudTimeZoneSyncState.swift
//  SunSmart
//
//  Created by One on 2026/8/15.
//

import Foundation

enum SiteGatewayCloudTimeZoneItemStatus: Equatable {
    case pushing
    case synced
    case failed
}

enum SiteGatewayCloudTimeZoneRemoteStatus: Hashable {
    case requested
    case succeed
    case failed
    case expired
}

struct SiteGatewayCloudTimeZoneRemoteStatusSnapshot: Equatable {
    let id: String
    let statuses: Set<SiteGatewayCloudTimeZoneRemoteStatus>
}

struct SiteGatewayCloudTimeZoneItem: Equatable, Identifiable {
    let id: String
    let requestMAC: String
    let displayName: String
    var status: SiteGatewayCloudTimeZoneItemStatus
}

struct SiteGatewayCloudTimeZoneBatchState: Equatable {
    private(set) var items: [SiteGatewayCloudTimeZoneItem]

    init(targets: [SiteGatewayCloudTimeZoneTarget]) {
        items = targets.map { target in
            SiteGatewayCloudTimeZoneItem(
                id: target.id,
                requestMAC: target.requestMAC,
                displayName: target.displayName,
                status: target.requiresSync ? .pushing : .synced
            )
        }
    }

    var authorizedCount: Int {
        items.count
    }

    var requestMACs: [String] {
        items
            .filter { $0.status == .pushing }
            .map(\.requestMAC)
    }

    var hasPushing: Bool {
        items.contains { $0.status == .pushing }
    }

    var failedCount: Int {
        items.reduce(into: 0) { count, item in
            if item.status == .failed {
                count += 1
            }
        }
    }

    var canDismiss: Bool {
        !hasPushing
    }

    mutating func apply(_ snapshots: [SiteGatewayCloudTimeZoneRemoteStatusSnapshot]) {
        var statusesByID = [String: Set<SiteGatewayCloudTimeZoneRemoteStatus>]()
        for snapshot in snapshots {
            guard let id = normalizedID(snapshot.id) else { continue }
            statusesByID[id, default: []].formUnion(snapshot.statuses)
        }

        for index in items.indices {
            guard
                items[index].status == .pushing,
                let id = normalizedID(items[index].id),
                let statuses = statusesByID[id]
            else {
                continue
            }

            let hasSucceed = statuses.contains(.succeed)
            let hasFailure = statuses.contains(.failed) || statuses.contains(.expired)
            guard !(hasSucceed && hasFailure) else { continue }

            if hasSucceed {
                items[index].status = .synced
            } else if hasFailure {
                items[index].status = .failed
            }
        }
    }

    mutating func failPushing() {
        for index in items.indices where items[index].status == .pushing {
            items[index].status = .failed
        }
    }

    private func normalizedID(_ value: String) -> String? {
        SiteGatewayAccessScope.normalize(value)
    }
}

struct SiteGatewayTimeZoneReviewContext: Equatable {
    let targetTimeZone: SiteTimeZoneValue
    let failedGatewayIDs: Set<String>

    init(
        targetTimeZone: SiteTimeZoneValue,
        failedGatewayIDs: Set<String>
    ) {
        self.targetTimeZone = targetTimeZone
        self.failedGatewayIDs = Set(
            failedGatewayIDs.compactMap(SiteGatewayAccessScope.normalize)
        )
    }

    static func make(
        targetTimeZone: SiteTimeZoneValue,
        terminalState: SiteGatewayCloudTimeZoneBatchState
    ) -> SiteGatewayTimeZoneReviewContext? {
        let failedIDs = Set<String>(
            terminalState.items.compactMap { item in
                guard item.status == .failed else { return nil }
                return SiteGatewayAccessScope.normalize(item.id)
            }
        )
        guard !failedIDs.isEmpty else { return nil }
        return SiteGatewayTimeZoneReviewContext(
            targetTimeZone: targetTimeZone,
            failedGatewayIDs: failedIDs
        )
    }

    func reconciled(
        with remote: SiteEntryTimeZoneRemoteSnapshot
    ) -> SiteGatewayTimeZoneReviewContext? {
        let scope = SiteGatewayAccessScope.resolve(remote: remote)
        let authorizedFailedIDs = failedGatewayIDs.filter {
            scope.contains(normalizedGatewayID: $0)
        }
        let acknowledgedIDs = SiteGatewayCloudTimeZoneConfirmationPolicy
            .acknowledgedGatewayIDs(
                confirmedOffsetMinutesByGatewayID: Dictionary(
                    uniqueKeysWithValues: authorizedFailedIDs.map {
                        ($0, targetTimeZone.offsetMinutes)
                    }
                ),
                remote: remote.gateways
            )
        let remainingIDs = authorizedFailedIDs.subtracting(acknowledgedIDs)
        guard !remainingIDs.isEmpty else { return nil }
        return SiteGatewayTimeZoneReviewContext(
            targetTimeZone: targetTimeZone,
            failedGatewayIDs: remainingIDs
        )
    }

    func reconciled(
        confirmedOffsetMinutesByGatewayID: [String: Int]
    ) -> SiteGatewayTimeZoneReviewContext? {
        let confirmedByID = confirmedOffsetMinutesByGatewayID.reduce(
            into: [String: Int]()
        ) { result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key) else { return }
            result[id] = pair.value
        }
        let remainingIDs = failedGatewayIDs.filter {
            confirmedByID[$0] != targetTimeZone.offsetMinutes
        }
        guard !remainingIDs.isEmpty else { return nil }
        return SiteGatewayTimeZoneReviewContext(
            targetTimeZone: targetTimeZone,
            failedGatewayIDs: Set(remainingIDs)
        )
    }
}

enum SiteGatewayTimeZoneReviewProjection: Equatable {
    case hidden
    case explicit(SiteGatewayTimeZoneReviewContext)
    case remote(SiteTimeZoneValue)

    var targetTimeZone: SiteTimeZoneValue? {
        switch self {
        case .hidden:
            return nil
        case .explicit(let context):
            return context.targetTimeZone
        case .remote(let timeZone):
            return timeZone
        }
    }

    var explicitContext: SiteGatewayTimeZoneReviewContext? {
        guard case .explicit(let context) = self else { return nil }
        return context
    }
}

enum SiteGatewayTimeZoneReviewProjectionPolicy {
    static func project(
        localTimeZone: SiteTimeZoneValue?,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        explicitContext: SiteGatewayTimeZoneReviewContext?
    ) -> SiteGatewayTimeZoneReviewProjection {
        guard let localTimeZone,
              let remoteTimeZone = remote.timezone,
              TimeZone(identifier: localTimeZone.ianaId) != nil,
              TimeZone(identifier: remoteTimeZone.ianaId) != nil,
              SiteGatewayAccessScope.resolve(remote: remote) != .visitor else {
            return .hidden
        }
        if let explicitContext {
            guard localTimeZone == explicitContext.targetTimeZone else {
                return .hidden
            }
            return .explicit(explicitContext)
        }
        guard localTimeZone == remoteTimeZone else { return .hidden }
        return .remote(remoteTimeZone)
    }
}
