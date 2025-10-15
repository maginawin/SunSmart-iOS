//
//  DeviceAddParameterSettingsView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/12.
//

import UIKit
import MediaPlayer


class DeviceAddParameterSettingsView: UIView {
  
    /// 设置数据回调
    typealias SettingsCallback = (DeviceSettingsParameterData) -> Void
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    
    /// 亮度
    private var brightnessTitleLabel: UILabel!
    private var brightnessTipLabel: UILabel!
    private var brightnessLabel: UILabel!
    private var brightnessView: DeviceSliderFunctionView!
    
    /// 光照差值
    private var illuminationTitleLabel: UILabel!
    private var illuminationTipLabel: UILabel!
    private var illuminationLabel: UILabel!
    private var illuminationView: DeviceSliderFunctionView!
    private var illuminationTagsView: UIStackView!
    
    /// 通知
    private var notificationLabel: UILabel!
    private var notificationSwitch: UISwitch!
    private var notificationSwitchBtn: UIButton!
    
    private var volumeLabel: UILabel!
    private var volumeSliderView: DeviceSliderFunctionView!

    /// 震动
    private var vibrationLabel: UILabel!
    private var vibrationSwitch: UISwitch!
    
    /// 帮助
    private var helpBtn: UIButton!
    
    private var functionView: UIView!
    private var lineView: UIView!
    private var saveBtn: UIButton!
    private var cancelBtn: UIButton!
    /// 照度值标签
    private let illuminationTags: [(title: String, illumination: Int)] = [
        ("＞15m", 10), ("12m", 20), ("9m", 30), ("6m", 40), ("＜3m", 50)
    ]
    
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?
   
    var parameterData: DeviceSettingsParameterData = .default {
        didSet {
            brightnessView.value = Int(parameterData.brightness)
            brightnessLabel.text = "\(parameterData.brightness)%"
            illuminationView.value = Int(parameterData.illuminationDelta)
            illuminationLabel.text = "\(parameterData.illuminationDelta)"
            notificationSwitch.isOn = parameterData.notificationEnable
            volumeSliderView.value = parameterData.volume
            volumeLabel.text = "\(parameterData.volume)%"
            vibrationSwitch.isOn = parameterData.vibrationEnable
        }
    }
    var volumeChangedEndCallback: ((Int)->Void)?
    var settingsCallback: SettingsCallback?
    
    /// 帮助事件回调
    var helpActionCallback: (()->Void)?
    /// 是否显示亮度值
    var showBrightness: Bool = true
    
    init(frame: CGRect, parameterData: DeviceSettingsParameterData = .default, showBrightness: Bool = true) {
        super.init(frame: frame)
        
        // 监听系统音量变化
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(volumeUpdateUI),
//            name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"),
//            object: nil
//        )
        // 后台进入前台通知
//        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: nil) {[weak self] _ in
//            
//            SystemVolumeManager.shared.refreshVolume()
//            self?.volumeUpdateUI()
//        }
        
        SystemVolumeManager.shared.onVolumeChanged = {[weak self] volume in
//            print(volume)
            self?.volumeUpdateUI()
        }
        
        // 激活 AVAudioSession（否则监听可能无效）
//        try? AVAudioSession.sharedInstance().setActive(true, options: [])

//        systemVolumeObservation = AVAudioSession.sharedInstance().observe(\.outputVolume, options: [.new], changeHandler: {[weak self] _, _ in
//            DispatchQueue.main.async {
//                self?.volumeUpdateUI()
//            }
//        })
        self.showBrightness = showBrightness
        self.parameterData = parameterData
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
//        systemVolumeObservation = nil
//        NotificationCenter.default.removeObserver(self)
    }
    
