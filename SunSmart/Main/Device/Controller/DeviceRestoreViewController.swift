//
//  DeviceRestoreViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/22.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

class DeviceRestoreViewController: UIViewController {

    private var navigationBackBtn: UIButton!
    /// header
    private var scanAnimationView: UIImageView!
    private var headerView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: RangeSlider!
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
    
        
    
    /// 搜索设备定时器
    private var scanTimer: Timer?
    /// 恢复数据sections
    private var sections: [DeviceRestoreSection] = []
    /// 找到的设备list
//    private var scanDevices: [Node] = []
    /// 展示的设备list（信号值筛选）
    private var showSections: [DeviceRestoreSection] = []
    /// 选择筛选的信号值
    private var selectRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 添加设备页面状态
    private var state: State = .none
    /// identify中的设备
    private var identifyDevice: ProvisioningDevice?
    /// 设备恢复完成回调
    var deviceRestoreCallback: (([Node], Bool)->Void)?
    /// 已恢复的设备
    private var restoreNodes: [Node] = []
    
    
    /// 展示的设备恢复数据list
    private var showRestoreData: [DeviceRestoreData] {
        var restoreDatas: [DeviceRestoreData] = []
        showSections.forEach { section in
            restoreDatas.append(contentsOf: section.restoreDatas)
        }
        return restoreDatas
    }
    
    /// 所有的设备list
    private var allDevices: [ProvisioningDevice] {
        var devices: [ProvisioningDevice] = []
        sections.forEach { section in
            devices.append(contentsOf: section.restoreDatas.compactMap({ $0.unprovisionedDevice }))
        }
        return devices
    }
    /// 展示的设备list
    private var showDevices: [ProvisioningDevice] {
        var devices: [ProvisioningDevice] = []
        showSections.forEach { section in
            devices.append(contentsOf: section.restoreDatas.compactMap({ $0.unprovisionedDevice }))
        }
        return devices
    }
    
    private var rssiSortTimer: Timer?
    
    let space: SpaceData
    
    /// 恢复数据模式
    let restoreMode: RestoreMode
    /// 自动化恢复（设置以后自动扫描恢复设备）
    var automationRestore: Bool = false
    /// 自动重试次数
    var automationRetryCount: Int = 1
    
    
    init(space: SpaceData, restoreMode: RestoreMode) {
        self.space = space
        self.restoreMode = restoreMode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Restore_Device_Data".localizedString
        
        view.backgroundColor = Background_Color
        self.isModalInPresentation = true
        
        
        navigationBackBtn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backClick))
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: navigationBackBtn)
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: scanAnimationView)
        
        setupUI()
        scanBtn.isSelected = true
        startScan()
        
        if automationRestore {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: {[weak self] in
                guard let self = self else { return }
                self.navigationController?.showAutomaticHud(messsage: "device_automatic_restore_message".localizedString) {[weak self] in
                    guard let self = self else { return }
                    self.navigationController?.hideAutomaticHud()
                    self.automationRestore = false
                    DispatchQueue.main.async {
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automationRestoreScanTimeout), object: nil)
                    }
                }
            })
        }
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if state == .scanning { // 退出页面/切换停止扫描
            stopScan()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    
    deinit {
//        if state == .scanning {
//            stopScan()
//        }else {
            if state == .adding {
                MeshAPI.stopFastAddDevice(finishBack: nil)
            }
//            if self.restoreNodes.count > 0 {
        self.deviceRestoreCallback?(self.restoreNodes, self.automationRestore)
//            }
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
//        }
    }
    
    @objc private func backClick() {
        if allDevices.contains(where: { $0.addState == .syncFailed }) {
            SRAlertView(title: "notification".localizedString, message: "devices_unrestored_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                self?.dismiss()
            })]).show()
        }else {
//            navigationController?.popViewController(animated: true)
            dismiss()
        }
    }
    
    private func dismiss() {
        if automationRestore {
            navigationController?.hideAutomaticHud()
        }
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        }else {
            dismiss(animated: true)
        }
    }
    
    
