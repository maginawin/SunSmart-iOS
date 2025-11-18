//
//  SiteDeviceAddViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/17.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth
import SwiftyJSON

class SiteDeviceAddViewController: UIViewController {

    private var navigationBackBtn: UIButton!
    private var scanAnimationView: UIImageView!
    /// header
    private var headerView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: RangeSlider!
    private var farLabel: UILabel!
    private var scanBtn: UIButton!
    /// 设备列表
    private var tableView: UITableView!
    /// 添加设备结果
    private var addResultView: DeviceAddResultView!
    /// 底部全选
    private var footerView: DeviceAddBottomView!
    /// 添加成功的设备list
    private var addSuccessNodes: [Node] = []
    
    /// 搜索设备定时器
    private var scanTimer: Timer?
    /// 找到的设备list
    private var scanDevices: [ProvisioningDevice] = []
    /// 展示的设备list（信号值筛选）
    private var showDevices: [ProvisioningDevice] = []
    /// 选择的信号值范围
//    private var filterRSSI: Int = 0
    private var selectRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 添加设备页面状态
    private var state: State = .none
    /// identify中的设备
    private var identifyDevice: ProvisioningDevice?
    
    private var rssiSortTimer: Timer?
    
    /// 添加设备回调
    var deviceAddCallback: (([Node])->Void)?
    
    let site: SiteData
    
    init(site: SiteData) {
        self.site = site
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        title = "add_device".localizedString
        
        navigationBackBtn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backClick))
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: navigationBackBtn)
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: scanAnimationView)
        
        setupUI()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if state == .scanning { // 退出页面/切换停止扫描
            stopScan()
        }
    }
    
    @objc private func backClick() {
        navigationController?.popViewController(animated: true)
    }
    
    deinit {
        if state == .adding {
            MeshAPI.stopFastAddDevice(finishBack: nil)
        }
        self.deviceAddCallback?(self.addSuccessNodes)
        
        if MeshNetworkManager.instance.currentNetworkKey.isPrimary {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
        
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    // MARK: - Scan
    
    private func startScan() {
        
        state = .scanning
        
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanAnimationView.isHidden = false
        scanAnimationView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "scan")
        
        startScanTimer()

        scanDevices.removeAll()
        showDevices.removeAll()
        tableView.reloadData()
        
        updateUIState()
        // 扫描中设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        
        MeshAPI.startScanDevice(.max, deviceScan: {[weak self] device in
            guard let self = self else { return }
            // 新发现设备
            if device.macAddress != nil && device.rssi.intValue >= self.filterRSSIRange.lowerBound, device.deviceType == .gateway {
                
                if device.rssi.intValue > self.filterRSSIRange.upperBound {
                    device.rssi = NSNumber(value: self.filterRSSIRange.upperBound)
                }
    
                self.stopScanTimer()
                
                device.selectedState = .selected
                device.addState = .scaning
                
                if let info = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.companyId == device.cid && $0.productId == device.pid }) {
                    device.deviceName = info.categoryName
                    device.elementCount = info.elementCount
//                    device.isSupport = true
                    device.icon = "device_\(info.iconCategory)"
                    device.deviceType = Node.DeviceType(deviceCategory: info.deviceCategory)
                    
                }else {
//                    device.isSupport = false
                    device.deviceType = .unknown
                    device.icon = "device_unknown"
                    device.selectedState = .disabled
                }
                
                if let index = self.scanDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
                    let cacheDevice = self.scanDevices[index]
                    cacheDevice.updateData(device: device)
                }else {
                    self.scanDevices.append(device)
                    
                    DispatchQueue.main.async {
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
                        self.perform(#selector(self.stopScan), with: nil, afterDelay: 8)
                    }
                }
                
                // 当前设备信号值在筛选范围内可展示
                self.startRssiSortTimer()
            }
            
        }, deviceScanFinish: nil)
    }
    
    @objc private func stopScan() {

        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
        }
        
        scanAnimationView.isHidden = true
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        
        scanBtn.isSelected = false
        MeshAPI.stopScan()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        // 停止扫描设备状态设置为空状态
        scanDevices.forEach({
            $0.addState = .none
//            reloadDeviceState($0)
        })
        
        updateUIState()
        
        stopScanTimer()
        if rssiSortTimer != nil {
            devicesRssiSort()
        }else {
            tableView.reloadData()
        }
    }
    
    // MARK: - Scan Timer
    private func startScanTimer() {
        scanTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(showDeviceNotFound), userInfo: nil, repeats: true)
        RunLoop.current.add(scanTimer!, forMode: .common)
    }
    
    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
        hideDeviceNotFound()
    }
    
    /// 显示找不到设备提示
    @objc private func showDeviceNotFound() {
        
        view.showEmptyDataView(imageName: "device_found_empty", title: "device_scan_notfound_title".localizedString, tipText: "device_scan_notfound_message".localizedString)
        
        if let emptyView = view.emptyView {
            emptyView.contentView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            emptyView.contentView.layer.cornerRadius = SCRYFrom(20)
            emptyView.contentView.backgroundColor = .white
            emptyView.tipLabel.textAlignment = .left
//            emptyView.tipLabel.lineBreakMode = .byClipping
            emptyView.tipLabel.textColor = RGB(148, 163, 184)
            emptyView.tipLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(16))
                make.bottom.equalTo(SCRYFrom(-28))
            }
            let shadeView = UIView(frame: view.bounds)
            shadeView.backgroundColor = RGB(0, 0, 0, 0.4)
            emptyView.insertSubview(shadeView, belowSubview: emptyView.contentView)
        }
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
            self.perform(#selector(self.hideDeviceNotFound), with: nil, afterDelay: 5)
        }
        
    }
    
    /// 隐藏找不到设备提示
    @objc private func hideDeviceNotFound() {
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
        }
        view.hideEmptyDataView()
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        guard rssiSortTimer == nil || !rssiSortTimer!.isValid else {
            return
        }
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 1, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        
        scanDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
        showDevices = scanDevices.filter({ selectRSSIRange.contains($0.rssi.intValue) })
