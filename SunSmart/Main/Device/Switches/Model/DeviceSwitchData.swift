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
        /// 按键数量
        var keyCount: Int {
            switch self {
            case .default_4key, .scenes_4key:
                return 4
            case .default_2key, .scenes_2key:
                return 2
            }
        }
        
        /// 占用地址数量
        var usedAddressesNumber: Int {
            switch self {
            case .default_4key, .scenes_4key:
                return 2
            case .default_2key, .scenes_2key:
                return 2
            }
        }
        
        var describe: String {
            var name: String = ""
            switch self {
            case .default_4key, .default_2key:
                name = "default".localizedString
                return "\("default".localizedString)(\(keyCount) \("key".localizedString))"
            case .scenes_4key, .scenes_2key:
                name = "scene_panel".localizedString
            }
            return name + "(\(keyCount) \("key".localizedString))"
        }
        /// 默认(4键)
        case default_4key = 0
        /// 场景面板(4键)
        case scenes_4key = 1
        /// 默认(2键)
        case default_2key = 2
        /// 场景面板(2键)
        case scenes_2key = 3
    }
    
    /// id
    let id: String
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String
    /// 面板类型
    var panelType: PanelType = .default_4key
    
    /// 关联的组地址Main（publish）
    var linkGroupAddress: Address?
    /// 关联的组
    var linkGroup: Group? {
        guard let address = linkGroupAddress else { return nil }
        return MeshNetworkManager.instance.virtualGroups.first(where: { $0.address.address == address })
    }
    /// 关联的子组地址Sub (cct)
    var subLinkGroupAddress: Address?
    /// 关联的子组
    var subLinkGroup: Group? {
        guard let address = subLinkGroupAddress else { return nil }
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
    
    /// 一键选择的场景
    var sceneCNumber: SceneNumber?
    var sceneC: Scene? {
        return MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneCNumber })
    }
    /// 二键选择的场景
    var sceneDNumber: SceneNumber?
    var sceneD: Scene? {
        return MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneDNumber })
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
    
    /// 动能开关最大按键数量（因可切换开关类型，分配固件开关数量按最大支持数量分配）
    var maxKeyCount: UInt8 = 4
    
    /// 默认动能开关
    static func `default`(id: String = UUID().uuidString) -> DeviceSwitchData {
        return DeviceSwitchData(id: id, enabled: true, name: MeshNetworkManager.instance.getNextSwitchName(), linkGroupAddress: nil, bindGroupAddresses: [], sceneANumber: nil, sceneBNumber: nil, proxyNodeAddress: nil)
    }
    
    
    init(id: String, enabled: Bool, name: String, linkGroupAddress: Address? = nil, subLinkGroupAddress: Address? = nil, bindGroupAddresses: [Address] = [], sceneANumber: SceneNumber? = nil, sceneBNumber: SceneNumber? = nil, sceneCNumber: SceneNumber? = nil, sceneDNumber: SceneNumber? = nil, proxyNodeAddress: Address? = nil) {
        self.id = id
        self.enabled = enabled
        self.name = name
        self.linkGroupAddress = linkGroupAddress
        self.subLinkGroupAddress = subLinkGroupAddress
        self.bindGroupAddresses = bindGroupAddresses
        self.sceneANumber = sceneANumber
        self.sceneBNumber = sceneBNumber
        self.sceneCNumber = sceneCNumber
        self.sceneDNumber = sceneDNumber
        self.proxyNodeAddress = proxyNodeAddress
    }
    
    func copy() -> Self {
        let copy = DeviceSwitchData(id: id, enabled: enabled, name: name, linkGroupAddress: linkGroupAddress, subLinkGroupAddress: subLinkGroupAddress, bindGroupAddresses: bindGroupAddresses, sceneANumber: sceneANumber, sceneBNumber: sceneBNumber, sceneCNumber: sceneCNumber, sceneDNumber: sceneDNumber, proxyNodeAddress: proxyNodeAddress) as! Self
        copy.enOceanMacAddress = self.enOceanMacAddress
        copy.enOceanSecurityKey = self.enOceanSecurityKey
        copy.unbindGroupAddresses = self.unbindGroupAddresses
        copy.deleteProxyNodeAddress = self.deleteProxyNodeAddress
        copy.panelType = self.panelType
        return copy
    }
    
    func update(switchData: DeviceSwitchData) {
        self.name = switchData.name
        self.enabled = switchData.enabled
        self.panelType = switchData.panelType
        self.linkGroupAddress = switchData.linkGroupAddress
        self.subLinkGroupAddress = switchData.subLinkGroupAddress
        self.bindGroupAddresses = switchData.bindGroupAddresses
        self.unbindGroupAddresses = switchData.unbindGroupAddresses
        self.sceneANumber = switchData.sceneANumber
        self.sceneBNumber = switchData.sceneBNumber
        self.sceneCNumber = switchData.sceneCNumber
        self.sceneDNumber = switchData.sceneDNumber
        self.proxyNodeAddress = switchData.proxyNodeAddress
        self.deleteProxyNodeAddress = switchData.deleteProxyNodeAddress
        self.enOceanMacAddress = switchData.enOceanMacAddress
        self.enOceanSecurityKey = switchData.enOceanSecurityKey
        //        self.group = switchData.group
    }
    
    static func == (lhs: DeviceSwitchData, rhs: DeviceSwitchData) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.linkGroupAddress == rhs.linkGroupAddress && lhs.subLinkGroupAddress == rhs.subLinkGroupAddress && lhs.bindGroupAddresses == rhs.bindGroupAddresses && lhs.unbindGroupAddresses == rhs.unbindGroupAddresses && lhs.enabled == rhs.enabled && lhs.panelType == rhs.panelType && lhs.sceneANumber == rhs.sceneANumber && lhs.sceneBNumber == rhs.sceneBNumber && lhs.sceneCNumber == rhs.sceneCNumber && lhs.sceneDNumber == rhs.sceneDNumber && lhs.proxyNodeAddress == rhs.proxyNodeAddress && lhs.enOceanMacAddress == rhs.enOceanMacAddress && lhs.enOceanSecurityKey == rhs.enOceanSecurityKey
    }
    
    /// 判断开关配置是否已保存（用于替换面板前的检查）
    /// 故意不比较 enOceanMacAddress 和 enOceanSecurityKey，因为替换面板时这些字段会变化
    func isSavedForReplacingEnOceanPanel(comparedWith saved: DeviceSwitchData) -> Bool {
        return id == saved.id &&
               name == saved.name &&
               enabled == saved.enabled &&
               panelType == saved.panelType &&
               linkGroupAddress == saved.linkGroupAddress &&
               subLinkGroupAddress == saved.subLinkGroupAddress &&
               bindGroupAddresses == saved.bindGroupAddresses &&
               unbindGroupAddresses == saved.unbindGroupAddresses &&
               sceneANumber == saved.sceneANumber &&
               sceneBNumber == saved.sceneBNumber &&
               sceneCNumber == saved.sceneCNumber &&
               sceneDNumber == saved.sceneDNumber &&
               proxyNodeAddress == saved.proxyNodeAddress &&
               deleteProxyNodeAddress == saved.deleteProxyNodeAddress
    }

    var batteryPowerSwitchData: PJEightKeySwitchData? {
        guard proxyNode?.isPowerSwitch == true else {
            return nil
        }
        if let switchData = self as? PJEightKeySwitchData {
            return switchData
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: self)
    }
    
    
    /// 动能开关按键信息list
    var switchKeys: [SwitchKey] {
        var switchKeys: [SwitchKey] = []
        guard let mainAddress = self.linkGroupAddress else {
            return switchKeys
        }
        switch panelType {
        case .default_4key:
            let subAddress = self.subLinkGroupAddress
            switchKeys = [
                SwitchKey(key: 4, shortPressAction: .auto(address: mainAddress), longPressAction: .dimUp(address: mainAddress), direction: .up),
                SwitchKey(key: 3, shortPressAction: .off(address: mainAddress), longPressAction: .dimDown(address: mainAddress), direction: .down),
                SwitchKey(key: 2, shortPressAction: .sceneRecall(sceneA?.number), longPressAction: .cctUp(address: subAddress ?? mainAddress), direction: .up),
                SwitchKey(key: 1, shortPressAction: .sceneRecall(sceneB?.number), longPressAction: .cctDown(address: subAddress ?? mainAddress), direction: .down)
            ]
        case .default_2key:
            switchKeys = [
                SwitchKey(key: 4, shortPressAction: .auto(address: mainAddress), longPressAction: .dimUp(address: mainAddress), direction: .up),
                SwitchKey(key: 3, shortPressAction: .off(address: mainAddress), longPressAction: .dimDown(address: mainAddress), direction: .down)
            ]
        case .scenes_4key:
            let subAddress = self.subLinkGroupAddress
            switchKeys = [
                SwitchKey(key: 4, shortPressAction: .sceneRecall(sceneA?.number), longPressAction: .dimUp(address: mainAddress), direction: .up),
                SwitchKey(key: 3, shortPressAction: .sceneRecall(sceneB?.number), longPressAction: .dimDown(address: mainAddress), direction: .down),
                SwitchKey(key: 2, shortPressAction: .sceneRecall(sceneC?.number), longPressAction: .cctUp(address: subAddress ?? mainAddress), direction: .up),
                SwitchKey(key: 1, shortPressAction: .sceneRecall(sceneD?.number), longPressAction: .cctDown(address: subAddress ?? mainAddress), direction: .down)
            ]
        case .scenes_2key:
            switchKeys = [
                SwitchKey(key: 4, shortPressAction: .sceneRecall(sceneA?.number), longPressAction: .dimUp(address: mainAddress), direction: .up),
                SwitchKey(key: 3, shortPressAction: .sceneRecall(sceneB?.number), longPressAction: .dimDown(address: mainAddress), direction: .down)
            ]
        }
        return switchKeys
    }
    