//    override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//        
//        MeshAPI.stopScanRecoverDevices()
//    }
    
    private func setupDataSource() {
        
        switch self.restoreMode {
        case .default:
            sections.removeAll()
            showSections.removeAll()
        case .specified(let nodes):
            sections.removeAll()
            /// 需要继续恢复的设备，如已恢复的设备将不展示
            let nextRestoreNodes = nodes.filter({ node in !restoreNodes.contains(where: { $0.macAddress == node.macAddress || $0.macAddress?.toOldMacAddress() == node.macAddress }) })
            nextRestoreNodes.forEach { node in
                let data = DeviceRestoreData(node: node)
                if let section = sections.first(where: { $0.group == node.group }) {
                    section.restoreDatas.append(data)
                }else {
                    let section = DeviceRestoreSection(group: node.group, restoreDatas: [data])
                    if node.group == nil {
                        sections.insert(section, at: 0)
                    }else {
                        sections.append(section)
                    }
                }
            }
            showSections = sections
        }
    }

    // MARK: - Scan
    private func startScan() {
        
        state = .scanning
        
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanAnimationView.isHidden = false
        scanAnimationView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "scan")
        startScanTimer()

//        scanDevices.removeAll()
//        showSections.removeAll()
        setupDataSource()
        tableView.reloadData()
        
        updateUIState()
        // 扫描中设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        if automationRestore { // 自动化恢复，开启30秒定时器
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automationRestoreScanTimeout), object: nil)
                self.perform(#selector(self.automationRestoreScanTimeout), with: nil, afterDelay: 30)
            }
        }
        
        MeshAPI.startScanRecoverDevices(duration: .max, scanDevice: {[weak self] unprovisionedDevice, node in
            guard let self = self, unprovisionedDevice.rssi.intValue >= self.filterRSSIRange.lowerBound else { return }
            
            if self.automationRestore {
                DispatchQueue.main.async {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automationRestoreScanTimeout), object: nil)
                }
            }
            
            if unprovisionedDevice.rssi.intValue > self.filterRSSIRange.upperBound {
                unprovisionedDevice.rssi = NSNumber(value: self.filterRSSIRange.upperBound)
            }
            
            self.stopScanTimer()
            // 只有指定设备才显示
            if case .specified(let nodes) = self.restoreMode {
                if !nodes.contains(where: {$0.primaryUnicastAddress == node.primaryUnicastAddress}) {
                    return
                }
            }
            
            unprovisionedDevice.selectedState = .selected
            unprovisionedDevice.addState = .scaning
            unprovisionedDevice.deviceName = node.name
            unprovisionedDevice.elementCount = Int(node.elementsCount)
            unprovisionedDevice.icon = node.iconName
            unprovisionedDevice.deviceType = node.deviceType
            
            var setSection: DeviceRestoreSection!
            // 是否刷新设备数据（找到同一个设备beacon包）
