//
//  ProfileSettingsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit
import NordicSigMeshSDK

class ProfileSettingsViewController: UIViewController, KeyboardScrollable {

    /// 自动化调光类型
    enum AutomationPhasesType {
        /// 默认
        case `default`
        /// 白天
        case day
        /// 晚上
        case night
    }
    
    struct TimeData {
        // 每个时间单元
        struct TimeItem {
            /// 描述
            let name: String
            /// 秒
            let second: Int
        }
        
        let type: String
        let title: String
        let items: [TimeItem]
    }
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    private var headerView: ProfileSettingsHeaderView!
    private var sphasesView: ProfileSettingsSphasesView!
//    private var daylightSensorView: ProfileDaylightSensorControlView!
    private var timeoutView: ProfileManualOverrideTimeoutView!
    private var powerUpBehaviorView: ProfilePowerUpBehaviorView!
    private var sensitivityView: ProfileSensitivityView!
    /// 速率调节
    private var adjustSpeedView: LightSensorCalibrationAdjustSpeedView!
    
    /// 邻近照明
    private var proximityLightingStepView: ProfileProximityLightingStepView?
    private var proximityLightingNumberView: ProfileProximityLightingNumberView?
    /// 晚上
    private var nightPhasesView: ProfileTriggerConditionPhasesView?
    /// 白天
    private var dayPhasesView: ProfileTriggerConditionPhasesView?
    /// 晚上/白天照度阈值
    private var nightDayIlluminanceView: ProfileNightDayIlluminanceThresholdView?
    
    private let contentMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(16)
    
    /// 配置数据
    private var profiles: [Profile] = [
        .init(type: .occupancy_daylight),
        .init(type: .vacancy_daylight),
        .init(type: .occupancy),
        .init(type: .vacancy),
        .init(type: .daylight),
        .init(type: .manualControl),
        .init(type: .proximityLighting),
        .init(type: .proximityLightingWithPhotocell)
    ]
    /// 选择的配置数据
    private var selectProfile: Profile!
    /// 初始的配置数据（判断是否编辑）
    private var initProfile: Profile!
    /// 白天的lux条件
//    private var dayStartsBelowLux: Int?
    /// 晚上的lux条件
//    private var nightStartsBelowLux: Int?
    
    /// 使用配置的group
    let group: Group?
    /// 是否可编辑
    var editable: Bool = true
    /// 保存事件回调
    var saveActionCallback: ((Profile)->Void)?

