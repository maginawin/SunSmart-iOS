//
//  SyncDevicesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit
import NordicSigMeshSDK

/// 同步结果数据
struct SyncResultData {
    let node: Node
    /// 成功的操作类型list
    var successOperationTypes: [DeviceOperationType]
    /// 失败的操作类型list
    var failedOperationTypes: [DeviceOperationType]
}

class SyncDevicesViewController: UIViewController {
    

    
    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    /// 返回按钮
    private lazy var backBtn: UIButton = {
        let btn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
        return btn
    }()
    
    private var sections: [SyncDevicesSectionModel] = []
    
    let type: SyncType
    /// 上一个group model
    private var lastGroupModel: SyncDevicesGroupModel?
    /// 上一个device model
    private var lastDeviceModel: SyncDevicesModel?
    /// 同步状态
    private var syncState: SyncState = .inSync
    /// 是否展示详细进度的model
    private var showProressStepModel: SyncDeviceStepModel?
    /// 同步完成回调
    var syncSuccessCallback: ((SyncType)->Void)?
    /// 点击返回回调（result: 每个设备成功、失败操作）
    var backActionCallback: ((_ result: [SyncResultData])->Void)?
    /// 更新版本的设备地址
    private var updateVersionAddresses: [Address] = []
    
    /// 自动化恢复
    var automationRestore: Bool = false
    /// 重试次数
    private var retryCount: Int = 0
    
    init(type: SyncType, reSync: Bool = false) {
        
        self.type = type
        super.init(nibName: nil, bundle: nil)
        
        syncState = reSync ? .syncFailure : .inSync
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        
        title = "sync_device(s)".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "re_sync".localizedString, color: Title_Color, font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(rightItemAction))
        
        if automationRestore {
            retryCount = 2
        }
        
        setupUI()
        
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        DispatchQueue.global().async {
            self.setupDataSource()
            DispatchQueue.main.async {
                XWHUDManager.hideInView(with: self.view)
                if self.syncState == .inSync {
                    self.startSync()
                }
                self.tableView.reloadData()
                self.updateSyncStateUI()
            }
        }
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if backActionCallback != nil {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }
    
    /// 设置数据源
    private func setupDataSource() {
      
            let removeSection = SyncDevicesSectionModel(title: "remove".localizedString)
            let configurationSection = SyncDevicesSectionModel(title: "configuration".localizedString)
            
            switch self.type {
            case .group(let group, let inNodes, let outNodes):
                
                outNodes?.forEach({ node in
                    let result = self.getSyncDeviceModel(group: group, node: node)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                })
                
                inNodes?.forEach({ node in
                    let result = self.getSyncDeviceModel(group: group, node: node)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                })
                
                group.nodes.filter({ node in !(outNodes?.contains(node) ?? false) }).forEach { node in
                    let result = self.getSyncDeviceModel(group: group, node: node)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                }
                
            case .scene(let scene):
                
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
                
            case .schedule(let schedule):
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
                
            case .enOceanSwitch(let switchData, let deleteSwitch):
                guard switchData.linkGroup != nil else {
                    break
                }
                let data = switchData.getNeedSyncDatas(deleteSwitch: deleteSwitch)
                // 删除动能开关
                if let proxyNode = data.deleteProxy {
                    let deviceModel = SyncDevicesModel(name: proxyNode.name ?? "", address: proxyNode.primaryUnicastAddress)
                    deviceModel.imageName = proxyNode.iconName
                    deviceModel.operationType = .delete(node: proxyNode, type: .enOceanProxy(switchData: switchData))
                    
                    let proxyModel = SyncDevicesSwitchProxyModel(name: "enocean_proxy".localizedString, deviceModel: deviceModel)
                    removeSection.switchProxy = proxyModel
                }
                // 同步动能开关
                if let syncNode = data.syncProxy {
                    
                    let deviceModel = SyncDevicesModel(name: syncNode.name ?? "", address: syncNode.primaryUnicastAddress)
                    deviceModel.imageName = syncNode.iconName
                    deviceModel.operationType = .configuration(node: syncNode, type: .enOceanProxy(switchData: switchData))
                    
                    let proxyModel = SyncDevicesSwitchProxyModel(name: "enocean_proxy".localizedString, deviceModel: deviceModel)
                    configurationSection.switchProxy = proxyModel
                }
                
                // 需解绑动能开关的组
                var deleteSwitchGroupModels = data.deleteGroups.map { (group, nodes) in
                    let deviceModels = nodes.map({
                        let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                        model.imageName = $0.iconName
                        model.operationType = .delete(node: $0, type: .enOceanSwitch(switchData: switchData))
                        return model
                    })
                    
                    let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
                    deviceModels.forEach({ $0.parentGroupModel = groupModel })
                    return groupModel
                }
                deleteSwitchGroupModels = deleteSwitchGroupModels.sorted(by: { $0.address < $1.address })
                removeSection.groups.append(contentsOf: deleteSwitchGroupModels)
                
                // 需订阅开关的组
                var syncSwitchGroupModels = data.syncGroups.map { (group, nodes) in
                    
                    let deviceModels = nodes.map({
                        let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                        model.imageName = $0.iconName
                        model.operationType = .configuration(node: $0, type: .enOceanSwitch(switchData: switchData))
                        return model
                    })
                    let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
                    deviceModels.forEach({ $0.parentGroupModel = groupModel })
                    return groupModel
                }
                syncSwitchGroupModels = syncSwitchGroupModels.sorted(by: { $0.address < $1.address })
                configurationSection.groups.append(contentsOf: syncSwitchGroupModels)
                
//            case .pwmPeriod(let period, let group):
//                
//                let nodes = group.nodes.filter({ $0.pwmFrequency != period })
//                let deviceModels = nodes.map({
//                    let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
//                    model.imageName = $0.iconName
//                    model.operationType = .configuration(node: $0, type: .deviceParameters(parameterType: .pwmPeriod(period: period)))
//                    return model
//                })
//                let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
//                deviceModels.forEach({ $0.parentGroupModel = groupModel })
//                configurationSection.groups.append(groupModel)
            case .devices(let nodes):

                nodes.forEach { node in
                    let result = self.getSyncDeviceModel(group: nil, node: node)
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                    if let removeDevice = result.removeDevice {
                        removeSection.devices.append(removeDevice)
                    }
                }
            case .devicesParameter(let datas):
                datas.forEach { (node: Node, parameters: [DeviceParameterType]) in
                    
                    if parameters.count > 0 {
                        var steps: [SyncDeviceStepModel] = []
                        parameters.forEach { type in
                            switch type {
                            case .pwmFrequency(let frequency):
                                let taskModel = SyncDeviceStepTaskModel(name: "pwm_frequency".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .pwmFrequency(frequency: frequency))))
                                
                                let step = SyncDeviceStepModel(type: "pwm_frequency".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .ratedPower(let value):
                                let taskModel = SyncDeviceStepTaskModel(name: "rated_power".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .ratedPower(datas: value))))
                                
                                let step = SyncDeviceStepModel(type: "rated_power".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .motionSensitivityRange(range: let range):
                                let taskModel = SyncDeviceStepTaskModel(name: "relative_sensitivity".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .motionSensitivityRange(range: range))))
                                
                                let step = SyncDeviceStepModel(type: "relative_sensitivity".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .defaultTransitionTime(let transitionTime):
                                let taskModel = SyncDeviceStepTaskModel(name: "transition_time".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .defaultTransitionTime(transitionTime: transitionTime))))
                                
                                let step = SyncDeviceStepModel(type: "transition_time".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            }
                        }
                        
