//
//  LightSensorCalibrationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/29.
//

import UIKit
import NordicSigMeshSDK

class LightSensorCalibrationViewController: UIViewController {

    private enum LuxPollingSuspensionReason: Hashable {
        case calibration
        case configuration
        case sensorSwitching
    }

    private struct NightCalibrationSnapshot {
        let selectedSensorCalibrationData: DaylightSensorCalibrationData?
        let selectedSensorPublish: Publish?
        let groupSensor: Node?
        let groupSensorPublish: Publish?
    }
    
    private var bottomView: UIView!
    private var calibrationBtn: UIButton!
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var sensorSelectView: LightSensorCalibrationSelectView!
    private var calibrationModeView: LightSensorCalibrationModeView!
    private var calibrationAboutView: LightSensorCalibrationAboutView!
//    private var calibrationView: LightSensorCalibrationView!
    private var onPointLuxView: LightSensorCalibrationPointLuxView!
    private var offPointLuxView: LightSensorCalibrationPointLuxView!
    private var targetNightBrightnessView: LightSensorTargetNightBrightnessView!
    private var nightCalibrationCompleteView: LightSensorNightCalibrationCompleteView!
    private var manualCorrectionBtn: UIButton!
    private var isNightRecalibrationDraft = false
    
    /// 配置中成功设备
    private var configurCompletedBtn: UIButton?
    /// 配置中失败设备
    private var configurFailedBtn: UIButton?
    
    private var selectSensor: Node? {
        didSet {
            guard isViewLoaded else { return }
            updateLuxPollingState()
        }
    }
    private let luxPollingInterval: TimeInterval = 1
    private var luxPollingTimer: Timer?
    private var luxPollingSensorAddress: Address?
    private var luxPollingSuspensionReasons: Set<LuxPollingSuspensionReason> = []
    private var isViewVisible = false
    /// 是否停止配置
    private var stopConfig: Bool = false
    /// 手动调节校准view
    private weak var manualCorrectionView: LightSensorManualCorrectionView?
    
    /// 最小设置的lux值
    var minimunLux: Int = 100
    
    /// 设备闪烁方式
    private var deviceBlinkMode: DeviceBlinkMode = .none
    
    let group: Group
    
    init(group: Group) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
        
