//
//  GroupSwitch.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/12.
//

import Foundation
import NordicSigMeshSDK

class GroupSwitch: Copyable {
    
    
    /// 按键面板类型
    enum PanelType: UInt8 {
        var describe: String {
            return "default".localizedString
        }
        case `default` = 0
    }

    /// id
    let id: String
    /// 所属组地址
    let groupAddress: Address
    /// 所属的组
    var group: Group? {
        return MeshNetworkManager.instance.groups.first(where: { $0.address.address == groupAddress })
    }
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String
    /// 面板类型
    var panelType: PanelType = .default
    
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
    
    init(id: String, groupAddress: Address, enabled: Bool, name: String, sceneANumber: SceneNumber? = nil, sceneBNumber: SceneNumber? = nil, proxyNodeAddress: Address? = nil) {
        self.id = id
        self.groupAddress = groupAddress
        self.enabled = enabled
        self.name = name
        self.sceneANumber = sceneANumber
        self.sceneBNumber = sceneBNumber
        self.proxyNodeAddress = proxyNodeAddress
    }
    
    func copy() -> Self {
        return GroupSwitch(id: id, groupAddress: groupAddress, enabled: enabled, name: name, sceneANumber: sceneANumber, sceneBNumber: sceneBNumber, proxyNodeAddress: proxyNodeAddress) as! Self
    }
    
    func update(switchData: GroupSwitch) {
        self.name = switchData.name
        self.enabled = switchData.enabled
        self.panelType = switchData.panelType
        self.sceneANumber = switchData.sceneANumber
        self.sceneBNumber = switchData.sceneBNumber
        self.proxyNodeAddress = switchData.proxyNodeAddress
//        self.group = switchData.group
    }
    
    static func == (lhs: GroupSwitch, rhs: GroupSwitch) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.groupAddress == rhs.groupAddress && lhs.enabled == rhs.enabled && lhs.panelType == rhs.panelType && lhs.sceneANumber == rhs.sceneANumber && lhs.sceneBNumber == rhs.sceneBNumber && lhs.proxyNodeAddress == rhs.proxyNodeAddress
    }
    
}

struct EnOceanQRCodeData {
    
    /// mac地址
    let macAddress: String
    /// 密钥
    let securityKey: String
    /// 设备型号
    let model: String

    /// 根据二维码内容读取EnOcean按键信息
    init?(qrcode: String) {
        
        /// MAC截取头 截取12个字符
        let macIdentify = "30S"
        /// 密钥截取头 截取32个字符
        let securityKeyIdentify = "Z"
        /// 型号截取头 截取10个字符
        let modelIdentify = "30P"
        
        guard qrcode.count >= 82, qrcode.contains(macIdentify), qrcode.contains(securityKeyIdentify), qrcode.contains(modelIdentify) else {
            return nil
        }
        let qrcodeStr = qrcode as NSString
        // mac起始位置
        let macLocation = qrcodeStr.range(of: macIdentify).location + macIdentify.count
        // 密钥起始位置
        let securityKeyLocation = qrcodeStr.range(of: securityKeyIdentify).location + securityKeyIdentify.count
        // mac起始位置
        let modelLocation = qrcodeStr.range(of: modelIdentify).location + modelIdentify.count
        
        self.macAddress = qrcodeStr.substring(with: NSRange(location: macLocation, length: 12))
        self.securityKey = qrcodeStr.substring(with: NSRange(location: securityKeyLocation, length: 32))
        self.model = qrcodeStr.substring(with: NSRange(location: modelLocation, length: 10))
    }
    
}
