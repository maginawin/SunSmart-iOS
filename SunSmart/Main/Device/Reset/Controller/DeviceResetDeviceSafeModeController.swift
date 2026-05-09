//
//  DeviceResetDeviceSafeModeController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/15.
//

import UIKit
import NordicSigMeshSDK

class DeviceResetDeviceSafeModeController: UIViewController {

    /// 导航栏按键
    private var navigationBackBtn: UIButton!
    private var settingsView: UIView!
    private var settingsBtn: UIButton!
    private var settingsTipView: UIView!
    
    private var loadingBar: GradientLoadingBar!
    
    /// 信号滑条
    private var rssiView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: RangeSlider!
    private var farLabel: UILabel!
    /// 注意事项
    private var noteView: UIView!
    private var noteImageView: UIImageView!
    private var noteLabel: UILabel!
    /// 选择所有view
    private var selectAllView: UIView!
    private var selectAllBtn: UIButton!
    private var selectAllLabel: UILabel!
    /// 停止扫描view
    private var stopScanView: UIView!
    private var stopScanBtn: UIButton!
    private var scanMessageLabel: UILabel!
    
    private var tableView: UITableView!
    /// 重置设备结果
    private var resetResultView: DeviceAddResultView!
    /// 底部view
    private var footerView: DeviceBottomBtnView!
    
    /// 参数设置view
    private var parameterSettingsView: DeviceAddParameterSettingsView?
    
    /// 扫描到的已配网设备list
//    private var provisionedDeviceDevices: [ProvisioningDevice] = []
    /// 触发设备list
    private var triggerDevices: [ProvisioningDevice] = []
    /// 展示的触发设备list
    private var showDevices: [ProvisioningDevice] = []
    /// 页面状态
    private var state: State = .none
    
    /// 可选的信号值范围
    private var selectRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 信号刷新定时器
    private var rssiSortTimer: Timer?
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?
    
    /// 当前无定向广播随机key
    private var randomKey: UInt16 = 0
    /// 广播时设备配置持续时长
    private let broadcasterDuration: UInt8 = 2
    /// 无定向广播
    private let broadcaster = BluetoothBroadcaster()
    /// 重置队列中心
    private var resetBroadcasterCentral: DeviceResetBroadcasterCentral!
    /// 重置设备定时器 key: macAddress  value: timer
    private var resetTimers: [String: BackgroundTimer] = [:]
    /// 重置扫描中
    private var resetScanning: Bool = false
    
    
    let resetMode: ResetMode
    
    init(resetMode: ResetMode) {
        self.resetMode = resetMode
        super.init(nibName: nil, bundle: nil)
        resetBroadcasterCentral = DeviceResetBroadcasterCentral(delegate: self)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "safe_mode".localizedString
        view.backgroundColor = Background_Color
        
        
        setupRightItem()
        setupUI()
        addObserver()
        
        startScan()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        SystemVolumeManager.shared.startObserveVolume()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        SystemVolumeManager.shared.stopObserveVolume()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if state == .scanning { // 退出页面/切换停止扫描
            stopScan()
        }
    }
    
    deinit {
        systemVolumeObservation = nil
    }
    
