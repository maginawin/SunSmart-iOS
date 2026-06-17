//
//  DeviceEmerFireData.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

extension Notification.Name {
    static let deviceEmerFireDataDidChange = Notification.Name("deviceEmerFireDataDidChange")
}

/// 应急火警控制器的本地聚合入口。
/// 这里负责把数据库中的 EFC 配置和当前 Mesh 网络里真实的 emergencyController 节点合并，
/// 页面层尽量通过 Store 读写，避免直接操作 Repository 后漏掉缓存、通知和 proxy filter 刷新。
final class DeviceEmerFireStore {

    static let shared = DeviceEmerFireStore()

    private let repository = DeviceEmerFireRepository.shared
    private(set) var devices: [DeviceEmerFireData] = []

    private init() {}

    func loadDevices(meshUUID: String, meshNetworkId: String) -> [DeviceEmerFireData] {
        let devices = mergeRealEmergencyControllers(
            repository.load(meshUUID: meshUUID, meshNetworkId: meshNetworkId),
            space: nil,
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId
        )
        self.devices = devices
        return devices
    }

    func devices(in space: SpaceData) -> [DeviceEmerFireData] {
        let devices = mergeRealEmergencyControllers(
            repository.load(
                meshUUID: space.meshUUID,
                meshNetworkId: space.meshNetworkId,
                spaceId: space.id
            ),
            space: space,
            meshUUID: space.meshUUID,
            meshNetworkId: space.meshNetworkId
        )
        mergeCache(with: devices)
        return devices
    }

    func device(id: String, meshUUID: String, meshNetworkId: String) -> DeviceEmerFireData? {
        repository.load(meshUUID: meshUUID, meshNetworkId: meshNetworkId, id: id).first
    }

    func nextDefaultName(space: SpaceData) -> String {
        let baseName = "EFC"
        var index = 1
        let devices = self.devices(in: space)
        while devices.contains(where: { $0.name == "\(baseName)\(index)" }) {
            index += 1
        }
        return "\(baseName)\(index)"
    }

    func isNameDuplicated(_ name: String, space: SpaceData, excluding deviceId: String? = nil) -> Bool {
        devices(in: space).contains { device in
            device.id != deviceId && device.name == name
        }
    }

    func selectableGroups(excluding device: DeviceEmerFireData? = nil) -> [Group] {
        let internalPublishAddress = device?.publishGroupAddress
        return MeshNetworkManager.instance.groups
            .filter { group in
                group.address.address.isGroup &&
                !group.address.address.isSpecialGroup &&
                // EFC 自己创建的 virtual group 只作为内部 publish group 使用，不能暴露给用户重复选择。
                !group.isVirtual &&
                group.address.address != internalPublishAddress
            }
            .sorted { $0.address.address < $1.address.address }
    }

    /// 确保真实 EFC 节点有一条本地配置记录。
    /// 设备可能是从 Mesh 网络恢复/导入进来的，未必经历过 App 的添加配置流程。
    @discardableResult
    func ensureDevice(for node: Node, in space: SpaceData) -> DeviceEmerFireData {
        if let device = devices(in: space).first(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) {
            ensurePublishGroupIfNeeded(for: device, in: space)
            return device
        }

        let device = DeviceEmerFireData.default(space: space)
        device.bindNodeAddress = node.primaryUnicastAddress
        node.name = device.name
        node.save()
        save(device)
        ensurePublishGroupIfNeeded(for: device, in: space)
        return device
    }

    @discardableResult
    func bind(_ device: DeviceEmerFireData, to node: Node, in space: SpaceData) -> DeviceEmerFireData {
        let target = self.device(id: device.id, meshUUID: space.meshUUID, meshNetworkId: space.meshNetworkId) ?? device
        target.bindNodeAddress = node.primaryUnicastAddress
        node.name = target.name
        node.save()
        // 绑定节点变更后，真实控制器的 publication/mode/resend 等都需要重新同步。
        target.isSynced = false
        save(target)
        ensurePublishGroupIfNeeded(for: target, in: space)
        if target !== device {
            device.update(deviceData: target)
        }
        return target
    }