//            var refreshDevice: Bool = false
            
            if let sectionIndex = self.sections.firstIndex(where: { $0.group == node.group }) {
                let section = self.sections[sectionIndex]
                if let data = section.restoreDatas.first(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    data.unprovisionedDevice = unprovisionedDevice
//                    refreshDevice = true
                }else {
                    section.restoreDatas.append(DeviceRestoreData(node: node, unprovisionedDevice: unprovisionedDevice))
                }
                setSection = section
            }else {
                let data = DeviceRestoreData(node: node, unprovisionedDevice: unprovisionedDevice)
                let section = DeviceRestoreSection(group: node.group, restoreDatas: [data])
                if node.group == nil {
                    self.sections.insert(section, at: 0)
                }else {
                    self.sections.append(section)
                }
                setSection = section
            }
    
            
            // 当前设备信号值在筛选范围内可展示
            if self.selectRSSIRange.contains(unprovisionedDevice.rssi.intValue) {
                if !self.showSections.contains(where: { $0.group == setSection.group }) {
                    if setSection.group == nil {
                        self.showSections.insert(setSection, at: 0)
//                        self.tableView.insertSections(IndexSet(integer: 0), with: .none)
                    }else {
                        self.showSections.append(setSection)
//                        self.tableView.insertSections(IndexSet(integer: self.showSections.count - 1), with: .none)
                    }
                                                          
                }
            }
            devicesRssiSort()
            
            switch self.restoreMode {
            case .default:
                self.footerView.selectCountLabel.text = "\(self.showDevices.count)"
            case .specified(let nodes):
                
                self.footerView.selectCountLabel.text = "\(self.showDevices.count)/\(nodes.count - self.restoreNodes.count)"
                // 已找到全部设备
                if self.allDevices.count >= nodes.count {
                    stopScan()
                    if self.automationRestore { // 自动恢复设备流程
                        addSelectedBtnClick()
                    }
                    DispatchQueue.main.async {
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
                self.perform(#selector(self.scanTimeout), with: nil, afterDelay: self.automationRestore ? 20 : 10)
            }

        }, scanFinish: nil)
                    
    }
    
    /// 扫描超时（未找到新设备）
    @objc private func scanTimeout() {
        stopScan()
        if self.automationRestore { // 自动恢复设备流程
            addSelectedBtnClick()
        }
    }
    
    @objc private func stopScan() {
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
        }
        
        scanAnimationView.isHidden = true
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanBtn.isSelected = false
        MeshAPI.stopScan()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        // 停止扫描设备状态设置为空状态
        self.sections.forEach { section in
            section.restoreDatas.forEach({
                $0.unprovisionedDevice?.addState = .none
            })
        }
        self.tableView.reloadData()
        
        updateUIState()
        
        stopScanTimer()
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 0.5, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        guard sections.count > 0 else {
            return
        }
        // 筛选展示的设备
        var currentShowSections: [DeviceRestoreSection] = []
        sections.forEach { section in
            let devices = section.restoreDatas.filter({ $0.unprovisionedDevice == nil || selectRSSIRange.contains($0.unprovisionedDevice!.rssi.intValue) })
            if devices.count > 0 {
                currentShowSections.append(DeviceRestoreSection(group: section.group, restoreDatas: devices))
            }
        }
        showSections = currentShowSections
        tableView.reloadData()
        
    }
    
    /// 自动恢复扫描设备超时
    @objc private func automationRestoreScanTimeout() {
        stopScan()
        // 回调超时状态到外部
        if automationRestore {
            dismiss()
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
    
    // MARK: - Device Restore
    /// 添加设备
    private func addDevice(_ deviceData: DeviceRestoreData) {
        
        guard let unprovisionedDevice = deviceData.unprovisionedDevice else {
            return
        }
        
        // 设备identify中添加不需要再闪烁
//        if unprovisionedDevice.addState == .identifyConnecting || unprovisionedDevice.addState == .identifyWait || unprovisionedDevice.addState == .failed || unprovisionedDevice.addState == .identifying {
            //            if device.addState == .identifying {
            //                device.identifyAttentionTimer = 0
            //            }
        if deviceData.unprovisionedDevice?.peripheral.identifier.uuidString == identifyDevice?.peripheral.identifier.uuidString {
                //                if let bearer = identifyBearer { // 将identify连接的设备数据传入添加设备操作，避免二次连接
                //                    device.gattBearer = PBGattBearer(bearer: bearer)
                //                    stopDeviceIdentify(close: false)
                //                }else {
            MeshAPI.stopUnprovisionedDeviceIdentify()
                //                }
            }
//        }
        // 添加设备不需要闪烁
        unprovisionedDevice.identifyAttentionTimer = 0
        if unprovisionedDevice.addState == .none {
            unprovisionedDevice.addState = .wait
            unprovisionedDevice.selectedState = .disabled
            reloadDeviceState(unprovisionedDevice)
        }
        updateUIState()
        
        MeshAPI.startFastAddDevices(devices: [unprovisionedDevice]) { [weak self] addDevice in
            addDevice.addState = .addConnecting
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } connectingBack: {[weak self] addDevice in
            addDevice.addState = .adding
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } provisionCompleteCallback: {[weak self] addDevice, node in
            guard let self = self else { return }
            
            var oldNode = deviceData.node
            var addToGroup = oldNode.group
            if oldNode.groupState == .exitFailure {
                addToGroup = nil
            }
            
            if let section = self.showSections.first(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == addDevice }) }), let data = section.restoreDatas.first(where: { $0.unprovisionedDevice == addDevice }) {
                oldNode = data.node
                if oldNode.groupState == .exitFailure {
                    addToGroup = nil
                }else {
                    addToGroup = section.group
                }
            }
            if addDevice.deviceType == .gateway, let mac = node.macAddress, NetworkRequest.shared.networkable {
                Task {
                    // 网关绑定到space
                    let bindSpaceResult = await NetworkRequest.shared.request(.gatewayBindSpace(spaceId: self.space.id, gatewayId: mac))
                    switch bindSpaceResult {
                    case .success:
                        node.gatewayModel?.associatedSpaces.append(self.space)
                        node.gatewayModel?.save()
                    case .failure:
                        break
                    }
                }
            }
            
            // 恢复数据
            node.updateResoreData(oldNode: oldNode, resoreGroup: addToGroup)
            
        } appendMessagesBack: {[weak self] addDevice, appendCompletion in
            guard let self = self, let newNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) else {
                appendCompletion([])
                return
            }
            
            var oldNode = deviceData.node
            var addToGroup = oldNode.group
