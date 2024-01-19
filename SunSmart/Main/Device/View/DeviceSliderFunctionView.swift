//
//  DeviceSliderFunctionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit

class DeviceSliderFunctionView: UIView {

    /// 标题
    var titleLabel: UILabel!
    /// 数值
//    var valueLabel: UIButton!
    /// 增加
    var addBtn: UIButton!
    /// 减少
    var minusBtn: UIButton!
    /// 最小值
    var minLabel: UILabel!
    /// 最大值
    var maxLabel: UILabel!
    /// 滑条
    var slider: CustomDeviceSlider!
    /// 线条
    var lineView: UIView!
    
    var title: String! {
        didSet {
            guard titleLabel != nil else {
                return
            }
            updateValue()
        }
    }
    var type: FunctionType = .level() {
        didSet {
            updateUI()
        }
    }
    
    /// 进度条更新回调  value： level 0~100 cct：2700~6500
    var valueChangedCallback: ((_ value: Int)->())?
    /// 进度条更新回调（限流发送间隔）  value： level 0~100 cct：2700~6500      ended：是否停止修改
    var throttleValueChangedCallback: ((_ value: Int, _ ended: Bool)->())?
    
    /// 设置value是否展示动画
    var setValueAnimated: Bool = true
    
    var value: Int {
        get {
            return Int(slider.value)
        }
        set {
            if value == newValue, slider.isSliding {
                return
            }
//            slider.value = Float(newValue)
            slider.setValue(Float(newValue), animated: setValueAnimated)
            updateValue()
        }
    }
    
    init(frame: CGRect, title: String, value: Int, functionType: FunctionType) {
        
        super.init(frame: frame)
        
        setupUI()
        self.type = functionType
        self.title = title
        updateUI()
        if !slider.isSliding {
            slider.value = Float(value)
        }
        updateValue()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func addBtnClick() {
        
        slider.value = min(slider.value + Float(type.data.step), slider.maximumValue)
        updateValue()
        
        valueChangedCallback?(Int(value))
        throttleValueChangedCallback?(Int(value), true)
    }
    
    @objc private func minusBtnClick() {
        
        slider.value = max(slider.value - Float(type.data.step), slider.minimumValue)
        updateValue()
        
        valueChangedCallback?(Int(value))
        throttleValueChangedCallback?(Int(value), true)
    }
    
    private func updateValue() {
        
        let data = type.data
        if title.isEmpty {
            titleLabel.text = "\(Int(slider.value))\(data.unit)"
        }else {
            titleLabel.text = "\(title!) | \(Int(slider.value))\(data.unit)"
        }
    }
    
    private func updateUI() {
        
        let data = type.data
        titleLabel.text = "\(title ?? "") | \(value)\(data.unit)"
        minLabel.text = "\(data.min)\(data.unit)"
        maxLabel.text = "\(data.max)\(data.unit)"
        slider.minimumValue = Float(data.min)
        slider.maximumValue = Float(data.max)
        switch type {
        case .level:
            slider.minimumTrackTintColor = data.sliderColors.first
            slider.maximumTrackTintColor = data.sliderColors.last
        default:
            slider.gradientColors = data.sliderColors
        }
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRXFrom(24))
            make.left.equalTo(SCRXFrom(16))
        }
        
        
        addBtn = UIButton(normalImageName: "light_value_add", target: self, action: #selector(addBtnClick))
//        addBtn.setImage(<#T##image: UIImage?##UIImage?#>, for: .highlighted)
        addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(26))
        }
        
        minusBtn = UIButton(normalImageName: "light_value_minus", target: self, action: #selector(minusBtnClick))
        addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(addBtn)
        }
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.layer.cornerRadius = 2
        slider.throttle = true
        slider.delegate = self
        addSubview(slider)
        slider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(67))
            make.right.equalTo(SCRXFrom(-68))
            make.top.equalTo(addBtn.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        minLabel = UILabel(text: "", textColor: RGB(134, 138, 160), fontSize: 14)
        minLabel.textAlignment = .left
//        minLabel.adjustsFontSizeToFitWidth = true
        addSubview(minLabel)
        minLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.centerY.equalTo(slider)
            make.right.equalTo(slider.snp.left).offset(SCRXFrom(-3))
        }
        
        maxLabel = UILabel(text: "", textColor: RGB(134, 138, 160), fontSize: 14)
        maxLabel.textAlignment = .right
        maxLabel.adjustsFontSizeToFitWidth = true
        addSubview(maxLabel)
        maxLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(minLabel)
            make.left.equalTo(slider.snp.right).offset(SCRXFrom(3))
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(236, 236, 236)
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalToSuperview()
            make.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        self.bringSubviewToFront(slider)
        
    }
    
    
}

extension DeviceSliderFunctionView: CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float) {
        updateValue()
        valueChangedCallback?(Int(value))
    }
    
    
    /// 滑动条数值修改回调（限流）
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    ///   - ended: 是否滑动结束
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        throttleValueChangedCallback?(Int(value), ended)
    }
    
}

extension DeviceSliderFunctionView {
 
  
    /// 功能类型
    enum FunctionType {
        /// 最小值，最大值，步长（加/减），单位，滑动条颜色
        var data: (min: Int,max: Int, step: Int, unit: String, sliderColors: [UIColor]) {
            switch self {
            case .level(let min, let max, let step, let unit, let sliderColors):
                return (min, max, step, unit, sliderColors)
            case .cct(let min, let max, let step, let unit, let sliderColors):
                return (min, max, step, unit, sliderColors)
            }
        }
        /// 亮度
        case level(min: Int = 0, max: Int = 100, step: Int = 1, unit: String = "%", sliderColors: [UIColor] = [RGB(255, 167, 44), RGB(229, 229, 229)])
        /// 色温
        case cct(min: Int = 2700, max: Int = 6500, step: Int = 10, unit: String = "K", sliderColors: [UIColor] = [RGB(255, 108, 0), .white, RGB(114, 179, 255)])
    }
    
}