    func show() {
        
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        
        volumeUpdateUI()
        
        shadeView.alpha = 0
        contentView.alpha = 0
//        if functionView != nil {
//
//        }
        functionView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
            self.functionView?.alpha = 1
        } completion: {[weak self] _ in
            guard let self = self else { return }
            if SystemVolumeManager.shared.currentVolume < 0.2 {
                XWHUDManager.showTipHUD(in: self.contentView, message: "系统音量不足20%", isLineFeed: true)
            }
        }

    }
    
    func dismiss() {
        
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
            self.functionView?.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }

    }

    @objc private func volumeUpdateUI() {
        
        let volume = SystemVolumeManager.shared.currentVolume //VolumeManager.getSystemVolume()
        notificationSwitch.isEnabled = volume > 0.2
        notificationSwitchBtn.isUserInteractionEnabled = !notificationSwitch.isEnabled
        
        if notificationSwitch.isEnabled && notificationSwitch.isOn {
            volumeSliderView.slider.isEnabled = true
            volumeSliderView.minusBtn.isEnabled = true
            volumeSliderView.addBtn.isEnabled = true
            volumeLabel.textColor = TextBlack_Color
            
        }else {
            volumeSliderView.slider.isEnabled = false
            volumeSliderView.minusBtn.isEnabled = false
            volumeSliderView.addBtn.isEnabled = false
            volumeLabel.textColor = TextBlack_Color.withAlphaComponent(0.5)
        }
    }
    
    @objc private func shadeViewAction() {

        dismiss()
    }
    
    @objc private func notificationSwitchValueChanged(sender: UISwitch) {
        
        volumeUpdateUI()
        
    }
    
    /// 通知因系统音量无效时提示
    @objc private func notificationSwitchBtnAction() {
        XWHUDManager.showTipHUD(in: self.contentView, message: "系统音量不足20%", isLineFeed: true)
    }
    
    @objc private func saveBtnAction() {
        
        let data = DeviceSettingsParameterData(brightness: UInt8(brightnessView.value), illuminationDelta: UInt16(illuminationView.value), notificationEnable: notificationSwitch.isOn, volume: volumeSliderView.value, vibrationEnable: vibrationSwitch.isOn)
        settingsCallback?(data)
        dismiss()
    }
    
    /// 帮助
    @objc private func helpBtnAction() {
        helpActionCallback?()
    }
    
    @objc private func cancelBtnAction() {
        dismiss()
    }
    
    @objc private func illuminationBtnAction(sender: UIButton) {
        let tag = illuminationTags[sender.tag - 100]
        self.illuminationView.value = tag.illumination
        self.illuminationLabel.text = "△\(tag.illumination)"
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeViewAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        functionView = UIView()
        functionView.backgroundColor = .white
        functionView.layer.cornerRadius = SCRYFrom(15)
        addSubview(functionView)
        functionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(SCRYFrom(-34))
            make.height.equalTo(SCRYFrom(60))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(216, 216, 216)
        functionView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(24))
        }
                    
        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(saveBtnAction))
        functionView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.left.equalTo(lineView.snp.right).offset(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleWeight: .light, titleColor: SubText_Color, target: self, action: #selector(cancelBtnAction))
        functionView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(lineView.snp.left).offset(SCRXFrom(-20))
            make.centerY.height.equalTo(saveBtn)
        }
        
        contentView = UIView()
        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(15)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(functionView.snp.top).offset(SCRYFrom(-8))
