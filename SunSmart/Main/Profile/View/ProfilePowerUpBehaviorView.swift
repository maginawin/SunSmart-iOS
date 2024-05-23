//
//  ProfilePowerUpBehaviorView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

protocol ProfilePowerUpBehaviorViewDelegate: AnyObject {
    
    /// 帮助
    func powerUpBehaviorViewHelpAction(view: ProfilePowerUpBehaviorView)
    
    /// 上电状态
    /// - Parameters:
    ///   - view: view
    ///   - state: 上电状态
    func view(_ view: ProfilePowerUpBehaviorView, powerStateChanged state: Profile.PowerUpState)
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
    /// 滑块view
    private var sliderView: UIView!
    /// 当前值
    private var valueLabel: UILabel!
    /// 滑条
    var slider: CustomDeviceSlider!
    /// 增加
    private var addBtn: UIButton!
    /// 减少
    private var minusBtn: UIButton!
    /// 记录上次选中的按键
    private var lastSelectBtn: UIButton?
    
    weak var delegate: ProfilePowerUpBehaviorViewDelegate?
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
                slider.value = Float(level)
            }
            
            updateUI()
            updateValue()
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = 10
        backgroundColor = .white
        
        setupUI()
        restoreBtn.isSelected = true
        lastSelectBtn = restoreBtn
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func helpBtnAction() {
        delegate?.powerUpBehaviorViewHelpAction(view: self)
    }
    
    @objc private func keepLightOffBtnAction(sender: UIButton) {
 
        if sender != lastSelectBtn {
            sender.isSelected = true
            lastSelectBtn?.isSelected = false
            if lastSelectBtn == definedLightLevelBtn {
                updateUI()
            }
            lastSelectBtn = sender
            
            delegate?.view(self, powerStateChanged: .off)
        }
    }
    
    @objc private func restoreBtnAction(sender: UIButton) {
        
        if sender != lastSelectBtn {
            sender.isSelected = true
            lastSelectBtn?.isSelected = false
            if lastSelectBtn == definedLightLevelBtn {
                updateUI()
            }
            lastSelectBtn = sender
            
            delegate?.view(self, powerStateChanged: .restore)
        }
    }
    
    @objc private func definedLightLevelBtnAction(sender: UIButton) {
        if sender != lastSelectBtn {
            sender.isSelected = true
            lastSelectBtn?.isSelected = false
            if lastSelectBtn != definedLightLevelBtn {
                updateUI()
            }
            lastSelectBtn = sender
            slider.value = 50
            updateValue()
            delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(Int(slider.value))))
        }
    }
    
    @objc private func addBtnClick() {
        
        slider.value = min(slider.value + 1, slider.maximumValue)
        updateValue()
        delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(Int(slider.value))))
    }
    
    @objc private func minusBtnClick() {
        
        slider.value = max(slider.value - 1, slider.minimumValue)
        updateValue()
        delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(Int(slider.value))))
    }
    
    private func updateValue() {
        
        valueLabel.text = "\(Int(slider.value))%"
    }
    
    private func updateUI() {
        
        let isShow = definedLightLevelBtn.isSelected
        sliderView.snp.updateConstraints { make in
            make.height.equalTo(isShow ? SCRYFrom(76) : 0)
        }
        sliderView.isHidden = !isShow
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
        
        sliderView = UIView()
        sliderView.isHidden = true
        addSubview(sliderView)
        sliderView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(definedLightLevelBtn.snp.bottom)
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(0)
        }
        
        valueLabel = UILabel(text: "50%", textColor: TextBlack_Color, fontWeight: .light)
        sliderView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(4))
//            make.centerY.equalTo(timeoutLabel)
        }

        addBtn = UIButton(normalImageName: "scene_data_value_add", target: self, action: #selector(addBtnClick))
        sliderView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-9))
        }
        
        minusBtn = UIButton(normalImageName: "scene_data_value_minus", target: self, action: #selector(minusBtnClick))
        sliderView.addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalTo(addBtn)
        }
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.minimumTrackTintColor = RGB(255, 167, 44)
        slider.maximumTrackTintColor = RGB(229, 229, 229)
        slider.layer.cornerRadius = 2
        slider.minimumValue = 0
        slider.maximumValue = 100
        slider.value = 50
        slider.throttle = true
        slider.delegate = self
        sliderView.addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(61))
            make.right.equalTo(SCRXFrom(-62))
            make.centerY.equalTo(addBtn)
            make.height.equalTo(SCRYFrom(40))
        }
    }
    
}

extension ProfilePowerUpBehaviorView: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        
        updateValue()
        delegate?.view(self, powerStateChanged: .definedLightLevel(UInt8(Int(slider.value))))
    }
    
}
