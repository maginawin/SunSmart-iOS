//
//  DaliMasterSingleControlView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/17.
//

import UIKit

protocol DaliMasterSingleControlViewDelegate: AnyObject {
    
    /// 开关事件
    func view(_ view: DaliMasterSingleControlView, onoffAction isOn: Bool)
    /// 亮度修改事件 value: 亮度百分比 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterSingleControlView, lightnessValueChanged value: Int, throttle: Bool, ended: Bool)
    /// 色温修改事件 cct: 色温 throttle: 是否事件分流（true：发送控制）ended: 是否停止
    func view(_ view: DaliMasterSingleControlView, cctValueChanged cct: Int, throttle: Bool, ended: Bool)
    
}

class DaliMasterSingleControlView: UIView {
    
    /// 灯类型
    enum LightType {
        /// 开关灯
        case onOff
        /// 调光灯
        case lightness
        /// 色温灯
        case cct(range: ClosedRange<UInt16>)
    }
    
    var lightGrayBgView: UIImageView!
    var lightBgView: UIImageView!
    var lightImageBtn: UIButton!
    var brightnessView: LightFunctionItem!
    var cctView: LightFunctionItem!
    
    var onoffBtn: UIButton!
    var lightnessSlider: BuoySliderView!
    var cctSlider: BuoySliderView!
    
    weak var delegate: DaliMasterSingleControlViewDelegate?
    
    let lightType: LightType
    
    init(frame: CGRect, lightType: LightType) {
        self.lightType = lightType
        
        super.init(frame: frame)
        
        backgroundColor = Background_Color
        
        setupUI()
        updateUI()
        
        bindSliderAction()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Action
    
    @objc private func onoffAction(sender: UIButton) {
//        node.isOn = !node.isOn
//        if node.isOn {
//            node.lightness = node.trunOffLightness ?? node.lightnessRange.upperBound
//        }else {
//            node.trunOffLightness = node.lightness
//            node.lightness = 0
//        }
//        MeshAPI.setNodeOnOffState(address: node.primaryUnicastAddress, isOn: node.isOn)
//        updateData()
//        updateSliderValue()
        
        delegate?.view(self, onoffAction: !sender.isSelected)
        
    }
    
    private func bindSliderAction() {
        
        lightnessSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            
            
            self.delegate?.view(self, lightnessValueChanged: value, throttle: false, ended: false)
//            let lightness = Node.getLightness(lightness100: value)
//
//            if value == 0 {
//                self.node.trunOffLightness = self.node.lightness
//            }
//
//            self.node.lightness = lightness
//            self.node.isOn = lightness > 0
//            self.updateData()
        }
        lightnessSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
//            let lightness = Node.getLightness(lightness100: value, range: self.node.lightnessRange)
//            MeshAPI.setNodeLightnessState(address: self.node.primaryUnicastAddress, lightness: lightness, ack: ended)
            self.delegate?.view(self, lightnessValueChanged: value, throttle: true, ended: ended)
        }
        
        cctSlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
//            self.node.temperature = UInt16(value)
//            self.updateData()
            self.delegate?.view(self, cctValueChanged: value, throttle: false, ended: false)
        }
        cctSlider.valueThrottleChangedCallback = {[weak self] (value, ended) in
            guard let self = self else { return }
//            MeshAPI.setNodeColorTemperatureState(address: self.node.primaryUnicastAddress, temperature: UInt16(value), ack: ended)
            self.delegate?.view(self, cctValueChanged: value, throttle: true, ended: ended)
        }
    }
    
    
    
    private func setupUI() {
        
        lightGrayBgView = UIImageView(image: UIImage(named: "device_light_gray_bg"))
        lightGrayBgView.alpha = 0
        addSubview(lightGrayBgView)
        lightGrayBgView.snp.makeConstraints { make in
            
            make.centerX.equalToSuperview()
//            make.width.equalTo(lightBgView.snp.height)
            if isIPad {
                make.top.equalTo(SCRYFit(142))
                make.width.height.equalTo(SCRYFit(238))
            }else {
                make.top.equalTo(SCRYFit(52))
                make.width.height.equalTo(SCRYFit(200))
            }
            
        }
        
        lightBgView = UIImageView(image: UIImage(named: "device_light_bg"))
        addSubview(lightBgView)
        lightBgView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.width.height.equalTo(lightGrayBgView)
        }
        
        lightImageBtn = UIButton(normalImageName: "device_light_control_off", selectedImageName: "device_light_control_on", target: self, action: #selector(onoffAction))
        addSubview(lightImageBtn)
        lightImageBtn.snp.makeConstraints { make in
            make.center.equalTo(lightBgView)
            if isIPad {
                make.width.height.equalTo(67)
            }
        }
        
        brightnessView = LightFunctionItem(imageName: "device_brightness", valueStr: "100%")
        addSubview(brightnessView)
        brightnessView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(isIPad ? 68 : 28))