//            if oldNode.groupState == .exitFailure {
//                addToGroup = nil
//            }
//            
            if let section = self.showSections.first(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == addDevice }) }), let data = section.restoreDatas.first(where: { $0.unprovisionedDevice == addDevice }) {
                oldNode = data.node
                if oldNode.groupState == .exitFailure {
                    addToGroup = nil
                }else {
                    addToGroup = section.group
                }
            }
//            
//            // 恢复数据
//            newNode.updateResoreData(oldNode: oldNode, resoreGroup: addToGroup)
            
            var appendMessages: [MeshMessageHandle] = []
            // 入网后默认调为最大亮度
            if let model = newNode.lightnessModel {
                appendMessages.append(MeshMessageHandle(message: LightLightnessSetUnacknowledged(lightness: .max), model: model))
            }
            let syncDatas = newNode.getSyncData(type: .all)
            syncDatas.forEach({
                appendMessages.append(contentsOf: $0.getMessageHandles(node: newNode))
            })
//            appendMessages.append(contentsOf: newNode.getResoreMessageHandles(oldNode: oldNode))
            
            if addToGroup == nil {
                if let vendorModel = newNode.sunricherVendorModel { // 未加入组的设备默认设置一个手动控制延迟时间，避免默认30s后状态被LC修改
                    appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max)), model: vendorModel))
                }
                if let powerOnOffSetupModel = newNode.powerOnOffSetupModel { // 设置默认上电状态为上一次亮度
                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .restore), model: powerOnOffSetupModel))
                    //                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .default), model: powerOnOffSetupModel))
                    //                    appendMessages.append(MeshMessageHandle(message: LightLightnessDefaultSet(lightness: .max), model: lightnessSetupModel))
                }
            }
            // 需要追加发送的消息
            if let ctlModel = newNode.ctlModel, newNode.temperatureModel != nil {
                appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
                newNode.lightCTLTemperatureRange = oldNode.lightCTLTemperatureRange
            }
            // 节点数据hash
