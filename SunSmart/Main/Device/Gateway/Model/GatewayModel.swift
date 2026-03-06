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
    case reset       // 已重置
}

enum GatewaySignalLevel: Int {
    /// 信号好
    case goodSignal = 0
    /// 信号差
    case poorSignal = 1
    /// 无信号
    case noSignal = 2
    /// 信号异常
    case signalError = 3
    /// 未知信号质量（拿不到数据）
    case unknownSignal = 4
}

/// 网关权限状态
enum GatewayPermissionState: Int {
    /// 正常
    case normal = 1
    /// 无权限
    case noPermission = 2
}

class GatewayModel: Copyable {
    
    /// site id
    let siteId: String
    /// 网关名称
    var name: String
    /// 设备地址
    var address: Address
    /// 网关节点（运行期按address解析）
    var node: Node? {
        return resolveNode()
    }
    
    /// mac地址
    let mac: String
    /// 是否启用
    var activate: Bool = false
    /// 关联的space list
    var associatedSpaces: [GatewaySpaceData]
    /// sim卡APN
    var apn: String?
    /// MQTT服务器信息
    var mqttServerInfo: GatewayInformation.MQTTConnectInformation?
    /// 网关连接状态
    var connectStatus: GatewayConnectStatus = .offline
    /// 最后在线时间
    var lastOnlineTime: String?
    /// 重置时间
    var resetTime: String?
    /// 最近更新的时间（时间戳秒）
    var lastUpdate: Int64
    /// 最近上传到云端的时间
    var lastUploadCloudTimestamp: Int64?
    /// 同步服务器错误信息
    var syncCloudError: NetworkApiError?
    /// 网关最大关联space数量
    var maxAssociatedSpaces: Int = 10
    /// 网关绑定的所有space数据
//    var allBindSpaceDatas: [GatewaySpaceData]
    /// 是否插入SIM卡
    var isSimInserted: Bool = true
    /// 蜂窝信号强度（CSQ RSSI）
    var csqRssi: Int?
    
    /// 是否需要上传到云端
    var needUploadCloud: Bool {
        return lastUpdate > lastUploadCloudTimestamp ?? 0
    }
    
    /// 网关信号等级
    var signalLevel: GatewaySignalLevel {
        guard let csqRssi else {
            return .unknownSignal
        }
        
        if csqRssi == 99 {
            return .signalError
        } else if csqRssi >= 15 {
            return .goodSignal
        } else if csqRssi >= 5 {
            return .poorSignal
        } else if csqRssi >= 0 {
            return .noSignal
        } else {
            return .unknownSignal
        }
    }
    
    
    
    /// 展示的同步服务区错误信息
//    var showSyncCloudError: NetworkApiError? {
//        
//        guard needUploadCloud else {
//            return nil
//        }
//        
//        // 有错误则显示之前上传服务器错误，如没有错误并需要上传服务器并不在同步过程，则说明同步过程退出APP
////        return syncCloudError ?? (CloudSynchronizationManager.shared.getSpaceCurrentSyncState(self) == nil ? .unknown : nil)
//    }
    
    
    init(siteId: String, name: String, address: Address, mac: String, lastUpdate: Int64 = Int64(Date().timeIntervalSince1970), activate: Bool = false, associatedSpaces: [GatewaySpaceData] = [], apn: String? = nil, mqttServerInfo: GatewayInformation.MQTTConnectInformation? = nil) {
        self.siteId = siteId
        self.name = name
        self.address = address
        self.mac = mac
        self.activate = activate
        self.associatedSpaces = associatedSpaces
        self.apn = apn
        self.mqttServerInfo = mqttServerInfo
        self.lastUpdate = lastUpdate
    }
    
    func copy() -> Self {
        return GatewayModel(siteId: self.siteId, name: self.name, address: self.address, mac: self.mac, lastUpdate: self.lastUpdate, activate: self.activate, associatedSpaces: self.associatedSpaces, apn: self.apn, mqttServerInfo: self.mqttServerInfo) as! Self
    }
    
    static func == (lhs: GatewayModel, rhs: GatewayModel) -> Bool {
        guard lhs.siteId == rhs.siteId && lhs.name == rhs.name && lhs.address == rhs.address && lhs.mac == rhs.mac && lhs.activate == rhs.activate && lhs.associatedSpaces.map({ $0.spaceId }) == rhs.associatedSpaces.map({ $0.spaceId }) && lhs.apn == rhs.apn else {
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
        self.name = gatewayModel.name
        self.address = gatewayModel.address
        self.associatedSpaces = gatewayModel.associatedSpaces
        self.apn = gatewayModel.apn
        self.activate = gatewayModel.activate
        self.mqttServerInfo = gatewayModel.mqttServerInfo
    }
    
    func resolveNode(in meshNetwork: MeshNetwork? = MeshNetworkManager.instance.meshNetwork) -> Node? {
        return meshNetwork?.node(withAddress: address)
    }
    
}

/// 运行期网关聚合对象（Node + GatewayModel）
final class Gateway {
    let model: GatewayModel
    let node: Node
    