                        let deviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                        deviceModel.steps = steps
                        steps.forEach({
                            $0.parentDeviceModel = deviceModel
                        })
                        configurationSection.devices.append(deviceModel)
                    }
                }
            case .dongle(let dongleData):
                if let node = dongleData.bindNode {
                    let syncDatas = node.getSyncData(type: .dongle(dongleData: dongleData))
                    guard syncDatas.count > 0 else {
                        break
                    }
                    let syncDeviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    syncDeviceModel.imageName = node.iconName
                    
                    let deleteDeviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    deleteDeviceModel.imageName = node.iconName
                    
                    // 获取日程同步数据
                    var syncCollectionSchedules: [NodeSyncData] = []
                    // 获取删除的日程数据
                    var deleteCollectionSchedules: [NodeSyncData] = []
                    
                    syncDatas.forEach { data in
                        switch data {
                        case .syncCollectionSchedules:
                            syncCollectionSchedules.append(data)
                        case .deleteCollectionSchedules:
                            deleteCollectionSchedules.append(data)
                        default:
                            break
                        }
                    }
                    if syncCollectionSchedules.count > 0 {
                        syncCollectionSchedules.forEach { syncData in
                            switch syncData {
                            case .syncCollectionSchedules(let schedules):
                                let tasks = schedules.map({ scheduleData in
                                    SyncDeviceStepTaskModel(name: "collection_schedule".localizedString + " \(scheduleData.0)", operationType: .configuration(node: node, type: .collectionSchedule(index: scheduleData.0, entry: scheduleData.1)))
                                })
                                
                                let stepModel = SyncDeviceStepModel(type: "collection_schedule".localizedString, state: .none, tasks: tasks)
                                tasks.forEach({ $0.parentStepModel = stepModel })
                                stepModel.parentDeviceModel = syncDeviceModel
                                syncDeviceModel.steps.append(stepModel)
                                
                            case .deleteCollectionSchedules(let scheduleIds):
                                
                                let tasks = scheduleIds.map({ scheduleId in
                                    SyncDeviceStepTaskModel(name: "collection_schedule".localizedString + " \(scheduleId)", operationType: .configuration(node: node, type: .collectionSchedule(index: scheduleId, entry: SchedulerRegistryEntry())))
                                })
                                let stepModel = SyncDeviceStepModel(type: "collection_schedule".localizedString, state: .none, tasks: tasks)
                                tasks.forEach({ $0.parentStepModel = stepModel })
                                stepModel.parentDeviceModel = deleteDeviceModel
                                deleteDeviceModel.steps.append(stepModel)
                            default:
                                break
                            }
                        }
                    }
                    
                    if syncDeviceModel.steps.count > 0 {
                        configurationSection.devices.append(syncDeviceModel)
                    }
                    if deleteDeviceModel.steps.count > 0 {
                        removeSection.devices.append(deleteDeviceModel)
                    }
                }
            case .proximityLightingPath(let group, _):
                
                group.nodes.forEach { node in
                    if let syncData = node.getNodeSyncProximityLighting() {
                        let syncDeviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                        syncDeviceModel.imageName = node.iconName
                        
                        switch syncData {
                        case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                            
                            let taskModel = SyncDeviceStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))
                            
                            let step = SyncDeviceStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                            taskModel.parentStepModel = step
                            
                            step.parentDeviceModel = syncDeviceModel
                            syncDeviceModel.steps.append(step)
                            
                        case .proximityLightingEnabled(let enabled):
                            let name = enabled ? "proximity_lighting_enabled".localizedString : "proximity_lighting_disable".localizedString
                            let taskModel = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
                            
                            let step = SyncDeviceStepModel(type: name, state: .none, tasks: [taskModel])
                            taskModel.parentStepModel = step
                            
                            step.parentDeviceModel = syncDeviceModel
                            syncDeviceModel.steps.append(step)
                        default:
                            break
                        }
                        configurationSection.devices.append(syncDeviceModel)
                    }
                }
            }
        
            if removeSection.groups.count > 0 || removeSection.devices.count > 0 || removeSection.switchProxy != nil {
                self.sections.append(removeSection)
            }
            if configurationSection.groups.count > 0 || configurationSection.devices.count > 0 || configurationSection.switchProxy != nil {
                self.sections.append(configurationSection)
            }
            for (index, section) in self.sections.enumerated() {
                section.groups.forEach({
                    $0.parentSectionIndex = index
                })
                section.devices.forEach({
                    $0.parentSectionIndex = index
                })
                if self.syncState == .syncFailure {
                    section.allModels.forEach({
                        $0.isFineshed = true
                        $0.state = .failed
    //                    ($0 as? SyncDevicesGroupModel)?.isShow = true
    //                    ($0 as? SyncDevicesModel)?.state = .failed
    //                    ($0 as? SyncDeviceStepTaskModel)?.state = .failed
                    })
                }
            }
    }
    
    /// 获取组对应设备同步数据model
    /// - Parameters:
    ///   - group: 组
    ///   - node: 设备
    ///   - exitGroup: 是否退组
    /// - Returns: 需要配置的model，需要删除的model
    private func getSyncDeviceModel(group: Group?, node: Node) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
        
        /// 删除操作
        var deleteSteps: [SyncDeviceStepModel] = []
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
            syncDataTypes = node.getSyncData(type: .group(group))
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
                
                let syncProfileTasks = types.map({
                    return SyncDeviceStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .profile(type: $0)))
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
                
                let syncScheduleTasks = schedules.map({
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .schedule(schedule: $0)))
                })
                if syncScheduleTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: syncScheduleTasks)
                    syncScheduleTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
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
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if syncSwitchTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "switch".localizedString, state: .none, tasks: syncSwitchTasks)
                    syncSwitchTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
                }
                
            case .deleteSwitchs(let switchDatas):
                
                let deleteSwitchTasks = switchDatas.map({
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if deleteSwitchTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "remove_switch".localizedString, state: .none, tasks: deleteSwitchTasks)
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
                
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                
                let taskModel = SyncDeviceStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))
                
                let step = SyncDeviceStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
            case .syncGatewayProjectId(let projectId):
                let taskModel = SyncDeviceStepTaskModel(name: "association_project".localizedString, operationType: .configuration(node: node, type: .gatewayAssociationProjectId(projectId: projectId)))
                
                let step = SyncDeviceStepModel(type: "association_project".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
            case .gatewayAssociatedSpaces(let networkDatas, let activate):
                var taskModels: [SyncDeviceStepTaskModel] = []
                networkDatas.forEach { (networkKey: NetworkKey, applicationKey: ApplicationKey) in
                    let space = SpaceData.load(subNetworkId: networkKey.networkId.hex)
                    let name = space?.name ?? "space".localizedString
                    let taskModel = SyncDeviceStepTaskModel(name: name, operationType: .configuration(node: node, type: .gatewayAssociatedSpace(networkKey: networkKey, applicationKey: applicationKey, activate: activate)))
                    taskModels.append(taskModel)
                }
                
                let step = SyncDeviceStepModel(type: "associated_spaces".localizedString, state: .none, tasks: taskModels)
                taskModels.forEach({ $0.parentStepModel = step })
                configturationSteps.append(step)
            case .gatewayUnbindAssociatedSpaces(let networkDatas, let activate):
                var taskModels: [SyncDeviceStepTaskModel] = []
                networkDatas.forEach { (networkKey: NetworkKey, applicationKey: ApplicationKey) in
                    let space = SpaceData.load(subNetworkId: networkKey.networkId.hex)
                    let name = space?.name ?? "space".localizedString
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
            step.relevanceStepModels = deleteSteps.filter({ $0 != step })
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
    
    /// 返回
    @objc private func backAction() {
        if backActionCallback != nil {
            
            // 设备数据list
            var resultDatas: [SyncResultData] = []
            var deviceModels: [SyncDevicesModel] = []
            self.sections.forEach { section in
                deviceModels.append(contentsOf: section.devices)
                section.groups.forEach { groupModel in
                    deviceModels.append(contentsOf: groupModel.deviceModels)
                }
            }
            
            if deviceModels.count > 0 {
                // 获取读取失败的设备参数类型
                deviceModels.forEach { deviceModel in
                    if let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.primaryUnicastAddress == deviceModel.address }) {
                        
                        var successOperationTypes: [DeviceOperationType] = []
                        var failedOperationTypes: [DeviceOperationType] = []
                        if let operationType = deviceModel.operationType {
                            if deviceModel.state == .successful {
                                successOperationTypes.append(operationType)
                            }else {
                                failedOperationTypes.append(operationType)
                            }
                        }else {
                            deviceModel.steps.forEach { step in
                                step.tasks.forEach { task in
                                    if task.state == .successful {
                                        successOperationTypes.append(task.operationType)
                                    }else {
                                        failedOperationTypes.append(task.operationType)
                                    }
                                }
                            }
                        }
                        if let index = resultDatas.firstIndex(where: { $0.node == node }) {
                            var data = resultDatas[index]
                            data.successOperationTypes.append(contentsOf: successOperationTypes)
                            data.failedOperationTypes.append(contentsOf: failedOperationTypes)
                            resultDatas[index] = data
                        }else {
                            let data = SyncResultData(node: node, successOperationTypes: successOperationTypes, failedOperationTypes: failedOperationTypes)
                            resultDatas.append(data)
                        }
                    }
                }
            }
            
            backActionCallback?(resultDatas)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func rightItemAction() {
        if syncState == .inSync { // stop
            
            MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
            sections.forEach({
                $0.allModels.forEach({
                    if $0.state == .wait  {//|| $0.state == .none
                        $0.state = .failed
                        ($0 as? SyncDevicesModel)?.failedCount += 1
                        ($0 as? SyncDeviceStepTaskModel)?.failedCount += 1
                    }
                })
            })
            tableView.reloadData()
            syncState = .syncFailure
        }else if syncState == .syncFailure {
            
//            let failedModels = sections.filter({ $0.allModels.contains(where: { $0 is SyncDevicesModel && ($0.state == .failed || $0.state == .repeatedFailure) }) })
            
            var selectModels: [SyncDevicesModel] = []
            
            sections.forEach({
                let models = $0.allModels.filter({ (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed }) as! [SyncDevicesModel]
                 selectModels.append(contentsOf: models)
            })
            if selectModels.count > 0 {
                selectModels.forEach({ device in
                    device.state = .wait
                    device.steps.forEach({
                        $0.tasks.forEach({ task in
//                            if task.state == .failed {
                                task.state = .wait
//                            }
                        })
                    })
                })
//                tableView.reloadData()
                syncState = .inSync
                startSync()
            }
//            navigationItem.rightBarButtonItem = "stop".localizedString
        }
        updateSyncStateUI()
        
//        startSync()
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
//        var failedModels: [SyncDevicesModel] = []
        sections.forEach({
            let models = $0.allModels.filter({ ($0 is SyncDevicesModel || $0 is SyncDevicesGroupModel) && $0.state == .failed })
//            failedModels.append(contentsOf: models)
            models.forEach({
                ($0 as? SyncDevicesModel)?.isSelected = sender.isSelected
                ($0 as? SyncDevicesGroupModel)?.isSelected = sender.isSelected
            })
        })
        navigationItem.rightBarButtonItem?.isEnabled = sender.isSelected
        tableView.reloadData()
    }
    
    /// 更新状态UI
    private func updateSyncStateUI() {
        if syncState == .inSync {
            navigationItem.rightBarButtonItem?.title = "stop".localizedString
            navigationItem.rightBarButtonItem?.isEnabled = true
            bottomView.isHidden = true
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomView.height, right: 0)
            backBtn.isHidden = true
        }else if syncState == .syncSuccess {
            bottomView.isHidden = true
            navigationItem.rightBarButtonItem = UIBarButtonItem()
            backBtn.isHidden = false
        }else if syncState == .syncFailure{
            navigationItem.rightBarButtonItem?.title = "re_sync".localizedString
            bottomView.isHidden = false
            backBtn.isHidden = false
            var failedModels: [SyncDevicesModel] = []
            
            var selectModels: [SyncDevicesModel] = []
            
             sections.forEach({
                 
                 let failedDevices = $0.allModels.filter({ $0 is SyncDevicesModel && $0.state == .failed  }) as! [SyncDevicesModel]
                 failedModels.append(contentsOf: failedDevices)
                 
                 let selectDevices = $0.allModels.filter({ (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed }) as! [SyncDevicesModel]
                 
                 selectModels.append(contentsOf: selectDevices)
            })
            
            selectAllBtn.isSelected = selectModels.count == failedModels.count
            if bottomView.frame == .zero {
                bottomView.layoutIfNeeded()
            }
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomView.height, right: 0)
            navigationItem.rightBarButtonItem?.isEnabled = selectModels.count > 0
        }
        
    }
    
    private func startSync() {
        
//        guard let section = sections.first, let model = section.allModels.first else { return }
        // 需要配置的设备list
        var configNodes: [Node] = []
        
        sections.forEach { section in
            section.allModels.forEach({
                if $0.state == .none {
                    $0.state = .wait
                }
                $0.isFineshed = false
                ($0 as? SyncDevicesGroupModel)?.isSelected = false
                ($0 as? SyncDevicesModel)?.isSelected = false
                //  需要配置的设备
                if let deviceModel = $0 as? SyncDevicesModel, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: deviceModel.address), node.sunricherVendorModel != nil, !configNodes.contains(node) {
                    configNodes.append(node)
                }
            })
        }
        tableView.reloadData()
        
        DispatchQueue.global().async {
            
//            let versionLockMessageHandles = configNodes.map({ MeshMessageHandle(message: SunricherVendorGet(function: .versionLock), model: $0.sunricherVendorModel!) })
            
            let semaphore = DispatchSemaphore(value: 0)
            // 给操作设备加锁
//            MeshProxyMessageCommand.shared.addMessage(messageHandles: versionLockMessageHandles) { _ in
//                semaphore.signal()
//            }
//            semaphore.wait()
            
            while let model = self.getNextHandleModel() {
                
                guard MeshLibManager.manager.isOpenBluetooth else {
                    self.sections.forEach { section in
                        section.allModels.forEach({
                            $0.state = .failed
                            $0.isFineshed = true
                        })
                    }
                    self.syncState = .syncFailure
                    
                    DispatchQueue.main.async {
                        self.updateSyncStateUI()
                        self.tableView.reloadData()
                    }
                    return
                }
//                var nodeAddress: Address?
                var messageHandles: [MeshMessageHandle] = []
                if let deviceModel = model as? SyncDevicesModel {
                    // code
                    messageHandles = deviceModel.operationType?.messageHandles ?? []
//                    deviceModel.parentGroupModel?.deviceModels.forEach({
//                        if $0.state == .none {
//                            $0.state = .wait
////                            self.updateCell(model: $0)
//                        }
//                    })
//                    nodeAddress = deviceModel.address
                    deviceModel.state = .inSettings
//                    self.tableView.reloadData()
//                    self.updateCell(model: deviceModel)
                    if let groupModel = deviceModel.parentGroupModel {
                        groupModel.isShow = true
//                        self.updateCell(model: groupModel)
                        
                        if self.lastGroupModel != groupModel {
                            
                            if self.lastGroupModel != nil {
                                self.lastGroupModel?.isShow = false
//                                self.updateCell(model: self.lastGroupModel!)
                            }
                            self.lastGroupModel = deviceModel.parentGroupModel
                        }
                    }
                    
                }else if let taskModel = model as? SyncDeviceStepTaskModel {
                    messageHandles = taskModel.operationType.messageHandles
                    taskModel.state = .inSettings
                    
                    if self.showProressStepModel == taskModel.parentStepModel {
                        DispatchQueue.main.async {
                            if let progressView = SyncDevicesProgressView.current() {
                                progressView.stepModel = taskModel.parentStepModel
                            }
                        }
                    }
                    
                    if let deviceModel = taskModel.parentStepModel?.parentDeviceModel {
                        if let groupModel = deviceModel.parentGroupModel {
                            groupModel.isShow = true
                            if self.lastGroupModel != groupModel {
                                if self.lastGroupModel != nil {
                                    self.lastGroupModel?.isShow = false
                                }
                                self.lastGroupModel = deviceModel.parentGroupModel
                            }
                        }
                        deviceModel.isShow = true
                        //                        self.updateCell(model: groupModel)
                        if self.lastDeviceModel != deviceModel {
                            
                            if self.lastDeviceModel != nil {
                                self.lastDeviceModel?.isShow = false
                                //                                self.updateCell(model: self.lastGroupModel!)
                            }
                            self.lastDeviceModel = deviceModel
                        }
//                        nodeAddress = deviceModel.address
                    }
                }
                // 节点加锁失败，不进行发送数据
//                if let node = configNodes.first(where: { $0.primaryUnicastAddress == nodeAddress }), node.versionVerifyCode == nil {
//                   messageHandles = []
//                }
                
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 10, progressBack: nil, successfulBack: { handle, statusMessage in
                    // 判断如果是设备初始化消息，则需要再初始化完成后完成基本配置
                    if statusMessage is ConfigCompositionDataStatus || statusMessage is ConfigAppKeyStatus {
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address), node.isInitialize {
                            MeshProxyMessageCommand.shared.addMessage(messageHandles: node.getConfigMessageHandles(), finishedBack: nil)
                        }
                    }else if (statusMessage is LightLightnessStatus || statusMessage is LightCTLTemperatureStatus || statusMessage is LightCTLStatus || statusMessage is LightHSLStatus), messageHandles.contains(where: { $0.message is SceneStore }) { // 设置场景时需要及时更新状态属性
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            node.updateNodeStatus(message: statusMessage, source: address)
                        }
                    }
                }, failedBack: nil) {[weak self] resultMessageHandles in

                    resultMessageHandles.forEach { handle in
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            node.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                        }
                    }
                    
//                    let resultSuccessful = !resultMessageHandles.contains(where: { !$0.isSuccessful })
                    let operationSuccessful = ((model as? SyncDevicesModel)?.operationType?.isSuccessful ?? (model as? SyncDeviceStepTaskModel)?.operationType.isSuccessful) ?? false
                    if operationSuccessful {
                        model.state = .successful
                    }else {
                        model.state = .failed
                        (model as? SyncDevicesModel)?.failedCount += 1
                        (model as? SyncDeviceStepTaskModel)?.failedCount += 1
                    }
                    self?.updateCell(model: model)
                    semaphore.signal()
                }
                semaphore.wait()
                
                DispatchQueue.main.async {
                    if let model = self.showProressStepModel {
                        if let progressView = SyncDevicesProgressView.current() {
                            progressView.stepModel = model
                        }
                    }
                }
            }
