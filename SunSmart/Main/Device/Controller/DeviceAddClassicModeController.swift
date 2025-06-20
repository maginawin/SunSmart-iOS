//
//  DeviceAddClassicModeController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/19.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth
import SwiftyJSON

class DeviceAddClassicModeController: UIViewController {

    /// header
    private var headerView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: CustomDeviceSlider!
    private var farLabel: UILabel!
    private var addDeviceToLabel: UILabel!
    private var addDeviceTargetBtn: UIButton!
    private var scanBtn: UIButton!
    /// 设备列表
    private var tableView: UITableView!
    /// 添加设备结果
    private var addResultView: DeviceAddResultView!
    /// 底部全选
    private var footerView: DeviceAddBottomView!
    /// 类型view
    private var categoryView: WMMenuView!
    
    /// 搜索设备定时器
    private var scanTimer: Timer?
    /// 找到的设备list
    private var scanDevices: [ProvisioningDevice] = []
    /// 展示的设备list（信号值筛选）
    private var showDevices: [ProvisioningDevice] = []
    /// 筛选的信号值
    private var filterRSSI: Int = 0
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -80 ... -40
    /// 添加设备页面状态
    private var state: State = .none
    /// identify中的设备
    private var identifyDevice: ProvisioningDevice?
    /// 所属空间
    let space: SpaceData
    /// 设备添加完成回调
    var deviceAddCallback: (([Node])->Void)?
    /// 添加成功的节点
    private var addSuccessNodes: [Node] = []
    /// 设备添加到的对应组
    private var addToGroup: Group?
    /// 外部传入指定添加该到group
    var appointGroup: Group?
    
    /// 设备绑定到dongle数据
    private var bindToDongle: DeviceDongleData?
    /// 外部传入指定dognle设备绑定该到dognle数据
    var forceBindToDongle: DeviceDongleData?
    /// 已存在的dognle数据list
    private var dongles: [DeviceDongleData] = []
    
    private var notAddedDevices: [ProvisioningDevice] = []
    /// 最大设备数量
    private var maxDeviceCount = 200
    /// 展示的设备类型
    private var showDeviceTypes: [Node.DeviceType] = [.light]
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
      
        filterRSSI = filterRSSIRange.lowerBound
        
        addToGroup = appointGroup
        bindToDongle = forceBindToDongle
        dongles = MeshNetworkManager.instance.dongles
        maxDeviceCount = space.maxDevicesCount
        
//        NetworkRequest.shared.addObserver(self, forKeyPath: "networkable", context: nil)
        
        setupUI()
        
        
        if forceBindToDongle != nil {
            showDeviceTypes = [.dongle, .unknown]
            categoryView.selectItem(at: 3)
        }
        
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
//        if state == .scanning {
//            stopScan()
//        }else {
            if state == .adding {
                MeshAPI.stopFastAddDevice(finishBack: nil)
            }
            if self.addSuccessNodes.count > 0 {
                // 找出未命名的设备
                let unnamedNodes = addSuccessNodes.filter({ !($0.name?.contains("ID") ?? true) })
                if unnamedNodes.count > 0 {
                    unnamedNodes.forEach({
                        $0.name = MeshNetworkManager.instance.getNextNodeName()
                        $0.save()
                    })
//                    _ = MeshNetworkManager.instance.save()
                }
                self.deviceAddCallback?(self.addSuccessNodes)
            }
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
//        }
    }
    
    /// KVO监听
