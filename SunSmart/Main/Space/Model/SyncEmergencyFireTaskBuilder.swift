import Foundation
import NordicSigMeshSDK

final class SyncEmergencyFireTaskBuilder {
    typealias EmergencyFireSyncContext = SyncDevicesViewController.EmergencyFireSyncContext
    private(set) var failureMessages: [String] = []

    func appendEmergencyFireControllerGroupMutationItems(to section: SyncDevicesSectionModel, group: Group, addNodes: [Node], exitNodes: [Node]) {
        guard let space = SpaceData.load(subNetworkId: group.subNetworkId ?? MeshNetworkManager.instance.currentNetworkKey.networkId.hex) else {
            return
        }

        let items = EmergencyFireControllerSyncPlanner.makeGroupMutationItems(
            group: group,
            addNodes: addNodes,
            exitNodes: exitNodes,
            space: space
        )

        items.forEach { item in
            guard let controller = item.controller else { return }
            let deviceModels = item.tasks.compactMap { task -> SyncDevicesModel? in
                guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: task.address) else {
                    return nil
                }
                let model = SyncDevicesModel(name: task.title, address: task.address)
                model.imageName = item.iconName
                model.operationType = .configuration(node: node, type: .emergencyFireController(task: task, data: controller))
                return model
            }
            guard !deviceModels.isEmpty else { return }
            let groupModel = SyncDevicesGroupModel(groupName: item.name, groupAddress: item.address, deviceModels: deviceModels)
            deviceModels.forEach { $0.parentGroupModel = groupModel }
            section.groups.append(groupModel)
        }
    }

    func makeEmergencyFireControllerItems(
        data: DeviceEmerFireData,
        context: EmergencyFireSyncContext
    ) -> [EmergencyFireControllerSyncItem] {
        let planner = EmergencyFireControllerSyncPlanner(
            data: data,
            meshUUID: data.meshUUID,
            subnetworkId: data.meshNetworkId,
            changedFromConfiguration: context.changedFromConfiguration
        )
        if context.isDeleteCleanup {
            return planner.makeDeleteCleanupItems()
        }
        do {
            return try planner.makeItems()
        } catch {
            failureMessages.append(error.localizedDescription)
            return []
        }
    }

    func appendEmergencyFireControllerItems(
        to section: SyncDevicesSectionModel,
        data: DeviceEmerFireData,
        items: [EmergencyFireControllerSyncItem]
    ) {
        items.forEach { item in
            let isControllerItem = item.iconName == EmergencyFireControllerIconName.main && item.name == data.name
            if isControllerItem {
                if let deviceModel = makeEmergencyFireControllerDeviceModel(item: item, data: data) {
                    section.devices.append(deviceModel)
                }
                return
            }

            let deviceModels = groupedEmergencyFireControllerTasksByNode(item.tasks).compactMap { group in
                makeEmergencyFireControllerLeafDeviceModel(item: item, tasks: group.tasks, data: data)
            }
            guard !deviceModels.isEmpty else { return }
            let groupModel = SyncDevicesGroupModel(groupName: item.name, groupAddress: item.address, deviceModels: deviceModels)
            deviceModels.forEach { $0.parentGroupModel = groupModel }
            section.groups.append(groupModel)
        }
    }

    private func makeEmergencyFireControllerDeviceModel(
        item: EmergencyFireControllerSyncItem,
        data: DeviceEmerFireData
    ) -> SyncDevicesModel? {
        let address = data.bindNodeAddress ?? item.tasks.first?.address ?? item.address
        guard MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) != nil else {
            return nil
        }

        let model = SyncDevicesModel(name: item.name, address: address)
        model.imageName = item.iconName
        let taskModels = item.tasks.compactMap { task in
            makeEmergencyFireControllerTaskModel(task: task, data: data)
        }
        guard !taskModels.isEmpty else {
            return nil
        }
        let step = SyncDeviceStepModel(type: "others".localizedString, state: .none, tasks: taskModels)
        taskModels.forEach { $0.parentStepModel = step }
        step.parentDeviceModel = model
        model.steps = [step]
        return model
    }

    private func makeEmergencyFireControllerLeafDeviceModel(
        item: EmergencyFireControllerSyncItem,
        tasks: [EmergencyFireControllerSyncTask],
        data: DeviceEmerFireData
    ) -> SyncDevicesModel? {
        guard let firstTask = tasks.first else {
            return nil
        }
        if isEmergencyFireControllerLocalGroupCleanupTask(firstTask) {
            return makeEmergencyFireControllerLocalGroupCleanupDeviceModel(item: item, tasks: tasks, data: data)
        }

        guard let node = nodeForEmergencyFireControllerTask(firstTask, data: data) else {
            return nil
        }
        let model = SyncDevicesModel(name: node.name ?? item.name, address: node.primaryUnicastAddress)
        model.imageName = item.iconName
        model.steps = tasks.compactMap { task in
            makeEmergencyFireControllerLeafStep(task: task, data: data)
        }
        model.steps.forEach { step in
            step.parentDeviceModel = model
        }
        guard !model.steps.isEmpty else { return nil }
        return model
    }

    private func makeEmergencyFireControllerLocalGroupCleanupDeviceModel(
        item: EmergencyFireControllerSyncItem,
        tasks: [EmergencyFireControllerSyncTask],
        data: DeviceEmerFireData
    ) -> SyncDevicesModel? {
        guard let operationNode = data.bindNode else {
            return nil
        }
        let model = SyncDevicesModel(name: item.name, address: item.address)
        model.imageName = item.iconName
        model.steps = tasks.compactMap { task in
            makeEmergencyFireControllerLeafStep(task: task, data: data, operationNode: operationNode)
        }
        model.steps.forEach { step in
            step.parentDeviceModel = model
        }
        guard !model.steps.isEmpty else { return nil }
        return model
    }

    private func groupedEmergencyFireControllerTasksByNode(_ tasks: [EmergencyFireControllerSyncTask]) -> [(address: Address, tasks: [EmergencyFireControllerSyncTask])] {
        var groupedTasks: [(address: Address, tasks: [EmergencyFireControllerSyncTask])] = []
        tasks.forEach { task in
            if let index = groupedTasks.firstIndex(where: { $0.address == task.address }) {
                groupedTasks[index].tasks.append(task)
            } else {
                groupedTasks.append((address: task.address, tasks: [task]))
            }
        }
        return groupedTasks
    }

    private func makeEmergencyFireControllerLeafStep(
        task: EmergencyFireControllerSyncTask,
        data: DeviceEmerFireData,
        operationNode: Node? = nil
    ) -> SyncDeviceStepModel? {
        guard let taskModel = makeEmergencyFireControllerTaskModel(task: task, data: data, operationNode: operationNode) else {
            return nil
        }
        let step = SyncDeviceStepModel(type: emergencyFireControllerTaskDisplayName(task, data: data), state: .none, tasks: [taskModel])
        taskModel.parentStepModel = step
        return step
    }

    private func makeEmergencyFireControllerTaskModel(
        task: EmergencyFireControllerSyncTask,
        data: DeviceEmerFireData,
        operationNode: Node? = nil
    ) -> SyncDeviceStepTaskModel? {
        guard let node = operationNode ?? nodeForEmergencyFireControllerTask(task, data: data) else {
            return nil
        }
        return SyncDeviceStepTaskModel(
            name: emergencyFireControllerTaskDisplayName(task, data: data),
            operationType: .configuration(node: node, type: .emergencyFireController(task: task, data: data))
        )
    }

    private func emergencyFireControllerTaskDisplayName(
        _ task: EmergencyFireControllerSyncTask,
        data: DeviceEmerFireData
    ) -> String {
        switch task.kind {
        case .resend:
            if task.title == EmergencyFireControllerState.restore.syncActionTitle ||
                task.title == "efc_sync_restore_resend".localizedString {
                return String(format: "efc_sync_send_count_format".localizedString, data.configuration.restoreSettings.sendCount)
            }
            return task.title
        case .restoreDelay:
            return String(format: "efc_sync_resuming_in_seconds_format".localizedString, data.configuration.restoreSettings.resumingSeconds)
        default:
            return task.kind.localizedTitle
        }
    }

    private func nodeForEmergencyFireControllerTask(_ task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData) -> Node? {
        MeshNetworkManager.instance.meshNetwork?.node(withAddress: task.address)
    }

    func isEmergencyFireControllerLocalGroupCleanupTask(_ task: EmergencyFireControllerSyncTask) -> Bool {
        let isAssociationCleanup = task.kind == .associationCleanup &&
            task.messageHandles.isEmpty &&
            task.clearsUnassociatePending &&
            task.pendingGroupAddress != nil
        let isDeleteCleanup = task.kind == .deleteCleanup &&
            task.messageHandles.isEmpty &&
            task.pendingGroupAddress != nil
        return (isAssociationCleanup || isDeleteCleanup) &&
            task.pendingGroupAddress == task.address
    }

}
