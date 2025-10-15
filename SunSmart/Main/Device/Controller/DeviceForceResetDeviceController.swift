//
//  DeviceForceResetDeviceController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/14.
//

import UIKit
import NordicSigMeshSDK
import CoreBluetooth

protocol DeviceForceResetDeviceControllerDelegate: AnyObject {
    
    /// 发现设备
    func controller(_ controller: DeviceForceResetDeviceController, deviceDiscovered device: ProvisioningDevice)
    
    /// 设备操作状态
    func controller(_ controller: DeviceForceResetDeviceController, deviceStateChanged deviceState: DeviceForceResetDeviceController.DeviceState)
    
    /// 设备重置成功
    func controller(_ controller: DeviceForceResetDeviceController, deviceResetFinish device: ProvisioningDevice)
    
}

class DeviceForceResetDeviceController: UIViewController {

    ///重置模式
    enum ResetMode {
        
        var info: (title: String, imageName: String, steps: [String]) {
            switch self {
            case .flashlight:
                return ("force_reset_message".localizedString, "device_reset_flashlight", ["force_reset_step_1".localizedString, "force_reset_flashlight_step_2".localizedString, "force_reset_step_3".localizedString])
            case .motion:
                return ("force_reset_message".localizedString, "device_reset_motion", ["force_reset_step_1".localizedString, "force_reset_motion_step_2".localizedString, "force_reset_step_3".localizedString])
            }
        }
        
        /// 手电筒
        case flashlight
        /// 移动感应
        case motion
    }
    
    /// 状态
    enum State {
        /// 无
        case none
        /// 扫描中
        case scaning
        /// 已发现
        case discovered
    }
    
    /// 设备状态
    enum DeviceState {
        /// 无
        case none
        /// 识别中
        case identifying
        /// 识别完成
        case idenfityFinish
        /// 删除中
        case reseting
    }
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var sliderView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: RangeSlider!
    private var farLabel: UILabel!
    
    private var headerView: UIView!
    private var titleLabel: UILabel!
    private var imageView: UIImageView!
    private var stepView: GroupPathSequenceDeviceAddStepView!
    private var deviceView: DeviceForceResetDeviceView!

    
    private var loadingView: UIView!
    private var loadingImageView: UIImageView!
    
    private var bottomBtn: UIButton!
    
    private(set) var state: State = .none
    private var deviceState: DeviceState = .none
    /// 扫描到的设备
//    private var scanDevices: [ProvisioningDevice] = []
    /// 待删除的设备
    private var device: ProvisioningDevice?
    /// 待删除设备所在组（当前space内设备）
    private var deviceGroup: Group?
    
    /// 无定向广播
    private let broadcaster = BluetoothBroadcaster()
    /// 当前无定向广播随机key
    private var randomKey: UInt16 = 0
    
    weak var delegate: DeviceForceResetDeviceControllerDelegate?
    
    /// 广播时设备配置持续时长
    private let broadcasterDuration: UInt8 = 2
    /// 广播时光感上报阈值
//    private let lightSensorDelta: UInt16 = 80
    private var displayDeviceNamePrefix: Bool = true
    /// 可选的信号值范围
    private var selectRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 重新选择倒计时
    private var reselectDowncount: Int = 5
    private var reselectTimer: Timer?
    /// 扫描到的已配网设备list
    private var provisionedDeviceDevices: [ProvisioningDevice] = []
    
    let resetMode: ResetMode
    
    init(resetMode: ResetMode) {
        self.resetMode = resetMode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        displayDeviceNamePrefix = SpaceViewController.currentSpace()?.displayDeviceNamePrefix ?? true
        setupUI()
        updateUI()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        if state == .scaning {
            stopScan()
            state = .none
            updateUI()
        }else {
            if device != nil {
                device = nil
                deviceState = .none
                state = .none
                stopReselectTimer()
                updateUI()
                stopBroadcaster()
            }
        }
        
    }

