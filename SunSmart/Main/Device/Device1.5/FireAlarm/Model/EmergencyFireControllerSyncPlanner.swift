//
//  EmergencyFireControllerSyncPlanner.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

/// 应急火警同步任务规划器。
/// 只负责把 desired configuration 转成同步页面可执行的任务，不直接发送 Mesh message。
/// 任务分为三类：
/// 1. EFC 控制器自身 publication/vendor 参数；
/// 2. 当前激活模式的灯组关联；
/// 3. 旧配置遗留灯组的订阅清理。
struct EmergencyFireControllerSyncPlanner {
    let data: DeviceEmerFireData
    let meshUUID: String
    let subnetworkId: String
    let changedFromConfiguration: EmergencyFireControllerConfiguration?

    init(
        data: DeviceEmerFireData,
        meshUUID: String,
        subnetworkId: String,
        changedFromConfiguration: EmergencyFireControllerConfiguration? = nil
    ) {
        self.data = data
        self.meshUUID = meshUUID
        self.subnetworkId = subnetworkId
        self.changedFromConfiguration = changedFromConfiguration
    }

    static func controllersAffecting(group: Group, in space: SpaceData) -> [DeviceEmerFireData] {
        DeviceEmerFireStore.shared.devices(in: space).filter { controller in
            guard controller.bindNode != nil else { return false }
            let settings = [
                controller.configuration.powerLossSettings,
                controller.configuration.fireAlarmSettings
            ]
            // 组成员变化时，不只看当前关联组，也要看 pending 清理组。
            // 退出组的灯如果曾经被 EFC 订阅过，需要继续走 cleanup。
            return settings.contains { setting in
                setting.associateGroupAddresses.contains(group.address.address) ||
                setting.pendingUnassociateGroupAddresses.contains(group.address.address)
            }
        }
    }

