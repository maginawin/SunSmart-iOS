import Foundation
import NordicSigMeshSDK

struct SyncSceneScheduleTaskBuilder {
    func appendScene(to configurationSection: SyncDevicesSectionModel, removal removeSection: SyncDevicesSectionModel, scene: Scene) {

        // Node entry points consume the same resolver for scene, device and recovery sync.
        for node in MeshNetworkManager.instance.realNodes {
            if let data = node.getNodeSyncSceneDatas(scene: scene).first?.data {
                let model = makeSceneDevice(node: node, scene: scene, data: data, removing: false)
                append(model, node: node, to: configurationSection)
            }
            if !node.getNodeNeedDeleteSceneDatas(scene: scene).isEmpty {
                let model = makeSceneDevice(node: node, scene: scene, data: nil, removing: true)
                append(model, node: node, to: removeSection)
            }
        }
    }

    private func append(_ model: SyncDevicesModel, node: Node, to section: SyncDevicesSectionModel) {
        guard let group = node.group else { section.devices.append(model); return }
        let groupModel: SyncDevicesGroupModel
        if let index = section.groups.firstIndex(where: { $0.address == group.address.address }) {
            let devices = section.groups[index].deviceModels + [model]
            groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: devices)
            section.groups[index] = groupModel
            devices.forEach { $0.parentGroupModel = groupModel }
        } else {
            groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: [model])
            section.groups.append(groupModel)
        }
        model.parentGroupModel = groupModel
    }

    private func makeSceneDevice(node: Node, scene: Scene, data: SceneExecuteData?, removing: Bool) -> SyncDevicesModel {
        let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
        model.imageName = node.iconName
        let operation: DeviceOperationType = removing
            ? .delete(node: node, type: .scene(sceneId: scene.number, executeData: nil))
            : .configuration(node: node, type: .scene(sceneId: scene.number, executeData: data))
        let schedules = scene.info.bindSchedules.filter { removing || $0.needsSync(on: node, contextGroup: node.group) }
        guard !schedules.isEmpty else { model.operationType = operation; return model }
        let task = SyncDeviceStepTaskModel(name: scene.name, operationType: operation)
        let sceneStep = SyncDeviceStepModel(type: "scene".localizedString, state: .none, tasks: [task])
        let tasks = schedules.map { schedule in
            SyncDeviceStepTaskModel(name: schedule.name, operationType: removing
                ? .delete(node: node, type: .schedule(schedule: schedule))
                : .configuration(node: node, type: .schedule(schedule: schedule)))
        }
        let scheduleStep = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: tasks)
        for step in [sceneStep, scheduleStep] {
            step.parentDeviceModel = model; step.showProgress = false
            step.tasks.forEach { $0.parentStepModel = step }
        }
        if removing { sceneStep.relevanceStepModels = [scheduleStep]; model.steps = [scheduleStep, sceneStep] }
        else { scheduleStep.relevanceStepModels = [sceneStep]; model.steps = [sceneStep, scheduleStep] }
        return model
    }

    func appendSchedule(to configurationSection: SyncDevicesSectionModel, removal removeSection: SyncDevicesSectionModel, schedule: Schedule) {
        // 需同步/删除的日程数据
        let data = schedule.getNeedSyncDatas()
        // 需删除日程的设备
        let deleteScheduleDeviceModels = data.deleteNodes.map({
            let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
            model.imageName = $0.iconName
            model.operationType = .delete(node: $0, type: .schedule(schedule: schedule))
            return model
        })
        removeSection.devices.append(contentsOf: deleteScheduleDeviceModels)
        // 需同步日程的设备
        let syncScheduleDeviceModels = data.syncNodes.map({
            let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
            model.imageName = $0.iconName
            model.operationType = .configuration(node: $0, type: .schedule(schedule: schedule))
            return model
        })
        configurationSection.devices.append(contentsOf: syncScheduleDeviceModels)

        // 需删除日程的组
        var deleteScheduleGroupModels = data.deleteGroups.map { (group: Group, nodes: [Node]) in
            let deviceModels = nodes.map({
                let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                model.imageName = $0.iconName
                model.operationType = .delete(node: $0, type: .schedule(schedule: schedule))
                return model
            })

            let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
            deviceModels.forEach({ $0.parentGroupModel = groupModel })
            return groupModel
        }
        deleteScheduleGroupModels = deleteScheduleGroupModels.sorted(by: { $0.address < $1.address })
        removeSection.groups.append(contentsOf: deleteScheduleGroupModels)
        // 需同步日程的组
        var syncScheduleGroupModels = data.syncGroups.map { (group: Group, nodes: [Node]) in
            let deviceModels = nodes.map({
                let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                model.imageName = $0.iconName
                model.operationType = .configuration(node: $0, type: .schedule(schedule: schedule))
                return model
            })
            let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
            deviceModels.forEach({ $0.parentGroupModel = groupModel })
            return groupModel
        }
        syncScheduleGroupModels = syncScheduleGroupModels.sorted(by: { $0.address < $1.address })
        configurationSection.groups.append(contentsOf: syncScheduleGroupModels)

    }

}
