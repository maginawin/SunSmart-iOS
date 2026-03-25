//
//  ProfileTriggerConditionPhasesView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/10.
//

import UIKit

protocol ProfileTriggerConditionPhasesViewDelegate: AnyObject {
    
    /// 帮助
    func phasesViewHelpAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// Phases帮助
    func phasesViewPhasesHelpAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// High-end/Low-end trim
    func phasesViewHighAndLowEndTrimAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// Occupancy/Vacant level
    func phasesViewOccupancyAndVacantLevelAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// Standby level
    func phasesViewStandbyLevelAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// Auto min level
    func phasesViewAutoMinValueAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// Task level (%/lx)
    func phasesViewTaskLevelAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// Time  T1/T2/T3/T4/T5
    func view(_ view: ProfileTriggerConditionPhasesView, timeAction timeType: Profile.LightData.TimePickerData.TimeType)
    
    /// 编辑输入条件lux回调
//    func view(_ view: ProfileTriggerConditionPhasesView, startsBelowLuxEditChanged lux: Int?)
    
    /// 使用校准值帮助
    func phasesViewUseCalibrationValuesHelpAction(_ view: ProfileTriggerConditionPhasesView)
    
    /// 启用/禁用使用校准值回调
    func view(_ view: ProfileTriggerConditionPhasesView, useCalibrationValues enabled: Bool)
    
    /// 选择执行数据类型回调
    func view(_ view: ProfileTriggerConditionPhasesView, selectExecuteType executeType: Profile.TriggerConditionData.ExecuteType)
    
    /// 固定亮度-Standby level编辑回调
    func view(_ view: ProfileTriggerConditionPhasesView, fixedLevelValueChnaged standbyLevel: Int)
    
}

class ProfileTriggerConditionPhasesView: UIView {

    var titleLabel: UILabel!
    private var helpBtn: UIButton!
    
//    var startsBelowLabel: UILabel!
//    private var luxField: UITextField!
//    private var luxLabel: UILabel!
//    private var luxTipLabel: UILabel!
    
//    private var useCalibrationLabel: UILabel!
//    private var useCalibrationHelpBtn: UIButton!
//    private var calibrationEnableSwitch: UISwitch!
    private var triggerTypeView: UIView!
    private var adjustOccupiedBtn: UIButton!
    private var fixedLevelBtn: UIButton!
    
    //************  Device trigger curve  **********/
    /// 设备执行view
    private var devicePhasesView: UIView!
    private var deviceTriggerLabel: UILabel!
    private var lightLevelImageView: UIImageView!
    private var phasesHelpBtn: UIButton!
    /// 阶段图
    private var chartImageView: UIImageView!
    
    //************  Light Level  **********/
    /// Max.light output
    private var maxLightOutputLabel: UILabel!
    /// High-end trim
    private var highEndTrimBtn: UIButton!
    private var highEndTrimLabel: UILabel!
    /// Occupancy level
    private var occupancyLevelBtn: UIButton!
    private var occupancyLevelLabel: UILabel!
    /// Vacant level
    private var vacantLevelBtn: UIButton!
    private var vacantLevelLabel: UILabel!
    /// Task Level
    private var taskLevelBtn: UIButton!
    private var taskLevelLabel: UILabel!
    /// Standby level
    private var phasesStandbyLevelBtn: UIButton!
    private var phasesStandbyLevelLabel: UILabel!
    
    /// Auto min level
    private var autoMinLevelBtn: UIButton!
    private var autoMinLevelLabel: UILabel!
    /// Low-end trim
    private var lowEndTrimBtn: UIButton!
    private var lowEndTrimLabel: UILabel!
    /// Off
    private var offLabel: UILabel!
    
    //************  Light Time  **********/
    /// T1
    private var timeT1Btn: UIButton!
    private var timeT1Label: UILabel!
    /// T2
    private var timeT2Btn: UIButton!
    private var timeT2Label: UILabel!
    /// T3
    private var timeT3Btn: UIButton!
    private var timeT3Label: UILabel!
    /// T4
    private var timeT4Btn: UIButton!
    private var timeT4Label: UILabel!
    /// T5
    private var timeT5Btn: UIButton!
    private var timeT5Label: UILabel!
    
    //************  Standby level  **********/
    private var standbyLevelView: UIView!
    private var standbyLevelTitleLabel: UILabel!
    private var standbyLevelLabel: UILabel!
    private var standbyLevelOffBtn: UIButton!
    private var standbyLevelSlider: CustomDeviceSlider!
    private var standbyLevelAddBtn: UIButton!
    private var standbyLevelMinusBtn: UIButton!
    
    weak var delegate: ProfileTriggerConditionPhasesViewDelegate?
    
//    var startsBelowLux: Int? {
//        get {
//            guard let inputText = luxField.text, let lux = Int(inputText) else { return nil }
//            return lux
//        }set {
//            luxField.text = newValue != nil ? "\(newValue!)" : nil
//        }
//    }
    