    // MARK: - Scan
    /// 开始扫描设备
    private func startScan(broadcaster: Bool = true) {
        if broadcaster {
            startBroadcaster()
        }
        provisionedDeviceDevices.removeAll()
        // MeshProvisioningService.uuid, MeshProxyService.uuid,
        MeshLibManager.manager.scanDevice(withServices: []) {[weak self] peripheral, advertisementData, rssi in
            
            guard let self = self,
                  let scanDevice = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
                  scanDevice.cid == CompanyId,
                  scanDevice.macAddress != nil else { return }
            
            if scanDevice.connectable { // 是否可被连接，1827/1828服务
                // 过滤移动感应不在信号范围内的设备
                if self.resetMode == .motion, !self.selectRSSIRange.contains(rssi.intValue) {
                    return
                }
                if let currentDevice = self.device, currentDevice.macAddress == scanDevice.macAddress, scanDevice.networkId == nil, self.deviceState == .reseting { // 删除设备成功
                    self.deviceResetSuccess()
                    
                }else if scanDevice.networkId != nil { // 只显示已入网设备
                    if self.device != nil {
                        return
                    }
                    
                    if !provisionedDeviceDevices.contains(where: { $0.macAddress == scanDevice.macAddress }) {
                        provisionedDeviceDevices.append(scanDevice)
                    }
                    
                }
            }else { // 无定向广播包
                if self.device != nil {
                    return
                }
                // 找到已配网对应设备
                if let provisionedDevice = self.provisionedDeviceDevices.first(where: { $0.macAddress == scanDevice.macAddress }) {
                    provisionedDevice.triggerActionTypes = scanDevice.triggerActionTypes
                    
                    if (self.resetMode == .flashlight && provisionedDevice.triggerActionTypes.contains(.lightSensing)) || (self.resetMode == .motion && provisionedDevice.triggerActionTypes.contains(.motionSensing)) {
                        
                        if let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.macAddress == provisionedDevice.macAddress }) {
                            
                            provisionedDevice.deviceName = node.name
                            provisionedDevice.icon = node.iconName
                            provisionedDevice.address = node.primaryUnicastAddress
                            self.deviceGroup = node.group
                            
                        }else if let info = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.companyId == provisionedDevice.cid && $0.productId == provisionedDevice.pid }) {
                            provisionedDevice.deviceName = info.categoryName
                            provisionedDevice.icon = "device_\(info.iconCategory)"
                            self.deviceGroup = nil
                        }
                        
                        self.device = provisionedDevice
                        self.state = .discovered
//                        self.startReselectTimer()
                        self.updateUI()
                        
                        self.deviceView.update(device: provisionedDevice, displayDeviceNamePrefix: self.displayDeviceNamePrefix, deviceGroup: self.deviceGroup, state: .none)
                        // 找到一个设备后停止扫描
                        self.stopScan()
                        
                        self.delegate?.controller(self, deviceDiscovered: provisionedDevice)
                    }
                    
                }
            }
        }
        
    }
    
    /// 停止扫描设备
    private func stopScan() {
        stopBroadcaster()
        MeshLibManager.manager.stopScan()
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
    
    /// 开始重新选择倒计时
    private func startReselectTimer() {
        
        reselectDowncount = 5
        
        reselectTimer?.invalidate()
        reselectTimer = LCWeakTimer.scheduledTimer(timeInterval: 1, aTarget: self, selector: #selector(reselectTimerEvent), userInfo: nil, repeats: true)
        RunLoop.current.add(reselectTimer!, forMode: .common)
    }
    
    @objc private func reselectTimerEvent() {
        guard self.state == .discovered else {
            stopReselectTimer()
            updateUI()
            return
        }
        reselectDowncount -= 1
        if reselectDowncount == 0 {
            stopReselectTimer()
        }
        updateUI()
    }
    
    private func stopReselectTimer() {
        reselectTimer?.invalidate()
        reselectTimer = nil
    }
    
    // MARK: - Action
    
    @objc private func bottomBtnAction() {
       
        switch state {
        case .none:
            state = .scaning
            startScan()
        case .scaning:
            state = .none
            stopScan()
        case .discovered:
            state = .none
            device = nil
            deviceState = .none
            delegate?.controller(self, deviceStateChanged: deviceState)
        }
        updateUI()
        
    }
    
    /// 重置设备成功
    private func deviceResetSuccess() {
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.deviceResetTimeout), object: nil)
        }
        stopScan()
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        state = .none
        deviceState = .none
        delegate?.controller(self, deviceStateChanged: deviceState)
        stopReselectTimer()
        updateUI()
        if let device = self.device {
            delegate?.controller(self, deviceResetFinish: device)
        }
        device = nil
    }
    
    /// 重置设备超时
    @objc private func deviceResetTimeout() {
        
        guard let device = self.device, deviceState == .reseting else {
            deviceState = .idenfityFinish
            self.delegate?.controller(self, deviceStateChanged: deviceState)
            broadcaster.stopBroadcasting()
            return
        }
        
        deviceState = .idenfityFinish
        self.delegate?.controller(self, deviceStateChanged: deviceState)
        broadcaster.stopBroadcasting()
        updateUI()
        deviceView.update(device: device, displayDeviceNamePrefix: self.displayDeviceNamePrefix, deviceGroup: self.deviceGroup, state: deviceState)
        XWHUDManager.showErrorTipHUD("reset_failed".localizedString)
    }
    
    /// 信号滑条修改
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        print(changeRSSIRange)
        selectRSSIRange = changeRSSIRange

        farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
        nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
    }
    

    // MARK: - UI
    private func updateUI() {
        
        bottomBtn.isEnabled = true
        switch state {
        case .none:
            deviceView.isHidden = true
            loadingView.isHidden = true
            loadingImageView.image = nil
            bottomBtn.setTitle("START".localizedString, for: .normal)
        case .scaning:
            loadingView.isHidden = false
            if let fileURL = Bundle.main.url(forResource: "broadcast_loading", withExtension: "gif"), let imageData = try? Data.init(contentsOf: fileURL) {
                loadingImageView.image = XWHUDManager.imageGIF(with: imageData)
            }
            deviceView.isHidden = true
            bottomBtn.setTitle("STOP".localizedString, for: .normal)
        case .discovered:
            loadingView.isHidden = true
            loadingImageView.image = nil
            deviceView.isHidden = false
            
            if reselectTimer != nil && reselectDowncount > 0 {
                bottomBtn.setTitle("\("RESELECT".localizedString) \(reselectDowncount)", for: .normal)
                bottomBtn.isEnabled = false
            }else {
                bottomBtn.setTitle("RESELECT".localizedString, for: .normal)
                if deviceState == .identifying || deviceState == .reseting {
                    bottomBtn.isEnabled = false
                }
            }
            
           
        }
        bottomBtn.layer.borderColor = bottomBtn.isEnabled ? Bar_Color.cgColor : Bar_Color.withAlphaComponent(0.5).cgColor
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
//            make.height.greaterThanOrEqualToSuperview()
        }
        
        sliderView = UIView()
        sliderView.isHidden = true
        contentView.addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFit(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        nearLabel.sizeToFit()
        sliderView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
//            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        farLabel.sizeToFit()
        sliderView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalToSuperview()
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
        sliderView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-49))
            make.centerY.equalTo(nearLabel)
            make.height.equalToSuperview()
        }
        
        headerView = UIView()
        headerView.backgroundColor = .white
        headerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        let info = resetMode.info
        
        titleLabel = UILabel(text: info.title, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        titleLabel.numberOfLines = 0
        titleLabel.textAlignment = .center
        headerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.right.equalTo(SCRXFrom(-10))
            make.top.equalTo(SCRYFrom(16))
        }
        
        imageView = UIImageView(image: UIImage(named: info.imageName))
        headerView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(isIPad ? 100 : 16))
            make.right.equalTo(SCRXFrom(isIPad ? -100 : -16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(17))
//            make.centerX.equalToSuperview().offset(SCRXFrom(15))
            make.height.equalTo(imageView.snp.width).multipliedBy(170 / 311.0)
        }
        
        stepView = GroupPathSequenceDeviceAddStepView()
        stepView.step1View.titleLabel.text = info.steps[0]
        stepView.step2View.titleLabel.text = info.steps[1]
        stepView.step3View.titleLabel.text = info.steps[2]
        headerView.addSubview(stepView)
        stepView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-14))
            make.top.equalTo(imageView.snp.bottom).offset(SCRYFrom(26))
            make.height.greaterThanOrEqualTo(SCRYFrom(56))
            make.bottom.equalTo(SCRYFrom(-22))
        }
        
        deviceView = DeviceForceResetDeviceView()
        deviceView.isHidden = true
        deviceView.delegate = self
        contentView.addSubview(deviceView)
        deviceView.snp.makeConstraints { make in
            make.left.right.equalTo(headerView)
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(70))
        }
        
        loadingView = UIView()
        loadingView.backgroundColor = Background_Color
        loadingView.isHidden = true
        loadingView.layer.cornerRadius = 10
        contentView.addSubview(loadingView)
        loadingView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(16))
            make.width.height.equalTo(88)
            make.bottom.equalToSuperview()
        }
        
        loadingImageView = UIImageView()
        loadingView.addSubview(loadingImageView)
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(56)
        }
        
        bottomBtn = UIButton(title: "START".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(bottomBtnAction))
        bottomBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        bottomBtn.layer.cornerRadius = SCRYFrom(10)
        bottomBtn.layer.borderWidth = 0.5
        bottomBtn.layer.borderColor = Bar_Color.cgColor
        view.addSubview(bottomBtn)
        bottomBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(-kSafeAreaBottomHeight - SCRYFrom(24))
            make.width.equalTo(SCRXFrom(216))
            make.height.equalTo(SCRYFrom(44))
        }
        
        if resetMode == .motion {
            sliderView.isHidden = false
            headerView.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(sliderView.snp.bottom).offset(SCRYFrom(8))
            }
        }
        
    }
    
}