//        if showDevices.count > 0 {
//            showDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
            tableView.reloadData()
        
//        }
    }
    
    // MARK: - Action
    /// 扫描
    @objc private func scanBtnClick(sender: UIButton) {
        
        if self.state == .adding || self.state == .identifying {
            // 提示设备正在操作中，不能扫描
//            XWHUDManager.showTipHUD(inView: "scan_disable_adding".localizedString, isLineFeed: true)
            return
        }
//        if self.state == .identifying {
//            // 提示设备正在操作中，不能扫描
//            XWHUDManager.showTipHUD(inView: "scan_disable_identify".localizedString, isLineFeed: true)
//            return
//        }
        
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
//            sender.setTitle("stop".localizedString, for: .normal)
            startScan()
        }else {
//            sender.setTitle("scan".localizedString, for: .normal)
            stopScan()
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
            }
        }
    }
    
    /// 全选/取消全选
    @objc private func selectAllBtnClick(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        
        let canAddDevices = showDevices.filter({ $0.selectedState != .disabled && !($0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting) })
        if sender.isSelected {
            canAddDevices.forEach({ $0.selectedState = .selected })
        }else {
            canAddDevices.forEach({ $0.selectedState = .unselected })
        }
        updateFooterViewState()
        tableView.reloadData()
    }
    
    /// 批量添加
    @objc private func addSelectedBtnClick() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        
        checkDeviceAddressesAreSufficient(devices: selectDevices)      
