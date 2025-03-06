//
//  GroupSwitchsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/12.
//

import UIKit
import NordicSigMeshSDK

class GroupSwitchsViewController: UIViewController {

    private var tableView: UITableView!
    private var bottomView: UIView!
    private var addSwitchBtn: UIButton!
    
    /// 加载动画
    private var loadingView: UIImageView!
    
    private var options: [CellType] = [.panel, .group, .scene, .proxy, .keyInfo]
    
    var group: Group
    /// 展开的开关
    private var showSwitchs: [DeviceSwitchData] = []
    /// 虚拟开关副本
    private var copySwitchs: [DeviceSwitchData] = []
    /// 是否可编辑
    var editable: Bool = true
    
    init(group: Group) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.title = "switch".localizedString
        view.backgroundColor = Background_Color
        
        self.isModalInPresentation = true
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        copySwitchs = group.info.switchs.map({ $0.copy() })
        
        setupUI()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (navigationController as? NavigationViewController)?.navigationDelegate = self
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        (navigationController as? NavigationViewController)?.navigationDelegate = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateEmptyUI()
    }
    
    private func exitAction() {
        
        if copySwitchs.contains(where: { copySwitch in !group.info.switchs.contains(where: { $0 == copySwitch }) }) {
            
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "exit".localizedString, actionHandler: {[weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })]).show()
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    private func updateEmptyUI() {
        
        if copySwitchs.isEmpty {
//            if tableView.frame == .zero {
//                view.layoutIfNeeded()
//            }
            tableView.showEmptyDataView(frame: tableView.frame, title: "switch_empty_title".localizedString, tipText: "switch_empty_message".localizedString, position: .center, bottomMargin: SCRYFit(100))
            tableView.emptyView?.backgroundColor = .clear
        }else {
            tableView.hideEmptyDataView()
        }
    }
    
    @objc private func addSwitchBtnAction() {
        addVirtualSwitch()
    }
    
    /// 添加虚拟开关
    private func addVirtualSwitch() {
        
//        if let index = group.info.switchs.firstIndex(where: { $0.id == groupSwitch.id }) {
//            tableView.deleteSections(IndexSet(integer: index), with: .automatic)
//        }
        guard let newSwitch = MeshNetworkManager.instance.createDefaultSwitch() else {
            SRAlertView(title: "notification".localizedString, message: "switchs_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
            return
        }
        newSwitch.bindGroupAddresses.append(group.address.address)
        newSwitch.save()
        copySwitchs.append(newSwitch.copy())
        // 默认展开
        showSwitchs.append(newSwitch)
        tableView.insertSections(IndexSet(integer: copySwitchs.count - 1), with: .top)

        DispatchQueue.main.async {
            self.tableView.scrollToRow(at: IndexPath(row: 0, section: self.copySwitchs.count - 1), at: .top, animated: true)
        }
        
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        
        updateEmptyUI()
    }
    
    /// 副本按键同步到真实按键数据
    private func syncRealSwitchData(copySwitch: DeviceSwitchData) {
        let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
        
        if let realSwitch = MeshNetworkManager.instance.switchs.first(where: { $0.id == copySwitch.id }) {
            realSwitch.update(switchData: copySwitch)
            if uuid != nil {
//                let networkKey = MeshNetworkManager.instance.currentNetworkKey
                realSwitch.save()
//                if let proxy = realSwitch.proxyNode {
//                    proxy.saveNodeInfo(meshUUID: uuid!, networkKey: networkKey)
//                }
            }
        }
        
    }
    
    /// 删除虚拟开关
    private func deleteSwitch(switchData: DeviceSwitchData) {
        
        if let index = copySwitchs.firstIndex(where: { $0.id == switchData.id }) {
            if let realSwitch = MeshNetworkManager.instance.switchs.first(where: { $0.id == switchData.id }) {
                MeshNetworkManager.instance.switchs.removeAll(where: { $0.id == realSwitch.id })
                if let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
                    let networkId = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
                    realSwitch.delete(meshUUID: meshUUID, networkId: networkId)
                }
//                group.delete(groupSwitch: realSwitch)
            }
            copySwitchs.removeAll(where: { $0.id == switchData.id })
            showSwitchs.removeAll(where: { $0.id == switchData.id })
            tableView.deleteSections(IndexSet(integer: index), with: .fade)
        }
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        updateEmptyUI()
    }
    
    /// 保存虚拟开关
    private func saveSwitch(switchData: DeviceSwitchData) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        // 是否存在别的虚拟动能开关也绑定了同一个动能开关
        if let otherSwitch = group.info.switchs.first(where: { $0.id != switchData.id && switchData.enOceanMacAddress?.count ?? 0 > 0 && $0.enOceanMacAddress == switchData.enOceanMacAddress }) {
            XWHUDManager.showTipHUD(String(format: "switchs_not_saved".localizedString, otherSwitch.name))
            return
        }
        
        // 切换代理/删除代理节点记录该代理地址
        var deleteProxyNodeAddress = switchData.deleteProxyNodeAddress
        if let realSwitch = group.info.switchs.first(where: { $0.id == switchData.id }), realSwitch.proxyNodeAddress != nil && realSwitch.proxyNodeAddress != switchData.proxyNodeAddress {
            deleteProxyNodeAddress = realSwitch.proxyNodeAddress
        }
        switchData.deleteProxyNodeAddress = deleteProxyNodeAddress
        
        // 未创建动能开关通讯组
        if switchData.proxyNodeAddress != nil && switchData.linkGroupAddress == nil {
            
            // 判断组地址是否足够分配
            guard let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString, MeshAPI.getAvailableGroupAddresses(meshUUID: meshUUID).count >= switchData.panelType.usedAddressesNumber else {
                XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
                return
            }
            
            guard let linkGroup = try? MeshAPI.createGroup(name: switchData.name + "-Group", isVirtual: true) else {
                XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                return
            }
            let subLinkGroup = try? MeshAPI.createGroup(name: switchData.name + "-Group_1", isVirtual: true)
            
            switchData.linkGroupAddress = linkGroup.address.address
            switchData.subLinkGroupAddress = subLinkGroup?.address.address
//            self.switchData?.save()
        }
        syncRealSwitchData(copySwitch: switchData)
        
        // 判断是否需要对设备发送数据
        guard !switchData.getNeedSyncDatas().isEmpty() else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            reloadSwitchItem(switchData: switchData)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            return
        }
        
        // 网络未连接
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        let vc = SyncDevicesViewController(type: .enOceanSwitch(switchData))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            if let realSwitch = MeshNetworkManager.instance.switchs.first(where: { $0.id == switchData.id }) {
                switchData.update(switchData: realSwitch)
            }
            self?.reloadSwitchItem(switchData: switchData)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        vc.backActionCallback = {[weak self] in
            if let realSwitch = MeshNetworkManager.instance.switchs.first(where: { $0.id == switchData.id }) {
                switchData.update(switchData: realSwitch)
            }
            self?.reloadSwitchItem(switchData: switchData)
            self?.navigationController?.popViewController(animated: true)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 重新同步
    private func switchReSync(switchData: DeviceSwitchData) {
       
        let vc = SyncDevicesViewController(type: .enOceanSwitch(switchData), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
            
            if let copySwitch = self.copySwitchs.first(where: { $0.id == switchData.id }) {
                copySwitch.update(switchData: switchData)
            }
            self.reloadSwitchItem(switchData: switchData)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        vc.backActionCallback = {[weak self] in
            guard let self = self else { return }
            if let copySwitch = self.copySwitchs.first(where: { $0.id == switchData.id }) {
                copySwitch.update(switchData: switchData)
            }
            self.reloadSwitchItem(switchData: switchData)
            self.navigationController?.popViewController(animated: true)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    /// 设置开关启用/禁用
    /// - Parameters:
    ///   - groupSwitch: 虚拟开关
    ///   - enabled: 是否启用
    private func setEnOceanSwitchKeysEnabled(groupSwitch: GroupSwitch, enabled: Bool) {
        
//        guard editable else {
//            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
//            return
//        }
//        // 虚拟按键未设置代理
//        guard let proxyNode = groupSwitch.proxyNode else {
//            groupSwitch.enabled = enabled
//            reloadSwitchItem(groupSwitch: groupSwitch)
//            return
//        }
//        
//        // 网络未连接
//        guard MeshLibManager.manager.isMeshNetworkConnected else {
//            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
//            return
//        }
//        
//        showLoadingAnimation()
//        if enabled {
//            MeshEnOceanProxyServer.bindEnOceanSwitchKeys(proxyNode: proxyNode, group: self.group, sceneA: groupSwitch.sceneA, sceneB: groupSwitch.sceneB) {[weak self] isSuccess, error in
//                guard let self = self else { return }
//                self.hideLoadingAnimation()
//                if isSuccess {
//                    groupSwitch.enabled = enabled
//                    self.syncRealSwitchData(copySwitch: groupSwitch)
//                    self.reloadSwitchItem(groupSwitch: groupSwitch)
//                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
//                    // 通知space数据修改
//                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//                }else {
//                    XWHUDManager.showErrorTipHUD("save_failure".localizedString)
//                }
//            }
//        }else {
//            MeshEnOceanProxyServer.unbindEnOceanSwitchKeys(proxyNode: proxyNode, group: self.group) {[weak self] isSuccess, error in
//                guard let self = self else { return }
//                self.hideLoadingAnimation()
//                if isSuccess {
//                    groupSwitch.enabled = enabled
//                    self.syncRealSwitchData(copySwitch: groupSwitch)
//                    self.reloadSwitchItem(groupSwitch: groupSwitch)
//                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
//                    // 通知space数据修改
//                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//                }else {
//                    XWHUDManager.showErrorTipHUD("save_failure".localizedString)
//                }
//                
//            }
//        }
        
    }
    
    /// 删除开关
    private func deleteEnOceanSwitch(switchData: DeviceSwitchData) {
        
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        guard switchData.linkGroupAddress != nil else { // 未绑定
            deleteSwitch(switchData: switchData)
            return
        }
        
        // 网络未连接
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
            self.navigationController?.popViewController(animated: true)
            self.deleteSwitch(switchData: switchData)
        }
        vc.backActionCallback = {[weak self] in
            guard let self = self else { return }
//            if let index = self.copySwitchs.firstIndex(where: { $0.id == switchData.id }) {
//                self.copySwitchs[index].update(switchData: switchData)
//            }
            self.navigationController?.popViewController(animated: true)
            if let realSwitch = MeshNetworkManager.instance.switchs.first(where: { $0.id == switchData.id }) {
                switchData.update(switchData: realSwitch)
            }
            self.reloadSwitchItem(switchData: switchData)
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        }
        navigationController?.pushViewController(vc, animated: true)
        
//        showLoadingAnimation()
//        MeshEnOceanProxyServer.deleteEnOceanProxy(proxyNode: proxyNode, group: self.group) {[weak self] isDeleteSuccess, deleteError in
//            guard let self = self else { return }
//            self.hideLoadingAnimation()
//            if isDeleteSuccess {
//                XWHUDManager.showSuccessTipHUD("done!".localizedString)
//                self.deleteSwitch(groupSwitch: groupSwitch)
//                // 通知space数据修改
//                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//            }else {
//                XWHUDManager.showErrorTipHUD("switch_delete_failure".localizedString)
//            }
//        }
        
    }
    
    /// 刷新数据
    private func reloadSwitchItem(switchData: DeviceSwitchData) {
        
        if let index = copySwitchs.firstIndex(where: { $0.id == switchData.id }) {
            tableView.reloadSections(IndexSet(integer: index), with: .none)
        }else {
            tableView.reloadData()
        }
    }
    
    
    
    /// 显示loading动画
    private func showLoadingAnimation() {
        
        tableView.isHidden = true
        bottomView.isHidden = true
        loadingView.isHidden = false
        
        loadingView.layer.addRotationAnimation(duration: 1.2, repeatCount: 9999, animationKey: "loading")
    }
    /// 隐藏loading动画
    private func hideLoadingAnimation() {
        tableView.isHidden = false
        bottomView.isHidden = false
        loadingView.isHidden = true
        loadingView.layer.removeAnimation(forKey: "loading")
    }
    
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        bottomView.isHidden = !editable
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        addSwitchBtn = UIButton(title: "add_switch".localizedString, titleSize: 15, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(addSwitchBtnAction))
        bottomView.addSubview(addSwitchBtn)
        addSwitchBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = Background_Color
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "info")
        tableView.register(GroupSwitchPanelViewCell.classForCoder(), forCellReuseIdentifier: "panel")
        tableView.register(GroupSwitchsHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        tableView.separatorStyle = .none
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaInsets.top)
            make.left.right.equalToSuperview()
            if editable {
                make.bottom.equalTo(bottomView.snp.top)
            }else {
                make.bottom.equalToSuperview()
            }
        }
        
        loadingView = UIImageView(image: UIImage(named: "loading_big"))
        loadingView.isHidden = true
        view.addSubview(loadingView)
        loadingView.snp.makeConstraints { make in
            make.center.equalToSuperview().offset(-view.safeAreaInsets.top)
        }
        
    }
    
}