//    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
//        if keyPath == "networkable" { // 手机网络连接状态
//            if NetworkRequest.shared.networkable, space.isLoadAddress { // 需要加载地址
//                SRAlertView.hide()
//                // 申请设备地址请求
//                applyDeviceAddressesRequest()
//            }
//        }
//    }
    
    // MARK: - Scan
    
    private func startScan() {
        
//        (wm_pageController as? DeviceAddViewController)?.startScan()
        
        state = .scanning
        
        startScanTimer()

        scanDevices.removeAll()
        showDevices.removeAll()
        tableView.reloadData()
        
        updateUIState()
        // 扫描中设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        
        categoryView.isHidden = true
        updateDeviceCategoryCount()
        MeshAPI.startScanDevice(.max, deviceScan: {[weak self] device in
            guard let self = self else { return }
            // 新发现设备
            if device.macAddress != nil && !self.scanDevices.contains(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
                
                self.stopScanTimer()
                
                self.scanDevices.append(device)
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
                
//                print(device.rssi)
                self.categoryView.isHidden = false
                
                // 当前设备信号值在筛选范围内可展示
                if self.filterRSSI == self.filterRSSIRange.lowerBound || device.rssi.intValue >= self.filterRSSI {
                    
                    self.updateDeviceCategoryCount()
                    
                    if self.showDeviceTypes.contains(device.deviceType) {
                            self.showDevices.append(device)
                            self.tableView.insertRows(at: [IndexPath(row: self.showDevices.count - 1, section: 0)], with: .automatic)
                    }
                }
                
                DispatchQueue.main.async {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
                    self.perform(#selector(self.stopScan), with: nil, afterDelay: 8)
                }
            }
            
        }, deviceScanFinish: nil)
    }
    
    @objc private func stopScan() {

        
//        (wm_pageController as? DeviceAddViewController)?.stopScan()
        
        scanBtn.isSelected = false
        MeshAPI.stopScan()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        // 停止扫描设备状态设置为空状态
        scanDevices.forEach({
            $0.addState = .none
            reloadDeviceState($0)
        })
        
        updateUIState()
        
        stopScanTimer()
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
        
        // space只能添加200个设备
        let existNodeCount = MeshNetworkManager.instance.realNodes.count + showDevices.filter({ $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }).count
//        guard !sender.isSelected, existNodeCount < 200 else {
//            let canSelectCount = 200 - existNodeCount
//
//
//            devices.forEach({ $0.selectedState = .selected })
//
//            SRAlertView(title: "notification".localizedString, message: "devices_number_exceeds_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
//            return
//        }
        
        sender.isSelected = !sender.isSelected
        
        let canAddDevices = showDevices.filter({ $0.selectedState != .disabled && !($0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting) })
        if sender.isSelected {
            if existNodeCount + canAddDevices.count > maxDeviceCount {
                SRAlertView(title: "notification".localizedString, message: "devices_number_exceeds_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
                canAddDevices.prefix(maxDeviceCount - existNodeCount).forEach({ $0.selectedState = .selected })
            }else {
                canAddDevices.forEach({ $0.selectedState = .selected })
            }
            
//            selectCountLabel.text = "\(devices.count)/\(devices.count)"
        }else {
            canAddDevices.forEach({ $0.selectedState = .unselected })
            
//            selectCountLabel.text = "0/\(devices.count)"
        }
        updateFooterViewState()
        tableView.reloadData()
    }
    
    /// 批量添加
    @objc private func addSelectedBtnClick() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        
        let dongleDevices = selectDevices.filter({ $0.deviceType == .dongle })
        // 多个dongle一起添加时提示
        if dongleDevices.count > 1 {
            SRAlertView(title: "notification".localizedString, message: "device_add_multiple_dongle_message".localizedString, actions: [.cancelAction, .init(title: "GOT IT".localizedString, actionHandler: {[weak self] _ in
                self?.checkDeviceAddressesAreSufficient(devices: selectDevices)
            })]).show()
        }else {
            checkDeviceAddressesAreSufficient(devices: selectDevices)
        }
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
        TestDeviceAddManager.manager.cancelAwaitOperations()
        
        MeshAPI.cancelFastAddAwaitOperations()
        let waitDevices = showDevices.filter({ $0.addState == .wait })
        waitDevices.forEach({
            $0.addState = .none
            $0.selectedState = .selected
        })
        tableView.reloadData()
        updateUIState()
    }
    
    /// 添加目标选择事件
    @objc private func addDeviceTargetBtnClick(sender: UIButton) {
        
        if state == .adding {
            return
        }
        
        var titles: [String] = [space.name]
        var selectIndex = 0
        
        let touchPoint = CGPoint(x: sender.x, y: sender.frame.maxY + SCRYFrom(2))
        let menuPoint = view.convert(touchPoint, to: UIApplication.shared.keyWindow())
        
        if showDeviceTypes.contains(.dongle) { // 选择dongle
            if forceBindToDongle != nil { // 固定智能绑定该dongle数据
                XWHUDManager.showTipHUD("dongle_cannot_select_message".localizedString, isLineFeed: true)
                return
            }
            
            for dongle in dongles {
                titles.append(dongle.name)
            }

            if let selectDongle = bindToDongle, let index = dongles.firstIndex(where: { $0.id == selectDongle.id }) {
                selectIndex = index + 1
            }
            
            TitleSelectView.show(titles: titles, anchorPoint: menuPoint, selectIndex: selectIndex) {[weak self] index in
                guard let self = self else { return }
                if index == 0 {
                    self.bindToDongle = nil
                }else {
                    self.bindToDongle = self.dongles[index - 1]
                }
                sender.setTitle(titles[index], for: .normal)
            }
            
        }else { // 选择组
            if appointGroup != nil {
                XWHUDManager.showTipHUD("group_cannot_select_message".localizedString, isLineFeed: true)
                return
            }
            
            let groups = MeshNetworkManager.instance.groups
            for group in groups {
                titles.append(group.name)
            }
            var selectIndex = 0
            if let selectGroup = addToGroup, let index = groups.firstIndex(where: { $0.address == selectGroup.address }) {
                selectIndex = index + 1
            }
            
            TitleSelectView.show(titles: titles, anchorPoint: menuPoint, selectIndex: selectIndex) {[weak self] index in
                guard let self = self else { return }
                if index == 0 {
                    self.addToGroup = nil
                }else {
                    self.addToGroup = groups[index - 1]
                }
                sender.setTitle(titles[index], for: .normal)
            }
        }
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
        MeshAPI.unprovisionedDeviceIdentify(device: device) {[weak self] _, _ in
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
            self.identifyDevice = nil
            self.reloadDeviceState(device)
            if self.state == .identifying {
                self.updateUIState()
            }
        }
    }
    
    /// 添加设备
    private func addDevice(_ device: ProvisioningDevice) {
        
        // 设备identify中添加不需要再闪烁
        if device.addState == .identifyConnecting || device.addState == .identifyWait || device.addState == .failed || device.addState == .identifying {
//            if device.addState == .identifying {
//                device.identifyAttentionTimer = 0
//            }
            if device == identifyDevice {
                MeshAPI.stopUnprovisionedDeviceIdentify()
            }
        }
        // 添加设备不需要闪烁
        device.identifyAttentionTimer = 0
        device.addState = .wait
        device.selectedState = .disabled
        reloadDeviceState(device)
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
            // 配网完成
            if addDevice.deviceType == .dongle { // dongle设备，需要一个dongle虚拟数据与之绑定
                if let selectDongle = self.bindToDongle { // 已选择dognle
                    if selectDongle.bindNode != nil { // 已绑定设备则创建新的dongle并绑定设备
                        let newDongle = DeviceDongleData(id: UUID().uuidString, name: MeshNetworkManager.instance.getNextDongleName(), bindNodeAddress: node.primaryUnicastAddress, timeAuthority: selectDongle.timeAuthority, collectionEnable: selectDongle.collectionEnable, schedules: selectDongle.schedules)
                        MeshNetworkManager.instance.dongles.append(newDongle)
                        newDongle.save()
                    }else { // 未绑定设备则设备绑定到dongle
                        selectDongle.bindNodeAddress = node.primaryUnicastAddress
                        selectDongle.save()
                    }
                }else { // 添加到space
                    // 创建一个空的dongle数据做为dongle设备的绑定
                    let newDongle = DeviceDongleData.default()
                    MeshNetworkManager.instance.dongles.append(newDongle)
                    newDongle.save()
                }
            }
            
        } appendMessagesBack: {[weak self] addDevice in
            guard let self = self, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) else { return [] }
            var appendMessages: [MeshMessageHandle] = []
            // 入网后默认调为最大亮度
            if let model = node.lightnessModel {
                appendMessages.append(MeshMessageHandle(message: LightLightnessSetUnacknowledged(lightness: .max), model: model))
            }
            if device.deviceType != .dongle, let group = self.addToGroup {
                // 判断组是否有关联动能开关，如果动能开关还未分配地址则提前分配地址以订阅设备
                let emptySwitchs = group.info.switchs.filter({ $0.linkGroup == nil })
                emptySwitchs.forEach { switchData in
                    
                    // 判断组地址是否足够分配
                    if MeshAPI.getAvailableGroupAddresses(meshUUID: self.space.meshUUID, subnetworkId: self.space.meshNetworkId).count >= switchData.panelType.usedAddressesNumber, switchData.linkGroupAddress == nil {
                        
                        let linkGroup = try? MeshAPI.createGroup(name: switchData.name + "-Group", isVirtual: true)
                        let subLinkGroup = try? MeshAPI.createGroup(name: switchData.name + "-Group_1", isVirtual: true)
                        
                        switchData.linkGroupAddress = linkGroup?.address.address
                        switchData.subLinkGroupAddress = subLinkGroup?.address.address
                        switchData.save()
//                        print("创建动能开关组")
                    }
                }
                appendMessages.append(contentsOf: group.getNodeAddMessageHandles(node: node))
            }else {
                if device.deviceType != .dongle && device.deviceType != .gateway {
                    if let vendorModel = node.sunricherVendorModel { // 未加入组的设备默认设置一个手动控制延迟时间，避免默认30s后状态被LC修改
                        appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max)), model: vendorModel))
                    }
                    if let powerOnOffSetupModel = node.powerOnOffSetupModel { // 设置默认上电状态为上一次亮度
                        appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .restore), model: powerOnOffSetupModel))
                        //                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .default), model: powerOnOffSetupModel))
                        //                    appendMessages.append(MeshMessageHandle(message: LightLightnessDefaultSet(lightness: .max), model: lightnessSetupModel))
                    }
                }
            }
            // 需要追加发送的消息
            if let ctlModel = node.ctlModel, node.temperatureModel != nil {
                appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
            }
            // 设置默认过渡时间