    var keyboardScrollView: UIScrollView {
        return self.scrollView
    }
    
    
    init(group: Group? = nil, profile: Profile) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
        self.selectProfile = profile.copy()
        self.initProfile = profile
        if let index = profiles.firstIndex(where: { $0.type == selectProfile.type }) {
            self.profiles.replaceSubrange(index...index, with: [selectProfile])
        }
//        if profile.type == .proximityLightingWithPhotocell {
//            self.nightStartsBelowLux = profile.nightData?.startsBelowLux
//            self.dayStartsBelowLux = profile.dayData?.startsBelowLux
//        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        view.backgroundColor = Background_Color
//        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        if editable {
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(saveAction))
            (navigationController as? NavigationViewController)?.navigationDelegate = self
        }
        
        setupUI()
        updateUI()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (navigationController as? NavigationViewController)?.navigationDelegate = self
        
        if selectProfile.type == .proximityLightingWithPhotocell {
            updateNightDayIlluminanceThresholdDeviceDetail()
        }
        registerForKeyboardNotifications()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.scrollView.firstShowFlashScrollIndicators {
            self.scrollView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        (navigationController as? NavigationViewController)?.navigationDelegate = nil
        
        unregisterFromKeyboardNotifications()
    }

    private func exitAction() {
        
        if initProfile == nil || selectProfile == initProfile! {
            navigationController?.popViewController(animated: true)
        }else {
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "EXIT".localizedString, actionHandler: {[weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })]).show()
        }
    }
    
    @objc private func saveAction() {
        if selectProfile.type == .proximityLightingWithPhotocell {
            guard let nightStartsBelowLux = nightDayIlluminanceView?.nightStartsBelowLux else {
                nightDayIlluminanceView?.updateNightStartsBelowLuxTip(tipMessage: "\("night".localizedString)  \("threshold_is_required".localizedString)")
                scrollView.setContentOffset(CGPoint(x: 0, y: nightPhasesView?.y ?? 0), animated: true)
                return
            }
            guard let dayStartsAboveLux = nightDayIlluminanceView?.dayStartsAboveLux else {
                nightDayIlluminanceView?.updateDayStartsAboveLuxTip(tipMessage: "\("day".localizedString)  \("threshold_is_required".localizedString)")
                scrollView.setContentOffset(CGPoint(x: 0, y: dayPhasesView?.y ?? 0), animated: true)
                return
            }
            
            // lux必须小于5000
            let luxRange: ClosedRange<Int> = 0...5000
            
            guard luxRange.contains(nightStartsBelowLux) else {
                nightDayIlluminanceView?.updateNightStartsBelowLuxTip(tipMessage: "\("limit_range".localizedString) \(luxRange.lowerBound)~\(luxRange.upperBound)lux")
                scrollView.setContentOffset(CGPoint(x: 0, y: nightDayIlluminanceView?.y ?? 0), animated: true)
                return
            }
            guard luxRange.contains(dayStartsAboveLux) else {
                nightDayIlluminanceView?.updateDayStartsAboveLuxTip(tipMessage: "\("limit_range".localizedString) \(luxRange.lowerBound)~\(luxRange.upperBound)lux")
                scrollView.setContentOffset(CGPoint(x: 0, y: nightDayIlluminanceView?.y ?? 0), animated: true)
                return
            }
            
            // 晚上必须小于白天lux
            guard nightStartsBelowLux < dayStartsAboveLux else {
                nightDayIlluminanceView?.updateNightStartsBelowLuxTip(tipMessage: "profile_night_startsbelow_less_day".localizedString)
                nightDayIlluminanceView?.updateDayStartsAboveLuxTip(tipMessage: "profile_night_startsbelow_greater_day".localizedString)
                scrollView.setContentOffset(CGPoint(x: 0, y: nightDayIlluminanceView?.y ?? 0), animated: true)
                return
            }
            // 白天lux-晚上lux必须大于等于5
            guard dayStartsAboveLux - nightStartsBelowLux >= 5 else {
                nightDayIlluminanceView?.updateNightStartsBelowLuxTip(tipMessage: "profile_night_startsbelow_less_day_threshold".localizedString)
                nightDayIlluminanceView?.updateDayStartsAboveLuxTip(tipMessage: "profile_night_startsbelow_greater_day_threshold".localizedString)
                scrollView.setContentOffset(CGPoint(x: 0, y: nightDayIlluminanceView?.y ?? 0), animated: true)
                return
            }
            
            selectProfile.dayData?.startsBelowLux = UInt16(dayStartsAboveLux)
            selectProfile.nightData?.startsBelowLux = UInt16(nightStartsBelowLux)
            
            // 使用最新的profile功能需要绑定对应model
            group?.nodes.forEach { node in
                if !node.requiredFunctionTypes.contains(.lightLCScene) {
                    node.requiredFunctionTypes.append(.lightLCScene)
                    node.save()
                }
                if let meshUUID = node.network?.uuid.uuidString {
                    node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
                }
            }
            
            ProfileLightSensorTemplate.delete(profileId: selectProfile.id)
            selectProfile.lightSensorTemplates.forEach {
                $0.save(profileId: selectProfile.id)
            }
        }
        
        if selectProfile.type != group?.info.profile.type { // 切换profile
            let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
            if selectProfile.type != .proximityLightingWithPhotocell { // 清空白天黑夜设置的设备预配置数据
                group?.nodes.forEach({ node in
                    node.preConfiguration.dayProfileStartsAboveLux = nil
                    node.preConfiguration.nightProfileStartsBelowLux = nil
                    node.preConfiguration.dayProfileLightData = nil
                    node.preConfiguration.nightProfileLightData = nil
                    if let meshUUID = meshUUID {
                        node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
                    }
                })
            }
            
            // 清空校准设备的校准数据
            if !selectProfile.type.daylightType {
                let calibrationNodes = group?.nodes.filter({ $0.sensorCalibrationData?.isCalibration ?? false }) ?? []
                calibrationNodes.forEach { node in
                    node.preConfiguration.resetDaylightCalibration = true
                    if let meshUUID = meshUUID {
                        node.preConfiguration.save(meshUUID: meshUUID, nodeAddress: node.primaryUnicastAddress)
                    }
                }
            }
        }
        
        saveActionCallback?(selectProfile)
     
        if let group = group, group.nodes.contains(where: { $0.needSync }) {
            let vc = SyncDevicesViewController(type: .group(group, inNodes: nil, outNodes: nil))
            vc.syncSuccessCallback = {[weak self] _ in
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                guard let self = self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
                        self.navigationController?.popToViewController(vcClass: GroupViewController.classForCoder(), animated: true)
                }
            }
            vc.backActionCallback = {[weak self] _ in
                guard let self = self else { return }
                NotificationCenter.default.post(name: .init(groupDataUpdateNotificationName), object: group)
                self.navigationController?.popToViewController(vcClass: GroupViewController.classForCoder())
            }
            navigationController?.pushViewController(vc, animated: true)
        }else {
            navigationController?.popViewController(animated: true)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        }
        
    }
    
    /// 展示level设置UI  type：level类型
    private func showLevelSettings(type: ProfileLevelSettingsView.LevelType, phasesType: AutomationPhasesType = .default) {
        
        ProfileLevelSettingsView(levelType: type) {[weak self] item, value in
            if item.itemType.data.calibrated, let group = self?.group, let sensorNode = group.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil {
                switch item.itemType {
                case .occupancyLux, .vacantLux, .taskLux:
                    guard MeshLibManager.manager.isMeshNetworkConnected else {
                        XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                        return
                    }
                    
                    item.showLoadingAnimation()
                    DispatchQueue.global().async {
                        MeshAPI.setGroupLightnessState(address: group.address.address, lightness: Node.getLightness(lightness100: value))
                        Thread.sleep(forTimeInterval: 3)
                        MeshAPI.getAmbientSensorValue(node: sensorNode) { lux in
                            DispatchQueue.main.async {
                                if lux != nil {
                                    item.value = Int(lux!)
                                }else if let currentLux = sensorNode.steadyDaylightLux {
                                    item.value = Int(currentLux)
                                }
                                item.hideLoadingAnimation()
                            }
                        }
                    }
                   
                default:
                    break
                }
            }
            
        } settingsCallback: {[weak self] result in
            guard let self = self else { return }
            
            var lightControlData = self.selectProfile.lightControlData
            switch phasesType {
            case .default:
                lightControlData = self.selectProfile.lightControlData
            case .day:
                if let dayLightControlData = self.selectProfile.dayData?.sceneData.lightControlData {
                    lightControlData = dayLightControlData
                }
            case .night:
                if let nightLightControlData = self.selectProfile.nightData?.sceneData.lightControlData {
                    lightControlData = nightLightControlData
                }
            }
            
            switch result {
            case .highLowEndTrim(let high, let low):

                // 更新最高/最低亮度输出，判断其它数据是否超出范围
                
                let range: ClosedRange<Int> = low...high
//                self.selectProfile.lightControlData.highEndTrim = high
//                self.selectProfile.lightControlData.lowEndTrim = low
//                lightData.updateLevel(lightType: .lightnessRange(low...high))
                
                // 亮度上下限共享数据，更新后更新各配置缓存
                var lightControlDatas: [Profile.LightControlData] = [selectProfile.lightControlData]
                if let day = selectProfile.dayData {
                    lightControlDatas.append(day.sceneData.lightControlData)
                }
                if let night = selectProfile.nightData {
                    lightControlDatas.append(night.sceneData.lightControlData)
                }
                
                lightControlDatas.forEach({
                    $0.highEndTrim = high
                    $0.lowEndTrim = low
                })
                
                // 判断是否是亮度配置
                let levelConfig = !(self.selectProfile.type == .occupancy_daylight || self.selectProfile.type == .vacancy_daylight || self.selectProfile.type == .daylight)
        
                    lightControlDatas.forEach({ data in
                        // level 百分比数据时修改最高最低亮度输出需判断其它阶段参数是否超出输出范围
                        if levelConfig {
                            if !range.contains(data.occupancyLevel) {
                                data.occupancyLevel = max(min(data.occupancyLevel, high), low)
                            }
                            if !range.contains(data.vacantLevel) {
                                data.vacantLevel = max(min(data.vacantLevel, high), low)
                            }
                            if !range.contains(data.taskLevel) {
                                data.taskLevel = max(min(data.taskLevel, high), low)
                            }
                            // 允许待机时0% off的情况
                            if data.standbyLevel > 0 && !range.contains(data.standbyLevel) {
                                data.standbyLevel = max(min(data.standbyLevel, high), low)
                            }
                        }else {
                            if !range.contains(data.autoMinLevel) {
                                data.autoMinLevel = max(min(data.autoMinLevel, high), low)
                            }
                        }
                    })
                
                
//                if data.autoMinLevelEnabled, !range.contains(data.autoMinLevel) {
//                    lightData.updateLevel(lightType: .autoMinValue(max(min(data.autoMinLevel, high), low), enabled: data.autoMinLevelEnabled))
//                }
                
               
                switch self.selectProfile.powerUpState {
                case .definedLightLevel(let level):
//                    if !range.contains(lightControlData.occupancyLevel) {
                    if !range.contains(Int(level)) { // 上电亮度不在亮度范围内
                        let value = max(min(Int(level), high), low)
                        self.selectProfile.powerUpState = .definedLightLevel(UInt8(value))
                        self.powerUpBehaviorView.powerState = self.selectProfile.powerUpState
                    }
                    fallthrough
                default:
                    self.powerUpBehaviorView.lightnessSliderView.slider.limitRange = range
                }
                
                self.sphasesView.profile = self.selectProfile
                if let dayData = self.selectProfile.dayData {
                    self.dayPhasesView?.updateData(profile: self.selectProfile, conditionData: dayData)
                }
                if let nightData = self.selectProfile.nightData {
                    self.nightPhasesView?.updateData(profile: self.selectProfile, conditionData: nightData)
                }
                
                return
            case .occupancyAndVacantLevel(let occupanyLevel, let vacantLevel):
                lightControlData.occupancyLevel = occupanyLevel
                lightControlData.vacantLevel = vacantLevel
            case .occupancyAndVacantLux(let occupanyLux, let vacantLux):
                lightControlData.occupancyLevel = occupanyLux
                lightControlData.vacantLevel = vacantLux
            case .taskLevel(let level):
                lightControlData.taskLevel = level
            case .taskLux(let lux):
                lightControlData.taskLevel = lux
            case .autoMinValue(let level, let enabled):
                lightControlData.autoMinLevel = enabled ? level : 255
//                lightData.updateLevel(lightType: .autoMinValue(enabled ? level : 0, enabled: enabled))
            case .standbyLevel(let level):
                lightControlData.standbyLevel = level
//                lightData.updateLevel(lightType: .standbyLevel(level))
            }
            
            
            
            switch phasesType {
            case .default:
                self.sphasesView.profile = self.selectProfile
            case .day:
                if let dayData = self.selectProfile.dayData {
                    self.dayPhasesView?.updateData(profile: self.selectProfile, conditionData: dayData)
                }
            case .night:
                if let nightData = self.selectProfile.nightData {
                    self.nightPhasesView?.updateData(profile: self.selectProfile, conditionData: nightData)
                }
            }
            
            
        }.show()
        
    }
    
    private func showTimeSettings(type: Profile.LightData.TimePickerData.TimeType, phasesType: AutomationPhasesType = .default) {
        
        guard let timeData = Profile.LightData.TimePickerData.pickerTimes[type] else { return }
        
        var data = selectProfile.lightControlData
        switch phasesType {
        case .default:
            data = selectProfile.lightControlData
        case .day:
            if let day = selectProfile.dayData {
                data = day.sceneData.lightControlData
            }
        case .night:
            if let night = selectProfile.nightData {
                data = night.sceneData.lightControlData
            }
        }
//        let data = selectProfile.lightData.data
        var selectValue = 0
        switch type {
        case .t1:
            selectValue = data.t1
        case .t2:
            selectValue = data.t2
        case .t3:
            selectValue = data.t3
        case .t4:
            selectValue = data.t4
        case .t5:
            selectValue = data.t5
        }
        
        let defalutSelectRow = timeData.items.firstIndex(where: { $0.second == selectValue }) ?? 0
        
        ProfilePhasesTimePickerView(title: timeData.title, name: timeData.type, times: timeData.items.map({ $0.name }), defalutSelectRow: defalutSelectRow) { [weak self] index in
            guard let self = self else { return }
            let second = timeData.items[index].second
            var lightControlData = self.selectProfile.lightControlData
            switch phasesType {
            case .default:
                lightControlData = self.selectProfile.lightControlData
            case .day:
                if let dayLightControlData = self.selectProfile.dayData?.sceneData.lightControlData {
                    lightControlData = dayLightControlData
                }
            case .night:
                if let nightLightControlData = self.selectProfile.nightData?.sceneData.lightControlData {
                    lightControlData = nightLightControlData
                }
            }
            switch type {
            case .t1:
                lightControlData.t1 = second
            case .t2:
                lightControlData.t2 = second
            case .t3:
                lightControlData.t3 = second
            case .t4:
                lightControlData.t4 = second
            case .t5:
                lightControlData.t5 = second
            }
            switch phasesType {
            case .default:
                self.sphasesView.profile = self.selectProfile
            case .day:
                if let dayData = self.selectProfile.dayData {
                    self.dayPhasesView?.updateData(profile: self.selectProfile, conditionData: dayData)
                }
            case .night:
                if let nightData = self.selectProfile.nightData {
                    self.nightPhasesView?.updateData(profile: self.selectProfile, conditionData: nightData)
                }
            }
            
        }.show()
        
    }
    
    private func updateUI() {
        
        self.headerView.profileBtn.setTitle(selectProfile.type.instruction.name, for: .normal)
        
        self.sphasesView.isHidden = false
        self.sphasesView.snp.updateConstraints { make in
            make.height.greaterThanOrEqualTo(SCRYFrom(self.selectProfile.lightData.times.count > 0 ? 344 : 264))
        }
        self.sphasesView.profile = self.selectProfile
        self.timeoutView.second = self.selectProfile.manualOverrideTimeout
        
        let data = self.selectProfile.lightControlData
        self.powerUpBehaviorView.lightnessSliderView.slider.limitRange = data.lowEndTrim...data.highEndTrim
        self.powerUpBehaviorView.powerState = self.selectProfile.powerUpState
        self.powerUpBehaviorView.powerOnCct = self.selectProfile.powerUpCct
        
        self.sensitivityView.sensitivity = self.selectProfile.sensitivity
        self.adjustSpeedView.adjustSpeed = self.selectProfile.adjustSpeed
        
        if selectProfile.type == .proximityLighting {
            dayPhasesView?.isHidden = true
            nightPhasesView?.isHidden = true
            nightDayIlluminanceView?.isHidden = true
            if proximityLightingStepView == nil || proximityLightingNumberView == nil {
                setupProximityLightingUI()
            }

            proximityLightingNumberView?.number = self.selectProfile.proximityLightingNumber
            proximityLightingStepView?.isHidden = false
            proximityLightingStepView?.message = "profile_predictive_lighting_message".localizedString
            proximityLightingStepView?.stepView.lineWidth = SCRXFrom(40)
            proximityLightingStepView?.stepView.steps = [
                .init(imageName: "proximity_lighting_step1", title: "save_profile".localizedString, textColor: TextBlack_Color),
                .init(imageName: "proximity_lighting_step2", title: "add_devices_to_the_group".localizedString, textColor: TextBlack_Color),
                .init(imageName: "proximity_lighting_step3", title: "set_the_path_sequence".localizedString, textColor: TextBlack_Color)
            ]
            proximityLightingNumberView?.isHidden = false
            sphasesView.snp.remakeConstraints { make in
                make.left.equalTo(contentMargin)
                make.right.equalTo(-contentMargin)
                make.top.equalTo(proximityLightingNumberView!.snp.bottom).offset(contentMargin)
                make.height.greaterThanOrEqualTo(SCRYFrom(selectProfile.lightData.times.count > 0 ? 344 : 264))
            }
            
        }else if selectProfile.type == .proximityLightingWithPhotocell {
            if dayPhasesView == nil || nightPhasesView == nil || nightDayIlluminanceView == nil {
                setupProximityLightingWithPhotocellUI()
            }else {
                dayPhasesView?.isHidden = false
                nightPhasesView?.isHidden = false
                nightDayIlluminanceView?.isHidden = false
            }
            proximityLightingNumberView?.number = self.selectProfile.proximityLightingNumber
            proximityLightingStepView?.message = "profile_predictive_lighting_with_photocell_message".localizedString
            proximityLightingStepView?.stepView.lineWidth = SCRXFrom(20)
            proximityLightingStepView?.stepView.steps = [
                .init(imageName: "proximity_lighting_step1", title: "save_profile".localizedString, textColor: TextBlack_Color),
                .init(imageName: "proximity_lighting_step2", title: "add_devices_to_the_group".localizedString, textColor: TextBlack_Color),
                .init(imageName: "proximity_lighting_step3", title: "set_the_path_sequence".localizedString, textColor: TextBlack_Color),
                .init(imageName: "proximity_lighting_step4", title: "set_night_day_lux_threshold".localizedString, textColor: TextBlack_Color)
            ]
            proximityLightingStepView?.isHidden = false
            proximityLightingNumberView?.isHidden = false
            sphasesView.isHidden = true
//            sphasesView.snp.remakeConstraints { make in
//                make.left.equalTo(contentMargin)
//                make.right.equalTo(-contentMargin)
//                make.top.equalTo(proximityLightingNumberView!.snp.bottom).offset(contentMargin)
//                make.height.greaterThanOrEqualTo(SCRYFrom(selectProfile.lightData.times.count > 0 ? 344 : 264))
//            }
        
            if let dayData = self.selectProfile.dayData {
                nightDayIlluminanceView?.dayStartsAboveLux = Int(dayData.startsBelowLux)
                dayPhasesView?.updateData(profile: self.selectProfile, conditionData: dayData)
            }
            if let nightData = self.selectProfile.nightData {
                nightDayIlluminanceView?.nightStartsBelowLux = Int(nightData.startsBelowLux)
                nightPhasesView?.updateData(profile: self.selectProfile, conditionData: nightData)
            }
            updateNightDayIlluminanceThresholdDeviceDetail()
            
        } else {
            proximityLightingStepView?.isHidden = true
            proximityLightingNumberView?.isHidden = true
            dayPhasesView?.isHidden = true
            nightPhasesView?.isHidden = true
            nightDayIlluminanceView?.isHidden = true
            
            sphasesView.snp.remakeConstraints { make in
                make.left.equalTo(contentMargin)
                make.right.equalTo(-contentMargin)
                make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(13))
                make.height.greaterThanOrEqualTo(SCRYFrom(selectProfile.lightData.times.count > 0 ? 344 : 264))
            }
        }
        // 是否显示灯光调节速率
        var showLightAdjustSpeed = false
        // 是否显示手动控制超时UI
        var showTimeout = true
        // 是否显示灵敏度
        var showSensitivity = true
        
        if selectProfile.type == .daylight || selectProfile.type == .manualControl {
            if selectProfile.type == .manualControl {
                showTimeout = false
            }
            showSensitivity = false
        }
        
        if selectProfile.type == .occupancy_daylight || selectProfile.type == .vacancy_daylight || selectProfile.type == .daylight {
            showLightAdjustSpeed = true
        }
        
        if showTimeout {
            timeoutView.snp.remakeConstraints { make in
                make.left.right.equalTo(sphasesView)
                if let nightDayIlluminanceView = self.nightDayIlluminanceView, !nightDayIlluminanceView.isHidden {
                    make.top.equalTo(nightDayIlluminanceView.snp.bottom).offset(contentMargin)
                }else {
                    make.top.equalTo(sphasesView.snp.bottom).offset(contentMargin)
                }
                
                make.height.equalTo(SCRYFrom(140))
            }
        }
        
       
        adjustSpeedView.isHidden = !showLightAdjustSpeed
        timeoutView.isHidden = !showTimeout
        sensitivityView.isHidden = !showSensitivity
        if !showSensitivity {
            sensitivityView.snp.removeConstraints()
        }
        
        powerUpBehaviorView.snp.remakeConstraints { make in
            make.left.right.equalTo(timeoutView)
            if showTimeout {
                make.top.equalTo(timeoutView.snp.bottom).offset(contentMargin)
            }else {
                if let nightDayIlluminanceView = self.nightDayIlluminanceView, !nightDayIlluminanceView.isHidden {
                    make.top.equalTo(nightDayIlluminanceView.snp.bottom).offset(contentMargin)
                }else {
                    make.top.equalTo(sphasesView.snp.bottom).offset(contentMargin)
                }
            }
            make.height.greaterThanOrEqualTo(SCRYFrom(172))
            if !showSensitivity && !showLightAdjustSpeed {
                make.bottom.equalTo(-contentMargin)
            }
        }
        
        if showSensitivity {
            sensitivityView.snp.remakeConstraints { make in
                make.left.right.equalTo(powerUpBehaviorView)
                make.top.equalTo(powerUpBehaviorView.snp.bottom).offset(contentMargin)
                make.height.equalTo(SCRYFrom(130))
                if !showLightAdjustSpeed {
                    make.bottom.equalTo(-contentMargin)
                }
            }
        }
        
        if showLightAdjustSpeed {
            adjustSpeedView.snp.remakeConstraints { make in
                make.left.right.equalTo(sphasesView)
                if showSensitivity {
                    make.top.equalTo(sensitivityView.snp.bottom).offset(contentMargin)
                }else {
                    make.top.equalTo(powerUpBehaviorView.snp.bottom).offset(contentMargin)
                }
                make.height.equalTo(SCRYFrom(104))
                make.bottom.equalTo(-contentMargin)
            }
        }
        
    }
    
    /// 更新设备lux与组的提示信息
    private func updateNightDayIlluminanceThresholdDeviceDetail() {
        guard let nightDayIlluminanceView = self.nightDayIlluminanceView else {
            return
        }
        
        guard let groupNightLux = nightDayIlluminanceView.nightStartsBelowLux, let groupDayLux = nightDayIlluminanceView.dayStartsAboveLux else {
            nightDayIlluminanceView.updateDeviceDetailMessage(state: .none)
            return
        }
        
        if let group = self.group, group.nodes.count > 0 {
            // 检查是否有设备与组设置的lux条件不一样
            if group.nodes.contains(where: { node in
                if let nightLux = node.preConfiguration.nightProfileStartsBelowLux, nightLux != groupNightLux {
                    return true
                }
                if let dayLux = node.preConfiguration.dayProfileStartsAboveLux, dayLux != groupDayLux {
                    return true
                }
                return false
            }) {
                nightDayIlluminanceView.updateDeviceDetailMessage(state: .someDifferentGroup)
            }else {
                nightDayIlluminanceView.updateDeviceDetailMessage(state: .allSameGroup)
            }
      
        }else {
            nightDayIlluminanceView.updateDeviceDetailMessage(state: .noDevices)
        }
        
    }
        
    private func setupUI() {
        
        scrollView = UIScrollView()
//        scrollView.showsVerticalScrollIndicator = false
        scrollView.enableKeyboardDismissal()
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
//            make.top.equalTo(navigationController?.navigationBar.height ?? kNavigationHeight)
            make.top.equalTo(view.safeAreaLayoutGuide)
        }
        
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        headerView = ProfileSettingsHeaderView()
        headerView.delegate = self
        contentView.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(76))
        }
        
        sphasesView = ProfileSettingsSphasesView()
        sphasesView.delegate = self
        contentView.addSubview(sphasesView)
        sphasesView.snp.makeConstraints { make in
            make.left.equalTo(contentMargin)
            make.right.equalTo(-contentMargin)
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(13))
            make.height.greaterThanOrEqualTo(SCRYFrom(selectProfile.lightData.times.count > 0 ? 344 : 264))
        }
        