//            _ = MeshNetworkManager.instance.save()
            print("完成")
            
            self.sections.forEach { section in
                section.allModels.forEach({
    //                $0.state = .wait
                    $0.isFineshed = true
                })
            }
            self.syncState = self.sections.contains(where: { $0.allModels.contains(where: { $0.state == .failed }) }) ? .syncFailure : .syncSuccess
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.updateSyncStateUI()
                
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                
                if self.syncState == .syncSuccess {
                    // 同步完成回调
                    self.syncSuccessCallback?(self.type)
                    if let progressView = SyncDevicesProgressView.current() {
                        progressView.hide()
                    }
                }else { // 同步失败
                    if let progressView = SyncDevicesProgressView.current() {
                        progressView.reload()
                    }
                    if self.automationRestore { // 自动化恢复流程
                        if self.retryCount <= 0 { // 重试机会已用完
                            self.navigationController?.hideAutomaticHud()
                            // 退出到ble页面
                            self.navigationController?.popToViewController(vcClass: BleFirmwareUpdateViewController.classForCoder())
                        }else {
                            // 模拟点击重试
                            self.retryCount -= 1
                            self.selectAllBtnAction(sender: self.selectAllBtn)
                            self.rightItemAction()
                        }
                    }
                }
              
//                self.bottomView.isHidden = self.syncState != .syncFailure
            }
            
            // 操作成功的设备地址
