//
//  LightSensorManualCorrectionView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/12.
//

import UIKit

class LightSensorManualCorrectionView: UIView {

    typealias RatioSaveCallback = ((UInt16, UInt16)->Void)
    
    private var shadeView: UIView!
    private var contentView: UIView!
    private var titleLabel: UILabel!
    private var noteLabel: UILabel!
    private var calibrationPointLabel: UILabel!
    private var lightLuxLabel: UILabel!
    
    private var sensorRatioTitleLabel: UILabel!
    private var sensorRatioSliderView: DeviceSliderFunctionView!
    private var sensorRatioLabel: UILabel!
    private var sensorRatioRestoreBtn: UIButton!
    
    private var ambientLightRatioTitleLabel: UILabel!
    private var ambientLightRatioSliderView: DeviceSliderFunctionView!
    private var ambientLightRatioLabel: UILabel!
    private var ambientLightRatioRestoreBtn: UIButton!
    
    private var bottomView: UIView!
    private var saveBtn: UIButton!
    private var cancelBtn: UIButton!

    private var sensorRatio: UInt16 = 100
    private var ambientLightRatio: UInt16 = 100
    private var saveCallback: RatioSaveCallback?
    
    private var updateLuxTimer: Timer?
    
    var daylightLux: UInt16 = 0 {
        didSet {
            lightLuxLabel.text = "\(daylightLux) lx"
            lightLuxLabel.backgroundColor = RGB(179, 237, 103)
            startUpdateLuxTimer()
        }
    }
    
    init(daylightLux: UInt16, sensorRatio: UInt16, ambientLightRatio: UInt16, saveCallback: RatioSaveCallback?) {
        super.init(frame: UIScreen.main.bounds)
        
        self.daylightLux = daylightLux
        self.sensorRatio = sensorRatio
        self.ambientLightRatio = ambientLightRatio
        self.saveCallback = saveCallback
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func show() {
        
        if self.superview == nil {
            self.tag = 100
            UIApplication.shared.keyWindow().addSubview(self)
        }
        
        shadeView.alpha = 0
        contentView.alpha = 0
        bottomView.alpha = 0
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 1
            self.contentView.alpha = 1
            self.bottomView.alpha = 1
        }

    }
    
    func dismiss() {
        UIView.animate(withDuration: 0.3) {
            self.shadeView.alpha = 0
            self.contentView.alpha = 0
            self.bottomView.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
        }
    }
    
    
    @objc private func sensorRatioRestoreBtnAction() {
        
        sensorRatioSliderView.value = Int(Double(sensorRatio) / 10.0)
        sensorRatioLabel.text = (Double(sensorRatioSliderView.value) / 10.0).toSimplifyStr(maxDigits: 1)
    }
    
    @objc private func ambientLightRatioRestoreBtnAction() {
        ambientLightRatioSliderView.value = Int(Double(ambientLightRatio) / 10.0)
        ambientLightRatioLabel.text = (Double(ambientLightRatioSliderView.value) / 10.0).toSimplifyStr(maxDigits: 1)
    }
    
    @objc private func cancelAction() {
        dismiss()
    }
    
    @objc private func saveBtnAction() {
        
        let sensorRatio = sensorRatioSliderView.value * 10
        let ambientLightRatio = ambientLightRatioSliderView.value * 10
        
        saveCallback?(UInt16(sensorRatio), UInt16(ambientLightRatio))
    }
    