//        daylightSensorView = ProfileDaylightSensorControlView()
//        daylightSensorView.delegate = self
//        contentView.addSubview(daylightSensorView)
//        daylightSensorView.snp.makeConstraints { make in
//            make.left.right.equalTo(sphasesView)
//            make.top.equalTo(sphasesView.snp.bottom).offset(SCRYFrom(16))
//            make.height.equalTo(SCRYFrom(140))
//            
//        }
        
        timeoutView = ProfileManualOverrideTimeoutView()
        timeoutView.delegate = self
        timeoutView.editable = self.editable
        contentView.addSubview(timeoutView)
        timeoutView.snp.makeConstraints { make in
//            make.left.right.equalTo(daylightSensorView)
//            make.top.equalTo(daylightSensorView.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalTo(sphasesView)
            make.top.equalTo(sphasesView.snp.bottom).offset(contentMargin)
            make.height.equalTo(SCRYFrom(140))
        }
        
        powerUpBehaviorView = ProfilePowerUpBehaviorView()
        powerUpBehaviorView.delegate = self
        powerUpBehaviorView.editable = self.editable
        contentView.addSubview(powerUpBehaviorView)
        powerUpBehaviorView.snp.makeConstraints { make in
            make.left.right.equalTo(timeoutView)
            make.top.equalTo(timeoutView.snp.bottom).offset(contentMargin)
            make.height.greaterThanOrEqualTo(SCRYFrom(172))
            make.bottom.equalTo(-contentMargin)
        }
        
        sensitivityView = ProfileSensitivityView()
        sensitivityView.editable = self.editable
        sensitivityView.delegate = self
        sensitivityView.isHidden = true
        contentView.addSubview(sensitivityView)
        sensitivityView.snp.makeConstraints { make in
            make.left.right.equalTo(powerUpBehaviorView)
            make.top.equalTo(powerUpBehaviorView.snp.bottom).offset(contentMargin)
            make.height.equalTo(SCRYFrom(130))
        }
        
        adjustSpeedView = LightSensorCalibrationAdjustSpeedView()
        adjustSpeedView.delegate = self
        adjustSpeedView.editable = self.editable
        adjustSpeedView.isHidden = true
        contentView.addSubview(adjustSpeedView)
        adjustSpeedView.snp.makeConstraints { make in
            make.left.right.equalTo(sphasesView)
            make.top.equalTo(powerUpBehaviorView.snp.bottom).offset(contentMargin)
            make.height.equalTo(SCRYFrom(104))
        }
    }
    
    private func setupProximityLightingUI() {
        
        if proximityLightingStepView == nil {
            proximityLightingStepView = ProfileProximityLightingStepView()
            contentView.addSubview(proximityLightingStepView!)
            proximityLightingStepView!.snp.makeConstraints { make in
                make.left.right.equalTo(sphasesView)
                make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(13))
            }
        }
            
        if proximityLightingNumberView == nil {
            proximityLightingNumberView = ProfileProximityLightingNumberView()
            proximityLightingNumberView?.delegate = self
            contentView.addSubview(proximityLightingNumberView!)
            proximityLightingNumberView!.snp.makeConstraints { make in
                make.left.right.equalTo(proximityLightingStepView!)
                make.top.equalTo(proximityLightingStepView!.snp.bottom).offset(contentMargin)
                make.height.equalTo(SCRYFrom(240))
            }
        }
    }
    
    private func setupProximityLightingWithPhotocellUI() {
        
        if proximityLightingStepView == nil {
            proximityLightingStepView = ProfileProximityLightingStepView()
            contentView.addSubview(proximityLightingStepView!)
            proximityLightingStepView!.snp.makeConstraints { make in
                make.left.right.equalTo(sphasesView)
                make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(13))
            }
        }
        
        if proximityLightingNumberView == nil {
            proximityLightingNumberView = ProfileProximityLightingNumberView()
            proximityLightingNumberView?.delegate = self
            contentView.addSubview(proximityLightingNumberView!)
            proximityLightingNumberView!.snp.makeConstraints { make in
                make.left.right.equalTo(proximityLightingStepView!)
                make.top.equalTo(proximityLightingStepView!.snp.bottom).offset(contentMargin)
                make.height.equalTo(SCRYFrom(240))
            }
        }
        
        nightPhasesView = ProfileTriggerConditionPhasesView()
        nightPhasesView!.titleLabel.text = "night".localizedString