//            if let defaultTransitionTimeModel = node.defaultTransitionTimeModel {
//                appendMessages.append(MeshMessageHandle(message: GenericDefaultTransitionTimeSet(transitionTime: .default), model: defaultTransitionTimeModel))
//            }
            // 节点数据hash
            if let vendorModel = node.sunricherVendorModel {
                appendMessages.append(MeshMessageHandle(message: SunricherVendorGet(function: .compositionHash), model: vendorModel))
            }
            // 添加成功后闪烁
            if let healthModel = node.healthModel {
                appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
            }
            
            if device.deviceType == .gateway, let vendorModel = node.sunricherVendorModel {
                appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewaySimInfoSet(cid: 1, ipType: .ip, apn: "3gnet")), model: vendorModel))
                
                appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(platformType: 0, serverAddress: "tcp://mqtt.sunsmart-cn.mericher.com:1883", userName: "Signature|Gateway|C2FB3109B9E0", password: "5dc9bc1d274548739b6a17cbd2298274", clientId: "sunsmart@@@C2FB3109B9E0", keepalive: 60, clearSession: true, authMode: .none, sslVersion: .all)), model: vendorModel))
//                appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewayMQTTConnectInfoSet(platformType: 0, serverAddress: "tcp://mqtt.sunsmart-cn.mericher.com:1883", userName: "Signature|Gateway|DDCDBC6F7308", password: "97636b9c647140b48363378b6c730f0c", clientId: "sunsmart@@@DDCDBC6F7308", keepalive: 60, clearSession: true, authMode: .none, sslVersion: .all)), model: vendorModel))
                
                if let mac = device.macAddress {
                    appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewayProjectRelevance(gatewayId: mac, projectId: space.siteId)), model: vendorModel))
                }
                
                appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .gatewaySubnetsRelevanceSet(subnetAppkeyIndexs: node.applicationKeys.map({ $0.index }))), model: vendorModel))
            }
        
