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
                tasks.append(contentsOf: addNodes.flatMap {
                    planner.makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, triggerScene: triggerScene, brightness: settings.triggerBrightness)
                })
            }

            if groupIsActiveDesired || !pendingModes.isEmpty {
                tasks.append(contentsOf: exitNodes.flatMap {
                    planner.makeLightLCCleanupTasks(node: $0, group: group, publishGroup: publishGroup, pendingModes: pendingModes)
                })
            }
            guard !tasks.isEmpty else { return [] }
            return [EmergencyFireControllerSyncItem(name: controller.name, iconName: EmergencyFireControllerIconName.main, address: groupAddress, tasks: tasks, controller: controller)]
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
        items.append(contentsOf: try makeActiveModeCleanupItems())
        return items
    }

    func makeDeleteCleanupItems() -> [EmergencyFireControllerSyncItem] {
        guard let publishGroup = data.publishGroup else {
            return []
        }

        let addresses = Set(
            data.configuration.powerLossSettings.associateGroupAddresses +
            data.configuration.powerLossSettings.pendingUnassociateGroupAddresses +
            data.configuration.fireAlarmSettings.associateGroupAddresses +
            data.configuration.fireAlarmSettings.pendingUnassociateGroupAddresses
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
        let triggerScene = triggerSceneNumber(for: mode)

        return settings.associateGroupAddresses.compactMap { address in
            guard let group = MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress(address)) else {
                return nil
            }
            let tasks = group.nodes.flatMap {
                makeAssociateTasks(node: $0, group: group, publishGroup: publishGroup, triggerScene: triggerScene, brightness: settings.triggerBrightness)
            }
            return EmergencyFireControllerSyncItem(name: group.name, iconName: "device_light", address: group.address.address, tasks: tasks)
        }
    }

    func makeActiveModeCleanupItems() throws -> [EmergencyFireControllerSyncItem] {
        guard activeMode != nil, let publishGroup = data.publishGroup else {
            return []
        }

        let activeDesiredGroups = data.configuration.activeLightLCGroupAddresses
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
        if let sceneTask = makeSceneServerSubscriptionTask(node: node, group: group, publishGroup: publishGroup) {
            tasks.append(sceneTask)
        }
        if let triggerTask = makeTriggerSceneStoreTask(node: node, triggerScene: triggerScene, brightness: brightness) {
            tasks.append(triggerTask)
        }
        if let lightLCTask = makeLightLCSubscriptionTask(node: node, group: group, publishGroup: publishGroup) {
            tasks.append(lightLCTask)
        }
        return tasks
    }

    func makeLightLCCleanupTasks(node: Node, group: Group, publishGroup: Group, pendingModes: [EmergencyFireControllerWorkMode]) -> [EmergencyFireControllerSyncTask] {
        guard let model = node.lightLCModel,
              model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionDelete(group: publishGroup, from: model) else {
            return []
        }
        return [EmergencyFireControllerSyncTask(title: node.name ?? group.name, kind: .lightLCCleanup, address: node.primaryUnicastAddress, messageHandles: [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)], pendingModes: pendingModes, pendingGroupAddress: group.address.address, clearsUnassociatePending: !pendingModes.isEmpty)]
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
        EmergencyFireControllerSyncTask(title: "LC Cleanup", kind: .lightLCCleanup, address: groupAddress, messageHandles: [], pendingModes: pendingModes, pendingGroupAddress: groupAddress, clearsUnassociatePending: true)
    }

    private func makeDeleteCleanupMessageHandles(node: Node, publishGroup: Group) -> [MeshMessageHandle] {
        guard let model = node.lightLCModel,
              model.isSubscribed(to: publishGroup),
              let message = ConfigModelSubscriptionDelete(group: publishGroup, from: model) else {
            return []
        }
        return [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)]
    }
}