    var editable: Bool = true
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateData(profile: Profile, conditionData: Profile.TriggerConditionData) {
 
        let data = conditionData.sceneData.lightControlData
        
//        calibrationEnableSwitch.isOn = conditionData.useCalibrationValues
        
        switch conditionData.executeType {
        case .adjustWhenOccupied:
            
            adjustOccupiedBtn.isSelected = true
            fixedLevelBtn.isSelected = false
            
            timeT1Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t1, second: data.t1)
            timeT2Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t2, second: data.t2)
            timeT3Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t3, second: data.t3)
            timeT4Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t4, second: data.t4)
            timeT5Label.text =  Profile.LightData.TimePickerData.timeDetail(type: .t5, second: data.t5)
            
            highEndTrimLabel.text = "\(data.highEndTrim)%"
            lowEndTrimLabel.text = "\(data.lowEndTrim)%"
            
            if profile.type == .vacancy_daylight || profile.type == .occupancy_daylight || profile.type == .daylight {
                occupancyLevelLabel.text = "\(data.occupancyLevel)lx"
                vacantLevelLabel.text = "\(data.vacantLevel)lx"
                taskLevelLabel.text = "\(data.taskLevel)lx"
            }else {
                occupancyLevelLabel.text = "\(data.occupancyLevel)%"
                vacantLevelLabel.text = "\(data.vacantLevel)%"
                taskLevelLabel.text = "\(data.taskLevel)%"
            }
            
            phasesStandbyLevelLabel.text = "\(data.standbyLevel)%"
            
            autoMinLevelLabel.text = data.autoMinLevelEnabled ? "\(data.autoMinLevel)%" : "N/A"
            
            timeT1Btn.isHidden = true
            timeT1Label.isHidden = true
            timeT2Btn.isHidden = true
            timeT2Label.isHidden = true
            timeT3Btn.isHidden = true
            timeT3Label.isHidden = true
            timeT4Btn.isHidden = true
            timeT4Label.isHidden = true
            timeT5Btn.isHidden = true
            timeT5Label.isHidden = true
            
            taskLevelBtn.isHidden = true
            taskLevelLabel.isHidden = true
            autoMinLevelBtn.isHidden = true
            autoMinLevelLabel.isHidden = true
            
            var profileChartImageName = "profile_chart_occupancy"
            switch profile.type {
            case .occupancy_daylight, .vacancy_daylight, .occupancy, .vacancy, .proximityLighting, .proximityLightingWithPhotocell:
                timeT1Btn.isHidden = false
                timeT1Label.isHidden = false
                timeT2Btn.isHidden = false
                timeT2Label.isHidden = false
                timeT3Btn.isHidden = false
                timeT3Label.isHidden = false
                timeT4Btn.isHidden = false
                timeT4Label.isHidden = false
                timeT5Btn.isHidden = false
                timeT5Label.isHidden = false
                vacantLevelBtn.isHidden = false
                vacantLevelLabel.isHidden = false
                occupancyLevelBtn.isHidden = false
                occupancyLevelLabel.isHidden = false
                
                if profile.type == .occupancy || profile.type == .vacancy || profile.type == .proximityLighting || profile.type == .proximityLightingWithPhotocell {
                    autoMinLevelBtn.isHidden = true
                    autoMinLevelLabel.isHidden = true
                    profileChartImageName = "profile_chart_occupancy"
                    if profile.type == .proximityLightingWithPhotocell {
                        profileChartImageName = "profile_chart_occupancy_standby"
                    }
    //                    chartImageView.image = UIImage(named: "profile_chart_occupancy")
                }else {
                    autoMinLevelBtn.isHidden = false
                    autoMinLevelLabel.isHidden = false
    //                    chartImageView.image = UIImage(named: "profile_chart_occupancy_daylight")
                    profileChartImageName = "profile_chart_occupancy_daylight"
                }
                autoMinLevelBtn.snp.remakeConstraints { make in
                    make.right.width.height.equalTo(highEndTrimBtn)
                    make.top.equalTo(vacantLevelBtn.snp.bottom).offset(SCRYFrom(8))
                }
                
                

            case .daylight:
    //                chartImageView.image = UIImage(named: "profile_chart_daylight")
                profileChartImageName = "profile_chart_daylight"
                autoMinLevelBtn.isHidden = false
                autoMinLevelLabel.isHidden = false
                taskLevelBtn.isHidden = false
                taskLevelLabel.isHidden = false
                vacantLevelBtn.isHidden = true
                vacantLevelLabel.isHidden = true
                occupancyLevelBtn.isHidden = true
                occupancyLevelLabel.isHidden = true
                
                timeT1Btn.isHidden = false
                timeT1Label.isHidden = false
                
    //                autoMinLevelBtn.snp.remakeConstraints { make in
    //                    make.right.width.height.equalTo(highEndTrimBtn)
    //                    make.top.equalTo(taskLevelBtn.snp.bottom).offset(SCRYFrom(8))
    //                }
                autoMinLevelBtn.snp.remakeConstraints { make in
                    make.right.width.height.equalTo(highEndTrimBtn)
                    make.top.equalTo(vacantLevelBtn.snp.bottom).offset(SCRYFrom(8))
                }
                
            case .manualControl:
    //                chartImageView.image = UIImage(named: "profile_chart_manual_control")
                profileChartImageName = "profile_chart_manual_control"
                timeT1Btn.isHidden = false
                timeT1Label.isHidden = false
    //                timeT5Btn.isHidden = false
    //                timeT5Label.isHidden = false
                
                autoMinLevelBtn.isHidden = true
                autoMinLevelLabel.isHidden = true
                taskLevelBtn.isHidden = false
                taskLevelLabel.isHidden = false
                
                vacantLevelBtn.isHidden = true
                vacantLevelLabel.isHidden = true
                occupancyLevelBtn.isHidden = true
                occupancyLevelLabel.isHidden = true
                
                autoMinLevelBtn.snp.remakeConstraints { make in
                    make.right.width.height.equalTo(highEndTrimBtn)
                    make.top.equalTo(vacantLevelBtn.snp.bottom).offset(SCRYFrom(8))
                }
            }
            if isIPad {
                profileChartImageName.append("_ipad")
            }
            chartImageView.image = UIImage(named: profileChartImageName)
            chartImageView.sizeToFit()
            
            var chartImageTopMargin = SCRYFrom(46)
            var helpTopMargin = SCRYFrom(4)
            var highEndTrimMargin = SCRYFrom(60)
            if profile.type == .proximityLighting {
                chartImageTopMargin = SCRYFrom(62)
                helpTopMargin = SCRYFrom(10)
                highEndTrimMargin = SCRYFrom(76)
            }
            chartImageView.snp.remakeConstraints { make in
                
                make.top.equalTo(chartImageTopMargin)
                if isIPad {
                    make.left.equalTo(SCRXFrom(136))
                    make.right.equalTo(SCRXFrom(-56.7))
    //                    make.height.equalTo(chartImageView.snp.width).multipliedBy(230 / 490.0)
                    make.height.equalTo(SCRYFrom(230))
                }else {
                    make.left.equalTo(SCRXFrom(86))
                    make.right.equalTo(SCRXFrom(-45))
                    make.height.equalTo(chartImageView.snp.width).multipliedBy(chartImageView.height / chartImageView.width)
                }
                make.bottom.equalTo(SCRYFrom(-68))
            }
            helpBtn.snp.updateConstraints { make in
                make.top.equalTo(helpTopMargin)
            }
            highEndTrimBtn.snp.updateConstraints { make in
                make.top.equalTo(highEndTrimMargin)
            }
            
            standbyLevelView.isHidden = true
            standbyLevelView.snp.remakeConstraints { make in
                make.top.equalTo(triggerTypeView.snp.bottom).offset(SCRYFrom(20))
                make.left.right.equalToSuperview()
                make.height.equalTo(SCRYFrom(85))
    //            make.bottom.equalTo(SCRYFrom(-24))
            }
            
            devicePhasesView.isHidden = false
            devicePhasesView.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.top.equalTo(triggerTypeView.snp.bottom).offset(SCRYFrom(11))
                make.bottom.equalToSuperview()
            }
            
        case .fixedLevel:
            adjustOccupiedBtn.isSelected = false
            fixedLevelBtn.isSelected = true
            
            standbyLevelView.isHidden = false
            standbyLevelView.snp.remakeConstraints { make in
                make.top.equalTo(triggerTypeView.snp.bottom).offset(SCRYFrom(20))
                make.left.right.equalToSuperview()
                make.height.equalTo(SCRYFrom(85))
                make.bottom.equalTo(SCRYFrom(-24))
            }
            
            devicePhasesView.isHidden = true
            devicePhasesView.snp.remakeConstraints { make in
                make.left.right.equalToSuperview()
                make.top.equalTo(triggerTypeView.snp.bottom).offset(SCRYFrom(11))
            }
            
            updateStandbyLevelUI(standbyLevel: conditionData.fixedStandbyLevel)
