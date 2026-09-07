//
//  GroupProximityLightingData.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/15.
//

import Foundation
import NordicSigMeshSDK

class GroupProximityLightingPathData: Codable, Copyable {
    
    /// 路径list
    var paths: [GroupProximityLightingSequencePath] = []
    /// 区域list
    var zones: [GroupProximityLightingPathZone] = []
    
    init(paths: [GroupProximityLightingSequencePath], zones: [GroupProximityLightingPathZone]) {
        self.paths = paths
        self.zones = zones
    }
    
    /// 涉及路径的设备list
    var nodes: [Node] {
        var nodes: [Node] = []
        paths.forEach { path in
            let pathNodes = path.items.compactMap({ $0.node })
            pathNodes.forEach { node in
                if !nodes.contains(node) {
                    nodes.append(node)
                }
            }
        }
        
        zones.forEach { zone in
            zone.nodes.forEach { node in
                if !nodes.contains(node) {
                    nodes.append(node)
                }
            }
        }
        return nodes
    }
    
    /// 是否空数据
    func isEmpty() -> Bool {
        return paths.isEmpty && zones.isEmpty
    }
    
    func copy() -> Self {
        return GroupProximityLightingPathData(paths: self.paths.map({ $0.copy() }), zones: self.zones.map({ $0.copy() })) as! Self
    }
    
    /// 删除设备
    func removeNode(_ node: Node) {
        let address = node.sunricherVendorModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
        paths.forEach { path in
            if let itemIndex = path.items.firstIndex(where: { $0.address == address }) {
                path.items[itemIndex].address = nil
            }
        }
        
        
//        if let path = paths.first(where: { path in path.items.contains(where: { $0.address == address }) }) {
//            if let item = path.items.first(where: { $0.address == address }) {
//                item.address = nil
//            }
//        }
        zones.forEach { zone in
            if let index = zone.addresses.firstIndex(of: address) {
                zone.addresses.remove(at: index)
            }
        }
    }
    
    /// 判断数据是否相等
    static func == (lhs: GroupProximityLightingPathData, rhs: GroupProximityLightingPathData) -> Bool {
        // 比较 paths
        guard lhs.paths.count == rhs.paths.count, lhs.zones.count == rhs.zones.count else { return false }
          
          let pathsEqual = zip(lhs.paths, rhs.paths).allSatisfy { lhsPath, rhsPath in
              lhsPath.items.count == rhsPath.items.count &&
              zip(lhsPath.items, rhsPath.items).allSatisfy { $0.address == $1.address }
          }
          
          // 比较 zones
          let zonesEqual = lhs.zones.count == rhs.zones.count &&
                          zip(lhs.zones, rhs.zones).allSatisfy { $0.addresses == $1.addresses }
          
          return pathsEqual && zonesEqual
    }
    
    
}


class GroupProximityLightingSequencePath: NSObject, Codable, Copyable {
   
    /// 路径最大32条
    static let maxPathCount = 32
    /// 路径item最大200个
    static let maxPathItemCount = 200
    
    /// 组邻近照明路径item
    class GroupProximityLightingPathItem: NSObject, Codable, Copyable {
        
        /// 绑定的设备地址
        var address: Address?
        var node: Node? {
            guard let nodeAddress = address else {
                return nil
            }
            return MeshNetworkManager.instance.realNodes.first(where: { $0.contains(elementWithAddress: nodeAddress) })
        }
        
        init(address: Address? = nil) {
            self.address = address
        }
        
        func copy() -> Self {
            return GroupProximityLightingPathItem(address: address) as! Self
        }
        
        func isEqualData(_ item: GroupProximityLightingPathItem?) -> Bool {
            guard let compareItem = item else {
                return false
            }
            return self.address == compareItem.address
        }
        
        /// 默认创建n个item
        static func `default`(count: Int) -> [GroupProximityLightingPathItem] {
            var items: [GroupProximityLightingPathItem] = []
            for _ in 0..<min(count, GroupProximityLightingSequencePath.maxPathItemCount) {
                items.append(GroupProximityLightingPathItem())
            }
            return items
        }
    }
    
    var items: [GroupProximityLightingPathItem] = []
    
    /// 使用的设备list
    var nodes: [Node] {
        guard items.count > 0 else {
            return []
        }
        return items.compactMap({ $0.node })
    }
    
    init(items: [GroupProximityLightingPathItem]) {
        self.items = items
    }
    
    func copy() -> Self {
        return GroupProximityLightingSequencePath(items: self.items.map({ $0.copy() }) ) as! Self
    }
    
    /// 判断数据是否相等
    static func == (lhs: GroupProximityLightingSequencePath, rhs: GroupProximityLightingSequencePath) -> Bool {
        return lhs.items.count == rhs.items.count && lhs.items.compactMap({ $0.address }) == rhs.items.compactMap({ $0.address })
    }
    
