import Foundation
import NordicSigMeshSDK

/// 将现有 Node 同步需求转换为兼容任务模型，不发送消息或修改页面状态。
struct SyncDeviceTaskBuilder {
    private let spaceName: (String) -> String?

    init(spaceName: @escaping (String) -> String? = { SpaceData.load(subNetworkId: $0)?.name }) {
        self.spaceName = spaceName
    }

    func makeDeviceModels(
        group: Group?,
        node: Node,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil,
        protectsProfileSensors: Bool = false
    ) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {

        /// 删除操作
        var deleteSteps: [SyncDeviceStepModel] = []
        var nonBlockingGroupExitSteps: [SyncDeviceStepModel] = []
        // 同步操作
        var configturationSteps: [SyncDeviceStepModel] = []

        // 添加组流程
        var addGroupStep: SyncDeviceStepModel?
        /// 删除组流程
        var removeGroupStep: SyncDeviceStepModel?
        /// 初始化设备流程
        var initializeStepModel: SyncDeviceStepModel?

        var syncDataTypes: [NodeSyncData] = []
        if group != nil {
            syncDataTypes = node.getSyncData(
                type: .group(group, effectiveMemberCount: effectiveMemberCount),
                profileSyncContext: profileSyncContext
            )
            // 排序，如同步组按照优先级高到低排序同步数据
            if syncDataTypes.contains(where: { data in
                if case .subscribeGroup = data { return true }
                    return false
            }) {
                syncDataTypes.sort(by: { $0.level < $1.level })
            } else if syncDataTypes.contains(where: { data in   // 如删除组则按照优先级从低到高排序删除数据
                if case .unsubscribeGroup = data { return true }
                    return false
            }) {
                syncDataTypes.sort(by: { $0.level > $1.level })
            }
        }else {
            syncDataTypes = node.getSyncData(type: .all)
        }

        syncDataTypes.forEach { type in
            switch type {
            case .subscribeGroup(let group):
                let addGroupTask = SyncDeviceStepTaskModel(name: "add_to_group".localizedString, operationType: .configuration(node: node, type  : .group(group: group)))
                let step = SyncDeviceStepModel(type: "add_to_group".localizedString, state: .none, tasks: [addGroupTask])
                addGroupTask.parentStepModel = step
                configturationSteps.append(step)

                addGroupStep = step

            case .unsubscribeGroup(let group):
                let removeGroupTask = SyncDeviceStepTaskModel(name: "remove_from_group".localizedString, operationType: .delete(node: node, type: .group(group: group)))
                let step = SyncDeviceStepModel(type: "remove_from_group".localizedString, state: .none, tasks: [removeGroupTask])
                removeGroupTask.parentStepModel = step
                // 需要依赖之前操作完成才能退出组
//                step.relevanceStepModels = deleteSteps
                deleteSteps.append(step)
                removeGroupStep = step

            case .profile(let types):
                // 锁定配置切换操作
                var luxTriggerLockTask: SyncDeviceStepTaskModel?
                /// 白天/晚上lux阈值操作
                var luxThresholdTask: SyncDeviceStepTaskModel?
                // 切换到对应profile操作
                var switchProfileTask: SyncDeviceStepTaskModel?
                // 保存到profile 场景
                var lastProfileStoreTask: SyncDeviceStepTaskModel?
                /// 同步profile场景的操作任务list
                var syncProfileSceneTasks: [SyncDeviceStepTaskModel] = []
                let syncProfileTasks = types.map({
                    let task = SyncDeviceStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .profile(type: $0)))
                    // 设置前置条件关联
                    switch $0 {
                    case .profileToggleTriggerConditionLuxLock:
                        luxTriggerLockTask = task
                    case .profileDayToggleTriggerConditionLux, .profileNightToggleTriggerConditionLux:
                        luxThresholdTask = task
                    case .lightControlSwitch, .daylightSensorConditionRecall:
                        switchProfileTask = task
                        if luxTriggerLockTask != nil {
                            task.relevanceTaskModels.append(luxTriggerLockTask!)
                        }
                        if luxThresholdTask != nil {
                            task.relevanceTaskModels.append(luxThresholdTask!)
                        }
                        if lastProfileStoreTask != nil {
                            task.relevanceTaskModels.append(lastProfileStoreTask!)
                        }
                    case .lightControlStore:
                        task.relevanceTaskModels = syncProfileSceneTasks
                        syncProfileSceneTasks.removeAll()
                        lastProfileStoreTask = task
                    case .powerOnState, .daylightCalibration, .daylightCalibrateRate, .daylightCalibrateInflectionPoint, .sensitivity, .lightControlDelete, .profileToggleTriggerConditionLuxDelete:
                        break
                    default:
                        if luxTriggerLockTask != nil {
                            task.relevanceTaskModels.append(luxTriggerLockTask!)
                        }
                        if switchProfileTask != nil {
                            task.relevanceTaskModels.append(switchProfileTask!)
                        }
                        syncProfileSceneTasks.append(task)
                    }
                    return task
                })
                if syncProfileTasks.count > 0 {

                    let step = SyncDeviceStepModel(type: "profile".localizedString, state: .none, tasks: syncProfileTasks)
                    syncProfileTasks.forEach({ $0.parentStepModel = step })
                    if node.groupState == .exitFailure || removeGroupStep != nil {
                        deleteSteps.append(step)
                    }else {
                        configturationSteps.append(step)
                    }
                }
            case .pirEnabled(let enabled):
                if protectsProfileSensors {
                    break
                }
                let name = enabled ? "pir_enabled".localizedString : "pir_disable".localizedString
                let task = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .pirEnabled(enabled)))

                let step = SyncDeviceStepModel(type: name, state: .none, tasks: [task])
                task.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }

            case .syncScenes(let datas):

                let syncSceneTasks = datas.map({ (scene, sceneData) in
                    return SyncDeviceStepTaskModel(name: scene.name, operationType: .configuration(node: node, type: .scene(sceneId: scene.number, executeData: sceneData)))
                })
                if syncSceneTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "scene".localizedString, state: .none, tasks: syncSceneTasks)
                    syncSceneTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
                }

            case .deleteScenes(let scenes):

                let deleteSceneTasks = scenes.map({
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .scene(sceneId: $0.number, executeData: nil)))
                })
                if deleteSceneTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "remove_scene".localizedString, state: .none, tasks: deleteSceneTasks)
                    deleteSceneTasks.forEach({ $0.parentStepModel = step })
                    deleteSteps.append(step)
                }
            case .syncSchedules(let schedules):
                let timeSyncPlan = TimedScheduleTimeSyncPolicy.makePlan(
                    hasTimeModel: node.timeModel != nil,
                    scheduleEnabledStates: schedules.map(\.enabled)
                )
                let timeSynchronizationTask: SyncDeviceStepTaskModel?
                if timeSyncPlan.requiresTimeSync {
                    timeSynchronizationTask = SyncDeviceStepTaskModel(
                        name: "sync_time".localizedString,
                        operationType: .configuration(node: node, type: .timeSynchronization)
                    )
                } else {
                    timeSynchronizationTask = nil
                }
                let syncScheduleTasks = schedules.enumerated().map { index, schedule in
                    let task = SyncDeviceStepTaskModel(
                        name: schedule.name,
                        operationType: .configuration(node: node, type: .schedule(schedule: schedule))
                    )
                    if timeSyncPlan.scheduleRequiresTimeSync[index],
                       let timeSynchronizationTask {
                        task.relevanceTaskModels.append(timeSynchronizationTask)
                    }
                    return task
                }
                if syncScheduleTasks.count > 0 {
                    let independentScheduleTasks = syncScheduleTasks.filter {
                        $0.relevanceTaskModels.isEmpty
                    }
                    let dependentScheduleTasks = syncScheduleTasks.filter {
                        !$0.relevanceTaskModels.isEmpty
                    }
                    let tasks = [timeSynchronizationTask].compactMap { $0 } + independentScheduleTasks + dependentScheduleTasks
                    let step = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: tasks)
                    tasks.forEach({ $0.parentStepModel = step })
                    let isExitingGroup = node.groupState == .exitFailure
                        || removeGroupStep != nil
                    switch TimedSchedulerGroupMemberExitStepPolicy.destination(
                        isExitingGroup: isExitingGroup
                    ) {
                    case .removal:
                        deleteSteps.append(step)
                        if !TimedSchedulerGroupMemberExitStepPolicy.shouldBlockGroupExit(
                            isExitingGroup: isExitingGroup
                        ) {
                            nonBlockingGroupExitSteps.append(step)
                        }
                    case .configuration:
                        configturationSteps.append(step)
                    }
                }

            case .deleteSchedules(let schedules):
                let deleteScheduleTasks = schedules.map({
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .schedule(schedule: $0)))
                })
                if deleteScheduleTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "remove_schedule".localizedString, state: .none, tasks: deleteScheduleTasks)
                    deleteScheduleTasks.forEach({ $0.parentStepModel = step })
                    deleteSteps.append(step)
                }

            case .syncSwitchProxy(let switchData):

                let syncSwitchProxyTask = SyncDeviceStepTaskModel(name: switchData.name, operationType: .configuration(node: node, type: .enOceanProxy(switchData: switchData)))
                let step = SyncDeviceStepModel(type: "enocean_proxy".localizedString, state: .none, tasks: [syncSwitchProxyTask])
                syncSwitchProxyTask.parentStepModel = step
                configturationSteps.append(step)

            case .deleteSwitchProxy(let switchData):

                let deleteSwitchProxyTask = SyncDeviceStepTaskModel(name: switchData.name, operationType: .delete(node: node, type: .enOceanProxy(switchData: switchData)))

                let step = SyncDeviceStepModel(type: "remove_switch_proxy".localizedString, state: .none, tasks: [deleteSwitchProxyTask])
                deleteSwitchProxyTask.parentStepModel = step
                deleteSteps.append(step)

            case .syncSwitchs(let switchDatas):

                let syncSwitchTasks = switchDatas.map({
                    if let batteryPowerSwitchData = $0.batteryPowerSwitchData,
                       let targetGroup = group ?? node.group {
                        return SyncDeviceStepTaskModel(name: batteryPowerSwitchData.name, operationType: .configuration(node: node, type: .batteryPowerSwitchTargetSubscription(switchData: batteryPowerSwitchData, group: targetGroup, unsubscribe: false)))
                    }
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if syncSwitchTasks.count > 0 {
                    let stepTitle = switchDatas.allSatisfy { $0.batteryPowerSwitchData != nil }
                        ? "Group Subscription"
                        : "switch".localizedString
                    let step = SyncDeviceStepModel(type: stepTitle, state: .none, tasks: syncSwitchTasks)
                    syncSwitchTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
                }

            case .deleteSwitchs(let switchDatas):

                let deleteSwitchTasks = switchDatas.map({
                    if let batteryPowerSwitchData = $0.batteryPowerSwitchData,
                       let targetGroup = group ?? node.group {
                        return SyncDeviceStepTaskModel(name: batteryPowerSwitchData.name, operationType: .delete(node: node, type: .batteryPowerSwitchTargetSubscription(switchData: batteryPowerSwitchData, group: targetGroup, unsubscribe: true)))
                    }
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if deleteSwitchTasks.count > 0 {
                    let stepTitle = switchDatas.allSatisfy { $0.batteryPowerSwitchData != nil }
                        ? "Group Unsubscription"
                        : "remove_switch".localizedString
                    let step = SyncDeviceStepModel(type: stepTitle, state: .none, tasks: deleteSwitchTasks)
                    deleteSwitchTasks.forEach({ $0.parentStepModel = step })
                    deleteSteps.append(step)
                }

            case .deviceInitialize:
                let initializeTaskModel = SyncDeviceStepTaskModel(name: "initialize".localizedString, operationType: .configuration(node: node, type: .deviceInitialize))
                initializeStepModel = SyncDeviceStepModel(type: "initialize".localizedString, state: .none, tasks: [initializeTaskModel])
                initializeTaskModel.parentStepModel = initializeStepModel!
                configturationSteps.append(initializeStepModel!)
            case .deviceParameterTypes(let types):

                var tasks: [SyncDeviceStepTaskModel] = []
                types.forEach { type in
                    switch type {
                    case .pwmFrequency(let frequency):
                        let taskModel = SyncDeviceStepTaskModel(name: "pwm_frequency".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .pwmFrequency(frequency: frequency))))
                        tasks.append(taskModel)
                    case .ratedPower(let value):
                        let taskModel = SyncDeviceStepTaskModel(name: "rated_power".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .ratedPower(datas: value))))
                        tasks.append(taskModel)
                    case .motionSensitivityRange(range: let range):
                        let taskModel = SyncDeviceStepTaskModel(name: "relative_sensitivity".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .motionSensitivityRange(range: range))))
                        tasks.append(taskModel)
                    case .defaultTransitionTime(let transitionTime):
                        let taskModel = SyncDeviceStepTaskModel(name: "transition_time".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .defaultTransitionTime(transitionTime: transitionTime))))
                        tasks.append(taskModel)
                    case .powerCalibration(let calibrationValue):
                        let taskModel = SyncDeviceStepTaskModel(name: "power_calibrate".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .powerCalibration(calibrationValue: calibrationValue))))
                        tasks.append(taskModel)
                    case .absoluteCctRange(let range):
                        let taskModel = SyncDeviceStepTaskModel(name: "absolute_cct_range".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .absoluteCctRange(range: range))))
                        tasks.append(taskModel)
                    case .photosensorException(let state):
                        let taskModel = SyncDeviceStepTaskModel(name: "photosensor_exception".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .photosensorException(state))))
                        tasks.append(taskModel)
                    }
                }
                let deviceParametersStepModel = SyncDeviceStepModel(type: "device_parameters".localizedString, state: .none, tasks: tasks)
                tasks.forEach({
                    $0.parentStepModel = deviceParametersStepModel
                })
                configturationSteps.append(deviceParametersStepModel)
            case .proximityLightingEnabled(let enabled):

                let name = enabled ? "proximity_lighting_enabled".localizedString : "proximity_lighting_disable".localizedString
                let taskModel = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))

                let step = SyncDeviceStepModel(type: name, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step

                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
            case .proximityLightingRelayNumber(let relayNumber):
                let taskModel = SyncDeviceStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))

                let step = SyncDeviceStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }

            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):

                let taskModel = SyncDeviceStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))

                let step = SyncDeviceStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
            case .emergencyFireControllerAssociations(let data, let tasks):
                let tasksByKind = Dictionary(grouping: tasks, by: { $0.kind })
                [
                    EmergencyFireControllerSyncTaskKind.associationSubscription,
                    EmergencyFireControllerSyncTaskKind.associationCleanup
                ].forEach { kind in
                    guard let kindTasks = tasksByKind[kind], !kindTasks.isEmpty else {
                        return
                    }
                    let taskModels = kindTasks.map {
                        SyncDeviceStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .emergencyFireController(task: $0, data: data)))
                    }
                    let step = SyncDeviceStepModel(type: kind.localizedTitle, state: .none, tasks: taskModels)
                    taskModels.forEach { $0.parentStepModel = step }
                    if kind == .associationCleanup {
                        deleteSteps.append(step)
                    } else {
                        configturationSteps.append(step)
                    }
                }
            case .syncGatewayProjectId(let projectId):
                let taskModel = SyncDeviceStepTaskModel(name: "association_project".localizedString, operationType: .configuration(node: node, type: .gatewayAssociationProjectId(projectId: projectId)))

                let step = SyncDeviceStepModel(type: "association_project".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
            case .gatewayAssociatedSpaces(let networkDatas, let activate):
                var taskModels: [SyncDeviceStepTaskModel] = []
                networkDatas.forEach { (networkKey: NetworkKey, applicationKey: ApplicationKey) in
                    let name = spaceName(networkKey.networkId.hex) ?? "space".localizedString
                    let taskModel = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .gatewayAssociatedSpace(networkKey: networkKey, applicationKey: applicationKey, activate: activate)))
                    taskModels.append(taskModel)
                }

                let step = SyncDeviceStepModel(type: "associated_spaces".localizedString, state: .none, tasks: taskModels)
                taskModels.forEach({ $0.parentStepModel = step })
                configturationSteps.append(step)
            case .gatewayUnbindAssociatedSpaces(let networkDatas, let activate):
                var taskModels: [SyncDeviceStepTaskModel] = []
                networkDatas.forEach { (networkKey: NetworkKey, applicationKey: ApplicationKey) in
                    let name = spaceName(networkKey.networkId.hex) ?? "space".localizedString
                    let taskModel = SyncDeviceStepTaskModel(name: name, operationType: .delete(node: node, type: .gatewayUnbindAssociatedSpace(networkKey: networkKey, applicationKey: applicationKey, activate: activate)))
                    taskModels.append(taskModel)
                }

                let step = SyncDeviceStepModel(type: "unbind_associated_spaces".localizedString, state: .none, tasks: taskModels)
                taskModels.forEach({ $0.parentStepModel = step })
                deleteSteps.append(step)

            case .syncGatewaySubnetAppkeyIndexs(let appkeyIndexs):
                let taskModel = SyncDeviceStepTaskModel(name: "gateway_sync_spaces".localizedString, operationType: .configuration(node: node, type: .gatewaySubnetAppkeyIndexs(appkeyIndexs: appkeyIndexs)))

                let step = SyncDeviceStepModel(type: "gateway_sync_spaces".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)

            case .syncGatewaySIMAPN(let apn):
                let taskModel = SyncDeviceStepTaskModel(name: "apn".localizedString, operationType: .configuration(node: node, type: .gatewaySIMAPN(apn: apn)))

                let step = SyncDeviceStepModel(type: "apn".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
            case .syncGatewayMQTTInformation(let mqttInformation):
                let taskModel = SyncDeviceStepTaskModel(name: "server_information".localizedString, operationType: .configuration(node: node, type: .gatewayMQTTInformation(mqttInformation: mqttInformation)))

                let step = SyncDeviceStepModel(type: "server_information".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
            default:
                break
            }
        }

        // 后续同步操作需要设备添加组完成才能进行
        if let relevanceStep = addGroupStep {
            configturationSteps.forEach({ step in
                if step != relevanceStep {
                    step.relevanceStepModels = [relevanceStep]
                }
            })
        }

        // 需要依赖之前操作完成才能退出组
        if let step = removeGroupStep {
            step.relevanceStepModels = deleteSteps.filter { dependencyStep in
                dependencyStep != step
                    && !nonBlockingGroupExitSteps.contains(where: {
                        $0 === dependencyStep
                    })
            }
        }

        // 初始化设备操作，必须在完成才可以同步其它参数
        if let initStep = initializeStepModel {
            configturationSteps.forEach({ step in
                if step != initStep {
                    if addGroupStep != nil {
                        step.relevanceStepModels = [initStep, addGroupStep!]
                    }else {
                        step.relevanceStepModels = [initStep]
                    }
                }
            })
        }

        var configturationDevice: SyncDevicesModel?
        var removeDevice: SyncDevicesModel?
        if configturationSteps.count > 0 {
            configturationDevice = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            configturationDevice?.imageName = node.iconName
            configturationDevice?.steps = configturationSteps
            configturationSteps.forEach({ $0.parentDeviceModel = configturationDevice })
        }

        if deleteSteps.count > 0 {
            removeDevice = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            removeDevice?.imageName = node.iconName
            removeDevice?.steps = deleteSteps
            deleteSteps.forEach({ $0.parentDeviceModel = removeDevice })
        }

        return (configturationDevice, removeDevice)
    }

}
