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
    private var progressLabel: UILabel!
    /// 返回按钮
    private lazy var backBtn: UIButton = {
        let btn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
        return btn
    }()
    
    private var sections: [SyncDevicesSectionModel] {
        get { executionSession.sections }
        set { executionSession.sections = newValue }
    }
    
    private(set) var type: SyncType
    /// 上一个group model
    private var lastGroupModel: SyncDevicesGroupModel?
    /// 上一个device model
    private var lastDeviceModel: SyncDevicesModel?
    /// 同步状态
    private var syncState: SyncState {
        get { executionSession.syncState }
        set { executionSession.syncState = newValue }
    }
    /// 是否展示详细进度的model
    private var showProressStepModel: SyncDeviceStepModel?
    /// 同步完成回调
    var syncSuccessCallback: ((SyncType)->Void)?
    /// 点击返回回调（result: 每个设备成功、失败操作）
    var backActionCallback: ((_ result: [SyncResultData])->Void)?
    /// lux触发锁定的设备list
    var luxTriggerLockDevices: [Node] {
        get { executionSession.luxTriggerLockDevices }
        set { executionSession.luxTriggerLockDevices = newValue }
    }
    /// 自动化恢复
    var automationRestore: Bool {
        get { executionSession.automationRestore }
        set { executionSession.automationRestore = newValue }
    }
    /// 自动恢复重试耗尽后的调用方处理；未设置时保持现有 BLE OTA 返回行为。
    var automationRestoreFailureCallback: (() -> Void)?
    /// SAVE Profile 期间临时禁用/恢复组内 PIR 传感器
    var profileSensorProtectionContext: ProfileSensorProtectionContext? {
        get { executionSession.profileSensorProtectionContext }
        set { executionSession.profileSensorProtectionContext = newValue }
    }
    /// Group profile switch context. Only applies to normal group profile SAVE, not member add/remove flows.
    var groupProfileSyncContext: GroupProfileSyncContext?
    /// Group/Profile/Member 生命周期变更产生的跨 Group 邻近照明任务。
    var supplementaryProximityLightingSyncDatas: [(node: Node, syncData: NodeSyncData)] = []
    private var proximityLightingTaskModels: [SyncDeviceStepTaskModel] {
        get { executionSession.proximityLightingTaskModels }
        set { executionSession.proximityLightingTaskModels = newValue }
    }
    private var batteryPowerSwitchActivationFlow: PJEightKeySwitchActivationFlow?
    private let executionSession: SyncExecutionSession
    private var syncRunIdentifier: UUID { executionSession.identifier }
    private var hasLeftSyncPage = false
    private let syncDisplayContext = SyncDevicesDisplayContext()

    
    private var deviceBlinkMode: DeviceBlinkMode {
        get { executionSession.deviceBlinkMode }
        set { executionSession.deviceBlinkMode = newValue }
    }
    
    var vcTitle: String?
    
    init(type: SyncType, reSync: Bool = false) {
        
        self.type = type
        self.executionSession = SyncExecutionSession(type: type, reSync: reSync)
        super.init(nibName: nil, bundle: nil)
        
        syncState = reSync ? .syncFailure : .inSync
    }
    
    deinit {
        let session = executionSession
        if Thread.isMainThread { session.close() }
        else { DispatchQueue.main.async { session.close() } }
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
        
        
        setupUI()
        bindExecutionSession()
        
        deviceBlinkMode = SpaceViewController.currentDeviceBlinkMode
        
        executionSession.onPlanInvalidated = { [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            self.profileSensorProtectionContext = nil
            self.groupProfileSyncContext = nil
            self.rebuildTaskPlan(resume: true)
        }
        rebuildTaskPlan(resume: syncState == .inSync)
    }

    private func rebuildTaskPlan(resume: Bool) {
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        Task { @MainActor [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            _ = await SpaceSyncCleanupCoordinator.prepareCurrentSpace()
            guard !self.hasLeftSyncPage else { return }
            self.type = self.currentSyncType()
            self.executionSession.type = self.type
            let isCurrent = SpaceSyncTaskScope.capture()
            self.executionSession.environment.configurationIsCurrent = isCurrent
            if resume { self.syncState = .inSync }
            let builder = SyncTaskPlanBuilder(
                type: self.type, initialState: self.syncState,
                profileSensorProtectionContext: self.profileSensorProtectionContext,
                groupProfileSyncContext: self.groupProfileSyncContext,
                supplementaryProximityLightingSyncDatas: self.supplementaryProximityLightingSyncDatas.compactMap { item in
                    guard let node = self.currentNode(item.node), let data = node.getNodeSyncProximityLighting() else { return nil }
                    return (node, data)
                }, imageExists: { UIImage(named: $0) != nil })
            // Own the mutable Mesh snapshot on the same queue as its callbacks.
            let result = builder.build()
            guard isCurrent() else { self.rebuildTaskPlan(resume: resume); return }
            self.installTaskPlan(result)
        }
    }

    private func currentNode(_ original: Node) -> Node? {
        MeshNetworkManager.instance.meshNetwork?.nodes.first {
            $0.uuid == original.uuid && $0.primaryUnicastAddress == original.primaryUnicastAddress
        }
    }

    private func currentSyncType() -> SyncType {
        let network = MeshNetworkManager.instance.meshNetwork
        switch type {
        case .devices(let nodes): return .devices(nodes.compactMap(currentNode))
        case .profile(let datas):
            return .profile(datas.compactMap { item in
                guard let node = currentNode(item.node) else { return nil }
                return (node, node.getNodeSyncProfiles(group: node.group))
            })
        case .group(let original, let inNodes, let outNodes):
            guard let group = network?.groups.first(where: { !$0.isVirtual && $0.address == original.address }) else {
                return .devices(network.map { ProximityLightingTopologyContext.realNodes(in: $0) } ?? [])
            }
            return .group(group, inNodes: inNodes?.compactMap(currentNode), outNodes: outNodes?.compactMap(currentNode))
        case .proximityLightingPath(let datas), .spaceTriggerZones(let datas):
            let current = datas.compactMap { item -> (node: Node, syncData: NodeSyncData)? in
                guard let node = currentNode(item.node), let data = node.getNodeSyncProximityLighting() else { return nil }
                return (node, data)
            }
            return .spaceTriggerZones(datas: current)
        default: return type
        }
    }

    private func installTaskPlan(_ result: SyncTaskPlanResult) {
        precondition(Thread.isMainThread)
        guard !self.hasLeftSyncPage else { return }
        self.sections = result.sections
        // 构建期间可能已 STOP；迟到的快照不能恢复自动同步。
        if self.syncState == .inSync {
            self.syncState = result.initialState
        } else if self.syncState == .syncFailure {
            // STOP 时这些模型尚未安装，补齐失败状态以支持用户手动重试。
            self.sections.forEach { section in
                section.allModels.forEach {
                    $0.isFineshed = true
                    $0.state = .failed
                }
            }
        }
        self.proximityLightingTaskModels = result.proximityLightingTasks
        XWHUDManager.hideInView(with: self.view)
        result.failureMessages.forEach { XWHUDManager.showErrorTipHUD($0) }
        if self.syncState == .inSync {
            self.startSync()
        }
        self.tableView.reloadData()
        self.updateSyncStateUI()
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
        if isMovingFromParent || isBeingDismissed || navigationController?.isBeingDismissed == true {
            hasLeftSyncPage = true
            executionSession.close()
            syncDisplayContext.invalidateRun()
        }
    }

    @objc private func backAction() {
        guard !hasLeftSyncPage else { return }
        hasLeftSyncPage = true
        executionSession.close()
        syncDisplayContext.invalidateRun()

        if backActionCallback != nil {

            let resultDatas = SyncResultCollector().collect(
                sections: sections,
                nodes: MeshNetworkManager.instance.meshNetwork?.nodes ?? []
            )
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
            executionSession.stop()
            syncDisplayContext.invalidateRun()
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
    
    private func bindExecutionSession() {
        executionSession.onRunBegan = { [weak self] identifier in
            guard let self, !self.hasLeftSyncPage else { return }
            self.syncDisplayContext.beginRun(identifier)
        }
        executionSession.onTaskStarted = { [weak self] model, identifier in
            self?.displayTaskStarted(model, identifier: identifier)
        }
        executionSession.onProgress = { [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            self.refreshVisibleSyncCells()
            if let model = self.showProressStepModel, let progress = SyncDevicesProgressView.current() {
                progress.stepModel = model
            }
            let devices = self.sections.flatMap { $0.groups.flatMap { $0.deviceModels } + $0.devices }
            self.progressLabel.text = "\(devices.filter { $0.state == .successful }.count)/\(devices.count)"
        }
        executionSession.onReload = { [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            self.tableView.reloadData()
            self.updateSyncStateUI()
        }
        executionSession.onError = { [weak self] message in
            guard self?.hasLeftSyncPage == false else { return }
            XWHUDManager.showErrorTipHUD(message)
        }
        executionSession.onCompleted = { [weak self] state in
            guard let self, !self.hasLeftSyncPage else { return }
            if state == .syncSuccess {
                self.syncSuccessCallback?(self.type)
                SyncDevicesProgressView.current()?.hide()
            } else {
                SyncDevicesProgressView.current()?.reload()
            }
        }
        executionSession.onBatteryActivationRequired = { [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            self.startBatteryPowerSwitchConfigurationResyncAfterActivation()
        }
        executionSession.onRetryExhausted = { [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            self.navigationController?.hideAutomaticHud()
            if let callback = self.automationRestoreFailureCallback { callback() }
            else { self.navigationController?.popToViewController(vcClass: BleFirmwareUpdateViewController.classForCoder()) }
        }
    }

    private func displayTaskStarted(_ model: SyncCellModel, identifier: UUID) {
        precondition(Thread.isMainThread)
        guard !hasLeftSyncPage, syncRunIdentifier == identifier else { return }
        var needsListReload = false
        let device = (model as? SyncDevicesModel) ?? (model as? SyncDeviceStepTaskModel)?.parentStepModel?.parentDeviceModel
        if let group = device?.parentGroupModel {
            needsListReload = !group.isShow
            group.isShow = true
            if lastGroupModel != group {
                needsListReload = needsListReload || lastGroupModel?.isShow == true
                lastGroupModel?.isShow = false
                lastGroupModel = group
            }
        }
        if model is SyncDeviceStepTaskModel, let device {
            needsListReload = needsListReload || !device.isShow
            device.isShow = true
            if lastDeviceModel != device {
                needsListReload = needsListReload || lastDeviceModel?.isShow == true
                lastDeviceModel?.isShow = false
                lastDeviceModel = device
            }
        }
        syncDisplayContext.taskDidStart(model, run: identifier)
        if needsListReload { tableView.reloadData() }
        else { refreshVisibleSyncCells() }
        if let task = model as? SyncDeviceStepTaskModel, task.parentStepModel === showProressStepModel {
            SyncDevicesProgressView.current()?.stepModel = task.parentStepModel
        }
    }

    private func startSync() {
        guard !hasLeftSyncPage else { return }
        executionSession.start()
    }

    private var batteryPowerSwitchDataForSync: PJEightKeySwitchData? { executionSession.batteryPowerSwitchDataForSync }

    private func resetBatteryPowerSwitchConfigurationForResync() {
        executionSession.enqueuePreparation { [executionSession] in executionSession.resetBatteryPowerSwitchConfigurationForResync() }
    }

    private func selectedFailedDevicesForResync() -> [SyncDevicesModel] { executionSession.selectedFailedDevicesForResync() }

    private func startBatteryPowerSwitchConfigurationResyncAfterActivation() {
        guard !hasLeftSyncPage else { return }
        guard let switchData = batteryPowerSwitchDataForSync else {
            return
        }
        guard switchData.requiresActivationBeforeOwnConfiguration else {
            resetBatteryPowerSwitchConfigurationForResync()
            syncState = .inSync
            updateSyncStateUI()
            startSync()
            return
        }
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: switchData
        ) { [weak self] in
            guard let self, !self.hasLeftSyncPage else { return }
            self.batteryPowerSwitchActivationFlow = nil
            self.resetBatteryPowerSwitchConfigurationForResync()
            self.syncState = .inSync
            self.updateSyncStateUI()
            self.startSync()
        }
        batteryPowerSwitchActivationFlow = flow
        flow.start()
    }

    private func prepareDeviceForResync(_ device: SyncDevicesModel) {
        executionSession.enqueuePreparation { [executionSession] in executionSession.prepareDeviceForResync(device) }
    }

    private func prepareStepForResync(_ step: SyncDeviceStepModel) {
        executionSession.enqueuePreparation { [executionSession] in executionSession.prepareStepForResync(step) }
    }

    private func prepareTaskForResync(_ task: SyncDeviceStepTaskModel) {
        executionSession.enqueuePreparation { [executionSession] in executionSession.prepareTaskForResync(task) }
    }

    private func containsBatteryPowerSwitchConfiguration(_ model: SyncDevicesModel) -> Bool {
        executionSession.containsBatteryPowerSwitchConfiguration(model)
    }

    private func containsBatteryPowerSwitchConfiguration(_ model: SyncDeviceStepModel) -> Bool {
        executionSession.containsBatteryPowerSwitchConfiguration(model)
    }

    private func refreshVisibleSyncCells() {
        for cell in tableView.visibleCells {
            if let cell = cell as? SyncDeviceStepViewCell {
                cell.updateProgress()
            } else if let cell = cell as? SyncDeviceViewCell, let model = cell.model {
                cell.updateState(syncDisplayContext.state(for: model))
            } else if let cell = cell as? SyncDevicesGroupViewCell, let model = cell.groupModel,
                      let indexPath = tableView.indexPath(for: cell),
                      sections.indices.contains(indexPath.section),
                      sections[indexPath.section].rowModels.indices.contains(indexPath.row),
                      sections[indexPath.section].rowModels[indexPath.row] === model {
                // groupCell 同时用于 Proxy 行，不能把复用前的 Group 状态写回 Proxy 行。
                cell.updateState(syncDisplayContext.state(for: model))
            }
        }
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
            cell.configure(with: cellModel as! SyncDevicesGroupModel, displayState: syncDisplayContext.state(for: cellModel))
            cell.delegate = self
            return cell
        case is SyncDevicesSwitchProxyModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! SyncDevicesGroupViewCell
            cell.clearBinding()
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
            cell.configure(with: cellModel as! SyncDevicesModel, displayState: syncDisplayContext.state(for: cellModel))
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
                guard let self, !self.hasLeftSyncPage else { return }
                self.prepareTaskForResync(task)
                self.showProressStepModel = stepModel
                self.syncState = .inSync
                self.updateSyncStateUI()
                self.startSync()
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
        guard !hasLeftSyncPage else { return }
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
        guard !hasLeftSyncPage else { return }
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

    enum EmergencyFireSyncContext {
        case saveConfiguration(persistsSyncResult: Bool, changedFromConfiguration: EmergencyFireControllerConfiguration?)
        case deleteCleanup

        var persistsSyncResult: Bool {
            switch self {
            case .saveConfiguration(let persistsSyncResult, _):
                return persistsSyncResult
            case .deleteCleanup:
                return false
            }
        }

        var changedFromConfiguration: EmergencyFireControllerConfiguration? {
            switch self {
            case .saveConfiguration(_, let changedFromConfiguration):
                return changedFromConfiguration
            case .deleteCleanup:
                return nil
            }
        }

        var isDeleteCleanup: Bool {
            if case .deleteCleanup = self {
                return true
            }
            return false
        }
    }
    
    enum GatewayRecoveryTrigger {
        case devicesNotSynced
        case repair

        var startsImmediately: Bool {
            switch self {
            case .devicesNotSynced:
                return false
            case .repair:
                return true
            }
        }
    }

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
        /// WiFi 网关添加中断后的完整恢复
        case gatewayRecovery(
            node: Node,
            gateway: GatewayModel,
            trigger: GatewayRecoveryTrigger
        )
        /// WiFi Gateway 手动 Authorize 的服务器恢复子链
        case gatewayServerRecovery(node: Node, gateway: GatewayModel)
        /// 同步设备参数
        case devicesParameter(_ datas: [(node: Node, parameters: [DeviceParameterType])])
        /// Dongle设备
        case dongle(_ dongleData: DeviceDongleData)
        /// 应急火警控制器
        case emergencyFire(data: DeviceEmerFireData, items: [EmergencyFireControllerSyncItem]?, context: EmergencyFireSyncContext)
        /// 邻近照明路径
        case proximityLightingPath(datas: [(node: Node, syncData: NodeSyncData)])
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