//            var successAddresses: [Address] = []
//            self.sections.forEach({
//                let successfulModels = $0.allModels.filter({ $0.state == .successful })
//                successfulModels.forEach({
//                    if let model = $0 as? SyncDevicesModel {
//                        if !successAddresses.contains(model.address) {
//                            successAddresses.append(model.address)
//                        }
//                    }else if let model = $0 as? SyncDeviceStepTaskModel, let deviceModel = model.parentStepModel?.parentDeviceModel {
//                        if !successAddresses.contains(deviceModel.address) {
//                            successAddresses.append(deviceModel.address)
//                        }
//                    }
//                })
//            })
            
            // 更新设备版本
//            let versionUpdateMessageHandles = configNodes.filter({ $0.versionVerifyCode != nil }).map({ MeshMessageHandle(message: SunricherVendorSet(function: .setVersion(version: $0.versionSEQ + (successAddresses.contains($0.primaryUnicastAddress) ? 1 : 0) , verifyCode: $0.versionVerifyCode ?? 0)), model: $0.sunricherVendorModel!) })
//            MeshProxyMessageCommand.shared.addMessage(messageHandles: versionUpdateMessageHandles, finishedBack: nil)
        }
      
    }
    
    /// 获取下一个需要处理的model
    private func getNextHandleModel() -> SyncCellModel? {
        
        for section in sections {
            let devices = section.allModels.filter({ $0.isKind(of: SyncDevicesModel.classForCoder()) }) as! [SyncDevicesModel]
//            for group in section.groups {
//                if let model = group.deviceModels.first(where: { $0.operationType != nil && ($0.state == .none || $0.state == .wait) }) {
//                    return model
//                }
////                return group.deviceModels.first(where: { $0.operationType != nil && ($0.state == .none || $0.state == .wait) })
//            }
            for device in devices {
                if device.operationType != nil && device.steps.isEmpty && (device.state == .none || device.state == .wait) {
                    return device
                }
                for step in device.steps {
                    if step.relevanceStepModels.contains(where: { $0.state == .failed }) {
                        continue
                    }
                    if let model = step.tasks.first(where: { $0.state == .none || $0.state == .wait }) {
                        return model
                    }
                }
            }
        }
        return nil
    }
    
    private func updateCell(model: SyncCellModel) {
        
        
//            var reloadIndexPath: IndexPath?
            
//            var sectionIndex: Int = 0
//            
//            if let groupModel = model as? SyncDevicesGroupModel, let section = groupModel.parentSectionIndex {
//                sectionIndex = section
//                
//            }else if let deviceModel = model as? SyncDevicesModel {
//                if let groupModel = deviceModel.parentGroupModel, let section = groupModel.parentSectionIndex {
//                    sectionIndex = section
//                    //                if let row = sections[section].rowModels.firstIndex(of: deviceModel) {
//                    //                    reloadIndexPaths.append(IndexPath(item: row, section: section))
//                    //                }
//                }else if let section = deviceModel.parentSectionIndex {
//                    sectionIndex = section
//                    //                if let row = sections[section].rowModels.firstIndex(of: deviceModel) {
//                    //                    reloadIndexPaths.append(IndexPath(item: row, section: section))
//                    //                }
//                }
//                
//            }else if let taskModel = model as? SyncDeviceStepTaskModel, let stepModel = taskModel.parentStepModel, let section = stepModel.parentDeviceModel?.parentSectionIndex {
//                
//                sectionIndex = section
//                
//                //            for (section, sectionModel) in sections.enumerated() {
//                //                let row = (sectionModel.rowModels as NSArray).index(of: stepModel)
//                //                if row != NSNotFound {
//                //                    reloadIndexPaths.append(IndexPath(item: row, section: section))
//                //                    break
//                //                }
//                //            }
//            }
            
//            if let row = self.sections[sectionIndex].rowModels.firstIndex(of: model) {
//                reloadIndexPath = IndexPath(item: row, section: sectionIndex)
//            }
            
//            if reloadIndexPath != nil {
        DispatchQueue.main.async {
//            self.tableView.reloadSections(IndexSet(integer: sectionIndex), with: .none)
            self.tableView.reloadData()
        }
                                
//            }
        
    }
    

    private func setupUI() {
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "titleHeader")
//        tableView.register(SyncDevicesSectionHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(SyncDevicesGroupViewCell.classForCoder(), forCellReuseIdentifier: "groupCell")
        tableView.register(SyncDeviceViewCell.classForCoder(), forCellReuseIdentifier: "deviceCell")
        tableView.register(SyncDeviceStepViewCell.classForCoder(), forCellReuseIdentifier: "stepCell")
        tableView.backgroundColor = .clear
        tableView.sectionFooterHeight = 0
        tableView.estimatedSectionFooterHeight = 0
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        bottomView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-26))
            make.top.equalTo(SCRYFrom(17))
        }
    }


}