//            appendMessages.insert(MeshMessageHandle(message: ConfigRelaySet(), address: node.primaryUnicastAddress), at: 0)
            
            // 获取对应传感器model，识别传感器类型
//            node.sensorModels.forEach { sensorModel in
//                appendMessages.append(MeshMessageHandle(message: SensorGet(), model: sensorModel))
//            }
            return appendMessages
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
                node.rssi = addDevice.rssi.intValue
                if let macAddress = addDevice.macAddress {
                    node.macAddress = macAddress
                }else {
                    // 没有MAC，自动生成一个随机数
                    let mac = MeshNetworkManager.instance.getRandomMacAddress()
                    node.macAddress = mac
                }
                node.name = MeshNetworkManager.instance.getNextNodeName()
                // 需添加到组里
                if let group = self.addToGroup {
                    if node.group == nil { // 未添加组成功，需要记录组数据下次同步恢复到组里
                        node.restoreData = NodeRestoreData(addGroupAddress: group.address.address)
                    }
                }
//                node.state = true
                node.save()
//                node.saveNodeInfo(meshUUID: self.space.meshUUID, networkKey: self.space.meshNetworkKey)
//                self?.space.getNextNodeName(resultCallback: { name in
//                    node.name = name
//                    print("address:\(node.primaryUnicastAddress), name:\(name)")
//                })
//                if let name = self?.space.getNextNodeName() {
//                    node.name = name
//                }
                self.addSuccessNodes.append(node)
            }
        } addFail: {[weak self] addDevice, error in
            addDevice.addState = .failed
            addDevice.selectedState = .selected
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
            // 设备地址已分配完
            if let provisioningError = error as? ProvisioningError, case .noAddressAvailable = provisioningError {
//                applyDeviceAddressesRequest(applyAddressCount: applyAddressCount, devices: [])
            }
            
        } addFinish: {[weak self] successList, failList in
            guard let self = self else { return }
//            let successNodes = MeshNetworkManager.instance.realNodes.filter { node in
//                successList.contains(where: { $0.address == node.primaryUnicastAddress })
//            }
//            successNodes.forEach { node in
//                node.name = MeshNetworkManager.instance.getNextNodeName()
//                node.save()
//            }
//            if MeshLibManager.manager.currentProxy?.node == nil, let node = successNodes.last {
//                MeshLibManager.manager.currentProxy?.nodeAddress = node.primaryUnicastAddress
//            }
            self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
            self.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count //MeshNetworkManager.instance.lightNodes.count
            self.space.save()
            // 通知space数据修改
//            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
            
//            self.addSuccessNodes.append(contentsOf: successNodes)
        }
        
    }
    
    /// 检查设备地址是否足够
    private func checkDeviceAddressesAreSufficient(devices: [ProvisioningDevice]) {
        
        // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
        let estimatedAddressCount = devices.reduce(0, { (result, device) in result + device.elementCount })
        // 获取网络内已存在的设备地址数量
        let existingAddressCount = Node.loadAddresses(meshUUID: self.space.meshUUID).count
        // 申请的地址数量
        let applyAddressCount = estimatedAddressCount - MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.space.meshUUID) + Int(Float(existingAddressCount) * 0.2)
        
        // 检查剩余地址是否足够添加设备
        guard MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.space.meshUUID) >= estimatedAddressCount else {
            // 地址不够
            // 手机是否联网
            guard NetworkRequest.shared.networkable else {
                // 未联网提示联网以获取地址
                self.space.applyDeviceAddressCount = applyAddressCount
                self.space.save()
                
                SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    if NetworkRequest.shared.networkable {
                        self?.space.applyDeviceAddressCount = nil
                        self?.space.save()
                        self?.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
                    }
                })]).show()
                return
            }
            // 向服务器申请地址
            applyDeviceAddressesRequest(applyAddressCount: applyAddressCount, devices: devices)
            return
        }
        devices.forEach({
            addDevice($0)
        })
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
        NetworkRequest.shared.request(.applyAddress(siteId: self.space.siteId, type: .device, number: applyAddressCount)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let repsonsed):
                // 新增地址
                if let site = SiteData.load(siteId: self.space.siteId), let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                    site.setProvisioner(provisionerData: provisionerData)
                    // 继续添加设备
                    devices.forEach({
                        self.addDevice($0)
                    })
                }else {
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
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
        }else {
            tableView.reloadData()
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
        
        if rssiSlider.isEnabled {
            rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
            rssiSlider.minimumTrackTintColor = Slider_Color
        }else {
            rssiSlider.setThumbImage(UIImage(named: "slider_point_disable"), for: .normal)
            rssiSlider.minimumTrackTintColor = Slider_Color.withAlphaComponent(0.5)
        }
        
        UIApplication.shared.isIdleTimerDisabled = false
        
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
    
    /// 更新设备类型数量
    private func updateDeviceCategoryCount() {
//        guard !categoryView.isHidden else {
//            return
//        }
        var showCategoryDevices: [ProvisioningDevice] = []
        
        let filterRSSI = Int(-rssiSlider.value)
        // 筛选展示的设备
        if filterRSSI == filterRSSIRange.lowerBound {
            showCategoryDevices = scanDevices
        }else {
            showCategoryDevices = scanDevices.filter({ $0.rssi.intValue >= filterRSSI })
        }
        
        categoryView.updateTitle("\("lights".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .light }).count)", at: 0, andWidth: false)
        categoryView.updateTitle("\("switches".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .switches }).count)", at: 1, andWidth: false)
        categoryView.updateTitle("\("sensors".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .sensor }).count)", at: 2, andWidth: false)
        categoryView.updateTitle("\("others".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .dongle || $0.deviceType == .gateway || $0.deviceType == .unknown }).count)", at: 3, andWidth: false)
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
            make.height.equalTo(SCRYFrom(100))
        }
        
        nearLabel = UILabel(text: "near".localizedString, textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        nearLabel.sizeToFit()
        headerView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24))
            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "far".localizedString, textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        farLabel.sizeToFit()
        headerView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(nearLabel)
            make.width.equalTo(farLabel.width)
        }
        
        rssiSlider = CustomDeviceSlider()
        rssiSlider.minimumTrackTintColor = Slider_Color
        rssiSlider.maximumTrackTintColor = RGB(229, 229, 229)
        rssiSlider.layer.cornerRadius = 2.5
        rssiSlider.minimumValue = Float(abs(filterRSSIRange.upperBound))
        rssiSlider.maximumValue = Float(abs(filterRSSIRange.lowerBound))
        rssiSlider.value = Float(abs(filterRSSI))
