//
//  DeviceEmerFireData.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/27.
//

import Foundation
import NordicSigMeshSDK

extension Notification.Name {
    static let deviceEmerFireDataDidChange = Notification.Name("deviceEmerFireDataDidChange")
}

final class DeviceEmerFireStore {

    static let shared = DeviceEmerFireStore()

    private let repository = DeviceEmerFireRepository.shared
    private(set) var devices: [DeviceEmerFireData] = []

    private init() {}

    func loadDevices(meshUUID: String, meshNetworkId: String) -> [DeviceEmerFireData] {
        let devices = repository.load(meshUUID: meshUUID, meshNetworkId: meshNetworkId)
        self.devices = devices
        return devices
    }

    func devices(in space: SpaceData) -> [DeviceEmerFireData] {
        let devices = repository.load(
            meshUUID: space.meshUUID,
            meshNetworkId: space.meshNetworkId,
            spaceId: space.id
        )
        mergeCache(with: devices)
        return devices
    }

    func device(id: String, meshUUID: String, meshNetworkId: String) -> DeviceEmerFireData? {
        repository.load(meshUUID: meshUUID, meshNetworkId: meshNetworkId, id: id).first
    }

    func nextDefaultName(space: SpaceData) -> String {
        let baseName = "EFC "
        var index = 1
        let devices = self.devices(in: space)
        while devices.contains(where: { $0.name == "\(baseName)\(index)" }) {
            index += 1
        }
        return "\(baseName)\(index)"
    }

    func save(_ device: DeviceEmerFireData) {
        _ = repository.save(device)
        mergeCache(with: [device])
        notifyDidChange()
    }

    func delete(_ device: DeviceEmerFireData) {
        _ = repository.delete(device)
        devices.removeAll(where: { $0.id == device.id })
        notifyDidChange()
    }

    private func mergeCache(with newDevices: [DeviceEmerFireData]) {
        newDevices.forEach { device in
            if let index = devices.firstIndex(where: { $0.id == device.id }) {
                devices[index] = device
            } else {
                devices.append(device)
            }
        }
    }

    private func notifyDidChange() {
        NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
    }
}

class DeviceEmerFireData: Copyable {

