//
//  ProfileSettingsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit
import NordicSigMeshSDK

class ProfileSettingsViewController: UIViewController {

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
    private let contentMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(16)
    
    /// 配置数据
    private var profiles: [Profile] = [
        .init(type: .occupancy_daylight),
        .init(type: .vacancy_daylight),
        .init(type: .occupancy),
        .init(type: .vacancy),
        .init(type: .daylight),
        .init(type: .manualControl)
    ]
    /// 选择的配置数据
    private var selectProfile: Profile!
    /// 初始的配置数据（判断是否编辑）
    private var initProfile: Profile?
    /// 使用配置的group
    let group: Group?
    /// 是否可编辑
    var editable: Bool = true
    /// 保存事件回调
    var saveActionCallback: ((Profile)->Void)?
    
    
    init(group: Group? = nil, profile: Profile) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
        self.selectProfile = profile.copy()
        self.initProfile = profile
        if let index = profiles.firstIndex(where: { $0.type == selectProfile.type }) {
            self.profiles.replaceSubrange(index...index, with: [selectProfile])
        }
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
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        (navigationController as? NavigationViewController)?.navigationDelegate = nil
    }

    private func exitAction() {
        
        if initProfile == nil || selectProfile == initProfile! {
            navigationController?.popViewController(animated: true)
        }else {
            SRAlertView(title: "notification".localizedString, message: "profile_exiting_message".localizedString, actions: [SRAlertAction(title: "keep_edit".localizedString, style: .cancel), SRAlertAction(title: "exit".localizedString, actionHandler: {[weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            })]).show()
        }
    }
    
    @objc private func saveAction() {
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
            vc.backActionCallback = {[weak self] in
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
    private func showLevelSettings(type: ProfileLevelSettingsView.LevelType) {
        
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
                                }else if let currentLux = sensorNode.daylightLux {
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
            switch result {
            case .highLowEndTrim(let high, let low):
                let range: ClosedRange<Int> = low...high
                self.selectProfile.lightData.updateLevel(lightType: .lightnessRange(low...high))
                // 更新最高/最低亮度输出，判断其它数据是否超出范围
                let data = self.selectProfile.lightData.data
                // 判断是否是亮度配置
                let levelConfig = self.selectProfile.type == .occupancy || self.selectProfile.type == .vacancy || self.selectProfile.type == .manualControl
                // level 百分比数据时修改最高最低亮度输出需判断其它阶段参数是否超出输出范围
                if levelConfig {
                    if !range.contains(data.occupancyLevel) {
                        self.selectProfile.lightData.updateLevel(lightType: .occupancyLevel(max(min(data.occupancyLevel, high), low)))
                    }
                    if !range.contains(data.vacantLevel) {
                        self.selectProfile.lightData.updateLevel(lightType: .vacantLevel(max(min(data.vacantLevel, high), low)))
                    }
                    
                    if !range.contains(data.taskLevel) {
                        self.selectProfile.lightData.updateLevel(lightType: .taskLevel(max(min(data.taskLevel, high), low)))
                    }
                }
                
                if data.autoMinLevelEnabled, !range.contains(data.autoMinLevel) {
                    self.selectProfile.lightData.updateLevel(lightType: .autoMinValue(max(min(data.autoMinLevel, high), low), enabled: data.autoMinLevelEnabled))
                }
                switch self.selectProfile.powerUpState {
                case .definedLightLevel(let level):
                    if !range.contains(data.occupancyLevel) { // 上电亮度不在亮度范围内
                        let value = max(min(Int(level), high), low)
                        self.selectProfile.powerUpState = .definedLightLevel(UInt8(value))
                        self.powerUpBehaviorView.powerState = self.selectProfile.powerUpState
                    }
                    fallthrough
                default:
                    self.powerUpBehaviorView.lightnessSliderView.slider.limitRange = range
                }
                    
            case .occupancyAndVacantLevel(let occupanyLevel, let vacantLevel):
                self.selectProfile.lightData.updateLevel(lightType: .occupancyLevel(occupanyLevel))
                self.selectProfile.lightData.updateLevel(lightType: .vacantLevel(vacantLevel))
            case .occupancyAndVacantLux(let occupanyLux, let vacantLux):
                self.selectProfile.lightData.updateLevel(lightType: .occupancyLevel(occupanyLux))
                self.selectProfile.lightData.updateLevel(lightType: .vacantLevel(vacantLux))
            case .taskLevel(let level):
                self.selectProfile.lightData.updateLevel(lightType: .taskLevel(level))
            case .taskLux(let lux):
                self.selectProfile.lightData.updateLevel(lightType: .taskLevel(lux))
            case .autoMinValue(let level, let enabled):
                self.selectProfile.lightData.updateLevel(lightType: .autoMinValue(enabled ? level : 0, enabled: enabled))
            }
            
            self.sphasesView.profile = self.selectProfile
            
        }.show()
        
    }
    
    private func showTimeSettings(type: Profile.LightData.TimePickerData.TimeType) {
        
        guard let timeData = Profile.LightData.TimePickerData.pickerTimes[type] else { return }
        
        let data = selectProfile.lightData.data
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
            let lightData = self.selectProfile.lightData
            switch type {
            case .t1:
                lightData.updateTime(time: .t1(second))
            case .t2:
                lightData.updateTime(time: .t2(second))
            case .t3:
                lightData.updateTime(time: .t3(second))
            case .t4:
                lightData.updateTime(time: .t4(second))
            case .t5:
                lightData.updateTime(time: .t5(second))
            }
            self.sphasesView.profile = self.selectProfile
        }.show()
        
    }
    
    private func updateUI() {
        
        self.headerView.profileBtn.setTitle(selectProfile.type.instruction.name, for: .normal)
        
        self.sphasesView.snp.updateConstraints { make in
            make.height.greaterThanOrEqualTo(SCRYFrom(self.selectProfile.lightData.times.count > 0 ? 344 : 264))
        }
        self.sphasesView.profile = self.selectProfile
        self.timeoutView.second = self.selectProfile.manualOverrideTimeout
        
        let data = self.selectProfile.lightData.data
        self.powerUpBehaviorView.lightnessSliderView.slider.limitRange = data.lowEndTrim...data.highEndTrim
        self.powerUpBehaviorView.powerState = self.selectProfile.powerUpState
        if self.group?.supportCct ?? false {
            self.powerUpBehaviorView.powerOnCct = self.selectProfile.powerUpCct
        }else {
            self.powerUpBehaviorView.powerOnCct = nil
        }
        
        if selectProfile.type == .daylight || selectProfile.type == .manualControl {
            timeoutView.isHidden = true
            powerUpBehaviorView.snp.remakeConstraints { make in
                make.left.right.equalTo(sphasesView)
                make.top.equalTo(sphasesView.snp.bottom).offset(SCRYFrom(16))
                make.height.greaterThanOrEqualTo(SCRYFrom(172))
                make.bottom.equalTo(SCRYFrom(-16))
            }
        }else {
            timeoutView.isHidden = false
            powerUpBehaviorView.snp.remakeConstraints { make in
                make.left.right.equalTo(timeoutView)
                make.top.equalTo(timeoutView.snp.bottom).offset(SCRYFrom(16))
                make.height.greaterThanOrEqualTo(SCRYFrom(172))
                make.bottom.equalTo(SCRYFrom(-16))
            }
        }
        
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
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
        let data = selectProfile.lightData.data
        showLevelSettings(type: .highLowEndTrim(high: data.highEndTrim, low: data.lowEndTrim))
    }
    
    /// Occupancy/Vacant level
    func sphasesViewOccupancyAndVacantLevelAction(_ view: ProfileSettingsSphasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        let data = selectProfile.lightData.data
        switch selectProfile.type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            // Occupancy sensing with daylight harvesting / Vacancy sensing with daylight harvesting / Daylight harvesting
            // TODO: 判断是否已校准
            if let sensorNode = group?.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil, sensorNode.sensorCalibrated {
                showLevelSettings(type: .occupancyAndVacantLux(occupanyLux: data.occupancyLevel, vacantLux: data.vacantLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
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
        let data = selectProfile.lightData.data
        showLevelSettings(type: .autoMinValue(level: data.autoMinLevel, inputRange: data.lowEndTrim...data.highEndTrim, enabled: data.autoMinLevelEnabled))
    }
    
    /// Task level (%/lx)
    func sphasesViewTaskLevelAction(_ view: ProfileSettingsSphasesView) {
        guard editable else {
            return
        }
        // 判断配置类型
        let data = selectProfile.lightData.data
        switch selectProfile.type {
        case .occupancy_daylight, .vacancy_daylight, .daylight:
            // Occupancy sensing with daylight harvesting / Vacancy sensing with daylight harvesting / Daylight harvesting
            // TODO: 判断是否已校准
            if let sensorNode = group?.info.ambientLightSensorNode, sensorNode.ambientLightSensorModel != nil, sensorNode.sensorCalibrated {
                showLevelSettings(type: .taskLux(lux: data.taskLevel, inputRange: data.lowEndTrim...data.highEndTrim, calibrated: true))
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