    static func makeGroupMutationItems(group: Group, addNodes: [Node], exitNodes: [Node], space: SpaceData) -> [EmergencyFireControllerSyncItem] {
        controllersAffecting(group: group, in: space).flatMap { controller -> [EmergencyFireControllerSyncItem] in
            guard controller.configuration.workMode != .allDisabled,
                  let publishGroupAddress = try? controller.ensurePublishGroup(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
                  let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)) else {
                return []
            }

            let planner = EmergencyFireControllerSyncPlanner(data: controller, meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            let activeDesiredGroups = controller.configuration.activeLightLCGroupAddresses
            let groupAddress = group.address.address
            let groupIsActiveDesired = activeDesiredGroups.contains(groupAddress)
            let pendingModes = planner.pendingCleanupModes(for: groupAddress)

            var tasks: [EmergencyFireControllerSyncTask] = []
            if groupIsActiveDesired,
               let settings = controller.activeModeSettings,
               let mode = planner.activeMode {
                let triggerScene = planner.triggerSceneNumber(for: mode)
                // 新进组的灯需要补齐 EFC 内部组订阅和触发场景。
                tasks.append(contentsOf: addNodes.flatMap {
                    planner.makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, triggerScene: triggerScene, brightness: settings.triggerBrightness)
                })
            }

            if groupIsActiveDesired || !pendingModes.isEmpty {
                // 退出组或等待清理的灯，需要取消对 EFC 内部 publish group 的订阅。
                tasks.append(contentsOf: exitNodes.flatMap {
                    planner.makeLightLCCleanupTasks(node: $0, group: group, publishGroup: publishGroup, pendingModes: pendingModes)
                })
            }
            guard !tasks.isEmpty else { return [] }
            return [EmergencyFireControllerSyncItem(name: controller.name, iconName: EmergencyFireControllerIconName.main, address: groupAddress, tasks: tasks, controller: controller)]
        }
    }

    func makeItems() throws -> [EmergencyFireControllerSyncItem] {
        // 同步前先确保内部 publish group 存在。
        // 这个 group 是 EFC 控制器发布和灯组订阅之间的桥，不是用户可见灯组。
        _ = try data.ensurePublishGroup(meshUUID: meshUUID, subnetworkId: subnetworkId)
        var items: [EmergencyFireControllerSyncItem] = []

        let controllerTasks = try data.makeControllerSyncTasks(meshUUID: meshUUID, subnetworkId: subnetworkId, changedFrom: changedFromConfiguration)
        if let node = data.bindNode {
            items.append(EmergencyFireControllerSyncItem(name: data.name, iconName: EmergencyFireControllerIconName.main, address: node.primaryUnicastAddress, tasks: controllerTasks, controller: data))
        }

        items.append(contentsOf: try makeActiveModeAssociateItems())
        items.append(contentsOf: try makeActiveModeCleanupItems())
        return items
    }

    func makeDeleteCleanupItems() -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            let items = makeDisableControllerItems()
            return items.isEmpty ? [makeLocalDeleteConfigurationItem()] : items
        }

        var items = makeDisableControllerItems()
        let addresses = Set(
            data.configuration.powerLossSettings.associateGroupAddresses +
            data.configuration.powerLossSettings.pendingUnassociateGroupAddresses +
            data.configuration.fireAlarmSettings.associateGroupAddresses +
            data.configuration.fireAlarmSettings.pendingUnassociateGroupAddresses
        )

        items.append(contentsOf: addresses.sorted().compactMap { address in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                return nil
            }

            let tasks = group.nodes.compactMap { node -> EmergencyFireControllerSyncTask? in
                guard node.state, node.isKeybindComplete else {
                    return nil
                }
                // 删除时只对真实仍在线、且确实订阅了内部 publish group 的灯下发清理。
                // 离线灯无法立即清理，所以删除流程最后仍要清本地 EFC 配置。
                let handles = makeDeleteCleanupMessageHandles(node: node, publishGroup: publishGroup)
                guard !handles.isEmpty else { return nil }
                return EmergencyFireControllerSyncTask(
                    title: node.name ?? group.name,
                    kind: .deleteCleanup,
                    address: node.primaryUnicastAddress,
                    messageHandles: handles
                )
            }

            guard !tasks.isEmpty else { return nil }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks, controller: data)
        })
        if items.isEmpty {
            items.append(makeLocalDeleteConfigurationItem())
        }
        return items
    }

    func makeActiveModeAssociateItems() throws -> [EmergencyFireControllerSyncItem] {
        guard let mode = activeMode, let settings = data.activeModeSettings, let publishGroup = data.publishGroup else {
            return []
        }
        let triggerScene = triggerSceneNumber(for: mode)

        return settings.associateGroupAddresses.compactMap { address in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                return nil
            }
            // 当前模式关联的每个灯组都展开为组内每个灯的同步任务。
            let tasks = group.nodes.flatMap {
                makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, triggerScene: triggerScene, brightness: settings.triggerBrightness)
            }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
        }
    }

    func makeActiveModeCleanupItems() throws -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            return []
        }

        let activeDesiredGroups = data.configuration.activeLightLCGroupAddresses
        // 如果 pending 组又重新成为当前模式的目标组，就不能清理，否则会把刚需要的订阅删掉。
        let pendingGroups = pendingCleanupGroups().filter { !activeDesiredGroups.contains($0.address) }

        return pendingGroups.map { pending in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(pending.address)) else {
                let task = makeLocalCleanupPendingTask(groupAddress: pending.address, pendingModes: pending.modes)
                return EmergencyFireControllerSyncItem(name: String(format: "%04X", pending.address), iconName: "device_light", address: pending.address, tasks: [task])
            }

            var tasks = group.nodes.flatMap {
                makeLightLCCleanupTasks(node: $0, group: group, publishGroup: publishGroup, pendingModes: pending.modes)
            }
            if tasks.isEmpty {
                tasks.append(makeLocalCleanupPendingTask(groupAddress: group.address.address, pendingModes: pending.modes))
            }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
        }
    }

    func makeAssociateTasks(node: Node, group: Group, publishGroup: Group, triggerScene: SceneNumber, brightness: Int) -> [EmergencyFireControllerSyncTask] {
        var tasks: [EmergencyFireControllerSyncTask] = []
        // Scene Server 订阅用于接收 EFC 触发/停止场景。
        if let sceneTask = makeSceneServerSubscriptionTask(node: node, group: group, publishGroup: publishGroup) {
            tasks.append(sceneTask)
        }
        // 这里会写入 EFC 保留场景。注意：该步骤会改变灯的当前亮度，后续如果补 profile 逻辑要考虑恢复现场。
        if let triggerTask = makeTriggerSceneStoreTask(node: node, triggerScene: triggerScene, brightness: brightness) {
            tasks.append(triggerTask)
        }
        // Light LC 订阅用于 EFC 直接让关联灯进入 Light LC On/恢复链路。
        if let lightLCTask = makeLightLCSubscriptionTask(node: node, group: group, publishGroup: publishGroup) {
            tasks.append(lightLCTask)
        }
        return tasks
    }

    func makeLightLCCleanupTasks(node: Node, group: Group, publishGroup: Group, pendingModes: [EmergencyFireControllerWorkMode]) -> [EmergencyFireControllerSyncTask] {
        let handles = makeCleanupMessageHandles(node: node, publishGroup: publishGroup)
        guard !handles.isEmpty else {
            return []
        }
        return [EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .lightLCCleanup, address: node.primaryUnicastAddress, messageHandles: handles, pendingModes: pendingModes, pendingGroupAddress: group.address.address, clearsUnassociatePending: !pendingModes.isEmpty)]
    }

    var activeMode: EmergencyFireControllerWorkMode? {
        switch data.configuration.workMode {
        case .powerLossEmergency, .fireAlarmEmergency:
            return data.configuration.workMode
        case .allDisabled:
            return nil
        }
    }

    func triggerSceneNumber(for mode: EmergencyFireControllerWorkMode) -> SceneNumber {
        switch mode {
        case .powerLossEmergency:
            return DeviceEmerFireData.powerLossTriggerSceneNumber
        case .fireAlarmEmergency:
            return DeviceEmerFireData.fireAlarmTriggerSceneNumber
        case .allDisabled:
            return DeviceEmerFireData.powerLossTriggerSceneNumber
        }
    }

    func pendingCleanupModes(for groupAddress: Address) -> [EmergencyFireControllerWorkMode] {
        [EmergencyFireControllerWorkMode.powerLossEmergency, .fireAlarmEmergency].filter { mode in
            data.settings(for: mode)?.pendingUnassociateGroupAddresses.contains(groupAddress) ?? false
        }
    }

    private func pendingCleanupGroups() -> [(address: Address, modes: [EmergencyFireControllerWorkMode])] {
        var groups: [Address: [EmergencyFireControllerWorkMode]] = [:]
        [EmergencyFireControllerWorkMode.powerLossEmergency, .fireAlarmEmergency].forEach { mode in
            data.settings(for: mode)?.pendingUnassociateGroupAddresses.forEach { address in
                groups[address, default: []].append(mode)
            }
        }
        return groups.map { (address: $0.key, modes: $0.value) }.sorted { $0.address < $1.address }
    }

    private func makeSceneServerSubscriptionTask(node: Node, group: Group, publishGroup: Group) -> EmergencyFireControllerSyncTask? {
        guard let model = node.sceneModel,
              !model.isSubscribed(to: publishGroup),
              let elementAddress = model.parentElement?.unicastAddress,
              model.companyIdentifier == nil,
              let message = ConfigModelSubscriptionAdd(parameters: Data() + elementAddress + publishGroup.address.address + UInt16(model.modelIdentifier)) else {
            return nil
        }
        return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .sceneSubscription, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)])
    }

    private func makeTriggerSceneStoreTask(node: Node, triggerScene: SceneNumber, brightness: Int) -> EmergencyFireControllerSyncTask? {
        guard let lightnessModel = node.lightnessModel,
              let sceneSetupModel = node.sceneSetupModel else {
            return nil
        }
        let lightness = Node.getLightness(lightness100: brightness)
        return EmergencyFireControllerSyncTask(
            title: "Trigger Scene",
            kind: .triggerScene,
            address: node.primaryUnicastAddress,
            messageHandles: [
                MeshMessageHandle(message: LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0), model: lightnessModel),
                MeshMessageHandle(message: SceneStore(triggerScene), model: sceneSetupModel)
            ]
        )
    }

    private func makeLightLCSubscriptionTask(node: Node, group: Group, publishGroup: Group) -> EmergencyFireControllerSyncTask? {
        guard let model = node.lightLCModel,
              !model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionAdd(group: publishGroup, to: model) else {
            return nil
        }
        return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .lightLCSubscription, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)])
    }

    private func makeLocalCleanupPendingTask(groupAddress: Address, pendingModes: [EmergencyFireControllerWorkMode]) -> EmergencyFireControllerSyncTask {
        // 找不到组或组内没有可下发节点时，也需要一个 local-only task 来清 pending 标记。
        // 这种任务没有 messageHandles，删除/清理流程不能要求 Mesh 在线。
        EmergencyFireControllerSyncTask(title: "LC Cleanup", kind: .lightLCCleanup, address: groupAddress, messageHandles: [], pendingModes: pendingModes, pendingGroupAddress: groupAddress, clearsUnassociatePending: true)
    }

    private func makeDeleteCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
        makeCleanupMessageHandles(node: node, publishGroup: publishGroup)
    }

    private func makeCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
        var handles: [MeshMessageHandle] = []
        if let model = node.sceneModel,
           model.isSubscribed(to: publishGroup),
           let elementAddress = model.parentElement?.unicastAddress,
           model.companyIdentifier == nil,
           let message = ConfigModelSubscriptionDelete(parameters: Data() + elementAddress + publishGroup.address.address + UInt16(model.modelIdentifier)) {
            let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }
        if let model = node.lightLCModel,
           model.isSubscribed(to: publishGroup),
           let message = ConfigModelSubscriptionDelete(group: publishGroup, from: model) {
            let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }
        return handles
    }

    private func makeDisableControllerItems() -> [EmergencyFireControllerSyncItem] {
        guard data.configuration.workMode != .allDisabled,
              let node = data.bindNode,
              node.isKeybindComplete,
              node.state,
              let vendorModel = node.sunricherVendorModel else {
            return []
        }
        let task = EmergencyFireControllerSyncTask(
            title: "Mode",
            kind: .workMode,
            address: node.primaryUnicastAddress,
            messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyMode(.disabled)), model: vendorModel)]
        )
        return [EmergencyFireControllerSyncItem(name: data.name, iconName: EmergencyFireControllerIconName.main, address: node.primaryUnicastAddress, tasks: [task], controller: data)]
    }

    private func makeLocalDeleteConfigurationItem() -> EmergencyFireControllerSyncItem {
        // 没有可执行 Mesh 消息时仍返回一个本地删除任务，保证同步页面/删除流程能统一收口。
        let task = EmergencyFireControllerSyncTask(
            title: data.name,
            kind: .deleteConfiguration,
            address: data.bindNodeAddress ?? data.publishGroupAddress ?? 0,
            messageHandles: []
        )
        return EmergencyFireControllerSyncItem(name: data.name, iconName: EmergencyFireControllerIconName.main, address: task.address, tasks: [task], controller: data)
    }
}
