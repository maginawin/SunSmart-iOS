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
    private var progressLabel: UILabel!
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
    /// lux触发锁定的设备list
    var luxTriggerLockDevices: [Node] = []
    /// 自动化恢复
    var automationRestore: Bool = false
    /// 重试次数
    private var retryCount: Int = 0
    /// 同步的设备list
    private var syncNodes: [Node] = []
    /// SAVE Profile 期间临时禁用/恢复组内 PIR 传感器
    var profileSensorProtectionContext: ProfileSensorProtectionContext?
    private var batteryPowerSwitchActivationFlow: PJEightKeySwitchActivationFlow?
    private var batteryPowerSwitchOwnConfigurationFailed = false
    private var batteryPowerSwitchKeyConfigurationCompleted = false
    private var batteryPowerSwitchKeyConfigEarliestDate: Date?
    private var syncRunIdentifier = UUID()

    private static let batteryPowerSwitchKeyConfigInitialDelay: TimeInterval = 3
    private static let batteryPowerSwitchPostKeyConfigProcessingDelay: TimeInterval = 0.5
    
    private var deviceBlinkMode: DeviceBlinkMode = .none
    
    var vcTitle: String?
    
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
        
        title = vcTitle ?? "sync_device(s)".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "re_sync".localizedString, color: Title_Color, font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(rightItemAction))
        
        if automationRestore {
            retryCount = 2
        }
        
        setupUI()
        
        deviceBlinkMode = SpaceViewController.currentDeviceBlinkMode
        
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
                let currentNodes = group.nodes
                let remainingNodes = currentNodes.filter { node in
                    !(outNodes?.contains(node) ?? false)
                }
                let addedNodes = (inNodes ?? []).filter { node in
                    !remainingNodes.contains(node)
                }
                let effectiveMemberCount = remainingNodes.count + addedNodes.count
                
                outNodes?.forEach({ node in
                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                })
                
                inNodes?.forEach({ node in
                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                })
                
                group.nodes.filter({ node in !(outNodes?.contains(node) ?? false) }).forEach { node in
                    let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
                    if let removceDevice = result.removeDevice {
                        removeSection.devices.append(removceDevice)
                    }
                    if let configurationDevice = result.configturationDevice {
                        configurationSection.devices.append(configurationDevice)
                    }
                }
                if inNodes == nil, outNodes == nil, let context = profileSensorProtectionContext {
                    if let preDisableDevice = context.preDisableDeviceModel() {
                        configurationSection.devices.insert(preDisableDevice, at: 0)
                    }
                    if let postTargetStateDevice = context.postTargetStateDeviceModel() {
                        configurationSection.devices.append(postTargetStateDevice)
                    }
                }
                appendEmergencyFireControllerGroupMutationItems(to: configurationSection, group: group, addNodes: inNodes ?? [], exitNodes: outNodes ?? [])
            case .emergencyFire(let data, let suppliedItems, let persistsSyncResult, let changedFromConfiguration):
                let targetSection = persistsSyncResult ? configurationSection : removeSection
                targetSection.prefersDevicesBeforeGroups = true
                appendEmergencyFireControllerItems(
                    to: targetSection,
                    data: data,
                    items: suppliedItems ?? makeEmergencyFireControllerItems(data: data, changedFromConfiguration: changedFromConfiguration)
                )
            case .profile(let datas):
                datas.forEach { (node: Node, profiles: [ProfileType]) in
                    // 锁定配置切换操作
                    var luxTriggerLockStep: SyncDeviceStepModel?
                    // 设置白天/晚上lux阈值操作
                    var luxThresholdStep: SyncDeviceStepModel?
                    // 切换到对应profile操作
                    var switchProfileStep: SyncDeviceStepModel?
                    // 保存到profile 场景
                    var lastProfileStoreStep: SyncDeviceStepModel?
                    /// 同步profile场景的操作list
                    var syncProfileSceneSteps: [SyncDeviceStepModel] = []
                    let syncProfileSteps = profiles.map({
                        
                        let task = SyncDeviceStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .profile(type: $0)))
                        
                        let step = SyncDeviceStepModel(type: $0.title, state: .none, tasks: [task])
                        task.parentStepModel = step
                        
                        // 设置前置条件关联
                        switch $0 {
                        case .profileToggleTriggerConditionLuxLock:
                            luxTriggerLockStep = step
                        case .profileDayToggleTriggerConditionLux, .profileNightToggleTriggerConditionLux:
                            luxThresholdStep = step
                        case .lightControlSwitch, .daylightSensorConditionRecall:
                            switchProfileStep = step
                            if luxTriggerLockStep != nil {
                                step.relevanceStepModels.append(luxTriggerLockStep!)
                            }
                            if luxThresholdStep != nil {
                                step.relevanceStepModels.append(luxThresholdStep!)
                            }
                            if lastProfileStoreStep != nil {
                                step.relevanceStepModels.append(lastProfileStoreStep!)
                            }
                        case .lightControlStore:
                            step.relevanceStepModels = syncProfileSceneSteps
                            syncProfileSceneSteps.removeAll()
                            lastProfileStoreStep = step
                        case .powerOnState, .daylightCalibration, .daylightCalibrateRate, .daylightCalibrateInflectionPoint, .sensitivity, .lightControlDelete, .profileToggleTriggerConditionLuxDelete:
                            break
                        default:
                            if luxTriggerLockStep != nil {
                                step.relevanceStepModels.append(luxTriggerLockStep!)
                            }
                            if switchProfileStep != nil {
                                step.relevanceStepModels.append(switchProfileStep!)
                            }
                            syncProfileSceneSteps.append(step)
                        }
                        return step
                    })
                    
                    let deviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    deviceModel.steps = syncProfileSteps
                    syncProfileSteps.forEach { step in
                        step.parentDeviceModel = deviceModel
                    }
                    configurationSection.devices.append(deviceModel)
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
            case .batteryPowerSwitch(let switchData):
                configurationSection.prefersDevicesBeforeGroups = true
                appendBatteryPowerSwitchItems(to: configurationSection, removeSection: removeSection, switchData: switchData)
                
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
                            case .powerCalibration(let calibrationValue):
                                let taskModel = SyncDeviceStepTaskModel(name: "power_calibrate".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .powerCalibration(calibrationValue: calibrationValue))))
                                
                                let step = SyncDeviceStepModel(type: "power_calibrate".localizedString, state: .none, tasks: [taskModel])
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
                        case .proximityLightingRelayNumber(let relayNumber):
                            let taskModel = SyncDeviceStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
                            
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
            case .spaceTriggerZones(let datas):
                datas.forEach { (node: Node, syncData: NodeSyncData) in
                    let syncDeviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    syncDeviceModel.imageName = node.iconName
                    
                    switch syncData {
                    case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                        let taskModel = SyncDeviceStepTaskModel(name: "trigger_zone".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))
                        let step = SyncDeviceStepModel(type: "trigger_zone".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        step.parentDeviceModel = syncDeviceModel
                        syncDeviceModel.steps.append(step)
                    case .proximityLightingRelayNumber(let relayNumber):
                        let taskModel = SyncDeviceStepTaskModel(name: "trigger_zone".localizedString, operationType: .configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
                        let step = SyncDeviceStepModel(type: "trigger_zone".localizedString, state: .none, tasks: [taskModel])
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
                    
                    if syncDeviceModel.steps.count > 0 {
                        configurationSection.devices.append(syncDeviceModel)
                    }
                }
            }
        
            let appendSectionIfNeeded: (SyncDevicesSectionModel) -> Void = { section in
                if section.groups.count > 0 || section.devices.count > 0 || section.switchProxy != nil {
                    self.sections.append(section)
                }
            }

            if case .batteryPowerSwitch = self.type {
                appendSectionIfNeeded(configurationSection)
                appendSectionIfNeeded(removeSection)
            } else {
                appendSectionIfNeeded(removeSection)
                appendSectionIfNeeded(configurationSection)
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

    private func appendBatteryPowerSwitchItems(
        to section: SyncDevicesSectionModel,
        removeSection: SyncDevicesSectionModel,
        switchData: PJEightKeySwitchData
    ) {
        guard let switchNode = switchData.proxyNode, switchData.linkGroup != nil else {
            syncState = .syncFailure
            return
        }

        let switchDeviceModel = SyncDevicesModel(name: switchData.name, address: switchNode.primaryUnicastAddress)
        let switchIconName = UIImage(named: switchNode.iconName) != nil ? switchNode.iconName : "device_BatteryPowerSwitch"
        switchDeviceModel.imageName = switchIconName

        var configurationDependencies: [SyncDeviceStepModel] = []
        if switchData.needsBatteryPowerSwitchConfigurationSync {
            let keyConfigTask = SyncDeviceStepTaskModel(name: "Key Config", operationType: .configuration(node: switchNode, type: .batteryPowerSwitchKeyConfig(switchData: switchData)))
            let keyConfigStep = SyncDeviceStepModel(type: "Key Config", state: .none, tasks: [keyConfigTask])
            keyConfigTask.parentStepModel = keyConfigStep
            keyConfigStep.parentDeviceModel = switchDeviceModel

            let publicationTask = SyncDeviceStepTaskModel(name: "Model Publication", operationType: .configuration(node: switchNode, type: .batteryPowerSwitchModelPublication(switchData: switchData)))
            let publicationStep = SyncDeviceStepModel(type: "Model Publication", state: .none, tasks: [publicationTask])
            publicationTask.parentStepModel = publicationStep
            publicationStep.parentDeviceModel = switchDeviceModel
            publicationStep.relevanceStepModels = [keyConfigStep]

            switchDeviceModel.steps = [keyConfigStep, publicationStep]
            section.devices.append(switchDeviceModel)
            configurationDependencies = [keyConfigStep, publicationStep]
        }

        let targetGroups = switchData.bindGroups.sorted { $0.address.address < $1.address.address }
        targetGroups.compactMap {
            makeBatteryPowerSwitchTargetGroupModel(group: $0, switchData: switchData, unsubscribe: false, dependencies: configurationDependencies)
        }.forEach { section.groups.append($0) }

        let removedGroups = switchData.unbindGroupAddresses
            .compactMap { MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress($0)) }
            .sorted { $0.address.address < $1.address.address }
        removedGroups.compactMap {
            makeBatteryPowerSwitchTargetGroupModel(group: $0, switchData: switchData, unsubscribe: true, dependencies: configurationDependencies)
        }.forEach { removeSection.groups.append($0) }
    }

    private func makeBatteryPowerSwitchTargetGroupModel(
        group: Group,
        switchData: PJEightKeySwitchData,
        unsubscribe: Bool,
        dependencies: [SyncDeviceStepModel]
    ) -> SyncDevicesGroupModel? {
        guard let switchGroup = switchData.linkGroup else { return nil }

        let title = unsubscribe ? "Group Unsubscription" : "Group Subscription"
        let deviceModels = group.nodes.compactMap { node -> SyncDevicesModel? in
            let handles = unsubscribe
                ? node.getBatteryPowerSwitchUnsubscriptionMessageHandles(switchGroup: switchGroup)
                : node.getBatteryPowerSwitchSubscriptionMessageHandles(switchGroup: switchGroup)
            guard !handles.isEmpty else {
                return nil
            }

            let task = SyncDeviceStepTaskModel(
                name: title,
                operationType: .configuration(
                    node: node,
                    type: .batteryPowerSwitchTargetSubscription(switchData: switchData, group: group, unsubscribe: unsubscribe)
                )
            )
            let step = SyncDeviceStepModel(type: title, state: .none, tasks: [task])
            step.relevanceStepModels = dependencies
            task.parentStepModel = step

            let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            model.imageName = node.iconName
            model.steps = [step]
            step.parentDeviceModel = model
            return model
        }

        guard !deviceModels.isEmpty else {
            return nil
        }

        let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
        deviceModels.forEach { $0.parentGroupModel = groupModel }
        return groupModel
    }

    private func appendEmergencyFireControllerGroupMutationItems(to section: SyncDevicesSectionModel, group: Group, addNodes: [Node], exitNodes: [Node]) {
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

    private func makeEmergencyFireControllerItems(
        data: DeviceEmerFireData,
        changedFromConfiguration: EmergencyFireControllerConfiguration?
    ) -> [EmergencyFireControllerSyncItem] {
        do {
            let planner = EmergencyFireControllerSyncPlanner(
                data: data,
                meshUUID: data.meshUUID,
                subnetworkId: data.meshNetworkId,
                changedFromConfiguration: changedFromConfiguration
            )
            return try planner.makeItems()
        } catch {
            syncState = .syncFailure
            DispatchQueue.main.async {
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
            return []
        }
    }

    private func appendEmergencyFireControllerItems(
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
        if let autoRestoreTask = tasks.first, tasks.count == 1, autoRestoreTask.kind == .autoRestore {
            let model = SyncDevicesModel(name: "AUTO", address: autoRestoreTask.address)
            model.imageName = "device_light"
            model.steps = [autoRestoreTask].compactMap { task in
                makeEmergencyFireControllerLeafStep(task: task, data: data)
            }
            model.steps.forEach { step in
                step.parentDeviceModel = model
            }
            guard !model.steps.isEmpty else { return nil }
            return model
        }

        guard let firstTask = tasks.first,
              let node = nodeForEmergencyFireControllerTask(firstTask, data: data) else {
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
        data: DeviceEmerFireData
    ) -> SyncDeviceStepModel? {
        guard let taskModel = makeEmergencyFireControllerTaskModel(task: task, data: data) else {
            return nil
        }
        let step = SyncDeviceStepModel(type: emergencyFireControllerTaskDisplayName(task, data: data), state: .none, tasks: [taskModel])
        taskModel.parentStepModel = step
        return step
    }

    private func makeEmergencyFireControllerTaskModel(
        task: EmergencyFireControllerSyncTask,
        data: DeviceEmerFireData
    ) -> SyncDeviceStepTaskModel? {
        guard let node = nodeForEmergencyFireControllerTask(task, data: data) else {
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
            if let settings = data.activeModeSettings {
                return "Send Count \(settings.stopCount)"
            }
            return "Send Count"
        case .restoreDelay:
            if let settings = data.activeModeSettings {
                return "Resuming in \(settings.restoreDelaySeconds)s"
            }
            return "Resuming in"
        case .triggerScene:
            if let brightness = data.activeModeSettings?.triggerBrightness {
                return "\("linked_set_brightness_to".localizedString) \(brightness)%"
            }
            return "linked_set_brightness_to".localizedString
        case .autoRestore:
            return "AUTO"
        default:
            return task.kind.rawValue
        }
    }

    private func nodeForEmergencyFireControllerTask(_ task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData) -> Node? {
        MeshNetworkManager.instance.meshNetwork?.node(withAddress: task.address) ?? data.bindNode
    }

    private func emergencyFireControllerTask(for model: SyncCellModel) -> (task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData)? {
        let operationType = (model as? SyncDevicesModel)?.operationType ?? (model as? SyncDeviceStepTaskModel)?.operationType
        guard case .configuration(_, let type) = operationType,
              case .emergencyFireController(let task, let data) = type else {
            return nil
        }
        return (task, data)
    }

    private func clearEmergencyFireControllerPendingIfNeeded(for model: SyncCellModel) {
        guard let taskContext = emergencyFireControllerTask(for: model) else { return }
        taskContext.data.clearPending(for: taskContext.task, meshUUID: taskContext.data.meshUUID, subnetworkId: taskContext.data.meshNetworkId)
    }

    private func completeEmptyEmergencyFireControllerTaskIfNeeded(for model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        guard messageHandles.isEmpty, let taskContext = emergencyFireControllerTask(for: model) else {
            return false
        }
        guard !taskContext.task.isUnsupported else {
            model.state = .failed
            (model as? SyncDevicesModel)?.failedCount += 1
            (model as? SyncDeviceStepTaskModel)?.failedCount += 1
            updateCell(model: model)
            return true
        }
        model.state = .successful
        clearEmergencyFireControllerPendingIfNeeded(for: model)
        updateCell(model: model)
        return true
    }

    private func completeEmergencyFireControllerAutoRestoreTaskIfNeeded(
        for model: SyncCellModel,
        messageHandles: [MeshMessageHandle],
        completion: @escaping () -> Void
    ) -> Bool {
        guard let taskContext = emergencyFireControllerTask(for: model),
              taskContext.task.kind == .autoRestore else {
            return false
        }
        guard messageHandles.count == 1,
              let messageHandle = messageHandles.first,
              let address = messageHandle.address ?? messageHandle.model?.parentElement?.unicastAddress else {
            model.state = .failed
            (model as? SyncDevicesModel)?.failedCount += 1
            (model as? SyncDeviceStepTaskModel)?.failedCount += 1
            updateCell(model: model)
            completion()
            return true
        }

        MeshAPI.sendMessage(message: messageHandle.message, address: address, defaultTTL: messageHandle.defaultTTL)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self, weak model] in
            guard let self, let model, self.syncState == .inSync else {
                completion()
                return
            }
            model.state = .successful
            self.clearEmergencyFireControllerPendingIfNeeded(for: model)
            self.updateCell(model: model)
            completion()
        }
        return true
    }

    private func isEmergencyFireControllerDeleteCleanup(_ model: SyncCellModel) -> Bool {
        guard case .emergencyFire(_, _, let persistsSyncResult, _) = type,
              !persistsSyncResult,
              let taskContext = emergencyFireControllerTask(for: model) else {
            return false
        }
        return taskContext.task.kind == .deleteCleanup
    }

    private func ackTimeout(for model: SyncCellModel) -> TimeInterval {
        isEmergencyFireControllerDeleteCleanup(model) ? 5 : 15
    }

    private func finishEmergencyFireControllerSyncIfNeeded(success: Bool) {
        guard case .emergencyFire(let data, _, let persistsSyncResult, _) = type else {
            return
        }

        if persistsSyncResult {
            data.isSynced = success
            DeviceEmerFireStore.shared.save(data)
        }
        let postSyncNotifications = {
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            NotificationCenter.default.postLinkedEmerFireConfigDidChange(data.toConfig())
        }
        if Thread.isMainThread {
            postSyncNotifications()
        } else {
            DispatchQueue.main.async {
                postSyncNotifications()
            }
        }
    }
    
    /// 获取组对应设备同步数据model
    /// - Parameters:
    ///   - group: 组
    ///   - node: 设备
    ///   - exitGroup: 是否退组
    /// - Returns: 需要配置的model，需要删除的model
    private func getSyncDeviceModel(group: Group?, node: Node, effectiveMemberCount: Int? = nil) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
        
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
            syncDataTypes = node.getSyncData(type: .group(group, effectiveMemberCount: effectiveMemberCount))
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
                if profileSensorProtectionContext != nil {
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
                    if let batteryPowerSwitchData = $0.batteryPowerSwitchData,
                       let targetGroup = group ?? node.group {
                        return SyncDeviceStepTaskModel(name: batteryPowerSwitchData.name, operationType: .configuration(node: node, type: .batteryPowerSwitchTargetSubscription(switchData: batteryPowerSwitchData, group: targetGroup, unsubscribe: false)))
                    }
                    return SyncDeviceStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if syncSwitchTasks.count > 0 {
                    let step = SyncDeviceStepModel(type: "switch".localizedString, state: .none, tasks: syncSwitchTasks)
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
                    case .powerCalibration(let calibrationValue):
                        let taskModel = SyncDeviceStepTaskModel(name: "power_calibrate".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .powerCalibration(calibrationValue: calibrationValue))))
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
        invalidateCurrentSyncRun()
        
        applyProfileSensorTargetStateInBackgroundIfNeeded()
        
        // 判断是否有lux触发设备需要解锁
        if self.luxTriggerLockDevices.count > 0 {
            let unlockMessage = SunricherVendorSet(function: .daylightLuxTriggerLock(delay: 0))
            if self.luxTriggerLockDevices.count > 3 { // 超过3个广播解锁
                MeshAPI.sendMessage(message: unlockMessage, address: .allNodes)
            }else { // 3个以内单播解锁
                self.luxTriggerLockDevices.forEach({
                    if let vendorModel = $0.sunricherVendorModel {
                        MeshAPI.sendMessage(message: unlockMessage, model: vendorModel)
                    }
                })
            }
        }
        
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
            closeAfterSync()
        }
    }

    private func closeAfterSync() {
        let isNavigationRoot = navigationController?.viewControllers.first === self
        if isNavigationRoot, presentingViewController != nil || navigationController?.presentingViewController != nil {
            dismiss(animated: true)
        } else if navigationController == nil, presentingViewController != nil {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    @objc private func rightItemAction() {
        if syncState == .inSync { // stop
            invalidateCurrentSyncRun()
            
            MeshProxyMessageCommand.shared.stopSendMessage { [weak self] _ in
                self?.applyProfileSensorTargetStateInBackgroundIfNeeded()
            }
            
            // 当前设置的设备存在profile快照恢复未设置时
            if let deviceModel = lastDeviceModel, let settingsStep = deviceModel.steps.first(where: { $0.state == .inSettings }) {
                if let task = settingsStep.tasks.first(where: { task in
                    switch task.operationType {
                    case .configuration(_, let type):
                        if case .profile(let profileType) = type {
                            if case .lightControlRestore = profileType, task.state == .wait {
                                return true
                            }
                        }
                        return false
                    default:
                        return false
                    }
                }) {
                   // 恢复快照，避免profile运行异常
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        MeshProxyMessageCommand.shared.addMessage(messageHandles: task.operationType.messageHandles, finishedBack: nil)
                    }
               }
            }
//            if let stepModel = $0 as? SyncDeviceStepModel {
//                stepModel.tasks.contains { task in
//                    switch task.operationType {
//                    case .configuration(let node, let type):
//                        if case .profile(let profileType) = type {
//                            if profileType == .lightControlRestore(sceneNumber)
//                        }
//                    }
//                }
//            }
            
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
            finishEmergencyFireControllerSyncIfNeeded(success: false)
        }else if syncState == .syncFailure {
            
//            let failedModels = sections.filter({ $0.allModels.contains(where: { $0 is SyncDevicesModel && ($0.state == .failed || $0.state == .repeatedFailure) }) })
            
            let selectModels = selectedFailedDevicesForResync()
            if selectModels.count > 0 {
                if selectModels.contains(where: { containsBatteryPowerSwitchConfiguration($0) }) {
                    startBatteryPowerSwitchConfigurationResyncAfterActivation()
                } else {
                    selectModels.forEach({ device in
//                    device.state = .none
//                    device.steps.forEach({
//                        $0.tasks.forEach({ task in
//                            if task.state != .successful {
//                                task.state = .none
//                                // 检查是否有profile数据需要加锁、切换场景前置要求，需要则重试必须连带前置条件一起设置
//                                if task.relevanceTaskModels.count > 0 {
//                                    task.resyncRelevanceCheck().forEach({
//                                        $0.state = .none
//                                    })
//                                }
//                            }
//                        })
//                    })
                        prepareDeviceForResync(device)
                    })
                    
//                tableView.reloadData()
                    syncState = .inSync
                    startSync()
                }
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
        
        let devices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
        progressLabel.text = "\(devices.filter({ $0.state == .successful }).count)/\(devices.count)"
        
        if syncState == .inSync {
            navigationItem.rightBarButtonItem?.title = "stop".localizedString
            navigationItem.rightBarButtonItem?.isEnabled = true
            bottomView.isHidden = false
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomView.height, right: 0)
            backBtn.isHidden = true
            selectAllBtn.isHidden = true
        }else if syncState == .syncSuccess {
            bottomView.isHidden = true
            navigationItem.rightBarButtonItem = UIBarButtonItem()
            backBtn.isHidden = false
        }else if syncState == .syncFailure{
            navigationItem.rightBarButtonItem?.title = "re_sync".localizedString
            bottomView.isHidden = false
            selectAllBtn.isHidden = false
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
    
    private func applyProfileSensorTargetStateIfNeeded() {
        guard let context = profileSensorProtectionContext else {
            return
        }

        let messageHandles = context.remainingTargetStateMessageHandles()
        guard !messageHandles.isEmpty else {
            return
        }
        
        let semaphore = DispatchSemaphore(value: 0)
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 7, progressBack: nil, successfulBack: nil, failedBack: nil) { resultMessageHandles in
            resultMessageHandles.forEach { handle in
                if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
                   let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                    node.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                    node.clearSyncStateCache()
                }
            }
            semaphore.signal()
        }
        semaphore.wait()
    }
    
    private func applyProfileSensorTargetStateInBackgroundIfNeeded() {
        DispatchQueue.global().async {
            self.applyProfileSensorTargetStateIfNeeded()
        }
    }

    private func completeProfileSensorProtectionTaskIfNeeded(for model: SyncCellModel) -> Bool {
        guard let taskModel = model as? SyncDeviceStepTaskModel else {
            return false
        }

        switch taskModel.operationType {
        case .configuration(let node, let type):
            switch type {
            case .profileSensorProtectionDisable:
                profileSensorProtectionContext?.markPreDisableStarted()
                return false
            case .profileSensorTargetEnable:
                profileSensorProtectionContext?.markTargetStateTaskStarted(for: node)
                return false
            default:
                return false
            }
        default:
            return false
        }
    }

    private func startSync() {
        
//        guard let section = sections.first, let model = section.allModels.first else { return }
        // 需要配置的设备list
        var configNodes: [Node] = []
        batteryPowerSwitchOwnConfigurationFailed = false
        batteryPowerSwitchKeyConfigurationCompleted = false
        let syncRunIdentifier = beginSyncRun()
        
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
                guard self.isActiveSyncRun(syncRunIdentifier) else {
                    return
                }
                
                guard MeshLibManager.manager.isOpenBluetooth else {
                    self.sections.forEach { section in
                        section.allModels.forEach({
                            $0.state = .failed
                            $0.isFineshed = true
                        })
                    }
                    self.syncState = .syncFailure
                    self.applyProfileSensorTargetStateIfNeeded()
                    
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
                    // 设置白天、晚上数据时记录下当前运行的配置，设置完成后恢复对应配置
                    if case .configuration(let node, let type) = taskModel.operationType, node.capabilities.contains(.lightSensorConditionRecall), case .profile(let profiletType) = type {
                        if let vendorModel = node.sunricherVendorModel {
                            switch profiletType {
                            case .profileToggleTriggerConditionLuxLock: // 加锁
                                node.daylightRecallConditionId = nil
                                messageHandles.insert(MeshMessageHandle(message: SunricherVendorGet(function: .daylightConditionRecallGet), model: vendorModel), at: 0)
                            case .profileToggleTriggerConditionLuxUnLock: // 解锁
                                if let index = node.daylightRecallConditionId {
                                    messageHandles.insert(MeshMessageHandle(message: SunricherVendorSet(function: .daylightConditionRecall(index: index)), model: vendorModel), at: 0)
                                }
                            default:
                                break
                            }
                        }
                    }
                    
                    
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
                messageHandles = self.batteryPowerSwitchMessageHandles(for: model, defaultHandles: messageHandles)
                
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }

                if self.completeProfileSensorProtectionTaskIfNeeded(for: model) {
                    DispatchQueue.main.async {
                        if let model = self.showProressStepModel {
                            if let progressView = SyncDevicesProgressView.current() {
                                progressView.stepModel = model
                            }
                        }
                        let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
                        self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
                    }
                    continue
                }

                if self.completeEmptyEmergencyFireControllerTaskIfNeeded(for: model, messageHandles: messageHandles) {
                    DispatchQueue.main.async {
                        if let model = self.showProressStepModel {
                            if let progressView = SyncDevicesProgressView.current() {
                                progressView.stepModel = model
                            }
                        }
                        let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
                        self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
                    }
                    continue
                }

                if self.completeEmergencyFireControllerAutoRestoreTaskIfNeeded(for: model, messageHandles: messageHandles, completion: {
                    semaphore.signal()
                }) {
                    semaphore.wait()
                    DispatchQueue.main.async {
                        if let model = self.showProressStepModel {
                            if let progressView = SyncDevicesProgressView.current() {
                                progressView.stepModel = model
                            }
                        }
                        let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
                        self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
                    }
                    continue
                }
                
                if self.batteryPowerSwitchOwnConfigurationFailed,
                   self.isBatteryPowerSwitchOwnConfiguration(model) {
                    model.state = .failed
                    (model as? SyncDevicesModel)?.failedCount += 1
                    (model as? SyncDeviceStepTaskModel)?.failedCount += 1
                    self.updateCell(model: model)
                    DispatchQueue.main.async {
                        if let model = self.showProressStepModel,
                           let progressView = SyncDevicesProgressView.current() {
                            progressView.stepModel = model
                        }
                    }
                    continue
                }

                if self.isMissingRequiredBatteryPowerSwitchConfigurationHandles(model, messageHandles: messageHandles) {
                    model.state = .failed
                    (model as? SyncDevicesModel)?.failedCount += 1
                    (model as? SyncDeviceStepTaskModel)?.failedCount += 1
                    self.batteryPowerSwitchOwnConfigurationFailed = true
                    self.markPendingBatteryPowerSwitchOwnConfigurationTasksFailed()
                    self.updateCell(model: model)
                    continue
                }

                guard self.waitBeforeBatteryPowerSwitchKeyConfigIfNeeded(for: model, syncRunIdentifier: syncRunIdentifier) else {
                    return
                }
                
                let isBatteryPowerSwitchKeyConfigModel = self.isBatteryPowerSwitchKeyConfigConfiguration(model)
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: self.ackTimeout(for: model), progressBack: nil, successfulBack: { handle, statusMessage in
                    // 判断如果是设备初始化消息，则需要再初始化完成后完成基本配置
                    if statusMessage is ConfigCompositionDataStatus || statusMessage is ConfigAppKeyStatus {
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address), node.isInitialize {
                            MeshProxyMessageCommand.shared.addMessage(messageHandles: node.getConfigMessageHandles(), finishedBack: nil)
                        }
                    }else if (statusMessage is LightLightnessStatus || statusMessage is LightCTLTemperatureStatus || statusMessage is LightCTLStatus || statusMessage is LightHSLStatus), messageHandles.contains(where: { $0.message is SceneStore }) { // 设置场景时需要及时更新状态属性
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            node.updateNodeStatus(message: statusMessage, source: address)
                        }
                    }else if let vendorStatusMessage = statusMessage as? SunricherVendorStatus {
                        if vendorStatusMessage.status.code == .dimmerPowerCalibrate {
                            if vendorStatusMessage.status.errorCode == 2 { // 功率校准异常
                                if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                                    if case .dimmerPowerCalibrateError(let maxPower) = vendorStatusMessage.status.parameters {
                                        node.powerCalibrateError = .powerExceed(maxPower: Int(maxPower / 10))
                                    }else {
                                        node.powerCalibrateError = .powerExceed(maxPower: 300)
                                    }
                                }
                            }
                        }else if vendorStatusMessage.status.code == .daylightLuxTriggerLock { // lux触发场景锁定/解锁
                            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                                if let vendorSet = handle.message as? SunricherVendorSet, case .daylightLuxTriggerLock(let delay) = vendorSet.function {
                                    if delay > 0 {
                                        if !self.luxTriggerLockDevices.contains(node) {
                                            self.luxTriggerLockDevices.append(node)
                                        }
                                    }else {
                                        if let index = self.luxTriggerLockDevices.firstIndex(of: node) {
                                            self.luxTriggerLockDevices.remove(at: index)
                                        }
                                    }
                                }
                            }
                        }else if handle.message is SunricherVendorGet, case .daylightConditionRecall(let index) = vendorStatusMessage.status.parameters, index >= 0 { // 记录当前运行的白天/黑夜条件配置
                            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                                node.daylightRecallConditionId = UInt8(index)
                            }
                        }
                    }
                }, failedBack: { handle in
                    if let vendorSetMessage = handle.message as? SunricherVendorSet, case .dimmerPowerCalibrate = vendorSetMessage.function { // 功率校准超时
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            node.powerCalibrateError = .timeout
                        }
                    }
                }) {[weak self] resultMessageHandles in
                    guard let self = self else { return }
                    resultMessageHandles.forEach { handle in
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            node.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                            // 清空同步缓存状态
                            node.clearSyncStateCache()
//                            if !self.syncNodes.contains(node) {
//                                self.syncNodes.append(node)
//                            }
                        }
                    }
                    
                    let resultSuccessful = !resultMessageHandles.contains(where: { !$0.isSuccessful })
                    let operationSuccessful = ((model as? SyncDevicesModel)?.operationType?.isSuccessful ?? (model as? SyncDeviceStepTaskModel)?.operationType.isSuccessful) ?? false
                    if self.isBatteryPowerSwitchOperationSuccessful(
                        model: model,
                        resultSuccessful: resultSuccessful,
                        operationSuccessful: operationSuccessful,
                        messageHandles: messageHandles
                    ) || self.isEmergencyFireControllerDeleteCleanup(model) {
                        model.state = .successful
                        self.clearEmergencyFireControllerPendingIfNeeded(for: model)
                        if isBatteryPowerSwitchKeyConfigModel {
                            self.batteryPowerSwitchKeyConfigurationCompleted = true
                        }
                        
                        if self.deviceBlinkMode != .none {
                            let deviceModel: SyncDevicesModel? =
                            (model as? SyncDevicesModel)
                            ?? (model as? SyncDeviceStepTaskModel)?.parentStepModel?.parentDeviceModel
                            // 设备全部成功判断
                            if let deviceModel = deviceModel,
                               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: deviceModel.address),
                                deviceModel.state == .successful {
                                // 发送设备闪烁命令
                                node.sendHandleCompleteIdentify(deviceBlinkMode: self.deviceBlinkMode)
                            }
                        }
                        
                    }else {
                        model.state = .failed
                        (model as? SyncDevicesModel)?.failedCount += 1
                        (model as? SyncDeviceStepTaskModel)?.failedCount += 1
                        if self.isBatteryPowerSwitchOwnConfiguration(model) {
                            self.batteryPowerSwitchOwnConfigurationFailed = true
                            self.markPendingBatteryPowerSwitchOwnConfigurationTasksFailed()
                        }
                    }
                    self.updateCell(model: model)
                    semaphore.signal()
                }
                semaphore.wait()
                if isBatteryPowerSwitchKeyConfigModel, model.state == .successful {
                    self.waitAfterBatteryPowerSwitchKeyConfigSuccessIfNeeded(for: model)
                }
                
                DispatchQueue.main.async {
                    if let model = self.showProressStepModel {
                        if let progressView = SyncDevicesProgressView.current() {
                            progressView.stepModel = model
                        }
                    }
                    let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
                    self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
                }
            }