//            make.height.equalTo(SCRYFrom(240))
        }
        
        titleLabel = UILabel(text: "settings".localizedString, textColor: ImportantText_Color, fontSize: 16)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        contentView.addSubview(helpBtn)
        helpBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(titleLabel)
        }
        
        brightnessTitleLabel = UILabel(text: "brightness_of_the_device_in_mode".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(brightnessTitleLabel)
        brightnessTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
        }
        
        brightnessTipLabel = UILabel(text: "brightness_of_the_device_in_mode_tip".localizedString, textColor: SubText_Color, fontSize: 12)
        contentView.addSubview(brightnessTipLabel)
        brightnessTipLabel.snp.makeConstraints { make in
            make.top.equalTo(brightnessTitleLabel.snp.bottom).offset(SCRYFrom(3))
            make.left.equalTo(brightnessTitleLabel)
            make.right.equalTo(SCRXFrom(-20))
        }
        
        brightnessLabel = UILabel(text: "\(parameterData.brightness)%", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(brightnessLabel)
        brightnessLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(brightnessTitleLabel.snp.bottom).offset(SCRYFrom(15))
        }
        
        brightnessView = DeviceSliderFunctionView(frame: .zero, title: "", value: Int(parameterData.brightness), functionType: .level())
        brightnessView.minLabel.isHidden = true
        brightnessView.maxLabel.isHidden = true
        brightnessView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        brightnessView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        brightnessView.lineView.isHidden = true
        brightnessView.titleLabel.isHidden = true
        brightnessView.valueChangedCallback = {[weak self] value in
            self?.brightnessLabel.text = "\(value)%"
        }
        contentView.addSubview(brightnessView)
        brightnessView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(brightnessTitleLabel.snp.bottom).offset(SCRYFrom(44))
            make.height.equalTo(SCRYFrom(40))
        }
        brightnessView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        brightnessView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        brightnessView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
        
        illuminationTitleLabel = UILabel(text: "illumination_fluctuation_range".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(illuminationTitleLabel)
        illuminationTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(brightnessView.snp.bottom).offset(SCRYFrom(20))
        }
        
        illuminationTipLabel = UILabel(text: "illumination_fluctuation_range_tip".localizedString, textColor: SubText_Color, fontSize: 12)
        contentView.addSubview(illuminationTipLabel)
        illuminationTipLabel.snp.makeConstraints { make in
            make.top.equalTo(illuminationTitleLabel.snp.bottom).offset(SCRYFrom(3))
            make.left.right.equalTo(illuminationTitleLabel)
        }
        
        illuminationLabel = UILabel(text: "△\(parameterData.illuminationDelta)", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(illuminationLabel)
        illuminationLabel.snp.makeConstraints { make in
            make.right.equalTo(brightnessLabel)
            make.top.equalTo(illuminationTipLabel.snp.bottom)
        }
        
        illuminationView = DeviceSliderFunctionView(frame: .zero, title: "", value: Int(parameterData.illuminationDelta), functionType: .level(min: 0, max: 500, step: 1))
        illuminationView.minLabel.isHidden = true
        illuminationView.maxLabel.isHidden = true
        illuminationView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        illuminationView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        illuminationView.lineView.isHidden = true
        illuminationView.titleLabel.isHidden = true
        illuminationView.valueChangedCallback = {[weak self] value in
            self?.illuminationLabel.text = "△\(value)"
        }
        contentView.addSubview(illuminationView)
        illuminationView.snp.makeConstraints { make in
            make.left.right.height.equalTo(brightnessView)
            make.top.equalTo(illuminationTitleLabel.snp.bottom).offset(SCRYFrom(44))
        }
        illuminationView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        illuminationView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        illuminationView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
        illuminationTagsView = UIStackView()
        illuminationTagsView.axis = .horizontal
        illuminationTagsView.spacing = SCRXFrom(isIPad ? 20 : 10)
        illuminationTagsView.distribution = .fillEqually
        contentView.addSubview(illuminationTagsView)
        illuminationTagsView.snp.makeConstraints { make in
            make.left.right.equalTo(illuminationView)
            make.top.equalTo(illuminationView.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(30))
        }
        
        notificationLabel = UILabel(text: "notification_volume".localizedString, textColor: ImportantText_Color, fontSize: 15)
        contentView.addSubview(notificationLabel)
        notificationLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(illuminationTagsView.snp.bottom).offset(SCRYFrom(27))
        }
        
        notificationSwitch = UISwitch()
        notificationSwitch.isOn = parameterData.notificationEnable
        notificationSwitch.onTintColor = Bar_Color
        notificationSwitch.addTarget(self, action: #selector(notificationSwitchValueChanged), for: .valueChanged)
        contentView.addSubview(notificationSwitch)
        notificationSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(notificationLabel)
        }
        
        notificationSwitchBtn = UIButton(target: self, action: #selector(notificationSwitchBtnAction))
        notificationSwitchBtn.isUserInteractionEnabled = false
        contentView.addSubview(notificationSwitchBtn)
        notificationSwitchBtn.snp.makeConstraints { make in
            make.edges.equalTo(notificationSwitch)
        }
        
        
        volumeLabel = UILabel(text: "\(parameterData.volume)%", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(volumeLabel)
        volumeLabel.snp.makeConstraints { make in
            make.right.equalTo(illuminationLabel)
            make.top.equalTo(notificationSwitch.snp.bottom).offset(SCRYFrom(8))
        }
        
        volumeSliderView = DeviceSliderFunctionView(frame: .zero, title: "", value: parameterData.volume, functionType: .level())
        volumeSliderView.minLabel.isHidden = true
        volumeSliderView.maxLabel.isHidden = true
        volumeSliderView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        volumeSliderView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        volumeSliderView.lineView.isHidden = true
        volumeSliderView.titleLabel.isHidden = true
        volumeSliderView.valueChangedCallback = {[weak self] value in
            self?.volumeLabel.text = "\(value)%"
        }
        volumeSliderView.throttleValueChangedCallback = {[weak self] value, ended in
            if ended {
                self?.volumeChangedEndCallback?(value)
            }
        }
        contentView.addSubview(volumeSliderView)
        volumeSliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(volumeLabel.snp.bottom).offset(SCRYFrom(13))
            make.height.equalTo(SCRYFrom(40))
        }
        volumeSliderView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        volumeSliderView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        volumeSliderView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
        vibrationLabel = UILabel(text: "vibration".localizedString, textColor: ImportantText_Color, fontSize: 15)
        contentView.addSubview(vibrationLabel)
        vibrationLabel.snp.makeConstraints { make in
            make.left.equalTo(notificationLabel)
            make.top.equalTo(volumeSliderView.snp.bottom).offset(SCRYFrom(27))
            make.bottom.equalTo(SCRYFrom(-37))
        }
        
        vibrationSwitch = UISwitch()
        vibrationSwitch.isOn = parameterData.vibrationEnable
        vibrationSwitch.onTintColor = Bar_Color
        contentView.addSubview(vibrationSwitch)
        vibrationSwitch.snp.makeConstraints { make in
            make.right.equalTo(notificationSwitch)
            make.centerY.equalTo(vibrationLabel)
        }
        
        if !showBrightness {
            brightnessTitleLabel.isHidden = true
            brightnessLabel.isHidden = true
            brightnessTipLabel.isHidden = true
            brightnessView.isHidden = true
            illuminationTitleLabel.snp.remakeConstraints({ make in
                make.left.equalTo(SCRXFrom(20))
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            })
        }
        
        if isIPad {
            vibrationLabel.isHidden = true
            vibrationSwitch.isHidden = true
            vibrationSwitch.isOn = false
        }
        
        setupIlluminationTags()
        
//        // 添加系统音量滑块（会显示系统音量UI）
//        let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
//        volumeView.isHidden = true  // 隐藏但保持功能
//        contentView.addSubview(volumeView)
//        volumeView.vol
    }
    
    private func setupIlluminationTags() {
        
        illuminationTags.enumerated().forEach { (index, data) in
            let button = UIButton(title: data.title, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(illuminationBtnAction))
            button.tag = 100 + index
            button.layer.borderColor = Bar_Color.withAlphaComponent(0.5).cgColor
            button.layer.borderWidth = 0.6
            button.layer.cornerRadius = SCRYFrom(15)
            illuminationTagsView.addArrangedSubview(button)
        }
        
    }
    
}

//class VolumeManager {
//    private static let volumeView = MPVolumeView(frame: .zero)
//    
//    static func setSystemVolume(_ volume: Float) {
//        // 确保在主线程执行
//        guard Thread.isMainThread else {
//            return
//        }
//        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else {
//            print("无法找到音量滑块")
//            return
//        }
//        
//        // 设置音量值（0.0到1.0之间）
//        slider.value = min(max(volume, 0.0), 1.0)
//        
//    }
//    
//    static func getSystemVolume() -> Float {
//        try? AVAudioSession.sharedInstance().setActive(true)
//        return AVAudioSession.sharedInstance().outputVolume
//    }
//}
