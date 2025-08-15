//
//  GatewayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/17.
//

import UIKit
import NordicSigMeshSDK

class GatewayViewController: UIViewController, DeviceProtocol {

    private var tableView: UITableView!
    private var headerView: GatewayInformationHeaderView!
    private var footerView: UIView!
    private var copyInformationBtn: UIButton!
    private var bottomView: DeviceBottomBtnView!
    
    let space: SpaceData
    let node: Node
    
    private var name: String?
    
    private var setGatewayModel: GatewayModel?
    /// 其它网关数据
    private var otherGateways: [GatewayModel] = []
    
    private var sections: [SectionType] = [.name, .info, .apn, .serverInformation]
    
    private weak var lastMessageDelegate: MeshLibManagerMessageDelegate?
    
    init(space: SpaceData, node: Node) {
        self.space = space
        self.node = node
        super.init(nibName: nil, bundle: nil)
        
        setGatewayModel = node.gatewayModel?.copy()
        
        otherGateways = GatewayModel.load(siteId: space.siteId).filter({ $0.mac != node.gatewayModel?.mac })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = node.name
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        
        name = node.name
        lastMessageDelegate = MeshLibManager.manager.messageDelegate
        
        setupUI()
        updateData()
        updateSaveBtnState()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        MeshLibManager.manager.messageDelegate = self
    }

    @objc private func close() {
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1  {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    deinit {
        MeshLibManager.manager.messageDelegate = self.lastMessageDelegate
        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
    }

    
    @objc private func copyInformationBtnAction() {
        
        var copyContent: String = ""
        if let name = node.name {
            copyContent.append("\("name".localizedString): \(name)")
        }else {
            copyContent.append("\("name".localizedString): N/A")
        }
        
        if let mac = node.gatewayModel?.mac {
            copyContent.append("\n\("MAC".localizedString): \(mac)")
        }else {
            copyContent.append("\n\("MAC".localizedString): N/A")
        }
        
        if let activate = node.gatewayModel?.activate {
            copyContent.append("\n\("activate".localizedString): \(activate ? "Yes".localizedString : "No".localizedString)")
        }else {
            copyContent.append("\n\("activate".localizedString): N/A")
        }
        
        if let apn = node.gatewayModel?.apn {
            copyContent.append("\n\("apn".localizedString): \(apn)")
        }else {
            copyContent.append("\n\("apn".localizedString): N/A")
        }
        if let mqttServerInfo = node.gatewayModel?.mqttServerInfo {
            let serverStr = mqttServerInfo.serverAddress.replacingOccurrences(of: "tcp://", with: "")
            let serverAddressArray = serverStr.components(separatedBy: ":")
            if let ip = serverAddressArray.first {
                copyContent.append("\n\("server_address".localizedString): \(ip)")
            }else {
                copyContent.append("\n\("server_address".localizedString): N/A")
            }
            if serverAddressArray.count >= 2 {
                let port = serverAddressArray[1]
                copyContent.append("\n\("port".localizedString): \(port)")
            }else {
                copyContent.append("\n\("port".localizedString): N/A")
            }
            copyContent.append("\n\("client_id".localizedString): \(mqttServerInfo.clientId)")
        }else {
            copyContent.append("\n\("server_address".localizedString): N/A")
            copyContent.append("\n\("port".localizedString): N/A")
            copyContent.append("\n\("client_id".localizedString): N/A")
        }
        
        UIPasteboard.general.string = copyContent
        XWHUDManager.showTipHUD("copy_success".localizedString, isLineFeed: false)
    }
    
    private func updateData() {
        
        if node.isKeybindComplete {
            
            view.hideEmptyDataView()
            
            guard node.state else { // 离线
                
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
                bottomView.showCreateUI()
                view.bringSubviewToFront(bottomView)
                return
            }
            view.hideEmptyDataView()
            bottomView.showEditUI()
        } else {
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                    // 修复
                    self?.repair()
                }
                if let emptyView = view.emptyView {
                    if space.deviceOperates.contains(.edit) { // 是否有编辑设备权限
                        emptyView.button.snp.updateConstraints { make in
                            make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                        }
                    }else {
                        emptyView.button.isHidden = true
                    }
                }
                view.bringSubviewToFront(bottomView)
                bottomView.showCreateUI()
            }
        }
    }
    
