//
//  GatewayViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/17.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

class GatewayViewController: UIViewController, DeviceProtocol {

    private var tableView: UITableView!
    private var headerView: GatewayInformationHeaderView!
    private var footerView: UIView!
    private var copyInformationBtn: UIButton!
    private var bottomView: DeviceBottomBtnView!
    
    
    private var name: String?
    
    private let setGatewayModel: GatewayModel
    /// 其它网关数据
//    private var otherGateways: [GatewayModel] = []
    
    private var sections: [SectionType] = [.name, .info, .associatedSpaces, .apn, .serverInformation]
    private let infoTypes: [InfoCellType] = [.mac, .address, .model, .deviceType, .firmwareVersion, .activate]
    /// 是否连接中
    private var isConnecting: Bool = false
    /// 网关在线状态缓存
    private var onlineState: Bool = false
    /// 页面当前是否可见
    private var isViewVisible: Bool = false
    /// 网关 4G 信号刷新定时器
    private var signalRefreshTimer: Timer?
    
    let site: SiteData
    let gateway: Gateway
    let gatewayModel: GatewayModel
    let node: Node
    private weak var lastMessageDelegate: MeshLibManagerMessageDelegate?
    
    init?(site: SiteData, gateway: Gateway) {
        self.site = site
        self.gateway = gateway
        self.gatewayModel = gateway.model
        self.node = gateway.node
        self.setGatewayModel = self.gatewayModel.copy()
        super.init(nibName: nil, bundle: nil)
        
//        let gateways = GatewayModel.load(siteId: gateway.siteId).filter({ $0.mac != gateway.mac })
//        // 确保是space内的网关
//        otherGateways = gateways.filter({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: $0.address) != nil })
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = gatewayModel.name
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        onlineState = node.state
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(closeAction))
        
        name = gatewayModel.name
        lastMessageDelegate = MeshLibManager.manager.messageDelegate
        
