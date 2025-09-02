//
//  DeviceForceResetDeviceController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/14.
//

import UIKit
import NordicSigMeshSDK

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
    
    /// 无定向广播
    private let broadcaster = BluetoothBroadcaster()
    /// 当前无定向广播随机key
    private var randomKey: UInt16 = 0
    
    weak var delegate: DeviceForceResetDeviceControllerDelegate?
    
    /// 广播时设备配置持续时长
    private let broadcasterDuration: UInt8 = 1
    /// 广播时光感上报阈值
//    private let lightSensorDelta: UInt16 = 80
    
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
        MeshLibManager.manager.scanDevice(withServices: [MeshProvisioningService.uuid, MeshProxyService.uuid]) {[weak self] peripheral, advertisementData, rssi in
            guard let self = self,
                  let provisioningDevice = ProvisioningDevice(peripheral: peripheral, advertisementData: advertisementData, rssi: rssi),
                  provisioningDevice.macAddress != nil else { return }
            
            if let currentDevice = self.device, currentDevice.peripheral.identifier == provisioningDevice.peripheral.identifier, provisioningDevice.networkId == nil { // 删除设备成功
                self.deviceResetSuccess()

            }else if provisioningDevice.networkId != nil { // 只显示已入网设备
                if self.device != nil {
                    return
                }
                if (self.resetMode == .flashlight && provisioningDevice.triggerActionTypes.contains(.lightSensing)) || (self.resetMode == .motion && provisioningDevice.triggerActionTypes.contains(.motionSensing)) {
                    
                    if let node = MeshNetworkManager.instance.meshNetwork?.nodes.first(where: { $0.macAddress == provisioningDevice.macAddress }) {
                        
                        provisioningDevice.deviceName = node.name
                        provisioningDevice.icon = node.iconName
                        
                    }else if let info = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.companyId == provisioningDevice.cid && $0.productId == provisioningDevice.pid }) {
                        provisioningDevice.deviceName = info.categoryName
                        provisioningDevice.icon = "device_\(info.iconCategory)"
                    }
                    
                    self.device = provisioningDevice
                    self.state = .discovered
                    self.updateUI()
                    self.deviceView.update(device: provisioningDevice, state: .none)
                    // 找到一个设备后停止扫描
                    self.stopScan()
                    
                    self.delegate?.controller(self, deviceDiscovered: provisioningDevice)
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
            broadcaster.startBroadcasting(type: .ambientLightDiscoverReset(timeout: broadcasterDuration, key: randomKey, delta: deviceSettingsParameterData.illuminationDelta))
        }else if resetMode == .motion {
            broadcaster.startBroadcasting(type: .pirDiscoverReset(timeout: broadcasterDuration, key: randomKey))
        }
    }
    
    /// 停止无定向广播
    private func stopBroadcaster() {
        broadcaster.stopBroadcasting()
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
        updateUI()
        if let device = self.device {
            delegate?.controller(self, deviceResetFinish: device)
        }
        device = nil
    }
    
    /// 重置设备超时
    @objc private func deviceResetTimeout() {
        guard let device = self.device, state == .discovered, deviceState == .reseting else { return }
        deviceState = .idenfityFinish
        deviceView.update(device: device, state: deviceState)
        XWHUDManager.showErrorTipHUD("reset_failed".localizedString)
        
        broadcaster.stopBroadcasting()
        
        self.delegate?.controller(self, deviceStateChanged: deviceState)
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
            
            bottomBtn.setTitle("RESELECT".localizedString, for: .normal)
            if deviceState == .identifying || deviceState == .reseting {
                bottomBtn.isEnabled = false
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
            make.left.equalTo(SCRXFrom(isIPad ? 100 : 45))
            make.right.equalTo(SCRXFrom(isIPad ? -100 : -23))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(17))
//            make.centerX.equalToSuperview().offset(SCRXFrom(15))
            make.height.equalTo(imageView.snp.width).multipliedBy(170 / 275.0)
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
        
    }
    
}

extension DeviceForceResetDeviceController: DeviceForceResetDeviceViewDelegate {
    
    /// 点击identity事件
    func deviceViewDidIdentifyActioin(view: DeviceForceResetDeviceView) {
        guard let device = self.device, let macAddress = device.macAddress else { return }
        
        // 发送identity无定向广播
        broadcaster.startBroadcasting(type: .identifyNode(key: randomKey, macAddress: macAddress))
        deviceState = .identifying
        
        self.delegate?.controller(self, deviceStateChanged: deviceState)
        updateUI()
        view.update(device: device, state: deviceState)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {[weak self] in
            guard let self = self, self.state == .discovered, self.deviceState == .identifying else { return }
            self.deviceState = .idenfityFinish
            view.update(device: device, state: self.deviceState)
            
            self.delegate?.controller(self, deviceStateChanged: deviceState)
            // 继续发送查找设备广播
            self.startBroadcaster()
            self.updateUI()
        }
        
    }
    
    /// 点击reset事件
    func deviceViewDidResetActioin(view: DeviceForceResetDeviceView) {
        guard let device = self.device, let macAddress = device.macAddress else { return }
        
        // 发送重置设备无定向广播
        broadcaster.startBroadcasting(type: .resetNode(key: randomKey, macAddress: macAddress))
        deviceState = .reseting
        updateUI()
        view.update(device: device, state: deviceState)
        
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