    private func addObserver() {
        
        systemVolumeObservation = SystemVolumeManager.shared.observe(\.currentVolume, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
            }
        })
    }
    
    
    // MARK: - Scan
    /// 开始扫描设备
    private func startScan(broadcaster: Bool = true) {
        if broadcaster {
            startBroadcaster()
        }
        state = .scanning
        resetScanning = false
//        provisionedDeviceDevices.removeAll()
        triggerDevices.removeAll()
        showDevices.removeAll()
        tableView.reloadData()
        updateUIState()
        // MeshProvisioningService.uuid, MeshProxyService.uuid,
        MeshLibManager.manager.scanDevice(withServices: []) {[weak self] peripheral, advertisementData, rssi in
            
            guard let self = self,
                  let scanDevice = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
                  scanDevice.cid == CompanyId,
                  scanDevice.macAddress != nil, !scanDevice.connectable else { return }
            
//            if scanDevice.connectable { // 是否可被连接，1827/1828服务
                
//                if scanDevice.provisioned { // 已入网设备
                    // 过滤移动感应不在信号范围内的设备
                    if rssi.intValue > self.filterRSSIRange.upperBound {
                        scanDevice.rssi = NSNumber(value: self.filterRSSIRange.upperBound)
                    }
//                    if self.resetMode == .motion, !self.selectRSSIRange.contains(rssi.intValue) {
//                        return
//                    }
                    
                    if let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.macAddress == scanDevice.macAddress }) {
                        
                        scanDevice.deviceName = node.name
                        scanDevice.icon = node.iconName
                        scanDevice.address = node.primaryUnicastAddress
                        scanDevice.deviceType = node.deviceType
                        scanDevice.selectedState = .selected
                    }else {
                        if let info = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.companyId == scanDevice.cid && $0.productId == scanDevice.pid }) {
                            scanDevice.deviceName = info.categoryName
                            scanDevice.deviceType = Node.DeviceType(deviceCategory: info.deviceCategory)
                            scanDevice.icon = EmergencyFireControllerIconName.addListIconName(for: scanDevice.deviceType, fallback: info.iconName)
                            scanDevice.selectedState = .selected
                        }else {
                            scanDevice.deviceType = .unknown
                            scanDevice.icon = "device_unknown"
                            scanDevice.selectedState = .disabled
                        }
                    }
                          
//                    if let index = self.provisionedDeviceDevices.firstIndex(where: { $0.macAddress == scanDevice.macAddress }) {
//                        self.provisionedDeviceDevices.replaceSubrange(index...index, with: [scanDevice])
//                    }else {
//                        self.provisionedDeviceDevices.append(scanDevice)
//                    }
                    
                    if let index = self.triggerDevices.firstIndex(where: { $0.macAddress == scanDevice.macAddress }) {
                        let cacheDevice = self.triggerDevices[index]
                        scanDevice.resetState = cacheDevice.resetState
                        scanDevice.selectedState = cacheDevice.selectedState
                        self.triggerDevices.replaceSubrange(index...index, with: [scanDevice])
                        self.startRssiSortTimer()
                    }else {
                        // 判断是否触发
                        if (self.resetMode == .flashlight && scanDevice.triggerActionTypes.contains(.lightSensing)) || (self.resetMode == .motion && scanDevice.triggerActionTypes.contains(.motionSensing) && self.selectRSSIRange.contains(scanDevice.rssi.intValue)) {
                            if self.state == .scanning {
                                scanDevice.resetState = .scanning
                            }
                            self.triggerDevices.append(scanDevice)
                            self.playerNotificationAudio()
                            self.startRssiSortTimer()
                        }
                    }
                    
//                    if !self.triggerDevices.contains(where: { $0.macAddress == scanDevice.macAddress }) {
//                        if (self.resetMode == .flashlight && scanDevice.triggerActionTypes.contains(.lightSensing)) || (self.resetMode == .motion && scanDevice.triggerActionTypes.contains(.motionSensing)) {
//                            
//                            scanDevice.resetState = .scanning
//                            self.triggerDevices.append(scanDevice)
//                            if self.resetMode == .flashlight {
////                                self.showDevices.append(scanDevice)
////                                self.tableView.insertRows(at: [IndexPath(row: self.showDevices.count - 1, section: 0)], with: .automatic)
////                                if self.showDevices.count == 1 {
////                                    self.updateUIState()
////                                }else {
////                                    self.updateSelectAllState()
////                                }
//                                self.playerNotificationAudio()
//                            }else {
//                                
//                            }
//                        }
//                    }
                    
//                }
//                else { // 未入网设备
//                    // 判断是否从已入网触发=>未入网，说明重置成功
//                    if let device = showDevices.first(where: { $0.macAddress == scanDevice.macAddress }) {
//                        device.resetState = .success
//                        self.reloadDeviceState(device)
//                        self.updateUIState()
//                    }
//                }
//            }else { // 无定向广播包
              
                // 找到已配网对应设备