//        nightPhasesView!.startsBelowLabel.text = "starts_below".localizedString
        nightPhasesView!.editable = self.editable
        nightPhasesView!.delegate = self
        contentView.addSubview(nightPhasesView!)
        nightPhasesView!.snp.makeConstraints { make in
            make.left.right.equalTo(proximityLightingNumberView!)
            make.top.equalTo(proximityLightingNumberView!.snp.bottom).offset(contentMargin)
            make.height.greaterThanOrEqualTo(SCRYFrom(170))
        }
        
        dayPhasesView = ProfileTriggerConditionPhasesView()
        dayPhasesView!.titleLabel.text = "day".localizedString
//        dayPhasesView!.startsBelowLabel.text = "starts_above".localizedString
        dayPhasesView!.editable = self.editable
        dayPhasesView!.delegate = self
        contentView.addSubview(dayPhasesView!)
        dayPhasesView!.snp.makeConstraints { make in
            make.left.right.equalTo(nightPhasesView!)
            make.top.equalTo(nightPhasesView!.snp.bottom).offset(contentMargin)
            make.height.greaterThanOrEqualTo(SCRYFrom(170))
        }
        
        nightDayIlluminanceView = ProfileNightDayIlluminanceThresholdView()
        nightDayIlluminanceView!.editable = self.editable
        nightDayIlluminanceView!.delegate = self
        contentView.addSubview(nightDayIlluminanceView!)
        nightDayIlluminanceView!.snp.makeConstraints { make in
            make.left.right.equalTo(dayPhasesView!)
            make.top.equalTo(dayPhasesView!.snp.bottom).offset(contentMargin)
            make.height.greaterThanOrEqualTo(SCRYFrom(200))
        }
    }

}

