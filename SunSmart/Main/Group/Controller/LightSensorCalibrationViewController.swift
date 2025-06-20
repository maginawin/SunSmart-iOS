//
//  LightSensorCalibrationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/29.
//

import UIKit
import NordicSigMeshSDK

class LightSensorCalibrationViewController: UIViewController {
    
    private var bottomView: UIView!
    private var calibrationBtn: UIButton!
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var sensorSelectView: LightSensorCalibrationSelectView!
    private var calibrationView: LightSensorCalibrationView!
    /// 配置中成功设备
    private var configurCompletedBtn: UIButton?
    /// 配置中失败设备
    private var configurFailedBtn: UIButton?
    
    private var selectSensor: Node?
    /// 是否停止配置
    private var stopConfig: Bool = false
    
    /// 最小设置的lux值
    var minimunLux: Int = 100
    
    let group: Group
    
    init(group: Group) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
        
        let profile = group.info.profile
        if profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight {
            // 75% * occupancyLux, 不小于100lx
            let data = profile.lightData.data
            var value = max(data.occupancyLevel, data.vacantLevel)
            if profile.type == .daylight {
                value = data.taskLevel
            }
            self.minimunLux = max(Int(Float(value) * 0.75), 100)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "calibration".localizedString
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
//        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: nil, action: #selector(moreAction))
        
        setupUI()
        
        group.ambientLightSensorNodes.forEach({ $0.selectState = .switchOff })
        
        // 传感器选中状态
        if let publishSensor = group.ambientLightSensorNodes.first(where: { $0.primaryUnicastAddress == group.info.ambientLightSensorNode?.primaryUnicastAddress }) {
            publishSensor.selectState = .switchOn
            selectSensor = publishSensor
        }
        sensorSelectView.daylightSensors = group.ambientLightSensorNodes
        
        // 组关灯
        MeshAPI.setGroupOnOffState(address: self.group.address.address, isOn: false)
        
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        // 禁用组内移动传感器上报
//        disablePresenceDetectedSensorPublish()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
    }
    
//    override func viewDidDisappear(_ animated: Bool) {
//        super.viewDidDisappear(animated)
//        
//        var messageHandles: [MeshMessageHandle] = []
//        // 恢复占用传感器是否有上报
//        let publishPresenceDetectedSensors = self.group.presenceDetectedSensorNodes.filter({ $0.presenceDetectedSensorModel?.publish?.publicationAddress != group.address })
//        
//        publishPresenceDetectedSensors.forEach({
//            let message = ConfigModelPublicationSet(Publish(to: group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: $0.presenceDetectedSensorModel!)!
//            let messageHandle = MeshMessageHandle(message: message, address: $0.primaryUnicastAddress)
//            messageHandles.append(messageHandle)
//        })
//        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles, finishedBack: nil)
//    }
    