    @discardableResult
    func restoreDevice(replacing oldNode: Node, with newNode: Node, in space: SpaceData) -> DeviceEmerFireData? {
        guard oldNode.deviceType == .emergencyController || newNode.deviceType == .emergencyController else {
            return nil
        }

        let storedDevices = devices(in: space)
        let target = storedDevices.first { $0.bindNodeAddress == oldNode.primaryUnicastAddress }
            ?? storedDevices.first { $0.bindNodeAddress == newNode.primaryUnicastAddress }
            ?? DeviceEmerFireData.default(space: space)

        newNode.name = target.name
        newNode.save()
        target.bindNodeAddress = newNode.primaryUnicastAddress
        target.isSynced = false
        save(target)
        ensurePublishGroupIfNeeded(for: target, in: space)

        storedDevices
            .filter { $0.id != target.id && $0.bindNodeAddress == newNode.primaryUnicastAddress }
            .forEach { delete($0) }

        return target
    }

    func save(_ device: DeviceEmerFireData) {
        _ = repository.save(device)
        mergeCache(with: [device])
        // EFC 的内部 publish group 会影响手动控制拦截和 proxy filter，需要在保存后刷新。
        EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()
        notifyDidChange()
    }

    func delete(_ device: DeviceEmerFireData) {
        _ = repository.delete(device)
        devices.removeAll(where: { $0.id == device.id })
        EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()
        notifyDidChange()
    }

    func deleteCachedDevice(_ device: DeviceEmerFireData) {
        removePublishGroupIfNeeded(for: device)
        delete(device)
    }

    func clearMonitoringConfiguration(for device: DeviceEmerFireData) {
        device.clearMonitoringConfiguration()
        save(device)
    }

    private func mergeRealEmergencyControllers(_ storedDevices: [DeviceEmerFireData], space: SpaceData?, meshUUID: String, meshNetworkId: String) -> [DeviceEmerFireData] {
        var devices = storedDevices
        let realNodes = MeshNetworkManager.instance.realNodes.filter { $0.deviceType == .emergencyController }
        realNodes.forEach { node in
            if !devices.contains(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) {
                // 真实 Mesh 节点已经存在但本地还没有配置时，补一条未同步记录。
                // 这样列表能显示出来，并引导用户进入编辑/同步，而不是静默丢失这个控制器。
                let name = nextDefaultName(in: devices)
                let device = DeviceEmerFireData(
                    id: UUID().uuidString,
                    spaceId: space?.id ?? "",
                    meshUUID: meshUUID,
                    meshNetworkId: meshNetworkId,
                    name: name,
                    bindNodeAddress: node.primaryUnicastAddress,
                    isSynced: false,
                    reportToGateway: true
                )
                node.name = name
                node.save()
                _ = repository.save(device)
                if let space {
                    ensurePublishGroupIfNeeded(for: device, in: space)
                }
                devices.append(device)
            }
        }
        return devices.sorted { $0.createTime < $1.createTime }
    }