extension ProfileSettingsViewController: NavigationViewControllerDelegate {

    /// 点击返回item回调
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
        exitAction()
    }
    
    /// pop手势begin回调，返回是否可以pop
    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool {
        if initProfile == nil || selectProfile == initProfile! {
            return true
        }else {
            exitAction()
            return false
        }
    }
    
}

extension ProfileSettingsViewController: ProfileSettingsHeaderViewDelegate {
    
    /// 名称编辑回调
    /// - Parameters:
    ///   - view: view
    ///   - name: 名称
    /// - Returns: 返回错误提示（可选）
    func view(_ view: ProfileSettingsHeaderView, nameEditChanged name: String) -> String? {
        return nil
    }
    
    /// 选择配置文件回调
    func headerViewDidSelectProfile(_ view: ProfileSettingsHeaderView, profileRect: CGRect) {
        
        guard editable else {
            return
        }
        
        let names = profiles.map({ $0.type.instruction.name })
        
//        view
        let viewPoint = contentView.convert(CGPoint(x: profileRect.minX, y: profileRect.maxY + 2), from: view)
        let windowPoint = view.convert(viewPoint, to: UIApplication.shared.keyWindow())
        
        let selectIndex = profiles.firstIndex(where: { $0.type == selectProfile.type }) ?? 0
        
        TitleSelectView.show(titles: names, anchorPoint: windowPoint, selectIndex: selectIndex, menuWidth: profileRect.size.width, titleColor: SubText_Color, titleFont: FONTS(SCRXFrom(12)), backgroundColor: .white, selectBackgroundColor: .clear, shadowColor: RGB(0, 0, 0, 0.1)) {[weak self] index in
            guard let self = self else { return }
            self.selectProfile = self.profiles[index]
            self.initProfile = self.selectProfile.copy()
            self.updateUI()
        }
        
    }
    
