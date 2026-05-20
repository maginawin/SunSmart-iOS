//
//  ProfilePowerUpBehaviorView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit
import NordicSigMeshSDK

protocol ProfilePowerUpBehaviorViewDelegate: AnyObject {
    
    /// 帮助
    func powerUpBehaviorViewHelpAction(view: ProfilePowerUpBehaviorView)
    
    /// 上电状态
    /// - Parameters:
    ///   - view: view
    ///   - state: 上电状态
    ///   - powerOnCct: 上电色温（state: 自定义时）
    func view(_ view: ProfilePowerUpBehaviorView, powerStateChanged state: Profile.PowerUpState, powerOnCct: UInt16?)
    
    /// 禁止交互下编辑事件
    func powerUpBehaviorViewDisableEditAction(view: ProfilePowerUpBehaviorView)
}

class ProfilePowerUpBehaviorView: UIView {

    private var titleLabel: UILabel!
    private var helpBtn: UIButton!
    /// 保持关闭
    private var keepLightOffBtn: UIButton!
    /// 上次状态
    private var restoreBtn: UIButton!
    /// 自定义目标值
    private var definedLightLevelBtn: UIButton!
    /// 亮度滑块view
    var lightnessSliderView: PowerUpLightSliderView!
    /// 色温滑块view
    var cctSliderView: PowerUpLightSliderView!
    /// 记录上次选中的按键
    private var lastSelectBtn: UIButton?
    
    weak var delegate: ProfilePowerUpBehaviorViewDelegate?
    var cctRange: ClosedRange<UInt16> = NodeAbsoluteCctRange.defaultRange {
        didSet {
            guard let cctSliderView = cctSliderView else {
                return
            }
            cctSliderView.slider.minimumValue = Float(cctRange.lowerBound)
            cctSliderView.slider.maximumValue = Float(cctRange.upperBound)
            cctSliderView.slider.value = Float(clampedCct(UInt16(cctSliderView.slider.value)))
            updateValue()
        }
    }
    /// 上电状态
    var powerState: Profile.PowerUpState = .restore {
        didSet {
            lastSelectBtn?.isSelected = false
            switch powerState {
            case .off:
                lastSelectBtn = keepLightOffBtn
                keepLightOffBtn.isSelected = true
            case .restore:
                lastSelectBtn = restoreBtn
                restoreBtn.isSelected = true
            case .definedLightLevel(let level):
                lastSelectBtn = definedLightLevelBtn
                definedLightLevelBtn.isSelected = true
                lightnessSliderView.slider.value = Float(level)
            }
            
            updateUI()
            updateValue()
        }
    }
    /// 上电色温
    var powerOnCct: UInt16? {
        didSet {
            guard let cct = powerOnCct else {
                cctSliderView.isHidden = true
                return
            }

            cctSliderView.slider.value = Float(clampedCct(cct))
            updateUI()
            updateValue()
        }
    }
    
    /// 是否可编辑
    var editable: Bool = true {
        didSet {
            lightnessSliderView.editable = editable
            cctSliderView.editable = editable
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setupUI()
        restoreBtn.isSelected = true
        lastSelectBtn = restoreBtn
        
        bindSliderAction()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func helpBtnAction() {
        delegate?.powerUpBehaviorViewHelpAction(view: self)
    }
    
    @objc private func keepLightOffBtnAction(sender: UIButton) {
 
        guard editable else {
            delegate?.powerUpBehaviorViewDisableEditAction(view: self)
            return
        }
        
        if sender != lastSelectBtn {
            sender.isSelected = true
            lastSelectBtn?.isSelected = false
            if lastSelectBtn == definedLightLevelBtn {
                updateUI()
            }
            lastSelectBtn = sender
            
            delegate?.view(self, powerStateChanged: .off, powerOnCct: nil)
        }
    }
    
    @objc private func restoreBtnAction(sender: UIButton) {
        
        guard editable else {
            delegate?.powerUpBehaviorViewDisableEditAction(view: self)
            return
        }
        
        if sender != lastSelectBtn {
            sender.isSelected = true
            lastSelectBtn?.isSelected = false
            if lastSelectBtn == definedLightLevelBtn {
                updateUI()
            }
            lastSelectBtn = sender
            
            delegate?.view(self, powerStateChanged: .restore, powerOnCct: nil)
        }
    }
    
    @objc private func definedLightLevelBtnAction(sender: UIButton) {
        
        guard editable else {
            delegate?.powerUpBehaviorViewDisableEditAction(view: self)
            return
        }
        
        if sender != lastSelectBtn {
            sender.isSelected = true
            lastSelectBtn?.isSelected = false
            if lastSelectBtn != definedLightLevelBtn {
                updateUI()
            }
            lastSelectBtn = sender
            lightnessSliderView.slider.value = 50
            cctSliderView.slider.value = Float(clampedCct(4500))
            
            updateValue()
            delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(Int(lightnessSliderView.slider.value))), powerOnCct: UInt16(cctSliderView.slider.value))
        }
    }
    
    
    private func updateValue() {
        
        lightnessSliderView.valueLabel.text = "\(Int(lightnessSliderView.slider.value))%"
        cctSliderView.valueLabel.text = "\(Int(cctSliderView.slider.value))K"
    }

    private func clampedCct(_ value: UInt16) -> UInt16 {
        min(cctRange.upperBound, max(cctRange.lowerBound, value))
    }
    
