//
//  LightSensorCalibrationView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/29.
//

import UIKit

protocol LightSensorCalibrationViewDelegate: AnyObject {
    
    /// 点击校准帮助
    func calibrationViewHelpAction(_ view: LightSensorCalibrationView)
    
    /// 输入测量值回调
    /// - Parameters:
    ///   - view: view
    ///   - lux: 测量值 为空则未输入
    func view(_ view: LightSensorCalibrationView, measuredLightValueEditing lux: Int?)
    
    /// 亮度修改回调
    /// - Parameters:
    ///   - view: view
    ///   - level: 0~100
    func view(_ view: LightSensorCalibrationView, lightLevelValueChanged level: Int)
    
    /// 调节速率修改回调
    /// - Parameters:
    ///   - view: view
    ///   - speed: 0~100
    func view(_ view: LightSensorCalibrationView, adjustSpeedChanged speed: Int)
    
    /// 点击调整速率帮助
    func calibrationViewAdjustSpeedHelpAction(_ view: LightSensorCalibrationView)
    
}

class LightSensorCalibrationView: UIView {

    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    private var levelField: UITextField!
    private var minimunLabel: UILabel!
    private var luxLabel: UILabel!
    private var showAdvancedBtn: UIButton!
    private var advancedSettingsView: UIView!
    
    private var lightLevelLabel: UILabel!
    private var lightLevelValueLabel: UILabel!
    private var lightLevelAddBtn: UIButton!
    private var lightLevelMinusBtn: UIButton!
    private var lightLevelSlider: CustomDeviceSlider!
    
    private var speedLabel: UILabel!
    private var speedHelpBtn: UIButton!
    private var speedSlowLabel: UILabel!
    private var speedFastLabel: UILabel!
    var speedSlider: CustomDeviceSlider!
    
    weak var delegate: LightSensorCalibrationViewDelegate?
    
    /// 最小的测量值
    var minimunValue: Int = 100 {
        didSet {
            minimunLabel.text = String(format: "light_sensor_minium_lux".localizedString, minimunValue)
        }
    }
    
    /// 亮度条输出范围
    var limitRange: ClosedRange<Int>? {
        didSet {
            lightLevelSlider.limitRange = limitRange
        }
    }
    
    /// 测量值
    var measuredLightValue: Int? {
        get {
            return Int(levelField.text ?? "")
        }set {
            if let value = newValue {
                levelField.text = "\(value)"
                luxLabel.isHidden = false
            }else {
                levelField.text = nil
                luxLabel.isHidden = false
            }
        }
    }
    
    /// 调节速率 0~100
    var adjustSpeed: Int {
        return Int(speedSlider.value)
    }
    