extension GroupSwitchsViewController: NavigationViewControllerDelegate {

    /// 点击返回item回调
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
        exitAction()
    }
    
    /// pop手势begin回调，返回是否可以pop
    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool {
        // 是否存在编辑未保存的数据
        if copySwitchs.contains(where: { copySwitch in !group.info.switchs.contains(where: { $0 == copySwitch }) }) {
            exitAction()
            return false
        }
        return true
    }
    
}


extension GroupSwitchsViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return copySwitchs.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let groupSwitch = group.info.switchs[section]
        if showSwitchs.contains(where: { $0.id == groupSwitch.id }) {
            return options.count
        }
        return 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let groupSwitch = copySwitchs[indexPath.section]
        
        let option = options[indexPath.row]
        if option == .keyInfo {
            let panelCell = tableView.dequeueReusableCell(withIdentifier: "panel", for: indexPath) as! GroupSwitchPanelViewCell
            switch groupSwitch.panelType {
            case .default:
                panelCell.key1ShortPressBtn.setTitle("switch_key_on".localizedString, for: .normal)
                panelCell.key2ShortPressBtn.setTitle("switch_key_off".localizedString, for: .normal)
                panelCell.key3ShortPressBtn.setTitle(groupSwitch.sceneA?.name ?? "switch_key_sceneA".localizedString, for: .normal)
                panelCell.key4ShortPressBtn.setTitle(groupSwitch.sceneB?.name ?? "switch_key_sceneB".localizedString, for: .normal)
            case .scenes:
                panelCell.key1ShortPressBtn.setTitle(groupSwitch.sceneA?.name ?? "switch_key_sceneA".localizedString, for: .normal)
                panelCell.key2ShortPressBtn.setTitle(groupSwitch.sceneB?.name ?? "switch_key_sceneB".localizedString, for: .normal)
                panelCell.key3ShortPressBtn.setTitle(groupSwitch.sceneC?.name ?? "switch_key_sceneC".localizedString, for: .normal)
                panelCell.key4ShortPressBtn.setTitle(groupSwitch.sceneD?.name ?? "switch_key_sceneD".localizedString, for: .normal)
            }
            if let realSwitch = group.info.switchs.first(where: { $0.id == groupSwitch.id }) {
                panelCell.saveBtn.isEnabled = !(realSwitch == groupSwitch) || realSwitch.needSyncData
            }
            panelCell.delegate = self
            return panelCell
        }else {
            let infoCell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! CustomTableViewCell
            infoCell.titleLabel.text = option.title
            infoCell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            infoCell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            infoCell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
            infoCell.lineView.isHidden = option == .proxy
            infoCell.selectionStyle = .none
            
            switch option {
//            case .enable:
//                infoCell.cellStyle = .switch
//                infoCell.enabledSwitch.isOn = groupSwitch.enabled
//                infoCell.contentLabel.text = nil
//                infoCell.switchActionCallback = {[weak self] isOn in
//                    self?.setEnOceanSwitchKeysEnabled(groupSwitch: groupSwitch, enabled: isOn)
//                }
//            case .name:
//                infoCell.cellStyle = .none
//                infoCell.contentLabel.text = groupSwitch.name
            case .panel:
                infoCell.cellStyle = .arrow
                infoCell.contentLabel.text = groupSwitch.panelType.describe
            case .group:
                infoCell.cellStyle = .arrow
                let groupNames = groupSwitch.bindGroups.map({ $0.name })
                var content = ""
                groupNames.forEach { name in
                    content.append((content.isEmpty ? "" : ",") + name)
                }
                infoCell.contentLabel.text = content.isEmpty ? "N/A" : content
                
            case .scene:
                infoCell.cellStyle = .arrow
                var sceneStr = ""
                if let sceneA = groupSwitch.sceneA {
                    sceneStr.append(sceneA.name)
                }
                if let sceneB = groupSwitch.sceneB {
                    sceneStr.append(String(format: "%@%@", sceneStr.isEmpty ? "" : ",", sceneB.name))
                }
                if sceneStr.isEmpty {
                    sceneStr = "N/A"
                }
                infoCell.contentLabel.text = sceneStr
            case .proxy:
                infoCell.cellStyle = .arrow
                if let node = groupSwitch.proxyNode, groupSwitch.enOceanMacAddress?.count ?? 0 > 0 {
                    infoCell.contentLabel.text = node.name ?? "\(node.primaryUnicastAddress)"
                }else {
                    infoCell.contentLabel.text = "N/A"
                }
            default:
                break
            }
            infoCell.titleX = SCRXFrom(32)
            return infoCell
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupSwitchsHeaderView
        let groupSwitch = copySwitchs[section]
        headerView.isShow = showSwitchs.contains(where: { $0.id == groupSwitch.id })
        headerView.delegate = self
        headerView.groupSwitch = groupSwitch
        if let realSwitch = group.info.switchs.first(where: { $0.id == groupSwitch.id }) {
            headerView.failedImageView.isHidden = !realSwitch.needSyncData
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(64)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let option = options[indexPath.row]
        if option == .keyInfo {
            return SCRYFrom(84) + SCRXFrom(288)
        }
        return SCRYFrom(44)
    }
    
//    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
//        let option = options[indexPath.row]
//        if option == .keyInfo {
//            return SCRYFrom(312)
//        }
//        return SCRYFrom(44)
//    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let option = options[indexPath.row]
        
        guard editable || option == .keyInfo else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        let groupSwitch = copySwitchs[indexPath.section]
        switch option {
        case .panel:
            
            let vc = SwitchSelectPanelTypeController()
            vc.selectPanelType = groupSwitch.panelType
            vc.selectPanelTypeCallback = {[weak self] type in
                guard let self = self else { return }
                groupSwitch.panelType = type
                groupSwitch.sceneANumber = nil
                groupSwitch.sceneBNumber = nil
                groupSwitch.sceneCNumber = nil
                groupSwitch.sceneDNumber = nil
                self.reloadSwitchItem(switchData: groupSwitch)
            }
            navigationController?.pushViewController(vc, animated: true)
            
        case .group:
            
            let vc = SwitchSelectGroupsViewController(groups: groupSwitch.bindGroups, selectGroups: groupSwitch.bindGroups)
            vc.editable = false
            navigationController?.pushViewController(vc, animated: true)
            
        case .scene:
            if SRAlertView.isVisible() {
                return
            }
            var datas: [SwitchSceneData] = [.init(type: .sceneA, scene: groupSwitch.sceneA), .init(type: .sceneB, scene: groupSwitch.sceneB)]
            if groupSwitch.panelType == .scenes {
                datas.append(contentsOf: [
                    .init(type: .sceneC, scene: groupSwitch.sceneC),
                    .init(type: .sceneD, scene: groupSwitch.sceneD),
                ])
            }
            let vc = SwitchSelectScenePageController(scenes: MeshNetworkManager.instance.scenes, sceneDatas: datas)
            vc.scenesSelectCallback = { sceneDatas in
                sceneDatas.forEach { data in
                    switch data.type {
                    case .sceneA:
                        groupSwitch.sceneANumber = data.scene?.number
                    case .sceneB:
                        groupSwitch.sceneBNumber = data.scene?.number
                    case .sceneC:
                        groupSwitch.sceneCNumber = data.scene?.number
                    case .sceneD:
                        groupSwitch.sceneDNumber = data.scene?.number
                    }
                }
                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
            }
//            vc.sceneSelectCallback = { sceneA, sceneB in
//                groupSwitch.sceneANumber = sceneA?.number
//                groupSwitch.sceneBNumber = sceneB?.number
//                tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
//            }
            navigationController?.pushViewController(vc, animated: true)
        case .proxy:
            if SRAlertView.isVisible() {
                return
            }
            let vc = EnOceanProxyViewController(switchData: groupSwitch)
            let allSwitches = MeshNetworkManager.instance.switchs.map({ $0.copy() })
            allSwitches.forEach({ switches in
                if let copySwitch = self.copySwitchs.first(where: { $0.id == switches.id }) {
                    switches.update(switchData: copySwitch)
                }
            })
            vc.switchs = allSwitches
//            self.copySwitchs
            vc.editable = self.editable
            vc.switchDataSaved = {[weak self] in
                guard let self = self, let switchData = self.group.info.switchs.first(where: { $0.id == groupSwitch.id }) else {
                    return true
                }
                return switchData == groupSwitch
            }
            vc.switchDataUpdateCallback = { _ in
//                guard let self = self else { return }
                
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
                    tableView.reloadSections(IndexSet(integer: indexPath.section), with: .none)
//                }
            }
            vc.switchCreateCallback = {[weak self] newSwitch in
                guard let self = self else { return }
                
                // 未创建动能开关通讯组
                if newSwitch.proxyNodeAddress != nil && newSwitch.linkGroupAddress == nil {
                    // 判断组地址是否足够分配
                    guard let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString, MeshAPI.getAvailableGroupAddresses(meshUUID: meshUUID).count >= newSwitch.panelType.usedAddressesNumber else {
                        XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
                        return
                    }
                    
                    guard let linkGroup = try? MeshAPI.createGroup(name: newSwitch.name + "-Group", isVirtual: true) else {
                        XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                        return
                    }
                    let subLinkGroup = try? MeshAPI.createGroup(name: newSwitch.name + "-Group_1", isVirtual: true)
                    
                    newSwitch.linkGroupAddress = linkGroup.address.address
                    newSwitch.subLinkGroupAddress = subLinkGroup?.address.address
                }
                newSwitch.save()
                MeshNetworkManager.instance.switchs.append(newSwitch)
                NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
                self.navigationController?.popViewController(animated: true)
                
                let copySwitch = newSwitch.copy()
                self.showSwitchs.append(copySwitch)
                self.copySwitchs.append(copySwitch)
                
                tableView.insertSections(IndexSet(integer: self.copySwitchs.count - 1), with: .top)
                DispatchQueue.main.async {
                    self.tableView.scrollToRow(at: IndexPath(row: 0, section: self.copySwitchs.count - 1), at: .top, animated: true)
                }
            }
            navigationController?.pushViewController(vc, animated: true)
        default:
            break
        }
        
        
//        EnOceanProxyViewController
    }
    
}