    /// 点击帮助回调
    func headerViewHelpAction(_ view: ProfileSettingsHeaderView) {
        navigationController?.pushViewController(ProfileInstructionsController(), animated: true)
    }
       
}

extension ProfileSettingsViewController: ProfileSettingsSphasesViewDelegate {
    
    /// 帮助
    func sphasesViewHelpAction(_ view: ProfileSettingsSphasesView) {
        
        let vc = MotionSensorInstructionsController(profile: selectProfile)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// High-end/Low-end trim
    func sphasesViewHighAndLowEndTrimAction(_ view: ProfileSettingsSphasesView) {
        guard editable else {
            return
        }
        let data = selectProfile.lightControlData
        showLevelSettings(type: .highLowEndTrim(high: data.highEndTrim, low: data.lowEndTrim))
    }
    
    /// Occupancy/Vacant level
    func sphasesViewOccupancyAndVacantLevelAction(_ view: ProfileSettingsSphasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        let data = selectProfile.lightControlData
        switch selectProfile.type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            // Occupancy sensing with daylight harvesting / Vacancy sensing with daylight harvesting / Daylight harvesting
            // TODO: 判断是否已校准
            if let sensorNode = group?.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil { // , sensorNode.sensorCalibrated
//                showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
//                if sensorNode.sensorCalibrated {
//                    showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
//                }else {
                    let levelAction = SRAlertAction(title: "Level", style: .default, actionHandler: {[weak self] _ in
                        self?.showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
                    })
                    let luxAction = SRAlertAction(title: "Lux", style: .default) {[weak self] _ in
                        self?.showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, calibrated: false))
                    }
                    SRSheetView(actions: [levelAction, luxAction]).show()
//                }
                
                
            }else {
                // 未校准
                showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, calibrated: false))
            }
        default:
            // Occupancy sensing / Vacancy sensing / Manual control
            showLevelSettings(type: .occupancyAndVacantLevel(occupanyLevel: data.occupancyLevel, vacantLevel: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim))
        }
        
    }
    
    /// Auto min level
    func sphasesViewAutoMinValueAction(_ view: ProfileSettingsSphasesView) {
        guard editable else {
            return
        }
        let data = selectProfile.lightControlData
        showLevelSettings(type: .autoMinValue(level: data.autoMinLevel, inputRange: data.lowEndTrim...data.highEndTrim, enabled: data.autoMinLevelEnabled))
    }
    
    /// Task level (%/lx)
    func sphasesViewTaskLevelAction(_ view: ProfileSettingsSphasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        let data = selectProfile.lightControlData
        switch selectProfile.type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            // Occupancy sensing with daylight harvesting / Vacancy sensing with daylight harvesting / Daylight harvesting
            // TODO: 判断是否已校准
            if let sensorNode = group?.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil { // , sensorNode.sensorCalibrated
//                if sensorNode.sensorCalibrated {
//                    showLevelSettings(type: .taskLux(lux: data.taskLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
//                }else {
                    let levelAction = SRAlertAction(title: "Level", style: .default, actionHandler: {[weak self] _ in
                        self?.showLevelSettings(type: .taskLux(lux: data.taskLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
                    })
                    let luxAction = SRAlertAction(title: "Lux", style: .default) {[weak self] _ in
                        self?.showLevelSettings(type: .taskLux(lux: data.taskLevel, calibrated: false))
                    }
                    SRSheetView(actions: [levelAction, luxAction]).show()
//                }

            }else { // 未校准
                showLevelSettings(type: .taskLux(lux: data.taskLevel, calibrated: false))
            }
        default:
            // Occupancy sensing / Vacancy sensing / Manual control
            showLevelSettings(type: .taskLevel(level: data.taskLevel, inputRange: data.lowEndTrim...data.highEndTrim))
        }
    }
    
    /// Time  T1/T2/T3/T4/T5
    func view(_ view: ProfileSettingsSphasesView, timeAction timeType: Profile.LightData.TimePickerData.TimeType) {
        guard editable else {
            return
        }
        showTimeSettings(type: timeType)
    }
    
}

extension ProfileSettingsViewController: ProfileDaylightSensorControlViewDelegate {
    
    /// 帮助
    func daylightSensorViewHelpAction(view: ProfileDaylightSensorControlView) {
        navigationController?.pushViewController(DaylightSensorInstructionsController(), animated: true)
    }
    
    /// 选择传感器
    func daylightSensorViewSelectAction(view: ProfileDaylightSensorControlView) {
        
        
    }
}

extension ProfileSettingsViewController: ProfileManualOverrideTimeoutViewDelegate {
    
    /// 不可编辑状态下修改参数回调
    func timeoutViewDisableEditAction(view: ProfileManualOverrideTimeoutView) {
        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
    }
    
    
    /// 帮助
    func timeoutViewHelpAction(view: ProfileManualOverrideTimeoutView) {
//        let vc = ProfileTeletextInstructionsController(vcTitle: "Manual override timeout instruction", richText: NSAttributedString(), headerView: nil)
        
        navigationController?.pushViewController(ManualOverrideTimeoutInstructionController(), animated: true)
    }
    
