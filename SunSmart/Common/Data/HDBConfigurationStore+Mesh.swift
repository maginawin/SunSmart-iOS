import Foundation
import NordicSigMeshSDK

extension HDBConfigurationStore {
    static func deviceConfiguration(node: Node) throws -> HDBDeviceConfiguration {
        var device = HDBDeviceConfiguration(nodeUuid: node.uuid, nodeAddress: node.primaryUnicastAddress,
              mac: try HDBDeviceConfiguration.normalizedMAC(node.macAddress))
        let targets = modelTargets(node: node)
        device.zoneModels = HDBLightingZonePolicy.zoneTargets(from: targets, primaryAddress: node.primaryUnicastAddress).map(HDBModelReference.init)
        device.sensorGroupModels = HDBLightingZonePolicy.sensorGroupTargets(from: targets).map(HDBModelReference.init)
        device.broadcastModels = broadcastTargets(node: node).map(HDBModelReference.init)
        return device
    }

    static func modelTargets(node: Node) -> [HDBModelTarget] {
        node.elements.flatMap { element in element.models.map {
            .init(elementAddress: element.unicastAddress, modelIdentifier: $0.modelIdentifier, companyIdentifier: $0.companyIdentifier)
        } }
    }

    /// Restore only receivers touched by this Zone reset. OnOff's primary-only
    /// Zone rule must not exclude same-element receivers from FEFD restoration.
    static func broadcastTargets(node: Node) -> [HDBModelTarget] {
        let zoneTargets = Set(HDBLightingZonePolicy.zoneTargets(from: modelTargets(node: node), primaryAddress: node.primaryUnicastAddress))
        func target(_ model: Model, element: Element) -> HDBModelTarget {
            .init(elementAddress: element.unicastAddress, modelIdentifier: model.modelIdentifier, companyIdentifier: model.companyIdentifier)
        }
        let zoneModels = node.elements.flatMap { element in element.models.filter { zoneTargets.contains(target($0, element: element)) } }
        let affected = Set(zoneModels.flatMap { [$0] + $0.relatedModels })
        let requiredIDs: [UInt16] = [0x1306, 0x130F]
        var receivers = Set<HDBModelTarget>()
        for element in node.elements where element.unicastAddress != node.primaryUnicastAddress {
            for model in element.models where model.companyIdentifier == nil && requiredIDs.contains(model.modelIdentifier) {
                if model.modelIdentifier == 0x130F {
                    for receiver in element.models where receiver.companyIdentifier == nil && [0x1000, 0x130F, 0x1310].contains(receiver.modelIdentifier) {
                        receivers.insert(target(receiver, element: element))
                    }
                } else if model.modelIdentifier == 0x1306 {
                    let shared = [model] + model.relatedModels.filter { $0.parentElement === element }
                    guard shared.contains(where: { affected.contains($0) }) else { continue }
                    let compatible = shared.filter { $0.companyIdentifier == nil && [0x1000, 0x1300, 0x130F, 0x1310].contains($0.modelIdentifier) }
                    for receiver in compatible.isEmpty ? [model] : compatible { receivers.insert(target(receiver, element: element)) }
                }
            }
        }
        return receivers.sorted(by: HDBLightingZonePolicy.targetOrder)
    }

    /// Check one already loaded Space snapshot; export must not repair or persist it.
    static func validateModels(_ configuration: HDBConfiguration, nodes: [Node]) throws {
        for device in configuration.devices {
            guard let node = nodes.first(where: { $0.uuid == device.nodeUuid && $0.primaryUnicastAddress == device.nodeAddress }),
                  device.hasSameModels(as: try deviceConfiguration(node: node)) else { throw HDBConfigurationError.invalidData }
            try device.validateSensorPublication(models: modelTargets(node: node))
        }
    }

    /// Group addresses are unique across the Site, not just within one Space.
    static func availableLightingZoneAddresses(meshUUID: String) -> [UInt16] {
        Set(MeshAPI.getAvailableGroupAddresses(meshUUID: meshUUID))
            .filter { (0xC001..<0xFEFD).contains(Int($0)) }.sorted()
    }

    static func sensorGroupName(_ nodeUuid: UUID) -> String { "Sensor " + nodeUuid.uuidString }