//                if let provisionedDevice = self.provisionedDeviceDevices.first(where: { $0.macAddress == scanDevice.macAddress }) {
//                    provisionedDevice.triggerActionTypes = scanDevice.triggerActionTypes
//                    
//                    if let index = self.triggerDevices.firstIndex(where: { $0.macAddress == provisionedDevice.macAddress }) {
//                        let cacheDevice = self.triggerDevices[index]
//                        provisionedDevice.resetState = cacheDevice.resetState
//                        provisionedDevice.selectedState = cacheDevice.selectedState
//                        self.triggerDevices.replaceSubrange(index...index, with: [provisionedDevice])
//                        self.startRssiSortTimer()
//                    }else {
//                        // 判断是否触发
//                        if (self.resetMode == .flashlight && provisionedDevice.triggerActionTypes.contains(.lightSensing)) || (self.resetMode == .motion && provisionedDevice.triggerActionTypes.contains(.motionSensing) && self.selectRSSIRange.contains(provisionedDevice.rssi.intValue)) {
//                            if self.state == .scanning {
//                                provisionedDevice.resetState = .scanning
//                            }
//                            self.triggerDevices.append(provisionedDevice)
//                            self.playerNotificationAudio()
//                            self.startRssiSortTimer()
//                        }
//                    }
                    
                    
//                    if (self.resetMode == .flashlight && provisionedDevice.triggerActionTypes.contains(.lightSensing)) || (self.resetMode == .motion && provisionedDevice.triggerActionTypes.contains(.motionSensing)) {
//                        provisionedDevice.selectedState = .selected
//                        provisionedDevice.resetState = .scanning
//                        self.showDevices.append(provisionedDevice)
//                        self.tableView.insertRows(at: [IndexPath(row: self.showDevices.count - 1, section: 0)], with: .automatic)
//                        self.selectAllView.isHidden = showDevices.isEmpty
//                        self.updateSelectAllState()
//                        self.playerNotificationAudio()
//                    }
                    
