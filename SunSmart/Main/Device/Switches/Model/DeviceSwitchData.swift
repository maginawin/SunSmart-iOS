//
//  DeviceSwitchData.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/5.
//

import Foundation
import NordicSigMeshSDK

class DeviceSwitchData: Copyable {
    
    /// 按键面板类型
    enum PanelType: UInt8 {
        var describe: String {
            return "default".localizedString
        }
        case `default` = 0
    }
    
    /// id
    let id: String
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String
    /// 面板类型
    var panelType: PanelType = .default
    
    /// 关联的组地址（publish）
    var linkGroupAddress: Address?
    /// 关联的组
    var linkGroup: Group? {
        guard let address = linkGroupAddress else { return nil }
        return MeshNetworkManager.instance.virtualGroups.first(where: { $0.address.address == address })
    }
    /// 绑定的组地址list
    var bindGroupAddresses: [Address] = []
    /// 绑定的组list
    var bindGroups: [Group] {
        return bindGroupAddresses.compactMap({ address in MeshNetworkManager.instance.groups.first(where: { $0.address.address == address }) })
    }
    
    /// 需要解除绑定的组地址list
    var unbindGroupAddresses: [Address] = []
    /// 需要解除绑定的组list
    var unbindGroups: [Group] {
        return unbindGroupAddresses.compactMap({ address in MeshNetworkManager.instance.groups.first(where: { $0.address.address == address }) })
    }
    
    /// 一键选择的场景
    var sceneANumber: SceneNumber?
    var sceneA: Scene? {
        return MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneANumber })
    }
    /// 二键选择的场景
    var sceneBNumber: SceneNumber?
    var sceneB: Scene? {
        return MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneBNumber })
    }
    /// 选择的代理节点（绑定设备后）
    var proxyNodeAddress: Address?
    var proxyNode: Node? {
        guard let address = proxyNodeAddress else { return nil }
        return MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)
    }
    /// 绑定真实动能开关mac
    var enOceanMacAddress: String?
    /// 绑定真实动能开关密钥
    var enOceanSecurityKey: String?
    
    /// 需要删除的代理节点
    var deleteProxyNodeAddress: Address?
    var deleteProxyNode: Node? {
        guard let address = deleteProxyNodeAddress else { return nil }
        return MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)
    }

//    var syncError: Bool {
//        
//        
//        
//    }
    
    /// 默认动能开关
    static func defalut() -> DeviceSwitchData {
        return DeviceSwitchData(id: UUID().uuidString, enabled: true, name: MeshNetworkManager.instance.getNextSwitchName(), linkGroupAddress: nil, bindGroupAddresses: [], sceneANumber: nil, sceneBNumber: nil, proxyNodeAddress: nil)
    }
    
    
    init(id: String, enabled: Bool, name: String, linkGroupAddress: Address? = nil, bindGroupAddresses: [Address] = [], sceneANumber: SceneNumber? = nil, sceneBNumber: SceneNumber? = nil, proxyNodeAddress: Address? = nil) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.linkGroupAddress = linkGroupAddress
        self.bindGroupAddresses = bindGroupAddresses
        self.sceneANumber = sceneANumber
        self.sceneBNumber = sceneBNumber
        self.proxyNodeAddress = proxyNodeAddress
    }
    
    func copy() -> Self {
        let copy = DeviceSwitchData(id: id, enabled: enabled, name: name, linkGroupAddress: linkGroupAddress, bindGroupAddresses: bindGroupAddresses, sceneANumber: sceneANumber, sceneBNumber: sceneBNumber, proxyNodeAddress: proxyNodeAddress) as! Self
        copy.enOceanMacAddress = self.enOceanMacAddress
        copy.enOceanSecurityKey = self.enOceanSecurityKey
        copy.unbindGroupAddresses = self.unbindGroupAddresses
        return copy
    }
    
    func update(switchData: DeviceSwitchData) {
        self.name = switchData.name
        self.enabled = switchData.enabled
        self.panelType = switchData.panelType
        self.linkGroupAddress = switchData.linkGroupAddress
        self.bindGroupAddresses = switchData.bindGroupAddresses
        self.unbindGroupAddresses = switchData.unbindGroupAddresses
        self.sceneANumber = switchData.sceneANumber
        self.sceneBNumber = switchData.sceneBNumber
        self.proxyNodeAddress = switchData.proxyNodeAddress
        self.enOceanMacAddress = switchData.enOceanMacAddress
        self.enOceanSecurityKey = switchData.enOceanSecurityKey
        //        self.group = switchData.group
    }
    
    static func == (lhs: DeviceSwitchData, rhs: DeviceSwitchData) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.linkGroupAddress == rhs.linkGroupAddress && lhs.bindGroupAddresses == rhs.bindGroupAddresses && lhs.unbindGroupAddresses == rhs.unbindGroupAddresses && lhs.enabled == rhs.enabled && lhs.panelType == rhs.panelType && lhs.sceneANumber == rhs.sceneANumber && lhs.sceneBNumber == rhs.sceneBNumber && lhs.proxyNodeAddress == rhs.proxyNodeAddress && lhs.enOceanMacAddress == rhs.enOceanMacAddress && lhs.enOceanSecurityKey == rhs.enOceanSecurityKey
    }
    
}