    func updateData(path: GroupProximityLightingSequencePath) {
        self.items = path.items.map({ $0.copy() })
    }
    
    
    /// 默认创建n条路径，每条路径3个item
    static func `default`(count: Int) -> [GroupProximityLightingSequencePath] {
        
        var list: [GroupProximityLightingSequencePath] = []
        for _ in 0..<min(count, GroupProximityLightingSequencePath.maxPathCount) {
            let path = GroupProximityLightingSequencePath(items: GroupProximityLightingPathItem.default(count: 3))
            list.append(path)
        }
        return list
    }
    
}


class GroupProximityLightingPathZone: NSObject, Codable, Copyable {
    
    /// 路径区域最大32条
    static let maxZoneCount = 32
    
    /// 选择的设备地址list
    var addresses: [Address] = []
    var nodes: [Node] {
        return addresses.compactMap({ address in MeshNetworkManager.instance.realNodes.first(where: { $0.contains(elementWithAddress: address) }) })
    }
    
    init(addresses: [Address] = []) {
        self.addresses = addresses
    }
    
    func copy() -> Self {
        return GroupProximityLightingPathZone(addresses: self.addresses) as! Self
    }
    
    /// 默认创建n条路径区域
    static func `default`(count: Int) -> [GroupProximityLightingPathZone] {
        
        var list: [GroupProximityLightingPathZone] = []
        for _ in 0..<min(count, GroupProximityLightingPathZone.maxZoneCount) {
            let zone = GroupProximityLightingPathZone()
            list.append(zone)
        }
        return list
    }
    
}

/// The network is retained while its Groups/Nodes (which hold weak SDK links) are used.
enum ProximityLightingTopologyContext {
    static func network(for space: SpaceData) -> MeshNetwork? {
        let manager = MeshNetworkManager.instance
        if let network = manager.meshNetwork,
           network.uuid.uuidString == space.meshUUID,
           manager.currentNetworkKey.networkId.hex == space.meshNetworkId {
            return network
        }
        guard let network = MeshNetwork.load(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId) else {
            return nil
        }
        loadGroupInfo(network: network, space: space)
        return network
    }

    static func loadGroupInfo(network: MeshNetwork, space: SpaceData) {
        for group in network.groups where !group.isVirtual {
            group.info = GroupInfo.load(meshUUID: space.meshUUID, address: group.address.address,
                                        subnetworkId: space.meshNetworkId)
                ?? GroupInfo.unavailable(address: group.address.address)
        }
    }

    static func realNodes(in network: MeshNetwork) -> [Node] {
        network.nodes.filter { !$0.isLocalProvisioner && !$0.isProvisioner && !$0.isConfigComplete }
    }

    static func members(of group: Group, nodes: [Node]) -> Set<Address> {
        guard let uuid = group.network?.uuid, let networkId = group.subNetworkId else { return [] }
        return Set(nodes.filter { node in
            node.network?.uuid == uuid && node.subNetworkId == networkId
                && !node.isProvisioner && !node.isConfigComplete
                && node.groupState != .exitFailure
                && node.elements.contains { element in
                    element.models.contains { $0.subscriptions.contains { $0.address == group.address } }
                }
        }.map { ProximityLightingTopologyPlanner.normalizedAddress(for: $0) })
    }

    static func isAvailable(space: SpaceData, network: MeshNetwork?, groups: [Group], nodes: [Node]) -> Bool {
        guard let network, network.uuid.uuidString == space.meshUUID,
              !space.triggerZonesLoadFailed,
              Set(groups.map { $0.address.address }) == Set(network.groups.filter { !$0.isVirtual }.map { $0.address.address }),
              Set(nodes.map { $0.primaryUnicastAddress }) == Set(realNodes(in: network).map { $0.primaryUnicastAddress }) else { return false }
        return groups.allSatisfy {
            $0.network?.uuid == network.uuid && $0.subNetworkId == space.meshNetworkId
                && !$0.info.profileLoadFailed && !$0.info.topologyLoadFailed
        } && nodes.allSatisfy {
            $0.network?.uuid == network.uuid && $0.subNetworkId == space.meshNetworkId
        }
    }
}

enum ProximityLightingTopologyPlanner {

    typealias Plan = ProximityLightingTopologyPolicy.Plan

    static func capacityLimitMessage(for plan: Plan) -> String? {
        guard let violation = plan.capacityViolations.first else {
            return nil
        }
        return String(
            format: "proximity_lighting_neighbor_limit_exceeded".localizedString,
            violation.maximumNeighborCount
        )
    }

    static func makePlan(
        space: SpaceData,
        groupPathOverrides: [Address: GroupProximityLightingPathData] = [:],
        spaceTriggerZonesOverride: [SpaceTriggerZone]? = nil,
        additionalGroupMembers: [Address: Set<Address>] = [:]
    ) -> Plan {
        guard let network = ProximityLightingTopologyContext.network(for: space) else { return .unavailable }
        let groups = network.groups.filter { !$0.isVirtual && $0.subNetworkId == space.meshNetworkId }
        let nodes = ProximityLightingTopologyContext.realNodes(in: network)
        guard ProximityLightingTopologyContext.isAvailable(space: space, network: network, groups: groups, nodes: nodes) else {
            return .unavailable
        }
        return withExtendedLifetime(network) {
            makePlan(
                groups: groups,
                nodes: nodes,
                groupPathOverrides: groupPathOverrides,
                spaceTriggerZones: spaceTriggerZonesOverride ?? space.triggerZones,
                additionalGroupMembers: additionalGroupMembers
            )
        }
    }