//            _ = MeshNetworkManager.instance.save()
            print("完成")
            
            self.applyProfileSensorTargetStateIfNeeded()
            
            self.sections.forEach { section in
                section.allModels.forEach({
    //                $0.state = .wait
                    $0.isFineshed = true
                })
            }
            self.syncState = self.sections.contains(where: { $0.allModels.contains(where: { $0.state == .failed }) }) ? .syncFailure : .syncSuccess
            self.finishEmergencyFireControllerSyncIfNeeded(success: self.syncState == .syncSuccess)
            
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
    
    private func beginSyncRun() -> UUID {
        let identifier = UUID()
        syncRunIdentifier = identifier
        if batteryPowerSwitchDataForSync != nil {
            batteryPowerSwitchKeyConfigEarliestDate = Date().addingTimeInterval(Self.batteryPowerSwitchKeyConfigInitialDelay)
        } else {
            batteryPowerSwitchKeyConfigEarliestDate = nil
        }
        return identifier
    }

    private func invalidateCurrentSyncRun() {
        syncRunIdentifier = UUID()
        batteryPowerSwitchKeyConfigEarliestDate = nil
    }

    private func isActiveSyncRun(_ identifier: UUID) -> Bool {
        syncRunIdentifier == identifier && syncState == .inSync
    }

    @discardableResult
    private func waitBeforeBatteryPowerSwitchKeyConfigIfNeeded(for model: SyncCellModel, syncRunIdentifier identifier: UUID) -> Bool {
        guard isBatteryPowerSwitchKeyConfigConfiguration(model),
              let earliestDate = batteryPowerSwitchKeyConfigEarliestDate else {
            return isActiveSyncRun(identifier)
        }
        let waitTime = earliestDate.timeIntervalSinceNow
        if waitTime > 0 {
            Thread.sleep(forTimeInterval: waitTime)
        }
        batteryPowerSwitchKeyConfigEarliestDate = nil
        return isActiveSyncRun(identifier)
    }

    private func waitAfterBatteryPowerSwitchKeyConfigSuccessIfNeeded(for model: SyncCellModel) {
        guard isBatteryPowerSwitchKeyConfigConfiguration(model) else {
            return
        }
        Thread.sleep(forTimeInterval: Self.batteryPowerSwitchPostKeyConfigProcessingDelay)
    }

    private var batteryPowerSwitchDataForSync: PJEightKeySwitchData? {
        guard case .batteryPowerSwitch(let switchData) = type else {
            return nil
        }
        return switchData
    }
    
    private func isBatteryPowerSwitchConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchModelPublication:
                return true
            case .batteryPowerSwitchTargetSubscription:
                return false
            default:
                return false
            }
        default:
            return false
        }
    }
    
    private func isBatteryPowerSwitchOwnConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchModelPublication:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    private func isBatteryPowerSwitchSyncOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType), .delete(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig,
                 .batteryPowerSwitchModelPublication,
                 .batteryPowerSwitchTargetSubscription:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }
    
    private func operationType(for model: SyncCellModel) -> DeviceOperationType? {
        if let deviceModel = model as? SyncDevicesModel {
            return deviceModel.operationType
        }
        if let taskModel = model as? SyncDeviceStepTaskModel {
            return taskModel.operationType
        }
        return nil
    }
    
    private func containsBatteryPowerSwitchConfiguration(_ device: SyncDevicesModel) -> Bool {
        if let operationType = device.operationType {
            return isBatteryPowerSwitchConfigurationOperation(operationType)
        }
        return device.steps.contains { step in
            containsBatteryPowerSwitchConfiguration(step)
        }
    }
    
    private func containsBatteryPowerSwitchConfiguration(_ step: SyncDeviceStepModel) -> Bool {
        step.tasks.contains { task in
            isBatteryPowerSwitchConfigurationOperation(task.operationType)
        }
    }
    
    private func isBatteryPowerSwitchOwnConfiguration(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model) else {
            return false
        }
        return isBatteryPowerSwitchOwnConfigurationOperation(operationType)
    }

    private func isBatteryPowerSwitchKeyConfigConfiguration(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model) else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            if case .batteryPowerSwitchKeyConfig = actionType {
                return true
            }
            return false
        default:
            return false
        }
    }

    private func batteryPowerSwitchMessageHandles(for model: SyncCellModel, defaultHandles: [MeshMessageHandle]) -> [MeshMessageHandle] {
        guard let operationType = operationType(for: model) else {
            return defaultHandles
        }
        switch operationType {
        case .configuration(let node, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig(let switchData):
                guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
                      let vendorModel = node.sunricherVendorModel else {
                    return defaultHandles
                }
                let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
                return switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
                    let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)), model: vendorModel)
                    handle.continuous = false
                    return handle
                }
            case .batteryPowerSwitchModelPublication(let switchData):
                guard batteryPowerSwitchKeyConfigurationCompleted,
                      node.primaryUnicastAddress == switchData.proxyNodeAddress,
                      let switchGroup = switchData.linkGroup else {
                    return defaultHandles
                }
                let handles = node.getBatteryPowerSwitchPublicationMessageHandles(switchGroup: switchGroup, includeExisting: true)
                handles.forEach { $0.continuous = false }
                return handles
            default:
                return defaultHandles
            }
        default:
            return defaultHandles
        }
    }

    private func isMissingRequiredBatteryPowerSwitchConfigurationHandles(_ model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        guard messageHandles.isEmpty,
              let operationType = operationType(for: model) else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig:
                return true
            case .batteryPowerSwitchModelPublication:
                return batteryPowerSwitchKeyConfigurationCompleted
            default:
                return false
            }
        default:
            return false
        }
    }

    private func isBatteryPowerSwitchOperationSuccessful(
        model: SyncCellModel,
        resultSuccessful: Bool,
        operationSuccessful: Bool,
        messageHandles: [MeshMessageHandle]
    ) -> Bool {
        guard isBatteryPowerSwitchOwnConfiguration(model) else {
            return resultSuccessful && operationSuccessful
        }
        return !messageHandles.isEmpty && resultSuccessful
    }
    
    private func resetBatteryPowerSwitchConfigurationForResync() {
        batteryPowerSwitchOwnConfigurationFailed = false
        sections.forEach { section in
            section.devices.forEach { resetBatteryPowerSwitchConfigurationIfNeeded($0) }
            section.groups.forEach { group in
                group.deviceModels.forEach { resetBatteryPowerSwitchConfigurationIfNeeded($0) }
            }
        }
        tableView.reloadData()
    }
    
    private func resetBatteryPowerSwitchConfigurationIfNeeded(_ device: SyncDevicesModel) {
        guard containsBatteryPowerSwitchSync(device) else {
            return
        }
        device.isFineshed = false
        device.isSelected = false
        device.failedCount = 0
        if let operationType = device.operationType,
           isBatteryPowerSwitchSyncOperation(operationType) {
            device.state = .none
            return
        }
        device.steps.forEach { step in
            guard containsBatteryPowerSwitchSync(step) else {
                return
            }
            step.isFineshed = false
            step.tasks.forEach { task in
                guard isBatteryPowerSwitchSyncOperation(task.operationType) else {
                    return
                }
                task.isFineshed = false
                task.failedCount = 0
                task.state = .none
            }
        }
    }
    
    private func startBatteryPowerSwitchConfigurationResyncAfterActivation() {
        guard let switchData = batteryPowerSwitchDataForSync else {
            return
        }
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: switchData
        ) { [weak self] in
            guard let self else { return }
            self.batteryPowerSwitchActivationFlow = nil
            self.resetBatteryPowerSwitchConfigurationForResync()
            self.syncState = .inSync
            self.updateSyncStateUI()
            self.startSync()
        }
        batteryPowerSwitchActivationFlow = flow
        flow.start()
    }
    
    private func selectedFailedDevicesForResync() -> [SyncDevicesModel] {
        var selectedDevices: [SyncDevicesModel] = []
        sections.forEach { section in
            let models = section.allModels.filter {
                (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed
            } as! [SyncDevicesModel]
            selectedDevices.append(contentsOf: models)
        }
        return selectedDevices
    }

    private func containsBatteryPowerSwitchSync(_ device: SyncDevicesModel) -> Bool {
        if let operationType = device.operationType {
            return isBatteryPowerSwitchSyncOperation(operationType)
        }
        return device.steps.contains { step in
            containsBatteryPowerSwitchSync(step)
        }
    }

    private func containsBatteryPowerSwitchSync(_ step: SyncDeviceStepModel) -> Bool {
        step.tasks.contains { task in
            isBatteryPowerSwitchSyncOperation(task.operationType)
        }
    }
    
    private func markPendingBatteryPowerSwitchOwnConfigurationTasksFailed() {
        sections.forEach { section in
            section.devices.forEach { markPendingBatteryPowerSwitchOwnConfigurationTasksFailed(in: $0) }
            section.groups.forEach { group in
                group.deviceModels.forEach { markPendingBatteryPowerSwitchOwnConfigurationTasksFailed(in: $0) }
            }
        }
    }
    
    private func markPendingBatteryPowerSwitchOwnConfigurationTasksFailed(in device: SyncDevicesModel) {
        guard containsBatteryPowerSwitchConfiguration(device) else {
            return
        }
        if let operationType = device.operationType,
           isBatteryPowerSwitchOwnConfigurationOperation(operationType),
           device.state == .none || device.state == .wait {
            device.state = .failed
            device.failedCount += 1
            return
        }
        device.steps.forEach { step in
            step.tasks.forEach { task in
                guard isBatteryPowerSwitchOwnConfigurationOperation(task.operationType),
                      task.state == .none || task.state == .wait else {
                    return
                }
                task.state = .failed
                task.failedCount += 1
            }
        }
    }
    
    /// 设备重同步前，清理当前轮次残留状态（仅保留成功任务）
    private func prepareDeviceForResync(_ device: SyncDevicesModel) {
        device.isFineshed = false
        device.isSelected = false
        
        // 直接操作设备（无步骤）
        if device.steps.isEmpty {
            if device.state != .successful {
                device.state = .none
            }
            return
        }
        
        // 按步骤操作设备：将非成功任务统一重置为 none，避免 wait/failed 混用导致错误聚合
        device.steps.forEach { step in
            step.isFineshed = false
            step.tasks.forEach { task in
                task.isFineshed = false
                if task.state != .successful {
                    task.state = .none
                }
            }
        }
    }

    private func prepareStepForResync(_ step: SyncDeviceStepModel) {
        step.isFineshed = false
        step.parentDeviceModel?.isFineshed = false
        step.parentDeviceModel?.isSelected = false
        step.tasks.forEach { task in
            task.isFineshed = false
            if task.state != .successful {
                task.state = .none
                if task.relevanceTaskModels.count > 0 {
                    task.resyncRelevanceCheck().forEach({
                        $0.state = .wait
                    })
                }
            }
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
                    if step.relevanceStepModels.contains(where: { $0.state != .successful }) {
                        continue
                    }
                    if let model = step.tasks.first(where: { $0.state == .none || $0.state == .wait }) {
                        if model.relevanceTaskModels.contains(where: { $0.state == .failed }) {
                            continue
                        }
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
        
        progressLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 12)
        bottomView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.top.equalTo(SCRYFrom(25))
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
                // 检查是否有profile数据需要加锁、切换场景前置要求，需要则重试必须连带前置条件一起设置
                if task.relevanceTaskModels.count > 0 {
                    task.resyncRelevanceCheck().forEach({
                        $0.state = .wait
                    })
                }
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
        if containsBatteryPowerSwitchConfiguration(model) {
            startBatteryPowerSwitchConfigurationResyncAfterActivation()
            return
        }
        prepareDeviceForResync(model)
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
    
}

extension SyncDevicesViewController: SyncDeviceStepViewCellDelegate {
    
    /// 重新同步事件回调
    func cell(_ cell: SyncDeviceStepViewCell, resyncAction model: SyncDeviceStepModel) {
        if containsBatteryPowerSwitchConfiguration(model) {
            startBatteryPowerSwitchConfigurationResyncAfterActivation()
            return
        }
        prepareStepForResync(model)
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
        /// profile数据
        case profile(_ datas: [(node: Node, profiles: [ProfileType])])
        /// 场景
        case scene(_ scene: Scene)
        /// 日程
        case schedule(_ schdule: Schedule)
        /// 动能开关 deleteSwitch: 是否删除动能开关
        case enOceanSwitch(_ switchData: DeviceSwitchData, deleteSwitch: Bool = false)
        /// Battery Power Switch Profile 同步
        case batteryPowerSwitch(_ switchData: PJEightKeySwitchData)
        /// 按组设置pwm频率
//        case pwmPeriod(_ period: UInt16, group: Group)
        /// 同步设备list
        case devices(_ nodes: [Node])
        /// 同步设备参数
        case devicesParameter(_ datas: [(node: Node, parameters: [DeviceParameterType])])
        /// Dongle设备
        case dongle(_ dongleData: DeviceDongleData)
        /// 应急火警控制器
        case emergencyFire(data: DeviceEmerFireData, items: [EmergencyFireControllerSyncItem]?, persistsSyncResult: Bool, changedFromConfiguration: EmergencyFireControllerConfiguration?)
        /// 邻近照明路径
        case proximityLightingPath(group: Group, path: GroupProximityLightingPathData)
        /// space级触发区域
        case spaceTriggerZones(datas: [(node: Node, syncData: NodeSyncData)])
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

private extension Node {
    
    static var daylightRecallConditionIdKey: UInt8 = 0
    /// 光照传感器当前激活的条件id
    var daylightRecallConditionId: UInt8? {
        get {
            objc_getAssociatedObject(self, &Node.daylightRecallConditionIdKey) as? UInt8
        }set {
            objc_setAssociatedObject(self, &Node.daylightRecallConditionIdKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

extension Node {
    
    /// 发送配置完成闪烁消息
    func sendHandleCompleteIdentify(deviceBlinkMode: DeviceBlinkMode) {
         
        guard let vendorModel = sunricherVendorModel, capabilities.contains(.setupBehavior) else { return }
        
        switch deviceBlinkMode {
        case .none:
            break
        case .breathing:
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .breathe(count: 1, period: 1500))), model: vendorModel)
        case .fast:
            MeshAPI.sendMessage(message: SunricherVendorSet(function: .identify(mode: .flash(count: 1))), model: vendorModel)
        }
    }
}

extension SyncDeviceStepTaskModel {
    
    /// 检查对应task相关联的条件task，如需重试同步时需要把前置关联的task也一起同步
    /// - Parameter task: 重新同步的task数据
    /// - Returns: 返回需要一起同步的关联task数据
    func resyncRelevanceCheck() -> [SyncDeviceStepTaskModel] {
        
        var relevanceTaskModels: [SyncDeviceStepTaskModel] = []
        // 检查是否有profile数据需要加锁、切换场景前置要求，需要则重试必须连带前置条件一起设置
        if self.relevanceTaskModels.count > 0 {
            relevanceTaskModels = self.relevanceTaskModels.filter { task in
                if case .configuration(_, let actionType) = task.operationType, case .profile(let profileType) = actionType {
                    switch profileType {
                    case .profileToggleTriggerConditionLuxLock, .lightControlSwitch, .daylightSensorConditionRecall:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
        }
        return relevanceTaskModels
    }
    
}