extension SyncDevicesViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionModel = sections[section]
        return sectionModel.rowModels.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let sectionModel = sections[indexPath.section]
        guard indexPath.row < sectionModel.rowModels.count else {
            return UITableViewCell()
        }
        let cellModel = sectionModel.rowModels[indexPath.row]
        
        switch cellModel {
        case is SyncDevicesGroupModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! SyncDevicesGroupViewCell
            cell.groupModel = cellModel as? SyncDevicesGroupModel
            cell.delegate = self
            return cell
        case is SyncDevicesSwitchProxyModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! SyncDevicesGroupViewCell
            cell.arrowImageView.isHidden = true
            cell.stateImageView.isHidden = true
            cell.selectBtn.isHidden = true
            if cellModel.isFineshed {
                cell.iconImageBtn.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(48))
                }
            }else {
                cell.iconImageBtn.snp.updateConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                }
            }
            let proxyModel = cellModel as? SyncDevicesSwitchProxyModel
            cell.nameLabel.text = proxyModel?.name
            cell.iconImageBtn.setImage(UIImage(named: proxyModel?.imageName ?? ""), for: .normal)
            return cell
            
        case is SyncDevicesModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell", for: indexPath) as! SyncDeviceViewCell
            cell.model = cellModel as? SyncDevicesModel
            cell.delegate = self
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "stepCell", for: indexPath) as! SyncDeviceStepViewCell
            if let stepModel = cellModel as? SyncDeviceStepModel {
                if let index = stepModel.parentDeviceModel?.steps.firstIndex(of: stepModel) {
                    cell.topLineView.isHidden = index == 0
                    cell.bottomLineView.isHidden = index == stepModel.parentDeviceModel!.steps.count - 1
                }
                cell.stepModel = stepModel
            }
            cell.delegate = self
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        let titleView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "titleHeader") as! SyncDevicesTitleHeaderView
        titleView.titleLabel.text = sections[section].title
        return titleView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0:
            return SCRYFrom(32)
        default:
            return SCRYFrom(40)
        } 
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let cellModel = sections[indexPath.section].rowModels[indexPath.row]
        if let groupModel = cellModel as? SyncDevicesGroupModel { // group
            // 展开/收起 group
            if groupModel.state == .successful || groupModel.state == .failed {
                groupModel.isShow = !groupModel.isShow
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            }
        }else if let deviceModel = cellModel as? SyncDevicesModel { // device
            if deviceModel.steps.count > 0 { // 展开device
                if deviceModel.state == .successful || deviceModel.state == .failed {
                    deviceModel.isShow = !deviceModel.isShow
                }
            }else { // 选择
                if deviceModel.state == .successful || deviceModel.state == .failed {
                    deviceModel.isSelected = !deviceModel.isSelected
                    
                    if let groupModel = deviceModel.parentGroupModel {
                        groupModel.isSelected = !groupModel.deviceModels.contains(where: { !$0.isSelected })
                    }
                    updateSyncStateUI()
                }
            }
            tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
        }else if let stepModel = cellModel as? SyncDeviceStepModel { // 过程
            // 弹窗显示进度
            guard stepModel.tasks.count > 0 else {
                return
            }
            SyncDevicesProgressView.show(stepModel: stepModel) { [weak self] task in
                task.state = .none
                self?.showProressStepModel = stepModel
                self?.syncState = .inSync
                self?.updateSyncStateUI()
                self?.startSync()
            } hide: {[weak self] in
                self?.showProressStepModel = nil
            }
            self.showProressStepModel = stepModel
        }
        
    }

    
}