//            standbyLevelSlider.value = conditionData.standbyLevel
            standbyLevelSlider.limitRange = data.lowEndTrim...data.highEndTrim
           
            
        }
    }
    
    /// 更新条件lux 提示
//    func updateStartsBelowLuxTip(tipMessage: String? = nil) {
//        luxTipLabel.text = tipMessage
//        if tipMessage != nil {
//            luxField.layer.borderColor = Red_Color.cgColor
//        }else {
//            luxField.layer.borderColor = Border_Color.cgColor
//        }
//    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        subviews.forEach({
            if $0.isKind(of: UIButton.classForCoder()), let btn = $0 as? UIButton, !btn.allTargets.contains(self), btn.isUserInteractionEnabled {
//                btn.clipsToBounds = true
//                btn.setBackgroundImage(UIImage.image(size: btn.frame.size, color: .black.withAlphaComponent(0.15)), for: .highlighted)
                btn.addTarget(self, action: #selector(btnTouchDownAction), for: .touchDown)
                btn.addTarget(self, action: #selector(btnTouchUpInside), for: .touchCancel)
            }
        })
        
    }
    
    // MARK: - Action
    /// 帮助
    @objc private func helpBtnAction(sender: UIButton) {
        delegate?.phasesViewHelpAction(self)
        btnTouchUpInside(sender: sender)
    }
    
    /// 条件lux输入回调