extension GroupSwitchsViewController: GroupSwitchsHeaderViewDelegate {
    
    /// 点击view回调  isShow：是否展开
    func view(_ view: GroupSwitchsHeaderView, viewDidClick isShow: Bool) {
        
        let groupSwitch = view.groupSwitch!
        if isShow {
            self.showSwitchs.append(groupSwitch)
        }else {
            self.showSwitchs.removeAll(where: { $0.id == groupSwitch.id })
        }
        if let index = copySwitchs.firstIndex(where: { $0.id == groupSwitch.id }) {
            tableView.reloadSections(IndexSet(integer: index), with: .automatic)
        }
    }
    
    /// 长按view回调
    func headerViewDidLongPress(_ view: GroupSwitchsHeaderView) {
        guard let groupSwitch = view.groupSwitch, self.editable else {
            return
        }
        SRAlertView(title: "edit_name".localizedString, messageColor: Red_Color, messageFont: UIFont.systemFont(ofSize: 13, weight: .light), inputText: groupSwitch.name, inputFieldStyle: .init(placeholder: ""), actions: [.cancelAction, .init(title: "done".localizedString, style: .default)]) { text, validRange in
//            guard let self = self else { return }
             if !validRange && !text.isEmpty { // 长度超限
                 return "text_length_exceeded".localizedString
             }else if MeshNetworkManager.instance.isSwitchTautonym(name: text) && text != groupSwitch.name { // 重名
                 return "name_already_exists".localizedString
             }
             return nil
         } inputDoneBack: {[weak self] text in
             guard let self = self else { return }
             groupSwitch.name = text
             self.syncRealSwitchData(copySwitch: groupSwitch)
             self.reloadSwitchItem(switchData: groupSwitch)
             NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
         }.show()
        
    }
    