extension SyncDevicesViewController: SyncDevicesGroupViewCellDelegate {
    
    /// 选中/取消选中更新回调
    func cell(_ cell: SyncDevicesGroupViewCell, didSelectedAction model: SyncDevicesGroupModel) {
        
        var reloadIndexPaths: [IndexPath] = []
        model.deviceModels.forEach({ device in
            if device.state == .failed  {
                device.isSelected = model.isSelected
                
                if let section = model.parentSectionIndex, let row = self.sections[section].rowModels.firstIndex(where: { $0 == device }) {
                    reloadIndexPaths.append(IndexPath(row: row, section: section))
                }
            }
        })
        if reloadIndexPaths.count > 0 {
            tableView.reloadRows(at: reloadIndexPaths, with: .automatic)
        }
        
        updateSyncStateUI()
    }
    
    /// 展开/收起状态更新回调
//    func view(_ view: SyncDevicesSectionHeaderView, showHideStateChanged isShow: Bool)
    /// 点击内容view回调
//    func cellClickAction(cell: SyncDevicesGroupViewCell) {
//        
//    }
    
    /// 点击图标回调
    func cellClickIconAction(cell: SyncDevicesGroupViewCell) {
        
    }
    
}

extension SyncDevicesViewController: SyncDeviceViewCellDelegate {
    