//    @objc private func luxFieldEditChanged(sender: UITextField) {
//        guard editable else {
//            return
//        }
//        luxField.layer.borderColor = Border_Color.cgColor
//        luxTipLabel.text = nil
//        delegate?.view(self, startsBelowLuxEditChanged: startsBelowLux)
//    }
    
    // MARK: - Level
    /// 最高输出亮度
    @objc private func highEndTrimBtnAction(sender: UIButton) {
        delegate?.phasesViewHighAndLowEndTrimAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 占用阶段
    @objc private func occupancyLevelBtnAction(sender: UIButton) {
        delegate?.phasesViewOccupancyAndVacantLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 维持阶段
    @objc private func vacantLevelBtnAction(sender: UIButton) {
        delegate?.phasesViewOccupancyAndVacantLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 日光补偿最低值
    @objc private func autoMinLevelBtnAction(sender: UIButton) {
        delegate?.phasesViewAutoMinValueAction(self)
        btnTouchUpInside(sender: sender)
    }
    
    /// 待机阶段
    @objc private func phasesStandbyLevelBtnAction(sender: UIButton) {
        delegate?.phasesViewStandbyLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    
    /// 最低输出亮度
    @objc private func lowEndTrimBtnAction(sender: UIButton) {
        delegate?.phasesViewHighAndLowEndTrimAction(self)
        btnTouchUpInside(sender: sender)
    }
    /// 维持亮度(手动控制On% / 环境光lx)
    @objc private func taskLevelBtnAction(sender: UIButton) {
        delegate?.phasesViewTaskLevelAction(self)
        btnTouchUpInside(sender: sender)
    }
    
    // MARK: - Time
    
    @objc private func timeT1BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t1)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT2BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t2)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT3BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t3)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT4BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t4)
        btnTouchUpInside(sender: sender)
    }
    
    @objc private func timeT5BtnAction(sender: UIButton) {
        delegate?.view(self, timeAction: .t5)
        btnTouchUpInside(sender: sender)
    }
   
    /// 按键按下回调
    @objc private func btnTouchDownAction(sender: UIButton) {
//        sender.isHighlighted = true
//        sender.backgroundColor = .black.withAlphaComponent(0.15)
        sender.backgroundColor = RGB(0, 0, 0, 0.15)
     
//        UIView.animate(withDuration: 0.25) {
//            sender.backgroundColor = RGB(0, 0, 0, 0.15)
//        } completion: { _ in
//            sender.backgroundColor = .clear
//        }
    }
    
    /// 按键点击抬起回调
    @objc private func btnTouchUpInside(sender: UIButton) {
        UIView.animate(withDuration: 0.25) {
            sender.backgroundColor = .clear
        }
    }
    
    /// 切换设备三段式调光执行
    @objc private func adjustOccupiedBtnAction(sender: UIButton) {
        guard editable else {
            return
        }
        sender.isSelected = true
        fixedLevelBtn.isSelected = false
        delegate?.view(self, selectExecuteType: .adjustWhenOccupied)
    }
    
    /// 切换固定亮度执行
    @objc private func fixedLevelBtnAction(sender: UIButton) {
        guard editable else {
            return
        }
        sender.isSelected = true
        adjustOccupiedBtn.isSelected = false
        delegate?.view(self, selectExecuteType: .fixedLevel)
    }
    
    /// 使用校准帮助点击事件
    @objc private func useCalibrationHelpBtnAction(sender: UIButton) {
        btnTouchUpInside(sender: sender)
        delegate?.phasesViewUseCalibrationValuesHelpAction(self)
    }
    
    /// 调光阶段帮助点击事件
    @objc private func phasesHelpBtnAction(sender: UIButton) {
        btnTouchUpInside(sender: sender)
        delegate?.phasesViewPhasesHelpAction(self)
    }
    
    /// 固定待机亮度"-"事件
    @objc private func standbyLevelMinusBtnAction() {
        guard editable else {
            return
        }
        standbyLevelSlider.value -= 1
        updateStandbyLevel()
        delegate?.view(self, fixedLevelValueChnaged: Int(standbyLevelSlider.value))
    }
    
    /// 固定待机亮度"+"事件
    @objc private func standbyLevelAddBtnAction() {
        guard editable else {
            return
        }
        standbyLevelSlider.value += 1
        updateStandbyLevel()
        delegate?.view(self, fixedLevelValueChnaged: Int(standbyLevelSlider.value))
    }
    
    /// 更新固定待机亮度数值UI
    private func updateStandbyLevel() {
        if standbyLevelSlider.value > 0 {
            standbyLevelLabel.text = "\(Int(standbyLevelSlider.value))%"
        }else {
            standbyLevelLabel.text = "off_state".localizedString
        }
    }
    
    /// 更新固定待机亮度UI
    private func updateStandbyLevelUI(standbyLevel: Int) {
        
        if standbyLevel > 0 {
            standbyLevelSlider.value = Float(standbyLevel)
            standbyLevelSlider.isEnabled = true
            standbyLevelMinusBtn.isEnabled = true
            standbyLevelAddBtn.isEnabled = true
            updateStandbyLevel()
            standbyLevelOffBtn.isSelected = false
            standbyLevelOffBtn.backgroundColor = .clear
        }else {
            standbyLevelSlider.isEnabled = false
            standbyLevelMinusBtn.isEnabled = false
            standbyLevelAddBtn.isEnabled = false
            standbyLevelLabel.text = "off_state".localizedString
            standbyLevelOffBtn.isSelected = true
            standbyLevelOffBtn.backgroundColor = Bar_Color
        }
        
    }
    
    /// 固定待机亮度off事件
    @objc private func standbyLevelOffBtnAction(sender: UIButton) {
        guard editable else {
            return
        }
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            updateStandbyLevelUI(standbyLevel: 0)
            delegate?.view(self, fixedLevelValueChnaged: 0)
        }else {
            updateStandbyLevelUI(standbyLevel: Int(standbyLevelSlider.value))
            delegate?.view(self, fixedLevelValueChnaged: Int(standbyLevelSlider.value))
        }
       
    }
    
    /// 使用校准开关事件
    @objc private func calibrationEnableSwitchValueChanged(sendor: UISwitch) {
        guard editable else {
            return
        }
        delegate?.view(self, useCalibrationValues: sendor.isOn)
    }
    
    // MARK: - UI
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "night".localizedString, textColor: TextBlack_Color, fontSize: 16)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(10))
        }
        
