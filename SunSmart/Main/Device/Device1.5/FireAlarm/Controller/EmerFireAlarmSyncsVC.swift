//
//  EmerFireAlarmSyncsVC.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/23.
//
//只是一个测试样例，研究下同步场景而已
import UIKit
import NordicSigMeshSDK

/// 同步结果数据
struct EmerFireAlarmSyncResultData {
    let node: Node
    /// 成功的操作类型list
    var successOperationTypes: [DeviceOperationType]
    /// 失败的操作类型list
    var failedOperationTypes: [DeviceOperationType]
}

class EmerFireAlarmSyncsVC: UIViewController {
    
    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var progressLabel: UILabel!
    /// 返回按钮
    private lazy var backBtn: UIButton = {
        let btn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
        return btn
    }()
    
    private var sections: [EmerFireAlarmSyncSectionModel] = []
    
    let type: SyncType
    /// 上一个group model
    private var lastGroupModel: EmerFireAlarmSyncGroupModel?
    /// 上一个device model
    private var lastDeviceModel: EmerFireAlarmSyncDeviceModel?
    /// 同步状态
    private var syncState: SyncState = .inSync
    /// 是否展示详细进度的model
    private var showProressStepModel: EmerFireAlarmSyncStepModel?
    /// 同步完成回调
    var syncSuccessCallback: ((SyncType)->Void)?
    /// 点击返回回调（result: 每个设备成功、失败操作）
    var backActionCallback: ((_ result: [EmerFireAlarmSyncResultData])->Void)?
    /// 更新版本的设备地址
    private var updateVersionAddresses: [Address] = []
    /// lux触发锁定的设备list
    var luxTriggerLockDevices: [Node] = []
    /// FireAlarm sync flow keeps its own recall cache instead of relying on the old controller's fileprivate storage.
    private var daylightRecallConditionIDs: [Address: UInt8] = [:]
    /// 自动化恢复
    var automationRestore: Bool = false
    /// 重试次数
    private var retryCount: Int = 0
    /// 同步的设备list
    private var syncNodes: [Node] = []
    
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
      
            let removeSection = EmerFireAlarmSyncSectionModel(title: "remove".localizedString)
            let configurationSection = EmerFireAlarmSyncSectionModel(title: "configuration".localizedString)
            
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
            case .profile(let datas):
                datas.forEach { (node: Node, profiles: [ProfileType]) in
                    // 锁定配置切换操作
                    var luxTriggerLockStep: EmerFireAlarmSyncStepModel?
                    // 设置白天/晚上lux阈值操作
                    var luxThresholdStep: EmerFireAlarmSyncStepModel?
                    // 切换到对应profile操作
                    var switchProfileStep: EmerFireAlarmSyncStepModel?
                    // 保存到profile 场景
                    var lastProfileStoreStep: EmerFireAlarmSyncStepModel?
                    /// 同步profile场景的操作list
                    var syncProfileSceneSteps: [EmerFireAlarmSyncStepModel] = []
                    let syncProfileSteps = profiles.map({
                        
                        let task = EmerFireAlarmSyncStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .profile(type: $0)))
                        
                        let step = EmerFireAlarmSyncStepModel(type: $0.title, state: .none, tasks: [task])
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
                    
                    let deviceModel = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
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
                            let model = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                            model.imageName = node.iconName
                            // 场景绑定日程
                            if scene.info.bindSchedules.count > 0 {
                                
                                let addSceneTask = EmerFireAlarmSyncStepTaskModel(name: scene.name, operationType: .configuration(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData)))
                                let addSceneStep = EmerFireAlarmSyncStepModel(type: "scene".localizedString, state: .none, tasks: [addSceneTask])
                                addSceneStep.parentDeviceModel = model
                                addSceneStep.showProgress = false
                                addSceneTask.parentStepModel = addSceneStep
                                
                                let addScheduleTasks = scene.info.bindSchedules.map({ schedule in
                                     EmerFireAlarmSyncStepTaskModel(name: schedule.name, operationType: .configuration(node: node, type: .schedule(schedule: schedule)))
                                })
                                let addScheduleStep = EmerFireAlarmSyncStepModel(type: "schedule".localizedString, state: .none, tasks: addScheduleTasks)
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
                            let groupModel = EmerFireAlarmSyncGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: syncSceneDeviceModels)
                            configurationSection.groups.append(groupModel)
                            
                            syncSceneDeviceModels.forEach({
                                $0.parentGroupModel = groupModel
                            })
                        }
                        
                        // 需要删除的设备
                        let deleteNodes = resut.deleteNodes
                        let deleteSceneDeviceModels = deleteNodes.map({ node in
                            let model = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                            model.imageName = node.iconName
                            if scene.info.bindSchedules.count > 0 {
                                
                                let deleteScheduleTasks = scene.info.bindSchedules.map({ schedule in
                                     EmerFireAlarmSyncStepTaskModel(name: schedule.name, operationType: .delete(node: node, type: .schedule(schedule: schedule)))
                                })
                                let deleteScheduleStep = EmerFireAlarmSyncStepModel(type: "schedule".localizedString, state: .none, tasks: deleteScheduleTasks)
                                deleteScheduleStep.parentDeviceModel = model
                                deleteScheduleStep.showProgress = false
                                deleteScheduleTasks.forEach({ $0.parentStepModel = deleteScheduleStep })
                                
                                
                                let deleteSceneTask = EmerFireAlarmSyncStepTaskModel(name: scene.name, operationType: .delete(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData)))
                                let deleteSceneStep = EmerFireAlarmSyncStepModel(type: "scene".localizedString, state: .none, tasks: [deleteSceneTask])
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
                            let groupModel = EmerFireAlarmSyncGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deleteSceneDeviceModels)
                            removeSection.groups.append(groupModel)
                            
                            deleteSceneDeviceModels.forEach({
                                $0.parentGroupModel = groupModel
                            })
                        }
                    }
                }
                
            case .schedule(let schedule):
                populateScheduleSections(schedule: schedule, removeSection: removeSection, configurationSection: configurationSection)
                
            case .enOceanSwitch(let switchData, let deleteSwitch):
                populateEnOceanSwitchSections(
                    switchData: switchData,
                    deleteSwitch: deleteSwitch,
                    removeSection: removeSection,
                    configurationSection: configurationSection
                )
                
