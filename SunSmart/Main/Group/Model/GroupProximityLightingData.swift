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
        let groups = MeshNetworkManager.instance.groups.filter {
            $0.subNetworkId == space.meshNetworkId
        }
        return makePlan(
            groups: groups,
            groupPathOverrides: groupPathOverrides,
            spaceTriggerZones: spaceTriggerZonesOverride ?? space.triggerZones,
            additionalGroupMembers: additionalGroupMembers
        )
    }

    static func makePlan(
        groups: [Group],
        groupPathOverrides: [Address: GroupProximityLightingPathData] = [:],
        spaceTriggerZones: [SpaceTriggerZone] = [],
        additionalGroupMembers: [Address: Set<Address>] = [:]
    ) -> Plan {
        let eligibleGroups = groups.filter { isEligible($0) }
        let groupSnapshots = eligibleGroups.map { group in
            makeGroupSnapshot(
                group: group,
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
        var additionalGroupMembers: [Address: Set<Address>] = [:]
        if let group, node.groupState != .exitFailure {
            additionalGroupMembers[group.address.address] = [normalizedAddress(for: node)]
        }

        if let subNetworkId = group?.subNetworkId,
           let space = SpaceData.load(subNetworkId: subNetworkId) {
            return makePlan(
                space: space,
                additionalGroupMembers: additionalGroupMembers
            )
        }

        return makePlan(
            groups: group.map { [$0] } ?? [],
            additionalGroupMembers: additionalGroupMembers
        )
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
        pathOverride: GroupProximityLightingPathData?,
        additionalMemberAddresses: Set<Address>
    ) -> ProximityLightingTopologyPolicy.GroupSnapshot {
        let path = pathOverride ?? group.info.proximityLightingPath
        let currentMemberAddresses = Set(
            group.nodes
                .filter { $0.groupState != .exitFailure }
                .map { normalizedAddress(for: $0) }
        )
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
        from oldAddress: Address,
        to newAddress: Address
    ) -> Bool {
        guard oldAddress != newAddress else {
            return false
        }

        let affectedGroups = MeshNetworkManager.instance.groups.filter { group in
            guard group.subNetworkId == meshNetworkId,
                  let path = group.info.proximityLightingPath else {
                return false
            }
            return path.paths.contains { path in
                path.items.contains { $0.address == oldAddress }
            } || path.zones.contains { $0.addresses.contains(oldAddress) }
        }
        let hasSpaceZoneReference = triggerZones.contains { zone in
            zone.items.contains { $0.deviceAddress == oldAddress }
        }

        guard !affectedGroups.isEmpty || hasSpaceZoneReference else {
            return false
        }

        markLocalChangePendingCloudSync()

        affectedGroups.forEach { group in
            guard let path = group.info.proximityLightingPath else {
                return
            }
            path.paths.forEach { path in
                path.items.forEach { item in
                    if item.address == oldAddress {
                        item.address = newAddress
                    }
                }
            }
            path.zones.forEach { zone in
                zone.addresses = zone.addresses.map { address in
                    address == oldAddress ? newAddress : address
                }
            }
            group.info.save()
            group.updateGroupSyncState()
        }

        if hasSpaceZoneReference {
            triggerZones.forEach { zone in
                zone.items.forEach { item in
                    if item.deviceAddress == oldAddress {
                        item.deviceAddress = newAddress
                    }
                }
            }
            save()
        }

        return true
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
