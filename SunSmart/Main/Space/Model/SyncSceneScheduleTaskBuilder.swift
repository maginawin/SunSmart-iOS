import Foundation
import NordicSigMeshSDK

struct SyncSceneScheduleTaskBuilder {
    func appendScene(to configurationSection: SyncDevicesSectionModel, removal removeSection: SyncDevicesSectionModel, scene: Scene) {

        // 场景内需要同步的组
        scene.info.groups.forEach { group in

            if let groupSceneData = group.info.sceneExecuteDatas.first(where: { scene.number == $0.sceneNumber }) {
                let resut = group.getNeedSyncDataNodes(scene: scene)
                // 需要同步的设备
                let syncNodes = resut.syncNodes
                let syncSceneDeviceModels = syncNodes.map({ node in
                    let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    model.imageName = node.iconName
                    // 场景绑定日程
                    if scene.info.bindSchedules.count > 0 {

                        let addSceneTask = SyncDeviceStepTaskModel(name: scene.name, operationType: .configuration(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData)))
                        let addSceneStep = SyncDeviceStepModel(type: "scene".localizedString, state: .none, tasks: [addSceneTask])
                        addSceneStep.parentDeviceModel = model
                        addSceneStep.showProgress = false
                        addSceneTask.parentStepModel = addSceneStep

                        let addScheduleTasks = scene.info.bindSchedules.map({ schedule in
                             SyncDeviceStepTaskModel(name: schedule.name, operationType: .configuration(node: node, type: .schedule(schedule: schedule)))
                        })
                        let addScheduleStep = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: addScheduleTasks)
                        addScheduleStep.parentDeviceModel = model
                        addScheduleStep.showProgress = false
                        addScheduleStep.relevanceStepModels = [addSceneStep]
                        addScheduleTasks.forEach({ $0.parentStepModel = addScheduleStep })
                        model.steps = [addSceneStep, addScheduleStep]
                    }else {
                        model.operationType = .configuration(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData))
                    }
                    return model
                })
                if syncSceneDeviceModels.count > 0 {
                    let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: syncSceneDeviceModels)
                    configurationSection.groups.append(groupModel)

                    syncSceneDeviceModels.forEach({
                        $0.parentGroupModel = groupModel
                    })
                }

                // 需要删除的设备
                let deleteNodes = resut.deleteNodes
                let deleteSceneDeviceModels = deleteNodes.map({ node in
                    let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    model.imageName = node.iconName
                    if scene.info.bindSchedules.count > 0 {

                        let deleteScheduleTasks = scene.info.bindSchedules.map({ schedule in
                             SyncDeviceStepTaskModel(name: schedule.name, operationType: .delete(node: node, type: .schedule(schedule: schedule)))
                        })
                        let deleteScheduleStep = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: deleteScheduleTasks)
                        deleteScheduleStep.parentDeviceModel = model
                        deleteScheduleStep.showProgress = false
                        deleteScheduleTasks.forEach({ $0.parentStepModel = deleteScheduleStep })

                        let deleteSceneTask = SyncDeviceStepTaskModel(name: scene.name, operationType: .delete(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData)))
                        let deleteSceneStep = SyncDeviceStepModel(type: "scene".localizedString, state: .none, tasks: [deleteSceneTask])
                        deleteSceneStep.parentDeviceModel = model
                        deleteSceneStep.showProgress = false
                        deleteSceneStep.relevanceStepModels = [deleteScheduleStep]
                        deleteSceneTask.parentStepModel = deleteSceneStep

                        model.steps = [deleteScheduleStep, deleteSceneStep]

                    }else {
                        model.operationType = .delete(node: node, type: .scene(sceneId: scene.number, executeData: nil))
                    }
                    return model
                })
                if deleteSceneDeviceModels.count > 0 {
                    let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deleteSceneDeviceModels)
                    removeSection.groups.append(groupModel)

                    deleteSceneDeviceModels.forEach({
                        $0.parentGroupModel = groupModel
                    })
                }
            }
        }

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
