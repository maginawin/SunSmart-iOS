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
//        if let zone = zones.first(where: { $0.addresses.contains(address) }) {
//            zone.addresses.removeAll(where: { $0 == address })
//        }
    }
    
    /// 更新路径
//    func updatePath(_ path: GroupProximityLightingSequencePath) {
//        if let currentPath = self.paths.first(where: { $0.id == path.id }) {
//            currentPath.items = path.items.map({ $0.copy() })
//        }else {
//            self.paths.append(path.copy())
//        }
//    }
    
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

/// 邻近照明-节点信息
class NodeProximityLightingData {
    
    let address: Address
    var proximityLightingNeighborAddresses: [Address]
    
    init(address: Address, proximityLightingNeighborAddresses: [Address]) {
        self.address = address
        self.proximityLightingNeighborAddresses = proximityLightingNeighborAddresses
    }
}
