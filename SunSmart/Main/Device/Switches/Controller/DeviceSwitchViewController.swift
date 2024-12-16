//
//  DeviceSwitchViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/6.
//

import UIKit
import NordicSigMeshSDK

class DeviceSwitchViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var lineView: UIView!
    private var btnLineView: UIView!
    private var deleteBtn: UIButton!
    private var saveBtn: UIButton!
    private var createBtn: UIButton!
    private weak var headerView: DeviceSwitchHeaderView?
    /// 是否可以编辑
    var editable: Bool = true
    
    var switchData: DeviceSwitchData?
    let space: SpaceData
//    private var enabled: Bool = false
    private var setSwitchData: DeviceSwitchData!
    
    private var sections: [[CellType]] = [[.id, .enable, .panel, .group, .scene, .proxy], [.keyInfo]]
    
    /// switchData为空时创建switch
    init(space: SpaceData, switchData: DeviceSwitchData?) {
        self.space = space
        self.switchData = switchData
        super.init(nibName: nil, bundle: nil)
        self.setSwitchData = switchData?.copy() ?? DeviceSwitchData.default()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        view.backgroundColor = Background_Color
        title = "switch".localizedString
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        setupUI()
        updateUI()
        updateSaveEnabledState()
    }
    
    deinit {
        if space.isConfiguring {
            space.isConfiguring = false
        }
    }
    
    private func fineshed() {
//        let spaceVc = UIViewController.getVisibleVc()?.presentingViewController
        if self.space.isConfiguring { // && (spaceVc?.isKind(of: SpaceViewController.classForCoder()) ?? false)
            self.dismiss(animated: false)
            let vc = SpaceNewCreationProcessController(space: self.space, options: .switch)
            NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
//            spaceVc?.present(NavigationViewController(rootViewController: vc), animated: true)
        }else {
            self.dismiss(animated: true)
        }
    }
    
    @objc private func back() {
//        if fineshed && self.space.isConfiguring && (UIViewController.getVisibleVc()?.isKind(of: SpaceViewController.classForCoder()) ?? false) {
//            self.dismiss(animated: false)
//            let vc = SpaceNewCreationProcessController(space: self.space, options: .switch)
//            UIViewController.getVisibleVc()?.present(NavigationViewController(rootViewController: vc), animated: true)
//            
//        }else {
        if !(setSwitchData == (switchData ?? DeviceSwitchData.default(id: setSwitchData.id))) {
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "exit".localizedString, actionHandler: {[weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    //                        self?.fineshed()
                    self?.dismiss(animated: true)
                }
            })]).show()
            view.endEditing(true)
        }else {
            self.dismiss(animated: true)
        }