    /// 亮度值 0~100
    var lightLevel: Int {
        get {
            return Int(lightLevelSlider.value)
        }set {
            lightLevelSlider.value = Float(newValue)
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    /// 验证测量值
    func verifyMeasuredValue() {
        if measuredLightValue == nil || measuredLightValue! >= minimunValue {
            minimunLabel.textColor = Message_Color
            levelField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        }else {
            minimunLabel.textColor = Red_Color
            levelField.layer.borderColor = Red_Color.cgColor
        }
    }
    
    // MARK: - Action
    
    @objc private func levelFieldEditChanged(sender: UITextField) {
        guard let text = sender.text, let value = Int(text) else {
            minimunLabel.textColor = Message_Color
            sender.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
            delegate?.view(self, measuredLightValueEditing: nil)
            luxLabel.isHidden = true
            verifyMeasuredValue()
            return
        }
      
        delegate?.view(self, measuredLightValueEditing: value)
        
        luxLabel.isHidden = false
        minimunLabel.textColor = Message_Color
        levelField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
    }
    
    @objc private func helpBtnAction() {
        delegate?.calibrationViewHelpAction(self)
    }
    
    @objc private func speedHelpBtnAction() {
        delegate?.calibrationViewAdjustSpeedHelpAction(self)
    }
    
    @objc private func showAdvancedBtnAction(sender: UIButton) {

        sender.isSelected = !sender.isSelected
        
        advancedSettingsView.isHidden = !sender.isSelected
        
        advancedSettingsView.snp.updateConstraints { make in
            make.height.equalTo(sender.isSelected ? SCRYFrom(176) : 0)
        }
    }
    
    @objc private func lightLevelAddBtnAction() {
        lightLevelSlider.value = min(lightLevelSlider.value + 1, lightLevelSlider.maximumValue)
        lightLevelValueLabel.text = "\(Int(lightLevelSlider.value))%"
        delegate?.view(self, lightLevelValueChanged: Int(lightLevelSlider.value))
    }
    
    @objc private func lightLevelMinusBtnAction() {
        
        lightLevelSlider.value = max(lightLevelSlider.value - 1, lightLevelSlider.minimumValue)
        lightLevelValueLabel.text = "\(Int(lightLevelSlider.value))%"
        delegate?.view(self, lightLevelValueChanged: Int(lightLevelSlider.value))
    }
    
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "calibration".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        titleLabel.sizeToFit()
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
            make.height.equalTo(titleLabel.height)
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(titleLabel)
        }
        
        levelField = UITextField()
        levelField.attributedPlaceholder = NSAttributedString(string: "measured_light_level".localizedString, attributes: [.foregroundColor: SubText_Color])
        levelField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        levelField.textColor = TextBlack_Color
        levelField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
        levelField.leftViewMode = .always
        levelField.layer.cornerRadius = 5
        levelField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        levelField.keyboardType = .numberPad
        levelField.layer.borderWidth = 0.6
        levelField.returnKeyType = .done
        levelField.delegate = self
        levelField.addTarget(self, action: #selector(levelFieldEditChanged), for: .editingChanged)
        addSubview(levelField)
        levelField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-63))
            make.height.equalTo(SCRYFrom(40))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(15))
        }
        
        luxLabel = UILabel(text: "LX", textColor: SubText_Color, fontSize: 15, fontWeight: .light)
        luxLabel.isHidden = true
        addSubview(luxLabel)
        luxLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(levelField)
        }
        
        minimunLabel = UILabel(text: String(format: "light_sensor_minium_lux".localizedString, 100), textColor: Message_Color, fontSize: 14, fontWeight: .light)
        minimunLabel.sizeToFit()
        addSubview(minimunLabel)
        minimunLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(27))
            make.top.equalTo(levelField.snp.bottom).offset(SCRYFrom(9))
            make.height.equalTo(minimunLabel.height)
        }
        
        showAdvancedBtn = UIButton(title: "show_advanced_settings".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "arrow_down", selectedImageName: "arrow_up", target: self, action: #selector(showAdvancedBtnAction))
        showAdvancedBtn.setTitle("hide_advanced_settings".localizedString, for: .selected)
        showAdvancedBtn.setImagePosition(position: .right, spacing: SCRXFrom(4))
        addSubview(showAdvancedBtn)
        showAdvancedBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(minimunLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        advancedSettingsView = UIView()
        advancedSettingsView.isHidden = true
        addSubview(advancedSettingsView)
        advancedSettingsView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(showAdvancedBtn.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(0)
            make.bottom.equalToSuperview()
        }
        
        lightLevelLabel = UILabel(text: "light_level".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        advancedSettingsView.addSubview(lightLevelLabel)
        lightLevelLabel.snp.makeConstraints { make in
            make.top.left.equalToSuperview()
        }
        
        lightLevelValueLabel = UILabel(text: "0%", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        advancedSettingsView.addSubview(lightLevelValueLabel)
        lightLevelValueLabel.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
        }

        lightLevelAddBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(lightLevelAddBtnAction))
        advancedSettingsView.addSubview(lightLevelAddBtn)
        lightLevelAddBtn.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.top.equalTo(lightLevelValueLabel.snp.bottom).offset(SCRYFrom(17))
        }
        
        lightLevelMinusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(lightLevelMinusBtnAction))
        advancedSettingsView.addSubview(lightLevelMinusBtn)
        lightLevelMinusBtn.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalTo(lightLevelAddBtn)
        }
        
        lightLevelSlider = CustomDeviceSlider()
        lightLevelSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        lightLevelSlider.minimumTrackTintColor = RGB(255, 167, 44)
        lightLevelSlider.maximumTrackTintColor = RGB(229, 229, 229)
        lightLevelSlider.layer.cornerRadius = 2
        lightLevelSlider.minimumValue = 0
        lightLevelSlider.maximumValue = 100
        lightLevelSlider.value = 0
        lightLevelSlider.throttle = true
        lightLevelSlider.delegate = self
        advancedSettingsView.addSubview(lightLevelSlider)
        lightLevelSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(45))
            make.right.equalTo(SCRXFrom(-45))
            make.centerY.equalTo(lightLevelAddBtn)
            make.height.equalTo(SCRYFrom(40))
        }
        
        speedLabel = UILabel(text: "adjust_speed".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        advancedSettingsView.addSubview(speedLabel)
        speedLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalTo(lightLevelSlider.snp.bottom).offset(SCRYFrom(24))
        }

        speedHelpBtn = UIButton(normalImageName: "help", target: self, action: #selector(speedHelpBtnAction))
        advancedSettingsView.addSubview(speedHelpBtn)
        speedHelpBtn.snp.makeConstraints { make in
            make.left.equalTo(speedLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(speedLabel)
        }
        
        speedSlowLabel = UILabel(text: "slow".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        advancedSettingsView.addSubview(speedSlowLabel)
        speedSlowLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalTo(speedLabel.snp.bottom).offset(SCRYFrom(23))
        }
        
        speedFastLabel = UILabel(text: "fast".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        advancedSettingsView.addSubview(speedFastLabel)
        speedFastLabel.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(speedSlowLabel)
        }
        
        speedSlider = CustomDeviceSlider()
        speedSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        speedSlider.minimumTrackTintColor = RGB(255, 167, 44)
        speedSlider.maximumTrackTintColor = RGB(229, 229, 229)
        speedSlider.layer.cornerRadius = 2
        speedSlider.minimumValue = 0
        speedSlider.maximumValue = 100
        speedSlider.value = 50
        speedSlider.delegate = self
        advancedSettingsView.addSubview(speedSlider)
        speedSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(lightLevelSlider)
            make.centerY.equalTo(speedFastLabel)
        }
        
    }
    
}

extension LightSensorCalibrationView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        return textField.resignFirstResponder()
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if !string.isPureNumandCharacters() && string != "" {
            return false
        }
        return true
    }
    
}

extension LightSensorCalibrationView: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        
        if slider == lightLevelSlider {
            lightLevelValueLabel.text = "\(Int(value))%"
        }else {
            delegate?.view(self, adjustSpeedChanged: Int(value))
        }
    }
    
    
    /// 滑动条数值修改回调（限流）
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    ///   - ended: 是否滑动结束
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        if slider == lightLevelSlider { // 回调
//            lightLevelLabel.text = "\(Int(value))%"
            delegate?.view(self, lightLevelValueChanged: Int(lightLevelSlider.value))
        }
    }
    
}