    init(model: GatewayModel, node: Node) {
        self.model = model
        self.node = node
    }
    
    static func resolve(model: GatewayModel) -> Gateway? {
        guard let node = model.resolveNode() else {
            return nil
        }
        return Gateway(model: model, node: node)
    }
}

extension Gateway {
    var siteId: String { model.siteId }
    var name: String {
        get { model.name }
        set { model.name = newValue }
    }
    var mac: String { model.mac }
    var address: Address {
        get { model.address }
        set { model.address = newValue }
    }
    var activate: Bool {
        get { model.activate }
        set { model.activate = newValue }
    }
    var associatedSpaces: [GatewaySpaceData] {
        get { model.associatedSpaces }
        set { model.associatedSpaces = newValue }
    }
    var connectStatus: GatewayConnectStatus {
        get { model.connectStatus }
        set { model.connectStatus = newValue }
    }
    var lastOnlineTime: String? {
        get { model.lastOnlineTime }
        set { model.lastOnlineTime = newValue }
    }
    var resetTime: String? {
        get { model.resetTime }
        set { model.resetTime = newValue }
    }
    var lastUpdate: Int64 {
        get { model.lastUpdate }
        set { model.lastUpdate = newValue }
    }
    var syncCloudError: NetworkApiError? {
        get { model.syncCloudError }
        set { model.syncCloudError = newValue }
    }
    func save() {
        model.save()
    }
}

extension GatewayModel {
    static func load(node: Node) -> GatewayModel? {
        guard node.deviceType == .gateway else {
            return nil
        }
        guard let meshUUID = node.network?.uuid.uuidString ?? MeshNetworkManager.instance.meshNetwork?.uuid.uuidString else {
            return nil
        }
        if let mac = node.macAddress, let model = GatewayModel.load(siteId: meshUUID, macAddress: mac).first {
            return model
        }
        return GatewayModel.load(siteId: meshUUID, address: node.primaryUnicastAddress).first
    }
    
    @discardableResult static func bind(to node: Node, model: GatewayModel, persist: Bool = true) -> Gateway {
        model.address = node.primaryUnicastAddress
        if model.name.isEmpty {
            model.name = node.name ?? model.name
        }
        if persist {
            model.save()
        }
        return Gateway(model: model, node: node)
    }
    
    static func resolve(node: Node) -> Gateway? {
        guard let model = GatewayModel.load(node: node) else {
            return nil
        }
        return Gateway(model: model, node: node)
    }
}

/// 网关space数据
class GatewaySpaceData: Codable {
    
    /// 网关关联的space权限
    enum GatewaySpacePermission: Int {
        /// 无权限
        case none = 0
        /// 有编辑权限
        case editor = 1
        /// 权限异常（需要输入密码）
        case permissionException = 2
    }
    
    /// space id
    let spaceId: String
    /// space名称
    let spaceName: String
    /// space内设备数量
    let deviceCount: Int
    /// space appkey index
    let appKeyIndex: UInt16
    /// 权限（自身在space的权限）
    var permission: GatewaySpacePermission = .none
    
    
    init(spaceId: String, spaceName: String, deviceCount: Int, appKeyIndex: UInt16, permission: GatewaySpacePermission = .none) {
        self.spaceId = spaceId
        self.spaceName = spaceName
        self.deviceCount = deviceCount
        self.appKeyIndex = appKeyIndex
        self.permission = permission
    }
    
    // MARK: - Codable
    
    private enum CodingKeys: String, CodingKey {
        case spaceId
        case spaceName
        case deviceCount
        case appKeyIndex
    }
    
    required init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.spaceId = try container.decode(String.self, forKey: .spaceId)
        self.spaceName = try container.decode(String.self, forKey: .spaceName)
        self.deviceCount = try container.decode(Int.self, forKey: .deviceCount)
        self.appKeyIndex = try container.decode(UInt16.self, forKey: .appKeyIndex)
    }
    
    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.spaceId, forKey: .spaceId)
        try container.encode(self.spaceName, forKey: .spaceName)
        try container.encode(self.deviceCount, forKey: .deviceCount)
        try container.encode(self.appKeyIndex, forKey: .appKeyIndex)
    }
}

/// 网关sim卡信息
struct GatewaySIMApnInfo {
    /// 国家
    let country: String
    /// sim/apn list
    let apns: [String]
    
    static let all: [GatewaySIMApnInfo] = [
        .init(country: "singapore".localizedString, apns: ["internet", "shwap", "sunsurf", "tpg"]),
        .init(country: "china".localizedString, apns: ["cmnet", "3gnet", "ctnet"]),
        .init(country: "usa".localizedString, apns: ["phone", "internet", "fast.t-mobile.com"]),
        .init(country: "canada".localizedString, apns: ["ltemobile.apn", "pda.bell.ca", "sp.telus.com"]),
        .init(country: "usa".localizedString, apns: ["telekom.de", "web.vodafone.de", "internet"])
    ]
}