//                }
//            }
        }
        
    }
    
    /// 停止扫描设备
    private func stopScan() {
        stopBroadcaster()
        MeshLibManager.manager.stopScan()
        
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        // 停止扫描设备状态设置为空状态
        triggerDevices.forEach({
            $0.resetState = .none
//            reloadDeviceState($0)
        })
        tableView.reloadData()
        updateUIState()
    }
    
    /// 开始扫描重置结果
    private func startResetScan() {
        if resetScanning {
            return
        }
        resetScanning = true
        // 扫描未入网设备
        MeshLibManager.manager.scanDevice(withServices: [MeshProvisioningService.uuid]) {[weak self] peripheral, advertisementData, rssi in
            
            guard let self = self,
                  let scanDevice = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
                  scanDevice.cid == CompanyId,
                  scanDevice.macAddress != nil else { return }
            
            // 判断是否从已入网触发=>未入网，说明重置成功
            if let device = showDevices.first(where: { $0.macAddress == scanDevice.macAddress }), device.resetState == .reseting {
                device.selectedState = .disabled
                device.resetState = .success
                self.removeResetTimer(device: device)
                self.reloadDeviceState(device)
                self.updateUIState()
                
                // 判断是否还有重置中的设备，没有则停止扫描
                if !self.showDevices.contains(where: { $0.resetState == .reseting }) {
                    stopResetScan()
                }
            }
        }
    }
    
    /// 停止扫描重置结果
    private func stopResetScan() {
        MeshLibManager.manager.stopScan()
        resetScanning = false
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        guard rssiSortTimer == nil || !rssiSortTimer!.isValid else {
            return
        }
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 0.5, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        
        triggerDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
        if resetMode == .motion {
            showDevices = triggerDevices.filter({ selectRSSIRange.contains($0.rssi.intValue) })
        }else {
            showDevices = triggerDevices
        }
        tableView.reloadData()
        updateSelectAllState()
        
        

//        if showDevices.count > 0 {
//            showDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
    
        
//        }
    }
    
    
    // MARK: - Broadcaster
    
    /// 开始无定向广播
    func startBroadcaster() {
        let randomKey = UInt16.random(in: 1...65535)
        self.randomKey = randomKey
        if resetMode == .flashlight {
            broadcaster.startBroadcasting(type: .ambientLightDiscoverReset(timeout: broadcasterDuration, key: randomKey, delta: deviceSettingsParameterData.illuminationDelta), interval: 0.5)
        }else if resetMode == .motion {
            broadcaster.startBroadcasting(type: .pirDiscoverReset(timeout: broadcasterDuration, key: randomKey), interval: 0.5)
        }
    }
    
    /// 停止无定向广播
    private func stopBroadcaster() {
        broadcaster.stopBroadcasting()
    }
    
    // MARK: - Timer
    
    private func addResetTimer(device: ProvisioningDevice) {
     
        let timer = BackgroundTimer.scheduledTimer(withTimeInterval: 15, repeats: false) {[weak self] timer in
            guard let self = self else { return }
            // 超时设备
            if let resetDevice = self.showDevices.first(where: { $0.macAddress == device.macAddress && $0.resetState == .reseting }) {
                resetDevice.selectedState = .selected
                resetDevice.resetState = .failed
                DispatchQueue.main.async {
                    self.reloadDeviceState(resetDevice)
                    self.updateUIState()
                }
            }
            // 判断是否还有重置中的设备，没有则停止扫描
            if !self.showDevices.contains(where: { $0.resetState == .reseting }) {
                stopResetScan()
            }
            timer.invalidate()
            self.resetTimers.removeValue(forKey: device.macAddress!)
        }
        resetTimers.updateValue(timer, forKey: device.macAddress!)
    }
    
    /// 删除重置定时器
    private func removeResetTimer(device: ProvisioningDevice) {
        if let timer = resetTimers.first(where: { $0.key == device.macAddress })?.value {
            timer.invalidate()
            resetTimers.removeValue(forKey: device.macAddress!)
        }
    }
    
    /// 播放添加设备通知
    private func playerNotificationAudio() {
        
        var parameterData: DeviceSettingsParameterData = .default
        if resetMode == .flashlight {
            parameterData = flashlightSafeModeParameterData
        }else {
            parameterData = motionModeParameterData
        }
        
        if parameterData.notificationEnable {
            try? DeviceAudioManager.manager.startAudio(type: .deviceAdd, volume: parameterData.volume)
        }
        if parameterData.vibrationEnable {
            DeviceAudioManager.manager.vibration()
        }
    }
    
    // MARK: - Action
    
    @objc private func backClick() {
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func parameterSettings() {
        
        var parameterData: DeviceSettingsParameterData = .default
        if resetMode == .flashlight {
            parameterData = flashlightSafeModeParameterData
        }else {
            parameterData = motionModeParameterData
        }
        
        if parameterSettingsView == nil {
            parameterSettingsView = DeviceAddParameterSettingsView(frame: UIScreen.main.bounds, parameterData: parameterData, showBrightness: false, showIllumination: resetMode == .flashlight, illuminationTip: "illumination_fluctuation_range_reset_tip".localizedString)
            parameterSettingsView?.volumeChangedEndCallback = { volume in
                try? DeviceAudioManager.manager.startAudio(type: .deviceReset, volume: volume)
            }
            parameterSettingsView?.settingsCallback = {[weak self] data in
                guard let self = self else { return }
                if self.resetMode == .flashlight {
                    flashlightSafeModeParameterData = data
                }else {
                    motionModeParameterData = data
                }
                
                // 正在发送扫描广播包中，修改广播包数据再发送
                if self.state == .scanning {
                    self.startBroadcaster()
                }
            }
            parameterSettingsView?.helpActionCallback = {[weak self] in
                guard let self = self else { return }
//                self.parameterSettingsView?.dismiss()
                let vc = DeviceParameterSetupInstructionsController(mode: .reset(mode: self.resetMode == .flashlight ? .flashlight : .motion))
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                    self.parameterSettingsView?.dismiss()
                }
                if self.presentingViewController == nil {
                    self.present(NavigationViewController(rootViewController: vc), animated: true)
                }else {
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            }
        }else {
            parameterSettingsView?.parameterData = deviceSettingsParameterData
        }
        parameterSettingsView?.show()
    }
    
    /// 重新开始
    @objc private func restart() {
        startScan()
    }
    
    /// 重置所选设备
    @objc private func resetSelected() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        guard selectDevices.count > 0 else {
            return
        }
        
        selectDevices.forEach({
            $0.resetState = .wait
            $0.selectedState = .disabled
            if let macAddress = $0.macAddress {
                let data = DeviceResetBroadcasterData(macAddress: macAddress, broadcasterType: .resetSensorNode(key: randomKey, macAddress: macAddress))
                resetBroadcasterCentral.addBroadcaster(data)
            }
        })
        tableView.reloadData()
        updateUIState()
    }
    
    /// 隐藏添加结果view
    @objc private func closeBtnClick() {
        resetResultView.isHidden = true
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
    }
    
    /// 停止重置（取消正在排队的设备）
    @objc private func stopAddBtnClick() {
        guard state == .reseting else {
            return
        }
//        TestDeviceAddManager.manager.cancelAwaitOperations()
        
        resetBroadcasterCentral.cancelAwaitBroadcasters()
        let waitDevices = showDevices.filter({ $0.resetState == .wait })
        waitDevices.forEach({
            $0.resetState = .none
            $0.selectedState = .selected
        })
        tableView.reloadData()
        updateUIState()
    }
    
    @objc private func selectAllBtnAction(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        
        let canResetDevices = showDevices.filter({ $0.selectedState != .disabled && !($0.resetState == .wait || $0.resetState == .reseting) })
        if sender.isSelected {
            canResetDevices.forEach({ $0.selectedState = .selected })
//            selectCountLabel.text = "\(devices.count)/\(devices.count)"
        }else {
            canResetDevices.forEach({ $0.selectedState = .unselected })
        }
        updateSelectAllState()
        tableView.reloadData()
        
    }
    
    @objc private func stopScanBtnAction() {
//        if state == .none {
//            startScan()
//        }else {
            stopScan()
//        }
    }
    
    /// 信号滑条修改
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        
        selectRSSIRange = changeRSSIRange
        farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
        nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
        
        // 筛选展示的设备
        showDevices = triggerDevices.filter({ selectRSSIRange.contains($0.rssi.intValue) })
         
        tableView.reloadData()
        updateSelectAllState()
        
    }

    // MARK: - UI
    
    /// 更新UI
    private func updateUIState() {

        // 重置设备中
        if showDevices.contains(where: { $0.resetState == .wait || $0.resetState == .reseting }) {
            state = .reseting
        }else if showDevices.contains(where: { $0.resetState == .identifyWait || $0.resetState == .identifying }) { // identify中
            state = .identifying
        }else if showDevices.contains(where: { $0.resetState == .success || $0.resetState == .failed }) { // 操作完成（reset）
            state = .resetFineshed
        }else if state != .scanning {
            state = .none
        }
        // 未操作、操作成功可以筛选信号
        rssiSlider.isEnabled = state == .none || state == .scanning || state == .resetFineshed
        
        if state == .scanning {
            stopScanView.isHidden = false
        }else {
            stopScanView.isHidden = true
        }
        
//        if rssiSlider.isEnabled {
//            rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
//            rssiSlider.minimumTrackTintColor = Slider_Color
//        }else {
//            rssiSlider.setThumbImage(UIImage(named: "slider_point_disable"), for: .normal)
//            rssiSlider.minimumTrackTintColor = Slider_Color.withAlphaComponent(0.5)
//        }
        footerView.deleteBtn.isEnabled = true
        UIApplication.shared.isIdleTimerDisabled = false
        loadingBar.isHidden = true
        loadingBar.stopAnimating()
        
        switch state {
        case .none:
            selectAllView.isHidden = false
            footerView.isHidden = false
            resetResultView.isHidden = true
            stopScanBtn.isHidden = false
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
        case .scanning:
            loadingBar.isHidden = false
            loadingBar.startAnimating()
            selectAllView.isHidden = showDevices.isEmpty
            footerView.isHidden = true
            tableView.contentInset = .zero
            resetResultView.isHidden = true
            if stopScanView.frame.isEmpty {
                stopScanView.layoutIfNeeded()
            }
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: stopScanView.height + SCRYFrom(8), right: 0)
        case .identifying:
            footerView.deleteBtn.isEnabled = false
        case .reseting, .resetFineshed:
            selectAllView.isHidden = false
            footerView.isHidden = false
            if state == .reseting {
                resetResultView.isHidden = false
                footerView.deleteBtn.isEnabled = false
                tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: resetResultView.height + footerView.height + SCRYFrom(8), right: 0)
                resetResultView.closeBtn.isHidden = true
                resetResultView.stopAddBtn.isHidden = !showDevices.contains(where: { $0.resetState == .wait})
                // 添加中设置屏幕常亮
                UIApplication.shared.isIdleTimerDisabled = true
            }else {
                resetResultView.closeBtn.isHidden = false
                resetResultView.stopAddBtn.isHidden = true
            }
            let successCount = showDevices.filter({ $0.resetState == .success }).count
            let failedCount = showDevices.filter({ $0.resetState == .failed }).count
            resetResultView.successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
            resetResultView.failedCountLabel.text = "\(failedCount)"
            
        }
        
        updateSelectAllState()
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        if let index = showDevices.firstIndex(of: device) {
            if let cell = tableView.cellForRow(at: IndexPath(row: index, section: 0)) as? DeviceForceResetViewCell {
                cell.device = device
            }else {
                tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }
        }else {
            tableView.reloadData()
        }
    }
    
    private func updateSelectAllState() {
        
        if selectAllView.isHidden {
            selectAllView.isHidden = showDevices.isEmpty
        }
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        let enableDevices = showDevices.filter({ $0.selectedState != .disabled })
        selectAllLabel.text = "\("select_all".localizedString)  \(selectDevices.count)/\(enableDevices.count)"
        selectAllBtn.isSelected = selectDevices.count == enableDevices.count && enableDevices.count > 0
        
//        footerView.selectCountLabel.text = "\(selectDevices.count)/\(enableDevices.count)"
//        if !enableDevices.isEmpty && selectDevices.count >= enableDevices.count {
//            footerView.selectAllBtn.isSelected = true
//        }else {
//            footerView.selectAllBtn.isSelected = false
//        }
//        footerView.addSelectedBtn.isEnabled = selectDevices.count > 0
    }
    
    private func setupRightItem() {
        
        settingsView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
        settingsBtn = UIButton(normalImageName: "device_add_setting", target: self, action: #selector(parameterSettings))
        settingsBtn.frame = CGRect(x: 0, y: 0, width: 30, height: 30)
        settingsView.addSubview(settingsBtn)
        
        settingsTipView = UIView()
        settingsTipView.layer.cornerRadius = 2.5
        settingsTipView.backgroundColor = RGB(255, 167, 44)
        settingsTipView.isUserInteractionEnabled = false
        settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        settingsBtn.addSubview(settingsTipView)
        settingsTipView.snp.makeConstraints { make in
            make.right.equalTo(-8.5)
            make.centerY.equalToSuperview().offset(0.5)
            make.width.height.equalTo(5)
        }
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: settingsView)
    }
    
    
    private func setupUI() {
        
        loadingBar = GradientLoadingBar()
        view.addSubview(loadingBar)
        loadingBar.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-6))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(6)
        }
        
        rssiView = UIView()
        rssiView.isHidden = true
        view.addSubview(rssiView)
        rssiView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        nearLabel.sizeToFit()
        rssiView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