//        rssiSlider.maximumValue - Float(filterRSSI - filterRSSIRange.lowerBound) / Float(filterRSSIRange.upperBound - filterRSSIRange.lowerBound) * 100
        rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
//        rssiSlider.setThumbImage(UIImage(named: "slider_point")?.withTintColor(RGB(220, 220, 220)), for: .normal)
//        rssiSlider.minimumTrackTintColor = RGB(229, 229, 229)
        rssiSlider.delegate = self
        headerView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(nearLabel.snp.right).offset(SCRXFrom(15))
            make.right.equalTo(farLabel.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        addDeviceToLabel = UILabel(text: "add_device_to".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addDeviceToLabel.sizeToFit()
        headerView.addSubview(addDeviceToLabel)
        addDeviceToLabel.snp.makeConstraints { make in
            make.left.equalTo(nearLabel)
            make.bottom.equalTo(SCRYFrom(-14))
            make.width.equalTo(addDeviceToLabel.width)
        }
        
        scanBtn = UIButton(title: "scan".localizedString, titleSize: 13, titleColor: Bottom_Done_Color, normalImageName: "device_scan", target: self, action: #selector(scanBtnClick))
        scanBtn.setTitle("stop".localizedString, for: .selected)
        scanBtn.setTitleColor(Purple_Color.withAlphaComponent(0.5), for: .disabled)
        scanBtn.layer.cornerRadius = SCRYFrom(5)
        scanBtn.layer.borderWidth = 1
        scanBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        scanBtn.backgroundColor = .white
        scanBtn.contentHorizontalAlignment = .left
        scanBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
        scanBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: 0)
        
        headerView.addSubview(scanBtn)
        scanBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.centerY.equalTo(addDeviceToLabel)
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
        
        var targetName = space.name
        if showDeviceTypes.contains(.dongle) {
            if let dongleName = bindToDongle?.name {
                targetName = dongleName
            }
        }else {
            if let groupName = addToGroup?.name {
                targetName = groupName
            }
        }
        addDeviceTargetBtn = UIButton(title: targetName, titleSize: 13, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "space_arrow_down", target: self, action: #selector(addDeviceTargetBtnClick))
        addDeviceTargetBtn.contentHorizontalAlignment = .left
        addDeviceTargetBtn.layer.cornerRadius = SCRYFrom(5)
        addDeviceTargetBtn.layer.borderWidth = 1
        addDeviceTargetBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        addDeviceTargetBtn.backgroundColor = .white
        headerView.addSubview(addDeviceTargetBtn)
        addDeviceTargetBtn.snp.makeConstraints { make in
            make.left.equalTo(addDeviceToLabel.snp.right).offset(SCRXFrom(5))
            make.centerY.equalTo(addDeviceToLabel)
            if isIPad {
                make.width.equalTo(SCRXFrom(128))
            }else {
                make.right.equalTo(scanBtn.snp.left).offset(SCRXFrom(-27))
            }
            make.height.equalTo(SCRYFrom(32))
        }
        addDeviceTargetBtn.layoutIfNeeded()
        addDeviceTargetBtn.imageView?.sizeToFit()
        let imageW = addDeviceTargetBtn.imageView?.image?.size.width ?? 0
        addDeviceTargetBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: addDeviceTargetBtn.width - imageW, bottom: 0, right: 0)
        addDeviceTargetBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8) - imageW, bottom: 0, right: imageW + SCRXFrom(6))
        
        
        categoryView = WMMenuView(frame: CGRect(x: 0, y: view.safeAreaInsets.top + SCRYFrom(100) + SCRYFrom(8), width: view.width, height: CGFloat(Int(SCRYFrom(40)))))
        categoryView.itemBackgroundColor = .clear
        categoryView.itemCornerRadius = CGFloat(Int(SCRYFrom(20)))
        if isIPad {
            categoryView.layoutMode = .center
        }
        categoryView.itemRateAnimation = false
        categoryView.fontWeight = .light
        categoryView.isHidden = true
        categoryView.dataSource = self
        categoryView.delegate = self
        categoryView.selectItem(at: 0)
        view.addSubview(categoryView)
        categoryView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
            make.height.equalTo(SCRYFrom(40))
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(60)
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(categoryView.snp.bottom).offset(SCRYFrom(8))
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