    private func nextDefaultName(in devices: [DeviceEmerFireData]) -> String {
        let baseName = "EFC"
        var index = 1
        while devices.contains(where: { $0.name == "\(baseName)\(index)" }) {
            index += 1
        }
        return "\(baseName)\(index)"
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

    private func ensurePublishGroupIfNeeded(for device: DeviceEmerFireData, in space: SpaceData) {
        guard device.publishGroupAddress == nil else {
            EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()
            return
        }
        do {
            _ = try device.ensurePublishGroup(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            mergeCache(with: [device])
            EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()
        } catch {
            print("[EFC] failed to ensure publish group device=\(device.name), error=\(error.localizedDescription)")
        }
    }

    private func removePublishGroupIfNeeded(for device: DeviceEmerFireData) {
        guard let publishGroupAddress = device.publishGroupAddress,
              let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)) else {
            return
        }
        do {
            // 这里只删除本地 MeshNetwork 缓存里的内部 virtual group。
            // 灯节点订阅清理由 SyncPlanner 生成 Mesh message 处理，不能混在这里做。
            try MeshNetworkManager.instance.meshNetwork?.remove(group: publishGroup)
            print("[EFC] removed cached publish group device=\(device.name), address=\(String(format: "0x%04X", publishGroupAddress))")
        } catch {
            print("[EFC] failed to remove cached publish group device=\(device.name), address=\(String(format: "0x%04X", publishGroupAddress)), error=\(error)")
        }
    }

    private func notifyDidChange() {
        let postNotification = {
            NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
        }
        if Thread.isMainThread {
            postNotification()
        } else {
            DispatchQueue.main.async {
                postNotification()
            }
        }
    }
}

/// 一条应急火警控制器配置。
/// 它不是普通 Node 的子类，而是“本地配置 + 绑定真实 EFC 节点 + 内部 publish group”的组合业务对象。
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
    /// Scene Client publication 使用的内部 virtual group 地址
    var publishGroupAddress: Address?
    /// 绑定的设备
    var bindNode: Node? {
        guard let address = bindNodeAddress else { return nil }
        return MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)
    }
    /// EFC Scene Client 发布场景使用的内部 virtual group。
    var publishGroup: Group? {
        guard let address = publishGroupAddress else { return nil }
        return MeshNetworkManager.instance.virtualGroups.first(where: { $0.address.address == address })
    }
    /// 是否已同步
    var isSynced: Bool
    /// 是否设置了网关
    var reportToGateway: Bool
    /// 已关联的网关
    var gateWayData: GatewayModel?
    /// 真实 EFC desired configuration。
    var configuration: EmergencyFireControllerConfiguration

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
        // 只有有可同步配置时才展示同步异常；纯本地空配置不应误报。
        if hasSyncableConfiguration, !isSynced {
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
        publishGroupAddress: Address? = nil,
        isSynced: Bool = false,
        reportToGateway: Bool,
        gatWayData: GatewayModel? = nil,
        configuration: EmergencyFireControllerConfiguration? = nil,
        createTime: Int64 = Int64(Date().timeIntervalSince1970),
        lastUpdate: Int64? = nil
    ) {
        self.id = id
        self.spaceId = spaceId
        self.meshUUID = meshUUID
        self.meshNetworkId = meshNetworkId
        self.name = name
        self.bindNodeAddress = bindNodeAddress
        self.publishGroupAddress = publishGroupAddress
        self.isSynced = isSynced
        self.reportToGateway = reportToGateway
        self.gateWayData = gatWayData
        self.configuration = configuration ?? .defaultValue
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
            reportToGateway: true
        )
    }

    func update(deviceData: DeviceEmerFireData) {
        name = deviceData.name
        bindNodeAddress = deviceData.bindNodeAddress
        publishGroupAddress = deviceData.publishGroupAddress
        isSynced = deviceData.isSynced
        reportToGateway = deviceData.reportToGateway
        gateWayData = deviceData.gateWayData
        configuration = deviceData.configuration
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
            publishGroupAddress: publishGroupAddress,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            gatWayData: gateWayData,
            configuration: configuration,
            createTime: createTime,
            lastUpdate: lastUpdate
        ) as! Self
    }

    func toConfig() -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceId: id,
            spaceId: spaceId,
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId,
            deviceName: name,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            publishGroupAddress: publishGroupAddress,
            configuration: configuration
        )
    }

    func clearMonitoringConfiguration() {
        isSynced = true
        reportToGateway = true
        configuration = .defaultValue
        lastUpdate = Int64(Date().timeIntervalSince1970)
    }
}