//        startsBelowLabel = UILabel(text: "starts_below".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
//        addSubview(startsBelowLabel)
//        startsBelowLabel.snp.makeConstraints { make in
//            make.left.equalTo(titleLabel)
//            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20))
//        }
//        
//        luxLabel = UILabel(text: "lx", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
//        addSubview(luxLabel)
//        luxLabel.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-16))
//            make.centerY.equalTo(startsBelowLabel)
//        }
//        
//        luxField = UITextField()
//        luxField.textColor = ImportantText_Color
//        luxField.textAlignment = .center
//        luxField.font = UIFont.systemFont(ofSize: FontFit(12))
//        luxField.keyboardType = .numberPad
//        luxField.layer.cornerRadius = SCRYFrom(5)
//        luxField.layer.borderWidth = 0.6
//        luxField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
//        luxField.returnKeyType = .done
//        luxField.delegate = self
//        luxField.addTarget(self, action: #selector(luxFieldEditChanged), for: .editingChanged)
//        addSubview(luxField)
//        luxField.snp.makeConstraints { make in
//            make.right.equalTo(luxLabel.snp.left).offset(SCRXFrom(-4))
//            make.centerY.equalTo(luxLabel)
//            make.width.equalTo(isIPad ? SCRXFrom(100) : SCRXFrom(72))
//            make.height.equalTo(SCRYFrom(28))
//        }
//        
//        luxTipLabel = UILabel(text: "", textColor: Error_Red_Color, fontSize: 12, fontWeight: .light)
//        addSubview(luxTipLabel)
//        luxTipLabel.snp.makeConstraints { make in
//            make.top.equalTo(luxField.snp.bottom).priority(.high)
//            make.right.equalTo(SCRXFrom(-16))
//        }
//        
//        
//        calibrationEnableSwitch = UISwitch()
//        calibrationEnableSwitch.onTintColor = Bar_Color
//        calibrationEnableSwitch.isEnabled = editable
//        calibrationEnableSwitch.addTarget(self, action: #selector(calibrationEnableSwitchValueChanged), for: .valueChanged)
//        addSubview(calibrationEnableSwitch)
//        calibrationEnableSwitch.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-16))
//            make.top.equalTo(luxField.snp.bottom).offset(SCRYFrom(20))
//        }
//        
//        useCalibrationLabel = UILabel(text: "use_calibration_values".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
//        addSubview(useCalibrationLabel)
//        useCalibrationLabel.snp.makeConstraints { make in
//            make.left.equalTo(startsBelowLabel)
//            make.centerY.equalTo(calibrationEnableSwitch)
//        }
//        
//        useCalibrationHelpBtn = UIButton(normalImageName: "help", target: self, action: #selector(useCalibrationHelpBtnAction))
//        addSubview(useCalibrationHelpBtn)
//        useCalibrationHelpBtn.snp.makeConstraints { make in
//            make.left.equalTo(useCalibrationLabel.snp.right).offset(SCRXFrom(8))
//            make.centerY.equalTo(useCalibrationLabel)
//        }
        
        triggerTypeView = UIView()
        triggerTypeView.backgroundColor = Background_Color
        triggerTypeView.layer.cornerRadius = SCRYFrom(7)
        addSubview(triggerTypeView)
        triggerTypeView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(15))
            make.height.equalTo(SCRYFrom(40))
        }
        
        adjustOccupiedBtn = UIButton(title: "adjust_when_occupied".localizedString, titleSize: 12, titleWeight: .light, titleColor: ImportantText_Color, normalImageName: "schedule_target_select_un", selectedImageName: "schedule_target_select", target: self, action: #selector(adjustOccupiedBtnAction))
        adjustOccupiedBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        triggerTypeView.addSubview(adjustOccupiedBtn)
        adjustOccupiedBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(10))
        }
        
        fixedLevelBtn = UIButton(title: "fixed_level".localizedString, titleSize: 12, titleWeight: .light, titleColor: ImportantText_Color, normalImageName: "schedule_target_select_un", selectedImageName: "schedule_target_select", target: self, action: #selector(fixedLevelBtnAction))
        fixedLevelBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        triggerTypeView.addSubview(fixedLevelBtn)
        fixedLevelBtn.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(triggerTypeView.snp.centerX).offset(SCRXFrom(20))
        }
        
        devicePhasesView = UIView()
        addSubview(devicePhasesView)
        devicePhasesView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(triggerTypeView.snp.bottom).offset(SCRYFrom(11))
            make.bottom.equalToSuperview()
        }
        
        deviceTriggerLabel = UILabel(text: "device_trigger_curve".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        devicePhasesView.addSubview(deviceTriggerLabel)
        deviceTriggerLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(6))
        }
        
        phasesHelpBtn = UIButton(normalImageName: "help", target: self, action: #selector(phasesHelpBtnAction))
        devicePhasesView.addSubview(phasesHelpBtn)
        phasesHelpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalTo(deviceTriggerLabel)
        }
        
        chartImageView = UIImageView(image: UIImage(named: "profile_chart_occupancy_daylight"))
        chartImageView.sizeToFit()
        devicePhasesView.addSubview(chartImageView)
        chartImageView.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(146))
                make.right.equalTo(SCRXFrom(-56.7))
