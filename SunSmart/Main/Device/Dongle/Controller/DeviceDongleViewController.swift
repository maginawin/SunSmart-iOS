//
//  DeviceDongleViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/21.
//

import UIKit
import NordicSigMeshSDK

class DeviceDongleViewController: UIViewController, DeviceProtocol {

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var lineView: UIView!
    private var btnLineView: UIView!
    private var deleteBtn: UIButton!
    private var saveBtn: UIButton!
    private var createBtn: UIButton!
    private var promptView: DevicePromptHudView?
    private var offlineView: DeviceOfflinePromptView!
    
    private weak var headerView: DeviceSwitchHeaderView?
    private weak var scheduleHeaderView: DeviceDongleScheduleHeaderView?
    
    private var sections: [SectionType] = [.info, .collectionSchedule, .collectionStrategy, .storageUsage]
    private var infos: [InfoType] = [.bindDevice, .timeAuthority, .collectionEnable]
    
    let space: SpaceData
    /// dongle数据（编辑时传入）
    var dongleData: DeviceDongleData?
    /// 编辑过程的dongle备份数据
    private var setDongleData: DeviceDongleData!
    
    /// 是否可以编辑
    private var editable: Bool = true
    
    /// 是否正在编辑日程
    private var editSchedules: Bool = false
    