    @objc private func backAction() {
        
        let loading = group.ambientLightSensorNodes.contains(where: { $0.selectState == .loading })
        
        if let sensor = selectSensor, !sensor.sensorCalibrated || sensor.ambientLightSensorModel?.publish == nil || loading {
            
            SRAlertView(title: "configuring".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: "calibration_exit_failed".localizedString, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "keep_calibrating".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), style: .cancel), SRAlertAction(title: "EXIT".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), actionHandler: {[weak self] _ in
                
                self?.navigationController?.popViewController(animated: true)
            })]).show()
            return
        }
        navigationController?.popViewController(animated: true)
    }
    
    @objc private func moreAction() {
        
        
        
    }
    
    @objc private func hideKeyboard() {
        view.endEditing(true)
    }
    
    /// 更新组光感传感器
    private func updateGroupLightSensor() {
        
        self.group.info.profile.adjustSpeed = self.calibrationView.adjustSpeed
        self.group.info.save()
        self.group.info.profile.save()
        
        NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: self.group)
    }
    
    /// 校准
    @objc private func calibrationBtnAction() {
        // 加载中
        
        guard !group.ambientLightSensorNodes.contains(where: { $0.selectState == .loading }),
              let sensor = self.selectSensor, let measuredLightLevel = calibrationView.measuredLightValue else {
            return
        }
        
        if measuredLightLevel < calibrationView.minimunValue || measuredLightLevel > calibrationView.maximunValue { // 输入测量值低于最小值、大于最大值
            calibrationView.verifyMeasuredValue()
            return
        }
        
        // 禁用组内移动传感器上报
//        disablePresenceDetectedSensorPublish()
        
        if sensor.sensorCalibrated, sensor.daylightCalibrationValue == UInt16(measuredLightLevel) {
            sensor.selectState = .loading
            self.sensorSelectView.reloadSensorCell(sensor: sensor)
            // 更新profile调节速率
            self.group.info.profile.adjustSpeed = self.calibrationView.adjustSpeed
            
            self.sensorEnabled(sensor: sensor) {[weak self] result in
                guard let self = self else { return }
                sensor.selectState = result ? .switchOn : .switchOff
                self.sensorSelectView.reloadSensorCell(sensor: sensor)
                //                    MeshAPI.sendMessage(message: ConfigRelaySet(count: 0, steps: 1), address: sensor.primaryUnicastAddress)
                if result {
                    self.selectSensor = sensor
                    // 切换选中的传感器，更新缓存
                    self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
                    self.calibrationView.measuredLightValue = nil
                    self.updateGroupLightSensor()
                    self.updateCalibrationState()
                    if self.group.nodes.filter({ $0.getNodeSyncProfiles().count > 0 }).isEmpty {
                        XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    }
                }
            }
            return
        }
        
        
//        SRAlertView(title: "daylight_sensor".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: "calibrating".localizedString, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 14, weight: .light), tapBackgroundHide: false, contentPadding: SCRXFrom(14), contentMinHeight: SCRYFrom(114)).show()
//        
//        MeshAPI.sendMessage(message: SunricherVendorSet(function: .daylightCalibrate(UInt16(measuredLightLevel))), model: sensor.sunricherVendorModel!) {[weak self] response in
//            if let vendorStatus = response as? SunricherVendorStatus, vendorStatus.status.isSuccessful {
//                
//                guard let self = self else { return }
//                SRAlertView.hide()
//                sensor.selectState = .loading
//                self.sensorSelectView.reloadSensorCell(sensor: sensor)
//                // 更新profile调节速率
//                self.group.info.profile.adjustSpeed = self.calibrationView.adjustSpeed
//
//                // 通知space数据修改
//                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//                
//                DispatchQueue.main.async {
//                    self.sensorEnabled(sensor: sensor) {[weak self] result in
//                        guard let self = self else { return }
//                        sensor.selectState = result ? .switchOn : .switchOff
//                        self.sensorSelectView.reloadSensorCell(sensor: sensor)
//    //                    MeshAPI.sendMessage(message: ConfigRelaySet(count: 0, steps: 1), address: sensor.primaryUnicastAddress)
//                        if result {
//                            self.selectSensor = sensor
//                            // 切换选中的传感器，更新缓存
//                            self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
//                            self.calibrationView.measuredLightValue = nil
//                            self.updateGroupLightSensor()
//                            self.updateCalibrationState()
//                        }
//                    }
//                }
//                
//            }else {
//                self?.showCalibrationFailed(message: "calibrating_failure".localizedString)
//            }
//        }
//        return
        
        showConnecting()
        MeshSensorCalibrateServer.shared.calibrate(node: sensor, measuredValue: UInt16(measuredLightLevel)) { step in
            
            switch step {
            case .calibrating, .stabilityChecking:
                SRAlertView.getCurrentAlertView()?.messageLabel.text = "calibrating".localizedString
            case .lightsChecking:
                SRAlertView.getCurrentAlertView()?.messageLabel.text = "checking_correct".localizedString
            default:
                break
            }
            
        } successful: {[weak self] _ in
            guard let self = self else { return }
            SRAlertView.hide()
            sensor.selectState = .loading
            self.sensorSelectView.reloadSensorCell(sensor: sensor)
            // 切换选中的光照传感器
//            self.group.info.ambientLightSensorNode = sensor
            // 更新profile调节速率
            self.group.info.profile.adjustSpeed = self.calibrationView.adjustSpeed
//            if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
//                sensor.saveNodeInfo(meshUUID: uuid, networkKey: MeshNetworkManager.instance.currentNetworkKey)
//            }
//            self.updateGroupLightSensor()
            
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            
            DispatchQueue.main.async {
                self.sensorEnabled(sensor: sensor) {[weak self] result in
                    guard let self = self else { return }
                    sensor.selectState = result ? .switchOn : .switchOff
                    self.sensorSelectView.reloadSensorCell(sensor: sensor)
//                    MeshAPI.sendMessage(message: ConfigRelaySet(count: 0, steps: 1), address: sensor.primaryUnicastAddress)
                    if result {
                        self.selectSensor = sensor
                        // 切换选中的传感器，更新缓存
                        self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
                        self.calibrationView.measuredLightValue = nil
                        self.updateGroupLightSensor()
                        self.updateCalibrationState()
                    }
                }
            }
            
        } failed: {[weak self] _, error in
            guard let self = self  else { return  }
            switch error {
            case .deviceNotsupport, .connectTimeout, .disconnect, .noResponse:
                self.showConnectFailed()
            case .ambientInstability(let minLux, let maxLux):
                self.showCalibrationFailed(message: "calibrating_failure".localizedString) //  + "min: \(minLux) max:\(maxLux)"
            case .lightNoEffect:
                self.showCalibrationFailed(message: "checking_correct_failure".localizedString)
            }
        }
        
    }
    
    /// 开始配置
    private func configuring(lightNodes: [Node]) {
        
        // 判断哪些需要设置的灯
        let setLightNodes = lightNodes.filter({ $0.getNodeSyncProfiles().count > 0 })
        if setLightNodes.isEmpty {
            SRAlertView.hide()
            return
        }
        
        self.stopConfig = false
        
        self.showConfiguring()
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            
            var successNodes: [Node] = []
            var failedNodes: [Node] = []
            
            for node in setLightNodes {
                
                var messageHandles: [MeshMessageHandle] = []
                let profiles = node.getNodeSyncProfiles()
                profiles.forEach({ profileType in
                    messageHandles.append(contentsOf: profileType.getMessageHandles(node: node))
                })
                MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles) {[weak self] resultHandles in
                    if resultHandles.contains(where: { !$0.isSuccessful }) {
                        failedNodes.append(node)
                    }else {
                        successNodes.append(node)
                    }
                    DispatchQueue.main.async {
                        self?.updateConfiguringProgress(total: setLightNodes.count, successCount: successNodes.count, failedCount: failedNodes.count)
                    }
//                    if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
//                        node.saveNodeProfile(meshUUID: uuid, networkKey: MeshNetworkManager.instance.currentNetworkKey)
//                    }
                    semaphore.signal()
                }
                if self.stopConfig { // 停止配置
                    // 中断的设备都算失败
                    let breakNodes = setLightNodes.filter({ !successNodes.contains($0) && !failedNodes.contains($0) })
                    failedNodes.append(contentsOf: breakNodes)
                    break
                }else {
                    semaphore.wait()
                }
            }
          
            DispatchQueue.main.async {
                // 通知space数据修改
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                if failedNodes.count > 0 {
                    self.showCheckingCorrectFailure(total: successNodes.count + failedNodes.count, successCount: successNodes.count, failedNodes: failedNodes)
                }else {
                    SRAlertView.hide()
                }
            }
        }
    }
    /// 取消配置
    private func stepConfiguring() {
        stopConfig = true
        MeshProxyMessageCommand.shared.stopSendMessage(finishedBack: nil)
//        MeshSensorCalibrateServer.shared.stopAdjustSpeedConfigured {[weak self] successNodes, failedNodes in
//            self?.showCheckingCorrectFailure(total: successNodes.count + failedNodes.count, successCount: successNodes.count, failedNodes: failedNodes)
//        }
    }
    
    /// 显示连接中弹窗
    private func showConnecting() {
        SRAlertView(title: "daylight_sensor".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: "connecting".localizedString, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 14, weight: .light), tapBackgroundHide: false, contentPadding: SCRXFrom(14), contentMinHeight: SCRYFrom(114)).show()
    }
    
    /// 显示连接失败弹窗
    private func showConnectFailed() {
        SRAlertView(title: "daylight_sensor".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: "connection_failure".localizedString, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "CLOSE".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light))]).show()
    }
    
    /// 显示校准失败弹窗
    private func showCalibrationFailed(message: String) {
        SRAlertView(title: "daylight_sensor".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: message, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "cancel".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), style: .cancel), SRAlertAction(title: "RETRY".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), actionHandler: {[weak self] _ in
            self?.calibrationBtnAction()
        })]).show()
    }
    
    /// 展示配置中弹窗
    private func showConfiguring() {
        
        let alertView = SRAlertView(title: "configuring".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: "\n\n\n\n", backgroundColor: RGB(247, 247, 247), contentMinHeight: SCRYFrom(220), btnText: "STOP".localizedString, btnTextColor: Red_Color, btnTextFont: UIFont.systemFont(ofSize: 14, weight: .light), btnBackgroundColor: .white, btnBorderWidth: 0.5) {[weak self] in
            SRAlertView.hide()
            // 取消配置
            self?.stepConfiguring()
        }
        alertView.progressView.isHidden = false
        alertView.progressLabel.isHidden = false
        alertView.progressLabel.text = "0%"
        alertView.progressView.snp.updateConstraints { make in
            make.top.equalTo(alertView.titleLabel.snp.bottom).offset(SCRYFrom(29))
            make.left.equalTo(SCRXFrom(26))
            make.right.equalTo(SCRXFrom(-26))
        }
        alertView.firstBtn.snp.remakeConstraints { make in
        }
        alertView.secondBtn.snp.remakeConstraints { make in
        }
        alertView.bottomBtn.snp.remakeConstraints { make in
            make.top.equalTo(alertView.progressView.snp.bottom).offset(SCRYFrom(47))
            make.width.equalTo(SCRXFrom(140))
            make.height.equalTo(SCRYFrom(32))
            make.centerX.equalToSuperview()
        }
        
        let completedBtn = UIButton(title: "\("completed:".localizedString) 0", titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "calibration_completed_num")
        completedBtn.setImagePosition(position: .left, spacing: SCRXFrom(6))
        completedBtn.isUserInteractionEnabled = false
        alertView.contentView.addSubview(completedBtn)
        completedBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(22))
            make.bottom.equalTo(SCRYFrom(-25))
        }
        
        self.configurCompletedBtn = completedBtn
        
        let failedBtn = UIButton(title: "\("failed:".localizedString) 0", titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "calibration_failed_num")
        failedBtn.setImagePosition(position: .left, spacing: SCRXFrom(6))
        failedBtn.isUserInteractionEnabled = false
        alertView.contentView.addSubview(failedBtn)
        failedBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-28))
            make.bottom.equalTo(completedBtn)
        }
        self.configurFailedBtn = failedBtn
        
        alertView.show()
        
    }
    
    /// 更新进度
    private func updateConfiguringProgress(total: Int, successCount: Int, failedCount: Int) {
        
        let progress = Float(successCount + failedCount) / Float(total) * 100.0
        SRAlertView.getCurrentAlertView()?.setProgress(Int(progress))
        self.configurCompletedBtn?.setTitle("\("completed:".localizedString) \(successCount)", for: .normal)
        self.configurFailedBtn?.setTitle("\("failed:".localizedString) \(failedCount)", for: .normal)
    }
    
    
    /// 显示配置失败弹窗
    /// - Parameters:
    ///   - total: 配置设备总数
    ///   - successCount: 成功数量
    private func showCheckingCorrectFailure(total: Int, successCount: Int, failedNodes: [Node]) {
        SRAlertView(title: "configuring".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: String(format: "calibration_configuring_failed".localizedString, successCount, total, total - successCount), messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "cancel".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), style: .cancel), SRAlertAction(title: "RETRY".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), actionHandler: {[weak self] _ in
            
            self?.configuring(lightNodes: failedNodes)
        })]).show()
    }
    
    private func updateCalibrationState() {
        
        if calibrationView.measuredLightValue != nil, selectSensor != nil {
            calibrationBtn.isEnabled = true
        }else {
            calibrationBtn.isEnabled = false
        }
        
    }
    
    /// 传感器启用
    private func sensorEnabled(sensor: Node, result: ((Bool)->Void)?) {
        
        guard let ambientLightSensorModel = sensor.ambientLightSensorModel else {
            result?(false)
            return
        }
        // 判断传感器是否已启用
        if ambientLightSensorModel.publish?.publicationAddress == self.group.address {
            result?(true)
            self.configuring(lightNodes: self.group.nodes)
            return
        }
        
        
        let publishMessage = ConfigModelPublicationSet(Publish(to: self.group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: .disabled), to: ambientLightSensorModel)!
        
        MeshProxyMessageCommand.shared.addMessage(messageHandles: [MeshMessageHandle(message: publishMessage, address: sensor.primaryUnicastAddress)]) {[weak self] resultHandles in
            guard let self = self else { return }
            if let handle = resultHandles.first, handle.isSuccessful {
                
                // 启用传感器，更新缓存
                self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
                self.updateGroupLightSensor()
                
                result?(true)
                self.configuring(lightNodes: self.group.nodes)
            }else {
                result?(false)
            }
        }
    }

    /// 传感器禁用
    private func sensorDisable(sensor: Node, lightConfig: Bool = true, result: ((Bool)->Void)?) {
        
        guard let ambientLightSensorModel = sensor.ambientLightSensorModel else {
            result?(false)
            return
        }
        
        let disableMessage = ConfigModelPublicationSet(disablePublicationFor: ambientLightSensorModel)!
        
        var messageHandles: [MeshMessageHandle] = []
        messageHandles.append(MeshMessageHandle(message: disableMessage, address: sensor.primaryUnicastAddress))
        // 灯光光照补偿最小亮度值
//        let profileAutoMinLevel = group.info.profile.lightData.data.autoMinLevel
//        let profile = group.info.profile
//        var lightNodes: [Node] = []
//        // 光感+占用模式
//        if profile.type == .occupancy_daylight || profile.type == .vacancy_daylight {
//            let lightnessOn = Node.getLightness(lightness100: 100)
//            let lightnessProlong = Node.getLightness(lightness100: 50)
//            // 获取需要设置占用、限制阶段亮度百分比，校准后则使用光照补偿禁用百分比
//            lightNodes = group.nodes.filter({
//                $0.lightLCSetupModel != nil && ($0.lightLCProperty.lightnessOn ?? 0 != lightnessOn || $0.lightLCProperty.lightnessProlong ?? 0 != lightnessProlong)
//            })
//            lightNodes.forEach({
//                if $0.lightLCProperty.lightnessOn ?? 0 != lightnessOn {
//                    messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlLightnessOn, value: .perceivedLightness(lightnessOn)), model: $0.lightLCSetupModel!))
//                }
//                if $0.lightLCProperty.lightnessProlong ?? 0 != lightnessProlong {
//                    messageHandles.append(MeshMessageHandle(message: LightLCPropertySet(of: .lightControlLightnessProlong, value: .perceivedLightness(lightnessProlong)), model: $0.lightLCSetupModel!))
//                }
//            })
//        }
        
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles) {[weak self] resultHandles in
            guard let self = self else { return }
            if let handle = resultHandles.first, handle.isSuccessful {
                
                // 禁用传感器，更新缓存
                self.group.info.ambientLightSensorNodeAddress = nil
                self.updateGroupLightSensor()
                
                result?(handle.isSuccessful)
                if lightConfig {
                    self.configuring(lightNodes: self.group.nodes)
                }
            }else {
                result?(false)
            }
        }
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }
        
        calibrationBtn = UIButton(title: "CALIBRATION".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Done_Color, target: self, action: #selector(calibrationBtnAction))
        calibrationBtn.setTitleColor(RGB(148, 163, 184), for: .disabled)
        calibrationBtn.isEnabled = false
        bottomView.addSubview(calibrationBtn)
        calibrationBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        scrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        contentView = UIView()
        contentView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        sensorSelectView = LightSensorCalibrationSelectView()
        sensorSelectView.delegate = self
        contentView.addSubview(sensorSelectView)
        sensorSelectView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.height.greaterThanOrEqualTo(SCRYFrom(86))
        }
        
        calibrationView = LightSensorCalibrationView()
        let profileData = group.info.profile.lightData.data
        calibrationView.limitRange = profileData.lowEndTrim...profileData.highEndTrim
        calibrationView.speedSlider.value = Float(group.info.profile.adjustSpeed)
        calibrationView.delegate = self
        calibrationView.minimunValue = minimunLux
        contentView.addSubview(calibrationView)
        calibrationView.snp.makeConstraints { make in
            make.left.right.equalTo(sensorSelectView)
            make.top.equalTo(sensorSelectView.snp.bottom).offset(SCRYFrom(16))
            make.height.greaterThanOrEqualTo(SCRYFrom(178))
            make.bottom.equalToSuperview()
        }
        
    }
   

}