//            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        farLabel.sizeToFit()
        rssiView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(nearLabel)
//            make.width.equalTo(farLabel.width)
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
        rssiSlider.minimumRange = 10
        rssiSlider.addTarget(self, action: #selector(rssiSliderValueChanged), for: .valueChanged)
        rssiView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(64))
            make.right.equalTo(SCRXFrom(-65))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        noteView = UIView()
        noteView.layer.cornerRadius = SCRYFrom(7)
        noteView.backgroundColor = RGB(239, 239, 239)
        noteView.isHidden = true
        view.addSubview(noteView)
        noteView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(rssiView.snp.bottom).offset(SCRYFrom(2))
            make.height.equalTo(SCRYFrom(27))
        }
        
        noteImageView = UIImageView(image: UIImage(named: "tips"))
        noteView.addSubview(noteImageView)
        noteImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(16)
        }
        
        noteLabel = UILabel(text: "devoce_motion_reset_note".localizedString, textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(noteImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
        }
        
        selectAllView = UIView()
        selectAllView.backgroundColor = Background_Color
        view.addSubview(selectAllView)
        selectAllView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(12))
            make.height.equalTo(SCRYFrom(30))
        }
        
        selectAllBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        selectAllView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        selectAllView.addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllBtn.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(70)
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(DeviceForceResetViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(selectAllView.snp.bottom)
        }
        
        footerView = DeviceBottomBtnView()
        footerView.deleteBtn.setTitle("RESTART".localizedString, for: .normal)
        footerView.deleteBtn.setTitleColor(Bar_Color, for: .normal)
        footerView.deleteBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        footerView.deleteBtn.addTarget(self, action: #selector(restart), for: .touchUpInside)
        footerView.saveBtn.setTitle("RESET SELECTED".localizedString, for: .normal)
        footerView.saveBtn.setTitleColor(Red_Color, for: .normal)
        footerView.saveBtn.setTitleColor(Red_Color.withAlphaComponent(0.5), for: .disabled)
        footerView.saveBtn.addTarget(self, action: #selector(resetSelected), for: .touchUpInside)
        footerView.showEditUI()
        footerView.isHidden = true
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
    
        resetResultView = DeviceAddResultView()
        resetResultView.addResultLabel.text = "reset_results".localizedString
        resetResultView.stopAddBtn.setTitle("stop_reseting".localizedString, for: .normal)
        resetResultView.isHidden = true
        view.addSubview(resetResultView)
        resetResultView.snp.makeConstraints { make in
            make.bottom.equalTo(footerView.snp.top).offset(SCRYFrom(-1))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
        }
        resetResultView.closeBtn.addTarget(self, action: #selector(closeBtnClick), for: .touchUpInside)
        resetResultView.stopAddBtn.addTarget(self, action: #selector(stopAddBtnClick), for: .touchUpInside)
        
        stopScanView = UIView()
        stopScanView.backgroundColor = .white
        view.addSubview(stopScanView)
        stopScanView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(max(kSafeAreaBottomHeight, 8) + SCRYFrom(56))
        }
        
        let stopScanLineView = UIView()
        stopScanLineView.backgroundColor = Line_Color
        stopScanView.addSubview(stopScanLineView)
        stopScanLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }
        
        stopScanBtn = UIButton(title: "STOP".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(stopScanBtnAction))
        stopScanView.addSubview(stopScanBtn)
        stopScanBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalToSuperview()
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(50))
        }
        
        
        let message = resetMode == .flashlight ? "illuminance_reset_scan_message".localizedString : "motion_reset_scan_message".localizedString
        scanMessageLabel = UILabel(text: message, textColor: ImportantText_Color, fontSize: 12, fontWeight: .light, fit: false)
        scanMessageLabel.textAlignment = .center
        scanMessageLabel.numberOfLines = 0
        stopScanView.addSubview(scanMessageLabel)
        scanMessageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(stopScanBtn.snp.bottom).offset(SCRYFrom(-3))
        }
        
        if resetMode == .motion {
            rssiView.isHidden = false
            noteView.isHidden = false
            selectAllView.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.top.equalTo(noteView.snp.bottom).offset(SCRYFrom(8))
                make.height.equalTo(SCRYFrom(30))
            }
        }
        
    }
  

}