//            if let vendorModel = newNode.sunricherVendorModel {
//                appendMessages.append(MeshMessageHandle(message: SunricherVendorGet(function: .compositionHash), model: vendorModel))
//                newNode.compositionHash = oldNode.compositionHash
//            }
            // 添加成功后闪烁
            if let healthModel = newNode.healthModel {
                appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
            }
            appendCompletion(appendMessages)
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
            if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) {
//                if let repalceNode = addDevice.repalceNode { // 删除被替换节点的缓存数据
//                    repalceNode.deleteExtension()
//                }
                node.rssi = addDevice.rssi.intValue
                node.macAddress = addDevice.macAddress
                node.name = deviceData.node.name
                if let section = self.showSections.first(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == addDevice }) }), let data = section.restoreDatas.first(where: { $0.unprovisionedDevice == addDevice }) {
                    node.name = data.node.name
                }
                node.save()
                // 恢复数据不包括邻近照明邻居关系，因涉及邻居节点，需要各设备恢复后再去外部同步数据
                if node.needSync && node.getNodeSyncProximityLighting() == nil {
                    addDevice.addState = .syncFailed
                }
                self.restoreNodes.append(node)
            }
            self.reloadDeviceState(addDevice)
            self.updateUIState()
            
        } addFail: {[weak self] addDevice, error in
            addDevice.addState = .failed
            addDevice.selectedState = .selected
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
            
        } addFinish: {[weak self] successList, failList in
            guard let self = self else { return }
            
            // 添加完成后检查是否有设备需要同步
            let needSyncNodes = self.restoreNodes.filter({ $0.needSync })
            if needSyncNodes.count > 0 {
                needSyncNodes.forEach({ node in
                    if let device = successList.first(where: { $0.address == node.primaryUnicastAddress }) {
                        device.addState = .syncFailed
                    }
                })
                self.tableView.reloadData()
                self.updateUIState()
            }
            
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
            // 是否自动化恢复流程
            if self.automationRestore {
                if failList.count > 0 && automationRetryCount > 0 {
                    automationRetryCount -= 1
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                        guard let self = self, self.automationRestore else { return }
                        self.addSelectedBtnClick()
//                        failList.compactMap({ device in self.showRestoreData.first(where: { $0.unprovisionedDevice?.peripheral.identifier == device.peripheral.identifier }) }).forEach({
//                            self.addDevice($0)
//                        })
                    }
                  
                }else {
                    
                    // TODO: 等几秒钟进入同步页面，添加设备完成后代理可能还在连接中
                    // 恢复设备后是否有同步失败的设备
                    if self.allDevices.contains(where: { $0.addState == .syncFailed }) {
                        syncBtnAction()
                    }else {
                        dismiss()
                    }
                }
               
            }
        }
    }
    
    /// 检查设备地址是否足够
    private func checkDeviceAddressesAreSufficient(devices: [DeviceRestoreData]) {
        
        let bleConnectCount = max(showDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        for (index, device) in devices.enumerated() {
            if index < (5 - bleConnectCount) {
                device.unprovisionedDevice?.addState = .addConnecting
            }else {
                device.unprovisionedDevice?.addState = .wait
            }
            device.unprovisionedDevice?.selectedState = .disabled
            if let unprovisionedDevice = device.unprovisionedDevice {
                reloadDeviceState(unprovisionedDevice)
            }
        }
        self.updateUIState()
        
        DispatchQueue.global().async {
            // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
            let estimatedAddressCount = devices.reduce(0, { (result, device) in result + (device.unprovisionedDevice?.elementCount ?? 0) })
            // 可用地址数量
            let availableUnicastCount = MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.space.meshUUID)
            
            // 检查剩余地址是否足够添加设备
            guard availableUnicastCount >= estimatedAddressCount else {
                
                // 获取网络内已存在的设备地址数量
                let existingAddressCount = Node.loadAddresses(meshUUID: self.space.meshUUID).count
                // 申请的地址数量
                let applyAddressCount = estimatedAddressCount - availableUnicastCount + Int(Float(existingAddressCount) * 0.2)
                
                // 地址不够
                // 手机是否联网
                guard NetworkRequest.shared.networkable else {
                    // 未联网提示联网以获取地址
                    self.space.applyDeviceAddressCount = applyAddressCount
                    self.space.save()
                    
                    DispatchQueue.main.async {
//                        XWHUDManager.hide()
                        devices.forEach({
                            if let unprovisionedDevice = $0.unprovisionedDevice {
                                unprovisionedDevice.addState = .none
                                unprovisionedDevice.selectedState = .selected
                                self.reloadDeviceState(unprovisionedDevice)
                            }
                        })
                        self.updateUIState()
                        SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                            if NetworkRequest.shared.networkable {
                                self?.space.applyDeviceAddressCount = nil
                                self?.space.save()
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
    private func applyDeviceAddressesRequest(applyAddressCount: Int, devices: [DeviceRestoreData] = []) {

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
                    devices.forEach({
                        if let unprovisionedDevice = $0.unprovisionedDevice {
                            unprovisionedDevice.addState = .none
                            unprovisionedDevice.selectedState = .selected
                            self.reloadDeviceState(unprovisionedDevice)
                        }
                    })
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
                devices.forEach({
                    if let unprovisionedDevice = $0.unprovisionedDevice {
                        unprovisionedDevice.addState = .none
                        unprovisionedDevice.selectedState = .selected
                        self.reloadDeviceState(unprovisionedDevice)
                    }
                })
                self.updateUIState()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
       
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
        
        var selectDeviceDatas: [DeviceRestoreData] = []
        showSections.forEach { section in
            selectDeviceDatas.append(contentsOf: section.restoreDatas.filter({ $0.unprovisionedDevice != nil && $0.unprovisionedDevice?.selectedState == .selected }))
        }
        checkDeviceAddressesAreSufficient(devices: selectDeviceDatas)
//        selectDeviceDatas.forEach { device in
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
    
    /// 点击同步设备
    @objc private func syncBtnAction() {
        
        let syncFailedDevices = allDevices.filter({ $0.addState == .syncFailed })
        let syncFailedNodes = syncFailedDevices.compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: $0.address) })
//        restoreNodes.filter({ $0.needSync })
        guard syncFailedNodes.count > 0 else {
            return
        }
        let vc = SyncDevicesViewController(type: .devices(syncFailedNodes))
        vc.automationRestore = automationRestore
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.hideAutomaticHud()
            if self.automationRestore, case .specified = restoreMode {
                self.deviceRestoreCallback?(self.restoreNodes, self.automationRestore)
                self.navigationController?.popToViewController(vcClass: BleFirmwareUpdateViewController.classForCoder())
            }else {
                self.navigationController?.popViewController(animated: true)
                syncFailedDevices.forEach { device in
                    if let node = syncFailedNodes.first(where: { $0.primaryUnicastAddress == device.address }), !node.needSync {
                        device.addState = .success
                    }
                }
                self.tableView.reloadData()
                self.updateUIState()
            }
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            syncFailedDevices.forEach { device in
                if let node = syncFailedNodes.first(where: { $0.primaryUnicastAddress == device.address }), !node.needSync {
                    device.addState = .success
                }
            }
            self.tableView.reloadData()
            self.updateUIState()
        }
        navigationController?.pushViewController(vc, animated: true)
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
//            if !automationRestore {
                let shadeView = UIView(frame: view.bounds)
                shadeView.backgroundColor = RGB(0, 0, 0, 0.4)
                emptyView.insertSubview(shadeView, belowSubview: emptyView.contentView)
//            }
            if isIPad && self.automationRestore {
                shadeView.layer.cornerRadius = 20
            }
        }
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
            self.perform(#selector(self.hideDeviceNotFound), with: nil, afterDelay: 5)
        }
        
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        
        if let sectionIndex = showSections.firstIndex(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == device }) }), let row = showSections[sectionIndex].restoreDatas.firstIndex(where: { $0.unprovisionedDevice == device }) {
            if let cell = tableView.cellForRow(at: IndexPath(row: row, section: sectionIndex)) as? DeviceAddViewCell {
                cell.device = device
                if device.addState == .addConnecting || device.addState == .adding {
                    cell.addStateLabel.isHidden = true
                    cell.stateImageView.snp.updateConstraints { make in
                        make.width.height.equalTo(30)
                    }
                }
                cell.selectImageView.isHidden = false
            }else {
                tableView.reloadRows(at: [IndexPath(row: row, section: sectionIndex)], with: .none)
            }
        }else {
            tableView.reloadData()
        }
    }
    
    /// 隐藏找不到设备提示
    @objc private func hideDeviceNotFound() {
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
        }
        view.hideEmptyDataView()
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
        navigationBackBtn.isHidden = false
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // 添加设备中

        if showDevices.contains(where: { $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }) {
            state = .adding
            navigationBackBtn.isHidden = true
            self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }else if showDevices.contains(where: { $0.addState == .identifyConnecting || $0.addState == .identifying }) { // identify中
            state = .identifying
        }else if showDevices.contains(where: { $0.addState == .success || $0.addState == .failed || $0.addState == .syncFailed }) { // 操作完成（add）
            state = .addFineshed
        }else if state != .scanning {
            state = .none
        }
        // 未操作、操作成功可以筛选信号
        rssiSlider.isEnabled = state == .none || state == .addFineshed
        scanBtn.isEnabled = state == .none || state == .scanning || state == .addFineshed
        
