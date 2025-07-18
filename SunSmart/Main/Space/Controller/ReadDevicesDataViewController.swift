//
//  ReadDevicesDataViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/17.
//

import UIKit
import NordicSigMeshSDK

class ReadDevicesDataViewController: UIViewController {

    /// 读取失败数据
    struct ReadFailedData {
        let node: Node
        var parameterTypes: [DeviceReadParameterType]
    }
    
    private var tableView: UITableView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var progressLabel: UILabel!
    
    /// 读取设备能耗（放弃全部数据）
    private var abandonAllDataBtn: UIButton!
    /// 读取设备能耗（使用缺失数据）
    private var useIncompleteDataBtn: UIButton!
    /// 返回按钮
    private lazy var backBtn: UIButton = {
        let btn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
        return btn
    }()
    
    private var sections: [SyncDevicesSectionModel] = []
    
    let type: ReadType
    /// 上一个group model
    private var lastGroupModel: SyncDevicesGroupModel?
    /// 上一个device model
    private var lastDeviceModel: SyncDevicesModel?
    /// 读取状态
    private var readState: ReadState = .inRead
    /// 是否展示详细进度的model
    private var showProressStepModel: SyncDeviceStepModel?
    /// 读取完成回调
    var readSuccessCallback: ((ReadType)->Void)?
    /// 点击返回回调
    var backActionCallback: (([ReadFailedData])->Void)?
    /// 获取能耗数据使用缺失数据回调
    var harvestEnergyUseIncompleteDataCallback: (([ReadFailedData])->Void)?
    
