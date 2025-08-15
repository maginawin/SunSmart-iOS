//
//  DeviceAddParameterSettingsView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/12.
//

import UIKit
import MediaPlayer

struct DeviceAddParameterData {
    
    static let `default`: DeviceAddParameterData = .init(notificationEnable: true, volume: 50, vibrationEnable: true)
    
    let notificationEnable: Bool
    let volume: Int
    let vibrationEnable: Bool
}

class DeviceAddParameterSettingsView: UIView {
  
    /// 设置数据回调
    typealias SettingsCallback = (DeviceAddParameterData) -> Void
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    
    private var notificationLabel: UILabel!
    private var notificationSwitch: UISwitch!
    private var notificationSwitchBtn: UIButton!
    
    private var volumeLabel: UILabel!
    private var volumeSliderView: DeviceSliderFunctionView!

    private var vibrationLabel: UILabel!
    private var vibrationSwitch: UISwitch!
    
    private var functionView: UIView!
    private var lineView: UIView!
    private var saveBtn: UIButton!
    private var cancelBtn: UIButton!
   
    private var parameterData: DeviceAddParameterData = .default
    var volumeChangedEndCallback: ((Int)->Void)?
    var settingsCallback: SettingsCallback?
    
    init(frame: CGRect, parameterData: DeviceAddParameterData = .default) {
        super.init(frame: frame)
        self.parameterData = parameterData
        
        // 监听系统音量变化
//        NotificationCenter.default.addObserver(
//            self,
//            selector: #selector(volumeUpdateUI),
//            name: NSNotification.Name(rawValue: "AVSystemController_SystemVolumeDidChangeNotification"),
//            object: nil
//        )
        AVAudioSession.sharedInstance().addObserver(self, forKeyPath: "outputVolume", options: .new, context: nil)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        AVAudioSession.sharedInstance().removeObserver(self, forKeyPath: "outputVolume")
    }
    
    func show() {
        
        if self.superview == nil {
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
        } completion: { _ in
            if AVAudioSession.sharedInstance().outputVolume < 0.2 {
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
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        self.volumeUpdateUI()
    }

    @objc private func volumeUpdateUI() {
        let volume = AVAudioSession.sharedInstance().outputVolume
        
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
        
        let data = DeviceAddParameterData(notificationEnable: notificationSwitch.isOn, volume: volumeSliderView.value, vibrationEnable: vibrationSwitch.isOn)
        settingsCallback?(data)
        dismiss()
    }
    
    @objc private func cancelBtnAction() {
        dismiss()
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
            make.height.equalTo(SCRYFrom(240))
        }
        
        titleLabel = UILabel(text: "settings".localizedString, textColor: ImportantText_Color, fontSize: 16)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        notificationLabel = UILabel(text: "notification_volume".localizedString, textColor: ImportantText_Color, fontSize: 15)
        contentView.addSubview(notificationLabel)
        notificationLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20))
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
            make.right.equalTo(SCRXFrom(-47))
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
        }
        
        vibrationSwitch = UISwitch()
        vibrationSwitch.isOn = parameterData.vibrationEnable
        vibrationSwitch.onTintColor = Bar_Color
        contentView.addSubview(vibrationSwitch)
        vibrationSwitch.snp.makeConstraints { make in
            make.right.equalTo(notificationSwitch)
            make.centerY.equalTo(vibrationLabel)
        }
        
        
//        // 添加系统音量滑块（会显示系统音量UI）
//        let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
//        volumeView.isHidden = true  // 隐藏但保持功能
//        contentView.addSubview(volumeView)
//        volumeView.vol
    }
}

class VolumeManager {
    private static let volumeView = MPVolumeView(frame: .zero)
    
    static func setSystemVolume(_ volume: Float) {
        // 确保在主线程执行
        guard Thread.isMainThread else {
            return
        }
        guard let slider = volumeView.subviews.compactMap({ $0 as? UISlider }).first else {
            print("无法找到音量滑块")
            return
        }
        
        // 设置音量值（0.0到1.0之间）
        slider.value = min(max(volume, 0.0), 1.0)
        
    }
    
    static func getSystemVolume() -> Float {
        return AVAudioSession.sharedInstance().outputVolume
    }
}