    static func ensureSensorGroup(space: SpaceData, nodeUuid: UUID) throws -> UInt16 {
        precondition(Thread.isMainThread)
        guard let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.uuid == nodeUuid }),
              let context = try HDBDeviceSyncContext.resolve(space: space, node: node), context.isCurrent() else {
            throw HDBConfigurationError.unavailable
        }
        let config = try load(space: space)
        guard let device = config.devices.first(where: { $0.nodeUuid == nodeUuid }) else { throw HDBConfigurationError.unavailable }
        let network = context.network
        let name = sensorGroupName(nodeUuid)
        let existing: Group?
        if let address = device.sensorGroupId {
            guard let group = network.group(withAddress: address), group.isVirtual,
                  group.subNetworkId == space.meshNetworkId else { throw HDBConfigurationError.invalidData }
            return group.address.address
        } else {
            let retiring = Set(try SpaceConfigurationSafety.deletionJournal(space).entries.compactMap(\.sensorGroupId))
            let owned = network.groups.filter { $0.isVirtual && $0.subNetworkId == space.meshNetworkId && $0.name == name && !retiring.contains($0.address.address) }
            guard owned.count <= 1 else { throw HDBConfigurationError.invalidData }
            existing = owned.first
        }
        let group: Group
        if let existing { group = existing }
        else {
            guard let address = availableLightingZoneAddresses(meshUUID: space.meshUUID).first else { throw HDBConfigurationError.addressUnavailable }
            group = try Group(name: name, address: MeshAddress(address))
            group.isVirtual = true; group.subNetworkId = space.meshNetworkId
            try network.add(group: group)
        }
        // The Group occupies the shared pool before the device points to it. Its stable
        // owner name allows retry after a crash between these two durable writes.
        guard group.save() else { throw HDBConfigurationError.persistenceFailed }
        try update(space: space) { current in
            guard let index = current.devices.firstIndex(where: { $0.nodeUuid == nodeUuid }) else { throw HDBConfigurationError.unavailable }
            current.devices[index].sensorGroupId = group.address.address
            try current.devices[index].refreshSensorPublication()
        }
        return group.address.address
    }

    /// Only for a new Space. The caller saves the complete Space and handles failure cleanup.
    static func initializeLightingZones(space: SpaceData, addresses: [UInt16]) throws {
        precondition(Thread.isMainThread)
        guard space.hdb == nil, addresses.count == 63, Set(addresses).count == 63,
              addresses.allSatisfy({ (0xC001..<0xFEFD).contains(Int($0)) }) else { throw HDBConfigurationError.invalidZones }
        guard let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
              network.networkKeys.contains(where: { $0.networkId.hex == space.meshNetworkId }) else { throw HDBConfigurationError.persistenceFailed }
        var config = HDBConfiguration()
        for (index, address) in addresses.enumerated() {
            let zoneId = index + 1
            let name = String(format: "hdb_default_zone_name".localizedString, zoneId)
            let group = try Group(name: name, address: MeshAddress(address))
            group.isVirtual = false
            group.subNetworkId = space.meshNetworkId
            group.info = GroupInfo(address: address)
            // Do not use MeshAPI.createGroup: it binds to the currently open Space.
            try network.add(group: group)
            guard group.save(), group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
                throw HDBConfigurationError.persistenceFailed
            }
            config.lightingZones.append(.init(zoneId: zoneId, name: name, groupAddress: address))
        }
        try HDBLightingZonePolicy.validate(config)
        space.hdb = config
        space.groupCount = addresses.count
    }

    static func createZone(space: SpaceData, zoneId: Int, name: String) throws -> HDBLightingZone {
        let current = try load(space: space)
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (1...63).contains(zoneId), !name.isEmpty, !current.lightingZones.contains(where: { $0.zoneId == zoneId }) else { throw HDBConfigurationError.invalidZones }
        guard let latest = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              latest.canEditing, space.groupOperates.contains(.edit), !SpaceConfigurationSafety.isBlocked(latest),
              let network = MeshNetworkManager.instance.meshNetwork, network.uuid.uuidString == space.meshUUID,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == space.meshNetworkId else { throw HDBConfigurationError.permissionDenied }
        guard let address = availableLightingZoneAddresses(meshUUID: space.meshUUID).first else { throw HDBConfigurationError.addressUnavailable }
        // Registration is durable before any target can be sent. On failure keep it occupied.
        let group = try MeshAPI.createGroup(name: name, address: address, isVirtual: false)
        group.info = GroupInfo(address: address)
        guard group.save(), group.info.save(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else { throw HDBConfigurationError.persistenceFailed }
        let zone = HDBLightingZone(zoneId: zoneId, name: name, groupAddress: address)
        try update(space: space, refreshCounts: true) { config in
            guard !config.lightingZones.contains(where: { $0.zoneId == zoneId || $0.groupAddress == address }) else { throw HDBConfigurationError.invalidZones }
            config.lightingZones.append(zone)
        }
        return zone
    }


    static func pendingSensorGroupAddresses(space: SpaceData) throws -> Set<UInt16> {
        let read = { Result { try sensorGroupCleanupAddresses(space: space) } }
        return try (NodeSyncReadContext.current?.memoized("hdb.sensorCleanup." + space.id, read: read) ?? read()).get()
    }

    private static func sensorGroupCleanupAddresses(space: SpaceData) throws -> Set<UInt16> {
        let entries = try SpaceConfigurationSafety.deletionJournal(space).entries.filter { $0.stage == .cleaned && $0.sensorGroupId != nil }
        guard !entries.isEmpty else { return [] }
        guard let network = ProximityLightingTopologyContext.network(for: space) else { throw HDBConfigurationError.unavailable }
        let assigned = Set(try load(space: space).devices.compactMap(\.sensorGroupId))
        return Set(entries.compactMap { entry in
            guard let address = entry.sensorGroupId, !assigned.contains(address),
                  let owner = UUID(uuidString: entry.nodeUUID),
                  let group = network.group(withAddress: address), group.isVirtual,
                  group.subNetworkId == space.meshNetworkId, group.name == sensorGroupName(owner) else { return nil }
            return address
        })
    }

    static func removeDevice(space: SpaceData, nodeUuid: UUID) throws {
        let config = try load(space: space)
        if let address = config.devices.first(where: { $0.nodeUuid == nodeUuid })?.sensorGroupId {
            guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                for index in journal.entries.indices where UUID(uuidString: journal.entries[index].nodeUUID) == nodeUuid {
                    journal.entries[index].sensorGroupId = address
                }
            }), try SpaceConfigurationSafety.deletionJournal(space).entries.contains(where: {
                UUID(uuidString: $0.nodeUUID) == nodeUuid && $0.sensorGroupId == address
            }) else { throw HDBConfigurationError.persistenceFailed }
        }
        try update(space: space) { $0.devices.removeAll { $0.nodeUuid == nodeUuid } }
    }

    @discardableResult
    static func finishSensorGroupCleanup(space: SpaceData) throws -> Bool {
        var released = false
        let addresses = Set(try SpaceConfigurationSafety.deletionJournal(space).entries.filter { $0.stage == .cleaned }.compactMap(\.sensorGroupId))
        guard !addresses.isEmpty else { return false }
        let ownedAddresses = try pendingSensorGroupAddresses(space: space)
        guard let network = ProximityLightingTopologyContext.network(for: space) else { throw HDBConfigurationError.unavailable }
        for address in addresses {
            if ownedAddresses.contains(address) {
                let hasReferences = network.nodes.contains { node in node.elements.contains { element in element.models.contains { model in
                    model.publish?.publicationAddress.address == address
                        || model.subscriptions.contains { $0.address.address == address }
                } } }
                guard !hasReferences else { continue }
                if let group = network.group(withAddress: address) {
                    guard group.isVirtual, group.subNetworkId == space.meshNetworkId, group.delete() else { throw HDBConfigurationError.persistenceFailed }
                    try network.remove(group: group)
                }
            }
            // Also retry this durable dirty mark if Group deletion succeeded but a later
            // write failed. An address since reused belongs to its new owner.
            try update(space: space) { _ in }
            guard SpaceConfigurationSafety.updateDeletionJournal(space, { journal in
                for index in journal.entries.indices where journal.entries[index].sensorGroupId == address && journal.entries[index].stage == .cleaned {
                    journal.entries[index].sensorGroupId = nil
                }
            }) else { throw HDBConfigurationError.persistenceFailed }
            released = true
        }
        return released
    }
}

extension Node {
    /// HDB subscriptions do not establish the App's ordinary single-Group membership.
    func configurationGroup(excluding addresses: Set<UInt16>) -> Group? {
        guard !addresses.isEmpty else { return group }
        return elements.lazy.flatMap(\.models).flatMap(\.subscriptions).first {
            !$0.isVirtual && $0.address.address >= 0xC000 && $0.address.address < 0xFEFD
                && !addresses.contains($0.address.address)
        }
    }
    var configurationGroup: Group? {
        guard let networkId = subNetworkId, let space = SpaceData.load(subNetworkId: networkId),
              space.meshUUID == network?.uuid.uuidString else { return group }
        return configurationGroup(excluding: space.hdbGroupAddresses)
    }
}
