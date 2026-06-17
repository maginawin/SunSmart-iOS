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
/// 2. Power Loss / Fire Alarm 两个功能的灯组关联；
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
            guard controller.configuration.hasSyncIntent,
                  let publishGroupAddress = try? controller.ensurePublishGroup(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
                  let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)) else {
                return []
            }

            let planner = EmergencyFireControllerSyncPlanner(data: controller, meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            let activeDesiredGroups = controller.configuration.activeLightLCGroupAddresses
            let groupAddress = group.address.address
            let groupIsActiveDesired = activeDesiredGroups.contains(groupAddress)
            let pendingFunctions = planner.pendingCleanupFunctions(for: groupAddress)

            var tasks: [EmergencyFireControllerSyncTask] = []
            if groupIsActiveDesired {
                // 新进组的灯需要补齐 EFC Group 的业务控制模型订阅。
                tasks.append(contentsOf: addNodes.flatMap {
                    planner.makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup)
                })
            }

            if groupIsActiveDesired || !pendingFunctions.isEmpty {
                // 退出组或等待清理的灯，需要取消对 EFC 内部 publish group 的订阅。
                tasks.append(contentsOf: exitNodes.flatMap {
                    planner.makeAssociationCleanupTasks(node: $0, group: group, publishGroup: publishGroup, pendingFunctions: pendingFunctions)
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

        items.append(contentsOf: try makeAssociatedGroupItems())
        items.append(contentsOf: try makeCleanupItems())
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

    func makeAssociatedGroupItems() throws -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            return []
        }

        return data.configuration.activeLightLCGroupAddresses.sorted().compactMap { address in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                return nil
            }
            // 每个关联灯组都展开为组内每个灯的同步任务。
            let tasks = group.nodes.flatMap {
                makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup)
            }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
        }
    }

    func makeCleanupItems() throws -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            return []
        }

        let activeDesiredGroups = data.configuration.activeLightLCGroupAddresses
        // 如果 pending 组又重新成为当前模式的目标组，就不能清理，否则会把刚需要的订阅删掉。
        let pendingGroups = pendingCleanupGroups().filter { !activeDesiredGroups.contains($0.address) }

        return pendingGroups.map { pending in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(pending.address)) else {
                let task = makeLocalCleanupPendingTask(groupAddress: pending.address, pendingFunctions: pending.functions)
                return EmergencyFireControllerSyncItem(name: String(format: "%04X", pending.address), iconName: "device_light", address: pending.address, tasks: [task])
            }

            var tasks = group.nodes.flatMap {
                makeAssociationCleanupTasks(node: $0, group: group, publishGroup: publishGroup, pendingFunctions: pending.functions)
            }
            if tasks.isEmpty {
                tasks.append(makeLocalCleanupPendingTask(groupAddress: group.address.address, pendingFunctions: pending.functions))
            }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
        }
    }

    func makeAssociateTasks(
        node: Node,
        group: Group,
        publishGroup: Group
    ) -> [EmergencyFireControllerSyncTask] {
        var tasks: [EmergencyFireControllerSyncTask] = []
        if let lightnessTask = makeLightnessSubscriptionTask(node: node, group: group, publishGroup: publishGroup) {
            tasks.append(lightnessTask)
        }

        let usesRestoreAuto = data.configuration.restoreSettings.actionType == .restoreAuto
        if usesRestoreAuto {
            if let lightLCTask = makeLightLCSubscriptionTask(node: node, group: group, publishGroup: publishGroup) {
                tasks.append(lightLCTask)
            }
            if let cleanupTask = makeHistoricalSubscriptionCleanupTask(node: node, group: group, publishGroup: publishGroup) {
                tasks.append(cleanupTask)
            }
        } else if let cleanupTask = makeNonAutoRestoreCleanupTask(node: node, group: group, publishGroup: publishGroup) {
            tasks.append(cleanupTask)
        }
        return tasks
    }

    func makeAssociationCleanupTasks(node: Node, group: Group, publishGroup: Group, pendingFunctions: [EmergencyFireControllerFunction]) -> [EmergencyFireControllerSyncTask] {
        let handles = makeCleanupMessageHandles(
            node: node,
            publishGroup: publishGroup,
            includeLightness: true,
            includeLightLC: true,
            includeScene: true
        )
        guard !handles.isEmpty else {
            return []
        }
        return [EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .associationCleanup, address: node.primaryUnicastAddress, messageHandles: handles, pendingFunctions: pendingFunctions, pendingGroupAddress: group.address.address, clearsUnassociatePending: !pendingFunctions.isEmpty)]
    }

    func pendingCleanupFunctions(for groupAddress: Address) -> [EmergencyFireControllerFunction] {
        EmergencyFireControllerFunction.allCases.filter { function in
            data.settings(for: function).pendingUnassociateGroupAddresses.contains(groupAddress)
        }
    }

    private func pendingCleanupGroups() -> [(address: Address, functions: [EmergencyFireControllerFunction])] {
        var groups: [Address: [EmergencyFireControllerFunction]] = [:]
        EmergencyFireControllerFunction.allCases.forEach { function in
            data.settings(for: function).pendingUnassociateGroupAddresses.forEach { address in
                groups[address, default: []].append(function)
            }
        }
        return groups.map { (address: $0.key, functions: $0.value) }.sorted { $0.address < $1.address }
    }

    private func makeLightnessSubscriptionTask(node: Node, group: Group, publishGroup: Group) -> EmergencyFireControllerSyncTask? {
        guard let model = node.lightnessModel,
              !model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionAdd(group: publishGroup, to: model) else {
            return nil
        }
        return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .lightnessSubscription, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)])
    }

    private func makeLightLCSubscriptionTask(node: Node, group: Group, publishGroup: Group) -> EmergencyFireControllerSyncTask? {
        guard let model = node.lightLCModel,
              !model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionAdd(group: publishGroup, to: model) else {
            return nil
        }
        return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .lightLCSubscription, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)])
    }

    private func makeHistoricalSubscriptionCleanupTask(node: Node, group: Group, publishGroup: Group) -> EmergencyFireControllerSyncTask? {
        let handles = makeCleanupMessageHandles(
            node: node,
            publishGroup: publishGroup,
            includeLightness: false,
            includeLightLC: false,
            includeScene: true
        )
        guard !handles.isEmpty else { return nil }
        return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .associationCleanup, address: node.primaryUnicastAddress, messageHandles: handles)
    }

    private func makeNonAutoRestoreCleanupTask(node: Node, group: Group, publishGroup: Group) -> EmergencyFireControllerSyncTask? {
        let handles = makeCleanupMessageHandles(
            node: node,
            publishGroup: publishGroup,
            includeLightness: false,
            includeLightLC: true,
            includeScene: true
        )
        guard !handles.isEmpty else { return nil }
        return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .associationCleanup, address: node.primaryUnicastAddress, messageHandles: handles)
    }

    private func makeLocalCleanupPendingTask(groupAddress: Address, pendingFunctions: [EmergencyFireControllerFunction]) -> EmergencyFireControllerSyncTask {
        // 找不到组或组内没有可下发节点时，也需要一个 local-only task 来清 pending 标记。
        // 这种任务没有 messageHandles，删除/清理流程不能要求 Mesh 在线。
        EmergencyFireControllerSyncTask(title: "Group Cleanup", kind: .associationCleanup, address: groupAddress, messageHandles: [], pendingFunctions: pendingFunctions, pendingGroupAddress: groupAddress, clearsUnassociatePending: true)
    }

    private func makeDeleteCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
        makeCleanupMessageHandles(
            node: node,
            publishGroup: publishGroup,
            includeLightness: true,
            includeLightLC: true,
            includeScene: true
        )
    }

    private func makeCleanupMessageHandles(
        node: Node,
        publishGroup: Group,
        includeLightness: Bool,
        includeLightLC: Bool,
        includeScene: Bool
    ) -> [MeshMessageHandle] {
        var handles: [MeshMessageHandle] = []
        if includeLightness,
           let model = node.lightnessModel,
           model.isSubscribed(to: publishGroup),
           let message = ConfigModelSubscriptionDelete(group: publishGroup, from: model) {
            let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }
        if includeScene,
           let model = node.sceneModel,
           model.isSubscribed(to: publishGroup),
           let elementAddress = model.parentElement?.unicastAddress,
           model.companyIdentifier == nil,
           let message = ConfigModelSubscriptionDelete(parameters: Data() + elementAddress + publishGroup.address.address + UInt16(model.modelIdentifier)) {
            let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }
        if includeLightLC,
           let model = node.lightLCModel,
           model.isSubscribed(to: publishGroup),
           let message = ConfigModelSubscriptionDelete(group: publishGroup, from: model) {
            let handle = MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
            handle.continuous = false
            handles.append(handle)
        }
        return handles
    }

    private func makeDisableControllerItems() -> [EmergencyFireControllerSyncItem] {
        guard let node = data.bindNode,
              node.isKeybindComplete,
              node.state,
              let vendorModel = node.sunricherVendorModel else {
            return []
        }
        let task = EmergencyFireControllerSyncTask(
            title: "Enable",
            kind: .enabled,
            address: node.primaryUnicastAddress,
            messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyEnabled(false)), model: vendorModel)]
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