    /// dongleData为空时创建dongle
    init(space: SpaceData, dongleData: DeviceDongleData?) {
        
        self.space = space
        self.dongleData = dongleData
        super.init(nibName: nil, bundle: nil)
        
        self.setDongleData = dongleData?.copy() ?? DeviceDongleData.default()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        view.backgroundColor = Background_Color
        title = "dongle".localizedString
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        editable = space.deviceOperates.contains(.edit)
        setupUI()
        updateUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    private func getNodeState() {
        
        // TODO: 获取设备内存信息
        
    }
    
    
    // MARK: Actions
    
    @objc private func back() {
        if !(setDongleData == (dongleData ?? DeviceDongleData.default(id: setDongleData.id))) {
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "EXIT".localizedString, actionHandler: {[weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    //                        self?.fineshed()
                    self?.dismiss(animated: true)
                }
            })]).show()
            view.endEditing(true)
        }else {
            self.dismiss(animated: true)
        }
    }
    
    @objc private func deleteBtnAction() {
        
        // 检查是否绑定设备
        guard dongleData?.bindNode != nil else {

            if dongleData != nil {
                MeshNetworkManager.instance.deleteDongle(dongleData: dongleData!)
            }
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.dismiss(animated: true)
            }
            return
        }
        
        DeviceDongleDeleteAlertView(deleteCallback: { mode in
            switch mode {
            case .retainStoredData:
                print("删除但保留数据")
            case .clearAllStoredData:
                print("删除并清空数据")
            }
        }).show()
    }
    
    @objc private func saveBtnAction() {
        
        // 是否创建开关
        var isCreate = false
        if self.dongleData != nil {
            self.dongleData?.update(dongleData: setDongleData)
        }else {
            isCreate = true
            MeshNetworkManager.instance.dongles.append(setDongleData)
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        }
        setDongleData.save()
        
        // 是否需要同步数据
        guard setDongleData.needSyncData else {
            
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                if isCreate { // 首次创建提示是否绑定设备
                    
                    SRAlertView(title: "dongle_bind_device".localizedString, message: "dongle_bind_device_message".localizedString, actions: [SRAlertAction(title: "Later".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                        // 下次创建
                        self?.dismiss(animated: true)
                    }), SRAlertAction(title: "Bind".localizedString, actionHandler: {[weak self] _ in
                        guard let self = self else { return }
                        self.dongleData = self.setDongleData.copy()
                        self.updateUI()
                        // 绑定设备
                        self.bindDevice()
                    })]).show()
                    
                }else {
//                    self?.dismiss(animated: true)
                    self?.updateUI()
                }
            }
            
            return
        }
        
        let vc = SyncDevicesViewController(type: .dongle(setDongleData))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                if isCreate {
                    self?.dismiss(animated: true)
                }else {
                    self?.updateSaveEnabledState()
                    self?.tableView.reloadData()
                    self?.navigationController?.popViewController(animated: true)
                }
            }
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            if isCreate {
                self.dismiss(animated: true)
            }else {
                self.navigationController?.popViewController(animated: true)
                self.updateSaveEnabledState()
                self.tableView.reloadData()
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 重新同步
    private func dongleReSync() {
        guard let dongleData = self.dongleData else { return }
        let vc = SyncDevicesViewController(type: .dongle(dongleData), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            self.navigationController?.popViewController(animated: true)
            
            self.updateSaveEnabledState()
            self.tableView.reloadData()
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            self.updateSaveEnabledState()
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc private func hideKeyboard() {
        view.endEditing(true)
    }
    
    /// 删除设备
    private func deleteNode(node: Node) {
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        let deletionContext = DevicePermanentDeletionContext(node: node)
        MeshAPI.resetNode(address: node.primaryUnicastAddress) {[weak self] _ in
            
            XWHUDManager.hide()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            deletionContext.commit()
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                self?.back()
            }
            
        } resetFail: { _, _ in
            
            let alertView = SRAlertView(title: "notification".localizedString, actions: [.cancelAction, SRAlertAction(title: "force_delete".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                deletionContext.commit()
                MeshNetworkManager.instance.meshNetwork?.remove(node: node)
                
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                    // 通知space数据修改
//                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                    self?.back()
                }
            })])
            let messageAttStr = NSMutableAttributedString(string: "device_force_delete_message".localizedString, attributes: [.foregroundColor: TextBlack_Color])
            messageAttStr.append(NSAttributedString(string: "device_force_delete_note".localizedString, attributes: [.foregroundColor: Message_Color]))
            alertView.messageLabel.attributedText = messageAttStr
            alertView.show()
            
        }

    }
    
    @objc private func repairBtnClick() {
        guard let node = self.dongleData?.bindNode else {
            return
        }
        self.repairDevices(nodes: [node]) {[weak self] _, _ in
            if node.isKeybindComplete {
                self?.getNodeState()
                self?.updateUI()
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
        }
    }
    
    /// 绑定真实设备
    private func bindDevice() {
        
//        dongle_bind_device
        let vc = DeviceAddViewController(space: space)
        vc.forceBindToDongle = dongleData
        vc.deviceAddCallback = {[weak self] _ in
//            if let dongle = nodes.first(where: { $0.deviceType == .dongle })
            self?.updateUI()
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    // MARK: - UI
    
    private func updateUI() {
        
        if let dongleData = self.dongleData {
            if let node = dongleData.bindNode {
                if node.isKeybindComplete {
                    view.hideEmptyDataView()
                    guard node.state else { // 离线
                        offlineView.isHidden = false
                        return
                    }
                    offlineView.isHidden = true
                }else {
                    
                    if view.emptyView == nil {
                        view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                            // 修复
                            self?.repairBtnClick()
                        }
                        if let emptyView = view.emptyView {
                            if editable { // 是否有编辑设备权限
                                emptyView.button.snp.updateConstraints { make in
                                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                                }
                            }else {
                                emptyView.button.isHidden = true
                            }
                        }
                    }
                    
                }
            }
            
            createBtn.isHidden = true
            deleteBtn.isHidden = false
            btnLineView.isHidden = false
            saveBtn.isHidden = false
            
        }else {
            createBtn.isHidden = false
            deleteBtn.isHidden = true
            btnLineView.isHidden = true
            saveBtn.isHidden = true
        }
        
        // 未显示任何状态
        if view.emptyView == nil {
            if setDongleData.collectionEnable || !offlineView.isHidden {
                promptView?.isHidden = true
            }else {
                promptView?.isHidden = false
            }
        }
        updateSaveEnabledState()
    }
    
    /// 更新保存按钮状态
    private func updateSaveEnabledState() {
        // 名称是否合法
        let nameValid = !(setDongleData.name.isAllInputTextEmpty() || MeshNetworkManager.instance.isSwitchTautonym(name: setDongleData.name) && setDongleData.name != dongleData?.name)
        
        if !nameValid || (dongleData != nil && setDongleData == dongleData!) { // 未改动
            createBtn.isUserInteractionEnabled = false
            createBtn.setTitleColor(Message_Color, for: .normal)
            
            saveBtn.isUserInteractionEnabled = false
            saveBtn.setTitleColor(Message_Color, for: .normal)
        }else {
            createBtn.isUserInteractionEnabled = true
            createBtn.setTitleColor(Bar_Color, for: .normal)
            
            saveBtn.isUserInteractionEnabled = true
            saveBtn.setTitleColor(Bar_Color, for: .normal)
        }
        
        self.isModalInPresentation = !(setDongleData == (dongleData ?? DeviceDongleData.default(id: setDongleData.id)))
    }
    
    private func reloadSection(sectionType: SectionType) {
        if let sectionIndex = sections.firstIndex(of: sectionType) {
            tableView.reloadSections(IndexSet(integer: sectionIndex), with: .none)
        }
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }
        
        deleteBtn = UIButton(title: "alert_item_delete".localizedString, titleSize: 16, titleWeight: .light, titleColor: Red_Color, target: self, action: #selector(deleteBtnAction))
        bottomView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
            make.right.equalTo(bottomView.snp.centerX)
        }
        
        btnLineView = UIView()
        btnLineView.backgroundColor = Line_Color1
        bottomView.addSubview(btnLineView)
        btnLineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(deleteBtn)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(40))
        }
        
        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(saveBtnAction))
        bottomView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.top.equalToSuperview()
            make.left.equalTo(bottomView.snp.centerX)
            make.height.equalTo(deleteBtn)
        }
        
        createBtn = UIButton(title: "CREATE".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(saveBtnAction))
        createBtn.isHidden = true
        bottomView.addSubview(createBtn)
        createBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(deleteBtn)
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.backgroundColor = Background_Color
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(40), right: 0)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "infoCell")
        tableView.register(DeviceDongleScheduleViewCell.classForCoder(), forCellReuseIdentifier: "scheduleCell")
        tableView.register(DeviceDongleScheduleEmptyCell.classForCoder(), forCellReuseIdentifier: "scheduleEmptyCell")
        tableView.register(DeviceDongleCollectionStrategyCell.classForCoder(), forCellReuseIdentifier: "strategyCell")
        tableView.register(DeviceDongleStorageUsageCell.classForCoder(), forCellReuseIdentifier: "storageUsageCell")
        tableView.register(DeviceSwitchHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "infoHeader")
        tableView.register(DeviceDongleScheduleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "scheduleHeader")
        tableView.register(DeviceDongleSectionHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "titleHeader")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        tableView.keyboardDismissMode = .onDrag
        let tap = UITapGestureRecognizer(target: self, action: #selector(hideKeyboard))
        tap.cancelsTouchesInView = false
        tableView.addGestureRecognizer(tap)
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaInsets.top)
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            if editable {
                make.bottom.equalTo(bottomView.snp.top)
            }else {
                make.bottom.equalToSuperview()
            }
        }
        
        promptView = DevicePromptHudView()
        view.addSubview(promptView!)
        promptView!.snp.makeConstraints { make in
            make.bottom.equalTo(bottomView.snp.top).offset(SCRYFrom(-2))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
        }
        
        offlineView = DeviceOfflinePromptView()
        offlineView.isHidden = true
        view.addSubview(offlineView)
        offlineView.snp.makeConstraints { make in
            make.left.right.bottom.equalTo(promptView!)
            make.height.equalTo(SCRYFrom(44))
        }
    }

}