//            case .pwmPeriod(let period, let group):
//                
//                let nodes = group.nodes.filter({ $0.pwmFrequency != period })
//                let deviceModels = nodes.map({
//                    let model = EmerFireAlarmSyncDeviceModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
//                    model.imageName = $0.iconName
//                    model.operationType = .configuration(node: $0, type: .deviceParameters(parameterType: .pwmPeriod(period: period)))
//                    return model
//                })
//                let groupModel = EmerFireAlarmSyncGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
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
                        var steps: [EmerFireAlarmSyncStepModel] = []
                        parameters.forEach { type in
                            switch type {
                            case .pwmFrequency(let frequency):
                                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "pwm_frequency".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .pwmFrequency(frequency: frequency))))
                                
                                let step = EmerFireAlarmSyncStepModel(type: "pwm_frequency".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .ratedPower(let value):
                                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "rated_power".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .ratedPower(datas: value))))
                                
                                let step = EmerFireAlarmSyncStepModel(type: "rated_power".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .motionSensitivityRange(range: let range):
                                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "relative_sensitivity".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .motionSensitivityRange(range: range))))
                                
                                let step = EmerFireAlarmSyncStepModel(type: "relative_sensitivity".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .defaultTransitionTime(let transitionTime):
                                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "transition_time".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .defaultTransitionTime(transitionTime: transitionTime))))
                                
                                let step = EmerFireAlarmSyncStepModel(type: "transition_time".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            case .powerCalibration(let calibrationValue):
                                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "power_calibrate".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .powerCalibration(calibrationValue: calibrationValue))))
                                
                                let step = EmerFireAlarmSyncStepModel(type: "power_calibrate".localizedString, state: .none, tasks: [taskModel])
                                taskModel.parentStepModel = step
                                steps.append(step)
                            }
                        }
                        
                        let deviceModel = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
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
                    let syncDeviceModel = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    syncDeviceModel.imageName = node.iconName
                    
                    let deleteDeviceModel = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
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
                                    EmerFireAlarmSyncStepTaskModel(name: "collection_schedule".localizedString + " \(scheduleData.0)", operationType: .configuration(node: node, type: .collectionSchedule(index: scheduleData.0, entry: scheduleData.1)))
                                })
                                
                                let stepModel = EmerFireAlarmSyncStepModel(type: "collection_schedule".localizedString, state: .none, tasks: tasks)
                                tasks.forEach({ $0.parentStepModel = stepModel })
                                stepModel.parentDeviceModel = syncDeviceModel
                                syncDeviceModel.steps.append(stepModel)
                                
                            case .deleteCollectionSchedules(let scheduleIds):
                                
                                let tasks = scheduleIds.map({ scheduleId in
                                    EmerFireAlarmSyncStepTaskModel(name: "collection_schedule".localizedString + " \(scheduleId)", operationType: .configuration(node: node, type: .collectionSchedule(index: scheduleId, entry: SchedulerRegistryEntry())))
                                })
                                let stepModel = EmerFireAlarmSyncStepModel(type: "collection_schedule".localizedString, state: .none, tasks: tasks)
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
                        let syncDeviceModel = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                        syncDeviceModel.imageName = node.iconName
                        
                        switch syncData {
                        case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                            
                            let taskModel = EmerFireAlarmSyncStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))
                            
                            let step = EmerFireAlarmSyncStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                            taskModel.parentStepModel = step
                            
                            step.parentDeviceModel = syncDeviceModel
                            syncDeviceModel.steps.append(step)
                        case .proximityLightingRelayNumber(let relayNumber):
                            let taskModel = EmerFireAlarmSyncStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
                            
                            let step = EmerFireAlarmSyncStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                            taskModel.parentStepModel = step
                            
                            step.parentDeviceModel = syncDeviceModel
                            syncDeviceModel.steps.append(step)
                            
                        case .proximityLightingEnabled(let enabled):
                            let name = enabled ? "proximity_lighting_enabled".localizedString : "proximity_lighting_disable".localizedString
                            let taskModel = EmerFireAlarmSyncStepTaskModel(name: name, operationType: .configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
                            
                            let step = EmerFireAlarmSyncStepModel(type: name, state: .none, tasks: [taskModel])
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
                    let syncDeviceModel = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                    syncDeviceModel.imageName = node.iconName
                    
                    switch syncData {
                    case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "trigger_zone".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))
                        let step = EmerFireAlarmSyncStepModel(type: "trigger_zone".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        step.parentDeviceModel = syncDeviceModel
                        syncDeviceModel.steps.append(step)
                    case .proximityLightingRelayNumber(let relayNumber):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "trigger_zone".localizedString, operationType: .configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
                        let step = EmerFireAlarmSyncStepModel(type: "trigger_zone".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        step.parentDeviceModel = syncDeviceModel
                        syncDeviceModel.steps.append(step)
                    case .proximityLightingEnabled(let enabled):
                        let name = enabled ? "proximity_lighting_enabled".localizedString : "proximity_lighting_disable".localizedString
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: name, operationType: .configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
                        let step = EmerFireAlarmSyncStepModel(type: name, state: .none, tasks: [taskModel])
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
        
            appendSectionIfNeeded(removeSection)
            appendSectionIfNeeded(configurationSection)
            updateSectionIndexesAndFailureStateIfNeeded()
    }

    private func appendSectionIfNeeded(_ section: EmerFireAlarmSyncSectionModel) {
        if section.groups.count > 0 || section.devices.count > 0 || section.switchProxy != nil {
            sections.append(section)
        }
    }

    private func updateSectionIndexesAndFailureStateIfNeeded() {
        for (index, section) in sections.enumerated() {
            section.groups.forEach {
                $0.parentSectionIndex = index
            }
            section.devices.forEach {
                $0.parentSectionIndex = index
            }
            guard syncState == .syncFailure else { continue }
            section.allModels.forEach {
                $0.isFineshed = true
                $0.state = .failed
            }
        }
    }

    private func populateScheduleSections(
        schedule: Schedule,
        removeSection: EmerFireAlarmSyncSectionModel,
        configurationSection: EmerFireAlarmSyncSectionModel
    ) {
        let data = schedule.getNeedSyncDatas()
        removeSection.devices.append(contentsOf: data.deleteNodes.map {
            makeDeviceModel(node: $0, operationType: .delete(node: $0, type: .schedule(schedule: schedule)))
        })
        configurationSection.devices.append(contentsOf: data.syncNodes.map {
            makeDeviceModel(node: $0, operationType: .configuration(node: $0, type: .schedule(schedule: schedule)))
        })
        removeSection.groups.append(contentsOf: makeSortedGroupModels(from: data.deleteGroups) {
            .delete(node: $0, type: .schedule(schedule: schedule))
        })
        configurationSection.groups.append(contentsOf: makeSortedGroupModels(from: data.syncGroups) {
            .configuration(node: $0, type: .schedule(schedule: schedule))
        })
    }

    private func populateEnOceanSwitchSections(
        switchData: DeviceSwitchData,
        deleteSwitch: Bool,
        removeSection: EmerFireAlarmSyncSectionModel,
        configurationSection: EmerFireAlarmSyncSectionModel
    ) {
        guard switchData.linkGroup != nil else { return }
        let data = switchData.getNeedSyncDatas(deleteSwitch: deleteSwitch)
        if let proxyNode = data.deleteProxy {
            removeSection.switchProxy = makeSwitchProxyModel(
                node: proxyNode,
                operationType: .delete(node: proxyNode, type: .enOceanProxy(switchData: switchData))
            )
        }
        if let syncNode = data.syncProxy {
            configurationSection.switchProxy = makeSwitchProxyModel(
                node: syncNode,
                operationType: .configuration(node: syncNode, type: .enOceanProxy(switchData: switchData))
            )
        }
        removeSection.groups.append(contentsOf: makeSortedGroupModels(from: data.deleteGroups) {
            .delete(node: $0, type: .enOceanSwitch(switchData: switchData))
        })
        configurationSection.groups.append(contentsOf: makeSortedGroupModels(from: data.syncGroups) {
            .configuration(node: $0, type: .enOceanSwitch(switchData: switchData))
        })
    }

    private func makeDeviceModel(node: Node, operationType: DeviceOperationType) -> EmerFireAlarmSyncDeviceModel {
        let model = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
        model.imageName = node.iconName
        model.operationType = operationType
        return model
    }

    private func makeSwitchProxyModel(node: Node, operationType: DeviceOperationType) -> EmerFireAlarmSyncSwitchProxyModel {
        let deviceModel = makeDeviceModel(node: node, operationType: operationType)
        return EmerFireAlarmSyncSwitchProxyModel(name: "enocean_proxy".localizedString, deviceModel: deviceModel)
    }

    private func makeSortedGroupModels(
        from groups: [Group: [Node]],
        operationTypeBuilder: (Node) -> DeviceOperationType
    ) -> [EmerFireAlarmSyncGroupModel] {
        groups
            .map { group, nodes in
                let deviceModels = nodes.map { makeDeviceModel(node: $0, operationType: operationTypeBuilder($0)) }
                let groupModel = EmerFireAlarmSyncGroupModel(
                    groupName: group.name,
                    groupAddress: group.address.address,
                    deviceModels: deviceModels
                )
                deviceModels.forEach { $0.parentGroupModel = groupModel }
                return groupModel
            }
            .sorted { $0.address < $1.address }
    }
    
    /// 获取组对应设备同步数据model
    /// - Parameters:
    ///   - group: 组
    ///   - node: 设备
    ///   - exitGroup: 是否退组
    /// - Returns: 需要配置的model，需要删除的model
    private func getSyncDeviceModel(group: Group?, node: Node) -> (configturationDevice: EmerFireAlarmSyncDeviceModel?, removeDevice: EmerFireAlarmSyncDeviceModel?) {
        
        /// 删除操作
        var deleteSteps: [EmerFireAlarmSyncStepModel] = []
        // 同步操作
        var configturationSteps: [EmerFireAlarmSyncStepModel] = []
        
        // 添加组流程
        var addGroupStep: EmerFireAlarmSyncStepModel?
        /// 删除组流程
        var removeGroupStep: EmerFireAlarmSyncStepModel?
        /// 初始化设备流程
        var initializeStepModel: EmerFireAlarmSyncStepModel?
        
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
                let addGroupTask = EmerFireAlarmSyncStepTaskModel(name: "add_to_group".localizedString, operationType: .configuration(node: node, type  : .group(group: group)))
                let step = EmerFireAlarmSyncStepModel(type: "add_to_group".localizedString, state: .none, tasks: [addGroupTask])
                addGroupTask.parentStepModel = step
                configturationSteps.append(step)
                
                addGroupStep = step
             
            case .unsubscribeGroup(let group):
                let removeGroupTask = EmerFireAlarmSyncStepTaskModel(name: "remove_from_group".localizedString, operationType: .delete(node: node, type: .group(group: group)))
                let step = EmerFireAlarmSyncStepModel(type: "remove_from_group".localizedString, state: .none, tasks: [removeGroupTask])
                removeGroupTask.parentStepModel = step
                // 需要依赖之前操作完成才能退出组
//                step.relevanceStepModels = deleteSteps
                deleteSteps.append(step)
                removeGroupStep = step
                
            case .profile(let types):
                // 锁定配置切换操作
                var luxTriggerLockTask: EmerFireAlarmSyncStepTaskModel?
                /// 白天/晚上lux阈值操作
                var luxThresholdTask: EmerFireAlarmSyncStepTaskModel?
                // 切换到对应profile操作
                var switchProfileTask: EmerFireAlarmSyncStepTaskModel?
                // 保存到profile 场景
                var lastProfileStoreTask: EmerFireAlarmSyncStepTaskModel?
                /// 同步profile场景的操作任务list
                var syncProfileSceneTasks: [EmerFireAlarmSyncStepTaskModel] = []
                let syncProfileTasks = types.map({
                    let task = EmerFireAlarmSyncStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .profile(type: $0)))
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
                    
                    let step = EmerFireAlarmSyncStepModel(type: "profile".localizedString, state: .none, tasks: syncProfileTasks)
                    syncProfileTasks.forEach({ $0.parentStepModel = step })
                    if node.groupState == .exitFailure || removeGroupStep != nil {
                        deleteSteps.append(step)
                    }else {
                        configturationSteps.append(step)
                    }
                }
            case .pirEnabled(let enabled):
                let name = enabled ? "pir_enabled".localizedString : "pir_disable".localizedString
                let task = EmerFireAlarmSyncStepTaskModel(name: name, operationType: .configuration(node: node, type: .pirEnabled(enabled)))
                
                let step = EmerFireAlarmSyncStepModel(type: name, state: .none, tasks: [task])
                task.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
                
            case .syncScenes(let datas):
                
                let syncSceneTasks = datas.map({ (scene, sceneData) in
                    return EmerFireAlarmSyncStepTaskModel(name: scene.name, operationType: .configuration(node: node, type: .scene(sceneId: scene.number, executeData: sceneData)))
                })
                if syncSceneTasks.count > 0 {
                    let step = EmerFireAlarmSyncStepModel(type: "scene".localizedString, state: .none, tasks: syncSceneTasks)
                    syncSceneTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
                }
                
            case .deleteScenes(let scenes):
                
                let deleteSceneTasks = scenes.map({
                    return EmerFireAlarmSyncStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .scene(sceneId: $0.number, executeData: nil)))
                })
                if deleteSceneTasks.count > 0 {
                    let step = EmerFireAlarmSyncStepModel(type: "remove_scene".localizedString, state: .none, tasks: deleteSceneTasks)
                    deleteSceneTasks.forEach({ $0.parentStepModel = step })
                    deleteSteps.append(step)
                }
            case .syncSchedules(let schedules):
                
                let syncScheduleTasks = schedules.map({
                    return EmerFireAlarmSyncStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .schedule(schedule: $0)))
                })
                if syncScheduleTasks.count > 0 {
                    let step = EmerFireAlarmSyncStepModel(type: "schedule".localizedString, state: .none, tasks: syncScheduleTasks)
                    syncScheduleTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
                }
                
            case .deleteSchedules(let schedules):
                let deleteScheduleTasks = schedules.map({
                    return EmerFireAlarmSyncStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .schedule(schedule: $0)))
                })
                if deleteScheduleTasks.count > 0 {
                    let step = EmerFireAlarmSyncStepModel(type: "remove_schedule".localizedString, state: .none, tasks: deleteScheduleTasks)
                    deleteScheduleTasks.forEach({ $0.parentStepModel = step })
                    deleteSteps.append(step)
                }
                
            case .syncSwitchProxy(let switchData):
                
                let syncSwitchProxyTask = EmerFireAlarmSyncStepTaskModel(name: switchData.name, operationType: .configuration(node: node, type: .enOceanProxy(switchData: switchData)))
                let step = EmerFireAlarmSyncStepModel(type: "enocean_proxy".localizedString, state: .none, tasks: [syncSwitchProxyTask])
                syncSwitchProxyTask.parentStepModel = step
                configturationSteps.append(step)
                
            case .deleteSwitchProxy(let switchData):
                
                let deleteSwitchProxyTask = EmerFireAlarmSyncStepTaskModel(name: switchData.name, operationType: .delete(node: node, type: .enOceanProxy(switchData: switchData)))
                
                let step = EmerFireAlarmSyncStepModel(type: "remove_switch_proxy".localizedString, state: .none, tasks: [deleteSwitchProxyTask])
                deleteSwitchProxyTask.parentStepModel = step
                deleteSteps.append(step)
                
            case .syncSwitchs(let switchDatas):
                
                let syncSwitchTasks = switchDatas.map({
                    return EmerFireAlarmSyncStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if syncSwitchTasks.count > 0 {
                    let step = EmerFireAlarmSyncStepModel(type: "switch".localizedString, state: .none, tasks: syncSwitchTasks)
                    syncSwitchTasks.forEach({ $0.parentStepModel = step })
                    configturationSteps.append(step)
                }
                
            case .deleteSwitchs(let switchDatas):
                
                let deleteSwitchTasks = switchDatas.map({
                    return EmerFireAlarmSyncStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .enOceanSwitch(switchData: $0)))
                })
                if deleteSwitchTasks.count > 0 {
                    let step = EmerFireAlarmSyncStepModel(type: "remove_switch".localizedString, state: .none, tasks: deleteSwitchTasks)
                    deleteSwitchTasks.forEach({ $0.parentStepModel = step })
                    deleteSteps.append(step)
                }
                
            case .deviceInitialize:
                let initializeTaskModel = EmerFireAlarmSyncStepTaskModel(name: "initialize".localizedString, operationType: .configuration(node: node, type: .deviceInitialize))
                initializeStepModel = EmerFireAlarmSyncStepModel(type: "initialize".localizedString, state: .none, tasks: [initializeTaskModel])
                initializeTaskModel.parentStepModel = initializeStepModel!
                configturationSteps.append(initializeStepModel!)
            case .deviceParameterTypes(let types):
                
                var tasks: [EmerFireAlarmSyncStepTaskModel] = []
                types.forEach { type in
                    switch type {
                    case .pwmFrequency(let frequency):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "pwm_frequency".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .pwmFrequency(frequency: frequency))))
                        tasks.append(taskModel)
                    case .ratedPower(let value):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "rated_power".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .ratedPower(datas: value))))
                        tasks.append(taskModel)
                    case .motionSensitivityRange(range: let range):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "relative_sensitivity".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .motionSensitivityRange(range: range))))
                        tasks.append(taskModel)
                    case .defaultTransitionTime(let transitionTime):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "transition_time".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .defaultTransitionTime(transitionTime: transitionTime))))
                        tasks.append(taskModel)
                    case .powerCalibration(let calibrationValue):
                        let taskModel = EmerFireAlarmSyncStepTaskModel(name: "power_calibrate".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .powerCalibration(calibrationValue: calibrationValue))))
                        tasks.append(taskModel)
                    }
                }
                let deviceParametersStepModel = EmerFireAlarmSyncStepModel(type: "device_parameters".localizedString, state: .none, tasks: tasks)
                tasks.forEach({
                    $0.parentStepModel = deviceParametersStepModel
                })
                configturationSteps.append(deviceParametersStepModel)
            case .proximityLightingEnabled(let enabled):
                
                let name = enabled ? "proximity_lighting_enabled".localizedString : "proximity_lighting_disable".localizedString
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: name, operationType: .configuration(node: node, type: .proximityLightingEnabled(enabled: enabled)))
                
                let step = EmerFireAlarmSyncStepModel(type: name, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
            case .proximityLightingRelayNumber(let relayNumber):
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingRelayNumber(relayNumber: relayNumber)))
                
                let step = EmerFireAlarmSyncStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
                
            case .proximityLightingNeighbor(let relayNumber, let neighborAddresses):
                
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "path_sequence".localizedString, operationType: .configuration(node: node, type: .proximityLightingNeighbor(relayNumber: relayNumber, neighborAddresses: neighborAddresses)))
                
                let step = EmerFireAlarmSyncStepModel(type: "path_sequence".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                if node.groupState == .exitFailure || removeGroupStep != nil {
                    deleteSteps.append(step)
                }else {
                    configturationSteps.append(step)
                }
            case .syncGatewayProjectId(let projectId):
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "association_project".localizedString, operationType: .configuration(node: node, type: .gatewayAssociationProjectId(projectId: projectId)))
                
                let step = EmerFireAlarmSyncStepModel(type: "association_project".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
            case .gatewayAssociatedSpaces(let networkDatas, let activate):
                var taskModels: [EmerFireAlarmSyncStepTaskModel] = []
                networkDatas.forEach { (networkKey: NetworkKey, applicationKey: ApplicationKey) in
                    let space = SpaceData.load(subNetworkId: networkKey.networkId.hex)
                    let name = space?.name ?? "space".localizedString
                    let taskModel = EmerFireAlarmSyncStepTaskModel(name: name, operationType: .configuration(node: node, type: .gatewayAssociatedSpace(networkKey: networkKey, applicationKey: applicationKey, activate: activate)))
                    taskModels.append(taskModel)
                }
                
                let step = EmerFireAlarmSyncStepModel(type: "associated_spaces".localizedString, state: .none, tasks: taskModels)
                taskModels.forEach({ $0.parentStepModel = step })
                configturationSteps.append(step)
            case .gatewayUnbindAssociatedSpaces(let networkDatas, let activate):
                var taskModels: [EmerFireAlarmSyncStepTaskModel] = []
                networkDatas.forEach { (networkKey: NetworkKey, applicationKey: ApplicationKey) in
                    let space = SpaceData.load(subNetworkId: networkKey.networkId.hex)
                    let name = space?.name ?? "space".localizedString
                    let taskModel = EmerFireAlarmSyncStepTaskModel(name: name, operationType: .delete(node: node, type: .gatewayUnbindAssociatedSpace(networkKey: networkKey, applicationKey: applicationKey, activate: activate)))
                    taskModels.append(taskModel)
                }
                
                let step = EmerFireAlarmSyncStepModel(type: "unbind_associated_spaces".localizedString, state: .none, tasks: taskModels)
                taskModels.forEach({ $0.parentStepModel = step })
                deleteSteps.append(step)
                
            case .syncGatewaySubnetAppkeyIndexs(let appkeyIndexs):
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "gateway_sync_spaces".localizedString, operationType: .configuration(node: node, type: .gatewaySubnetAppkeyIndexs(appkeyIndexs: appkeyIndexs)))
                
                let step = EmerFireAlarmSyncStepModel(type: "gateway_sync_spaces".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
                
            case .syncGatewaySIMAPN(let apn):
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "apn".localizedString, operationType: .configuration(node: node, type: .gatewaySIMAPN(apn: apn)))
                
                let step = EmerFireAlarmSyncStepModel(type: "apn".localizedString, state: .none, tasks: [taskModel])
                taskModel.parentStepModel = step
                configturationSteps.append(step)
            case .syncGatewayMQTTInformation(let mqttInformation):
                let taskModel = EmerFireAlarmSyncStepTaskModel(name: "server_information".localizedString, operationType: .configuration(node: node, type: .gatewayMQTTInformation(mqttInformation: mqttInformation)))
                
                let step = EmerFireAlarmSyncStepModel(type: "server_information".localizedString, state: .none, tasks: [taskModel])
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

        var configturationDevice: EmerFireAlarmSyncDeviceModel?
        var removeDevice: EmerFireAlarmSyncDeviceModel?
        if configturationSteps.count > 0 {
            configturationDevice = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            configturationDevice?.imageName = node.iconName
            configturationDevice?.steps = configturationSteps
            configturationSteps.forEach({ $0.parentDeviceModel = configturationDevice })
        }
        
        if deleteSteps.count > 0 {
            removeDevice = EmerFireAlarmSyncDeviceModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            removeDevice?.imageName = node.iconName
            removeDevice?.steps = deleteSteps
            deleteSteps.forEach({ $0.parentDeviceModel = removeDevice })
        }
        
        return (configturationDevice, removeDevice)
    }
    
    /// 返回
    @objc private func backAction() {
        
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
            var resultDatas: [EmerFireAlarmSyncResultData] = []
            var deviceModels: [EmerFireAlarmSyncDeviceModel] = []
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
                            let data = EmerFireAlarmSyncResultData(node: node, successOperationTypes: successOperationTypes, failedOperationTypes: failedOperationTypes)
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
//            if let stepModel = $0 as? EmerFireAlarmSyncStepModel {
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
                        ($0 as? EmerFireAlarmSyncDeviceModel)?.failedCount += 1
                        ($0 as? EmerFireAlarmSyncStepTaskModel)?.failedCount += 1
                    }
                })
            })
            tableView.reloadData()
            syncState = .syncFailure
        }else if syncState == .syncFailure {
            
//            let failedModels = sections.filter({ $0.allModels.contains(where: { $0 is EmerFireAlarmSyncDeviceModel && ($0.state == .failed || $0.state == .repeatedFailure) }) })
            
            var selectModels: [EmerFireAlarmSyncDeviceModel] = []
            
            sections.forEach({
                let models = $0.allModels.filter({ (($0 as? EmerFireAlarmSyncDeviceModel)?.isSelected ?? false) && $0.state == .failed }) as! [EmerFireAlarmSyncDeviceModel]
                 selectModels.append(contentsOf: models)
            })
            if selectModels.count > 0 {
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
//            navigationItem.rightBarButtonItem = "stop".localizedString
        }
        updateSyncStateUI()
        
//        startSync()
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
//        var failedModels: [EmerFireAlarmSyncDeviceModel] = []
        sections.forEach({
            let models = $0.allModels.filter({ ($0 is EmerFireAlarmSyncDeviceModel || $0 is EmerFireAlarmSyncGroupModel) && $0.state == .failed })
//            failedModels.append(contentsOf: models)
            models.forEach({
                ($0 as? EmerFireAlarmSyncDeviceModel)?.isSelected = sender.isSelected
                ($0 as? EmerFireAlarmSyncGroupModel)?.isSelected = sender.isSelected
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
            var failedModels: [EmerFireAlarmSyncDeviceModel] = []
            
            var selectModels: [EmerFireAlarmSyncDeviceModel] = []
            
             sections.forEach({
                 
                 let failedDevices = $0.allModels.filter({ $0 is EmerFireAlarmSyncDeviceModel && $0.state == .failed  }) as! [EmerFireAlarmSyncDeviceModel]
                 failedModels.append(contentsOf: failedDevices)
                 
                 let selectDevices = $0.allModels.filter({ (($0 as? EmerFireAlarmSyncDeviceModel)?.isSelected ?? false) && $0.state == .failed }) as! [EmerFireAlarmSyncDeviceModel]
                 
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
    
    /// 同步主循环。
    /// 这里只保留流程编排，不直接处理协议细节：
    /// 1. 同步状态机推进到 wait / inSettings / success / failed
    /// 2. 为当前模型准备消息
    /// 3. 发送消息并等待当前批次完成
    /// 4. 刷新进度弹窗和列表进度
    /// 具体的消息发送、节点数据更新、失败处理都下沉到 helper，避免主流程失控。
    private func startSync() {
        prepareModelsForSync()
        tableView.reloadData()
        
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            
            while let model = self.getNextHandleModel() {
                
                guard MeshLibManager.manager.isOpenBluetooth else {
                    self.handleBluetoothUnavailable()
                    return
                }
                let messageHandles = self.prepareMessageHandles(for: model)
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                self.executeSyncModel(model, messageHandles: messageHandles, semaphore: semaphore)
                semaphore.wait()
                self.refreshProgressUI()
                continue
                #if false
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 15, progressBack: nil, successfulBack: { handle, statusMessage in
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
                                self.daylightRecallConditionIDs[node.primaryUnicastAddress] = UInt8(index)
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
                    let operationSuccessful = ((model as? EmerFireAlarmSyncDeviceModel)?.operationType?.isSuccessful ?? (model as? EmerFireAlarmSyncStepTaskModel)?.operationType.isSuccessful) ?? false
                    if resultSuccessful && operationSuccessful {
                        model.state = .successful
                        
                        if self.deviceBlinkMode != .none {
                            let deviceModel: EmerFireAlarmSyncDeviceModel? =
                            (model as? EmerFireAlarmSyncDeviceModel)
                            ?? (model as? EmerFireAlarmSyncStepTaskModel)?.parentStepModel?.parentDeviceModel
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
                        (model as? EmerFireAlarmSyncDeviceModel)?.failedCount += 1
                        (model as? EmerFireAlarmSyncStepTaskModel)?.failedCount += 1
                    }
                    self.updateCell(model: model)
                    semaphore.signal()
                }
                semaphore.wait()
                
                DispatchQueue.main.async {
                    if let model = self.showProressStepModel {
                        if let progressView = EmerFireAlarmSyncProgressView.current() {
                            progressView.stepModel = model
                        }
                    }
                    let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
                    self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
                }
                #endif
            }
//            _ = MeshNetworkManager.instance.save()
            print("完成")
            
            self.completeSync()
            
            // 操作成功的设备地址
//            var successAddresses: [Address] = []
//            self.sections.forEach({
//                let successfulModels = $0.allModels.filter({ $0.state == .successful })
//                successfulModels.forEach({
//                    if let model = $0 as? EmerFireAlarmSyncDeviceModel {
//                        if !successAddresses.contains(model.address) {
//                            successAddresses.append(model.address)
//                        }
//                    }else if let model = $0 as? EmerFireAlarmSyncStepTaskModel, let deviceModel = model.parentStepModel?.parentDeviceModel {
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

    // MARK: - Sync State Machine

    /// 开始同步前重置一轮 UI/状态机状态。
    /// 这里只处理展示模型，不碰 mesh 数据，也不做协议发送。
    private func prepareModelsForSync() {
        sections.forEach { section in
            section.allModels.forEach {
                if $0.state == .none {
                    $0.state = .wait
                }
                $0.isFineshed = false
                ($0 as? EmerFireAlarmSyncGroupModel)?.isSelected = false
                ($0 as? EmerFireAlarmSyncDeviceModel)?.isSelected = false
            }
        }
    }

    /// 蓝牙不可用时，直接将本轮未完成模型落为失败。
    /// 这是同步状态机的中断出口，不负责重试。
    private func handleBluetoothUnavailable() {
        sections.forEach { section in
            section.allModels.forEach {
                $0.state = .failed
                $0.isFineshed = true
            }
        }
        syncState = .syncFailure

        DispatchQueue.main.async {
            self.updateSyncStateUI()
            self.tableView.reloadData()
        }
    }

    /// 同步循环结束后的统一收尾。
    /// 这里负责：
    /// - 汇总同步状态机结果
    /// - 刷新列表与通知
    /// - 驱动自动重试
    /// - 控制进度弹窗最终状态
    private func completeSync() {
        sections.forEach { section in
            section.allModels.forEach {
                $0.isFineshed = true
            }
        }
        syncState = sections.contains(where: { $0.allModels.contains(where: { $0.state == .failed }) }) ? .syncFailure : .syncSuccess

        DispatchQueue.main.async {
            self.tableView.reloadData()
            self.updateSyncStateUI()
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)

            if self.syncState == .syncSuccess {
                self.syncSuccessCallback?(self.type)
                EmerFireAlarmSyncProgressView.current()?.hide()
                return
            }

            EmerFireAlarmSyncProgressView.current()?.reload()
            guard self.automationRestore else { return }

            if self.retryCount <= 0 {
                self.navigationController?.hideAutomaticHud()
                self.navigationController?.popToViewController(vcClass: BleFirmwareUpdateViewController.classForCoder())
            } else {
                self.retryCount -= 1
                self.selectAllBtnAction(sender: self.selectAllBtn)
                self.rightItemAction()
            }
        }
    }

    // MARK: - Message Preparation & Sending

    /// 将当前待执行的展示模型转换为 mesh 消息。
    /// 同时推进当前模型 UI 状态，并展开对应 group/device，保证列表能跟上执行进度。
    private func prepareMessageHandles(for model: EmerFireAlarmSyncCellModel) -> [MeshMessageHandle] {
        if let deviceModel = model as? EmerFireAlarmSyncDeviceModel {
            deviceModel.state = .inSettings
            updateExpandedGroupIfNeeded(for: deviceModel.parentGroupModel)
            return deviceModel.operationType?.messageHandles ?? []
        }

        guard let taskModel = model as? EmerFireAlarmSyncStepTaskModel else {
            return []
        }

        var messageHandles = taskModel.operationType.messageHandles
        appendDaylightRecallMessagesIfNeeded(to: &messageHandles, taskModel: taskModel)
        taskModel.state = .inSettings

        if showProressStepModel == taskModel.parentStepModel {
            DispatchQueue.main.async {
                EmerFireAlarmSyncProgressView.current()?.stepModel = taskModel.parentStepModel
            }
        }

        if let deviceModel = taskModel.parentStepModel?.parentDeviceModel {
            updateExpandedGroupIfNeeded(for: deviceModel.parentGroupModel)
            updateExpandedDeviceIfNeeded(deviceModel)
        }

        return messageHandles
    }

    /// daylight recall 相关配置有额外前置协议，单独在这里补消息。
    /// 这是纯协议拼装层，不更新 UI，不修改列表状态。
    private func appendDaylightRecallMessagesIfNeeded(to messageHandles: inout [MeshMessageHandle], taskModel: EmerFireAlarmSyncStepTaskModel) {
        guard case .configuration(let node, let type) = taskModel.operationType,
              node.capabilities.contains(.lightSensorConditionRecall),
              case .profile(let profileType) = type,
              let vendorModel = node.sunricherVendorModel else {
            return
        }

        switch profileType {
        case .profileToggleTriggerConditionLuxLock:
            daylightRecallConditionIDs[node.primaryUnicastAddress] = nil
            messageHandles.insert(MeshMessageHandle(message: SunricherVendorGet(function: .daylightConditionRecallGet), model: vendorModel), at: 0)
        case .profileToggleTriggerConditionLuxUnLock:
            if let index = daylightRecallConditionIDs[node.primaryUnicastAddress] {
                messageHandles.insert(MeshMessageHandle(message: SunricherVendorSet(function: .daylightConditionRecall(index: index)), model: vendorModel), at: 0)
            }
        default:
            break
        }
    }

    /// 将当前正在执行的 group 展开，其他 group 收起。
    /// 这是表格展示模型逻辑，独立于同步协议。
    private func updateExpandedGroupIfNeeded(for groupModel: EmerFireAlarmSyncGroupModel?) {
        guard let groupModel = groupModel else { return }
        groupModel.isShow = true
        guard lastGroupModel != groupModel else { return }
        lastGroupModel?.isShow = false
        lastGroupModel = groupModel
    }

    /// 将当前正在执行的 device 展开，方便观察 step/task 进度。
    /// 这是表格展示模型逻辑，独立于同步协议。
    private func updateExpandedDeviceIfNeeded(_ deviceModel: EmerFireAlarmSyncDeviceModel) {
        deviceModel.isShow = true
        guard lastDeviceModel != deviceModel else { return }
        lastDeviceModel?.isShow = false
        lastDeviceModel = deviceModel
    }

    /// 发送当前模型对应的消息批次。
    /// 这个方法只桥接 MeshProxyMessageCommand 与本地状态机，不直接改 table section 结构。
    private func executeSyncModel(_ model: EmerFireAlarmSyncCellModel, messageHandles: [MeshMessageHandle], semaphore: DispatchSemaphore) {
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 15, progressBack: nil, successfulBack: { [weak self] handle, statusMessage in
            self?.handleSuccessfulStatusMessage(handle, statusMessage: statusMessage, messageHandles: messageHandles)
        }, failedBack: { [weak self] handle in
            self?.handleFailedStatusMessage(handle)
        }) { [weak self] resultMessageHandles in
            guard let self = self else { return }
            self.handleFinishedMessageHandles(resultMessageHandles, for: model)
            semaphore.signal()
        }
    }

    // MARK: - Result Handling & Node Updates

    /// 单条成功状态消息回调。
    /// 这里处理两类副作用：
    /// - 初始化/场景类即时状态回写
    /// - vendor 私有状态解析
    private func handleSuccessfulStatusMessage(_ handle: MeshMessageHandle, statusMessage: MeshMessage, messageHandles: [MeshMessageHandle]) {
        if statusMessage is ConfigCompositionDataStatus || statusMessage is ConfigAppKeyStatus {
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
               node.isInitialize {
                MeshProxyMessageCommand.shared.addMessage(messageHandles: node.getConfigMessageHandles(), finishedBack: nil)
            }
            return
        }

        if (statusMessage is LightLightnessStatus || statusMessage is LightCTLTemperatureStatus || statusMessage is LightCTLStatus || statusMessage is LightHSLStatus),
           messageHandles.contains(where: { $0.message is SceneStore }) {
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.updateNodeStatus(message: statusMessage, source: address)
            }
            return
        }

        guard let vendorStatusMessage = statusMessage as? SunricherVendorStatus else { return }
        handleVendorStatusMessage(vendorStatusMessage, handle: handle)
    }

    /// vendor 私有状态回写。
    /// 这里更新的是节点运行时缓存，不直接决定列表成败；列表成败由批次完成后的统一判断处理。
    private func handleVendorStatusMessage(_ vendorStatusMessage: SunricherVendorStatus, handle: MeshMessageHandle) {
        if vendorStatusMessage.status.code == .dimmerPowerCalibrate {
            guard vendorStatusMessage.status.errorCode == 2,
                  let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
                  let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) else {
                return
            }

            if case .dimmerPowerCalibrateError(let maxPower) = vendorStatusMessage.status.parameters {
                node.powerCalibrateError = .powerExceed(maxPower: Int(maxPower / 10))
            } else {
                node.powerCalibrateError = .powerExceed(maxPower: 300)
            }
            return
        }

        if vendorStatusMessage.status.code == .daylightLuxTriggerLock {
            guard let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
                  let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
                  let vendorSet = handle.message as? SunricherVendorSet,
                  case .daylightLuxTriggerLock(let delay) = vendorSet.function else {
                return
            }

            if delay > 0 {
                if !luxTriggerLockDevices.contains(node) {
                    luxTriggerLockDevices.append(node)
                }
            } else if let index = luxTriggerLockDevices.firstIndex(of: node) {
                luxTriggerLockDevices.remove(at: index)
            }
            return
        }

        if handle.message is SunricherVendorGet,
           case .daylightConditionRecall(let index) = vendorStatusMessage.status.parameters,
           index >= 0,
           let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
           let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
            daylightRecallConditionIDs[node.primaryUnicastAddress] = UInt8(index)
        }
    }

    /// 单条失败消息回调。
    /// 当前仅处理需要即时写回节点错误信息的协议，例如功率校准超时。
    private func handleFailedStatusMessage(_ handle: MeshMessageHandle) {
        guard let vendorSetMessage = handle.message as? SunricherVendorSet,
              case .dimmerPowerCalibrate = vendorSetMessage.function,
              let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
              let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) else {
            return
        }

        node.powerCalibrateError = .timeout
    }

    /// 当前模型整批消息执行完成后的统一收口。
    /// 这里同时负责：
    /// - 节点数据更新
    /// - 同步状态机成败判定
    /// - 列表 cell 状态刷新
    /// - 成功后的设备闪烁提示
    private func handleFinishedMessageHandles(_ resultMessageHandles: [MeshMessageHandle], for model: EmerFireAlarmSyncCellModel) {
        resultMessageHandles.forEach { handle in
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                node.clearSyncStateCache()
            }
        }

        let resultSuccessful = !resultMessageHandles.contains(where: { !$0.isSuccessful })
        let operationSuccessful = ((model as? EmerFireAlarmSyncDeviceModel)?.operationType?.isSuccessful ?? (model as? EmerFireAlarmSyncStepTaskModel)?.operationType.isSuccessful) ?? false

        if resultSuccessful && operationSuccessful {
            model.state = .successful
            triggerDeviceBlinkIfNeeded(for: model)
        } else {
            model.state = .failed
            (model as? EmerFireAlarmSyncDeviceModel)?.failedCount += 1
            (model as? EmerFireAlarmSyncStepTaskModel)?.failedCount += 1
        }

        updateCell(model: model)
    }

    /// 设备级同步全部成功后触发识别闪烁。
    /// 这是成功后的附加交互，不参与成败判定。
    private func triggerDeviceBlinkIfNeeded(for model: EmerFireAlarmSyncCellModel) {
        guard deviceBlinkMode != .none else { return }

        let deviceModel: EmerFireAlarmSyncDeviceModel? =
            (model as? EmerFireAlarmSyncDeviceModel)
            ?? (model as? EmerFireAlarmSyncStepTaskModel)?.parentStepModel?.parentDeviceModel

        guard let deviceModel = deviceModel,
              let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: deviceModel.address),
              deviceModel.state == .successful else {
            return
        }

        node.sendHandleCompleteIdentify(deviceBlinkMode: deviceBlinkMode)
    }

    // MARK: - Progress & Table Presentation

    /// 刷新进度弹窗与底部计数。
    /// 这里只读 sections 当前状态，不做任何业务判定。
    private func refreshProgressUI() {
        DispatchQueue.main.async {
            if let model = self.showProressStepModel {
                EmerFireAlarmSyncProgressView.current()?.stepModel = model
            }
            let allDevices = self.sections.flatMap({ $0.groups.flatMap({ $0.deviceModels }) + $0.devices })
            self.progressLabel.text = "\(allDevices.filter({ $0.state == .successful }).count)/\(allDevices.count)"
        }
    }
    
    /// 设备重同步前，清理当前轮次残留状态（仅保留成功任务）
    private func prepareDeviceForResync(_ device: EmerFireAlarmSyncDeviceModel) {
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
    
    /// 获取下一个需要处理的模型。
    /// 这是同步状态机的“调度器”：
    /// - 设备级操作优先直接执行
    /// - step/task 按前置依赖顺序推进
    /// - 已失败依赖会阻断后续任务
    private func getNextHandleModel() -> EmerFireAlarmSyncCellModel? {
        
        for section in sections {
            let devices = section.allModels.filter({ $0.isKind(of: EmerFireAlarmSyncDeviceModel.classForCoder()) }) as! [EmerFireAlarmSyncDeviceModel]
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
        
    /// 刷新单次执行后的表格展示。
    /// 当前实现仍是整表 reload，原因是 group/device 展开态、step 进度、section 计数会一起变化。
    /// 如果后面要优化成局部刷新，应先把“展示模型变化”和“业务状态变化”进一步分离。
    private func updateCell(model: EmerFireAlarmSyncCellModel) {
        
        
//            var reloadIndexPath: IndexPath?
            
//            var sectionIndex: Int = 0
//            
//            if let groupModel = model as? EmerFireAlarmSyncGroupModel, let section = groupModel.parentSectionIndex {
//                sectionIndex = section
//                
//            }else if let deviceModel = model as? EmerFireAlarmSyncDeviceModel {
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
//            }else if let taskModel = model as? EmerFireAlarmSyncStepTaskModel, let stepModel = taskModel.parentStepModel, let section = stepModel.parentDeviceModel?.parentSectionIndex {
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
        tableView.register(EmerFireAlarmSyncTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "titleHeader")
//        tableView.register(SyncDevicesSectionHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.register(EmerFireAlarmSyncGroupViewCell.classForCoder(), forCellReuseIdentifier: "groupCell")
        tableView.register(EmerFireAlarmSyncDeviceViewCell.classForCoder(), forCellReuseIdentifier: "deviceCell")
        tableView.register(EmerFireAlarmSyncDeviceStepViewCell.classForCoder(), forCellReuseIdentifier: "stepCell")
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

extension EmerFireAlarmSyncsVC: UITableViewDataSource, UITableViewDelegate {
    
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
        case is EmerFireAlarmSyncGroupModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! EmerFireAlarmSyncGroupViewCell
            cell.groupModel = cellModel as? EmerFireAlarmSyncGroupModel
            cell.delegate = self
            return cell
        case is EmerFireAlarmSyncSwitchProxyModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! EmerFireAlarmSyncGroupViewCell
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
            let proxyModel = cellModel as? EmerFireAlarmSyncSwitchProxyModel
            cell.nameLabel.text = proxyModel?.name
            cell.iconImageBtn.setImage(UIImage(named: proxyModel?.imageName ?? ""), for: .normal)
            return cell
            
        case is EmerFireAlarmSyncDeviceModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell", for: indexPath) as! EmerFireAlarmSyncDeviceViewCell
            cell.model = cellModel as? EmerFireAlarmSyncDeviceModel
            cell.delegate = self
            return cell
        default:
            let cell = tableView.dequeueReusableCell(withIdentifier: "stepCell", for: indexPath) as! EmerFireAlarmSyncDeviceStepViewCell
            if let stepModel = cellModel as? EmerFireAlarmSyncStepModel {
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
        
        let titleView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "titleHeader") as! EmerFireAlarmSyncTitleHeaderView
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
        if let groupModel = cellModel as? EmerFireAlarmSyncGroupModel { // group
            // 展开/收起 group
            if groupModel.state == .successful || groupModel.state == .failed {
                groupModel.isShow = !groupModel.isShow
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .automatic)
            }
        }else if let deviceModel = cellModel as? EmerFireAlarmSyncDeviceModel { // device
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
        }else if let stepModel = cellModel as? EmerFireAlarmSyncStepModel { // 过程
            // 弹窗显示进度
            guard stepModel.tasks.count > 0 else {
                return
            }
            EmerFireAlarmSyncProgressView.show(stepModel: stepModel) { [weak self] task in
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

extension EmerFireAlarmSyncsVC: EmerFireAlarmSyncGroupViewCellDelegate {
    
    /// 选中/取消选中更新回调
    func cell(_ cell: EmerFireAlarmSyncGroupViewCell, didSelectedAction model: EmerFireAlarmSyncGroupModel) {
        
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
//    func cellClickAction(cell: EmerFireAlarmSyncGroupViewCell) {
//        
//    }
    
    /// 点击图标回调
    func cellClickIconAction(cell: EmerFireAlarmSyncGroupViewCell) {
        
    }
    
}

extension EmerFireAlarmSyncsVC: EmerFireAlarmSyncDeviceViewCellDelegate {
    
    /// 选中/取消选中更新回调
    func cell(_ cell: EmerFireAlarmSyncDeviceViewCell, didSelectedAction model: EmerFireAlarmSyncDeviceModel) {
        
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
    func cell(_ cell: EmerFireAlarmSyncDeviceViewCell, iconClickAction model: EmerFireAlarmSyncDeviceModel) {
        MeshAPI.identify(address: model.address)
    }
    
    /// 失败重试回调
    func cell(_ cell: EmerFireAlarmSyncDeviceViewCell, resyncAction model: EmerFireAlarmSyncDeviceModel) {
        model.state = .none
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
    
}

extension EmerFireAlarmSyncsVC: EmerFireAlarmSyncDeviceStepViewCellDelegate {
    
    /// 重新同步事件回调
    func cell(_ cell: EmerFireAlarmSyncDeviceStepViewCell, resyncAction model: EmerFireAlarmSyncStepModel) {
        
        model.tasks.forEach({ task in
            if task.state == .failed {
                task.state = .none
                // 检查是否有profile数据需要加锁、切换场景前置要求，需要则重试必须连带前置条件一起设置
                if task.relevanceTaskModels.count > 0 {
                    task.resyncRelevanceCheck().forEach({
                        $0.state = .wait
                    })
                }
            }
        })
        syncState = .inSync
        updateSyncStateUI()
        startSync()
    }
    
}

extension EmerFireAlarmSyncsVC {
    
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
