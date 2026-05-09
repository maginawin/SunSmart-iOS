//
//  EmergencyFireControllerSyncPlanner.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

struct EmergencyFireControllerSyncPlanner {
    let data: DeviceEmerFireData
    let meshUUID: String
    let subnetworkId: String

    static func controllersAffecting(group: Group, in space: SpaceData) -> [DeviceEmerFireData] {
        DeviceEmerFireStore.shared.devices(in: space).filter { controller in
            guard controller.bindNode != nil else { return false }
            let settings = [
                controller.configuration.powerLossSettings,
                controller.configuration.fireAlarmSettings
            ]
            return settings.contains { setting in
                setting.associateGroupAddresses.contains(group.address.address) ||
                setting.pendingUnassociateGroupAddresses.contains(group.address.address)
            }
        }
    }

    static func makeGroupMutationItems(group: Group, addNodes: [Node], exitNodes: [Node], space: SpaceData) -> [EmergencyFireControllerSyncItem] {
        controllersAffecting(group: group, in: space).flatMap { controller -> [EmergencyFireControllerSyncItem] in
            guard let publishGroupAddress = try? controller.ensurePublishGroup(meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId),
                  let publishGroup = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(publishGroupAddress)),
                  controller.configuration.workMode != .allDisabled,
                  let settings = controller.activeModeSettings,
                  settings.associateGroupAddresses.contains(group.address.address) else {
                return []
            }

            let mode = controller.configuration.workMode
            let planner = EmergencyFireControllerSyncPlanner(data: controller, meshUUID: space.meshUUID, subnetworkId: space.meshNetworkId)
            let scenes = planner.sceneNumbers(for: mode)
            let addTasks = addNodes.flatMap {
                planner.makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, triggerScene: scenes.trigger, stopScene: scenes.stop, brightness: settings.triggerBrightness, mode: mode, forceStopRewrite: false)
            }
            let exitTasks = exitNodes.flatMap {
                planner.makeCleanupTasks(node: $0, group: group, publishGroup: publishGroup, mode: mode)
            }
            let tasks = addTasks + exitTasks
            guard !tasks.isEmpty else { return [] }
            return [EmergencyFireControllerSyncItem(name: controller.name, iconName: EmergencyFireControllerIconName.main, address: group.address.address, tasks: tasks, controller: controller)]
        }
    }

    func makeItems() throws -> [EmergencyFireControllerSyncItem] {
        _ = try data.ensurePublishGroup(meshUUID: meshUUID, subnetworkId: subnetworkId)
        var items: [EmergencyFireControllerSyncItem] = []

        let controllerTasks = try data.makeControllerSyncTasks(meshUUID: meshUUID, subnetworkId: subnetworkId)
        if let node = data.bindNode {
            items.append(EmergencyFireControllerSyncItem(name: data.name, iconName: EmergencyFireControllerIconName.main, address: node.primaryUnicastAddress, tasks: controllerTasks, controller: data))
        }

        items.append(contentsOf: try makeActiveModeAssociateItems())
        items.append(contentsOf: try makeAllModeCleanupItems())
        return items
    }

    func makeDeleteCleanupItems() -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            return []
        }

        let addresses = Set(
            data.configuration.powerLossSettings.associateGroupAddresses +
            data.configuration.powerLossSettings.pendingUnassociateGroupAddresses +
            data.configuration.powerLossSettings.pendingStopSceneRewriteGroupAddresses +
            data.configuration.fireAlarmSettings.associateGroupAddresses +
            data.configuration.fireAlarmSettings.pendingUnassociateGroupAddresses +
            data.configuration.fireAlarmSettings.pendingStopSceneRewriteGroupAddresses
        )

        return addresses.sorted().compactMap { address in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                return nil
            }

            let tasks = group.nodes.compactMap { node -> EmergencyFireControllerSyncTask? in
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
        }
    }

    func makeActiveModeAssociateItems() throws -> [EmergencyFireControllerSyncItem] {
        guard let mode = activeMode, let settings = data.activeModeSettings, let publishGroup = data.publishGroup else {
            return []
        }
        let sceneNumbers = sceneNumbers(for: mode)

        return settings.associateGroupAddresses.compactMap { address in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                return nil
            }
            let forceStopRewrite = settings.pendingStopSceneRewriteGroupAddresses.contains(address)
            var tasks = group.nodes.flatMap {
                makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, triggerScene: sceneNumbers.trigger, stopScene: sceneNumbers.stop, brightness: settings.triggerBrightness, mode: mode, forceStopRewrite: forceStopRewrite)
            }
            if forceStopRewrite, tasks.isEmpty {
                tasks.append(makeLocalProfileRewritePendingTask(groupAddress: group.address.address, mode: mode))
            }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
        }
    }

    func makeAllModeCleanupItems() throws -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            return []
        }

        return [EmergencyFireControllerWorkMode.powerLossEmergency, .fireAlarmEmergency].flatMap { mode -> [EmergencyFireControllerSyncItem] in
            let settings = data.settings(for: mode)
            return (settings?.pendingUnassociateGroupAddresses ?? []).map { address in
                guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                    let task = makeLocalCleanupPendingTask(groupAddress: address, mode: mode)
                    return EmergencyFireControllerSyncItem(name: String(format: "%04X", address), iconName: "device_light", address: address, tasks: [task])
                }

                var tasks = group.nodes.flatMap {
                    makeCleanupTasks(node: $0, group: group, publishGroup: publishGroup, mode: mode)
                }
                if tasks.isEmpty {
                    tasks.append(makeLocalCleanupPendingTask(groupAddress: group.address.address, mode: mode))
                }
                return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
            }
        }
    }

    func makeAssociateTasks(node: Node, group: Group, publishGroup: Group, triggerScene: SceneNumber, stopScene: SceneNumber, brightness: Int, mode: EmergencyFireControllerWorkMode, forceStopRewrite: Bool) -> [EmergencyFireControllerSyncTask] {
        var tasks: [EmergencyFireControllerSyncTask] = []
        node.getSubscribeToGroupMessages(publishGroup).forEach { message in
            tasks.append(EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .groupSubscription, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)]))
        }
        tasks.append(contentsOf: makeSceneSubscriptionTasks(node: node, group: group, publishGroup: publishGroup))
        tasks.append(contentsOf: makeSceneStoreTasks(node: node, group: group, triggerScene: triggerScene, stopScene: stopScene, brightness: brightness, mode: mode, forceStopRewrite: forceStopRewrite))
        return tasks
    }

    func makeCleanupTasks(node: Node, group: Group, publishGroup: Group, mode: EmergencyFireControllerWorkMode) -> [EmergencyFireControllerSyncTask] {
        let handles = node.getUnsubscribeGroupMessages(publishGroup).map {
            MeshMessageHandle(message: $0, address: node.primaryUnicastAddress)
        }
        guard !handles.isEmpty else { return [] }
        return [EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .cleanupSubscription, address: node.primaryUnicastAddress, messageHandles: handles, pendingMode: mode, pendingGroupAddress: group.address.address, clearsUnassociatePending: true)]
    }

    private var activeMode: EmergencyFireControllerWorkMode? {
        switch data.configuration.workMode {
        case .powerLossEmergency, .fireAlarmEmergency:
            return data.configuration.workMode
        case .allDisabled:
            return nil
        }
    }

    func sceneNumbers(for mode: EmergencyFireControllerWorkMode) -> (trigger: SceneNumber, stop: SceneNumber) {
        switch mode {
        case .powerLossEmergency:
            return (DeviceEmerFireData.powerLossTriggerSceneNumber, DeviceEmerFireData.powerLossStopSceneNumber)
        case .fireAlarmEmergency:
            return (DeviceEmerFireData.fireAlarmTriggerSceneNumber, DeviceEmerFireData.fireAlarmStopSceneNumber)
        case .allDisabled:
            return (DeviceEmerFireData.powerLossTriggerSceneNumber, DeviceEmerFireData.powerLossStopSceneNumber)
        }
    }

    private func makeSceneSubscriptionTasks(node: Node, group: Group, publishGroup: Group) -> [EmergencyFireControllerSyncTask] {
        let sceneModels: [Model?] = [node.sceneModel, node.lightLCSceneModel]
        return sceneModels.compactMap { model in
            guard let model,
                  !model.isSubscribed(to: publishGroup),
                  let elementAddress = model.parentElement?.unicastAddress,
                  model.companyIdentifier == nil,
                  let message = ConfigModelSubscriptionAdd(parameters: Data() + elementAddress + publishGroup.address.address + UInt16(model.modelIdentifier)) else {
                return nil
            }
            return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .groupSubscription, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)])
        }
    }

    private func makeSceneStoreTasks(node: Node, group: Group, triggerScene: SceneNumber, stopScene: SceneNumber, brightness: Int, mode: EmergencyFireControllerWorkMode, forceStopRewrite: Bool) -> [EmergencyFireControllerSyncTask] {
        var tasks: [EmergencyFireControllerSyncTask] = []
        let lightness = Node.getLightness(lightness100: brightness)

        if let lightnessModel = node.lightnessModel, let sceneSetupModel = node.sceneSetupModel {
            tasks.append(EmergencyFireControllerSyncTask(
                title: "Trigger Scene",
                kind: .triggerScene,
                address: node.primaryUnicastAddress,
                messageHandles: [
                    MeshMessageHandle(message: LightLightnessSet(lightness: lightness, transitionTime: .immediate, delay: 0), model: lightnessModel),
                    MeshMessageHandle(message: SceneStore(triggerScene), model: sceneSetupModel)
                ]
            ))
        }

        let stopTask = makeStopSceneStoreTask(node: node, group: group, stopScene: stopScene)
        if forceStopRewrite {
            tasks.append(EmergencyFireControllerSyncTask(title: stopTask.title, kind: .profileRewrite, address: stopTask.address, messageHandles: stopTask.messageHandles, isUnsupported: stopTask.isUnsupported, pendingMode: mode, pendingGroupAddress: group.address.address, clearsStopRewritePending: true))
        } else {
            tasks.append(stopTask)
        }

        return tasks
    }

    private func makeStopSceneStoreTask(node: Node, group: Group, stopScene: SceneNumber) -> EmergencyFireControllerSyncTask {
        guard let lightLCModel = node.lightLCModel,
              let lightLCSceneSetupModel = node.lightLCSceneSetupModel else {
            return EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .stopScene, address: node.primaryUnicastAddress, messageHandles: [], isUnsupported: true)
        }

        let profile = group.info.profile
        var messageHandles = node.getNodeLightDataSyncProfiles(group: group, groupLightData: profile.lightControlData, lightLCProperty: LightLCProperty()).flatMap {
            $0.getMessageHandles(node: node)
        }
        messageHandles.append(MeshMessageHandle(message: LightLCLightOnOffSet(true), model: lightLCModel))
        messageHandles.append(MeshMessageHandle(message: SceneStore(stopScene), model: lightLCSceneSetupModel))

        return EmergencyFireControllerSyncTask(title: "Stop Scene", kind: .stopScene, address: node.primaryUnicastAddress, messageHandles: messageHandles)
    }

    private func makeLocalCleanupPendingTask(groupAddress: Address, mode: EmergencyFireControllerWorkMode) -> EmergencyFireControllerSyncTask {
        EmergencyFireControllerSyncTask(title: "Cleanup", kind: .cleanupSubscription, address: groupAddress, messageHandles: [], pendingMode: mode, pendingGroupAddress: groupAddress, clearsUnassociatePending: true)
    }

    private func makeLocalProfileRewritePendingTask(groupAddress: Address, mode: EmergencyFireControllerWorkMode) -> EmergencyFireControllerSyncTask {
        EmergencyFireControllerSyncTask(title: "Profile Rewrite", kind: .profileRewrite, address: groupAddress, messageHandles: [], pendingMode: mode, pendingGroupAddress: groupAddress, clearsStopRewritePending: true)
    }

    private func makeDeleteCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
        node.getUnsubscribeGroupMessages(publishGroup).map {
            MeshMessageHandle(message: $0, address: node.primaryUnicastAddress)
        }
    }
}