//        if rssiSlider.isEnabled {
//            rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
//            rssiSlider.minimumTrackTintColor = Slider_Color
//        }else {
//            rssiSlider.setThumbImage(UIImage(named: "slider_point_disable"), for: .normal)
//            rssiSlider.minimumTrackTintColor = Slider_Color.withAlphaComponent(0.5)
//        }
        
        UIApplication.shared.isIdleTimerDisabled = false
        
        footerView.selectAllBtn.isHidden = false
        footerView.selectAllLabel.text = "select_all".localizedString
        footerView.addSelectedBtn.isHidden = false
        footerView.syncBtn.isHidden = true
        if footerView.frame == .zero {
            footerView.layoutIfNeeded()
        }
        
        switch state {
        case .none:
            footerView.isHidden = false
            addResultView.isHidden = true
            updateFooterViewState()
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
        case .scanning:
            footerView.isHidden = false
            footerView.selectAllBtn.isHidden = true
            footerView.selectAllLabel.text = "devices_found".localizedString
            footerView.addSelectedBtn.isHidden = true
            switch self.restoreMode {
            case .default:
                footerView.selectCountLabel.text = "\(showDevices.count)"
            case .specified(let nodes):
                
                footerView.selectCountLabel.text = "\(showDevices.count)/\(nodes.count - restoreNodes.count)"
            }
            
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
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
            
            let successCount = allDevices.filter({ $0.addState == .success }).count
            let failedCount = allDevices.filter({ $0.addState == .failed }).count
            let syncFailedCount = allDevices.filter({ $0.addState == .syncFailed }).count
            addResultView.successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
            addResultView.failedCountLabel.text = "\(failedCount)"
            if syncFailedCount > 0 {
                addResultView.syncFailedLabel.isHidden = false
                addResultView.syncFailedCountLabel.isHidden = false
                addResultView.syncFailedCountLabel.text = "\(syncFailedCount)"
                self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            }else {
                addResultView.syncFailedLabel.isHidden = true
                addResultView.syncFailedCountLabel.isHidden = true
            }
            
            if syncFailedCount > 0 && state == .addFineshed {
                footerView.syncBtn.isHidden = false
            }else {
                footerView.syncBtn.isHidden = true
            }
        }
        
    }
    
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        print(changeRSSIRange)
        selectRSSIRange = changeRSSIRange
        // 筛选展示的设备