extension DeviceDongleViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        switch sections[section] {
        case .info:
            return infos.count
        case .collectionSchedule:
            return max(setDongleData.schedules.count, 1)
        case .collectionStrategy:
            return 1
        case .storageUsage:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = sections[indexPath.section]
        var returnCell: UITableViewCell!
        switch section {
        case .info:
            let cell = tableView.dequeueReusableCell(withIdentifier: "infoCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            switch infos[indexPath.row] {
            case .bindDevice:
        
                cell.titleLabel.text = "bind_device".localizedString
                if let node = setDongleData.bindNode {
                    cell.cellStyle = .none
                    cell.contentLabel.text = node.macAddressResult
                }else {
                    cell.cellStyle = .none
                    var notBindMessage: String?
                    if dongleData != nil {
                        cell.cellStyle = .arrow
                        notBindMessage = "dongle_edit_not_bind".localizedString
                    }else {
                        notBindMessage = "dongle_create_not_bind".localizedString
                    }
                    cell.contentLabel.text = notBindMessage
                }
        
            case .timeAuthority:
                cell.cellStyle = .switch
                cell.titleLabel.text = "time_authority".localizedString
                cell.enabledSwitch.isOn = setDongleData.timeAuthority
                cell.switchActionCallback = {[weak self] isOn in
                    cell.enabledSwitch.isOn = isOn
                    guard let self = self else { return }
                    self.setDongleData.timeAuthority = isOn
                    self.updateSaveEnabledState()
                }
            case .collectionEnable:
                cell.cellStyle = .switch
                cell.titleLabel.text = "collection_enable".localizedString
                cell.enabledSwitch.isOn = setDongleData.collectionEnable
                cell.switchActionCallback = {[weak self] isOn in
                    cell.enabledSwitch.isOn = isOn
                    guard let self = self else { return }
                    self.setDongleData.collectionEnable = isOn
                    if self.offlineView.isHidden {
                        self.promptView?.isHidden = isOn
                    }
                    self.updateSaveEnabledState()
                }
            }
            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
            cell.backgroundColor = .clear
            cell.selectionStyle = .none
            returnCell = cell
        case .collectionSchedule:
            if setDongleData.schedules.isEmpty {
                let emptyCell = tableView.dequeueReusableCell(withIdentifier: "scheduleEmptyCell", for: indexPath) as! DeviceDongleScheduleEmptyCell
                returnCell = emptyCell
            }else {
                let schedule = setDongleData.schedules[indexPath.row]
                let scheduleCell = tableView.dequeueReusableCell(withIdentifier: "scheduleCell", for: indexPath) as! DeviceDongleScheduleViewCell
                scheduleCell.schedule = schedule
                returnCell = scheduleCell
            }
        case .collectionStrategy:
            let cell = tableView.dequeueReusableCell(withIdentifier: "strategyCell", for: indexPath) as! DeviceDongleCollectionStrategyCell
            returnCell = cell
        case .storageUsage:
            let cell = tableView.dequeueReusableCell(withIdentifier: "storageUsageCell", for: indexPath) as! DeviceDongleStorageUsageCell
            if let node = dongleData?.bindNode {
                cell.clearBtn.isHidden = false
                cell.progressLabel.isHidden = false
                cell.progressView.progress = 50
            }else {
                cell.clearBtn.isHidden = true
                cell.progressLabel.isHidden = true
            }
            returnCell = cell
        }
        returnCell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        return returnCell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        
        let sectionType = sections[section]
        switch sectionType {
        case .info:
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "infoHeader") as! DeviceSwitchHeaderView
            headerView.nameField.text = setDongleData.name
            headerView.nameField.isEnabled = editable
            headerView.syncFailedBtn.isHidden = dongleData == nil || !dongleData!.needSyncData
            headerView.nameEditChanged = {[weak self] name in
                self?.setDongleData.name = name
                self?.updateSaveEnabledState()
                if name.count > 32 {
                    return "text_length_exceeded".localizedString
                }
                // 重名
                if name.count > 0 && MeshNetworkManager.instance.isDongleTautonym(name: name) && name != self?.dongleData?.name {
                    return "name_already_exists".localizedString
                }
                return nil
            }
            headerView.reSyncCallback = {[weak self] in
                self?.dongleReSync()
            }
            self.headerView = headerView
            return headerView
        case .collectionSchedule:
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "scheduleHeader") as! DeviceDongleScheduleHeaderView
            headerView.isEdit = editSchedules
            headerView.deleteBtn.isEnabled = setDongleData.schedules.contains(where: { $0.selectState == .selected })
            if setDongleData.schedules.count > 0 {
                headerView.addBtn.setTitle("＋", for: .normal)
                headerView.addBtn.snp.updateConstraints { make in
                    make.right.equalTo(0)
                }
                headerView.minusBtn.isHidden = editSchedules
            }else {
                headerView.addBtn.setTitle("\("Add".localizedString) ＋", for: .normal)
                headerView.addBtn.snp.updateConstraints { make in
                    make.right.equalTo(SCRXFrom(-12))
                }
                headerView.minusBtn.isHidden = true
            }
            if let timestamp = dongleData?.firstCollectionTimestamp {
                headerView.startCollectLabel.isHidden = false
                headerView.startCollectLabel.text = "\("start_from".localizedString) \(String.dateConvert(timestamp: "\(timestamp)", dateFormat: "M/d/yyyy hh:mm a"))"
            }else {
                headerView.startCollectLabel.isHidden = true
            }
            headerView.delegate = self
            scheduleHeaderView = headerView
            return headerView
            
        case .collectionStrategy, .storageUsage:
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "titleHeader") as! DeviceDongleSectionHeaderView
            if sectionType == .collectionStrategy {
                headerView.titleLabel.text = "collection_strategy".localizedString
                headerView.contentLabel.text = nil
            }else {
                headerView.titleLabel.text = "storage_usage".localizedString
                headerView.contentLabel.text = "0M/0M " + "used".localizedString
            }
            return headerView
        }
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let sectionType = sections[section]
        switch sectionType {
        case.info:
            return SCRYFrom(93)
        case .collectionSchedule:
            if setDongleData.firstCollectionTimestamp != nil {
                return SCRYFrom(59)
            }else {
                return SCRYFrom(40)
            }
        default:
            return SCRYFrom(40)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let sectionType = sections[indexPath.section]
        switch sectionType {
        case .info, .collectionSchedule:
            return SCRYFrom(44)
        case .collectionStrategy, .storageUsage:
            return SCRYFrom(80)
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let sectionType = sections[indexPath.section]
        switch sectionType {
        case .info:
            if infos[indexPath.row] == .bindDevice {
                guard dongleData != nil, dongleData?.bindNode == nil else {
                    return
                }
                // 绑定真实设备
                // 未修改数据
                if setDongleData == dongleData! { // 绑定设备
                    bindDevice()
                }else { // 提示需要先保存数据
                    SRAlertView(title: "notification".localizedString, message: "changled_parameter_not_saved".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
                }
            }
        case .collectionSchedule:
            guard setDongleData.schedules.count > 0 else {
                return 
            }
            let schedule = setDongleData.schedules[indexPath.row]
            // 选择
            if editSchedules {
                if schedule.selectState == .unselect {
                    schedule.selectState = .selected
                }else if schedule.selectState == .selected {
                    schedule.selectState = .unselect
                }
                tableView.reloadRows(at: [indexPath], with: .none)
                scheduleHeaderView?.deleteBtn.isEnabled = setDongleData.schedules.contains(where: { $0.selectState == .selected })
            }else { // 编辑
                
                let editScheduleVc = DongleAddCollectionScheduleController(dongleData: setDongleData, schedule: schedule)
                editScheduleVc.scheudleDoneCallback = {[weak self] editSchedule in
                    guard let self = self else { return }
                    schedule.updateData(schedule: editSchedule)
                    self.setDongleData.schedules.sort(by: { $0.timestamp < $1.timestamp })
                    tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
//                    tableView.reloadRows(at: [indexPath], with: .none)
                }
                navigationController?.pushViewController(editScheduleVc, animated: true)
            }
            
        default:
            break
        }
    }
    
}

extension DeviceDongleViewController: DeviceDongleScheduleHeaderViewDelegate {
    
    /// 编辑/取消编辑回调
    func headerView(_ headerView: DeviceDongleScheduleHeaderView, didEditAction edit: Bool) {
        editSchedules = edit
        setDongleData.schedules.forEach({
            if edit {
                $0.selectState = .unselect
            }else {
                $0.selectState = .none
            }
        })
        reloadSection(sectionType: .collectionSchedule)
    }
    
    /// 点击添加日程回调
    func headerViewAddAction(_ headerView: DeviceDongleScheduleHeaderView) {
        
        guard setDongleData.schedules.count < 16 else {
            XWHUDManager.showTipHUD("schedules_overrun_message".localizedString, isLineFeed: true)
            return
        }
        
        let vc = DongleAddCollectionScheduleController(dongleData: setDongleData, schedule: nil)
        vc.scheudleDoneCallback = {[weak self] schedule in
            guard let self = self else { return }
            self.setDongleData.schedules.append(schedule)
            self.setDongleData.schedules.sort(by: { $0.timestamp < $1.timestamp })
            self.reloadSection(sectionType: .collectionSchedule)
//            if let sectionIndex = self.sections.firstIndex(of: .collectionSchedule) {
//                self.tableView.insertRows(at: [IndexPath(row: self.setDongleData.schedules.count - 1, section: sectionIndex)], with: .automatic)
//            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 点击删除日程回调
    func headerViewDeleteAction(_ headerView: DeviceDongleScheduleHeaderView) {
        guard self.editSchedules else {
            return
        }
        
        setDongleData.schedules.removeAll(where: { $0.selectState == .selected })
        reloadSection(sectionType: .collectionSchedule)
        updateSaveEnabledState()
    }
    
}

extension DeviceDongleViewController {
    
    /// section类型
    enum SectionType {
    /// 基本信息
    case info
        /// 采集日程
    case collectionSchedule
        /// 采集周期
    case collectionStrategy
        /// 存储信息
    case storageUsage
    }
   
    /// 基本信息类型
    enum InfoType {
        /// 绑定设备
        case bindDevice
        /// RTC时间
        case timeAuthority
        /// 采集开关
        case collectionEnable
    }
}

extension DeviceDongleData.CollectionSchedule {
    
    /// 选择状态
    enum SelectState {
        /// 无
    case none
        /// 未选择
    case unselect
        /// 已选择
    case selected
    }
    
    static var selectStateKey: UInt8 = 0
    
    /// 日程选择状态
    var selectState: SelectState {
        get {
            objc_getAssociatedObject(self, &DeviceDongleData.CollectionSchedule.selectStateKey) as? SelectState ?? .none
        }set {
            objc_setAssociatedObject(self, &DeviceDongleData.CollectionSchedule.selectStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