//            make.height.greaterThanOrEqualTo(SCRYFrom(20))
        }
        
        cctView = LightFunctionItem(imageName: "device_cct", valueStr: "4500K")
        addSubview(cctView)
        cctView.snp.makeConstraints { make in
            make.left.equalTo(self.snp.centerX).offset(SCRXFrom(22))
            make.centerY.height.equalTo(brightnessView)
        }
        
//        let cctRange = self.node.lightCTLTemperatureRange ?? self.node.defalutLightCTLTemperatureRange
        var cctType: DeviceSliderFunctionView.FunctionType = .cct()
        var showCct = false
        if case .cct(let range) = lightType {
            cctType = .cct(min: Int(range.lowerBound), max: Int(range.upperBound))
            showCct = true
        }
        cctSlider = BuoySliderView(frame: .zero, functionType: cctType)
        cctSlider.slider.interval = 0.3
        cctSlider.slider.step = 10
        cctSlider.isHidden = !showCct
        addSubview(cctSlider)
        cctSlider.snp.makeConstraints { make in
            if isIPad {
                make.left.equalTo(SCRXFrom(107))
                make.right.equalTo(SCRXFrom(-107))
                make.bottom.equalTo(SCRYFit(-102) - kSafeAreaBottomHeight)
            }else {
                make.left.equalTo(SCRXFrom(30))
                make.right.equalTo(SCRXFrom(-29))
                make.bottom.equalTo(SCRYFit(-52) - kSafeAreaBottomHeight)
            }
            make.height.equalTo(76)
        }
        
        lightnessSlider = BuoySliderView(frame: .zero, functionType: .level())
        lightnessSlider.slider.interval = 0.3
//        lightnessSlider.isHidden = !group.supportLightness
        addSubview(lightnessSlider)
        lightnessSlider.snp.makeConstraints { make in
            make.left.right.height.equalTo(cctSlider)
            make.bottom.equalTo(cctSlider.snp.top).offset(SCRYFit(2))
        }
        
        var offImageName = "device_control_off"
        var onImageName = "device_control_on"
        var disableImageName = "group_control_disable"
        if isIPad {
            offImageName = "device_control_off_big"
            onImageName = "device_control_on_big"
            disableImageName = "group_control_disable_big"
        }
        
        onoffBtn = UIButton(normalImageName: offImageName, selectedImageName: onImageName, target: self, action: #selector(onoffAction))
        onoffBtn.setImage(UIImage(named: disableImageName), for: .disabled)
        addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            if isIPad {
                make.width.height.equalTo(56)
                make.bottom.equalTo(lightnessSlider.snp.top).offset(SCRYFit(-28))
            }else {
                make.bottom.equalTo(lightnessSlider.snp.top).offset(SCRYFit(-8))
            }
        }
        
    }
    
    private func updateUI() {
        
        switch lightType {
        case .onOff:
            lightnessSlider.isHidden = true
            brightnessView.isHidden = true
            cctSlider.isHidden = true
            cctView.isHidden = true
        case .lightness:
            
            lightnessSlider.isHidden = false
            brightnessView.isHidden = false
            
            cctSlider.isHidden = true
            cctView.isHidden = true
            
        case .cct:
            
            lightnessSlider.isHidden = false
            brightnessView.isHidden = false

            cctSlider.isHidden = false
            cctView.isHidden = false
            
            brightnessView.snp.remakeConstraints { make in
                make.right.equalTo(self.snp.centerX).offset(SCRXFrom(-42))
                make.top.equalTo(lightBgView.snp.bottom).offset(SCRYFit(28))
                make.height.equalTo(SCRYFrom(20))
            }
        }
    }
    
}

class LightFunctionItem: UIView {
    var itemImageView: UIImageView!
    var itemLineView: UIView!
    var itemValueLabel: UILabel!
    
    init(imageName: String, valueStr: String) {
        super.init(frame: .zero)
        
        setupUI()
        itemImageView.image = UIImage(named: imageName)
        itemValueLabel.text = valueStr
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        itemImageView = UIImageView()
        addSubview(itemImageView)
        itemImageView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
        }
        
        itemLineView = UIView()
        itemLineView.backgroundColor = RGB(148, 163, 184)
        addSubview(itemLineView)
        itemLineView.snp.makeConstraints { make in
            make.left.equalTo(itemImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalToSuperview()
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(12))
        }
        itemValueLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        addSubview(itemValueLabel)
//        brightnessLabel.sizeToFit()
        itemValueLabel.snp.makeConstraints { make in
            make.left.equalTo(itemLineView.snp.right).offset(SCRXFrom(6))
            make.centerY.right.equalToSuperview()
            make.right.equalToSuperview()
//            make.width.equalTo(brightnessLabel.width)
        }
    }
    
}