    /// 手动控制超时时长修改
    /// - Parameters:
    ///   - view: view
    ///   - second: 秒 max：不启用 >0：启用
    func view(_ view: ProfileManualOverrideTimeoutView, timeoutValueChanged second: UInt32) {
        
        selectProfile.manualOverrideTimeout = second
        
    }
}

extension ProfileSettingsViewController: ProfilePowerUpBehaviorViewDelegate {
    /// 禁止交互下编辑事件
    func powerUpBehaviorViewDisableEditAction(view: ProfilePowerUpBehaviorView) {
        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
    }
    
    /// 帮助
    func powerUpBehaviorViewHelpAction(view: ProfilePowerUpBehaviorView) {
        
        navigationController?.pushViewController(PowerUpBehaviorInstructionController(), animated: true)
//        navigationController?.pushViewController(AdjustSpeedInstructionController(), animated: true)
        
    }
    
    /// 上电状态
    /// - Parameters:
    ///   - view: view
    ///   - state: 上电状态
    ///   - powerOnCct: 上电色温）
    func view(_ view: ProfilePowerUpBehaviorView, powerStateChanged state: Profile.PowerUpState, powerOnCct: UInt16?) {
        selectProfile.powerUpState = state
        if let cct = powerOnCct {
            selectProfile.powerUpCct = cct
        }
    }
    
}


extension ProfileSettingsViewController: ProfileSensitivityViewDelegate {
    
    /// 灵敏度修改
    /// - Parameters:
    ///   - view: view
    ///   - sensitivity: 灵敏度0~100%
    func view(_ view: ProfileSensitivityView, sensitivityValueChanged sensitivity: UInt8) {
        selectProfile.sensitivity = sensitivity
    }
    
    /// 禁止交互下编辑事件
    func sensitivityViewDisableEditAction(view: ProfileSensitivityView) {
        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
    }
    
    /// 帮助
    func sensitivityViewHelpAction(_ view: ProfileSensitivityView) {
        navigationController?.pushViewController(RelativeSensitivityInstructionsController(), animated: true)
    }
    
}

extension ProfileSettingsViewController: ProfileProximityLightingNumberViewDelegate {
    
    /// 邻近照明数量修改
    /// - Parameters:
    ///   - view: view
    ///   - number: 数量 0-5 | 255
    func view(_ view: ProfileProximityLightingNumberView, lightingNumberChanged number: UInt8) {
        
        selectProfile.proximityLightingNumber = number
    }
    
    /// 禁止交互下编辑事件
    func proximityLightingNumberViewDisableEditAction(view: ProfileProximityLightingNumberView) {
        XWHUDManager.showTipHUD("no_permission".localizedString + "！")
    }
    
    /// 帮助
    func proximityLightingNumberViewHelpAction(_ view: ProfileProximityLightingNumberView) {
        navigationController?.pushViewController(NumberOfNeghbourNodeInstructionsController(), animated: true)
    }
    
}

extension ProfileSettingsViewController: ProfileTriggerConditionPhasesViewDelegate {
    