    /// 开关点击回调  enabled：是否启用
    func view(_ view: GroupSwitchsHeaderView, switchDidClick enabled: Bool) {
        guard self.editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        view.groupSwitch.enabled = enabled
        reloadSwitchItem(switchData: view.groupSwitch)
        
//        let groupSwitch = view.groupSwitch!
//        setEnOceanSwitchKeysEnabled(groupSwitch: groupSwitch, enabled: enabled)
    }
    
    /// 重新同步点击回调
    func headerViewDidResyncAction(_ view: GroupSwitchsHeaderView) {
        guard self.editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        if let realSwitch = self.group.info.switchs.first(where: { $0.id == view.groupSwitch.id }) {
            switchReSync(switchData: realSwitch)
        }
    }
    
}

extension GroupSwitchsViewController: GroupSwitchPanelViewCellDelegate {
    
    /// 删除事件
    func switchPanelViewCellDeleteAction(_ cell: GroupSwitchPanelViewCell) {
        
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        if let index = tableView.indexPath(for: cell)?.section {
            let switchData = copySwitchs[index]
            // 动能开关原始数据，副本数据可能未保存
            let realSwitchData = group.info.switchs.first(where: { $0.id == switchData.id })
//            if switchData.linkGroupAddress != nil || switchData.proxyNodeAddress != nil { // 已绑定开关
                SRAlertView(title: "notification".localizedString, message: "switch_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: {[weak self] _ in
                    
                    self?.deleteEnOceanSwitch(switchData: realSwitchData ?? switchData)
                })]).show()
                
//            }else {
//                deleteEnOceanSwitch(switchData: realSwitchData ?? switchData)
//            }
//            deleteSwitch(groupSwitch: groupSwitch)
//            deleteEnOceanSwitch(switchData: switchData)
        }
    }
    
    /// 保存事件
    func switchPanelViewCellSaveAction(_ cell: GroupSwitchPanelViewCell) {
        if let index = tableView.indexPath(for: cell)?.section {
            let groupSwitch = copySwitchs[index]
            saveSwitch(switchData: groupSwitch)
        }
    }
    
}

extension GroupSwitchsViewController {
    /// cell类型
    enum CellType {
        
        var title: String {
            switch self {
//            case .enable:
//                return "enable".localizedString
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
        
        
        /// 启用
//        case enable
        /// 名称
//        case name
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
