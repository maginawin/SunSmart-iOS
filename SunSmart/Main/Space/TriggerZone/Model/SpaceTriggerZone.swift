//
//  SpaceTriggerZone.swift
//  SunSmart
//
//  Created by yuankehong on 2026/3/30.
//

import Foundation
import NordicSigMeshSDK

class SpaceTriggerZone: NSObject, Codable, Copyable {
    
    class Item: NSObject, Codable, Copyable {
        
        var groupAddress: Address
        var deviceAddress: Address
        
        var group: Group? {
            return MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(groupAddress))
        }
        
        var node: Node? {
            return MeshNetworkManager.instance.realNodes.first(where: { $0.contains(elementWithAddress: deviceAddress) })
        }
        
        init(groupAddress: Address, deviceAddress: Address) {
            self.groupAddress = groupAddress
            self.deviceAddress = deviceAddress
        }
        
        func copy() -> Self {
            return Item(groupAddress: self.groupAddress, deviceAddress: self.deviceAddress) as! Self
        }
        
        static func == (lhs: Item, rhs: Item) -> Bool {
            return lhs.groupAddress == rhs.groupAddress && lhs.deviceAddress == rhs.deviceAddress
        }
    }
    
    static let maxZoneCount = 32
    
    var items: [Item] = []
    
    var addresses: [Address] {
        return items.map { $0.deviceAddress }
    }
    
    var nodes: [Node] {
        return items.compactMap { $0.node }
    }
    
    init(items: [Item] = []) {
        self.items = items
    }
    
    func copy() -> Self {
        return SpaceTriggerZone(items: self.items.map { $0.copy() }) as! Self
    }
    
    static func == (lhs: SpaceTriggerZone, rhs: SpaceTriggerZone) -> Bool {
        guard lhs.items.count == rhs.items.count else {
            return false
        }
        return zip(lhs.items, rhs.items).allSatisfy { $0 == $1 }
    }
    
    static func `default`(count: Int) -> [SpaceTriggerZone] {
        var list: [SpaceTriggerZone] = []
        for _ in 0..<min(count, maxZoneCount) {
            list.append(SpaceTriggerZone())
        }
        return list
    }
}
