//
//  BuoySliderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/12.
//

import UIKit

class BuoySliderView: UIView {

    private var buoyImageView: UIImageView!
    private var valueLabel: UILabel!
    var slider: CustomDeviceSlider!
    
    private let unit: String
    
    /// 进度条更新回调  value： level 0~100 cct：2700~6500
    var valueChangedCallback: ((_ value: Int)->())?
    
    /// 进度条更新回调（限流发送间隔）  value： level 0~100 cct：2700~6500      ended：是否停止修改
    var valueThrottleChangedCallback: ((_ value: Int, _ ended: Bool)->())?
    
    var value: Int {
        get {
            return Int(slider.value)
        }set {
            slider.value = Float(newValue)
            valueLabel.text = "\(Int(slider.value))\(unit)"
        }
    }
    
    let type: DeviceSliderFunctionView.FunctionType
    
    init(frame: CGRect, functionType: DeviceSliderFunctionView.FunctionType) {
        self.type = functionType
        self.unit = functionType.data.unit
        super.init(frame: frame)
        setupUI()
        
        let data = functionType.data
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
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updateCctRange(_ range: ClosedRange<UInt16>) {
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        value = min(Int(range.upperBound), max(Int(range.lowerBound), value))
    }
    
    private func setupUI() {
        
        slider = CustomDeviceSlider()
        slider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
        slider.layer.cornerRadius = 2
        slider.throttle = true
        slider.delegate = self
        slider.addTarget(self, action: #selector(sliderTouchDownAction), for: .touchDown)
        slider.addTarget(self, action: #selector(sliderTouchExitAction), for: .touchUpInside)
        slider.addTarget(self, action: #selector(sliderTouchExitAction), for: .touchCancel)
        slider.addTarget(self, action: #selector(sliderTouchExitAction), for: .touchUpOutside)
         
        addSubview(slider)
        slider.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(67))
//            make.right.equalTo(SCRXFrom(-68))
            
//            make.top.equalTo(addBtn.snp.bottom).offset(SCRYFrom(8))
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        let image = UIImage(named: "value_buoy")?.resizableImage(withCapInsets: UIEdgeInsets(top: 8, left: 11, bottom: 13, right: 11))
        buoyImageView = UIImageView(image: image)
        buoyImageView.alpha = 0
        addSubview(buoyImageView)
        buoyImageView.snp.makeConstraints { make in
            make.centerX.equalTo(slider.snp.left).offset(0)
            make.bottom.equalTo(slider.snp.top)
        }
        
        valueLabel = UILabel(text: "40%", textColor: .white, fontSize: 13)
        valueLabel.font = FONTS(13)
        valueLabel.textAlignment = .center
        buoyImageView.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.left.equalTo(6)
            make.right.equalTo(-6)
//            make.centerX.equalToSuperview()
            make.top.equalTo(8)
//            make.centerX.equalToSuperview()
//            make.height.equalTo(15)
        }
        
    }
    
    
    @objc private func sliderTouchDownAction() {
        UIView.animate(withDuration: 0.3) {
//            self.buoyImageView.isHidden = false
            self.buoyImageView.alpha = 1
        }
        valueLabel.text = "\(Int(slider.value))%"
    }
    
    @objc private func sliderTouchExitAction() {
        
        UIView.animate(withDuration: 0.3) {
            self.buoyImageView.alpha = 0
        }
    }
    
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        if let slider = slider, !self.isHidden, self.isUserInteractionEnabled {
            let pointInSlider = slider.convert(point, from: self)
            let extendedBounds = slider.bounds.insetBy(dx: -15, dy: -10)
            if extendedBounds.contains(pointInSlider) {
                return slider
            }
        }
        return super.hitTest(point, with: event)
    }
    
}

extension BuoySliderView: CustomDeviceSliderDelegate {
    
    
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool) {
        
        valueLabel.text = "\(Int(value))\(unit)"
        let progress = (value - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)
        var x = slider.width * CGFloat(progress)
        
        if let thumbRect = slider.lastBounds {
            x = thumbRect.origin.x + thumbRect.size.width * 0.5 - 1
//            buoyImageView.center.x = x
        }
        //        else {
        //            let progress = (value - slider.minimumValue) / (slider.maximumValue - slider.minimumValue)
        //            let x = slider.width * CGFloat(progress)
        //            buoyImageView.center.x = x
        //        }
//        buoyImageView.center.x = x
        buoyImageView.snp.updateConstraints { make in
            make.centerX.equalTo(slider.snp.left).offset(x)
        }
        valueChangedCallback?(Int(value))
    }
    
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        valueThrottleChangedCallback?(Int(value), ended)
    }
    
}