//        showDevices = scanDevices.filter({ showDeviceTypes.contains($0.deviceType) && selectRSSIRange.contains($0.rssi.intValue) })

        farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
        nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
        
        // 筛选展示的设备
        var currentShowSections: [DeviceRestoreSection] = []
        sections.forEach { section in
            let devices = section.restoreDatas.filter({ $0.unprovisionedDevice == nil || selectRSSIRange.contains($0.unprovisionedDevice!.rssi.intValue) })
            if devices.count > 0 {
                currentShowSections.append(DeviceRestoreSection(group: section.group, restoreDatas: devices))
            }
        }
        showSections = currentShowSections
        
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
        tableView.register(DeviceLightInfoSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
//        tableView.register(DeviceRestoreEmptyViewCell.classForCoder(), forCellReuseIdentifier: "emptyCell")
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
        footerView.addSelectedBtn.layer.cornerRadius = SCRYFrom(20)
        footerView.addSelectedBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        footerView.addSelectedBtn.setTitle("restore_selected".localizedString, for: .normal)
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        footerView.selectAllBtn.addTarget(self, action: #selector(selectAllBtnClick), for: .touchUpInside)
        footerView.addSelectedBtn.addTarget(self, action: #selector(addSelectedBtnClick), for: .touchUpInside)
        let btnSize = CGSize(width: SCRXFrom(140), height: SCRYFrom(40))
        footerView.addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color), for: .normal)
        footerView.addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        footerView.addSelectedBtn.snp.updateConstraints { make in
            make.size.equalTo(btnSize)
        }
        footerView.syncBtn.addTarget(self, action: #selector(syncBtnAction), for: .touchUpInside)
        
        addResultView = DeviceAddResultView()
        addResultView.addResultLabel.text = "restore_result".localizedString
        addResultView.isHidden = true
        view.addSubview(addResultView)
        addResultView.snp.makeConstraints { make in
            make.bottom.equalTo(footerView.snp.top).offset(SCRYFrom(-1))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
        }
        addResultView.closeBtn.addTarget(self, action: #selector(closeBtnClick), for: .touchUpInside)
        addResultView.stopAddBtn.addTarget(self, action: #selector(stopAddBtnClick), for: .touchUpInside)
        addResultView.stopAddBtn.snp.remakeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.top.equalTo(SCRYFrom(7))
            make.height.equalTo(SCRYFrom(32))
        }
    }

}

extension DeviceRestoreViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return showSections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionData = showSections[section]
        return sectionData.isShow ?sectionData.restoreDatas.count : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionData = showSections[indexPath.section]
//        if sectionData.restoreDatas.isEmpty {
//            let emptyCell = tableView.dequeueReusableCell(withIdentifier: "emptyCell", for: indexPath) as! DeviceRestoreEmptyViewCell
//            return emptyCell
//        }else {
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
            cell.selectionStyle = .none
            let deviceData = sectionData.restoreDatas[indexPath.row]
            //        let device = showDevices[indexPath.row]
            if let device = deviceData.unprovisionedDevice {
                cell.device = device
                if device.addState == .addConnecting || device.addState == .adding {
                    cell.addStateLabel.isHidden = true
                    cell.stateImageView.snp.updateConstraints { make in
                        make.width.height.equalTo(30)
                    }
                }
                cell.selectImageView.isHidden = false
            }else {
                cell.deviceImageView.image = UIImage(named: deviceData.node.iconName)?.withTintColor(RGB(166, 166, 166))
                cell.identifyAnimationView.isHidden = true
                cell.nameLabel.text = deviceData.node.name
                cell.macAddressLabel.text = deviceData.node.macAddress?.getMacAddressSegmentString()
                cell.identifyBtn.isEnabled = false
                cell.addBtn.isEnabled = false
                cell.identifyBtn.isHidden = false
                cell.addBtn.isHidden = false
                cell.identifyBtn.layer.borderColor = RGB(156, 163, 175, 0.5).cgColor
                cell.selectImageView.isHidden = true
                cell.stateImageView.isHidden = true
                cell.signalStrengthView.setSignalStrength(rssi: -999)
                cell.signalLabel.text = nil
            }
            cell.addBtn.setImage(UIImage(named: "device_restore"), for: .normal)
            cell.addBtn.setImage(UIImage(named: "device_restore_disable"), for: .disabled)
            cell.delegate = self
            return cell
//        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceLightInfoSectionView
        let sectionData = showSections[section]
        if let group = sectionData.group {
            headerView.titleLabel.text = group.name
        }else {
            headerView.titleLabel.text = "not_in_the_group".localizedString
        }
        headerView.showImageView.isHidden = false
        headerView.showImageView.image = UIImage(named: sectionData.isShow ? "arrow_up": "arrow_down")
        headerView.sectionViewClickCallback = {
            sectionData.isShow = !sectionData.isShow
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let sectionData = showSections[indexPath.section]
        guard indexPath.row < sectionData.restoreDatas.count else {
            return
        }
        let deviceData = sectionData.restoreDatas[indexPath.row]
        guard let device = deviceData.unprovisionedDevice, device.selectedState == .unselected || device.selectedState == .selected else {
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

extension DeviceRestoreViewController: DeviceAddViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        if device.addState == .identifying {
            return
        }
        if state == .scanning {
            
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_identify".localizedString)
            return
        }
        if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: device.address), node.healthModel != nil, node.healthModel!.boundApplicationKeys.count > 0 { // 已加入网络的设备identity用mesh方式
            MeshAPI.identify(address: node.primaryUnicastAddress)
          
            cell.identifyStateLabel.text = "identifying".localizedString
            cell.identifyAnimationView.isHidden = false
//                    deviceImageView.layer.addOpacityAnimation(fromOpacity: 1, toOpacity: 0, duration: 0.5, repeatCount: 10, animationKey: "identify")
            cell.identifyAnimationView.layer.addScaleAnimation(fromScale: 0, toScale: 1, duration: 1, repeatCount: .max, timingName: .easeInEaseOut, animationKey: "identify")
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 5) {[weak self] in
                self?.reloadDeviceState(device)
            }
        }else {
            identify(device)
        }
    }
    
    /// 设备添加点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_add".localizedString)
            return
        }
        if let deviceData = showSections.compactMap({ $0.restoreDatas.first(where: { $0.unprovisionedDevice == device }) }).first {
//            addDevice(deviceData)
            checkDeviceAddressesAreSufficient(devices: [deviceData])
        }
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

extension DeviceRestoreViewController {
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
    
    /// 恢复设备模式
    enum RestoreMode {
        /// 默认（无限制）
        case `default`
        /// 指定恢复部分设备，不在内的设备不显示
        case specified(nodes: [Node])
    }
    
    /// 设备恢复数据组
    class DeviceRestoreSection {
        /// 对应组
        let group: Group?
        /// 恢复数据list
        var restoreDatas: [DeviceRestoreData]
        /// 是否展开
        var isShow: Bool = true
        
        init(group: Group?, restoreDatas: [DeviceRestoreData]) {
            self.group = group
            self.restoreDatas = restoreDatas
        }
        
    }
    
    /// 设备恢复数据
    class DeviceRestoreData {
        /// 对应节点
        let node: Node
        /// 未配网的设备
        var unprovisionedDevice: ProvisioningDevice?
        
        init(node: Node, unprovisionedDevice: ProvisioningDevice? = nil) {
            self.node = node
            self.unprovisionedDevice = unprovisionedDevice
        }
    }
    
    
}