    /// 修复
    private func repair() {
        
        repairDevices(nodes: [self.node], result: {[weak self] _, _ in
            guard let self = self else { return }
            if self.node.isKeybindComplete {
                self.updateData()
//                self.getNodeState()
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
        })
    }
    
    /// 保存
    @objc private func saveBtnAction() {
        
        guard self.space.deviceOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        if node.name != name {
            self.node.name = name
            self.title = name
            self.node.save()
        }
        guard let setGatewayModel = self.setGatewayModel else {
            return
        }
        node.gatewayModel?.update(gatewayModel: setGatewayModel)
        node.gatewayModel?.save()
        updateSaveBtnState()
        // 判断是否需要同步设备数据
        guard node.getNodeSyncGatewayData(gateway: setGatewayModel).count > 0 else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            return
        }
        let vc = SyncDevicesViewController(type: .devices([node]))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                self?.navigationController?.popViewController(animated: true)
                self?.updateSaveBtnState()
                self?.tableView.reloadData()
            }
        }
        vc.backActionCallback = {[weak self] _ in
            self?.navigationController?.popViewController(animated: true)
            self?.updateSaveBtnState()
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 删除
    @objc private func deleteBtnAction() {
        
        guard self.space.deviceOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "gateway_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            
            if let gatewayModel = node.gatewayModel, gatewayModel.associatedSpaces.contains(where: { $0.id == self.space.id }) {
                XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
                NetworkRequest.shared.request(.gatewayUnbindSpace(spaceId: space.id, gatewayId: gatewayModel.mac)) {[weak self] result in
                    XWHUDManager.hide()
                    guard let self = self else { return }
                    switch result {
                    case .success(_):
                        if let index = gatewayModel.associatedSpaces.firstIndex(where: { $0.id == self.space.id }) {
                            gatewayModel.associatedSpaces.remove(at: index)
                            gatewayModel.save()
                        }
                        if let index = self.setGatewayModel?.associatedSpaces.firstIndex(where: { $0.id == self.space.id }) {
                            self.setGatewayModel?.associatedSpaces.remove(at: index)
                        }
                        self.tableView.reloadData()
                        
                        self.resetNode(authorize: true)
                    case .failure:
                        XWHUDManager.showErrorTipHUD("delete_no_connect_server_message".localizedString)
                    }
                }
            }else {
                self.resetNode()
            }
        })]).show()
        
    }
    
    /// 重置设备
    /// - authorize: 是否服务器已授权
    private func resetNode(authorize: Bool = false) {

        let message = authorize ? "gateway_force_delete_message".localizedString : "gateway_no_authorize_force_delete_message".localizedString
        
        self.deleteNodes(nodes: [node], forceDeleteMessage: message, forceDeleteNote: "gateway_force_delete_note".localizedString) {[weak self] successNodes, failedNodes in
            guard let self = self else { return }
            if successNodes.contains(where: { $0.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                self.space.luminairesCount = MeshNetworkManager.instance.lightNodes.count
                self.space.save()
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
                    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                    // 通知space数据修改
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                    self.close()
                }
            }
        }

    }
    
    /// 服务器授权绑定网关
    private func authorizeRequest() {
        guard let gatewayModel = node.gatewayModel else {
            XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
            return
        }
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        
        Task {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            
            // 判断网关是否注册mqtt服务
            if gatewayModel.mqttServerInfo == nil {
                let gatewayRegisterResult = await NetworkRequest.shared.request(.gatewayRegister(gatewayId: gatewayModel.mac))
                switch gatewayRegisterResult {
                case .success(let response):
                    // MQTT参数
                    if let data = response["data"] as? [String: Any],
                       let username = data["mqttUsername"] as? String,
                       let password = data["mqttPassword"] as? String,
                       let clientId = data["mqttClientId"] as? String,
                       let host = data["host"] as? String, let port = data["port"] as? Int {
                        let mqttServerInfo = GatewayInformation.MQTTConnectInformation(customId: customId, serverAddress: "tcp://\(host):\(port)", userName: username, password: password, clientId: clientId, keepalive: 60, clearSession: true, authMode: .none, sslVersion: .all)
                        self.setGatewayModel?.mqttServerInfo = mqttServerInfo
                        self.node.gatewayModel?.mqttServerInfo = mqttServerInfo
                        self.node.gatewayModel?.save()
                        
                        // 同步到设备
                        if let vendorModel = self.node.sunricherVendorModel {
                            _ = await MeshAPI.sendMessage(message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(connectInfo: mqttServerInfo)), model: vendorModel)
                        }
                    }
                case .failure:
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD("server_failure".localizedString)
                    return
                }
            }
            
            // 判断网关是否绑定到space
            if !gatewayModel.associatedSpaces.contains(where: { $0.id == self.space.id }) {
                let bindSpaceResult = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: self.space.id, gatewayId: gatewayModel.mac))
                switch bindSpaceResult {
                case .success:
                    gatewayModel.associatedSpaces.append(self.space)
                    self.setGatewayModel?.associatedSpaces.append(self.space)
                    gatewayModel.save()
                    break
                case .failure:
                    XWHUDManager.hide()
//                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    XWHUDManager.showErrorTipHUD("server_failure".localizedString)
                    return
                }
            }
            
            XWHUDManager.hide()
            self.tableView.reloadData()
            self.updateSaveBtnState()
        }
    }
    
    private func resync() {
       
        let vc = SyncDevicesViewController(type: .devices([node]), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            self?.updateSaveBtnState()
            self?.tableView.reloadData()
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func setupUI() {
        
        bottomView = DeviceBottomBtnView()
        bottomView.createBtn.setTitle("DELETE".localizedString, for: .normal)
        bottomView.createBtn.setTitleColor(Red_Color, for: .normal)
        bottomView.createBtn.addTarget(self, action: #selector(deleteBtnAction), for: .touchUpInside)
        bottomView.saveBtn.addTarget(self, action: #selector(saveBtnAction), for: .touchUpInside)
        bottomView.deleteBtn.addTarget(self, action: #selector(deleteBtnAction), for: .touchUpInside)
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
//        headerView = GatewayInformationHeaderView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: 72))
        
        footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: SCRYFrom(62)))
        copyInformationBtn = UIButton(title: "copy_gateway_information".localizedString, titleSize: 14, titleColor: ImportantText_Color, normalImageName: "share_copy", target: self, action: #selector(copyInformationBtnAction))
        copyInformationBtn.setImagePosition(position: .right, spacing: SCRXFrom(8))
        footerView.addSubview(copyInformationBtn)
        copyInformationBtn.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(GatewayNameViewCell.classForCoder(), forCellReuseIdentifier: "name")
        tableView.register(GatewayServerInformationViewCell.classForCoder(), forCellReuseIdentifier: "serverInformation")
        tableView.register(GatewaySectionHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.estimatedSectionHeaderHeight = UITableView.automaticDimension
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.keyboardDismissMode = .onDrag
        tableView.enableKeyboardDismissal()
//        tableView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(16))
//        tableView.tableHeaderView = headerView
        tableView.tableFooterView = footerView
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        if !space.deviceOperates.contains(.edit) {
            bottomView.isHidden = true
            tableView.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(view.safeAreaLayoutGuide)
                make.bottom.equalToSuperview()
            }
        }
        
    }
    
    /// 更新保存按钮状态
    private func updateSaveBtnState() {
        guard let setGatewayModel = self.setGatewayModel, let initialGatewayModel = node.gatewayModel else {
            return
        }
        
        bottomView.saveBtn.isEnabled = self.space.deviceOperates.contains(.edit) && (!(setGatewayModel == initialGatewayModel) || (!(name?.isAllInputTextEmpty() ?? true) && node.name != name))
    }
    
    /// 选择sim卡 APN
    private func selectSIMAPN(point: CGPoint) {
        
        let items = [
             GatewayAPNMenuView.APNMenuItem(title: "not_set".localizedString, children: nil),
             GatewayAPNMenuView.APNMenuItem(title: "singapore".localizedString, children: ["internet", "shwap", "sunsurf", "tpg"]),
             GatewayAPNMenuView.APNMenuItem(title: "china".localizedString, children: ["cmnet", "3gnet", "ctnet"]),
             GatewayAPNMenuView.APNMenuItem(title: "usa".localizedString, children: ["phone", "internet", "fast.t-mobile.com"]),
             GatewayAPNMenuView.APNMenuItem(title: "canada".localizedString, children: ["ltemobile.apn", "pda.bell.ca", "sp.telus.com"]),
             GatewayAPNMenuView.APNMenuItem(title: "germany".localizedString, children: ["telekom.de", "web.vodafone.de", "internet"])
         ]
        
        GatewayAPNMenuView(menuItems: items, selectApnName: setGatewayModel?.apn, showPoint: point) {[weak self] apn in
            guard let self = self else { return }
            if apn == "not_set".localizedString { // 未选择
                self.setGatewayModel?.apn = nil
            }else {
                self.setGatewayModel?.apn = apn
            }
            if let section = self.sections.firstIndex(of: .apn) {
                self.tableView.reloadSections(IndexSet(integer: section), with: .none)
            }
            self.updateSaveBtnState()
        }.show()
         
    }

}

extension GatewayViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = sections[section]
        switch sectionType {
        case .associatedSpaces:
            return 1
        case .info:
            return 2
        default:
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionType = sections[indexPath.section]
        var tableviewCell: UITableViewCell!
        
        switch sectionType {
        case .name:
            let nameCell = tableView.dequeueReusableCell(withIdentifier: "name", for: indexPath) as! GatewayNameViewCell
            nameCell.nameField.text = name
            nameCell.nameField.isEnabled = self.space.deviceOperates.contains(.edit)
            nameCell.nameEditChangedCallback = {[weak self] name in
                if name.count > 32 && !name.isEmpty { // 长度超限
                    self?.bottomView.saveBtn.isEnabled = false
                    return "text_length_exceeded".localizedString
                }else if (MeshNetworkManager.instance.isNodeTautonym(nodeName: name) ) && name != self?.node.name { // 重名
                    self?.bottomView.saveBtn.isEnabled = false
                    return "name_already_exists".localizedString
                }
                self?.name = name
                self?.updateSaveBtnState()
                return nil
            }
            tableviewCell = nameCell
        case .info:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.contentLabel.textColor = SubText_Color
            cell.contentLabel.text = nil
            if indexPath.row == 0 {
                cell.titleLabel.text = "mac".localizedString
                cell.contentLabel.text = node.macAddressResult
                cell.cellStyle = .none
            }else if indexPath.row == 1 {
                cell.titleLabel.text = "activate".localizedString
                cell.cellStyle = .switch
                cell.enabledSwitch.isOn = setGatewayModel?.activate ?? false
                cell.switchActionCallback = {[weak self] enable in
                    guard let self = self else { return }
                    guard self.space.deviceOperates.contains(.edit) else {
                        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                        return
                    }
                    guard self.node.gatewayModel?.mqttServerInfo != nil else {
                        XWHUDManager.showErrorTipHUD("gateway_not_authorize_message".localizedString)
                        return
                    }
                    guard !self.otherGateways.contains(where: { $0.activate }) else {
                        SRAlertView(title: "notification".localizedString, message: "gateway_disable_activate_message".localizedString, actions: [SRAlertAction(title: "GOT IT".localizedString)]).show()
                        return
                    }
                    cell.enabledSwitch.isOn = enable
                    self.setGatewayModel?.activate = enable
                    self.updateSaveBtnState()
                }
            }
            tableviewCell = cell
        case .associatedSpaces:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.contentLabel.text = "Nodes: 70"
            cell.contentLabel.textColor = SubText_Color
            cell.cellStyle = .icon
            cell.arrowImageView.isHidden = true
            cell.iconX = tableView.width - SCRXFrom(8) - 30
            cell.iconImageView.image = UIImage(named: "share_delete")
            cell.iconImageClickCallback = {
                
            }
            tableviewCell = cell
        case .apn:
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.cellStyle = .arrow
            cell.titleLabel.text = nil
            cell.arrowImageView.image = UIImage(named: "arrow_down_black")
            cell.contentLabel.text = setGatewayModel?.apn
            cell.contentLabel.textColor = ImportantText_Color
            tableviewCell = cell
        case .serverInformation:
            let cell = tableView.dequeueReusableCell(withIdentifier: "serverInformation", for: indexPath) as! GatewayServerInformationViewCell
            if let serverInfo = setGatewayModel?.mqttServerInfo {
                let serverAddressArray = serverInfo.serverAddress.components(separatedBy: ":")
                cell.serverAddressField.text = serverAddressArray.first ?? "N/A"
                cell.portField.text = serverAddressArray.count >= 2 ? serverAddressArray[1] : "N/A"
                cell.clientIdField.text = serverInfo.clientId
            }else {
                cell.serverAddressField.text = "N/A"
                cell.portField.text = "N/A"
                cell.clientIdField.text = "N/A"
            }
            tableviewCell = cell
        }
        tableviewCell.configureCell(isFirst: indexPath.row == 0, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
        tableviewCell.selectionStyle = .none
        return tableviewCell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let sectionType = sections[indexPath.section]
        if sectionType == .serverInformation {
            return SCRYFrom(144)
        }
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GatewaySectionHeaderView
        let sectionType = sections[section]
        headerView.operationBtn.isHidden = true
        headerView.operationBtn.setImage(nil, for: .normal)
        headerView.operationBtn.setTitleColor(Bar_Color, for: .normal)
        headerView.operationBtn.layer.cornerRadius = 0
        headerView.operationBtn.layer.borderWidth = 0
        headerView.messageLabel.isHidden = true
        headerView.titleLabel.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        headerView.messageLabel.snp.remakeConstraints { make in
            make.top.equalTo(headerView.titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.left.equalTo(headerView.titleLabel)
            make.right.equalTo(SCRXFrom(-102))
        }
        switch sectionType {
        case .name:
            headerView.titleLabel.text = "name".localizedString
            if let gateway = node.gatewayModel, node.getNodeSyncGatewayData(gateway: gateway).count > 0 {
                headerView.operationBtn.isHidden = false
                headerView.operationBtn.setImage(UIImage(named: "schedule_sync_failed"), for: .normal)
                headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
                headerView.operationBtn.setTitle("devices_not_synced".localizedString, for: .normal)
                headerView.operationBtn.setTitleColor(Red_Color, for: .normal)
                headerView.operationBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
                headerView.operationBtn.snp.remakeConstraints { make in
                    make.right.equalTo(0)
                    make.bottom.equalTo(SCRYFrom(-6))
                }
            }
        case .info:
            headerView.titleLabel.text = nil
            headerView.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(16))
                make.bottom.equalToSuperview()
            }
        case .associatedSpaces:
            headerView.titleLabel.text = "associated_spaces".localizedString
            headerView.operationBtn.isHidden = false
            headerView.operationBtn.setTitle("\("Add".localizedString) ＋", for: .normal)
            headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14)
            headerView.operationBtn.snp.remakeConstraints { make in
                make.right.equalTo(SCRXFrom(-12))
                make.bottom.equalTo(SCRYFrom(-8))
            }
        case .apn:
            headerView.titleLabel.text = "apn".localizedString
        case .serverInformation:
            headerView.titleLabel.text = "server_information".localizedString
            if setGatewayModel?.mqttServerInfo == nil {
                headerView.messageLabel.isHidden = false
                headerView.messageLabel.text = "gateway_server_not_authorize".localizedString
                headerView.operationBtn.isHidden = false
                headerView.operationBtn.setTitle("authorize".localizedString, for: .normal)
                headerView.operationBtn.layer.cornerRadius = SCRYFrom(5)
                headerView.operationBtn.layer.borderWidth = 0.5
                headerView.operationBtn.layer.borderColor = Bar_Color.cgColor
                headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 13)
                
                headerView.titleLabel.snp.remakeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.top.equalTo(SCRYFrom(16))
                }
                headerView.messageLabel.snp.remakeConstraints { make in
                    make.top.equalTo(headerView.titleLabel.snp.bottom).offset(SCRYFrom(8))
                    make.left.equalTo(headerView.titleLabel)
                    make.right.equalTo(SCRXFrom(-86))
                    make.bottom.equalTo(SCRYFrom(-8))
                }
                
                headerView.operationBtn.snp.remakeConstraints { make in
                    make.right.equalToSuperview()
                    make.top.equalTo(headerView.messageLabel)
                    make.width.equalTo(SCRXFrom(66))
                    make.height.equalTo(SCRYFrom(32))
                }
            }
        }
        headerView.operationActionCallback = {[weak self] in
            guard let self = self else { return }
            switch sectionType {
            case .name: // 同步
                guard self.space.deviceOperates.contains(.edit) else {
                    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                    return
                }
                resync()
            case .associatedSpaces: // 添加space
                print("添加space")
            case .serverInformation: // 服务器授权
                guard self.space.deviceOperates.contains(.edit) else {
                    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                    return
                }
                self.authorizeRequest()
            default:
                break
            }
        }
        return headerView
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
        case .apn:
            guard self.space.deviceOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            if let cell = tableView.cellForRow(at: indexPath) {
                let viewPoint = view.convert(CGPoint(x: cell.frame.maxX - GatewayAPNMenuView.defalutWidth, y: cell.frame.maxY), from: tableView)
                let windowPoint = view.convert(viewPoint, to: UIApplication.shared.keyWindow())
                selectSIMAPN(point: windowPoint)
            }
            
        default:
            break
        }
    }
    
}

extension GatewayViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if node.primaryUnicastAddress == self.node.primaryUnicastAddress {
            updateData()
        }
    }
}

extension GatewayViewController {
 
    /// seciton 组类型
    enum SectionType {
        /// 名称
        case name
        /// 基本信息
        case info
        /// 关联spaces
        case associatedSpaces
        /// APN
        case apn
        /// MQTT服务器信息
        case serverInformation
    }
    
    enum CellType {
        
        var title: String {
            switch self {
            case .name:
                return "name".localizedString
            case .mac:
                return "mac".localizedString
            case .activate:
                return "activate".localizedString
            case .apn:
                return "apn_full".localizedString
            case .serverInformation:
                return "server_information".localizedString
            }
        }
        
        case name
        case mac
        case activate
//        case space
        case apn
        case serverInformation
    }
}
