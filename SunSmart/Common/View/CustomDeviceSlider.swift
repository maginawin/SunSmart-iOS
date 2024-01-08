//
//  CustomDeviceSlider.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit

protocol CustomDeviceSliderDelegate: AnyObject {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float)
    
    
    /// 滑动条数值修改回调（限流）
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    ///   - ended: 是否滑动结束
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool)
    
}

extension CustomDeviceSliderDelegate {
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float) {
        
    }
    
    
    /// 滑动条数值修改回调（限流）
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    ///   - ended: 是否滑动结束
    func slider(_ slider: CustomDeviceSlider, throttleValueChanged value: Float, ended: Bool) {
        
    }
    
}

class CustomDeviceSlider: UISlider {

    /// 是否需要限流（ture：滑动数据限流300ms返回一次最新的数据    false：滑动则返回当前数据）
    var throttle: Bool = false
    /// 数据回调间隔（打开限流时）
    var interval: TimeInterval = 0.3
    /// 渐变色
    var gradientColors: [UIColor] = [] {
        didSet {
            
            maximumTrackTintColor = .clear
            minimumTrackTintColor = .clear
            
            guard !self.frame.isEmpty else { return }
            updateTrackGradient()
        }
    }
    
    /// 是否正在滑动中
    var isSliding: Bool = false
    
    weak var delegate: CustomDeviceSliderDelegate?
    
    /// 滑动条上报定时器
    private var valueChangedTimer: Timer?
    /// 上一次发送的值
    private var lastSendValue: Float?
    
    private var trackRect: CGRect?
    
    var lastBounds: CGRect?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addTarget(self, action: #selector(sliderTouchDown), for: .touchDown)
        addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
        addTarget(self, action: #selector(sliderEndValueChange), for: .touchUpInside)
        addTarget(self, action: #selector(sliderEndValueChange), for: .touchDragExit)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateTrackGradient()
    }
    
    deinit {
        print("dealloc")
    }
    
    private func updateTrackGradient() {
        
        if gradientColors.count > 0 {
            if let gradientLayer = layer.sublayers?.first(where: { $0.isKind(of: CAGradientLayer.classForCoder() ) }) {
                gradientLayer.removeFromSuperlayer()
            }
            
            let gradient = CAGradientLayer()
            //            gl.frame = CGRectMake(66,731,242,2);
            
            gradient.frame = trackRect ?? CGRect(x: 0, y: center.y, width: bounds.width, height: 2)
            gradient.startPoint = CGPointMake(0, 0)
            gradient.endPoint = CGPointMake(1, 0)
            //            var colors: [CGColor] = []
            //            gradientColors.forEach({ $0.cgColor })
            gradient.colors = gradientColors.map({ $0.cgColor })
            gradient.cornerRadius = 2
            gradient.masksToBounds = true
//            gradientColors.count > 2 {
//                gradient.locations = [0, 0.5, 1]
//            }
            layer.insertSublayer(gradient, at: 0)
//            layer.addSublayer(gradient)
        }
    }
    
    @objc private func sliderValueChanged() {
        isSliding = true
        if throttle { // 是否需要限流
            startTimer()
        }
        self.delegate?.slider(self, valueChanged: self.value)
    }
    
    @objc private func sliderTouchDown() {
        isSliding = true
    }
    
    @objc private func sliderEndValueChange() {
        isSliding = false
        if throttle { // 是否需要限流
            stopTimer()
            self.delegate?.slider(self, throttleValueChanged: self.value, ended: true)
        }else {
            self.delegate?.slider(self, valueChanged: self.value)
        }
    }
    
    // MARK: - Timer
    /// 启动定时器
    private func startTimer() {
        
        if valueChangedTimer == nil {
            
            valueChangedTimer = Timer(timeInterval: interval, repeats: true) {[weak self] _ in
                guard let self = self else { return  }
                if self.lastSendValue != self.value {
                    self.lastSendValue = self.value
                    self.delegate?.slider(self, throttleValueChanged: self.value, ended: false)
                }
            }
            RunLoop.current.add(valueChangedTimer!, forMode: .common)
        }
    }
    /// 停止定时器
    private func stopTimer() {
        valueChangedTimer?.invalidate()
        valueChangedTimer = nil
    }
    
    
    override func thumbRect(forBounds bounds: CGRect, trackRect rect: CGRect, value: Float) -> CGRect {

        // 滑块图片宽度
        let thumbW = (self.currentThumbImage?.size.width ?? 0) - 10
        let thumbRect = CGRect(x: rect.origin.x - thumbW * 0.5, y: rect.origin.y, width: rect.size.width + thumbW, height: rect.size.height)
        
        let returnRect = super.thumbRect(forBounds: bounds, trackRect: thumbRect, value: value)
        lastBounds = returnRect
        return returnRect
    }
    
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.trackRect(forBounds: bounds)
        rect.size.height = 2
        
        trackRect = rect
        return rect
    }
    
//    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
//
//        //调用父类方法,找到能够处理event的view
//        var result = super.hitTest(point, with: event)
//        if result != self {
//            /*如果这个view不是self,我们给slider扩充一下响应范围,
//             这里的扩充范围数据就可以自己设置了
//             */
//
//            // 滑块图片宽度
//            let thumbW = self.currentThumbImage?.size.width ?? 0
//
//            if ((point.y >= -thumbW * 0.5) &&
//                point.y < (lastBounds?.size.height ?? self.height) &&
//                (point.x >= 0 && point.x < CGRectGetWidth(self.bounds))) {
//                //如果在扩充的范围类,就将event的处理权交给self
//                result = self
//            }
//        }
//        //否则,返回能够处理的view
//        return result;
//
//    }
    
    //检查是点击事件的点是否在slider范围内
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {

        //调用父类判断
        var result = super.point(inside: point, with: event)
        if !result {
            
            // 滑块图片宽度
            let thumbW = self.currentThumbImage?.size.width ?? 0
            
            //同理,如果不在slider范围类,扩充响应范围
            if point.x >= ((lastBounds?.origin.x ?? self.frame.origin.x) - thumbW) && (point.x <= ((lastBounds?.origin.x ?? self.frame.origin.x) + (lastBounds?.size.width ?? self.frame.size.width) + thumbW)) && point.y > 0 {
                //在扩充范围内,返回yes
                result = true
            }
        }
//        else if !(lastBounds?.contains(point) ?? true) {
//            result = false
//        }
        return result
    }
    
}