    /// 选中/取消选中更新回调
    func cell(_ cell: SyncDeviceViewCell, didSelectedAction model: SyncDevicesModel) {
        
        model.isSelected = !model.isSelected
        
        if let section = model.parentSectionIndex, let row = self.sections[section].rowModels.firstIndex(where: { $0 == model }) {
            tableView.reloadRows(at: [IndexPath(row: row, section: section)], with: .none)
        }else if let section = model.parentGroupModel?.parentSectionIndex {
            if let groupModel = model.parentGroupModel {
                groupModel.isSelected = !groupModel.deviceModels.contains(where: { !$0.isSelected })
            }
            tableView.reloadSections(IndexSet(integer: section), with: .none)
        }
        
//        var reloadIndexPaths: [IndexPath] = []
//        model.deviceModels.forEach({ device in
//            if device.state == .failed  {
//                device.isSelected = model.isSelected
//                
//                if let section = model.parentSectionIndex, let row = self.sections[section].rowModels.firstIndex(where: { $0 == device }) {
//                    reloadIndexPaths.append(IndexPath(row: row, section: section))
//                }
//            }
//        })
//        if reloadIndexPaths.count > 0 {
//            tableView.reloadRows(at: reloadIndexPaths, with: .automatic)
//        }
        
        updateSyncStateUI()
    }
    