//        }
    }
    
    private func updateUI() {
        if self.switchData == nil {
            createBtn.isHidden = false
            deleteBtn.isHidden = true
            btnLineView.isHidden = true
            saveBtn.isHidden = true
        }
    }
    
    @objc private func deleteBtnAction() {
        
        
        SRAlertView(title: "notification".localizedString, message: "switch_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            
            // 是否需要清空设备数据
            guard let self = self, let switchData = self.switchData, !switchData.getNeedSyncDatas(deleteSwitch: true).isEmpty() else {
                MeshNetworkManager.instance.deleteSwitch(switchData: self!.switchData!)
                
                // 空数据直接删除
                NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                    self?.fineshed()
                }
                return
            }
            self.deleteSwitchData()
        })]).show()
        
    }
    
    @objc private func saveBtnAction() {
        // 是否创建开关
        var isCreate = false
        if self.switchData != nil {
            // 切换代理/删除代理节点记录该代理地址
            var deleteProxyNodeAddress = setSwitchData.deleteProxyNodeAddress
            if self.switchData?.proxyNodeAddress != nil && self.switchData?.proxyNodeAddress != setSwitchData.proxyNodeAddress {
                deleteProxyNodeAddress = self.switchData?.proxyNodeAddress
            }
            setSwitchData.deleteProxyNodeAddress = deleteProxyNodeAddress
            self.switchData?.update(switchData: setSwitchData)
//            self.switchData?.deleteProxyNodeAddress = deleteProxyNodeAddress
        }else {
//            setSwitchData.save()
            isCreate = true
            MeshNetworkManager.instance.switchs.append(setSwitchData)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        
        // 未创建动能开关通讯组
        if (setSwitchData.proxyNodeAddress != nil || setSwitchData.bindGroups.contains(where: { $0.nodes.count > 0 })) && setSwitchData.linkGroup == nil {
            guard let linkGroup = try? MeshAPI.createGroup(name: self.setSwitchData.name + "-Group", address: setSwitchData.linkGroupAddress, isVirtual: true) else {
                XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                return
            }
            self.setSwitchData.linkGroupAddress = linkGroup.address.address
            self.switchData?.linkGroupAddress = linkGroup.address.address
//            self.setSwitchData?.save()
        }
        
        let syncData = setSwitchData.getNeedSyncDatas()
        // 判断哪些移出的组需要同步数据，不需要同步数据则直接更新缓存，需要同步的组在同步操作后做数据更新
        let unbindGroupAddresses = syncData.deleteGroups.map({ $0.key.address.address })
        setSwitchData.unbindGroupAddresses = unbindGroupAddresses
        self.switchData?.update(switchData: setSwitchData)
        setSwitchData.save()
        
//        self.switchData?.unbindGroupAddresses = unbindGroupAddresses
//        self.switchData?.save()
        
        // 是否需要同步数据
        guard setSwitchData.needSyncData else {
            
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                if isCreate {
                    self?.fineshed()
                }else {
                    self?.updateSaveEnabledState()
                    self?.tableView.reloadData()
                    self?.navigationController?.popViewController(animated: true)
                }
            }
            
            return
        }
        
        let vc = SyncDevicesViewController(type: .enOceanSwitch(setSwitchData))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            if self.switchData != nil {
                self.setSwitchData.update(switchData: self.switchData!)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                if isCreate {
                    self?.fineshed()
                }else {
                    self?.updateSaveEnabledState()
                    self?.tableView.reloadData()
                    self?.navigationController?.popViewController(animated: true)
                }
            }
            
        }
        vc.backActionCallback = {[weak self] in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            if self.switchData != nil {
                self.setSwitchData.update(switchData: self.switchData!)
            }
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
    private func switchReSync() {
        guard let switchData = self.switchData, self.editable else {
            return
        }
        let vc = SyncDevicesViewController(type: .enOceanSwitch(switchData), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            self.navigationController?.popViewController(animated: true)
            self.setSwitchData.update(switchData: switchData)
            self.updateSaveEnabledState()
            self.tableView.reloadData()
        }
        vc.backActionCallback = {[weak self] in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            self.setSwitchData.update(switchData: switchData)
            self.updateSaveEnabledState()
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    /// 删除动能开关
    private func deleteSwitchData() {
        
        guard let switchData = self.switchData else {
            return
        }
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        // 删除开关先将组解除订阅
//        switchData.bindGroupAddresses.forEach { address in
//            if !switchData.unbindGroupAddresses.contains(address) {
//                switchData.unbindGroupAddresses.append(address)
//            }
//        }
//        switchData.save()
        
        let vc = SyncDevicesViewController(type: .enOceanSwitch(switchData, deleteSwitch: true))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            MeshNetworkManager.instance.deleteSwitch(switchData: switchData)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                self?.fineshed()
            }
        }
        vc.backActionCallback = {[weak self] in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            self.setSwitchData.update(switchData: switchData)
            self.updateSaveEnabledState()
            self.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
               
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + kSafeAreaBottomHeight)
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
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
//        tableView.separatorInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(16))
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "info")
        tableView.register(GroupSwitchPanelViewCell.classForCoder(), forCellReuseIdentifier: "panel")
        tableView.register(DeviceSwitchHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
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
        
    }

    /// 更新保存按钮状态
    private func updateSaveEnabledState() {
        // 名称是否合法
        let nameValid = !(setSwitchData.name.isAllInputTextEmpty() || MeshNetworkManager.instance.isSwitchTautonym(name: setSwitchData.name) && setSwitchData.name != switchData?.name)
        
        if !nameValid || (switchData != nil && setSwitchData == switchData!) { // 未改动
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
        
        self.isModalInPresentation = !(setSwitchData == (switchData ?? DeviceSwitchData.default()))
    }
    
}

extension DeviceSwitchViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return sections[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let option = sections[indexPath.section][indexPath.row]
        if option == .keyInfo {
            let panelCell = tableView.dequeueReusableCell(withIdentifier: "panel", for: indexPath) as! GroupSwitchPanelViewCell
            panelCell.sceneNameA = setSwitchData.sceneA?.name
            panelCell.sceneNameB = setSwitchData.sceneB?.name
            panelCell.saveBtn.isHidden = true
            panelCell.deleteBtn.isHidden = true
            panelCell.margin = 0
            panelCell.switchContentView.layer.borderWidth = 0
            return panelCell
        }else {
            let infoCell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! CustomTableViewCell
            infoCell.titleLabel.text = option.title
            infoCell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            infoCell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            infoCell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
            infoCell.lineView.isHidden = option == .proxy
            infoCell.iconImageView.isHidden = true
            infoCell.selectionStyle = .none
            let numberOfRows = tableView.numberOfRows(inSection: indexPath.section)
            let isFirstCell = indexPath.row == 0
            let isLastCell = indexPath.row == numberOfRows - 1
            infoCell.configureCell(isFirst: isFirstCell, isLast: isLastCell)
            switch option {
            case .enable:
                infoCell.cellStyle = .switch
                infoCell.enabledSwitch.isOn = self.setSwitchData.enabled
                infoCell.contentLabel.text = nil
                infoCell.switchActionCallback = {[weak self] isOn in
                    guard let self = self else { return }
                    guard self.editable else {
                        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                        return
                    }
                    self.setSwitchData.enabled = isOn
                    infoCell.enabledSwitch.isOn = isOn
                    self.updateSaveEnabledState()
//                    self?.setEnOceanSwitchKeysEnabled(groupSwitch: groupSwitch, enabled: isOn)
                }
            case .id:
                infoCell.cellStyle = .none
                infoCell.contentLabel.text = setSwitchData.enOceanMacAddress ?? "switch_not_linked".localizedString
//                groupSwitch.name
            case .panel:
                infoCell.cellStyle = .arrow
                infoCell.contentLabel.text = setSwitchData.panelType.describe
            case .group:
                infoCell.cellStyle = .arrow
                let groupNames = setSwitchData.bindGroups.map({ $0.name })
                var content = ""
                groupNames.forEach { name in
                    content.append((content.isEmpty ? "" : ",") + name)
                }
                infoCell.contentLabel.text = content.isEmpty ? "N/A" : content
            case .scene:
                infoCell.cellStyle = .arrow
                var sceneStr = ""
                if let sceneA = setSwitchData.sceneA {
                    sceneStr.append(sceneA.name)
                }
                if let sceneB = setSwitchData.sceneB {
                    sceneStr.append(String(format: "%@%@", sceneStr.isEmpty ? "" : ",", sceneB.name))
                }
                if sceneStr.isEmpty {
                    sceneStr = "N/A"
                }
                infoCell.contentLabel.text = sceneStr
            case .proxy:
                infoCell.cellStyle = .arrow
                infoCell.iconImageView.isHidden = false
                infoCell.iconImageView.image = UIImage(named: "help")
                infoCell.contentTextMaxWidth = SCRXFrom(135)
                infoCell.iconImageView.snp.remakeConstraints { make in
                    make.left.equalTo(infoCell.titleLabel.snp.right)
                    make.centerY.equalToSuperview()
                }
                infoCell.iconImageClickCallback = {[weak self] in
                    self?.navigationController?.pushViewController(SwitchProxyInstructionsViewController(), animated: true)
                }
                if let node = setSwitchData.proxyNode {
                    infoCell.contentLabel.text = node.name ?? "\(node.primaryUnicastAddress)"
                }else {
                    infoCell.contentLabel.text = "N/A"
                }
            default:
                break
            }
            return infoCell
        }
        
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        if section == 0 {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceSwitchHeaderView
            headerView.nameField.text = setSwitchData.name
            headerView.nameField.isEnabled = editable
            headerView.syncFailedBtn.isHidden = switchData == nil || !switchData!.needSyncData
            headerView.nameEditChanged = {[weak self] name in
                self?.setSwitchData.name = name
                self?.updateSaveEnabledState()
                if name.count > 32 {
                    return "text_length_exceeded".localizedString
                }
                // 重名
                if name.count > 0 && MeshNetworkManager.instance.isSwitchTautonym(name: name) && name != self?.switchData?.name {
                    return "name_already_exists".localizedString
                }
                return nil
            }
            headerView.reSyncCallback = {[weak self] in
                self?.switchReSync()
            }
            self.headerView = headerView
            return headerView
        }
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if section == 0 {
            return SCRYFrom(92)
        }
        return SCRYFrom(8)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let option = sections[indexPath.section][indexPath.row]
        if option == .keyInfo {
            return SCRXFrom(288)
        }
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if headerView?.nameField.isEditing ?? false {
            view.endEditing(true)
            return
        }
        
        let option = sections[indexPath.section][indexPath.row]
        
        guard editable || option == .keyInfo else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        switch option {
        case .group:
            let vc = SwitchSelectGroupsViewController(groups: MeshNetworkManager.instance.groups, selectGroups: setSwitchData.bindGroups)
            vc.editable = self.editable
            vc.proxyGroup = setSwitchData.proxyNode?.group
            vc.selectGroupsCallback = {[weak self] selectGroups in
                guard let self = self else { return }
                let unbindGroupAddresses = self.switchData?.bindGroupAddresses.filter({ address in !selectGroups.contains(where: { $0.address.address == address }) }) ?? []
                self.setSwitchData.bindGroupAddresses = selectGroups.map({ $0.address.address })
                self.setSwitchData.unbindGroupAddresses.removeAll(where: { self.setSwitchData.bindGroupAddresses.contains($0) })
                unbindGroupAddresses.forEach({
                    if !self.setSwitchData.unbindGroupAddresses.contains($0) {
                        self.setSwitchData.unbindGroupAddresses.append($0)
                    }
                })
//                self.setSwitchData.unbindGroupAddresses.removeAll(where: { unbindAddress in selectGroups.contains(where: { $0.address.address == unbindAddress }) })
                tableView.reloadRows(at: [indexPath], with: .none)
                self.updateSaveEnabledState()
            }
            navigationController?.pushViewController(vc, animated: true)
            
        case .scene:
            if SRAlertView.isVisible() {
                return
            }
            let vc = SwitchSelectSceneViewController(scenes: MeshNetworkManager.instance.scenes, sceneA: setSwitchData.sceneA, sceneB: setSwitchData.sceneB)
            vc.sceneSelectCallback = {[weak self] sceneA, sceneB in
                guard let self = self else { return }
                self.setSwitchData.sceneANumber = sceneA?.number
                self.setSwitchData.sceneBNumber = sceneB?.number
                tableView.reloadData()
                self.updateSaveEnabledState()
            }
            navigationController?.pushViewController(vc, animated: true)
        case .proxy:
            if SRAlertView.isVisible() {
                return
            }
            
            let vc = EnOceanProxyViewController(switchData: setSwitchData)
            vc.editable = self.editable
            vc.switchDataSaved = {[weak self] in
                guard let self = self, let switchData = self.switchData else {
                    return true
                }
                return switchData == self.setSwitchData
            }
            vc.switchDataUpdateCallback = {[weak self] switchData in
                guard let self = self else { return }
                if switchData.proxyNodeAddress == switchData.deleteProxyNodeAddress {
                    switchData.deleteProxyNodeAddress = nil
                }
                self.tableView.reloadData()
                self.updateSaveEnabledState()
            }
            vc.switchCreateCallback = {[weak self] newSwitch in
                guard let self = self else { return }
                navigationController?.popViewController(animated: true)
                self.switchData = nil
                self.setSwitchData = newSwitch
                self.updateUI()
                self.updateSaveEnabledState()
                self.tableView.reloadData()
//                self.dismiss(animated: true) {[weak self] in
//                    guard let self = self else { return }
//                    let vc = DeviceSwitchViewController(space: self.space, switchData: newSwitch)
//                    UIViewController.getVisibleVc()?.present(NavigationViewController(rootViewController: vc), animated: true)
//                }
            }
//            vc.switchDataUpdateCallback = {[weak self] setSwitch in
//                guard let self = self else { return }
//                
//                self.syncRealSwitchData(copySwitch: setSwitch)
//                if setSwitch.id != groupSwitch.id {
//                    if let copySwitch = copySwitchs.first(where: { $0.id == setSwitch.id }) {
//                        copySwitch.update(switchData: setSwitch)
//                    }else {
//                        copySwitchs.append(setSwitch.copy())
//                    }
//                    tableView.reloadData()
//                }else {
//                    if let copySwitch = copySwitchs.first(where: { $0.id == setSwitch.id }) {
//                        copySwitch.update(switchData: setSwitch)
//                    }
//                    tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
//                }
//            }
            navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
        
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
    
}

extension DeviceSwitchViewController {
    /// cell类型
    enum CellType {
        
        var title: String {
            switch self {
            case .enable:
                return "enable".localizedString
            case .id:
                return "ID".localizedString
//            case .name:
//                return "name".localizedString
            case .panel:
                return "panel".localizedString
            case .group:
                return "group".localizedString
            case .scene:
                return "scene".localizedString
            case .proxy:
                return "enocean_proxy".localizedString
            case .keyInfo:
                return ""
            }
        }
        
        
        /// 名称
//        case name
        /// ID (Mac)
        case id
        /// 启用
        case enable
        /// 面板类型
        case panel
        /// 组
        case group
        /// 场景
        case scene
        /// 代理
        case proxy
        /// 面板按键信息
        case keyInfo
    }
}