extension DeviceResetDeviceSafeModeController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return showDevices.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceForceResetViewCell
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
        if device.resetState == .failed {
            device.resetState = .none
            device.selectedState = .selected
            tableView.reloadRows(at: [indexPath], with: .none)

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
        
        updateSelectAllState()
    }
    
}

extension DeviceResetDeviceSafeModeController: DeviceForceResetViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceForceResetViewCell, identify device: ProvisioningDevice) {
        
        if let identifyDevice = showDevices.first(where: { $0.resetState == .identifyWait || $0.resetState == .identifying }) {
            identifyDevice.resetState = .none
            reloadDeviceState(identifyDevice)
            resetBroadcasterCentral.cancelBroadcaster(data: DeviceResetBroadcasterData(macAddress: identifyDevice.macAddress!, broadcasterType: .identifySensorNode(key: randomKey, macAddress: identifyDevice.macAddress!)))
        }
        
        device.resetState = .identifyWait
        reloadDeviceState(device)
        updateUIState()
        
        resetBroadcasterCentral.addBroadcaster(DeviceResetBroadcasterData(macAddress: device.macAddress!, broadcasterType: .identifySensorNode(key: randomKey, macAddress: device.macAddress!)))
    }
    
    /// 设备重置事件回调
    func cell(_ cell: DeviceForceResetViewCell, deviceReset device: ProvisioningDevice) {
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_reset".localizedString)
            return
        }
        if device.resetState == .identifyWait || device.resetState == .identifying { // 停止发送identity
            resetBroadcasterCentral.cancelBroadcaster(data: DeviceResetBroadcasterData(macAddress: device.macAddress!, broadcasterType: .identifySensorNode(key: randomKey, macAddress: device.macAddress!)))
        }
        
        device.resetState = .wait
        device.selectedState = .disabled
        reloadDeviceState(device)
        resetBroadcasterCentral.addBroadcaster(DeviceResetBroadcasterData(macAddress: device.macAddress!, broadcasterType: .resetSensorNode(key: randomKey, macAddress: device.macAddress!)))
        updateUIState()
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceForceResetViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
        guard device.resetState == .wait || device.resetState == .failed else {
            return
        }
        if device.resetState == .wait { // 等待删除
            resetBroadcasterCentral.cancelBroadcaster(data: DeviceResetBroadcasterData(macAddress: device.macAddress!, broadcasterType: .resetSensorNode(key: randomKey, macAddress: device.macAddress!)))
        }
        
        // 设备状态回归为默认状态
        device.resetState = .none
        device.selectedState = .selected
        reloadDeviceState(device)
        
        updateUIState()
        
    }
    
}

