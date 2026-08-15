//
//  SyncGatewaysContext.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

#if canImport(NordicSigMeshSDK)
import NordicSigMeshSDK
#endif

struct SyncGatewayRuntimeAvailability: Equatable {
    let hasGatewayModel: Bool
    let hasNode: Bool
}

struct SyncGatewayAuthorizedCandidate: Equatable {
    let id: String
    let displayName: String
    let remoteOrder: Int
    let effectiveOffsetMinutes: Int?
    let requiresSync: Bool
}

struct SyncGatewayTargetDescriptor: Equatable {
    let id: String
    let displayName: String?
    let remoteOrder: Int
    let initialOffsetMinutes: Int?
    let isSyncable: Bool
}

enum SyncGatewayRuntimeDescriptorPolicy {
    static func make(
        candidates: [SyncGatewayAuthorizedCandidate],
        localAvailabilityByGatewayID: [String: SyncGatewayRuntimeAvailability],
        requiredGatewayIDs: Set<String>? = nil
    ) -> [SyncGatewayTargetDescriptor] {
        let normalizedAvailability = localAvailabilityByGatewayID.reduce(
            into: [String: SyncGatewayRuntimeAvailability]()
        ) {
            result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key), result[id] == nil else {
                return
            }
            result[id] = pair.value
        }
        let requiredIDs = requiredGatewayIDs.map {
            Set($0.compactMap(SiteGatewayAccessScope.normalize))
        }
        var seen: Set<String> = []

        return candidates.compactMap { candidate in
            guard let id = SiteGatewayAccessScope.normalize(candidate.id),
                  seen.insert(id).inserted else {
                return nil
            }
            if let requiredIDs {
                guard requiredIDs.contains(id) else { return nil }
            } else if !candidate.requiresSync {
                return nil
            }
            let displayName = candidate.displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            let availability = normalizedAvailability[id]
            return SyncGatewayTargetDescriptor(
                id: id,
                displayName: displayName.isEmpty ? nil : displayName,
                remoteOrder: candidate.remoteOrder,
                initialOffsetMinutes: candidate.effectiveOffsetMinutes,
                isSyncable: availability?.hasGatewayModel == true &&
                    availability?.hasNode == true
            )
        }
    }
}

#if canImport(NordicSigMeshSDK)
struct SyncGatewayRuntimeTarget {
    let descriptor: SyncGatewayTargetDescriptor
    let gateway: GatewayModel?
    let node: Node?
}

struct SyncGatewaysContext {
    let sessionID: UUID
    let siteID: String
    let siteName: String
    let targetTimeZone: SiteTimeZoneValue
    let targets: [SyncGatewayRuntimeTarget]
    let allowedNetworkKeyIndexesByNodeAddress: [UInt16: Set<UInt16>]
}

enum SyncGatewaysContextBuilder {
    static func makeTargets(
        targetTimeZone: SiteTimeZoneValue,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        meshNetwork: MeshNetwork,
        gatewayModels: [GatewayModel],
        confirmedOffsetMinutesByGatewayID: [String: Int] = [:],
        requiredGatewayIDs: Set<String>? = nil
    ) -> [SyncGatewayRuntimeTarget] {
        var modelsByID: [String: GatewayModel] = [:]
        gatewayModels.forEach { model in
            guard let id = SiteGatewayAccessScope.normalize(model.mac),
                  modelsByID[id] == nil else {
                return
            }
            modelsByID[id] = model
        }

        let localSnapshots = modelsByID.reduce(
            into: [String: SiteGatewayCloudTimeZoneLocalSnapshot]()
        ) {
            result, pair in
            let node = pair.value.resolveNode(in: meshNetwork)
            result[pair.key] = SiteGatewayCloudTimeZoneLocalSnapshot(
                displayName: pair.value.name,
                dirtyOffsetMinutes: pair.value.needUploadCloud
                    ? (node?.timezone?.secondsFromGMT()).map { $0 / 60 }
                    : nil
            )
        }
        let entryTargets = SiteGatewayCloudTimeZoneTargetBuilder.build(
            targetOffsetMinutes: targetTimeZone.offsetMinutes,
            remote: remote,
            localByGatewayID: localSnapshots,
            confirmedOffsetMinutesByGatewayID:
                confirmedOffsetMinutesByGatewayID
        )
        let availability = modelsByID.reduce(
            into: [String: SyncGatewayRuntimeAvailability]()
        ) { result, pair in
            result[pair.key] = SyncGatewayRuntimeAvailability(
                hasGatewayModel: true,
                hasNode: pair.value.resolveNode(in: meshNetwork) != nil
            )
        }
        let descriptors = SyncGatewayRuntimeDescriptorPolicy.make(
            candidates: entryTargets.map { target in
                SyncGatewayAuthorizedCandidate(
                    id: target.id,
                    displayName: target.displayName,
                    remoteOrder: target.remoteOrder,
                    effectiveOffsetMinutes: target.effectiveOffsetMinutes,
                    requiresSync: target.requiresSync
                )
            },
            localAvailabilityByGatewayID: availability,
            requiredGatewayIDs: requiredGatewayIDs
        )
        return descriptors.map { descriptor in
            let gateway = modelsByID[descriptor.id]
            return SyncGatewayRuntimeTarget(
                descriptor: descriptor,
                gateway: gateway,
                node: gateway?.resolveNode(in: meshNetwork)
            )
        }
    }

    static func make(
        siteID: String,
        siteName: String,
        targetTimeZone: SiteTimeZoneValue,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        meshNetwork: MeshNetwork,
        gatewayModels: [GatewayModel],
        confirmedOffsetMinutesByGatewayID: [String: Int] = [:],
        requiredGatewayIDs: Set<String>? = nil
    ) -> SyncGatewaysContext {
        let targets = makeTargets(
            targetTimeZone: targetTimeZone,
            remote: remote,
            meshNetwork: meshNetwork,
            gatewayModels: gatewayModels,
            confirmedOffsetMinutesByGatewayID:
                confirmedOffsetMinutesByGatewayID,
            requiredGatewayIDs: requiredGatewayIDs
        )

        let keyResolution = GatewayFirmwareScanNetworkKeyScopePolicy.resolve(
            primaryNetworkKeyIndex: meshNetwork.networkKeys.first(where: \.isPrimary)?.index,
            availableNetworkKeyIndexes: Set(meshNetwork.networkKeys.map(\.index)),
            boundNetworkKeyIndexByApplicationKeyIndex: meshNetwork.applicationKeys.reduce(
                into: [UInt16: UInt16]()
            ) { result, applicationKey in
                result[applicationKey.index] = applicationKey.boundNetworkKeyIndex
            },
            gateways: targets.compactMap { target in
                guard let gateway = target.gateway, let node = target.node else { return nil }
                return GatewayFirmwareScanNetworkKeyScopeInput(
                    address: node.primaryUnicastAddress,
                    associatedApplicationKeyIndexes: gateway.associatedSpaces.map(\.appKeyIndex)
                )
            }
        )

        return SyncGatewaysContext(
            sessionID: UUID(),
            siteID: siteID,
            siteName: siteName,
            targetTimeZone: targetTimeZone,
            targets: targets,
            allowedNetworkKeyIndexesByNodeAddress: keyResolution.allowedNetworkKeyIndexesByAddress
        )
    }
}
#endif