extension Node {
    /// 传感器选择状态
    enum DaylightSelectState {
        /// 已选择
        case switchOn
        /// 未选择
        case switchOff
        /// 切换中
        case loading
    }
    static var selectStateKey = 1
    
    var selectState: DaylightSelectState {
        get {
            objc_getAssociatedObject(self, &Node.selectStateKey) as? DaylightSelectState ?? .switchOff
        }set {
            objc_setAssociatedObject(self, &Node.selectStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}

extension LightSensorCalibrationViewController: LightSensorCalibrationSelectViewDelegate {
    
    /// 设备identify
    func view(_ view: LightSensorCalibrationSelectView, identify sensor: Node) {
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        MeshAPI.identify(address: sensor.primaryUnicastAddress)
//        if let healthModel = sensor.healthModel {
//            MeshAPI.sendMessage(message: AttentionSetUnacknowledged(attentionTimer: 5), model: healthModel)
//        }
    }
    
    /// 选择传感器回调
    /// - Parameters:
    ///   - view: self
    ///   - selectSensor: 选中的传感器
    ///   - lastSelectSensor: 上一个选中的传感器
    func view(_ view: LightSensorCalibrationSelectView, didSelectDaylightSensor selectSensor: Node, lastSelectSensor: Node?) {
        
        view.endEditing(true)
        if group.ambientLightSensorNodes.contains(where: { $0.selectState == .loading }) {
            return
        }
        
        var lastSelectSensorUnPublish: Bool = false
        var selectSensorPublish: Bool = false
        
        if lastSelectSensor != nil { // 关闭上一个光照传感器上报
            if let sensorModel = lastSelectSensor!.ambientLightSensorModel, sensorModel.publish?.publicationAddress == group.address {
                lastSelectSensorUnPublish = true
            }
        }
        
        if selectSensor.sensorCalibrated { // 是否校准
            selectSensorPublish = true
        }
        
        if let sensor = lastSelectSensor {
            if lastSelectSensorUnPublish {
                sensor.selectState = .loading
            }else {
                sensor.selectState = .switchOff
            }
            view.reloadSensorCell(sensor: sensor)
        }
        if selectSensorPublish {
            selectSensor.selectState = .loading
        }else {
            selectSensor.selectState = .switchOn
            self.selectSensor = selectSensor
            self.updateCalibrationState()
        }
    
        view.reloadSensorCell(sensor: selectSensor)
        
        DispatchQueue.global().async {
            let semaphore = DispatchSemaphore(value: 0)
            if lastSelectSensorUnPublish, let sensor = lastSelectSensor {
                self.sensorDisable(sensor: sensor, lightConfig: !selectSensorPublish) {[weak self] result in
                    DispatchQueue.main.async {
                        sensor.selectState = result ? .switchOff : .switchOn
                        view.reloadSensorCell(sensor: sensor)
                        if result {
                            if self?.selectSensor == sensor {
                                self?.selectSensor = nil
                            }
                            self?.group.info.ambientLightSensorNodeAddress = nil
                            self?.updateGroupLightSensor()
                            // 通知space数据修改
                            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
            if selectSensorPublish {
                self.sensorEnabled(sensor: selectSensor) {[weak self] result in
                    DispatchQueue.main.async {
                        selectSensor.selectState = result ? .switchOn : .switchOff
                        view.reloadSensorCell(sensor: selectSensor)
                        if result {
                            self?.selectSensor = selectSensor
                            self?.calibrationView.measuredLightValue = nil
                            // 通知space数据修改
                            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
            DispatchQueue.main.async {
                self.updateCalibrationState()
            }
        }
        
    }
    
    /// 取消选择传感器回调
    /// - Parameters:
    ///   - view: self
    ///   - selectSensor: 取消选中的传感器
    func view(_ view: LightSensorCalibrationSelectView, didDeselectDaylightSensor sensor: Node) {
        
        if sensor.ambientLightSensorModel?.publish?.publicationAddress == group.address { // 是否设置上报
            sensor.selectState = .loading
            view.reloadSensorCell(sensor: sensor)
            self.sensorDisable(sensor: sensor) {[weak self] result in
                DispatchQueue.main.async {
                    sensor.selectState = result ? .switchOff : .switchOn
                    view.reloadSensorCell(sensor: sensor)
                    if result {
                        self?.selectSensor = nil
//                        self?.group.info.ambientLightSensorNode = nil
//                        self?.updateGroupLightSensor()
                        self?.updateCalibrationState()
                        // 通知space数据修改
                        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                    }
                }
            }
        }else {
            sensor.selectState = .switchOff
            self.selectSensor = nil
            view.reloadSensorCell(sensor: sensor)
            updateCalibrationState()
        }
           
    }
    
    /// 点击帮助回调
    func sensorViewClickHelpAction(_ view: LightSensorCalibrationSelectView) {
        navigationController?.pushViewController(DaylightSensorInstructionsController(), animated: true)
    }
 
}

extension LightSensorCalibrationViewController: UIScrollViewDelegate {
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }
}

extension LightSensorCalibrationViewController: LightSensorCalibrationViewDelegate {
   
    /// 输入测量值回调
    /// - Parameters:
    ///   - view: view
    ///   - lux: 测量值 为空则未输入
    func view(_ view: LightSensorCalibrationView, measuredLightValueEditing lux: Int?) {
        updateCalibrationState()
    }
    
    /// 点击校准帮助
    func calibrationViewHelpAction(_ view: LightSensorCalibrationView) {
        navigationController?.pushViewController(CalibrationInstructionController(), animated: true)
    }
    
    /// 亮度修改回调
    /// - Parameters:
    ///   - view: view
    ///   - level: 0~100
    func view(_ view: LightSensorCalibrationView, lightLevelValueChanged level: Int) {
        
        MeshAPI.setGroupLightnessState(address: group.address.address, lightness: Node.getLightness(lightness100: level))
    }
    
    /// 调节速率修改回调
    /// - Parameters:
    ///   - view: view
    ///   - speed: 0~100
    func view(_ view: LightSensorCalibrationView, adjustSpeedChanged speed: Int) {
        
    }
    
    /// 点击调整速率帮助
    func calibrationViewAdjustSpeedHelpAction(_ view: LightSensorCalibrationView) {
        navigationController?.pushViewController(AdjustSpeedInstructionController(), animated: true)
    }
    
    
    
}