    /// 帮助
    func phasesViewHelpAction(_ view: ProfileTriggerConditionPhasesView) {
        
        let vc = ProfileTextInstructionsViewController(vcTitle: "night_day_mode_description".localizedString, instructions: [ProfileTextInstructionInfo(title: "night".localizedString, content: "night_mode_description_note".localizedString), ProfileTextInstructionInfo(title: "day".localizedString, content: "day_mode_description_note".localizedString)])
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// Phases帮助
    func phasesViewPhasesHelpAction(_ view: ProfileTriggerConditionPhasesView) {
        let vc = MotionSensorInstructionsController(profile: selectProfile)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// High-end/Low-end trim
    func phasesViewHighAndLowEndTrimAction(_ view: ProfileTriggerConditionPhasesView) {
        guard editable else {
            return
        }
        let data = selectProfile.lightControlData
        var phasesType: AutomationPhasesType = .default
        if view == dayPhasesView {
//            if let dayData = selectProfile.dayData {
//                data = dayData.sceneData.lightControlData
//            }
            phasesType = .day
        }else {
//            if let nightData = selectProfile.nightData {
//                data = nightData.sceneData.lightControlData
//            }
            phasesType = .night
        }
        
        showLevelSettings(type: .highLowEndTrim(high: data.highEndTrim, low: data.lowEndTrim), phasesType: phasesType)
    }
    
    /// Occupancy/Vacant level
    func phasesViewOccupancyAndVacantLevelAction(_ view: ProfileTriggerConditionPhasesView) {
     
        guard editable else {
            return
        }
        // 判断配置类型
        var data = selectProfile.lightControlData
        var phasesType: AutomationPhasesType = .default
        if view == dayPhasesView {
            if let dayData = selectProfile.dayData {
                data = dayData.sceneData.lightControlData
            }
            phasesType = .day
        }else {
            if let nightData = selectProfile.nightData {
                data = nightData.sceneData.lightControlData
            }
            phasesType = .night
        }
        
        switch selectProfile.type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            // Occupancy sensing with daylight harvesting / Vacancy sensing with daylight harvesting / Daylight harvesting
            // TODO: 判断是否已校准
            if let sensorNode = group?.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil {
                    let levelAction = SRAlertAction(title: "Level", style: .default, actionHandler: {[weak self] _ in
                        self?.showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true), phasesType: phasesType)
                    })
                    let luxAction = SRAlertAction(title: "Lux", style: .default) {[weak self] _ in
                        self?.showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, calibrated: false), phasesType: phasesType)
                    }
                    SRSheetView(actions: [levelAction, luxAction]).show()
            }else {
                // 未校准
                showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, calibrated: false), phasesType: phasesType)
            }
        default:
            // Occupancy sensing / Vacancy sensing / Manual control
            showLevelSettings(type: .occupancyAndVacantLevel(occupanyLevel: data.occupancyLevel, vacantLevel: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim), phasesType: phasesType)
        }
        
    }
    
    /// Standby level
    func phasesViewStandbyLevelAction(_ view: ProfileTriggerConditionPhasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        var data = selectProfile.lightControlData
        var phasesType: AutomationPhasesType = .default
        if view == dayPhasesView {
            if let dayData = selectProfile.dayData {
                data = dayData.sceneData.lightControlData
            }
            phasesType = .day
        }else {
            if let nightData = selectProfile.nightData {
                data = nightData.sceneData.lightControlData
            }
            phasesType = .night
        }
        showLevelSettings(type: .standbyLevel(value: data.standbyLevel, inputRange: max(1, data.lowEndTrim)...data.highEndTrim), phasesType: phasesType)
    }
    
    /// Auto min level
    func phasesViewAutoMinValueAction(_ view: ProfileTriggerConditionPhasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        var data = selectProfile.lightControlData
        var phasesType: AutomationPhasesType = .default
        if view == dayPhasesView {
            if let dayData = selectProfile.dayData {
                data = dayData.sceneData.lightControlData
            }
            phasesType = .day
        }else {
            if let nightData = selectProfile.nightData {
                data = nightData.sceneData.lightControlData
            }
            phasesType = .night
        }
        
        showLevelSettings(type: .autoMinValue(level: data.autoMinLevel, inputRange: data.lowEndTrim...data.highEndTrim, enabled: data.autoMinLevel != 255), phasesType: phasesType)
    }
    
    /// Task level (%/lx)
    func phasesViewTaskLevelAction(_ view: ProfileTriggerConditionPhasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        
        var data = selectProfile.lightControlData
        var phasesType: AutomationPhasesType = .default
        if view == dayPhasesView {
            if let dayData = selectProfile.dayData {
                data = dayData.sceneData.lightControlData
            }
            phasesType = .day
        }else {
            if let nightData = selectProfile.nightData {
                data = nightData.sceneData.lightControlData
            }
            phasesType = .night
        }
        
        switch selectProfile.type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            // Occupancy sensing with daylight harvesting / Vacancy sensing with daylight harvesting / Daylight harvesting
            // TODO: 判断是否已校准
            if let sensorNode = group?.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil {
                let levelAction = SRAlertAction(title: "Level", style: .default, actionHandler: {[weak self] _ in
                    self?.showLevelSettings(type: .taskLux(lux: data.taskLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true), phasesType: phasesType)
                })
                let luxAction = SRAlertAction(title: "Lux", style: .default) {[weak self] _ in
                    self?.showLevelSettings(type: .taskLux(lux: data.taskLevel, calibrated: false), phasesType: phasesType)
                }
                SRSheetView(actions: [levelAction, luxAction]).show()
            }else { // 未校准
                showLevelSettings(type: .taskLux(lux: data.taskLevel, calibrated: false), phasesType: phasesType)
            }
        default:
            // Occupancy sensing / Vacancy sensing / Manual control
            showLevelSettings(type: .taskLevel(level: data.taskLevel, inputRange: data.lowEndTrim...data.highEndTrim), phasesType: phasesType)
        }
    }
    
    /// Time  T1/T2/T3/T4/T5
    func view(_ view: ProfileTriggerConditionPhasesView, timeAction timeType: Profile.LightData.TimePickerData.TimeType) {
        guard editable else {
            return
        }
        var phasesType: AutomationPhasesType = .default
        if view == dayPhasesView {
            phasesType = .day
        }else {
            phasesType = .night
        }
        
        showTimeSettings(type: timeType, phasesType: phasesType)
    }
    
    /// 编辑输入条件lux回调
    func view(_ view: ProfileTriggerConditionPhasesView, startsBelowLuxEditChanged lux: Int?) {
        
    }
    
    /// 使用校准值帮助
    func phasesViewUseCalibrationValuesHelpAction(_ view: ProfileTriggerConditionPhasesView) {
        
    }
    
    /// 启用/禁用使用校准值回调
    func view(_ view: ProfileTriggerConditionPhasesView, useCalibrationValues enabled: Bool) {
        if view == dayPhasesView {
            selectProfile.dayData?.useCalibrationValues = enabled
        }else {
            selectProfile.nightData?.useCalibrationValues = enabled
        }
    }
    
    /// 选择执行数据类型回调
    func view(_ view: ProfileTriggerConditionPhasesView, selectExecuteType executeType: Profile.TriggerConditionData.ExecuteType) {
        if view == dayPhasesView {
            if let dayData = selectProfile.dayData {
                dayData.executeType = executeType
                view.updateData(profile: selectProfile, conditionData: dayData)
            }
        }else {
            if let nightData = selectProfile.nightData {
                nightData.executeType = executeType
                view.updateData(profile: selectProfile, conditionData: nightData)
            }
        }
    }
    
    /// 固定亮度-Standby level编辑回调
    func view(_ view: ProfileTriggerConditionPhasesView, fixedLevelValueChnaged standbyLevel: Int) {
        
        if view == dayPhasesView {
            selectProfile.dayData?.fixedStandbyLevel = standbyLevel
        }else {
            selectProfile.nightData?.fixedStandbyLevel = standbyLevel
        }
    }
    
}

extension ProfileSettingsViewController: ProfileNightDayIlluminanceThresholdViewDelegate {
    
    /// 帮助
    func nightDayIlluminanceThresholdViewHelpAction(_ view: ProfileNightDayIlluminanceThresholdView) {
        
        let instructions = [
            ProfileTextInstructionInfo(title: "night_starts_below_lux".localizedString, content: "night_starts_below_lux_note".localizedString),
            ProfileTextInstructionInfo(title: "day_starts_above_lux".localizedString, content: "day_starts_above_lux_note".localizedString),
            ProfileTextInstructionInfo(title: "important_notes".localizedString, content: "important_notes_note".localizedString)
        ]
        
        let vc = ProfileTextInstructionsViewController(vcTitle: "night_day_illuminance_threshold".localizedString, instructions: instructions)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 编辑晚上输入条件lux回调
    func view(_ view: ProfileNightDayIlluminanceThresholdView, nightStartsBelowLuxEditChanged lux: Int?) {
        updateNightDayIlluminanceThresholdDeviceDetail()
    }
    
    /// 编辑白天输入条件lux回调
    func view(_ view: ProfileNightDayIlluminanceThresholdView, dayStartsAboveLuxEditChanged lux: Int?) {
        updateNightDayIlluminanceThresholdDeviceDetail()
    }
    
    /// 设备详情
    func nightDayIlluminanceThresholdViewDeviceDetailAction(_ view: ProfileNightDayIlluminanceThresholdView) {
        
        var setMode: ProfileDayNightLuxSetMode = .saveAndSync
        if group == nil || group!.info.profile.type != selectProfile.type {
            setMode = .onlySet
        }
        let vc = ProfileDayNightLuxViewController(profile: self.selectProfile, groupNodes: group?.nodes ?? [], setMode: setMode)
        vc.templates = selectProfile.lightSensorTemplates
        vc.templatesSetCallback = {[weak self] templates in
            guard let self = self else { return }
            self.selectProfile.lightSensorTemplates = templates
            if self.selectProfile.type == .proximityLightingWithPhotocell, setMode == .saveAndSync {
                ProfileLightSensorTemplate.delete(profileId: self.selectProfile.id)
                templates.forEach {
                    $0.save(profileId: self.selectProfile.id)
                }
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
}



extension ProfileSettingsViewController: LightSensorCalibrationAdjustSpeedViewDelegate {
    
    /// 调节速率修改回调
    /// - Parameters:
    ///   - view: view
    ///   - speed: 0~100
    func view(_ view: LightSensorCalibrationAdjustSpeedView, adjustSpeedChanged speed: Int) {
        selectProfile.adjustSpeed = speed
    }
    
    /// 点击调整速率帮助
    func calibrationAdjustSpeedHelpAction(_ view: LightSensorCalibrationAdjustSpeedView) {
        navigationController?.pushViewController(AdjustSpeedInstructionController(), animated: true)
    }
    
}