    /// 图标点击回调
    func cell(_ cell: SyncDeviceViewCell, iconClickAction model: SyncDevicesModel) {
        MeshAPI.identify(address: model.address)
    }
    
    /// 失败重试回调
    func cell(_ cell: SyncDeviceViewCell, resyncAction model: SyncDevicesModel) {
        model.state = .none
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
    
}

extension SyncDevicesViewController: SyncDeviceStepViewCellDelegate {
    
    /// 重新同步事件回调
    func cell(_ cell: SyncDeviceStepViewCell, resyncAction model: SyncDeviceStepModel) {
        
        model.tasks.forEach({
            if $0.state == .failed {
                $0.state = .none
            }
        })
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
    
}

extension SyncDevicesViewController {
    
    /// 同步数据类型
    enum SyncType {
        /// 组（设备同步组数据） inNodes：需要进入组的设备list   outNodes：需要组退出的设备list
        case group(_ group: Group, inNodes: [Node]? = nil, outNodes: [Node]? = nil)
        /// 场景
        case scene(_ scene: Scene)
        /// 日程
        case schedule(_ schdule: Schedule)
        /// 动能开关 deleteSwitch: 是否删除动能开关
        case enOceanSwitch(_ switchData: DeviceSwitchData, deleteSwitch: Bool = false)
        /// 按组设置pwm频率
//        case pwmPeriod(_ period: UInt16, group: Group)
        /// 同步设备list
        case devices(_ nodes: [Node])
        /// 同步设备参数
        case devicesParameter(_ datas: [(node: Node, parameters: [DeviceParameterType])])
        /// Dongle设备
        case dongle(_ dongleData: DeviceDongleData)
        /// 邻近照明路径
        case proximityLightingPath(group: Group, path: GroupProximityLightingPathData)
    }
    
    /// 同步状态
    enum SyncState {
        /// 同步中
        case inSync
        /// 同步失败
        case syncFailure
        /// 同步成功
        case syncSuccess
    }
    
    
    
}
