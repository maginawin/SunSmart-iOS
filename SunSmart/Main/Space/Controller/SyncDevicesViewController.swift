//
//  SyncDevicesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit
import NordicSigMeshSDK

class SyncDevicesViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    /// 返回按钮
    private lazy var backBtn: UIButton = {
        let btn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
        return btn
    }()
    
    private var headers: [UIView] = []
    
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
    /// 点击返回回调
    var backActionCallback: (()->Void)?
    
    
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

        title = "sync_device(s)".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "re_sync".localizedString, color: Title_Color, font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(rightItemAction))
        
        setupUI()
        
        setupDataSource()
//        test()
        if syncState == .inSync {
            startSync()
        }
        updateSyncStateUI()
    }
    
    /// 设置数据源
    private func setupDataSource() {
        
        let removeSection = SyncDevicesSectionModel(title: "remove".localizedString)
        let configurationSection = SyncDevicesSectionModel(title: "configuration".localizedString)
        
        switch type {
        case .group(let group, let inNodes, let outNodes):
            
            outNodes?.forEach({ node in
                let result = getSyncDeviceModel(group: group, node: node, exitGroup: true)
                if let removceDevice = result.removeDevice {
                    removeSection.devices.append(removceDevice)
                }
            })
            
            inNodes?.forEach({ node in
                let result = getSyncDeviceModel(group: group, node: node)
                if let removceDevice = result.removeDevice {
                    removeSection.devices.append(removceDevice)
                }
                if let configurationDevice = result.configturationDevice {
                    configurationSection.devices.append(configurationDevice)
                }
            })
            
            group.nodes.forEach { node in
                let result = getSyncDeviceModel(group: group, node: node, exitGroup: node.groupState == .exitFailure)
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
                
                if let groupSceneData = group.info.bindSceneDatas[scene.number] {
                    let resut = group.getNeedSyncDataNodes(scene: scene)
                    // 需要同步的设备
                    let syncNodes = resut.syncNodes
                    let syncSceneDeviceModels = syncNodes.map({ node in
                        let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                        // 场景绑定日程
                        if scene.info.bindSchedules.count > 0 {
                            
                            let addSceneTask = SyncDeviceStepTaskModel(name: scene.info.name ?? scene.name, operationType: .configuration(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData)))
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
                        let groupModel = SyncDevicesGroupModel(groupName: group.info.name ?? group.name, groupAddress: group.address.address, deviceModels: syncSceneDeviceModels)
                        configurationSection.groups.append(groupModel)
                        
                        syncSceneDeviceModels.forEach({
                            $0.parentGroupModel = groupModel
                        })
                    }
                    
                    // 需要删除的设备
                    let deleteNodes = resut.deleteNodes
                    let deleteSceneDeviceModels = deleteNodes.map({ node in
                        let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                        if scene.info.bindSchedules.count > 0 {
                            
                            let deleteScheduleTasks = scene.info.bindSchedules.map({ schedule in
                                 SyncDeviceStepTaskModel(name: schedule.name, operationType: .delete(node: node, type: .schedule(schedule: schedule)))
                            })
                            let deleteScheduleStep = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: deleteScheduleTasks)
                            deleteScheduleStep.parentDeviceModel = model
                            deleteScheduleStep.showProgress = false
                            deleteScheduleTasks.forEach({ $0.parentStepModel = deleteScheduleStep })
                            
                            
                            let deleteSceneTask = SyncDeviceStepTaskModel(name: scene.info.name ?? scene.name, operationType: .delete(node: node, type: .scene(sceneId: scene.number, executeData: groupSceneData)))
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
                        let groupModel = SyncDevicesGroupModel(groupName: group.info.name ?? group.name, groupAddress: group.address.address, deviceModels: deleteSceneDeviceModels)
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
                model.operationType = .delete(node: $0, type: .schedule(schedule: schedule))
                return model
            })
            removeSection.devices.append(contentsOf: deleteScheduleDeviceModels)
            // 需同步日程的设备
            let syncScheduleDeviceModels = data.syncNodes.map({
                let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                model.operationType = .configuration(node: $0, type: .schedule(schedule: schedule))
                return model
            })
            configurationSection.devices.append(contentsOf: syncScheduleDeviceModels)
            
            // 需删除日程的组
            var deleteScheduleGroupModels = data.deleteGroups.map { (group: Group, nodes: [Node]) in
                let deviceModels = nodes.map({
                    let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                    model.operationType = .delete(node: $0, type: .schedule(schedule: schedule))
                    return model
                })
                
                let groupModel = SyncDevicesGroupModel(groupName: group.info.name ?? group.name, groupAddress: group.address.address, deviceModels: deviceModels)
                deviceModels.forEach({ $0.parentGroupModel = groupModel })
                return groupModel
            }
            deleteScheduleGroupModels = deleteScheduleGroupModels.sorted(by: { $0.address < $1.address })
            removeSection.groups.append(contentsOf: deleteScheduleGroupModels)
            // 需同步日程的组
            var syncScheduleGroupModels = data.syncGroups.map { (group: Group, nodes: [Node]) in
                let deviceModels = nodes.map({
                    let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                    model.operationType = .configuration(node: $0, type: .schedule(schedule: schedule))
                    return model
                })
                let groupModel = SyncDevicesGroupModel(groupName: group.info.name ?? group.name, groupAddress: group.address.address, deviceModels: deviceModels)
                deviceModels.forEach({ $0.parentGroupModel = groupModel })
                return groupModel
            }
            syncScheduleGroupModels = syncScheduleGroupModels.sorted(by: { $0.address < $1.address })
            configurationSection.groups.append(contentsOf: syncScheduleGroupModels)
        }
    
        if removeSection.groups.count > 0 || removeSection.devices.count > 0 {
            sections.append(removeSection)
        }
        if configurationSection.groups.count > 0 || configurationSection.devices.count > 0 {
            sections.append(configurationSection)
        }
        for (index, section) in sections.enumerated() {
            section.groups.forEach({
                $0.parentSectionIndex = index
            })
            section.devices.forEach({
                $0.parentSectionIndex = index
            })
            if syncState == .syncFailure {
                section.allModels.forEach({
                    $0.isFineshed = true
//                    ($0 as? SyncDevicesGroupModel)?.isShow = true
                    ($0 as? SyncDevicesModel)?.state = .failed
                    ($0 as? SyncDeviceStepTaskModel)?.state = .failed
                })
            }
        }
        
        tableView.reloadData()
    }
    
    /// 获取组对应设备同步数据model
    /// - Parameters:
    ///   - group: 组
    ///   - node: 设备
    ///   - exitGroup: 是否退组
    /// - Returns: 需要配置的model，需要删除的model
    private func getSyncDeviceModel(group: Group, node: Node, exitGroup: Bool = false) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
        
        let data = node.getNeedSyncGroupData(group: group)
        var nodeDeleteScenes = data.deleteScenes
        var nodeSyncScenes = data.syncScenes
        var nodeDeleteSchedules = data.deleteSchedules
        var nodeSyncSchedules = data.syncSchedules
        /// 删除操作
        var deleteSteps: [SyncDeviceStepModel] = []
        /// 同步操作
        var configturationSteps: [SyncDeviceStepModel] = []
        
        // 是否退出组
        if exitGroup {
            nodeDeleteScenes = node.scenes.filter({ group.info.bindSceneDatas.keys.contains($0.number) })
            nodeDeleteSchedules = group.info.bindSchedules.filter({ schedule in node.scheduleDatas.contains(where: { $0.key == schedule.id }) })
            
            nodeSyncScenes.removeAll()
            nodeSyncSchedules.removeAll()
        }
        
        let deleteScheduleTasks = nodeDeleteSchedules.map({
            return SyncDeviceStepTaskModel(name: $0.name, operationType: .delete(node: node, type: .schedule(schedule: $0)))
        })
        if deleteScheduleTasks.count > 0 {
            let step = SyncDeviceStepModel(type: "remove_schedule".localizedString, state: .none, tasks: deleteScheduleTasks)
            deleteScheduleTasks.forEach({ $0.parentStepModel = step })
            deleteSteps.append(step)
        }
        
        let deleteSceneTasks = nodeDeleteScenes.map({
            return SyncDeviceStepTaskModel(name: $0.info.name ?? $0.name, operationType: .delete(node: node, type: .scene(sceneId: $0.number, executeData: nil)))
        })
        if deleteSceneTasks.count > 0 {
            let step = SyncDeviceStepModel(type: "remove_scene".localizedString, state: .none, tasks: deleteSceneTasks)
            deleteSceneTasks.forEach({ $0.parentStepModel = step })
            deleteSteps.append(step)
        }
        
        let syncSceneTasks = nodeSyncScenes.map({ sceneData in
            let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == sceneData.key })
            return SyncDeviceStepTaskModel(name: scene?.info.name ?? scene?.name ?? "", operationType: .configuration(node: node, type: .scene(sceneId: sceneData.key, executeData: sceneData.value)))
        })
        if syncSceneTasks.count > 0 {
            let step = SyncDeviceStepModel(type: "scene".localizedString, state: .none, tasks: syncSceneTasks)
            syncSceneTasks.forEach({ $0.parentStepModel = step })
            configturationSteps.append(step)
        }
        
        let syncScheduleTasks = nodeSyncSchedules.map({
            return SyncDeviceStepTaskModel(name: $0.name, operationType: .configuration(node: node, type: .schedule(schedule: $0)))
        })
        if syncScheduleTasks.count > 0 {
            let step = SyncDeviceStepModel(type: "schedule".localizedString, state: .none, tasks: syncScheduleTasks)
            syncSceneTasks.forEach({ $0.parentStepModel = step })
            configturationSteps.append(step)
        }
        
        // 退出组
        if exitGroup {
            if node.group?.address.address == group.address.address {
                let removeGroupTask = SyncDeviceStepTaskModel(name: "remove_from_group".localizedString, operationType: .delete(node: node, type: .group(group: group)))
                let step = SyncDeviceStepModel(type: "remove_from_group".localizedString, state: .none, tasks: [removeGroupTask])
                removeGroupTask.parentStepModel = step
                // 需要依赖之前操作完成才能退出组
                step.relevanceStepModels = deleteSteps
                deleteSteps.append(step)
            }
            
        }else {
            // 组订阅数据未完整/未加入组
            if data.subscribeGroup {
                let addGroupTask = SyncDeviceStepTaskModel(name: "add_to_group".localizedString, operationType: .configuration(node: node, type: .group(group: group)))
                let step = SyncDeviceStepModel(type: "add_to_group".localizedString, state: .none, tasks: [addGroupTask])
                addGroupTask.parentStepModel = step
                
                // 后续同步操作需要设备添加组完成才能进行
                configturationSteps.forEach({
                    $0.relevanceStepModels = [step]
                })
                configturationSteps.insert(step, at: 0)
            }
        }
        
        var configturationDevice: SyncDevicesModel?
        var removeDevice: SyncDevicesModel?
        if configturationSteps.count > 0 {
            configturationDevice = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            configturationDevice?.steps = configturationSteps
            configturationSteps.forEach({ $0.parentDeviceModel = configturationDevice })
        }
        
        if deleteSteps.count > 0 {
            removeDevice = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            removeDevice?.steps = deleteSteps
            deleteSteps.forEach({ $0.parentDeviceModel = removeDevice })
        }
        
        return (configturationDevice, removeDevice)
    }
    
    /// 返回
    @objc private func backAction() {
        if backActionCallback != nil {
            backActionCallback?()
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    
    @objc private func rightItemAction() {
        if syncState == .inSync { // stop
            
            MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
            sections.forEach({
                $0.allModels.forEach({
                    if $0.state == .wait || $0.state == .none {
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
                            if task.state == .failed {
                                task.state = .wait
                            }
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
            tableView.contentInset = .zero
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
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: bottomView.height, right: 0)
            navigationItem.rightBarButtonItem?.isEnabled = selectModels.count > 0
        }
        
    }
    
    private func startSync() {
        
//        guard let section = sections.first, let model = section.allModels.first else { return }
        
        sections.forEach { section in
            section.allModels.forEach({
                if $0.state == .none {
                    $0.state = .wait
                }
                $0.isFineshed = false
                ($0 as? SyncDevicesGroupModel)?.isSelected = false
                ($0 as? SyncDevicesModel)?.isSelected = false
            })
        }
        tableView.reloadData()

        
        DispatchQueue.global().async {
            while let model = self.getNextHandleModel() {
                
                var messageHandles: [MeshMessageHandle] = []
                if let deviceModel = model as? SyncDevicesModel {
                    messageHandles = deviceModel.operationType?.messageHandles ?? []
//                    deviceModel.parentGroupModel?.deviceModels.forEach({
//                        if $0.state == .none {
//                            $0.state = .wait
////                            self.updateCell(model: $0)
//                        }
//                    })
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
                        
                    }
                }
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                
                
                let semaphore = DispatchSemaphore(value: 0)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
//                    if arc4random_uniform(10) < 9  {
//                    if (model as? SyncDevicesModel)?.address == 9 {
//                        model.state = .failed
//                    }else {
                        model.state = .successful
                        (model as? SyncDevicesModel)?.operationType?.finneshHandle()
                        (model as? SyncDeviceStepTaskModel)?.operationType.finneshHandle()
//                    }
//                    }else {
//                        (model as? SyncDevicesModel)?.failedCount += 1
//                        (model as? SyncDeviceStepTaskModel)?.failedCount += 1
//                        model.state = .failed
//                    }
                
                    
                    if let stepModel = (model as? SyncDeviceStepTaskModel)?.parentStepModel, self.showProressStepModel == stepModel {
                        DispatchQueue.main.async {
                            if let progressView = SyncDevicesProgressView.current() {
                                progressView.stepModel = stepModel
                            }
                        }
                    }
                    self.updateCell(model: model)
                    semaphore.signal()
                }
                semaphore.wait()
                
                
                
//                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, progressBack: nil, successfulBack: nil, failedBack: nil) {[weak self] resultMessageHandles in
//                    
//                    resultMessageHandles.forEach { handle in
////                        updateData
//                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
//                            node.updateData(message: handle.message)
//                        }
//                        if handle.isFinished {
//                            model.state = .successful
//                        }else {
//                            model.state = model.state == .failed ? .repeatedFailure : .failed
//                        }
//                    }
//                    self?.updateCell(model: model)
//                    semaphore.signal()
//                }
//                semaphore.wait()
            }
            _ = MeshNetworkManager.instance.save()
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
                if self.syncState == .syncSuccess {
                    // 同步完成回调
                    self.syncSuccessCallback?(self.type)
                    if let progressView = SyncDevicesProgressView.current() {
                        progressView.hide()
                    }
                }
                
                if let model = self.showProressStepModel {
                    if let progressView = SyncDevicesProgressView.current() {
                        progressView.stepModel = model
                    }
                }
//                self.bottomView.isHidden = self.syncState != .syncFailure
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
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
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
            guard stepModel.tasks.count > 1 else {
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
