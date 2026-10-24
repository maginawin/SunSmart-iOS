import Foundation
import NordicSigMeshSDK

/// Explicit ownership for execution. UI visibility is not a configuration authority.
final class HDBDeviceSyncContext {
    let site: SiteData
    let space: SpaceData
    let node: Node
    let network: MeshNetwork
    private let account = UserData.currentUserId
    private let region = UserData.currentServerRegion
    private let address: UInt16
    private let deviceKey: Data?

    private init(site: SiteData, space: SpaceData, node: Node, network: MeshNetwork) {
        self.site = site; self.space = space; self.node = node; self.network = network
        address = node.primaryUnicastAddress; deviceKey = node.deviceKey
    }

    static func resolve(space explicitSpace: SpaceData? = nil, node: Node, allowNonLights: Bool = false) throws -> HDBDeviceSyncContext? {
        guard !node.isProvisioner, (allowNonLights || node.deviceType == .light), let network = node.network else { return nil }
        let networkID = NodeSyncReadContext.current?.networkID ?? node.subNetworkId
        guard let networkID else { return nil }
        let readSpace = { SpaceData.load(siteId: network.uuid.uuidString).filter {
            $0.meshUUID == network.uuid.uuidString && $0.meshNetworkId == networkID
        } }
        let spaces = NodeSyncReadContext.current?.memoized("hdb.spaces", read: readSpace) ?? readSpace()
        guard let space = explicitSpace ?? (spaces.count == 1 ? spaces.first : nil) else {
            if spaces.count > 1 { throw HDBConfigurationError.unavailable }
            return nil
        }
        guard space.meshUUID == network.uuid.uuidString, space.meshNetworkId == networkID else { throw HDBConfigurationError.unavailable }
        let readSite = { SiteData.load(siteId: space.siteId) }
        let resolvedSite: SiteData?
        if let readContext = NodeSyncReadContext.current {
            resolvedSite = readContext.memoized("hdb.site." + space.siteId, read: readSite)
        } else { resolvedSite = readSite() }
        guard let site = resolvedSite else { return nil }
        let readType = { Result { try site.loadIsHdbSite() } }
        let type = NodeSyncReadContext.current?.memoized("hdb.type." + site.id, read: readType) ?? readType()
        guard try type.get() else { return nil }
        guard network.nodes.contains(where: { $0 === node }),
              let key = network.networkKeys.first(where: { $0.networkId.hex == networkID }),
              node.knows(networkKey: key), !space.hdbLoadFailed else { throw HDBConfigurationError.unavailable }
        return .init(site: site, space: space, node: node, network: network)
    }

    func isCurrent() -> Bool {
        guard account == UserData.currentUserId, region == UserData.currentServerRegion,
              network === MeshNetworkManager.instance.meshNetwork,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId,
              network.nodes.contains(where: { $0 === node }), node.primaryUnicastAddress == address,
              node.deviceKey == deviceKey, node.subNetworkId == space.meshNetworkId,
              (try? site.loadIsHdbSite()) == true,
              let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.meshUUID == space.meshUUID, latest.meshNetworkId == space.meshNetworkId,
              latest.canEditing, latest.groupOperates.contains(.edit),
              !SpaceConfigurationSafety.isBlocked(latest) else { return false }
        return true
    }

    var targets: [HDBModelTarget] {
        node.elements.flatMap { element in element.models.map {
            HDBModelTarget(elementAddress: element.unicastAddress, modelIdentifier: $0.modelIdentifier, companyIdentifier: $0.companyIdentifier)
        } }
    }
    var publicationTargets: [HDBModelTarget] {
        get throws {
            let sensors = node.elements.flatMap { element in
                element.models.filter { $0.companyIdentifier == nil && $0.modelIdentifier == 0x1100 }
                    .map { (element: element, model: $0) }
            }
            // Unknown properties do not create a publication task or an HDB readiness requirement.
            guard sensors.allSatisfy({ (node.sensorModelTypes[$0.model]?.id ?? 0) != 0 }) else { return [] }
            let presence = sensors.filter { node.sensorModelTypes[$0.model]?.id == 0x004D }
            guard presence.count <= 1 else { throw HDBConfigurationError.unsupportedModels }
            return presence.map {
                HDBModelTarget(elementAddress: $0.element.unicastAddress,
                    modelIdentifier: $0.model.modelIdentifier, companyIdentifier: nil)
            }
        }
    }
    var hasSensor: Bool { targets.contains { $0.modelId == 0x1100 } }
    var key: ApplicationKey? { network.applicationKeys.first { $0.boundNetworkKey.networkId.hex == space.meshNetworkId } }

    func plan(in config: HDBConfiguration) throws -> HDBDevicePreparationPlan {
        guard let key else { throw HDBConfigurationError.applicationKeyUnavailable }
        guard let device = config.devices.first(where: { $0.nodeUuid == node.uuid }) else { throw HDBConfigurationError.unavailable }
        return try HDBDevicePreparationPolicy.plan(nodeUuid: node.uuid, nodeAddress: node.primaryUnicastAddress,
            appKeyIndex: key.index, targets: targets,
            sensorGroupId: device.sensorGroupId,
            publicationTargets: device.sensorPublication.first?.elementAddress == nil ? [] : try publicationTargets,
            sensorPublication: device.sensorPublication)
    }

    func zoneSensorTargets(in config: HDBConfiguration) throws -> [HDBModelTarget] {
        HDBLightingZonePolicy.sensorGroupTargets(from: targets)
    }

    func zoneBroadcastTargets() throws -> [HDBModelTarget] {
        HDBConfigurationStore.broadcastTargets(node: node)
    }

    func model(_ target: HDBModelTarget) -> Model? {
        node.elements.first { $0.unicastAddress == target.elementAddress }?.models.first {
            $0.modelIdentifier == target.modelIdentifier && $0.companyIdentifier == target.companyIdentifier
        }
    }

    func zoneOperations(in config: HDBConfiguration) throws -> [HDBZoneOperation] {
        guard let device = config.devices.first(where: { $0.nodeUuid == node.uuid }) else {
            throw HDBConfigurationError.unavailable
        }
        return try HDBLightingZonePolicy.operations(for: device, in: config, targets: targets,
            sensorTargets: zoneSensorTargets(in: config), broadcastTargets: zoneBroadcastTargets())
    }

}