extension DeviceAddClassicModeController: WMMenuViewDataSource, WMMenuViewDelegate {
    
    func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return 4
    }
    
    func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        
        var showCategoryDevices: [ProvisioningDevice] = []
        let filterRSSI = Int(-rssiSlider.value)
        // 筛选展示的设备
        if filterRSSI == filterRSSIRange.lowerBound {
            showCategoryDevices = scanDevices
        }else {
            showCategoryDevices = scanDevices.filter({ $0.rssi.intValue >= filterRSSI })
        }
        
        switch index {
        case 0:
            return "\("lights".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .light }).count)"
        case 1:
            return "\("switches".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .switches }).count)"
        case 2:
            return "\("sensors".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .sensor }).count)"
        case 3:
            return "\("others".localizedString)-\(showCategoryDevices.filter({ $0.deviceType == .dongle || $0.deviceType == .unknown }).count)"
        default:
            return ""
        }
    }
    
    func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return 14
    }
    
    func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? .white : Bar_Color
    }
    
    func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        return isIPad ? SCRXFrom(120) : SCRXFrom(80)
    }
    
    func menuView(_ menu: WMMenuView!, itemMarginAt index: Int) -> CGFloat {
//        if isIPad {
//
//            return super.menuView(menu, itemMarginAt: index)
//        }
        if index == 0 || index == 4 {
            return SCRXFrom(12)
        }
        return SCRXFrom(10)
    }
    
    func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        if forceBindToDongle != nil && index != 3 {
            XWHUDManager.showTipHUD("dongle_cannot_select_message".localizedString, isLineFeed: true)
            return false
        }
        return true
    }
    
    func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
        
        let item = menu.item(at: index)
        item?.backgroundColor = Bar_Color
        item?.font = UIFont.systemFont(ofSize: 14)
        
        guard index != currentIndex else {
            return
        }
        
        let lastItem = menu.item(at: currentIndex)
        lastItem?.backgroundColor = .white
        
        
        
        switch index {
        case 0:
            showDeviceTypes = [.light]
        case 1:
            showDeviceTypes = [.switches]
        case 2:
            showDeviceTypes = [.sensor]
        case 3:
            showDeviceTypes = [.dongle, .gateway, .unknown]
        default:
            showDeviceTypes = [.light]
        }
        
        let filterRSSI = Int(-rssiSlider.value)
        var showDevices: [ProvisioningDevice] = []
        // 筛选展示的设备
        if filterRSSI == filterRSSIRange.lowerBound {
            showDevices = scanDevices
        }else {
            showDevices = scanDevices.filter({ $0.rssi.intValue >= filterRSSI })
        }
        self.showDevices = showDevices.filter({ showDeviceTypes.contains($0.deviceType) })
        tableView.reloadData()
        updateFooterViewState()
        
        // 更新设备添加到哪UI
        var name = space.name
        if showDeviceTypes.contains(.dongle) {
            if let dongleName = bindToDongle?.name {
                name = dongleName
            }
        }else {
            if let groupName = addToGroup?.name {
                name = groupName
            }
        }
        addDeviceTargetBtn.setTitle(name, for: .normal)
    }
    
    func menuView(_ menu: WMMenuView!, initialMenuItem: WMMenuItem!, at index: Int) -> WMMenuItem! {
        if index == 0 {
            initialMenuItem.backgroundColor = Bar_Color
        }else {
            initialMenuItem.backgroundColor = .white
//                .white.withAlphaComponent(0.95)
        }
        return initialMenuItem
    }
    
}

