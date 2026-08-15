//
//  SiteGatewayCloudTimeZoneLocalContext.swift
//  SunSmart
//
//  Created by One on 2026/8/16.
//

import Foundation
import NordicSigMeshSDK

struct SiteGatewayCloudTimeZoneLocalContext: Equatable {
    let snapshotsByID: [String: SiteGatewayCloudTimeZoneLocalSnapshot]
    let dirtyOverridesByID: [String: SyncGatewayDirtyTimeOverride]
}

@MainActor
enum SiteGatewayLocalTimeZoneContextBuilder {
    static func make(
        site: SiteData,
        targetTimeZone: SiteTimeZoneValue
    ) -> [SiteGatewayCloudTimeZoneTarget] {
        let meshNetwork = MeshNetwork.load(
            meshUUID: site.meshUUID,
            subnetworkId: site.meshNetworkId
        )
        let candidates = GatewayModel.load(siteId: site.id).map { gateway in
            let node = gateway.resolveNode(in: meshNetwork)
            return SiteGatewayLocalTimeZoneCandidate(
                requestMAC: gateway.mac,
                displayName: gateway.name,
                currentOffsetMinutes:
                    (node?.timezone?.secondsFromGMT()).map { $0 / 60 },
                canConfigure: site.canConfigureGateway(gateway)
            )
        }
        return SiteGatewayLocalTimeZoneTargetBuilder.build(
            targetOffsetMinutes: targetTimeZone.offsetMinutes,
            candidates: candidates
        )
    }
}

@MainActor
enum SiteGatewayCloudTimeZoneLocalContextBuilder {
    static func make(
        site: SiteData,
        remoteSnapshot: SiteEntryTimeZoneRemoteSnapshot,
        targetTimeZone: SiteTimeZoneValue
    ) -> SiteGatewayCloudTimeZoneLocalContext {
        let scope = SiteGatewayAccessScope.resolve(remote: remoteSnapshot)
        let authorizedGatewayIDs: Set<String>
        switch scope {
        case .owner:
            authorizedGatewayIDs = Set(
                remoteSnapshot.gateways.compactMap { gateway in
                    SiteGatewayAccessScope.normalize(gateway.id)
                }
            )
        case .editor(let gatewayIDs):
            authorizedGatewayIDs = gatewayIDs
        case .visitor:
            authorizedGatewayIDs = []
        }

        let remoteGatewaysByID = remoteSnapshot.gateways.reduce(
            into: [String: SiteEntryGatewayTimeZoneSnapshot]()
        ) { result, gateway in
            guard let id = SiteGatewayAccessScope.normalize(gateway.id),
                  result[id] == nil else {
                return
            }
            result[id] = gateway
        }
        let meshNetwork = MeshNetwork.load(
            meshUUID: site.meshUUID,
            subnetworkId: site.meshNetworkId
        )
        var namesByID: [String: String] = [:]
        var dirtyCandidates: [SyncGatewayDirtyTimeCandidate] = []

        GatewayModel.load(siteId: site.id).forEach { gateway in
            guard let id = SiteGatewayAccessScope.normalize(gateway.mac),
                  authorizedGatewayIDs.contains(id),
                  scope.contains(normalizedGatewayID: id),
                  namesByID[id] == nil else {
                return
            }
            let node = gateway.resolveNode(in: meshNetwork)
            namesByID[id] = gateway.name
            dirtyCandidates.append(
                SyncGatewayDirtyTimeCandidate(
                    id: id,
                    isCloudDirty: gateway.needUploadCloud,
                    localTimestamp: node?.timestamp ?? 0,
                    localOffsetMinutes:
                        (node?.timezone?.secondsFromGMT()).map { $0 / 60 },
                    remoteOffsetMinutes: remoteGatewaysByID[id]?.offsetMinutes
                )
            )
        }

        let dirtyOverridesByID = SyncGatewaysDirtyTimeOverridePolicy.capture(
            targetOffsetMinutes: targetTimeZone.offsetMinutes,
            candidates: dirtyCandidates
        )
        let snapshotsByID = namesByID.reduce(
            into: [String: SiteGatewayCloudTimeZoneLocalSnapshot]()
        ) { result, pair in
            result[pair.key] = SiteGatewayCloudTimeZoneLocalSnapshot(
                displayName: pair.value,
                dirtyOffsetMinutes: dirtyOverridesByID[pair.key]?.offsetMinutes
            )
        }
        return SiteGatewayCloudTimeZoneLocalContext(
            snapshotsByID: snapshotsByID,
            dirtyOverridesByID: dirtyOverridesByID
        )
    }
}
