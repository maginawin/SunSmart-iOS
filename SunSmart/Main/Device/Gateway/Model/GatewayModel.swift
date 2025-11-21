//
//  GatewayModel.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/1.
//

import Foundation
import NordicSigMeshSDK


/// 网关连接状态
enum GatewayConnectStatus {
    case online      // 在线（绿色）
    case offline     // 离线（灰色）
    case inactive     // 未激活（黄色）
}

class GatewayModel: Copyable {
    
    /// site id
    let siteId: String
    /// 设备地址
    var address: Address
    /// mac地址
    let mac: String
    /// 是否启用
    var activate: Bool = false
    /// 关联的space list
    var associatedSpaces: [SpaceData]
    /// sim卡APN
    var apn: String?
    /// MQTT服务器信息
    var mqttServerInfo: GatewayInformation.MQTTConnectInformation?
    
    init(siteId: String,address: Address, mac: String, activate: Bool = false, associatedSpaces: [SpaceData] = [], apn: String? = nil, mqttServerInfo: GatewayInformation.MQTTConnectInformation? = nil) {
        self.siteId = siteId
        self.address = address
        self.mac = mac
        self.activate = activate
        self.associatedSpaces = associatedSpaces
        self.apn = apn
        self.mqttServerInfo = mqttServerInfo
    }
    
    func copy() -> Self {
        return GatewayModel(siteId: self.siteId, address: self.address, mac: self.mac, activate: self.activate, associatedSpaces: self.associatedSpaces, apn: self.apn, mqttServerInfo: self.mqttServerInfo) as! Self
    }
    
    static func == (lhs: GatewayModel, rhs: GatewayModel) -> Bool {
        guard lhs.siteId == rhs.siteId && lhs.address == rhs.address && lhs.mac == rhs.mac && lhs.activate == rhs.activate && lhs.associatedSpaces.map({ $0.id }) == rhs.associatedSpaces.map({ $0.id }) && lhs.apn == rhs.apn else {
            return false
        }
        if lhs.mqttServerInfo == nil || rhs.mqttServerInfo == nil {
            if lhs.mqttServerInfo == nil && rhs.mqttServerInfo == nil {
                return true
            }
            return false
        }
        return lhs.mqttServerInfo! == rhs.mqttServerInfo!
    }
    
    func update(gatewayModel: GatewayModel) {
        self.associatedSpaces = gatewayModel.associatedSpaces
        self.apn = gatewayModel.apn
        self.activate = gatewayModel.activate
        self.mqttServerInfo = gatewayModel.mqttServerInfo
    }
    
}