extension DeviceForceResetDeviceController: DeviceForceResetDeviceViewDelegate {
    
    /// 点击identity事件
    func deviceViewDidIdentifyActioin(view: DeviceForceResetDeviceView) {
        guard let device = self.device, let macAddress = device.macAddress else { return }
        
        // 发送identity无定向广播
        broadcaster.startBroadcasting(type: .identifyNode(key: randomKey, macAddress: macAddress), interval: 0.5)
        deviceState = .identifying
        
        self.delegate?.controller(self, deviceStateChanged: deviceState)
        updateUI()
        view.update(device: device, displayDeviceNamePrefix: self.displayDeviceNamePrefix, deviceGroup: self.deviceGroup, state: deviceState)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {[weak self] in
            guard let self = self, self.state == .discovered, self.deviceState == .identifying else { return }
            self.deviceState = .idenfityFinish
            view.update(device: device, displayDeviceNamePrefix: self.displayDeviceNamePrefix, deviceGroup: self.deviceGroup, state: self.deviceState)
            
            self.delegate?.controller(self, deviceStateChanged: deviceState)
            self.stopBroadcaster()
            // 继续发送查找设备广播
//            self.startBroadcaster()
            self.updateUI()
        }
        
    }
    
    /// 点击reset事件
    func deviceViewDidResetActioin(view: DeviceForceResetDeviceView) {
        guard let device = self.device, let macAddress = device.macAddress else { return }
        
        // 发送重置设备无定向广播
        broadcaster.startBroadcasting(type: .resetNode(key: randomKey, macAddress: macAddress), interval: 0.5)
        deviceState = .reseting
        updateUI()
        view.update(device: device, displayDeviceNamePrefix: self.displayDeviceNamePrefix, deviceGroup: self.deviceGroup, state: deviceState)
        
        self.delegate?.controller(self, deviceStateChanged: deviceState)
        state = .scaning
        // 开始搜索设备是否重置
        startScan(broadcaster: false)
        // 增加重置设备超时
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.deviceResetTimeout), object: nil)
            self.perform(#selector(self.deviceResetTimeout), with: nil, afterDelay: 10)
        }
    }
    
}