        setupUI()
        updateData()
        updateSaveBtnState()
        
//        Task {
//            guard let vendorModel = node.sunricherVendorModel else { return }
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimActivateState), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewayMqttState), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCpin), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCreg), model: vendorModel)
//            _ = await MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCpsi), model: vendorModel)
//            
//        }
//        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString != self.site.meshUUID {
//            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.site.meshUUID, subNetworkId: self.site.meshNetworkId, connected: false)
//            self.node = self.gateway.node
//            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
//                self?.setNetworkConnected()
//            }
//        }
        setNetworkConnected()
        
        // 获取网关关联space数据
        Task { [weak self] in
            guard let self else { return }
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
            let result = await self.loadAssociatedSpaces()
            guard !Task.isCancelled else { return }
            XWHUDManager.hide()
            switch result {
            case .success(let bindSpaces):
                let currentAssociatedSpaceIds = self.gatewayModel.associatedSpaces.map({ $0.spaceId })
                self.gatewayModel.associatedSpaces = bindSpaces
                self.setGatewayModel.associatedSpaces = bindSpaces
                self.reloadSection(.associatedSpaces)
                if bindSpaces.map({ $0.spaceId }) != currentAssociatedSpaceIds {
                    self.gatewayModel.save()
                }
                
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        isViewVisible = true
        MeshLibManager.manager.messageDelegate = self
        syncSignalRefreshState(forceRefresh: node.state)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        isViewVisible = false
        stopSignalRefreshTimer()
    }
    

    @objc private func closeAction() {
        
        if setGatewayModel == gatewayModel {
            close()
        }else {
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "EXIT".localizedString, actionHandler: {[weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {[weak self] in
                    self?.close()
                }
            })]).show()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        // EmptyDataView uses frame layout, update it after container frame is finalized.
        view.emptyView?.frame = view.bounds
    }

    @objc private func close() {
        if self.presentingViewController != nil && navigationController?.viewControllers.count ?? 0 == 1  {
            dismiss(animated: true)
        }else {
            navigationController?.popViewController(animated: true)
        }
    }
    
    deinit {
        stopSignalRefreshTimer()
        MeshLibManager.manager.messageDelegate = self.lastMessageDelegate
        
        MeshLibManager.manager.close()
        
        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
    }

    /// 获取网络数据+网络连接
    private func setNetworkConnected() {
        // 读取网络数据
//        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false, afterDelay: 10)
//        DispatchQueue.global().async {[weak self] in
//            guard let self = self else { return }
//            
//            DispatchQueue.main.async {
//                XWHUDManager.hide()
        self.headerView.showConnectingUI()
        isConnecting = true
        self.updateData()
        MeshLibManager.manager.connectProxy(node: self.node) {[weak self] result in
            guard let self = self else { return }
            self.isConnecting = false
            self.headerView.hideConnectingUI()
            self.onlineState = self.node.state
            self.syncSignalRefreshState(forceRefresh: self.node.state)
            self.updateData()
            self.updateSaveBtnState()
        }

    }
    
    /// 获取网关信号
    private func getGatewaySignal() {
        guard node.state else {
            clearGatewaySignal()
            return
        }
        guard let vendorModel = self.node.sunricherVendorModel else { return }
        MeshAPI.sendMessage(message: SunricherVendorGet(function: .gatewaySimCpin), model: vendorModel) {[weak self] response in
            guard let self = self else { return }
            guard self.node.state else {
                self.clearGatewaySignal()
                return
            }
            if let statusMessage = response as? SunricherVendorStatus, case .gatewaySimCpinState(let cpin, let csqRssi, _) = statusMessage.status.parameters {
                self.gatewayModel.csqRssi = Int(csqRssi)
                self.gatewayModel.isSimInserted = cpin >= 0
            }else {
                self.gatewayModel.csqRssi = nil
            }
            self.updateData()
        }
    }
    
    @objc private func refreshGatewaySignal() {
        guard node.state else {
            stopSignalRefreshTimer()
            clearGatewaySignal()
            return
        }
        getGatewaySignal()
    }
    
    private func syncSignalRefreshState(forceRefresh: Bool = false) {
        guard isViewLoaded, isViewVisible else {
            stopSignalRefreshTimer()
            return
        }
        
        if node.state {
            startSignalRefreshTimer()
            if forceRefresh {
                getGatewaySignal()
            }
        } else {
            stopSignalRefreshTimer()
            clearGatewaySignal()
        }
    }
    
    private func startSignalRefreshTimer() {
        guard signalRefreshTimer == nil else { return }
        signalRefreshTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(refreshGatewaySignal), userInfo: nil, repeats: true)
        if let signalRefreshTimer {
            RunLoop.main.add(signalRefreshTimer, forMode: .common)
        }
    }
    
    private func stopSignalRefreshTimer() {
        signalRefreshTimer?.invalidate()
        signalRefreshTimer = nil
    }
    
    private func clearGatewaySignal() {
        guard gatewayModel.csqRssi != nil else { return }
        gatewayModel.csqRssi = nil
        updateData()
    }
    
    /// 获取已关联的spaces
    private func loadAssociatedSpaces() async -> Result<[GatewaySpaceData], Error> {
        
        let result = await NetworkRequest.shared.request(.gatewayAssociationSpaceList(siteId: gatewayModel.siteId, gatewayId: gatewayModel.mac))
        switch result {
        case .success(let response):
            let list = JSON(response)["data"]["refSpaces"].arrayValue
            // 网关已绑定的space
            let bindSpaces: [GatewaySpaceData] = list.compactMap { spaceJson in
                guard let spaceId = spaceJson["spaceId"].string, let spaceName = spaceJson["spaceName"].string, let deviceCount = spaceJson["deviceCount"].int, let appKeyIndex = spaceJson["appKey"]["index"].uInt16 else {
                    return nil
                }
                let gatewaySpace = GatewaySpaceData(spaceId: spaceId, spaceName: spaceName, deviceCount: deviceCount, appKeyIndex: appKeyIndex)
                if let space = SpaceData.load(siteId: self.gatewayModel.siteId, spaceId: spaceId).first {
                    if space.canEditing {
                        gatewaySpace.permission = .editor
                    }else {
                        if space.state == .waitDeleted {
                            gatewaySpace.permission = .permissionLoss
                        }else if space.requiresPasswordVerification {
                            gatewaySpace.permission = .permissionException
                        }else {
                            gatewaySpace.permission = .none
                        }
                    }
                }
                return gatewaySpace
            }
            return .success(bindSpaces)
            
        case .failure(let error):
            return .failure(error)
        }
    }
    
    
    @objc private func copyInformationBtnAction() {
        
        var copyContent: String = ""
//        if gateway.name {
            copyContent.append("\("name".localizedString): \(gatewayModel.name)")
//        }else {
//            copyContent.append("\("name".localizedString): N/A")
//        }
        
//        if let mac = node.gatewayModel?.mac {
        copyContent.append("\n\("MAC".localizedString): \(node.macAddressResult ?? gatewayModel.mac)")
//        }else {
//            copyContent.append("\n\("MAC".localizedString): N/A")
//        }
        copyContent.append("\n\("address".localizedString): \(node.primaryUnicastAddress)")
        
        if let modelName = node.modelName {
            copyContent.append("\n\("model".localizedString): \(modelName)")
        }
        
        if let categoryName = node.categoryName {
            copyContent.append("\n\("device_type".localizedString): \(categoryName)")
        }
        
        if let version = node.firmwareVersion {
            copyContent.append("\n\("firmware".localizedString): \(version)")
        }
  
//        if let activate = gateway.activate {
            copyContent.append("\n\("activate".localizedString): \(gatewayModel.activate ? "Yes".localizedString : "No".localizedString)")
//        }else {
//            copyContent.append("\n\("activate".localizedString): N/A")
//        }
        
        if gatewayModel.associatedSpaces.count > 0 {
            let spacesName = gatewayModel.associatedSpaces.map({ $0.spaceName }).joined(separator: ",")
            copyContent.append("\n\("associated_spaces".localizedString): \(spacesName)")
        }else {
            copyContent.append("\n\("associated_spaces".localizedString): \("no_associated_spaces".localizedString)")
        }
        
        if let apn = gatewayModel.apn {
            copyContent.append("\n\("apn".localizedString): \(apn)")
        }else {
            copyContent.append("\n\("apn".localizedString): \("not_set".localizedString)")
        }
        if let mqttServerInfo = gatewayModel.mqttServerInfo {
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
            
//            guard node.state else { // 离线
//                
//                view.showEmptyDataView(imageName: "device_state_offline", title: "device_offline_message".localizedString, backgroundColor: Background_Color)
//                bottomView.showCreateUI()
//                view.bringSubviewToFront(bottomView)
//                return
//            }
//            view.hideEmptyDataView()
            headerView.updateData(gateway: gateway)
            if isConnecting {
                bottomView.deleteBtn.isEnabled = false
            }else {
                // 无权限
                if gatewayModel.associatedSpaces.contains(where: { $0.permission == .none || $0.permission == .permissionLoss || $0.permission == .permissionException }) {
                    bottomView.deleteBtn.isEnabled = false
                }else {
                    bottomView.deleteBtn.isEnabled = true
                }
            }
          
            bottomView.showEditUI()
        } else {
            if view.emptyView == nil {
                view.showEmptyDataView(imageName: "device_state_offline", title: "device_repair_message".localizedString, backgroundColor: Background_Color, buttonText: "repair".localizedString, buttomWidth: SCRXFrom(216), bottomMargin: SCRYFit(-78)) {[weak self] in
                    // 修复
                    self?.repair()
                }
                if let emptyView = view.emptyView {
                    if site.deviceOperates.contains(.edit) { // 是否有编辑设备权限
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
     
        repairDevices(nodes: [node], result: {[weak self] _, _ in
            guard let self = self else { return }
            if self.node.isKeybindComplete {
                self.updateData()
//                self.getNodeState()
                // 通知网关数据修改
                NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            }
        })
    }
    
    /// 保存
    @objc private func saveBtnAction() {
        guard let name = self.name, !name.isAllInputTextEmpty() else {
            return
        }
        guard gateway.associatedSpaces.isEmpty || gateway.associatedSpaces.contains(where: { $0.permission == .editor }) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
//        guard self.site.permissionOperates.contains(.edit) else {
//            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
//            return
//        }
        
        if gateway.name != name {
            self.setGatewayModel.name = name
            self.gateway.name = name
            self.node.name = name
            self.title = name
            self.node.save()
        }
        
        setGatewayModel.associatedSpaces = gateway.associatedSpaces
        gatewayModel.update(gatewayModel: setGatewayModel)
        gateway.model.save()
        //        node.gatewayModel?.update(gatewayModel: setGatewayModel)
        //        node.gatewayModel?.save()

        updateSaveBtnState()
        // 判断是否需要同步设备数据
        guard node.getNodeSyncGatewayData(gateway: setGatewayModel).count > 0 else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            // 通知网关数据修改
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            return
        }
        let vc = SyncDevicesViewController(type: .devices([node]))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
                self?.updateSaveBtnState()
                self?.tableView.reloadData()
            }
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            self.updateSaveBtnState()
            self.tableView.reloadData()
            
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 删除
    @objc private func deleteBtnAction() {
        
        guard self.site.deviceOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "gateway_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_continue".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 是否已注册网关
            if self.gatewayModel.mqttServerInfo != nil || self.gatewayModel.lastUploadCloudTimestamp != nil {
                Task {
                    XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
                    if self.site.permission != .owner {
                        let result = await self.loadAssociatedSpaces()
                        switch result {
                        case .success(let bindSpaces):
                            // 检查是否关联了无权限的space
                            if bindSpaces.contains(where: { $0.permission == .none || $0.permission == .permissionLoss || $0.permission == .permissionException }) {
                                XWHUDManager.hide()
                                XWHUDManager.showErrorTipHUD("no_permission".localizedString)
                                return
                            }
                        case .failure(let error):
                            XWHUDManager.hide()
                            XWHUDManager.showErrorTipHUD(error.localizedDescription)
                            return
                        }
                    }
                    
                    let deleteResult = await NetworkRequest.shared.request(.gatewayDelete(gatewayId: self.gateway.mac))
                    switch deleteResult {
                    case .success(_):
                        self.gatewayModel.mqttServerInfo = nil
                        self.gatewayModel.associatedSpaces.removeAll()
                        self.setGatewayModel.mqttServerInfo = nil
                        self.setGatewayModel.associatedSpaces.removeAll()
                        self.gatewayModel.lastUploadCloudTimestamp = nil
                        self.gatewayModel.save()
                        self.resetNode(authorize: true)
                    case .failure(let error):
                        XWHUDManager.hide()
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
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
//                self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
//                self.space.luminairesCount = MeshNetworkManager.instance.lightNodes.count
//                self.space.save()
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {
//                    NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
                    // 通知space数据修改
//                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                    self.gatewayModel.delete()
                    self.close()
                    NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
                }
            }else {
                if authorize {
                    // 通知网关数据修改
                    NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
                }
                self.tableView.reloadData()
            }
        }

    }
    
    
    /// 服务器授权绑定网关
    private func authorizeRequest() {

        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        
        Task {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            
            // 判断网关是否注册mqtt服务
            if self.gatewayModel.mqttServerInfo == nil, let nodeDict = await node.export() {
                let gatewayRegisterResult = await NetworkRequest.shared.request(.gatewayRegister(siteId: self.site.id, gatewayId: self.gateway.mac, nodeId: self.node.uuid.uuidString, node: nodeDict, updateTimestamp: self.gateway.lastUpdate))
                switch gatewayRegisterResult {
                case .success(let response):
                    // MQTT参数
                    if let data = response["data"] as? [String: Any],
                       let username = data["mqttUsername"] as? String,
                       let password = data["mqttPassword"] as? String,
                       let clientId = data["mqttClientId"] as? String,
                       let host = data["host"] as? String, let port = data["port"] as? Int {
                        let mqttServerInfo = GatewayInformation.MQTTConnectInformation(customId: customId, serverAddress: "tcp://\(host):\(port)", userName: username, password: password, clientId: clientId, keepalive: 60, clearSession: true, authMode: .none, sslVersion: .all)
                        self.setGatewayModel.mqttServerInfo = mqttServerInfo
                        self.gatewayModel.mqttServerInfo = mqttServerInfo
                        self.gatewayModel.save()
                        
                        // 同步到设备
                        if let vendorModel = self.node.sunricherVendorModel {
                            _ = await MeshAPI.sendMessage(message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(connectInfo: mqttServerInfo)), model: vendorModel)
                        }
                        
                        // 通知网关数据修改
                        NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
                    }
                case .failure:
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD("server_failure".localizedString)
                    return
                }
            }
            
//             判断网关是否绑定到space
//            if !gateway.associatedSpaces.contains(where: { $0.id == self.space.id }) {
//                let bindSpaceResult = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: self.space.id, gatewayId: gateway.mac))
//                switch bindSpaceResult {
//                case .success:
//                    gateway.associatedSpaces.append(self.space)
//                    self.setGatewayModel?.associatedSpaces.append(self.space)
//                    gateway.save()
//                    break
//                case .failure:
//                    XWHUDManager.hide()
////                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
//                    XWHUDManager.showErrorTipHUD("server_failure".localizedString)
//                    return
//                }
//            }
            
            XWHUDManager.hide()
            self.tableView.reloadData()
            self.updateSaveBtnState()
        }
    }
    
    private func resync() {
        
        let vc = SyncDevicesViewController(type: .devices([node]), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            self.updateSaveBtnState()
            self.tableView.reloadData()
            // 通知网关数据修改
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    private func associatedSpaces() {
        
        guard gatewayModel.mqttServerInfo != nil else {
            XWHUDManager.showTipHUD("associate_space_unauthorized_message".localizedString, isLineFeed: true, afterDelay: 1.5)
            return
        }
        
        guard let meshNetwork = MeshNetworkManager.instance.meshNetwork else {
            return
        }
        let gatewaySpaceData: [GatewaySpaceData] = site.spaces.filter({ ($0.permission == .owner || $0.permission == .editor) && $0.state == .normal && !$0.requiresPasswordVerification && ($0.relevanceGatewayId == nil || $0.relevanceGatewayId == gateway.mac) }).compactMap({ space in
            if let appkey = meshNetwork.applicationKeys.first(where: { $0.boundNetworkKey.networkId.hex == space.meshNetworkId }) {
                let permission: GatewaySpaceData.GatewaySpacePermission
                if space.canEditing {
                    permission = .editor
                }else {
                    if space.state == .waitDeleted {
                        permission = .permissionLoss
                    }else {
                        permission = space.requiresPasswordVerification ? .permissionException : .none
                    }
                }
                return GatewaySpaceData(spaceId: space.id, spaceName: space.name, deviceCount: space.deviceCount, appKeyIndex: appkey.index, permission: permission)
            }
            return nil
        })

        let vc = GatewayAssociatedSpacesController(gateway: gatewayModel, spaces: gatewaySpaceData)
//        GatewayAssociatedSpacesController(spaces: gatewaySpaceData, selectSpaces: selectSpaces)
        vc.associatedSpacesSelectCallback = {[weak self] spaces in
            guard let self = self else { return }
            self.reloadSection(.associatedSpaces)
            self.reloadSection(.name)
            self.updateSaveBtnState()
            // 通知网关数据修改
            NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
            // 通知site数据更新
            NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    /// 解除空间关联
    private func unbindAssociatedSpace(_ space: GatewaySpaceData) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        
        NetworkRequest.shared.request(.gatewayUnbindSpace(spaceId: space.spaceId, gatewayId: gateway.mac)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else {
                return
            }
            switch result {
            case .success(_):
                if let index = self.gateway.associatedSpaces.firstIndex(where: { $0.spaceId == space.spaceId }) {
                    self.gateway.associatedSpaces.remove(at: index)
//                    self.setGatewayModel.associatedSpaces = self.gateway.associatedSpaces
                    self.reloadSection(.associatedSpaces)
                    self.updateSaveBtnState()
                }
                // 通知网关数据修改
                NotificationCenter.default.post(name: .init(siteGatewayDataChangedNotificaitonName), object: self.gateway)
                // 通知site数据更新
                NotificationCenter.default.post(name: .init(SiteStateChangeNotificationName), object: nil)
                
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    /// 选择sim卡 APN
    private func selectSIMAPN(point: CGPoint) {
        var items = GatewaySIMApnInfo.all.map({ GatewayAPNMenuView.APNMenuItem(title: $0.country, children: $0.apns) })
        items.insert(GatewayAPNMenuView.APNMenuItem(title: "not_set".localizedString, children: nil), at: 0)
        
        GatewayAPNMenuView(menuItems: items, selectApnName: setGatewayModel.apn, showPoint: point) {[weak self] apn in
            guard let self = self else { return }
            if apn == "not_set".localizedString { // 未选择
                self.setGatewayModel.apn = nil
            }else {
                self.setGatewayModel.apn = apn
            }
            if let section = self.sections.firstIndex(of: .apn) {
                self.tableView.reloadSections(IndexSet(integer: section), with: .none)
            }
            self.updateSaveBtnState()
        }.show()
         
    }
    
    /// 刷新section
    private func reloadSection(_ section: SectionType) {
        if let section = self.sections.firstIndex(of: section) {
            tableView.reloadSections(IndexSet(integer: section), with: .none)
        }
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
        
        headerView = GatewayInformationHeaderView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: SCRYFrom(72)))
        
        
        footerView = UIView(frame: CGRect(x: 0, y: 0, width: view.width - SCRXFrom(32), height: SCRYFrom(62)))
        copyInformationBtn = UIButton(title: "copy_gateway_information".localizedString, titleSize: 14, titleColor: ImportantText_Color, normalImageName: "share_copy", target: self, action: #selector(copyInformationBtnAction))
        copyInformationBtn.setImagePosition(position: .right, spacing: SCRXFrom(8))
        footerView.addSubview(copyInformationBtn)
        copyInformationBtn.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "infoCell")
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "associatedSpacesCell")
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "apnCell")
        tableView.register(GatewayNameViewCell.classForCoder(), forCellReuseIdentifier: "name")
        tableView.register(GatewayServerInformationViewCell.classForCoder(), forCellReuseIdentifier: "serverInformation")
        tableView.register(GatewaySectionHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.estimatedSectionHeaderHeight = UITableView.automaticDimension
        tableView.estimatedSectionHeaderHeight = SCRYFrom(41)
        tableView.showsVerticalScrollIndicator = false
        tableView.backgroundColor = .clear
        tableView.dataSource = self
        tableView.delegate = self
        tableView.enableKeyboardDismissal()
//        tableView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(16))
        tableView.tableHeaderView = headerView
        tableView.tableFooterView = footerView
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        if !site.deviceOperates.contains(.edit) {
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
        if self.isConnecting {
            bottomView.saveBtn.isEnabled = false
        }else {
            bottomView.saveBtn.isEnabled = self.site.deviceOperates.contains(.edit) && (!(setGatewayModel == gatewayModel) || (!(name?.isAllInputTextEmpty() ?? true) && node.name != name))
        }
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
            return max(gatewayModel.associatedSpaces.count, 1)
        case .info:
            return infoTypes.count
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
            nameCell.nameField.isEnabled = self.site.deviceOperates.contains(.edit)
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
            let cell = tableView.dequeueReusableCell(withIdentifier: "infoCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.contentLabel.textColor = SubText_Color
            cell.contentLabel.text = nil
            cell.cellStyle = .none
            let cellType = infoTypes[indexPath.row]
            cell.titleLabel.text = cellType.title
            switch cellType {
            case .mac:
                cell.contentLabel.text = node.macAddressResult
            case .address:
                cell.contentLabel.text = "\(node.primaryUnicastAddress)"
            case .model:
                cell.contentLabel.text = node.modelName ?? "--"
            case .deviceType:
                cell.contentLabel.text = node.categoryName ?? "--"
            case .firmwareVersion:
                cell.contentLabel.text = node.firmwareVersion ?? "--"
            case .activate:
                cell.cellStyle = .switch
                cell.enabledSwitch.isOn = setGatewayModel.activate
                cell.switchActionCallback = {[weak self] enable in
                    guard let self = self else { return }
                    guard !self.isConnecting else {
                        return
                    }
                    guard self.site.deviceOperates.contains(.edit) else {
                        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                        return
                    }
                    guard self.gatewayModel.mqttServerInfo != nil else {
                        XWHUDManager.showErrorTipHUD("gateway_not_authorize_message".localizedString)
                        return
                    }
//                    guard !self.otherGateways.contains(where: { $0.activate }) else {
//                        SRAlertView(title: "notification".localizedString, message: "gateway_disable_activate_message".localizedString, actions: [SRAlertAction(title: "GOT IT".localizedString)]).show()
//                        return
//                    }
                    cell.enabledSwitch.isOn = enable
                    self.setGatewayModel.activate = enable
                    self.updateSaveBtnState()
                }
            }
            
            tableviewCell = cell
        case .associatedSpaces:
            let cell = tableView.dequeueReusableCell(withIdentifier: "associatedSpacesCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            if gateway.associatedSpaces.count > 0 {
                let space = gateway.associatedSpaces[indexPath.row]
                cell.titleLabel.textColor = TextBlack_Color
                cell.titleLabel.text = space.spaceName
                cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
                cell.contentLabel.text = "\("nodes".localizedString) \(space.deviceCount)"
                cell.contentLabel.textColor = SubText_Color
                cell.cellStyle = .icon
                cell.arrowImageView.isHidden = true
                cell.iconX = tableView.width - SCRXFrom(8) - 30
                cell.iconImageView.image = UIImage(named: "share_delete")
                if space.permission == .permissionException || space.permission == .permissionLoss || space.permission == .none {
                    cell.titleLabel.textColor = Message_Color
                    cell.iconImageView.image = UIImage(named: "share_delete")?.withTintColor(Message_Color)
                }
                
                cell.iconImageClickCallback = {[weak self] in
                    guard let self = self else { return }
                    guard !self.isConnecting else {
                        return
                    }
                    guard space.permission == .editor else {
                        return
                    }
                    // 删除
                    self.unbindAssociatedSpace(space)
                }
            }else {
                cell.titleLabel.text = "no_associated_spaces".localizedString
                cell.titleLabel.textColor = Message_Color
                cell.cellStyle = .none
                cell.contentLabel.text = nil
            }
            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
            tableviewCell = cell
        case .apn:
            let cell = tableView.dequeueReusableCell(withIdentifier: "apnCell", for: indexPath) as! CustomTableViewCell
            cell.titleLabel.font = UIFont.systemFont(ofSize: 14)
            cell.contentLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
            cell.cellStyle = .arrow
            cell.titleLabel.text = nil
            cell.arrowImageView.image = UIImage(named: "arrow_down_black")
            cell.contentLabel.text = setGatewayModel.apn
            cell.contentLabel.textColor = ImportantText_Color
            tableviewCell = cell
        case .serverInformation:
            let cell = tableView.dequeueReusableCell(withIdentifier: "serverInformation", for: indexPath) as! GatewayServerInformationViewCell
            if let serverInfo = setGatewayModel.mqttServerInfo {
                let serverStr = serverInfo.serverAddress.replacingOccurrences(of: "tcp://", with: "")
                let serverAddressArray = serverStr.components(separatedBy: ":")
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
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.bottom.equalToSuperview().offset(SCRYFrom(-8))
        }
        headerView.messageLabel.snp.remakeConstraints { make in
            make.top.equalTo(headerView.titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.left.equalTo(headerView.titleLabel)
            make.right.equalTo(SCRXFrom(-102))
        }
        switch sectionType {
        case .name:
            headerView.titleLabel.text = "name".localizedString
            if node.getNodeSyncGatewayData(gateway: gatewayModel).count > 0 {
                headerView.operationBtn.isHidden = false
                headerView.operationBtn.setImage(UIImage(named: "schedule_sync_failed"), for: .normal)
                headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
                headerView.operationBtn.setTitle("devices_not_synced".localizedString, for: .normal)
                headerView.operationBtn.setTitleColor(Red_Color, for: .normal)
                headerView.operationBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
                headerView.operationBtn.snp.remakeConstraints { make in
                    make.right.equalTo(0)
                    make.bottom.equalToSuperview().offset(SCRYFrom(-6))
                }
            }
        case .info:
            headerView.titleLabel.text = nil
            headerView.titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalToSuperview().offset(SCRYFrom(16))
                make.bottom.equalToSuperview()
            }
        case .associatedSpaces:
            headerView.titleLabel.text = "associated_spaces".localizedString
            headerView.operationBtn.isHidden = false
            headerView.operationBtn.setTitle("\("Add".localizedString) ＋", for: .normal)
            headerView.operationBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14)
            headerView.operationBtn.snp.remakeConstraints { make in
                make.right.equalTo(SCRXFrom(-12))
                make.centerY.equalTo(headerView.titleLabel)
            }
        case .apn:
            headerView.titleLabel.text = "apn".localizedString
        case .serverInformation:
            headerView.titleLabel.text = "server_information".localizedString
            if setGatewayModel.mqttServerInfo == nil {
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
                    make.top.equalToSuperview().offset(SCRYFrom(16))
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
                    make.bottom.lessThanOrEqualTo(SCRYFrom(-8))
                }
            }
        }
        headerView.operationActionCallback = {[weak self] in
            guard let self = self else { return }
            guard !self.isConnecting else {
                return
            }
            switch sectionType {
            case .name: // 同步
                guard self.site.deviceOperates.contains(.edit), self.gateway.associatedSpaces.contains(where: { $0.permission == .editor }) else {
                    XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                    return
                }
                resync()
            case .associatedSpaces: // 添加space
                associatedSpaces()
            case .serverInformation: // 服务器授权
                guard self.site.deviceOperates.contains(.edit) else {
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

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UITableView.automaticDimension
    }
    
    func tableView(_ tableView: UITableView, estimatedHeightForHeaderInSection section: Int) -> CGFloat {
        let sectionType = sections[section]
        switch sectionType {
        case .serverInformation:
            if setGatewayModel.mqttServerInfo == nil {
                return SCRYFrom(80)
            }
            return SCRYFrom(44)
        default:
            return SCRYFrom(44)
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
        case .apn:
            guard self.site.deviceOperates.contains(.edit) else {
                XWHUDManager.showTipHUD("no_permission".localizedString + "！")
                return
            }
            if let cell = tableView.cellForRow(at: indexPath) {
                let viewPoint = view.convert(CGPoint(x: cell.frame.maxX - GatewayAPNMenuView.defaultWidth, y: cell.frame.maxY), from: tableView)
                var windowPoint = view.convert(viewPoint, to: UIApplication.shared.keyWindow())
                if windowPoint.y + GatewayAPNMenuView.defaultHeight > SCREEN_HEIGHT {
                    windowPoint = CGPoint(x: windowPoint.x, y: windowPoint.y - GatewayAPNMenuView.defaultHeight - SCRYFrom(44))
                }
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
            if node.state != onlineState {
                onlineState = node.state
                syncSignalRefreshState(forceRefresh: node.state)
            } else if !node.state {
                syncSignalRefreshState()
            }
            updateData()
        }
    }
    
    /// 设备数据修改时间戳更新
    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdateTimeChange node: Node, lastUpdate: Int64) {
//        if node.lastUpdateSyncTime != lastUpdate {
            node.clearSyncStateCache()
//        }
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
    
    /// 设备信息cell类型
    enum InfoCellType {
        
        var title: String {
            switch self {
            case .mac:
                return "mac".localizedString
            case .address:
                return "address".localizedString
            case .model:
                return "model".localizedString
            case .deviceType:
                return "device_type".localizedString
            case .firmwareVersion:
                return "firmware".localizedString
            case .activate:
                return "activate".localizedString
            }
        }
        
        case mac
        case address
        case model
        case deviceType
        case firmwareVersion
        case activate
    }
}