extension DeviceAddClassicModeController: UITableViewDataSource, UITableViewDelegate {
    
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
        // space只能添加200个设备
        guard MeshNetworkManager.instance.realNodes.count + showDevices.filter({ $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }).count < maxDeviceCount else {
            SRAlertView(title: "notification".localizedString, message: "devices_number_exceeds_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
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
//            let successCount = scanDevices.filter({ $0.addState == .success }).count
//            let failedCount = scanDevices.filter({ $0.addState == .failed }).count
//            successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
//            failedCountLabel.text = "\(failedCount)"
            
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

extension DeviceAddClassicModeController: CustomDeviceSliderDelegate {
    
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        
        let rssi = Int(-value)
//        filterRSSIRange.lowerBound + abs(Int(((value - 100) / 100.0) * Float(filterRSSIRange.upperBound - filterRSSIRange.lowerBound)))
        if filterRSSI != rssi {
            filterRSSI = rssi
//            print(rssi)
//            var showCategoryDevices: [ProvisioningDevice] = []
            // 筛选展示的设备
            if rssi == filterRSSIRange.lowerBound {
//                showCategoryDevices = scanDevices
                showDevices = scanDevices.filter({ showDeviceTypes.contains($0.deviceType) })
            }else {
//                showCategoryDevices = scanDevices.filter({ $0.rssi.intValue >= rssi })
                showDevices = scanDevices.filter({ showDeviceTypes.contains($0.deviceType) && $0.rssi.intValue >= rssi })
            }
            updateFooterViewState()
            tableView.reloadData()
            updateDeviceCategoryCount()
        }
    }
}

extension DeviceAddClassicModeController: DeviceAddViewCellDelegate {
    
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
        // space只能添加200个设备
        guard MeshNetworkManager.instance.realNodes.count + showDevices.filter({ $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }).count < maxDeviceCount else {
            SRAlertView(title: "notification".localizedString, message: String(format: "devices_number_exceeds_message".localizedString, maxDeviceCount), actions: [SRAlertAction(title: "ok".localizedString)]).show()
            return
        }
        checkDeviceAddressesAreSufficient(devices: [device])
//        addDevice(device)
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

extension DeviceAddClassicModeController {
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