    private func updateUI() {
        
        let isShow = definedLightLevelBtn.isSelected
        let showCct = isShow && powerOnCct != nil
        
        lightnessSliderView.snp.updateConstraints { make in
            make.height.equalTo(isShow ? SCRYFrom(76) : 0)
            make.bottom.equalTo(-SCRYFrom(16 + (showCct ? 12 + 76 : 0)))
        }
        lightnessSliderView.isHidden = !isShow
        
        cctSliderView.snp.updateConstraints { make in
            make.height.equalTo(showCct ? SCRYFrom(76) : 0)
        }
        cctSliderView.isHidden = !showCct
        
//        UIView.animate(withDuration: 0.25) {
//            self.sliderView.isHidden = !isShow
//        }
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "power_up_behavior".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.left.equalTo(titleLabel.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(titleLabel)
        }
    
        keepLightOffBtn = UIButton(title: "keep_light_off".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "schedule_target_select_un", selectedImageName: "schedule_target_select", target: self, action: #selector(keepLightOffBtnAction))
        keepLightOffBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(keepLightOffBtn)
        keepLightOffBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(SCRYFrom(30))
        }
        
        restoreBtn = UIButton(title: "restore".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "schedule_target_select_un", selectedImageName: "schedule_target_select", target: self, action: #selector(restoreBtnAction))
        restoreBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(restoreBtn)
        restoreBtn.snp.makeConstraints { make in
            make.left.equalTo(keepLightOffBtn)
            make.top.equalTo(keepLightOffBtn.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(30))
        }
        
        definedLightLevelBtn = UIButton(title: "defined_light_level".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "schedule_target_select_un", selectedImageName: "schedule_target_select", target: self, action: #selector(definedLightLevelBtnAction))
        definedLightLevelBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(definedLightLevelBtn)
        definedLightLevelBtn.snp.makeConstraints { make in
            make.left.equalTo(keepLightOffBtn)
            make.top.equalTo(restoreBtn.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(30))
        }
        
        lightnessSliderView = PowerUpLightSliderView()
        lightnessSliderView.slider.minimumValue = 1
        lightnessSliderView.isHidden = true
        
        addSubview(lightnessSliderView)
        lightnessSliderView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(definedLightLevelBtn.snp.bottom)
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(0)
        }
        
        cctSliderView = PowerUpLightSliderView()
        cctSliderView.slider.minimumValue = Float(cctRange.lowerBound)
        cctSliderView.slider.maximumValue = Float(cctRange.upperBound)
        cctSliderView.isHidden = true
        cctSliderView.slider.gradientColors = [RGB(255, 108, 0), .white, RGB(114, 179, 255)]
        addSubview(cctSliderView)
        cctSliderView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(lightnessSliderView.snp.bottom).offset(SCRYFrom(12))
//            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(0)
        }
        
    }
    
    private func bindSliderAction() {
        
        lightnessSliderView.valueChangedCallback = {[weak self] lightness in
            guard let self = self else { return }
            let cct: UInt16? = cctSliderView.isHidden ? nil : UInt16(cctSliderView.slider.value)
            delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(lightness)), powerOnCct: cct)
            
            self.updateValue()
        }
        lightnessSliderView.disableEditActionCallback = {[weak self] in
            guard let self = self else { return }
            self.delegate?.powerUpBehaviorViewDisableEditAction(view: self)
        }
        
        cctSliderView.valueChangedCallback = {[weak self] cct in
            guard let self = self else { return }
            delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(self.lightnessSliderView.slider.value)), powerOnCct: UInt16(cct))
            
            self.updateValue()
        }
        cctSliderView.disableEditActionCallback = {[weak self] in
            guard let self = self else { return }
            self.delegate?.powerUpBehaviorViewDisableEditAction(view: self)
        }
        
    }
    
}

class PowerUpLightSliderView: UIView {
    
    /// 当前值
    var valueLabel: UILabel!
    /// 滑条
    var slider: CustomDeviceSlider!
    /// 增加
    private var addBtn: UIButton!
    /// 减少
    private var minusBtn: UIButton!
    /// 数值变更回调
    var valueChangedCallback: ((Int)->Void)?
    /// 不可编辑状态下修改滑条
    var disableEditActionCallback: (()->Void)?
    
    /// 是否可编辑
    var editable: Bool = true
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        valueLabel = UILabel(text: "50%", textColor: TextBlack_Color, fontWeight: .light)
        addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(4))
//            make.centerY.equalTo(timeoutLabel)
        }

        addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
        addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-9))
        }
        
        minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
        addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalTo(addBtn)
        }
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.minimumTrackTintColor = Slider_Color
        slider.maximumTrackTintColor = RGB(229, 229, 229)
        slider.layer.cornerRadius = 2
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.value = 50
        slider.throttle = true
        slider.delegate = self
        addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(61))
            make.right.equalTo(SCRXFrom(-62))
            make.centerY.equalTo(addBtn)
            make.height.equalTo(SCRYFrom(40))
        }
    }
    
    @objc private func addBtnClick() {
        
        guard editable else {
//            delegate?.powerUpBehaviorViewDisableEditAction(view: self)
            disableEditActionCallback?()
            return
        }
        
        slider.value = min(slider.value + 1, slider.maximumValue)
//        updateValue()
        valueChangedCallback?(Int(slider.value))
    }
    
    @objc private func minusBtnClick() {
        
        guard editable else {
            disableEditActionCallback?()
            return
        }
        
        slider.value = max(slider.value - 1, slider.minimumValue)
        valueChangedCallback?(Int(slider.value))
    }
    
    
}

extension PowerUpLightSliderView: CustomDeviceSliderDelegate {
    
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool {
        if !editable {
            disableEditActionCallback?()
        }
        return editable
    }
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        
        valueChangedCallback?(Int(value))
    }
    
}
