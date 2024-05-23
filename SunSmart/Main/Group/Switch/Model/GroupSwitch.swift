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
    /// 所属的组
    let group: Group
    /// 是否启用
    var enabled: Bool = false
    /// 名称
    var name: String
    /// 面板类型
    var panelType: PanelType = .default
    /// 一键选择的场景
    var sceneA: Scene?
    /// 二键选择的场景
    var sceneB: Scene?
    /// 选择的代理节点（绑定设备后）
    var proxyNode: Node?
    /// 绑定真实动能开关mac
    var enOceanMacAddress: String?
    
    init(id: String, group: Group, enabled: Bool, name: String, sceneA: Scene? = nil, sceneB: Scene? = nil, proxyNode: Node? = nil) {
        self.id = id
        self.group = group
        self.enabled = enabled
        self.name = name
        self.sceneA = sceneA
        self.sceneB = sceneB
        self.proxyNode = proxyNode
    }
    
    func copy() -> Self {
        return GroupSwitch(id: id, group: group, enabled: enabled, name: name, sceneA: sceneA, sceneB: sceneB, proxyNode: proxyNode) as! Self
    }
    
    func update(switchData: GroupSwitch) {
        self.name = switchData.name
        self.enabled = switchData.enabled
        self.panelType = switchData.panelType
        self.sceneA = switchData.sceneA
        self.sceneB = switchData.sceneB
        self.proxyNode = switchData.proxyNode
//        self.group = switchData.group
    }
    
    static func == (lhs: GroupSwitch, rhs: GroupSwitch) -> Bool {
        return lhs.id == rhs.id && lhs.name == rhs.name && lhs.group == rhs.group && lhs.enabled == rhs.enabled && lhs.panelType == rhs.panelType && lhs.sceneA == rhs.sceneA && lhs.sceneB == rhs.sceneB && lhs.proxyNode == rhs.proxyNode
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