//                make.height.equalTo(chartImageView.snp.width).multipliedBy(230 / 490.0)
                make.height.equalTo(SCRYFrom(230))
            }else {
                make.left.equalTo(SCRXFrom(86))
                make.right.equalTo(SCRXFrom(-45))
                make.height.equalTo(chartImageView.snp.width).multipliedBy(chartImageView.height / chartImageView.width)
            }
            make.top.equalTo(SCRYFrom(46))
            make.bottom.equalTo(SCRYFrom(-68))
//            if isIPad {
////                make.centerX.equalToSuperview()
//            }else {
//                make.top.equalTo(SCRYFrom(46))
//            }
        }
        
        lightLevelImageView = UIImageView(image: UIImage(named: "profile_light_level"))
        devicePhasesView.addSubview(lightLevelImageView)
        lightLevelImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(isIPad ? 13 : 2))
//            make.top.equalTo(SCRYFrom(34))
            make.top.equalTo(chartImageView).offset(SCRYFrom(-12))
            make.bottom.equalTo(chartImageView)
        }
        
        maxLightOutputLabel = UILabel(text: "profile_max_light_output".localizedString, textColor: Chart_Text_Color, fontSize: 12)
        maxLightOutputLabel.numberOfLines = 2
        maxLightOutputLabel.textAlignment = .center
        devicePhasesView.addSubview(maxLightOutputLabel)
        maxLightOutputLabel.snp.makeConstraints { make in
            make.right.equalTo(chartImageView.snp.left)
//            if !isIPad {
//                make.left.equalTo(SCRXFrom(25))
//            }
            if isIPad {
                make.width.equalTo(SCRXFrom(93.8))
            }else {
                make.width.equalTo(SCRXFrom(60))
            }
            make.centerY.equalTo(chartImageView.snp.top)
        }
        
        highEndTrimBtn = UIButton(title: "profile_high_end_trim".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(highEndTrimBtnAction))
        highEndTrimBtn.titleLabel?.numberOfLines = 2
        highEndTrimBtn.titleLabel?.textAlignment = .center
        highEndTrimBtn.layer.cornerRadius = 5
        highEndTrimBtn.layer.borderWidth = 1
        highEndTrimBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        highEndTrimBtn.clipsToBounds = true
        devicePhasesView.addSubview(highEndTrimBtn)
        highEndTrimBtn.snp.makeConstraints { make in
            make.right.equalTo(chartImageView.snp.left)
            make.top.equalTo(SCRYFrom(60))
            if isIPad {
//                make.top.equalTo(maxLightOutputLabel.snp.bottom).offset(SCRYFrom(20))
                make.width.equalTo(SCRXFrom(93.6))
            }else {
                make.width.equalTo(SCRXFrom(64))
            }
            make.height.equalTo(SCRYFrom(32))
        }
        
        highEndTrimLabel = UILabel(text: "100%", textColor: Chart_Text_Color, fontSize: 10)
        devicePhasesView.addSubview(highEndTrimLabel)
        highEndTrimLabel.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(chartImageView.snp.right).offset(SCRXFrom(7))
            }else {
                make.left.equalTo(chartImageView.snp.right).offset(SCRXFrom(1))
            }
            make.centerY.equalTo(highEndTrimBtn)
        }
        
        let levelSphaseMargin = isIPad ? SCRYFrom(7) : SCRYFrom(8)
        
        occupancyLevelBtn = UIButton(title: "profile_occupa-ncy_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(occupancyLevelBtnAction))
        occupancyLevelBtn.titleLabel?.numberOfLines = 2
        occupancyLevelBtn.titleLabel?.textAlignment = .center
        occupancyLevelBtn.layer.cornerRadius = 5
        occupancyLevelBtn.layer.borderWidth = 1
        occupancyLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(occupancyLevelBtn)
        occupancyLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(highEndTrimBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        occupancyLevelLabel = UILabel(text: "1000lx", textColor: Chart_Text_Color, fontSize: 10)
        devicePhasesView.addSubview(occupancyLevelLabel)
        occupancyLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(occupancyLevelBtn)
        }
        
        taskLevelBtn = UIButton(title: "profile_task_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(taskLevelBtnAction))
        taskLevelBtn.titleLabel?.textAlignment = .center
        taskLevelBtn.layer.cornerRadius = 5
        taskLevelBtn.layer.borderWidth = 1
        taskLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        taskLevelBtn.isHidden = true
        devicePhasesView.addSubview(taskLevelBtn)
        taskLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(highEndTrimBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        taskLevelLabel = UILabel(text: "500lx", textColor: Chart_Text_Color, fontSize: 10)
        taskLevelLabel.isHidden = true
        devicePhasesView.addSubview(taskLevelLabel)
        taskLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(taskLevelBtn)
        }
        
        vacantLevelBtn = UIButton(title: "profile_vacant_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(vacantLevelBtnAction))
        vacantLevelBtn.titleLabel?.numberOfLines = 2
        vacantLevelBtn.titleLabel?.textAlignment = .center
        vacantLevelBtn.contentMode = .center
        vacantLevelBtn.layer.cornerRadius = 5
        vacantLevelBtn.layer.borderWidth = 1
        vacantLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(vacantLevelBtn)
        vacantLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(occupancyLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        vacantLevelLabel = UILabel(text: "1000lx", textColor: Chart_Text_Color, fontSize: 10)
        devicePhasesView.addSubview(vacantLevelLabel)
        vacantLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(vacantLevelBtn)
        }
        
        autoMinLevelBtn = UIButton(title: "profile_auto_min_value".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(autoMinLevelBtnAction))
        autoMinLevelBtn.titleLabel?.numberOfLines = 2
        autoMinLevelBtn.titleLabel?.textAlignment = .center
        autoMinLevelBtn.layer.cornerRadius = 5
        autoMinLevelBtn.layer.borderWidth = 1
        autoMinLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        autoMinLevelBtn.isHidden = true
        devicePhasesView.addSubview(autoMinLevelBtn)
        autoMinLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(vacantLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        autoMinLevelLabel = UILabel(text: "100%", textColor: Chart_Text_Color, fontSize: 10)
        autoMinLevelLabel.isHidden = true
        devicePhasesView.addSubview(autoMinLevelLabel)
        autoMinLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(autoMinLevelBtn)
        }
        
        phasesStandbyLevelBtn = UIButton(title: "standby_level".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(phasesStandbyLevelBtnAction))
        phasesStandbyLevelBtn.titleLabel?.numberOfLines = 2
        phasesStandbyLevelBtn.titleLabel?.textAlignment = .center
        phasesStandbyLevelBtn.layer.cornerRadius = 5
        phasesStandbyLevelBtn.layer.borderWidth = 1
        phasesStandbyLevelBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(phasesStandbyLevelBtn)
        phasesStandbyLevelBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(vacantLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        phasesStandbyLevelLabel = UILabel(text: "30%", textColor: Chart_Text_Color, fontSize: 10)
        devicePhasesView.addSubview(phasesStandbyLevelLabel)
        phasesStandbyLevelLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(phasesStandbyLevelBtn)
        }
        
        lowEndTrimBtn = UIButton(title: "profile_low_end_trim".localizedString, titleSize: 12, titleColor: Chart_Text_Color, target: self, action: #selector(lowEndTrimBtnAction))
        lowEndTrimBtn.titleLabel?.numberOfLines = 2
        lowEndTrimBtn.titleLabel?.textAlignment = .center
        lowEndTrimBtn.layer.cornerRadius = 5
        lowEndTrimBtn.layer.borderWidth = 1
        lowEndTrimBtn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(lowEndTrimBtn)
        lowEndTrimBtn.snp.makeConstraints { make in
            make.right.width.height.equalTo(highEndTrimBtn)
            make.top.equalTo(autoMinLevelBtn.snp.bottom).offset(levelSphaseMargin)
        }
        
        lowEndTrimLabel = UILabel(text: "0%", textColor: Chart_Text_Color, fontSize: 10)
        devicePhasesView.addSubview(lowEndTrimLabel)
        lowEndTrimLabel.snp.makeConstraints { make in
            make.left.equalTo(highEndTrimLabel)
            make.centerY.equalTo(lowEndTrimBtn)
        }
        
        offLabel = UILabel(text: "action_off".localizedString, textColor: Chart_Text_Color, fontSize: 12)
        devicePhasesView.addSubview(offLabel)
        offLabel.snp.makeConstraints { make in
            make.centerX.equalTo(lowEndTrimBtn)
            if isIPad {
                make.bottom.equalTo(chartImageView).offset(SCRYFrom(-4))
            }else {
                make.top.equalTo(lowEndTrimBtn.snp.bottom).offset(levelSphaseMargin)
            }
        }
        
        timeT1Btn = UIButton(title: "T1", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT1BtnAction))
        timeT1Btn.layer.cornerRadius = 5
        timeT1Btn.layer.borderWidth = 1
        timeT1Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(timeT1Btn)
        timeT1Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(chartImageView).offset(SCRXFrom(2.5))
                make.width.equalTo(SCRXFrom(69.45))
                make.height.equalTo(SCRYFrom(30))
            }else {
                make.left.equalTo(chartImageView).offset(SCRXFrom(-4))
                make.width.height.equalTo(SCRXFrom(30))
            }
            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        timeT1Label = UILabel(text: "2s", textColor: .black, fontSize: 10, fontWeight: .light)
        devicePhasesView.addSubview(timeT1Label)
        timeT1Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Btn.snp.top).offset(SCRYFrom(-5))
            make.centerX.equalTo(timeT1Btn)
        }
        
        timeT2Btn = UIButton(title: "T2", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT2BtnAction))
        timeT2Btn.layer.cornerRadius = 5
        timeT2Btn.layer.borderWidth = 1
        timeT2Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(timeT2Btn)
        timeT2Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT1Btn.snp.right).offset(SCRXFrom(64))
            }else {
                make.left.equalTo(timeT1Btn.snp.right).offset(SCRXFrom(34))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT2Label = UILabel(text: "20min", textColor: .black, fontSize: 10, fontWeight: .light)
        devicePhasesView.addSubview(timeT2Label)
        timeT2Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT2Btn)
        }
        
        timeT3Btn = UIButton(title: "T3", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT3BtnAction))
        timeT3Btn.layer.cornerRadius = 5
        timeT3Btn.layer.borderWidth = 1
        timeT3Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(timeT3Btn)
        timeT3Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT2Btn.snp.right).offset(SCRXFrom(22))
            }else {
                make.left.equalTo(timeT2Btn.snp.right).offset(SCRXFrom(10))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT3Label = UILabel(text: "2s", textColor: .black, fontSize: 10, fontWeight: .light)
        devicePhasesView.addSubview(timeT3Label)
        timeT3Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT3Btn)
        }
        
        timeT4Btn = UIButton(title: "T4", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT4BtnAction))
        timeT4Btn.layer.cornerRadius = 5
        timeT4Btn.layer.borderWidth = 1
        timeT4Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(timeT4Btn)
        timeT4Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT3Btn.snp.right).offset(SCRXFrom(10))
            }else {
                make.left.equalTo(timeT3Btn.snp.right).offset(SCRXFrom(5))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT4Label = UILabel(text: "infinite".localizedString, textColor: .black, fontSize: 10, fontWeight: .light)
        devicePhasesView.addSubview(timeT4Label)
        timeT4Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT4Btn)
        }
        
        timeT5Btn = UIButton(title: "T5", titleSize: 12, titleWeight: .light, titleColor: .black, target: self, action: #selector(timeT5BtnAction))
        timeT5Btn.layer.cornerRadius = 5
        timeT5Btn.layer.borderWidth = 1
        timeT5Btn.layer.borderColor = RGB(216, 216, 216).cgColor
        devicePhasesView.addSubview(timeT5Btn)
        timeT5Btn.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(timeT4Btn.snp.right).offset(SCRXFrom(10))
            }else {
                make.left.equalTo(timeT4Btn.snp.right).offset(SCRXFrom(5))
            }
            make.bottom.width.height.equalTo(timeT1Btn)
        }
        
        timeT5Label = UILabel(text: "2s".localizedString, textColor: .black, fontSize: 10, fontWeight: .light)
        devicePhasesView.addSubview(timeT5Label)
        timeT5Label.snp.makeConstraints { make in
            make.bottom.equalTo(timeT1Label)
            make.centerX.equalTo(timeT5Btn)
        }
        
        standbyLevelView = UIView()
        standbyLevelView.isHidden = true
        addSubview(standbyLevelView)
        standbyLevelView.snp.makeConstraints { make in
            make.top.equalTo(triggerTypeView.snp.bottom).offset(SCRYFrom(20))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(85))