        let profile = group.info.profile
        if profile.type == .occupancy_daylight || profile.type == .vacancy_daylight || profile.type == .daylight {
            // 75% * occupancyLux, 不小于100lx
            let data = profile.lightControlData
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
        
        self.isModalInPresentation = true
        
        deviceBlinkMode = SpaceViewController.currentDeviceBlinkMode
        
        setupUI()
        
        group.ambientLightSensorNodes.forEach({ $0.selectState = .switchOff })
        
        // 传感器选中状态
        if let publishSensor = group.ambientLightSensorNodes.first(where: { $0.primaryUnicastAddress == group.info.ambientLightSensorNode?.primaryUnicastAddress }) {
            publishSensor.selectState = .switchOn
            selectSensor = publishSensor
        }
        sensorSelectView.daylightSensors = group.ambientLightSensorNodes
        updateActiveCalibrationMode()
        let initialMode = lightSensorMode(for: effectiveActiveCalibrationMode) ?? .plane
        calibrationModeView.setSelectedMode(initialMode, notify: true)
        updateManualCorrectionBtn()
        // 组关灯
//        MeshAPI.setGroupOnOffState(address: self.group.address.address, isOn: false)
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        isViewVisible = true
        MeshLibManager.manager.messageDelegate = self
        updateLuxPollingState()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.scrollView.firstShowFlashScrollIndicators {
            self.scrollView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isViewVisible = false
        stopLuxPolling()
        if let sensor = selectSensor {
            sensorSelectView.updateLux(sensor: sensor, isFresh: false)
        }
        NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
    }

    deinit {
        stopLuxPolling()
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
        
        let requiresPlaneExitConfirmation = calibrationModeView.selectedMode == .plane && {
            guard let sensor = selectSensor else { return false }
            return !sensor.sensorCalibrated || sensor.ambientLightSensorModel?.publish == nil
        }()
        if requiresPlaneExitConfirmation || loading {
            
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

    private func setLuxPollingSuspended(_ suspended: Bool, for reason: LuxPollingSuspensionReason) {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.setLuxPollingSuspended(suspended, for: reason)
            }
            return
        }

        if suspended {
            luxPollingSuspensionReasons.insert(reason)
        }else {
            luxPollingSuspensionReasons.remove(reason)
        }
        updateLuxPollingState()
    }

    private func updateLuxPollingState() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in
                self?.updateLuxPollingState()
            }
            return
        }

        guard isViewVisible,
              luxPollingSuspensionReasons.isEmpty,
              let sensor = selectSensor,
              sensor.selectState == .switchOn,
              sensor.ambientLightSensorModel != nil else {
            stopLuxPolling()
            if let sensor = selectSensor {
                sensorSelectView.updateLux(sensor: sensor, isFresh: false)
            }
            return
        }

        guard luxPollingSensorAddress != sensor.primaryUnicastAddress || luxPollingTimer == nil else {
            return
        }

        stopLuxPolling()
        luxPollingSensorAddress = sensor.primaryUnicastAddress
        sensorSelectView.updateLux(sensor: sensor, isFresh: false)
        requestSelectedSensorLux()

        luxPollingTimer = LCWeakTimer.scheduledTimer(timeInterval: luxPollingInterval, aTarget: self, selector: #selector(luxPollingTimerAction), userInfo: nil, repeats: true)
        RunLoop.main.add(luxPollingTimer!, forMode: .common)
    }

    private func stopLuxPolling() {
        luxPollingTimer?.invalidate()
        luxPollingTimer = nil
        luxPollingSensorAddress = nil
    }

    @objc private func luxPollingTimerAction() {
        requestSelectedSensorLux()
    }

    private func requestSelectedSensorLux() {
        guard isViewVisible,
              luxPollingSuspensionReasons.isEmpty,
              MeshLibManager.manager.isMeshNetworkConnected,
              let sensor = selectSensor,
              sensor.selectState == .switchOn,
              sensor.primaryUnicastAddress == luxPollingSensorAddress else {
            return
        }
        MeshAPI.getAmbientSensorValue(node: sensor, result: nil)
    }
    
    /// 更新组光感传感器
    private func updateGroupLightSensor() {
        
        self.group.info.save()
        self.group.updateGroupSyncState()
        
        NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: self.group)

        if Thread.isMainThread {
            updateActiveCalibrationMode()
        }else {
            DispatchQueue.main.async { [weak self] in
                self?.updateActiveCalibrationMode()
            }
        }
    }

    private func updateActiveCalibrationMode() {
        calibrationModeView.updateActiveMode(lightSensorMode(for: effectiveActiveCalibrationMode))
    }

    private var effectiveActiveCalibrationMode: Profile.DaylightCalibrationMode {
        group.info.profile.effectiveCalibrationMode(
            sensorCalibrated: group.info.ambientLightSensorNode?.sensorCalibrated == true
        )
    }

    private func lightSensorMode(for mode: Profile.DaylightCalibrationMode) -> LightSensorCalibrationMode? {
        switch mode {
        case .none:
            return nil
        case .nightCal:
            return .night
        case .sensorCal:
            return .sensor
        case .planeCal:
            return .plane
        }
    }

    private var isNightCalibrationComplete: Bool {
        effectiveActiveCalibrationMode == .nightCal && !isNightRecalibrationDraft
    }

    private var targetNightBrightnessRange: ClosedRange<Int> {
        let lightControlData = group.info.profile.lightControlData
        let lowerBound = max(1, lightControlData.lowEndTrim)
        let upperBound = max(lowerBound, lightControlData.highEndTrim)
        return lowerBound...upperBound
    }

    private func updateCalibrationModeUI(_ mode: LightSensorCalibrationMode) {
        if mode == .plane {
            restorePersistedSensorSelectionForPlane()
        }
        let showsPlaneContent = mode != .night
        onPointLuxView.isHidden = !showsPlaneContent
        offPointLuxView.isHidden = !showsPlaneContent

        let nightComplete = mode == .night && isNightCalibrationComplete
        targetNightBrightnessView.isHidden = mode != .night || nightComplete
        nightCalibrationCompleteView.isHidden = !nightComplete

        if mode == .night {
            calibrationBtn.setTitle("apply_night_calibration".localizedString, for: .normal)
            targetNightBrightnessView.allowedRange = targetNightBrightnessRange
            targetNightBrightnessView.value = Profile.normalizedTargetNightBrightness(group.info.profile.targetNightBrightness)
            let targetLux = group.info.profile.type == .daylight
                ? group.info.profile.lightControlData.taskLevel
                : group.info.profile.lightControlData.occupancyLevel
            nightCalibrationCompleteView.update(
                targetLux: targetLux,
                targetBrightness: Profile.normalizedTargetNightBrightness(group.info.profile.targetNightBrightness),
                pendingDeviceCount: group.nodes.filter { !$0.getNodeSyncProfiles().isEmpty }.count
            )
        } else {
            calibrationBtn.setTitle("CALIBRATION".localizedString, for: .normal)
        }
        updateManualCorrectionBtn()
        updateCalibrationState()
    }

    private func restorePersistedSensorSelectionForPlane() {
        let persistedSensor = group.info.ambientLightSensorNode
        guard persistedSensor?.primaryUnicastAddress != selectSensor?.primaryUnicastAddress else {
            return
        }
        group.ambientLightSensorNodes.forEach { sensor in
            sensor.selectState = sensor.primaryUnicastAddress == persistedSensor?.primaryUnicastAddress
                ? .switchOn
                : .switchOff
            sensorSelectView.reloadSensorCell(sensor: sensor)
        }
        selectSensor = persistedSensor
    }

    private func recalibrateNight() {
        isNightRecalibrationDraft = true
        updateCalibrationModeUI(.night)
    }
    
    private var shouldRestoreAutoAfterDaylightCalibration: Bool {
        let type = group.info.profile.type
        return type == .occupancy_daylight || type == .vacancy_daylight || type == .daylight
    }
    
    private func restoreGroupAutoAfterDaylightCalibration() {
        guard shouldRestoreAutoAfterDaylightCalibration else { return }
        MeshAPI.sendMessage(
            message: LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0),
            address: group.address.address
        )
    }
    
    /// 更新修改校准按钮
    private func updateManualCorrectionBtn() {
        self.manualCorrectionBtn.isHidden = calibrationModeView.selectedMode != .plane || !(selectSensor?.sensorCalibrationData?.isCalibration ?? false)
    }
    
    /// 修改校准倍率
    @objc private func manualCorrectionBtnAction() {
        guard let sensor = selectSensor, let calibrationData = sensor.sensorCalibrationData, let lastSensorRatio = calibrationData.sensorRatio, let lastAmbientlightRatio = calibrationData.ambientlightRatio else { return }
        
        MeshAPI.getAmbientSensorValue(node: sensor, result: nil)
        
        let view = LightSensorManualCorrectionView(daylightLux: sensor.steadyDaylightLux ?? 0, sensorRatio: lastSensorRatio, ambientLightRatio: lastAmbientlightRatio) {[weak self] sensorRatio, ambientLightRatio in
            guard let self = self else { return }
            if sensorRatio != lastSensorRatio || ambientLightRatio != lastAmbientlightRatio {
                self.updateCalibrationRate(sensorRatio: sensorRatio, ambientLightRatio: ambientLightRatio)
            }else {
                self.manualCorrectionView?.dismiss()
            }
        }
        view.show()
        self.manualCorrectionView = view
        
        if let sensorModel = sensor.ambientLightSensorModel {
            MeshAPI.sendMessage(message: SensorGet(), model: sensorModel)
        }
        
    }
    
    /// 更新校准倍率
    private func updateCalibrationRate(sensorRatio: UInt16, ambientLightRatio: UInt16) {
        guard let vendorModel = selectSensor?.sunricherVendorModel else { return }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true, afterDelay: 10)
        MeshAPI.sendMessage(message: SunricherVendorSet(function: .daylightCalibrateRate(sensorRate: sensorRatio, ambientLightRate: ambientLightRatio)), model: vendorModel) {[weak self] response in
            XWHUDManager.hide()
            guard let self = self else { return }
            
            guard let statusMessage = response as? SunricherVendorStatus, statusMessage.status.isSuccessful else {
                XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
                return
            }
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            self.manualCorrectionView?.dismiss()
            
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        }
        
    }
    
    /// 校准
    @objc private func calibrationBtnAction() {
        if calibrationModeView.selectedMode == .night {
            showApplyNightCalibrationConfirmation()
            return
        }

        // 加载中
        
        guard !group.ambientLightSensorNodes.contains(where: { $0.selectState == .loading }),
              let sensor = self.selectSensor else {
            return
        }
        let validRange = Int(UInt16.min)...Int(UInt16.max)
        guard let onLux = onPointLuxView.measuredLightValue, let offLux = offPointLuxView.measuredLightValue, validRange.contains(onLux), validRange.contains(offLux) else {
            
            return
        }
        guard onLux > offLux else {
            showCalibrationFailed(message: "sensor_calibration_on_lux_must_exceed_off_lux".localizedString)
            return
        }
        
        /// 是否支持校准，检查固件版本
        guard sensor.supportSensorCalibration else {
            SRAlertView(title: "notification".localizedString, message: String(format: "sensor_calibration_minimum_version_message".localizedString, sensor.sensorCalibrationMinimumVersion), actions: [SRAlertAction(title: "ok".localizedString)]).show()
            return
        }
        
//        if measuredLightLevel < calibrationView.minimunValue || measuredLightLevel > calibrationView.maximunValue { // 输入测量值低于最小值、大于最大值
//            calibrationView.verifyMeasuredValue()
//            return
//        }
        
        // 禁用组内移动传感器上报
//        disablePresenceDetectedSensorPublish()
        
        setLuxPollingSuspended(true, for: .calibration)
        showConnecting()
        
        MeshSensorCalibrateManager.manager.calibrate(node: sensor, ambientLightOffLux: UInt16(offLux), ambientLightOnLux: UInt16(onLux)) { step in
            switch step {
            case .ready, .stabilityChecking:
                SRAlertView.getCurrentAlertView()?.messageLabel.text = "calibrating".localizedString
            case .lightsChecking, .lightInflectionPoints:
                SRAlertView.getCurrentAlertView()?.messageLabel.text = "checking_correct".localizedString
            default:
                break
            }
        } successful: { [weak self] _ in
            guard let self = self else { return }
            SRAlertView.hide()
            sensor.selectState = .loading
            self.sensorSelectView.reloadSensorCell(sensor: sensor)
            if sensor.restoreData != nil {
                sensor.restoreData?.daylightCalibrationData = nil
                sensor.save()
            }
            if sensor.preConfiguration.resetDaylightCalibration ?? false {
                sensor.preConfiguration.resetDaylightCalibration = nil
                if let meshUUID = sensor.network?.uuid.uuidString {
                    sensor.preConfiguration.save(meshUUID: meshUUID, nodeAddress: sensor.primaryUnicastAddress)
                }
            }
            // 切换选中的光照传感器
//            self.group.info.ambientLightSensorNode = sensor
//            if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
//                sensor.saveNodeInfo(meshUUID: uuid, networkKey: MeshNetworkManager.instance.currentNetworkKey)
//            }
//            self.updateGroupLightSensor()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            
            DispatchQueue.main.async {
                self.sensorEnabled(sensor: sensor) {[weak self] result in
                    guard let self = self else { return }
                    sensor.selectState = result ? .switchOn : .switchOff
                    self.sensorSelectView.reloadSensorCell(sensor: sensor)
//                    MeshAPI.sendMessage(message: ConfigRelaySet(count: 0, steps: 1), address: sensor.primaryUnicastAddress)
                    if result {
                        self.saveCalibrationMode(.planeCal)
                        self.selectSensor = sensor
                        // 切换选中的传感器，更新缓存
                        self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
                        self.onPointLuxView.measuredLightValue = nil
                        self.offPointLuxView.measuredLightValue = nil
                        self.updateGroupLightSensor()
                        self.updateCalibrationState()
                        self.updateManualCorrectionBtn()
                    } else {
                        self.saveCalibrationMode(.none)
                    }
                }
                self.setLuxPollingSuspended(false, for: .calibration)
            }
        } failed: {[weak self] _, error in
            guard let self = self  else { return }
            switch error {
            case .connectTimeout, .disconnect:
                self.showConnectFailed()
            case .deviceNotsupport, .noResponse:
                self.showCalibrationFailed(message: "connection_failure".localizedString)
            case .ambientInstability:
                self.showCalibrationFailed(message: "calibrating_failure".localizedString) //  + "min: \(minLux) max:\(maxLux)"
            case .lightNoEffect:
                self.showCalibrationFailed(message: "checking_correct_failure".localizedString)
            case .inflectionPointError:
                self.showCalibrationFailed(message: "checking_correct_failure".localizedString)
            case .targetIlluminanceInvalid, .targetIlluminanceUnstable:
                self.showCalibrationFailed(message: "calibration_target_illuminance_failure".localizedString)
            case .calibrationRollbackFailed:
                self.invalidateCalibrationAfterRollbackFailure()
                self.showCalibrationFailed(message: "calibration_rollback_failure".localizedString)
            }
        }
        
        
//        MeshSensorCalibrateServer.shared.calibrate(node: sensor, measuredValue: UInt16(measuredLightLevel)) { step in
//            
//            switch step {
//            case .calibrating, .stabilityChecking:
//                SRAlertView.getCurrentAlertView()?.messageLabel.text = "calibrating".localizedString
//            case .lightsChecking:
//                SRAlertView.getCurrentAlertView()?.messageLabel.text = "checking_correct".localizedString
//            default:
//                break
//            }
//            
//        } successful: {[weak self] _ in
//            guard let self = self else { return }
//            SRAlertView.hide()
//            sensor.selectState = .loading
//            self.sensorSelectView.reloadSensorCell(sensor: sensor)
//            // 切换选中的光照传感器
////            self.group.info.ambientLightSensorNode = sensor
//            // 更新profile调节速率
//            self.group.info.profile.adjustSpeed = self.calibrationView.adjustSpeed
////            if let uuid = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString {
////                sensor.saveNodeInfo(meshUUID: uuid, networkKey: MeshNetworkManager.instance.currentNetworkKey)
////            }
////            self.updateGroupLightSensor()
//            
//            // 通知space数据修改
//            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
//            
//            DispatchQueue.main.async {
//                self.sensorEnabled(sensor: sensor) {[weak self] result in
//                    guard let self = self else { return }
//                    sensor.selectState = result ? .switchOn : .switchOff
//                    self.sensorSelectView.reloadSensorCell(sensor: sensor)
////                    MeshAPI.sendMessage(message: ConfigRelaySet(count: 0, steps: 1), address: sensor.primaryUnicastAddress)
//                    if result {
//                        self.selectSensor = sensor
//                        // 切换选中的传感器，更新缓存
//                        self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
//                        self.calibrationView.measuredLightValue = nil
//                        self.updateGroupLightSensor()
//                        self.updateCalibrationState()
//                    }
//                }
//            }
//            
//        } failed: {[weak self] _, error in
//            guard let self = self  else { return  }
//            switch error {
//            case .deviceNotsupport, .connectTimeout, .disconnect, .noResponse:
//                self.showConnectFailed()
//            case .ambientInstability(let minLux, let maxLux):
//                self.showCalibrationFailed(message: "calibrating_failure".localizedString) //  + "min: \(minLux) max:\(maxLux)"
//            case .lightNoEffect:
//                self.showCalibrationFailed(message: "checking_correct_failure".localizedString)
//            }
//        }
        
    }

    private func showApplyNightCalibrationConfirmation() {
        guard !isNightCalibrationComplete else { return }
        SRAlertView(
            title: "apply_calibration_title".localizedString,
            message: "apply_calibration_message".localizedString,
            actions: [
                SRAlertAction(title: "cancel".localizedString, style: .cancel),
                SRAlertAction(title: "APPLY".localizedString, actionHandler: { [weak self] _ in
                    self?.startNightCalibration()
                })
            ]
        ).show()
    }

    private func startNightCalibration() {
        guard !group.ambientLightSensorNodes.contains(where: { $0.selectState == .loading }),
              let sensor = selectSensor else {
            return
        }

        guard !group.nodes.isEmpty, group.nodes.contains(where: { $0.state }) else {
            showAllDevicesOffline()
            return
        }

        guard sensor.supportSensorCalibration else {
            SRAlertView(
                title: "notification".localizedString,
                message: String(format: "sensor_calibration_minimum_version_message".localizedString, sensor.sensorCalibrationMinimumVersion),
                actions: [SRAlertAction(title: "ok".localizedString)]
            ).show()
            return
        }

        setLuxPollingSuspended(true, for: .calibration)
        showConnecting()
        let targetBrightness = targetNightBrightnessView.value
        let rollbackSnapshot = makeNightCalibrationSnapshot(for: sensor)

        MeshSensorCalibrateManager.manager.calibrateNight(
            node: sensor,
            targetBrightness: targetBrightness,
            progress: { step in
                DispatchQueue.main.async {
                    switch step {
                    case .connecting:
                        SRAlertView.getCurrentAlertView()?.messageLabel.text = "connecting".localizedString
                    case .targetIlluminance:
                        SRAlertView.getCurrentAlertView()?.messageLabel.text = "calculating_target_illuminance".localizedString
                    case .ready, .stabilityChecking, .lightsChecking, .lightInflectionPoints, .calibrateRate:
                        SRAlertView.getCurrentAlertView()?.messageLabel.text = "calibrating".localizedString
                    case .none:
                        break
                    }
                }
            },
            successful: { [weak self] _, result in
                guard let self else { return }
                SRAlertView.hide()
                self.finishNightCalibration(
                    sensor: sensor,
                    result: result,
                    targetBrightness: targetBrightness,
                    rollbackSnapshot: rollbackSnapshot
                )
            },
            failed: { [weak self] _, error in
                guard let self else { return }
                switch error {
                case .connectTimeout, .disconnect:
                    self.showConnectFailed()
                case .targetIlluminanceInvalid:
                    self.showCalibrationFailed(message: "calibration_target_illuminance_failure".localizedString)
                case .targetIlluminanceUnstable:
                    self.showCalibrationFailed(message: "calibration_target_illuminance_unstable".localizedString)
                case .calibrationRollbackFailed:
                    self.invalidateCalibrationAfterRollbackFailure()
                    self.showCalibrationFailed(message: "calibration_rollback_failure".localizedString)
                case .deviceNotsupport, .noResponse:
                    self.showCalibrationFailed(message: "connection_failure".localizedString)
                case .ambientInstability:
                    self.showCalibrationFailed(message: "calibrating_failure".localizedString)
                case .lightNoEffect, .inflectionPointError:
                    self.showCalibrationFailed(message: "checking_correct_failure".localizedString)
                }
            }
        )
    }

    private func finishNightCalibration(
        sensor: Node,
        result: NightSensorCalibrationResult,
        targetBrightness: Int,
        rollbackSnapshot: NightCalibrationSnapshot
    ) {
        sensor.selectState = .loading
        sensorSelectView.reloadSensorCell(sensor: sensor)

        commitNightSensorSelection(sensor, rollbackSnapshot: rollbackSnapshot) { [weak self] success, publicationRollbackSucceeded in
            guard let self else { return }
            guard success else {
                MeshSensorCalibrateManager.manager.restoreDaylightCalibration(
                    node: sensor,
                    to: rollbackSnapshot.selectedSensorCalibrationData
                ) { [weak self] calibrationRollbackSucceeded in
                    guard let self else { return }
                    if !publicationRollbackSucceeded || !calibrationRollbackSucceeded {
                        self.invalidateCalibrationAfterRollbackFailure()
                    }
                    self.group.ambientLightSensorNodes
                        .filter { $0 != sensor }
                        .forEach { $0.selectState = .switchOff }
                    sensor.selectState = .switchOn
                    self.selectSensor = sensor
                    self.sensorSelectView.reloadSensorCell(sensor: sensor)
                    self.setLuxPollingSuspended(false, for: .calibration)
                    self.setLuxPollingSuspended(false, for: .configuration)
                    let message = publicationRollbackSucceeded && calibrationRollbackSucceeded
                        ? "connection_failure".localizedString
                        : "calibration_rollback_failure".localizedString
                    self.showCalibrationFailed(message: message)
                }
                return
            }

            if sensor.restoreData != nil {
                sensor.restoreData?.daylightCalibrationData = nil
                sensor.save()
            }
            if sensor.preConfiguration.resetDaylightCalibration ?? false {
                sensor.preConfiguration.resetDaylightCalibration = nil
                if let meshUUID = sensor.network?.uuid.uuidString {
                    sensor.preConfiguration.save(meshUUID: meshUUID, nodeAddress: sensor.primaryUnicastAddress)
                }
            }

            let profile = self.group.info.profile
            if profile.type == .daylight {
                profile.lightControlData.taskLevel = Int(result.targetLux)
            } else {
                profile.lightControlData.occupancyLevel = Int(result.targetLux)
            }
            profile.targetNightBrightness = Profile.normalizedTargetNightBrightness(targetBrightness)
            profile.calibrationMode = .nightCal
            profile.save()
            self.group.info.save()
            self.group.updateGroupSyncState()
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)

            self.isNightRecalibrationDraft = false
            sensor.selectState = .switchOn
            self.selectSensor = sensor
            self.sensorSelectView.reloadSensorCell(sensor: sensor)
            self.updateGroupLightSensor()
            self.updateActiveCalibrationMode()
            self.updateCalibrationModeUI(.night)
            self.setLuxPollingSuspended(false, for: .calibration)

            self.configuring(lightNodes: self.group.nodes) { [weak self] success in
                guard success else { return }
                self?.restoreGroupAutoAfterDaylightCalibration()
            }
        }
    }

    private func makeNightCalibrationSnapshot(for sensor: Node) -> NightCalibrationSnapshot {
        let calibrationData = sensor.sensorCalibrationData.flatMap { data -> DaylightSensorCalibrationData? in
            guard data.isCalibration else { return nil }
            return DaylightSensorCalibrationData(
                sensorRatio: data.sensorRatio,
                ambientlightRatio: data.ambientlightRatio,
                minLightInflectionPointData: data.minLightInflectionPointData.map {
                    .init(lightness: $0.lightness, lux: $0.lux)
                },
                maxLightInflectionPointData: data.maxLightInflectionPointData.map {
                    .init(lightness: $0.lightness, lux: $0.lux)
                }
            )
        }
        let groupSensor = group.info.ambientLightSensorNode
        return NightCalibrationSnapshot(
            selectedSensorCalibrationData: calibrationData,
            selectedSensorPublish: sensor.ambientLightSensorModel?.publish,
            groupSensor: groupSensor,
            groupSensorPublish: groupSensor?.ambientLightSensorModel?.publish
        )
    }

    /// Night/Sensor 页的开关只修改草稿；只有完成校准后才一次性提交 publication 切换。
    private func commitNightSensorSelection(
        _ sensor: Node,
        rollbackSnapshot: NightCalibrationSnapshot,
        completion: @escaping (Bool, Bool) -> Void
    ) {
        setLuxPollingSuspended(true, for: .configuration)
        var messageHandles: [MeshMessageHandle] = []
        let previousSensor = rollbackSnapshot.groupSensor

        if let previousSensor,
           previousSensor != sensor,
           let previousModel = previousSensor.ambientLightSensorModel,
           previousModel.publish?.publicationAddress == group.address {
            let disableMessage = ConfigModelPublicationSet(disablePublicationFor: previousModel)!
            messageHandles.append(MeshMessageHandle(message: disableMessage, address: previousSensor.primaryUnicastAddress))
        }

        if let sensorModel = sensor.ambientLightSensorModel,
           sensorModel.publish?.publicationAddress != group.address {
            let publish = Publish(
                to: group.address,
                using: MeshNetworkManager.instance.currentApplicationKey,
                usingFriendshipMaterial: false,
                ttl: MeshNetworkManager.instance.networkParameters.defaultTtl,
                period: .disabled,
                retransmit: group.sensorServerPublicationRetransmit()
            )
            let publishMessage = ConfigModelPublicationSet(publish, to: sensorModel)!
            messageHandles.append(MeshMessageHandle(message: publishMessage, address: sensor.primaryUnicastAddress))
        }

        let finish: (Bool) -> Void = { [weak self] success in
            guard let self else { return }
            if success {
                self.group.ambientLightSensorNodes
                    .filter { $0 != sensor }
                    .forEach { $0.selectState = .switchOff }
                self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
                sensor.sendHandleCompleteIdentify(deviceBlinkMode: self.deviceBlinkMode)
            }
            DispatchQueue.main.async {
                completion(success, true)
            }
        }

        guard !messageHandles.isEmpty else {
            finish(true)
            return
        }
        MeshProxyMessageCommand.shared.addMessage(messageHandles: messageHandles) { resultHandles in
            let success = resultHandles.count == messageHandles.count && resultHandles.allSatisfy(\.isSuccessful)
            guard !success else {
                finish(true)
                return
            }

            var rollbackHandles: [MeshMessageHandle] = []
            if let selectedHandle = self.publicationRestoreHandle(
                node: sensor,
                publish: rollbackSnapshot.selectedSensorPublish
            ) {
                rollbackHandles.append(selectedHandle)
            }
            if let previousSensor,
               previousSensor != sensor,
               let previousHandle = self.publicationRestoreHandle(
                   node: previousSensor,
                   publish: rollbackSnapshot.groupSensorPublish
               ) {
                rollbackHandles.append(previousHandle)
            }

            guard !rollbackHandles.isEmpty else {
                DispatchQueue.main.async {
                    completion(false, true)
                }
                return
            }
            MeshProxyMessageCommand.shared.addMessage(messageHandles: rollbackHandles) { rollbackResults in
                let rollbackSucceeded = rollbackResults.count == rollbackHandles.count
                    && rollbackResults.allSatisfy(\.isSuccessful)
                DispatchQueue.main.async {
                    completion(false, rollbackSucceeded)
                }
            }
        }
    }

    private func publicationRestoreHandle(node: Node, publish: Publish?) -> MeshMessageHandle? {
        guard let sensorModel = node.ambientLightSensorModel else {
            return nil
        }
        let message: ConfigModelPublicationSet?
        if let publish {
            message = ConfigModelPublicationSet(publish, to: sensorModel)
        } else {
            message = ConfigModelPublicationSet(disablePublicationFor: sensorModel)
        }
        guard let message else { return nil }
        return MeshMessageHandle(message: message, address: node.primaryUnicastAddress)
    }

    private func saveCalibrationMode(_ mode: Profile.DaylightCalibrationMode) {
        group.info.profile.calibrationMode = mode
        group.info.profile.save()
        group.info.save()
        group.updateGroupSyncState()
        updateActiveCalibrationMode()
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
    }

    private func invalidateCalibrationAfterRollbackFailure() {
        saveCalibrationMode(.none)
        MeshAPI.sendMessage(
            message: LightLCLightOnOffSetUnacknowledged(false),
            address: group.address.address
        )
    }

    private func showAllDevicesOffline() {
        SRAlertView(
            title: "daylight_sensor".localizedString,
            message: "calibration_all_devices_offline".localizedString,
            actions: [
                SRAlertAction(title: "cancel".localizedString, style: .cancel),
                SRAlertAction(title: "RETRY".localizedString, actionHandler: { [weak self] _ in
                    self?.startNightCalibration()
                })
            ]
        ).show()
    }
    
    
    /// 开始配置
    private func configuring(lightNodes: [Node], completion: ((Bool) -> Void)? = nil) {
        setLuxPollingSuspended(true, for: .configuration)
        // 判断哪些需要设置的灯
        let setLightNodes = lightNodes.filter({ $0.getNodeSyncProfiles().count > 0 })
        if setLightNodes.isEmpty {
            DispatchQueue.main.async {
                SRAlertView.hide()
                self.setLuxPollingSuspended(false, for: .configuration)
                completion?(true)
            }
            return
        }
        
        self.stopConfig = false
        DispatchQueue.main.async {
            self.showConfiguring()
        }
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
                self.group.updateGroupSyncState()
                if self.calibrationModeView.selectedMode == .night {
                    self.updateCalibrationModeUI(.night)
                }
                if failedNodes.count > 0 {
                    self.showCheckingCorrectFailure(total: successNodes.count + failedNodes.count, successCount: successNodes.count, failedNodes: failedNodes, completion: completion)
                    completion?(false)
                }else {
                    SRAlertView.hide()
                    self.setLuxPollingSuspended(false, for: .configuration)
                    completion?(true)
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
        SRAlertView(title: "daylight_sensor".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: "connection_failure".localizedString, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "CLOSE".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), actionHandler: { [weak self] _ in
            self?.setLuxPollingSuspended(false, for: .calibration)
        })]).show()
    }
    
    /// 显示校准失败弹窗
    private func showCalibrationFailed(message: String) {
        SRAlertView(title: "daylight_sensor".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: message, messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "cancel".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), style: .cancel, actionHandler: { [weak self] _ in
            self?.setLuxPollingSuspended(false, for: .calibration)
        }), SRAlertAction(title: "RETRY".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), actionHandler: {[weak self] _ in
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
    private func showCheckingCorrectFailure(total: Int, successCount: Int, failedNodes: [Node], completion: ((Bool) -> Void)? = nil) {
        SRAlertView(title: "configuring".localizedString, titleColor: TextBlack_Color, titleFont: FONTS(SCRYFrom(15)), message: String(format: "calibration_configuring_failed".localizedString, successCount, total, total - successCount), messageColor: TextBlack_Color, messageFont: UIFont.systemFont(ofSize: 15, weight: .light), actions: [SRAlertAction(title: "cancel".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), style: .cancel, actionHandler: { [weak self] _ in
            self?.setLuxPollingSuspended(false, for: .configuration)
        }), SRAlertAction(title: "RETRY".localizedString, titleFont: UIFont.systemFont(ofSize: 15, weight: .light), actionHandler: {[weak self] _ in
            
            self?.configuring(lightNodes: failedNodes, completion: completion)
        })]).show()
    }
    
    private func updateCalibrationState() {
        switch calibrationModeView.selectedMode {
        case .night:
            calibrationBtn.isEnabled = selectSensor != nil && !isNightCalibrationComplete
        case .sensor, .plane:
            calibrationBtn.isEnabled = onPointLuxView.measuredLightValue != nil
                && offPointLuxView.measuredLightValue != nil
                && selectSensor != nil
        }
    }
    
    /// 传感器启用
    private func sensorEnabled(sensor: Node, resetCalibrated: Bool = false, result: ((Bool)->Void)?) {
        
        guard let ambientLightSensorModel = sensor.ambientLightSensorModel else {
            result?(false)
            return
        }
        setLuxPollingSuspended(true, for: .configuration)
        // 判断传感器是否已启用
        if ambientLightSensorModel.publish?.publicationAddress == self.group.address {
            result?(true)
            DispatchQueue.main.async {
                self.configuring(lightNodes: self.group.nodes) { [weak self] success in
                    guard success else { return }
                    self?.restoreGroupAutoAfterDaylightCalibration()
                }
            }
            return
        }
        
        
        let retransmit = group.sensorServerPublicationRetransmit()
        let publishMessage = ConfigModelPublicationSet(Publish(to: self.group.address, using: MeshNetworkManager.instance.currentApplicationKey, usingFriendshipMaterial: false, ttl: MeshNetworkManager.instance.networkParameters.defaultTtl, period: .disabled, retransmit: retransmit), to: ambientLightSensorModel)!
        
        MeshProxyMessageCommand.shared.addMessage(messageHandles: [MeshMessageHandle(message: publishMessage, address: sensor.primaryUnicastAddress)]) {[weak self] resultHandles in
            guard let self = self else { return }
            if let handle = resultHandles.first, handle.isSuccessful {
                sensor.sendHandleCompleteIdentify(deviceBlinkMode: self.deviceBlinkMode)
                // 启用传感器，更新缓存
                self.group.info.ambientLightSensorNodeAddress = sensor.primaryUnicastAddress
                result?(true)
                DispatchQueue.main.async {
                    self.updateGroupLightSensor()
                    self.configuring(lightNodes: self.group.nodes) { [weak self] success in
                        guard success else { return }
                        self?.restoreGroupAutoAfterDaylightCalibration()
                    }
                }
            }else {
                self.setLuxPollingSuspended(false, for: .configuration)
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
        setLuxPollingSuspended(true, for: .configuration)
        
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
                result?(handle.isSuccessful)
                
                DispatchQueue.main.async {
                    self.updateGroupLightSensor()
                    if lightConfig {
                        self.configuring(lightNodes: self.group.nodes)
                    }else {
                        self.setLuxPollingSuspended(false, for: .configuration)
                    }
                }
                
            }else {
                self.setLuxPollingSuspended(false, for: .configuration)
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
//        scrollView.showsVerticalScrollIndicator = false
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

        calibrationModeView = LightSensorCalibrationModeView()
        contentView.addSubview(calibrationModeView)
        calibrationModeView.snp.makeConstraints { make in
            make.left.right.equalTo(sensorSelectView)
            make.top.equalTo(sensorSelectView.snp.bottom).offset(SCRYFrom(16))
        }

        calibrationAboutView = LightSensorCalibrationAboutView()
        calibrationModeView.modeChangedHandler = { [weak self] mode in
            self?.calibrationAboutView.updateMode(mode)
            self?.updateCalibrationModeUI(mode)
        }
        contentView.addSubview(calibrationAboutView)
        calibrationAboutView.snp.makeConstraints { make in
            make.left.right.equalTo(sensorSelectView)
            make.top.equalTo(calibrationModeView.snp.bottom).offset(SCRYFrom(16))
        }
       
        onPointLuxView = LightSensorCalibrationPointLuxView()
        onPointLuxView.titleLabel.text = "sensor_calibration_on_lux".localizedString
        onPointLuxView.onoffBtn.setTitle("on".localizedString, for: .normal)
        onPointLuxView.noteLabel.text = "sensor_calibration_on_lux_note".localizedString
        onPointLuxView.delegate = self
        
        offPointLuxView = LightSensorCalibrationPointLuxView()
        offPointLuxView.titleLabel.text = "sensor_calibration_off_lux".localizedString
        offPointLuxView.onoffBtn.setTitle("off".localizedString, for: .normal)
        offPointLuxView.noteLabel.text = "sensor_calibration_off_lux_note".localizedString
        offPointLuxView.delegate = self

        targetNightBrightnessView = LightSensorTargetNightBrightnessView()
        targetNightBrightnessView.allowedRange = targetNightBrightnessRange
        targetNightBrightnessView.value = Profile.normalizedTargetNightBrightness(group.info.profile.targetNightBrightness)

        nightCalibrationCompleteView = LightSensorNightCalibrationCompleteView()
        nightCalibrationCompleteView.recalibrateHandler = { [weak self] in
            self?.recalibrateNight()
        }

        manualCorrectionBtn = UIButton(titleSize: 15, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(manualCorrectionBtnAction))
        manualCorrectionBtn.setAttributedTitle( NSAttributedString(string: "manual_correction".localizedString, attributes: [.underlineStyle: 1]), for: .normal)
        manualCorrectionBtn.isHidden = true

        let calibrationContentStackView = UIStackView(arrangedSubviews: [
            onPointLuxView,
            offPointLuxView,
            targetNightBrightnessView,
            nightCalibrationCompleteView,
            manualCorrectionBtn
        ])
        calibrationContentStackView.axis = .vertical
        calibrationContentStackView.spacing = SCRYFrom(16)
        contentView.addSubview(calibrationContentStackView)
        calibrationContentStackView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(calibrationAboutView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-32))
        }
        
//        calibrationView = LightSensorCalibrationView()
//        let profileData = group.info.profile.lightData.data
//        calibrationView.limitRange = profileData.lowEndTrim...profileData.highEndTrim
//        calibrationView.speedSlider.value = Float(group.info.profile.adjustSpeed)
//        calibrationView.delegate = self
//        calibrationView.minimunValue = minimunLux
//        contentView.addSubview(calibrationView)
//        calibrationView.snp.makeConstraints { make in
//            make.left.right.equalTo(sensorSelectView)
//            make.top.equalTo(sensorSelectView.snp.bottom).offset(SCRYFrom(16))
//            make.height.greaterThanOrEqualTo(SCRYFrom(178))
//            make.bottom.equalToSuperview()
//        }
        
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
    static var selectStateKey: UInt8 = 0
    
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
    
    private func showExternalLightSensorConnectionAlert(for sensor: Node, in view: LightSensorCalibrationSelectView, confirmHandler: @escaping () -> Void) {
        SRAlertView(
            title: "external_light_sensor_capable_luminaire_calibration_title".localizedString,
            message: "external_light_sensor_capable_luminaire_calibration_message".localizedString,
            actions: [
                SRAlertAction(title: "external_light_sensor_capable_luminaire_calibration_cancel".localizedString, style: .cancel, actionHandler: { [weak view] _ in
                    sensor.selectState = .switchOff
                    view?.reloadSensorCell(sensor: sensor)
                }),
                SRAlertAction(title: "external_light_sensor_capable_luminaire_calibration_confirm".localizedString, actionHandler: { _ in
                    confirmHandler()
                })
            ]
        ).show()
    }

    private func enableDaylightSensor(_ selectSensor: Node, lastSelectSensor: Node?, in view: LightSensorCalibrationSelectView) {
        setLuxPollingSuspended(true, for: .sensorSwitching)
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
        
        DispatchQueue.global().async {
            var disableLastSensor: Bool = true
            let semaphore = DispatchSemaphore(value: 0)
            if lastSelectSensorUnPublish, let sensor = lastSelectSensor {
                self.sensorDisable(sensor: sensor, lightConfig: !selectSensorPublish) {[weak self] result in
                    disableLastSensor = result
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
                        }else {
                            selectSensor.selectState = .switchOff
                            view.reloadSensorCell(sensor: selectSensor)
                            SRAlertView(title: "notification".localizedString, message: "sensor_calibration_disable_failed_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString)]).show()
                        }
                    }
                    semaphore.signal()
                }
                semaphore.wait()
            }
            // 是否关闭之前的校准传感器，否则失败
            guard disableLastSensor else {
                self.setLuxPollingSuspended(false, for: .sensorSwitching)
                return
            }
            
            DispatchQueue.main.async {
                if selectSensorPublish {
                    selectSensor.selectState = .loading
                }else {
                    selectSensor.selectState = .switchOn
                    self.selectSensor = selectSensor
                    self.updateCalibrationState()
                }
                view.reloadSensorCell(sensor: selectSensor)
            }
        
            if selectSensorPublish {
                self.sensorEnabled(sensor: selectSensor, resetCalibrated: true) {[weak self] result in
                    DispatchQueue.main.async {
                        selectSensor.selectState = result ? .switchOn : .switchOff
                        view.reloadSensorCell(sensor: selectSensor)
                        if result {
                            self?.selectSensor = selectSensor
                            self?.onPointLuxView.measuredLightValue = nil
                            self?.offPointLuxView.measuredLightValue = nil
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
                self.updateManualCorrectionBtn()
                self.setLuxPollingSuspended(false, for: .sensorSwitching)
            }
        }
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

        if calibrationModeView.selectedMode != .plane {
            lastSelectSensor?.selectState = .switchOff
            if let lastSelectSensor {
                view.reloadSensorCell(sensor: lastSelectSensor)
            }
            selectSensor.selectState = .switchOn
            self.selectSensor = selectSensor
            view.reloadSensorCell(sensor: selectSensor)
            updateCalibrationState()
            updateManualCorrectionBtn()
            return
        }
        
        guard selectSensor.isExternalLightSensorCapableLuminaire else {
            enableDaylightSensor(selectSensor, lastSelectSensor: lastSelectSensor, in: view)
            return
        }

        showExternalLightSensorConnectionAlert(for: selectSensor, in: view) { [weak self, weak view] in
            guard let self, let view else { return }
            self.enableDaylightSensor(selectSensor, lastSelectSensor: lastSelectSensor, in: view)
        }
    }
    
    /// 取消选择传感器回调
    /// - Parameters:
    ///   - view: self
    ///   - selectSensor: 取消选中的传感器
    func view(_ view: LightSensorCalibrationSelectView, didDeselectDaylightSensor sensor: Node) {
        if calibrationModeView.selectedMode != .plane {
            sensor.selectState = .switchOff
            if selectSensor == sensor {
                selectSensor = nil
            }
            view.reloadSensorCell(sensor: sensor)
            updateCalibrationState()
            updateManualCorrectionBtn()
            return
        }

        setLuxPollingSuspended(true, for: .sensorSwitching)
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
                        self?.updateManualCorrectionBtn()
                    }
                    self?.setLuxPollingSuspended(false, for: .sensorSwitching)
                }
            }
        }else {
            sensor.selectState = .switchOff
            self.selectSensor = nil
            view.reloadSensorCell(sensor: sensor)
            updateCalibrationState()
            updateManualCorrectionBtn()
            setLuxPollingSuspended(false, for: .sensorSwitching)
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

extension LightSensorCalibrationViewController: LightSensorCalibrationPointLuxViewDelegate {
    
    /// 输入测量值回调
    /// - Parameters:
    ///   - view: view
    ///   - lux: 测量值 为空则未输入
    func view(_ view: LightSensorCalibrationPointLuxView, measuredLightValueEditing lux: Int?) {
        updateCalibrationState()
    }
    
    /// 点击onoff事件
    func sensorCalibrationPointLuxViewOnOffAction(_ view: LightSensorCalibrationPointLuxView) {
        if view == onPointLuxView {
            MeshAPI.setGroupLightnessState(address: group.address.address, lightness: .max)
        }else {
            MeshAPI.setGroupLightnessState(address: group.address.address, lightness: 0)
        }
    }

}

extension LightSensorCalibrationViewController: MeshLibManagerMessageDelegate {
    
    func meshNetworkManager(_ manager: MeshNetworkManager, didReceiveMessage message: any MeshMessage, sentFrom source: Address, to destination: Address) {
        guard let sensor = selectSensor,
              sensor.contains(elementWithAddress: source),
              let sensorMessage = message as? SensorStatus,
              sensorMessage.values.contains(where: { $0.property.id == DeviceProperty.presentAmbientLightLevel.id }),
              let lux = sensor.steadyDaylightLux else {
            return
        }

        DispatchQueue.main.async { [weak self, weak sensor] in
            guard let self = self, let sensor = sensor, self.selectSensor == sensor else { return }
            self.manualCorrectionView?.daylightLux = lux

            guard self.isViewVisible,
                  self.luxPollingSuspensionReasons.isEmpty,
                  sensor.selectState == .switchOn else {
                return
            }
            self.sensorSelectView.updateLux(sensor: sensor, isFresh: true)
        }
    }
    
}