extension DeviceResetDeviceSafeModeController: DeviceResetBroadcasterCentralDelegate {
    
    /// 开始发送广播包回调
    func broadcasterCentral(_ broadcasterCentral: DeviceResetBroadcasterCentral, didSendBroadcaster broadcasterData: DeviceResetBroadcasterData) {
        
        if let device = showDevices.first(where: { $0.macAddress == broadcasterData.macAddress }) {
            if case .resetSensorNode = broadcasterData.broadcasterType, device.resetState == .wait {
                device.resetState = .reseting
                reloadDeviceState(device)
                // 开始重置倒计时
                addResetTimer(device: device)
                // 开始扫描重置结果
                if !resetScanning {
                    startResetScan()
                }
//                reloadDataing = true
            }else if case .identifySensorNode = broadcasterData.broadcasterType, device.resetState == .identifyWait {
                device.resetState = .identifying
                reloadDeviceState(device)
//                reloadDataing = true
            }
            updateUIState()
        }
    }
    
    /// 发送广播包完成回调
    func broadcasterCentral(_ broadcasterCentral: DeviceResetBroadcasterCentral, didFinishedBroadcaster broadcasterData: DeviceResetBroadcasterData) {
        
        if let device = showDevices.first(where: { $0.macAddress == broadcasterData.macAddress }) {
            if case .identifySensorNode = broadcasterData.broadcasterType, device.resetState == .identifying {
                device.resetState = .none
                reloadDeviceState(device)
//                if reloadDataing, (state != .identifying || state != .reseting) {
//                    reloadDataing = false
//                }
//                reloadDataing = true
                updateUIState()
            }
        }
        
    }
    
    
    
}