    // MARK: - Timer
    /// 开始lux更新倒计时，3s内没有新的数据则变为灰色背景
    private func startUpdateLuxTimer() {
        
        stopUpdateLuxTimer()
        
        updateLuxTimer = LCWeakTimer.scheduledTimer(timeInterval: 3, aTarget: self, selector: #selector(updateLuxState), userInfo: nil, repeats: false)
        RunLoop.current.add(updateLuxTimer!, forMode: .common)
    }
    
    private func stopUpdateLuxTimer() {
        updateLuxTimer?.invalidate()
        updateLuxTimer = nil
    }
    
    @objc private func updateLuxState() {
        stopUpdateLuxTimer()
        lightLuxLabel.backgroundColor = RGB(245, 245, 245)
    }
    
    private func setupUI() {
        
        shadeView = UIView()
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(cancelAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        bottomView.layer.cornerRadius = SCRYFrom(15)
        addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.bottom.equalTo(-max(kSafeAreaBottomHeight, SCRYFrom(8)))
            make.height.equalTo(SCRYFrom(60))
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(cancelAction))
        bottomView.addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(bottomView.snp.centerX)
        }
        
        let lineView = UIView()
        lineView.backgroundColor = RGB(216, 216, 216)
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(24))
        }
        
        saveBtn = UIButton(title: "save".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(saveBtnAction))
        bottomView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.top.bottom.equalToSuperview()
            make.left.equalTo(bottomView.snp.centerX)
        }
        
        contentView = UIView()
        contentView.layer.cornerRadius = SCRYFrom(15)
        contentView.backgroundColor = .white
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.equalTo(bottomView)
            make.bottom.equalTo(bottomView.snp.top).offset(SCRYFrom(-8))
        }
        
        titleLabel = UILabel(text: "manual_correction".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        noteLabel = UILabel(text: "manual_correction_note".localizedString, textColor: Message_Color, fontSize: 13, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 0
        contentView.addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20))
        }
        
        calibrationPointLabel = UILabel(text: "calibration_point_title".localizedString, textColor: Title_Color, fontSize: 15, fit: false)
        contentView.addSubview(calibrationPointLabel)
        calibrationPointLabel.snp.makeConstraints { make in
            make.left.equalTo(noteLabel)
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(21))
        }
        
        lightLuxLabel = UILabel(text: "", textColor: .black, fontSize: 12)
        lightLuxLabel.textAlignment = .center
        lightLuxLabel.backgroundColor = RGB(245, 245, 245)
        lightLuxLabel.layer.cornerRadius = SCRYFrom(10)
        lightLuxLabel.layer.masksToBounds = true
        contentView.addSubview(lightLuxLabel)
        lightLuxLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(calibrationPointLabel)
            make.height.equalTo(SCRYFrom(20))
            make.width.equalTo(SCRXFrom(64))
        }
        
        sensorRatioTitleLabel = UILabel(text: "sensor_ratio".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(sensorRatioTitleLabel)
        sensorRatioTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(lightLuxLabel.snp.bottom).offset(SCRYFrom(28))
        }
        
        
        sensorRatioLabel = UILabel(text: (Double(sensorRatio) / 100.0).toSimplifyStr(maxDigits: 1), textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(sensorRatioLabel)
        sensorRatioLabel.snp.makeConstraints { make in
            make.centerY.equalTo(sensorRatioTitleLabel)
            make.right.equalTo(SCRXFrom(-20))
        }
        
        sensorRatioRestoreBtn = UIButton(normalImageName: "reset", target: self, action: #selector(sensorRatioRestoreBtnAction))
        contentView.addSubview(sensorRatioRestoreBtn)
        sensorRatioRestoreBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-64))
            make.centerY.equalTo(sensorRatioLabel)
        }
        
        sensorRatioSliderView = DeviceSliderFunctionView(frame: .zero, title: "", value: Int(sensorRatio / 10), functionType: .level(min: 0, max: 500, step: 1))
        sensorRatioSliderView.minLabel.isHidden = true
        sensorRatioSliderView.maxLabel.isHidden = true
        sensorRatioSliderView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        sensorRatioSliderView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        sensorRatioSliderView.lineView.isHidden = true
        sensorRatioSliderView.titleLabel.isHidden = true
        sensorRatioSliderView.valueChangedCallback = {[weak self] value in
            self?.sensorRatioLabel.text = (Double(value) / 10.0).toSimplifyStr(maxDigits: 1)
        }
        contentView.addSubview(sensorRatioSliderView)
        sensorRatioSliderView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(sensorRatioTitleLabel.snp.bottom).offset(SCRYFrom(22))
            make.height.equalTo(SCRYFrom(40))
        }
        sensorRatioSliderView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        sensorRatioSliderView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        sensorRatioSliderView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
        ambientLightRatioTitleLabel = UILabel(text: "ambient_light_ratio".localizedString, textColor: Title_Color, fontSize: 15)
        contentView.addSubview(ambientLightRatioTitleLabel)
        ambientLightRatioTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(sensorRatioTitleLabel)
            make.top.equalTo(sensorRatioSliderView.snp.bottom).offset(SCRYFrom(28))
        }
        
        ambientLightRatioLabel = UILabel(text: (Double(ambientLightRatio) / 100.0).toSimplifyStr(maxDigits: 1), textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(ambientLightRatioLabel)
        ambientLightRatioLabel.snp.makeConstraints { make in
            make.centerY.equalTo(ambientLightRatioTitleLabel)
            make.right.equalTo(SCRXFrom(-20))
        }
        
        ambientLightRatioRestoreBtn = UIButton(normalImageName: "reset", target: self, action: #selector(ambientLightRatioRestoreBtnAction))
        contentView.addSubview(ambientLightRatioRestoreBtn)
        ambientLightRatioRestoreBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-64))
            make.centerY.equalTo(ambientLightRatioLabel)
        }
        
        ambientLightRatioSliderView = DeviceSliderFunctionView(frame: .zero, title: "", value: Int(ambientLightRatio / 10), functionType: .level(min: 0, max: 500, step: 1))
        ambientLightRatioSliderView.minLabel.isHidden = true
        ambientLightRatioSliderView.maxLabel.isHidden = true
        ambientLightRatioSliderView.minusBtn.setImage(UIImage(named: "scene_data_value_minus"), for: .normal)
        ambientLightRatioSliderView.addBtn.setImage(UIImage(named: "scene_data_value_add"), for: .normal)
        ambientLightRatioSliderView.lineView.isHidden = true
        ambientLightRatioSliderView.titleLabel.isHidden = true
        ambientLightRatioSliderView.valueChangedCallback = {[weak self] value in
            self?.ambientLightRatioLabel.text = (Double(value) / 10.0).toSimplifyStr(maxDigits: 1)
        }
        contentView.addSubview(ambientLightRatioSliderView)
        ambientLightRatioSliderView.snp.makeConstraints { make in
            make.left.right.height.equalTo(sensorRatioSliderView)
            make.top.equalTo(ambientLightRatioLabel.snp.bottom).offset(SCRYFrom(22))
            make.bottom.equalTo(SCRYFrom(-30))
        }
        ambientLightRatioSliderView.minusBtn.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        ambientLightRatioSliderView.addBtn.snp.remakeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalToSuperview()
        }
        ambientLightRatioSliderView.slider.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(48))
            make.right.equalTo(SCRXFrom(-47))
            make.top.bottom.equalToSuperview()
        }
        
    }
    
}