    init(type: ReadType) {
        
        self.type = type
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.isModalInPresentation = true
        
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: backBtn)
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "re_read".localizedString, color: Title_Color, font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(rightItemAction))
        
        
        setupUI()
        
        switch type {
        case .parameters:
            title = "read_settings".localizedString
        case .harvestData:
            title = "harvest_data".localizedString
            navigationItem.rightBarButtonItem?.title = "re-harvest".localizedString
        }
        
        
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        DispatchQueue.global().async {
            self.setupDataSource()
            DispatchQueue.main.async {
                XWHUDManager.hideInView(with: self.view)
                if self.readState == .inRead {
                    self.startRead()
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
    }

    private func setupDataSource() {
        
        let readSection = SyncDevicesSectionModel(title: "READ".localizedString)
        
        switch type {
        case .parameters(let nodes, let parameters):
            if parameters.isEmpty {
                return
            }
            nodes.forEach { node in
                var steps: [SyncDeviceStepModel] = []
                parameters.forEach { type in
                    switch type {
                    case .pwmFrequency:
                        let taskModel = SyncDeviceStepTaskModel(name: "pwm_frequency".localizedString, operationType: .read(node: node, type: .deviceReadParmeters(parameterType: .pwmFrequency)))
                        
                        let step = SyncDeviceStepModel(type: "pwm_frequency".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .ratedPower:
                        
                        let taskModel = SyncDeviceStepTaskModel(name: "rated_power".localizedString, operationType: .read(node: node, type: .deviceReadParmeters(parameterType: .ratedPower)))
                        
                        let step = SyncDeviceStepModel(type: "rated_power".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .motionSensitivityRange:
                        let taskModel = SyncDeviceStepTaskModel(name: "absolute_sensitivity".localizedString, operationType: .read(node: node, type: .deviceReadParmeters(parameterType: .motionSensitivityRange)))
                        
                        let step = SyncDeviceStepModel(type: "absolute_sensitivity".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    default:
                        break
                    }
                }
                
                let deviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                deviceModel.steps = steps
                steps.forEach({
                    $0.parentDeviceModel = deviceModel
                })
                readSection.devices.append(deviceModel)
            }
        case .harvestData(let nodes):
            nodes.forEach { node in
                let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                model.operationType = .read(node: node, type: .deviceReadParmeters(parameterType: .totalDeviceEnergyUse))
                model.missingData = node.phaseEnergyConsumptions.isEmpty
                if model.missingData {
                    model.state = .failed
                }
                readSection.devices.append(model)
            }
        }
        
        if readSection.devices.count > 0 {
            self.sections.append(readSection)
        }
        for (index, section) in self.sections.enumerated() {
        
            section.devices.forEach({
                $0.parentSectionIndex = index
            })
            if self.readState == .failure {
                section.allModels.forEach({
                    $0.isFineshed = true
                    $0.state = .failed
                })
            }
        }
        
    }
    
    
    /// 返回
    @objc private func backAction() {
        if backActionCallback != nil {
           
            backActionCallback?(getReadFailedDatas())
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    /// 获取失败数据list
    private func getReadFailedDatas() -> [ReadFailedData] {
        
        // 失败的设备数据list
        var failedDatas: [ReadFailedData] = []
        if let section = self.sections.first {
            let failedDevices = section.devices.filter({ $0.state == .failed })
            // 判断哪些设备有失败
            if failedDevices.count > 0 {
                var allNodes: [Node] = []
                switch type {
                case .parameters(let nodes, _):
                    allNodes = nodes
                case .harvestData(let nodes):
                    allNodes = nodes
                }
                // 获取读取失败的设备参数类型
                failedDevices.forEach { deviceModel in
                    if let node = allNodes.first(where: { $0.primaryUnicastAddress == deviceModel.address }) {
                        
                        var actionTypes: [ActionType] = []
                        if let operationType = deviceModel.operationType, case .read(_, let type) = operationType {
                            
                            actionTypes.append(type)
                        }else {
                            deviceModel.steps.forEach { step in
                                let list: [ActionType] = step.tasks.compactMap { task in
                                    if case .read(_, let type) = task.operationType, task.state == .failed {
                                        return type
                                    }
                                    return nil
                                }
                                actionTypes.append(contentsOf: list)
                            }
                        }
                        
                        let parameterTypes: [DeviceReadParameterType] = actionTypes.compactMap({ type in
                            switch type {
                            case .deviceReadParmeters(let parameterType):
                                return parameterType
                            default:
                                return nil
                            }
                        })
                        failedDatas.append(ReadFailedData(node: node, parameterTypes: parameterTypes))
                    }
                }
            }
        }
        return failedDatas
    }
    
    @objc private func rightItemAction() {
        if readState == .inRead { // stop
            
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
            readState = .failure
        }else if readState == .failure {
            
//            let failedModels = sections.filter({ $0.allModels.contains(where: { $0 is SyncDevicesModel && ($0.state == .failed || $0.state == .repeatedFailure) }) })
            
            var selectModels: [SyncDevicesModel] = []
            
            sections.forEach({
                let models = $0.allModels.filter({ (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed && !($0 as! SyncDevicesModel).missingData }) as! [SyncDevicesModel]
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
                readState = .inRead
                startRead()
            }
//            navigationItem.rightBarButtonItem = "stop".localizedString
        }
        updateSyncStateUI()
        
//        startSync()
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        
//        var failedModels: [SyncDevicesModel] = []
        var reReadEnabled = false
        sections.forEach({
            let models = $0.allModels.filter({ ($0 is SyncDevicesModel || $0 is SyncDevicesGroupModel) && $0.state == .failed && !(($0 as? SyncDevicesModel)?.missingData ?? false) })
//            failedModels.append(contentsOf: models)
            models.forEach({
                ($0 as? SyncDevicesModel)?.isSelected = sender.isSelected
                ($0 as? SyncDevicesGroupModel)?.isSelected = sender.isSelected
            })
            if !reReadEnabled, models.count > 0 {
                reReadEnabled = true
            }
        })
        navigationItem.rightBarButtonItem?.isEnabled = reReadEnabled
        tableView.reloadData()
    }
    
    /// 使用缺失的数据（设备能耗）
    @objc private func useIncompleteDataBtnAction() {
        harvestEnergyUseIncompleteDataCallback?(getReadFailedDatas())
        backAction()
    }
    
    /// 放弃读取的数据（设备能耗）
    @objc private func abandonAllDataBtnAction() {
        backAction()
    }
    
    /// 更新状态UI
    private func updateSyncStateUI() {

        var devices: [SyncDevicesModel] = []
        if let section = sections.first {
            devices = section.devices
        }
        progressLabel.text = "\(devices.filter({ $0.state == .successful }).count)/\(devices.count)"
        
        if case .harvestData = type {
            useIncompleteDataBtn.isHidden = readState != .failure
            abandonAllDataBtn.isHidden = readState != .failure

            if devices.contains(where: { !$0.missingData }) {
                useIncompleteDataBtn.backgroundColor = .white
                useIncompleteDataBtn.isUserInteractionEnabled = true
            }else {
                useIncompleteDataBtn.backgroundColor = RGB(220, 220, 220)
                useIncompleteDataBtn.isUserInteractionEnabled = false
            }
        }
        
        switch readState {
        case .inRead:
            navigationItem.rightBarButtonItem?.title = "STOP".localizedString
            navigationItem.rightBarButtonItem?.isEnabled = true
            bottomView.isHidden = false
            selectAllBtn.isHidden = true
            tableView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: 0, right: 0)
            backBtn.isHidden = true
        case .success:
            bottomView.isHidden = true
            navigationItem.rightBarButtonItem = UIBarButtonItem()
            backBtn.isHidden = false
        case .failure:
            if case .harvestData = type {
                navigationItem.rightBarButtonItem?.title = "re-harvest".localizedString
            }else {
                navigationItem.rightBarButtonItem?.title = "re_read".localizedString
            }
            
            bottomView.isHidden = false
            selectAllBtn.isHidden = false
            backBtn.isHidden = false
            var failedModels: [SyncDevicesModel] = []
            
            var selectModels: [SyncDevicesModel] = []
            
             sections.forEach({
                 
                 let failedDevices = $0.allModels.filter({ $0 is SyncDevicesModel && $0.state == .failed && !($0 as! SyncDevicesModel).missingData  }) as! [SyncDevicesModel]
                 failedModels.append(contentsOf: failedDevices)
                 
                 let selectDevices = $0.allModels.filter({ (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed && !($0 as! SyncDevicesModel).missingData }) as! [SyncDevicesModel]
                 
                 selectModels.append(contentsOf: selectDevices)
            })
            if failedModels.count > 0 {
                selectAllBtn.isSelected = selectModels.count > 0 && selectModels.count == failedModels.count
            }else {
                selectAllBtn.isHidden = true
            }
            if bottomView.frame == .zero {
                bottomView.layoutIfNeeded()
            }
            tableView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: 0, bottom: bottomView.height, right: 0)
            navigationItem.rightBarButtonItem?.isEnabled = selectModels.count > 0
        }
        
    }
    
    private func startRead() {
        
            
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
            
            let semaphore = DispatchSemaphore(value: 0)
            while let model = self.getNextHandleModel() {
                
                guard MeshLibManager.manager.isOpenBluetooth else {
                    self.sections.forEach { section in
                        section.allModels.forEach({
                            $0.state = .failed
                            $0.isFineshed = true
                        })
                    }
                    self.readState = .failure
                    
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
                    deviceModel.state = .inSettings
                    if let groupModel = deviceModel.parentGroupModel {
                        groupModel.isShow = true
                        if self.lastGroupModel != groupModel {
                            
                            if self.lastGroupModel != nil {
                                self.lastGroupModel?.isShow = false
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
                
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, ackMessageTimeout: 10, progressBack: nil, successfulBack: { handle, statusMessage in
                    // 判断如果是设备初始化消息，则需要再初始化完成后完成基本配置
                    if statusMessage is ConfigCompositionDataStatus || statusMessage is ConfigAppKeyStatus {
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address), node.isInitialize {
                            MeshProxyMessageCommand.shared.addMessage(messageHandles: node.getConfigMessageHandles(), finishedBack: nil)
                        }
                    }
                }, failedBack: nil) {[weak self] resultMessageHandles in
                    
                    resultMessageHandles.forEach { handle in
                        if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                            node.updateData(message: handle.message, isSuccess: handle.isSuccessful)
                        }
                    }
                    let resultSuccessful = !resultMessageHandles.contains(where: { !$0.isSuccessful })
                    let operationSuccessful = ((model as? SyncDevicesModel)?.operationType?.isSuccessful ?? (model as? SyncDeviceStepTaskModel)?.operationType.isSuccessful) ?? false
                    if resultSuccessful && operationSuccessful {
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
                    if let section = self.sections.first {
                        self.progressLabel.text = "\(section.devices.filter({ $0.state == .successful }).count)/\(section.devices.count)"
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
            self.readState = self.sections.contains(where: { $0.allModels.contains(where: { $0.state == .failed }) }) ? .failure : .success
            
            DispatchQueue.main.async {
                self.tableView.reloadData()
                self.updateSyncStateUI()
                // 通知space数据修改
//                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                if self.readState == .success {
                    // 同步完成回调
                    self.readSuccessCallback?(self.type)
                    if let progressView = SyncDevicesProgressView.current() {
                        progressView.hide()
                    }
                }else {
                    if let progressView = SyncDevicesProgressView.current() {
                        progressView.reload()
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
        DispatchQueue.main.async {
//            self.tableView.reloadSections(IndexSet(integer: sectionIndex), with: .none)
            self.tableView.reloadData()
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
        
        useIncompleteDataBtn = UIButton(title: "use_incomplete_data".localizedString, titleSize: 13, titleWeight: .light, titleColor: RGB(27, 20, 37), target: self, action: #selector(useIncompleteDataBtnAction))
        useIncompleteDataBtn.backgroundColor = .white
        useIncompleteDataBtn.layer.cornerRadius = 10
        useIncompleteDataBtn.layer.borderWidth = 0.5
        useIncompleteDataBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        useIncompleteDataBtn.isHidden = true
        view.addSubview(useIncompleteDataBtn)
        useIncompleteDataBtn.snp.makeConstraints { make in
            make.right.equalTo(view.snp.centerX).offset(SCRXFrom(-7.5))
            make.bottom.equalTo(bottomView.snp.top).offset(SCRYFrom(-10))
            make.width.equalTo(SCRXFrom(164))
            make.height.equalTo(SCRYFrom(40))
        }
        
        abandonAllDataBtn = UIButton(title: "abandon_all_data".localizedString, titleSize: 13, titleWeight: .light, titleColor: RGB(27, 20, 37), target: self, action: #selector(abandonAllDataBtnAction))
        abandonAllDataBtn.backgroundColor = .white
        abandonAllDataBtn.layer.cornerRadius = 10
        abandonAllDataBtn.layer.borderWidth = 0.5
        abandonAllDataBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        abandonAllDataBtn.isHidden = true
        view.addSubview(abandonAllDataBtn)
        abandonAllDataBtn.snp.makeConstraints { make in
            make.left.equalTo(view.snp.centerX).offset(SCRXFrom(7.5))
            make.centerY.width.height.equalTo(useIncompleteDataBtn)
        }
        
    }

}

extension ReadDevicesDataViewController: UITableViewDataSource, UITableViewDelegate {
    
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
//        case is SyncDevicesGroupModel:
//            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! SyncDevicesGroupViewCell
//            cell.groupModel = cellModel as? SyncDevicesGroupModel
//            cell.delegate = self
//            return cell
//        case is SyncDevicesSwitchProxyModel:
//            let cell = tableView.dequeueReusableCell(withIdentifier: "groupCell", for: indexPath) as! SyncDevicesGroupViewCell
//            cell.arrowImageView.isHidden = true
//            cell.stateImageView.isHidden = true
//            cell.selectBtn.isHidden = true
//            if cellModel.isFineshed {
//                cell.iconImageBtn.snp.updateConstraints { make in
//                    make.left.equalTo(SCRXFrom(48))
//                }
//            }else {
//                cell.iconImageBtn.snp.updateConstraints { make in
//                    make.left.equalTo(SCRXFrom(16))
//                }
//            }
//            let proxyModel = cellModel as? SyncDevicesSwitchProxyModel
//            cell.nameLabel.text = proxyModel?.name
//            cell.iconImageBtn.setImage(UIImage(named: proxyModel?.imageName ?? ""), for: .normal)
//            return cell
//            
        case let deviceModel as SyncDevicesModel:
            let cell = tableView.dequeueReusableCell(withIdentifier: "deviceCell", for: indexPath) as! SyncDeviceViewCell
            cell.model = deviceModel
            if case .harvestData = type, deviceModel.missingData {
                cell.stateImageView.image = UIImage(named: "rated_power_noset")
                cell.resyncBtn.isHidden = true
                cell.stateImageView.isUserInteractionEnabled = true
                cell.selectedImageView.isHidden = true
            }else {
                cell.stateImageView.isUserInteractionEnabled = false
            }
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
//        switch section {
//        case 0:
//            return SCRYFrom(32)
//        default:
//            return SCRYFrom(40)
//        }
        return 0.01
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
                if deviceModel.state == .successful || (deviceModel.state == .failed && !deviceModel.missingData) {
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
                self?.readState = .inRead
                self?.updateSyncStateUI()
                self?.startRead()
            } hide: {[weak self] in
                self?.showProressStepModel = nil
            }
            self.showProressStepModel = stepModel
        }
        
    }

}

extension ReadDevicesDataViewController: SyncDeviceViewCellDelegate {
    
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
        updateSyncStateUI()
    }
    
    /// 图标点击回调
    func cell(_ cell: SyncDeviceViewCell, iconClickAction model: SyncDevicesModel) {
        MeshAPI.identify(address: model.address)
    }
    
    /// 失败重试回调
    func cell(_ cell: SyncDeviceViewCell, resyncAction model: SyncDevicesModel) {
        model.state = .none
        readState = .inRead
        updateSyncStateUI()
        startRead()
    }
    
    /// 状态图标点击回调
    func cell(_ cell: SyncDeviceViewCell, stateImageClickAction model: SyncDevicesModel) {
        if model.missingData {
            SRAlertView(message: "rated_power_no_set_message".localizedString, actions: [SRAlertAction(title: "GOT IT".localizedString, titleColor: Bar_Color)]).show()
        }
    }
    
}

extension ReadDevicesDataViewController: SyncDeviceStepViewCellDelegate {
    
    /// 重新同步事件回调
    func cell(_ cell: SyncDeviceStepViewCell, resyncAction model: SyncDeviceStepModel) {
        
        model.tasks.forEach({
            if $0.state == .failed {
                $0.state = .none
            }
        })
        readState = .inRead
        updateSyncStateUI()
        startRead()
    }
    
}

extension ReadDevicesDataViewController {
    
    /// 读取数据类型
    enum ReadType {
        /// 设备参数  parameters: 读取的对应设备参数list
        case parameters(nodes: [Node], parameters: [DeviceReadParameterType])
        /// 能耗数据
        case harvestData(nodes: [Node])
    }
    
    /// 读取状态
    enum ReadState {
        /// 读取中
        case inRead
        /// 读取失败
        case failure
        /// 读取成功
        case success
    }
    
}


fileprivate extension SyncDevicesModel {
    
    static var missingDataKey = 1
    
    /// 是否缺失数据（如缺少额定功率设置，导致读取能耗前置条件缺失）
    var missingData: Bool {
        get {
            objc_getAssociatedObject(self, &SyncDevicesModel.missingDataKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &SyncDevicesModel.missingDataKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