    /// id
    let id: String
    /// space id
    let spaceId: String
    /// mesh uuid
    let meshUUID: String
    /// mesh network id
    let meshNetworkId: String
    /// 名称
    var name: String
    /// 绑定的DeviceEmerFire节点地址
    var bindNodeAddress: Address?
    /// 绑定的设备
    var bindNode: Node? {
        guard let address = bindNodeAddress else { return nil }
        return MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)
    }
    /// 是否已同步
    var isSynced: Bool
    /// 是否设置了网关
    var reportToGateway: Bool
    /// 已关联的网关
    var gateWayData: GatewayModel?

    /// 应急断电开关
    var enablePowerLossEmergency: Bool
    /// 应急火警开关
    var enableFireAlarmEmergency: Bool

    /// 断电组索引
    var powerLossGroupIndex: Int
    /// 火警组索引
    var fireAlarmGroupIndex: Int
    /// 断电关联组
    var powerLossGroupAddresses: [UInt16]
    /// 火警关联组
    var fireAlarmGroupAddresses: [UInt16]

    /// 断电亮度
    var powerLossBrightness: Int
    /// 断电恢复时长
    var powerLossResuming: Int
    /// 断电发送次数
    var powerLossSendCount: Int

    /// 火警亮度
    var fireAlarmBrightness: Int
    /// 火警恢复时长
    var fireAlarmResuming: Int
    /// 火警发送次数
    var fireAlarmSendCount: Int
    /// 创建时间
    let createTime: Int64
    /// 最后更新时间
    var lastUpdate: Int64

    var displayStatus: EmerFireStatus {
        guard let node = bindNode else {
            return .unboundDevice
        }
        guard node.isKeybindComplete else {
            return .repairRequiredDevice
        }
        guard node.state else {
            return .offlineBoundDevice
        }
        if !reportToGateway {
            return .gatewayUnassignedWarning
        }
        if !isSynced {
            return .syncIssueDevice
        }
        return .onlineBoundDevice
    }

    init(
        id: String,
        spaceId: String,
        meshUUID: String,
        meshNetworkId: String,
        name: String,
        bindNodeAddress: Address? = nil,
        isSynced: Bool = false,
        reportToGateway: Bool,
        gatWayData: GatewayModel? = nil,
        enablePowerLossEmergency: Bool,
        enableFireAlarmEmergency: Bool,
        powerLossGroupIndex: Int = 1,
        fireAlarmGroupIndex: Int = 1,
        powerLossGroupAddresses: [UInt16] = [],
        fireAlarmGroupAddresses: [UInt16] = [],
        powerLossBrightness: Int = 25,
        powerLossResuming: Int = 2,
        powerLossSendCount: Int = 2,
        fireAlarmBrightness: Int = 100,
        fireAlarmResuming: Int = 2,
        fireAlarmSendCount: Int = 2,
        createTime: Int64 = Int64(Date().timeIntervalSince1970),
        lastUpdate: Int64? = nil
    ) {
        self.id = id
        self.spaceId = spaceId
        self.meshUUID = meshUUID
        self.meshNetworkId = meshNetworkId
        self.name = name
        self.bindNodeAddress = bindNodeAddress
        self.isSynced = isSynced
        self.reportToGateway = reportToGateway
        self.gateWayData = gatWayData
        self.enablePowerLossEmergency = enablePowerLossEmergency
        self.enableFireAlarmEmergency = enableFireAlarmEmergency
        self.powerLossGroupIndex = powerLossGroupIndex
        self.fireAlarmGroupIndex = fireAlarmGroupIndex
        self.powerLossGroupAddresses = powerLossGroupAddresses
        self.fireAlarmGroupAddresses = fireAlarmGroupAddresses
        self.powerLossBrightness = powerLossBrightness
        self.powerLossResuming = powerLossResuming
        self.powerLossSendCount = min(max(powerLossSendCount, 1), 5)
        self.fireAlarmBrightness = fireAlarmBrightness
        self.fireAlarmResuming = fireAlarmResuming
        self.fireAlarmSendCount = min(max(fireAlarmSendCount, 1), 5)
        self.createTime = createTime
        self.lastUpdate = lastUpdate ?? createTime
    }

    static func `default`(space: SpaceData, id: String = UUID().uuidString) -> DeviceEmerFireData {
        DeviceEmerFireData(
            id: id,
            spaceId: space.id,
            meshUUID: space.meshUUID,
            meshNetworkId: space.meshNetworkId,
            name: DeviceEmerFireStore.shared.nextDefaultName(space: space),
            reportToGateway: true,
            enablePowerLossEmergency: true,
            enableFireAlarmEmergency: false
        )
    }

    func update(deviceData: DeviceEmerFireData) {
        name = deviceData.name
        bindNodeAddress = deviceData.bindNodeAddress
        isSynced = deviceData.isSynced
        reportToGateway = deviceData.reportToGateway
        gateWayData = deviceData.gateWayData
        enablePowerLossEmergency = deviceData.enablePowerLossEmergency
        enableFireAlarmEmergency = deviceData.enableFireAlarmEmergency
        powerLossGroupIndex = deviceData.powerLossGroupIndex
        fireAlarmGroupIndex = deviceData.fireAlarmGroupIndex
        powerLossGroupAddresses = deviceData.powerLossGroupAddresses
        fireAlarmGroupAddresses = deviceData.fireAlarmGroupAddresses
        powerLossBrightness = deviceData.powerLossBrightness
        powerLossResuming = deviceData.powerLossResuming
        powerLossSendCount = deviceData.powerLossSendCount
        fireAlarmBrightness = deviceData.fireAlarmBrightness
        fireAlarmResuming = deviceData.fireAlarmResuming
        fireAlarmSendCount = deviceData.fireAlarmSendCount
        lastUpdate = Int64(Date().timeIntervalSince1970)
    }

    func copy() -> Self {
        DeviceEmerFireData(
            id: id,
            spaceId: spaceId,
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId,
            name: name,
            bindNodeAddress: bindNodeAddress,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            gatWayData: gateWayData,
            enablePowerLossEmergency: enablePowerLossEmergency,
            enableFireAlarmEmergency: enableFireAlarmEmergency,
            powerLossGroupIndex: powerLossGroupIndex,
            fireAlarmGroupIndex: fireAlarmGroupIndex,
            powerLossGroupAddresses: powerLossGroupAddresses,
            fireAlarmGroupAddresses: fireAlarmGroupAddresses,
            powerLossBrightness: powerLossBrightness,
            powerLossResuming: powerLossResuming,
            powerLossSendCount: powerLossSendCount,
            fireAlarmBrightness: fireAlarmBrightness,
            fireAlarmResuming: fireAlarmResuming,
            fireAlarmSendCount: fireAlarmSendCount,
            createTime: createTime,
            lastUpdate: lastUpdate
        ) as! Self
    }
}