//        selectDevices.forEach { device in
//            addDevice(device)
//        }
    }
    
    /// 隐藏添加结果view
    @objc private func closeBtnClick() {
        addResultView.isHidden = true
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
    }
    
    /// 停止添加（取消正在排队的设备）
    @objc private func stopAddBtnClick() {
        guard state == .adding else {
            return
        }
//        TestDeviceAddManager.manager.cancelAwaitOperations()
        
        MeshAPI.cancelFastAddAwaitOperations()
        let waitDevices = showDevices.filter({ $0.addState == .wait })
        waitDevices.forEach({
            $0.addState = .none
            $0.selectedState = .selected
        })
        tableView.reloadData()
        updateUIState()
    }

    // MARK: - Mesh API
    
    /// 设备identify
    private func identify(_ device: ProvisioningDevice) {
        
        // 判断连接量是否达到上限
        let bleConnectCount = max(showDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        guard bleConnectCount < 5 else {
            device.addState = .identifyWait
            reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                if device.addState == .identifyWait {
                    device.addState = .none
                    self?.reloadDeviceState(device)
                }
            }
            return
        }
        
        if identifyDevice != nil {
            identifyDevice?.addState = .none
            reloadDeviceState(identifyDevice!)
            identifyDevice = nil
            MeshAPI.stopUnprovisionedDeviceIdentify()
        }
        
        device.addState = .identifyConnecting
        reloadDeviceState(device)
        if state == .none || state == .addFineshed {
            state = .identifying
            updateUIState()
        }
        identifyDevice = device
        MeshAPI.unprovisionedDeviceIdentify(device: device, attentionTimer: 6) {[weak self] _, _ in
            device.addState = .identifying
            self?.reloadDeviceState(device)
        } identifyFinished: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .none
            self.identifyDevice = nil
            self.reloadDeviceState(device)
            if self.state == .identifying {
                self.updateUIState()
            }
        } identifyFail: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .identifyFail
            self.reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                guard let self = self else { return }
                if device.addState == .identifyFail {
                    device.addState = .none
                    self.reloadDeviceState(device)
                }
                if self.state == .identifying {
                    self.updateUIState()
                }
            }
        }
    }
    
    /// 添加设备
    private func addDevice(_ device: ProvisioningDevice) {
        
        if MeshNetworkManager.instance.meshNetwork?.uuid == self.site.meshUUID, !MeshNetworkManager.instance.currentNetworkKey.isPrimary {
            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: <#T##String#>, connected: false)
        }
        
        // 设备identify中添加不需要再闪烁
//        if device.addState == .identifyConnecting || device.addState == .identifyWait || device.addState == .failed || device.addState == .identifying {
//            if device.addState == .identifying {
//                device.identifyAttentionTimer = 0
//            }
            if device.peripheral.identifier.uuidString == identifyDevice?.peripheral.identifier.uuidString {
                identifyDevice = nil
                MeshAPI.stopUnprovisionedDeviceIdentify()
            }
//        }
        // 添加设备不需要闪烁
        device.identifyAttentionTimer = 0
        if device.addState == .none {
            device.addState = .wait
            device.selectedState = .disabled
            reloadDeviceState(device)
        }
        updateUIState()
        MeshAPI.startFastAddDevices(devices: [device]) { [weak self] addDevice in
            addDevice.addState = .addConnecting
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } connectingBack: {[weak self] addDevice in
            addDevice.addState = .adding
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } provisionCompleteCallback: {[weak self] addDevice, node in
            guard let self = self else { return }
            node.rssi = addDevice.rssi.intValue
            if let macAddress = addDevice.macAddress {
                node.macAddress = macAddress
            }else {
                // 没有MAC，自动生成一个随机数
                let mac = MeshNetworkManager.instance.getRandomMacAddress()
                node.macAddress = mac
            }
            node.name = MeshNetworkManager.instance.getNextNodeName(node.defaultNameCategory)
//            if device.deviceType == .gateway {
//                node.name = MeshNetworkManager.instance.getNextNodeName("gateway".localizedString)
//            }else {
//                node.name = MeshNetworkManager.instance.getNextNodeName(node.defaultNameCategory)
//            }
            node.save()
            
            guard let mac = node.macAddress else {
                return
            }
            let gatewayModel = GatewayModel(siteId: self.site.id, address: node.primaryUnicastAddress, mac: mac)
            
            node.gatewayModel = gatewayModel
            gatewayModel.save()
            
            
        } appendMessagesBack: {[weak self] addDevice, appendCompletion in
            guard let self = self, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) else {
                appendCompletion([])
                return
            }
            var appendMessages: [MeshMessageHandle] = []

            if device.deviceType == .gateway, let mac = node.macAddress, NetworkRequest.shared.networkable {
                Task {
                    // 注册网关
                    let gatewayRegisterResult = await NetworkRequest.shared.request(.gatewayRegister(gatewayId: mac))
                    switch gatewayRegisterResult {
                    case .success(let response):
                        // MQTT参数
                        if let data = response["data"] as? [String: Any],
                           let username = data["mqttUsername"] as? String,
                           let password = data["mqttPassword"] as? String,
                           let clientId = data["mqttClientId"] as? String,
                           let host = data["host"] as? String, let port = data["port"] as? Int {
                            
                            node.gatewayModel?.mqttServerInfo = GatewayInformation.MQTTConnectInformation(customId: customId, serverAddress: "tcp://\(host):\(port)", userName: username, password: password, clientId: clientId, keepalive: 60, clearSession: true, authMode: .none, sslVersion: .all)
                            node.gatewayModel?.save()
                        }
                    case .failure:
                        break
                    }
                    
                    // 网关绑定到space
//                    let bindSpaceResult = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: self.space.id, gatewayId: mac))
//                    switch bindSpaceResult {
//                    case .success:
//                        node.gatewayModel?.associatedSpaces.append(self.space)
//                        node.gatewayModel?.save()
//                    case .failure:
//                        break
//                    }
                    
                    if let gateway = node.gatewayModel {
                        let syncDatas = node.getNodeSyncGatewayData(gateway: gateway)
                        syncDatas.forEach({
                            appendMessages.append(contentsOf: $0.getMessageHandles(node: node))
                        })
                    }
                    
                    // 添加成功后闪烁
                    if let healthModel = node.healthModel {
                        appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
                    }
                    appendCompletion(appendMessages)
                }
            }else {
                
                if let gateway = node.gatewayModel {
                    let syncDatas = node.getNodeSyncGatewayData(gateway: gateway)
                    syncDatas.forEach({
                        appendMessages.append(contentsOf: $0.getMessageHandles(node: node))
                    })
                }
                // 添加成功后闪烁
                if let healthModel = node.healthModel {
                    appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
                }
                appendCompletion(appendMessages)
            }
//            return appendMessages
        } appendMessageSuccessBack: { messageHandle in
            // 发送扩展消息成功更新缓存数据
            if let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                DispatchQueue.global().async {
                    node.updateData(message: messageHandle.message)
                }
            }
        } addSuccess: {[weak self] addDevice in
            guard let self = self else { return }
            addDevice.addState = .success
            self.reloadDeviceState(addDevice)
            self.updateUIState()
            if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) {
                if let repalceNode = addDevice.repalceNode { // 删除被替换节点的缓存数据
                    repalceNode.deleteExtension()
                }
                self.addSuccessNodes.append(node)
            }
        } addFail: {[weak self] addDevice, error in
            addDevice.addState = .failed
            addDevice.selectedState = .selected
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
            // 设备地址已分配完
            if case .noAddressAvailable = error {
                
            }
            
        } addFinish: {[weak self] successList, failList in
            guard let self = self else { return }
            
            // 通知space数据修改
//            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
//            self.addSuccessNodes.append(contentsOf: successNodes)
        }
        
    }
    
    /// 检查设备地址是否足够
    private func checkDeviceAddressesAreSufficient(devices: [ProvisioningDevice]) {

        let bleConnectCount = max(showDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        for (index, device) in devices.enumerated() {
            if index < (5 - bleConnectCount) {
                device.addState = .addConnecting
            }else {
                device.addState = .wait
            }
            device.selectedState = .disabled
            reloadDeviceState(device)
        }
        updateUIState()
        
        DispatchQueue.global().async {
            // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
            let estimatedAddressCount = devices.reduce(0, { (result, device) in result + device.elementCount })
            // 可用地址数量
            let availableUnicastCount = MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.site.meshUUID)
            
            // 检查剩余地址是否足够添加设备
            guard availableUnicastCount >= estimatedAddressCount else {
                
                // 获取网络内已存在的设备地址数量
                let existingAddressCount = Node.loadAddresses(meshUUID: self.site.meshUUID).count
                // 申请的地址数量
                let applyAddressCount = estimatedAddressCount - availableUnicastCount + Int(Float(existingAddressCount) * 0.2)
                
                // 地址不够
                // 手机是否联网
                guard NetworkRequest.shared.networkable else {
                    DispatchQueue.main.async {
//                        XWHUDManager.hide()
                        devices.forEach({
                            $0.addState = .none
                            $0.selectedState = .selected
                            self.reloadDeviceState($0)
                        })
                        self.updateUIState()
                        SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                            if NetworkRequest.shared.networkable {
                                self?.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
                            }
                        })]).show()
                    }
                    return
                }
                // 向服务器申请地址
                DispatchQueue.main.async {
//                    XWHUDManager.hide()
                    self.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount, devices: devices)
                }
                return
            }
            DispatchQueue.main.async {
                XWHUDManager.hide()
                devices.forEach({
                    self.addDevice($0)
                })
            }
        }
    }
    
    /// 申请设备地址请求
    /// - Parameters:
    ///   - applyAddressCount: 申请地址数量
    ///   - devices: 需要添加的设备
    private func applyDeviceAddressesRequest(applyAddressCount: Int, devices: [ProvisioningDevice] = []) {
        
//        // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
//        let estimatedAddressCount = devices.reduce(0, { (result, device) in result + device.elementCount })
//        // 获取网络内已存在的设备地址数量
//        let existingAddressCount = Node.loadAddresses(meshUUID: self.space.meshUUID).count
//        // 申请的地址数量
//        let applyAddressCount = estimatedAddressCount - MeshAPI.getNumberOfAvailableUnicastAddresses() + Int(Float(existingAddressCount) * 0.2)
        // request
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.applyAddress(siteId: self.site.id, type: .device, number: applyAddressCount)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let repsonsed):
                // 新增地址
                if let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                    self.site.setProvisioner(provisionerData: provisionerData)
                    // 继续添加设备
                    devices.forEach({
                        self.addDevice($0)
                    })
                }else {
                    devices.forEach({
                        $0.addState = .none
                        $0.selectedState = .selected
                        self.reloadDeviceState($0)
                    })
                    self.updateUIState()
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
                devices.forEach({
                    $0.addState = .none
                    $0.selectedState = .selected
                    self.reloadDeviceState($0)
                })
                self.updateUIState()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
       
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        if let index = showDevices.firstIndex(of: device) {
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? DeviceAddViewCell {
                cell.device = device
            }else {
                tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }
    }
    
    /// 更新底部view数量状态
    private func updateFooterViewState() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        let enableDevices = showDevices.filter({ $0.selectedState != .disabled })
        footerView.selectCountLabel.text = "\(selectDevices.count)/\(enableDevices.count)"
        if !enableDevices.isEmpty && selectDevices.count >= enableDevices.count {
            footerView.selectAllBtn.isSelected = true
        }else {
            footerView.selectAllBtn.isSelected = false
        }
        footerView.addSelectedBtn.isEnabled = selectDevices.count > 0
    }
    
    /// 更新UI
    private func updateUIState() {

        // 添加设备中
        if showDevices.contains(where: { $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }) {
            state = .adding
        }else if showDevices.contains(where: { $0.addState == .identifyConnecting || $0.addState == .identifying }) { // identify中
            state = .identifying
        }else if showDevices.contains(where: { $0.addState == .success || $0.addState == .failed }) { // 操作完成（add）
            state = .addFineshed
        }else if state != .scanning {
            state = .none
        }
        // 未操作、操作成功可以筛选信号
        rssiSlider.isEnabled = state == .none || state == .addFineshed
        scanBtn.isEnabled = state == .none || state == .scanning || state == .addFineshed
        
        UIApplication.shared.isIdleTimerDisabled = false
        navigationBackBtn.isHidden = false
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        switch state {
        case .none:
            footerView.isHidden = false
            addResultView.isHidden = true
            updateFooterViewState()
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
        case .scanning:
            footerView.isHidden = true
            tableView.contentInset = .zero
            addResultView.isHidden = true
        case .identifying:
            break
        case .adding, .addFineshed:
            footerView.isHidden = false
            updateFooterViewState()
            if state == .adding {
                addResultView.isHidden = false
                tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: addResultView.height + footerView.height + SCRYFrom(8), right: 0)
                addResultView.closeBtn.isHidden = true
                addResultView.stopAddBtn.isHidden = !showDevices.contains(where: { $0.addState == .wait})
                // 添加中设置屏幕常亮
                UIApplication.shared.isIdleTimerDisabled = true
                navigationBackBtn.isHidden = true
                navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            }else {
                addResultView.closeBtn.isHidden = false
                addResultView.stopAddBtn.isHidden = true
            }
            let successCount = scanDevices.filter({ $0.addState == .success }).count
            let failedCount = scanDevices.filter({ $0.addState == .failed }).count
            addResultView.successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
            addResultView.failedCountLabel.text = "\(failedCount)"
            
        }
    }
    
    /// 信号滑条修改
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        print(changeRSSIRange)
        selectRSSIRange = changeRSSIRange
        // 筛选展示的设备
        showDevices = scanDevices.filter({ selectRSSIRange.contains($0.rssi.intValue) })

        farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
        nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
         
        updateFooterViewState()
        tableView.reloadData()
        
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
//        let navigationHeight = (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
//            make.top.equalTo(kNavigationHeight)
            make.height.equalTo(SCRYFrom(64))	
        }
        
        scanBtn = UIButton(title: "scan".localizedString, titleSize: 13, titleColor: Bottom_Done_Color, normalImageName: "device_scan", target: self, action: #selector(scanBtnClick))
        scanBtn.setTitle("stop".localizedString, for: .selected)
        scanBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        scanBtn.layer.cornerRadius = SCRYFrom(5)
        scanBtn.layer.borderWidth = 1
        scanBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        scanBtn.backgroundColor = .white
        scanBtn.contentHorizontalAlignment = .left
        scanBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
        scanBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: 0)
        headerView.addSubview(scanBtn)
        scanBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        nearLabel.sizeToFit()
        headerView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalTo(scanBtn)
            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        farLabel.sizeToFit()
        headerView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(scanBtn.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(nearLabel)
            make.width.equalTo(farLabel.width)
        }
        
        rssiSlider = RangeSlider()
        rssiSlider.trackHighlightTintColor = Slider_Color
        rssiSlider.trackHighlightDisableTintColor = Slider_Color.withAlphaComponent(0.5)
        rssiSlider.trackTintColor = RGB(229, 229, 229)
        rssiSlider.thumbDisableTintColor = Background_Color
        rssiSlider.minimumValue = Double(abs(filterRSSIRange.upperBound))
        rssiSlider.maximumValue = Double(abs(filterRSSIRange.lowerBound))
        rssiSlider.lowerValue = Double(abs(selectRSSIRange.upperBound))
        rssiSlider.upperValue = Double(abs(selectRSSIRange.lowerBound))
        rssiSlider.addTarget(self, action: #selector(rssiSliderValueChanged), for: .valueChanged)
        headerView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(nearLabel.snp.right).offset(SCRXFrom(-3))
            make.right.equalTo(farLabel.snp.left).offset(SCRXFrom(3))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(70)
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
        }
        
        footerView = DeviceAddBottomView()
        footerView.isHidden = true
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        footerView.selectAllBtn.addTarget(self, action: #selector(selectAllBtnClick), for: .touchUpInside)
        footerView.addSelectedBtn.addTarget(self, action: #selector(addSelectedBtnClick), for: .touchUpInside)
        
        addResultView = DeviceAddResultView()
        addResultView.isHidden = true
        view.addSubview(addResultView)
        addResultView.snp.makeConstraints { make in
            make.bottom.equalTo(footerView.snp.top).offset(SCRYFrom(-1))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
        }
        addResultView.closeBtn.addTarget(self, action: #selector(closeBtnClick), for: .touchUpInside)
        addResultView.stopAddBtn.addTarget(self, action: #selector(stopAddBtnClick), for: .touchUpInside)
    }

}

extension SiteDeviceAddViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
        cell.selectionStyle = .none
        let device = showDevices[indexPath.row]
        cell.device = device
        cell.delegate = self
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let device = showDevices[indexPath.row]
        guard device.selectedState == .unselected || device.selectedState == .selected else {
            return
        }
 
        if device.selectedState == .unselected {
            device.selectedState = .selected
        }else {
            device.selectedState = .unselected
        }
        if device.addState == .failed {
            device.addState = .none
            device.selectedState = .selected
            tableView.reloadRows(at: [indexPath], with: .none)
            updateUIState()
        }else {
            if let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
                switch device.selectedState {
                case .unselected:
                    cell.selectImageView.image = UIImage(named: "device_select_un")
                case .selected:
                    cell.selectImageView.image = UIImage(named: "device_select")
                case .disabled:
                    cell.selectImageView.image = UIImage(named: "device_select_disable")
                }
            }else {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        
        updateFooterViewState()
    }
    
}

extension SiteDeviceAddViewController: DeviceAddViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        if device.addState == .identifying {
            return
        }
        if state == .scanning {
            
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_identify".localizedString)
            return
        }
        identify(device)
    }
    
    /// 设备添加点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_add".localizedString)
            return
        }
        checkDeviceAddressesAreSufficient(devices: [device])
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
        guard device.addState == .wait || device.addState == .failed else {
            return
        }
        if device.addState == .wait { // 等待添加
            MeshAPI.cancelFastAddAwaitOperations(devices: [device])
        }
        
        // 设备状态回归为默认状态
        device.addState = .none
        device.selectedState = .selected
        reloadDeviceState(device)
        
        updateUIState()
    }
}

extension SiteDeviceAddViewController {
    
    /// 设备添加页面状态
    enum State {
        /// 无状态
        case none
        /// 扫描设备中
        case scanning
        /// identify中
        case identifying
        /// 添加设备中
        case adding
        /// 设备添加完成
        case addFineshed
    }
    
}