//    var defaultSwitchKeys: [SwitchKey] {
//        var switchKeys: [SwitchKey] = []
////        guard let mainAddress = self.linkGroupAddress else {
////            return switchKeys
////        }
//        switch panelType {
//        case .default:
////            let subAddress = self.subLinkGroupAddress
//            switchKeys = [
//                SwitchKey(key: 4, shortPressAction: .auto(address: nil), longPressAction: .dimUp(address: nil), direction: .up),
//                SwitchKey(key: 3, shortPressAction: .off(address: nil), longPressAction: .dimDown(address: nil), direction: .down),
//                SwitchKey(key: 2, shortPressAction: .sceneRecall(sceneA?.number), longPressAction: .cctUp(address: nil), direction: .up),
//                SwitchKey(key: 1, shortPressAction: .sceneRecall(sceneB?.number), longPressAction: .cctDown(address: nil), direction: .down)
//            ]
//        case .scenes:
//            let subAddress = self.subLinkGroupAddress
//            switchKeys = [
//                SwitchKey(key: 4, shortPressAction: .auto(address: mainAddress), longPressAction: .dimUp(address: mainAddress), direction: .up),
//                SwitchKey(key: 3, shortPressAction: .off(address: mainAddress), longPressAction: .dimDown(address: mainAddress), direction: .down),
//                SwitchKey(key: 2, shortPressAction: .sceneRecall(sceneA?.number), longPressAction: .cctUp(address: subAddress ?? mainAddress), direction: .up),
//                SwitchKey(key: 1, shortPressAction: .sceneRecall(sceneB?.number), longPressAction: .cctDown(address: subAddress ?? mainAddress), direction: .down)
//            ]
//        }
//        return switchKeys
//    }
    
}