extension DeviceResetDeviceSafeModeController {
    /// 设备重置页面状态
    enum State {
        /// 无状态
        case none
        /// 扫描设备中
        case scanning
        /// identify中
        case identifying
        /// 重置设备中
        case reseting
        /// 重置完成
        case resetFineshed
    }
    
    ///重置模式
    enum ResetMode {
        /// 手电筒
        case flashlight
        /// 移动感应
        case motion
    }
}

extension ProvisioningDevice {
    
    static var resetStateKey: UInt8 = 0
    
    static var versionKey: UInt8 = 0
    
    /// 设备重置状态
    enum DeviceResetState {
        /// 无
        case none
        /// 扫描中
        case scanning
        /// 等待重置
        case wait
        /// identify等待
        case identifyWait
        /// identify中
        case identifying
        /// identity失败
        case identifyFail
        /// 重置中
        case reseting
        /// 重置成功
        case success
        /// 重置失败
        case failed
        /// 操作禁止
        case disable
    }

    /// 重置状态
    var resetState: DeviceResetState {
        get {
            objc_getAssociatedObject(self, &ProvisioningDevice.resetStateKey) as? DeviceResetState ?? .none
        }set {
            objc_setAssociatedObject(self, &ProvisioningDevice.resetStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 设备版本
    var version: String? {
        get {
            objc_getAssociatedObject(self, &ProvisioningDevice.versionKey) as? String
        }set {
            objc_setAssociatedObject(self, &ProvisioningDevice.versionKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