//            make.bottom.equalTo(SCRYFrom(-24))
        }
        
        standbyLevelTitleLabel = UILabel(text: "standby_level".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        standbyLevelView.addSubview(standbyLevelTitleLabel)
        standbyLevelTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(7))
        }
        
        standbyLevelLabel = UILabel(text: "0%", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        standbyLevelView.addSubview(standbyLevelLabel)
        standbyLevelLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(standbyLevelTitleLabel)
        }
        
        standbyLevelOffBtn = UIButton(title: "off".localizedString, titleSize: 13, titleColor: ImportantText_Color, target: self, action: #selector(standbyLevelOffBtnAction))
        standbyLevelOffBtn.setTitleColor(.white, for: .selected)
        standbyLevelOffBtn.layer.cornerRadius = SCRYFrom(15)
        standbyLevelOffBtn.layer.borderColor = Border_Color.cgColor
        standbyLevelOffBtn.layer.borderWidth = 0.6
        standbyLevelView.addSubview(standbyLevelOffBtn)
        standbyLevelOffBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(standbyLevelTitleLabel)
            make.width.equalTo(SCRXFrom(64))
            make.height.equalTo(SCRYFrom(32))
        }
        
        standbyLevelMinusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(standbyLevelMinusBtnAction))
        standbyLevelView.addSubview(standbyLevelMinusBtn)
        standbyLevelMinusBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.bottom.equalTo(SCRYFrom(-6))
        }
        
        standbyLevelAddBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(standbyLevelAddBtnAction))
        standbyLevelView.addSubview(standbyLevelAddBtn)
        standbyLevelAddBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.bottom.equalTo(standbyLevelMinusBtn)
        }
        
        standbyLevelSlider = CustomDeviceSlider()
        standbyLevelSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        standbyLevelSlider.minimumTrackTintColor = Slider_Color
        standbyLevelSlider.maximumTrackTintColor = RGB(229, 229, 229)
        standbyLevelSlider.layer.cornerRadius = 2
        standbyLevelSlider.minimumValue = 1
        standbyLevelSlider.maximumValue = 100
        standbyLevelSlider.value = 1
        standbyLevelSlider.throttle = true
        standbyLevelSlider.delegate = self
        standbyLevelView.addSubview(standbyLevelSlider)
        standbyLevelSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(61))
            make.right.equalTo(SCRXFrom(-62))
            make.centerY.equalTo(standbyLevelAddBtn)
            make.height.equalTo(SCRYFrom(40))
        }
        
        
    }
    
}


extension ProfileTriggerConditionPhasesView: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
//        updateValue()
//        valueChangedCallback?(Int(value), ended)
        delegate?.view(self, fixedLevelValueChnaged: Int(value))
        updateStandbyLevel()
    }
}


//extension ProfileTriggerConditionPhasesView: UITextFieldDelegate {
//    
//    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
//        endEditing(true)
//        return true
//    }
//    
//    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//        guard string.isEmpty || string.isPureNumandCharacters() else {
//            return false
//        }
//        return true
//    }
//    
//}