    static func makePlan(
        groups: [Group],
        nodes: [Node],
        groupPathOverrides: [Address: GroupProximityLightingPathData] = [:],
        spaceTriggerZones: [SpaceTriggerZone] = [],
        additionalGroupMembers: [Address: Set<Address>] = [:]
    ) -> Plan {
        let eligibleGroups = groups.filter { isEligible($0) }
        let groupSnapshots = eligibleGroups.map { group in
            makeGroupSnapshot(
                group: group,
                nodes: nodes,
                pathOverride: groupPathOverrides[group.address.address],
                additionalMemberAddresses: additionalGroupMembers[group.address.address] ?? []
            )
        }
        return ProximityLightingTopologyPolicy.makePlan(
            groups: groupSnapshots,
            spaceZones: makeSpaceZoneSnapshots(spaceTriggerZones)
        )
    }

    static func makePlan(
        for node: Node,
        contextGroup: Group? = nil
    ) -> Plan {
        let group = contextGroup ?? node.group
        if let group, group.network?.uuid != node.network?.uuid || group.subNetworkId != node.subNetworkId {
            return .unavailable
        }
        var additionalGroupMembers: [Address: Set<Address>] = [:]
        if let group, node.groupState != .exitFailure {
            additionalGroupMembers[group.address.address] = [normalizedAddress(for: node)]
        }

        guard let subNetworkId = node.subNetworkId,
              let space = SpaceData.load(subNetworkId: subNetworkId),
              space.meshUUID == node.network?.uuid.uuidString else {
            // A Group-only fallback would silently omit Space zones.
            return .unavailable
        }
        return makePlan(space: space, additionalGroupMembers: additionalGroupMembers)
    }

    static func makeSpaceZoneSnapshots(
        _ zones: [SpaceTriggerZone]
    ) -> [ProximityLightingTopologyPolicy.SpaceZoneSnapshot] {
        return zones.map { zone in
            .init(
                members: zone.items.map {
                    .init(
                        groupAddress: $0.groupAddress,
                        deviceAddress: $0.deviceAddress
                    )
                }
            )
        }
    }

    static func affectedDeviceAddresses(
        oldSpaceZones: [SpaceTriggerZone],
        newSpaceZones: [SpaceTriggerZone]
    ) -> Set<Address> {
        return ProximityLightingTopologyPolicy.affectedDeviceAddresses(
            oldSpaceZones: makeSpaceZoneSnapshots(oldSpaceZones),
            newSpaceZones: makeSpaceZoneSnapshots(newSpaceZones)
        )
    }

    static func normalizedAddress(for node: Node) -> Address {
        return node.sunricherVendorModel?.parentElement?.unicastAddress
            ?? node.primaryUnicastAddress
    }

    static func isEligible(_ group: Group) -> Bool {
        return group.info.profile.type == .proximityLighting
            || group.info.profile.type == .proximityLightingWithPhotocell
    }

    private static func makeGroupSnapshot(
        group: Group,
        nodes: [Node],
        pathOverride: GroupProximityLightingPathData?,
        additionalMemberAddresses: Set<Address>
    ) -> ProximityLightingTopologyPolicy.GroupSnapshot {
        let path = pathOverride ?? group.info.proximityLightingPath
        let currentMemberAddresses = ProximityLightingTopologyContext.members(of: group, nodes: nodes)
        return .init(
            address: group.address.address,
            relayNumber: group.info.profile.proximityLightingNumber,
            memberAddresses: currentMemberAddresses.union(additionalMemberAddresses),
            paths: path?.paths.map { $0.items.map(\.address) } ?? [],
            zones: path?.zones.map(\.addresses) ?? []
        )
    }
}

extension SpaceData {

    @discardableResult
    func migrateProximityLightingReferences(
        from oldNode: Node,
        to newNode: Node,
        group: Group?
    ) -> ProximityLightingLifecycleResult? {
        var transaction = ProximityLightingLifecycleCoordinator.begin(space: self)
        if let group {
            transaction.replaceNodeAddress(from: oldNode, to: newNode, group: group)
        } else {
            transaction.removeNode(oldNode)
        }
        return ProximityLightingLifecycleCoordinator.commit(
            transaction.prepare(),
            allowExistingHardErrors: true
        )
    }
}

/// 邻近照明-节点信息
class NodeProximityLightingData {
    
    let address: Address
    var proximityLightingNeighborAddresses: [Address]
    
    init(address: Address, proximityLightingNeighborAddresses: [Address]) {
        self.address = address
        self.proximityLightingNeighborAddresses = proximityLightingNeighborAddresses
    }
}
