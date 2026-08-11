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

struct SyncGatewayRemoteCandidate: Equatable {
    let id: String?
    let offsetMinutes: Int?
    let order: Int
}

struct SyncGatewayLocalCandidate: Equatable {
    let displayName: String
    let offsetMinutes: Int?
    let isCloudDirty: Bool
    let hasGatewayModel: Bool
    let hasNode: Bool
}

struct SyncGatewayTargetDescriptor: Equatable {
    let id: String
    let displayName: String?
    let remoteOrder: Int
    let initialOffsetMinutes: Int?
    let isSyncable: Bool
}

enum SyncGatewaysContextSelectionPolicy {
    static func select(
        scope: SiteGatewayAccessScope,
        targetOffsetMinutes: Int,
        remote: [SyncGatewayRemoteCandidate],
        local: [String: SyncGatewayLocalCandidate]
    ) -> [SyncGatewayTargetDescriptor] {
        guard scope != .visitor else { return [] }

        let normalizedLocal = local.reduce(into: [String: SyncGatewayLocalCandidate]()) {
            result, pair in
            guard let id = SiteGatewayAccessScope.normalize(pair.key), result[id] == nil else {
                return
            }
            result[id] = pair.value
        }
        var seen: Set<String> = []

        return remote.compactMap { candidate in
            guard let id = SiteGatewayAccessScope.normalize(candidate.id),
                  scope.contains(normalizedGatewayID: id),
                  seen.insert(id).inserted else {
                return nil
            }

            let localCandidate = normalizedLocal[id]
            let effectiveOffset = localCandidate?.isCloudDirty == true
                ? localCandidate?.offsetMinutes
                : candidate.offsetMinutes
            guard effectiveOffset != targetOffsetMinutes else {
                return nil
            }

            let displayName = localCandidate?.displayName.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
            return SyncGatewayTargetDescriptor(
                id: id,
                displayName: displayName?.isEmpty == false ? displayName : nil,
                remoteOrder: candidate.order,
                initialOffsetMinutes: effectiveOffset,
                isSyncable: localCandidate?.hasGatewayModel == true &&
                    localCandidate?.hasNode == true
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
    static func make(
        siteID: String,
        siteName: String,
        targetTimeZone: SiteTimeZoneValue,
        remote: SiteEntryTimeZoneRemoteSnapshot,
        meshNetwork: MeshNetwork,
        gatewayModels: [GatewayModel]
    ) -> SyncGatewaysContext {
        var modelsByID: [String: GatewayModel] = [:]
        gatewayModels.forEach { model in
            guard let id = SiteGatewayAccessScope.normalize(model.mac), modelsByID[id] == nil else {
                return
            }
            modelsByID[id] = model
        }

        let local = modelsByID.reduce(into: [String: SyncGatewayLocalCandidate]()) {
            result, pair in
            let node = pair.value.resolveNode(in: meshNetwork)
            result[pair.key] = SyncGatewayLocalCandidate(
                displayName: pair.value.name,
                offsetMinutes: (node?.timezone?.secondsFromGMT()).map { $0 / 60 },
                isCloudDirty: pair.value.needUploadCloud,
                hasGatewayModel: true,
                hasNode: node != nil
            )
        }
        let descriptors = SyncGatewaysContextSelectionPolicy.select(
            scope: SiteGatewayAccessScope.resolve(remote: remote),
            targetOffsetMinutes: targetTimeZone.offsetMinutes,
            remote: remote.gateways.enumerated().map { index, gateway in
                SyncGatewayRemoteCandidate(
                    id: gateway.id,
                    offsetMinutes: gateway.offsetMinutes,
                    order: index
                )
            },
            local: local
        )
        let targets = descriptors.map { descriptor in
            let gateway = modelsByID[descriptor.id]
            return SyncGatewayRuntimeTarget(
                descriptor: descriptor,
                gateway: gateway,
                node: gateway?.resolveNode(in: meshNetwork)
            )
        }

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
