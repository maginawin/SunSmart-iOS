//
//  CustomDeviceSlider.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit

protocol CustomDeviceSliderDelegate: AnyObject {
    
    /// 是否可以滑动
    /// - Parameters:
    ///   - slider: 滑条
    ///   - value: 数值
    /// - Returns: 是否可以滑动
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool
    
    /// 滑动条数值修改回调
    /// - Parameters:
    ///   - slider: 滑动条
    ///   - value: 数值
    func slider(_ slider: CustomDeviceSlider, valueChanged value: Float, ended: Bool)
    
    
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
    
    /// 是否可以滑动
    /// - Parameters:
    ///   - slider: 滑条
    ///   - value: 数值
    /// - Returns: 是否可以滑动
    func slider(_ slider: CustomDeviceSlider, canEditChanged value: Float) -> Bool {
        return true
    }
    
}

class CustomDeviceSlider: UISlider {

    var sendsFinalValueOnTouchCancel = false

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
    /// 限制滑动范围（可选）
    var limitRange: ClosedRange<Int>? {
        willSet {
            if let oldRange = limitRange, let newRange = newValue, oldRange == newRange {
                return
            }
            self.limitRange = newValue
        }
        didSet {
            updateLimitUI()
        }
    }
    
    /// 是否正在滑动中
    private(set) var isSliding: Bool = false
    
    weak var delegate: CustomDeviceSliderDelegate?
    /// 步进值
    var step: Int?
    
    /// 滑动条上报定时器
    private var valueChangedTimer: Timer?
    /// 上一次发送的值
    private var lastSendValue: Float?
    /// 只由本轮用户输入更新，避免把界面刷新后的 value 当成调光指令。
    private var interactionValue: Float?
    private var pendingValue: Float?
    
    private var trackRect: CGRect?
    
    
    lazy private var minLineView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(red: 100 / 255.0, green: 116 / 255.0, blue: 139 / 255.0, alpha: 1)
        view.layer.cornerRadius = 1
        return view
    }()
    
    lazy private var maxLineView: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = UIColor(red: 100 / 255.0, green: 116 / 255.0, blue: 139 / 255.0, alpha: 1)
        view.layer.cornerRadius = 1
        return view
    }()
    
    var lastBounds: CGRect?

    
    /// 重写value属性，设置步进后只返回对应步进倍数值
    override var value: Float {
        get {
            var value = super.value
            if let step = self.step {
                value = roundf(value / Float(step)) * Float(step)
                value = max(min(value, maximumValue), minimumValue)
            }
            // 判断是否限制value范围
            if let limitRange = self.limitRange {
                value = Float(max(limitRange.lowerBound, min(Int(value), limitRange.upperBound)))
            }
            return value
        }set {
            var value = newValue
            if let step = self.step {
                var value = roundf(newValue / Float(step)) * Float(step)
                value = max(min(value, maximumValue), minimumValue)
            }
            
            // 判断是否限制value范围
            if let limitRange = self.limitRange {
                value = Float(max(limitRange.lowerBound, min(Int(value), limitRange.upperBound)))
            }
            super.value = value
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addTarget(self, action: #selector(sliderValueChanged), for: .valueChanged)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        updateTrackGradient()
        updateLimitUI()
    }
    
    /// 更新限制滑动UI
    private func updateLimitUI() {
        // 清除旧范围；取消限制、布局未就绪或系统更换图标容器时也不能残留灰段。
        maxLineView.removeFromSuperview()
        minLineView.removeFromSuperview()

        guard let range = limitRange, let trackRect = self.trackRect,
              !trackRect.isEmpty, maximumValue > minimumValue else { return }

        if #available(iOS 27.0, *) {
            guard let image = currentThumbImage ?? thumbImage(for: state) ?? thumbImage(for: .normal) else { return }
            let imageViews = allSubviews.compactMap { $0 as? UIImageView }.filter { !$0.isHidden }
            // 图标可能直接挂在 Slider 上，也可能嵌套；不依赖 UIKit 的固定层级。
            let thumbImageView = imageViews.first { $0.image?.isEqual(image) == true } ?? imageViews.first { view in
                guard view.image?.size == image.size, let thumbRect = lastBounds else { return false }
                let frame = view.convert(view.bounds, to: self)
                return abs(frame.midX - thumbRect.midX) < 1 && abs(frame.midY - thumbRect.midY) < 1
            }
            guard let thumbImageView else { return }

            // 灰段与图标分支同级并位于其下方；避开只能容纳图标的狭窄容器。
            var thumbBranch: UIView = thumbImageView
            while let parent = thumbBranch.superview, parent !== self,
                  !parent.bounds.contains(convert(trackRect, to: parent)) {
                thumbBranch = parent
            }
            guard let container = thumbBranch.superview else { return }
            let rect = convert(trackRect, to: container)
            let valueRange = maximumValue - minimumValue
            let lowProgress = CGFloat(min(max((Float(range.lowerBound) - minimumValue) / valueRange, 0), 1))
            let highProgress = CGFloat(min(max((maximumValue - Float(range.upperBound)) / valueRange, 0), 1))
            let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft
            if lowProgress > 0 {
                let width = rect.width * lowProgress
                minLineView.frame = CGRect(x: isRTL ? rect.maxX - width : rect.minX,
                                           y: rect.minY, width: width, height: rect.height)
                container.insertSubview(minLineView, belowSubview: thumbBranch)
            }
            if highProgress > 0 {
                let width = rect.width * highProgress
                maxLineView.frame = CGRect(x: isRTL ? rect.minX : rect.maxX - width,
                                           y: rect.minY, width: width, height: rect.height)
                container.insertSubview(maxLineView, belowSubview: thumbBranch)
            }
            return
        }

        guard let trackView = subviews.first,
              let thumbImageView = trackView.subviews.first(where: { $0.isKind(of: UIImageView.classForCoder()) }) else { return }
        
        if Int(maximumValue) > range.upperBound {
            let overrunValue = Int(maximumValue) - range.upperBound
            let progress = CGFloat(overrunValue) / CGFloat(maximumValue - minimumValue)
            let width = trackView.frame.size.width * progress
            maxLineView.frame = CGRect(x: trackView.frame.size.width - width, y: trackRect.minY, width: width, height: trackRect.height)
            trackView.addSubview(maxLineView)
        }
        
        if Int(minimumValue) < range.lowerBound {
            let overrunValue = range.lowerBound - Int(minimumValue)
            let progress = CGFloat(overrunValue) / CGFloat(maximumValue - minimumValue)
            let width = trackView.frame.size.width * progress
            minLineView.frame = CGRect(x: trackView.frame.minX, y: trackRect.minY, width: width, height: trackRect.height)
            trackView.addSubview(minLineView)
//            trackView.insertSubview(minLineView, at: 2)
        }
        trackView.bringSubviewToFront(thumbImageView)
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
    
    /// 是否可以滑动编辑数值
    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard delegate?.slider(self, canEditChanged: value) ?? true else { return false }
        beginInteraction()
        return true
    }
    
    @objc private func sliderValueChanged() {
        // UIKit 可能在 touchesEnded 之后继续派发 valueChanged，不能重启已结束的会话。
        guard isSliding else { return }
        let userValue = value
        interactionValue = userValue
        pendingValue = userValue
        if throttle { // 是否需要限流
            startTimer()
        }
        delegate?.slider(self, valueChanged: userValue, ended: false)
    }

    private func beginInteraction() {
        cancelPendingInteraction()
        isSliding = true
        interactionValue = value
    }

    /// 新的控制命令或页面退出接管时，丢弃旧手势，不提交其最终值。
    func cancelPendingInteraction() {
        isSliding = false
        stopTimer()
        interactionValue = nil
        pendingValue = nil
        lastSendValue = nil
    }

    private func sliderEndValueChange() {
        guard isSliding, let finalValue = interactionValue else { return }
        cancelPendingInteraction()
        // 第一个回调可能刷新界面；第二个回调仍必须使用同一份用户输入。
        delegate?.slider(self, valueChanged: finalValue, ended: true)
        delegate?.slider(self, throttleValueChanged: finalValue, ended: true)
    }
    
    // MARK: - Timer
    /// 启动定时器
    private func startTimer() {
        
        if valueChangedTimer == nil {
            
            valueChangedTimer = Timer(timeInterval: interval, repeats: true) {[weak self] timer in
                guard let self, self.isSliding, self.valueChangedTimer === timer,
                      let userValue = self.pendingValue else { return }
                self.pendingValue = nil
                if self.lastSendValue != userValue {
                    self.lastSendValue = userValue
                    self.delegate?.slider(self, throttleValueChanged: userValue, ended: false)
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

        var resultValue = value
        // 判断是否限制滑动范围
        if let range = limitRange {
            resultValue = Float(max(range.lowerBound, min(Int(resultValue), range.upperBound)))
        }

        // iOS 27 可能在已设置自定义图标时仍返回 nil，需回退到已配置的状态图片。
        if #available(iOS 27.0, *),
           let image = currentThumbImage ?? thumbImage(for: state) ?? thumbImage(for: .normal) {
            // UIKit 传入的轨道可能带有拖动伸缩；使用 bounds 与自定义轨道保持一致。
            // 保留原有两端各 5pt 的中心内缩，使图片覆盖轨道端点。
            let valueRange = maximumValue - minimumValue
            var progress = valueRange > 0 ? CGFloat((resultValue - minimumValue) / valueRange) : 0
            progress = min(max(progress, 0), 1)
            if effectiveUserInterfaceLayoutDirection == .rightToLeft {
                progress = 1 - progress
            }
            let edgeInset = min(5, bounds.width * 0.5)
            let centerX = bounds.minX + edgeInset + (bounds.width - edgeInset * 2) * progress
            let returnRect = CGRect(
                x: centerX - image.size.width * 0.5,
                y: bounds.midY - image.size.height * 0.5,
                width: image.size.width,
                height: image.size.height
            )
            lastBounds = returnRect
            return returnRect
        }
        
        // 滑块图片宽度
        let thumbW = (self.currentThumbImage?.size.width ?? 0) - 10
        let thumbRect = CGRect(x: rect.origin.x - thumbW * 0.5, y: rect.origin.y, width: rect.size.width + thumbW, height: rect.size.height)
        
        let returnRect = super.thumbRect(forBounds: bounds, trackRect: thumbRect, value: resultValue)
        lastBounds = returnRect
        return returnRect
    }
    
    override func trackRect(forBounds bounds: CGRect) -> CGRect {
        var rect = super.trackRect(forBounds: bounds)
        rect.size.height = 2

        if #available(iOS 27.0, *),
           (currentThumbImage ?? thumbImage(for: state) ?? thumbImage(for: .normal)) != nil {
            rect = CGRect(x: bounds.minX, y: bounds.midY - 1, width: bounds.width, height: 2)
        }
        
        trackRect = rect
        return rect
    }

    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        sliderEndValueChange()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        finishCancelledInteraction()
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        finishCancelledInteraction()
    }

    private func finishCancelledInteraction() {
        if sendsFinalValueOnTouchCancel {
            sliderEndValueChange()
        } else {
            cancelPendingInteraction()
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil {
            cancelPendingInteraction()
        }
    }

    // VoiceOver 调节不经过触摸跟踪，也需要独立且完整的一次用户输入。
    override func accessibilityIncrement() {
        performAccessibilityAdjustment { super.accessibilityIncrement() }
    }

    override func accessibilityDecrement() {
        performAccessibilityAdjustment { super.accessibilityDecrement() }
    }

    private func performAccessibilityAdjustment(_ adjustment: () -> Void) {
        guard isEnabled, delegate?.slider(self, canEditChanged: value) ?? true else { return }
        beginInteraction()
        interactionValue = nil
        adjustment()
        // 原生 valueChanged 已记录输入时，不把其 delegate 的界面刷新再次当成输入。
        if isSliding, interactionValue == nil {
            sliderValueChanged()
        }
        sliderEndValueChange()
    }

    deinit {
        valueChangedTimer?.invalidate()
    }
    
    
    //检查是点击事件的点是否在slider范围内
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {

        let extendedBounds = bounds.insetBy(dx: -15, dy: -10)
        return extendedBounds.contains(point)
        
        //调用父类判断
//        var result = super.point(inside: point, with: event)
//        if !result {
//            
//            // 滑块图片宽度
//            let thumbW = (self.currentThumbImage?.size.width ?? 20) * 0.5
//            
//            //同理,如果不在slider范围类,扩充响应范围
//            if point.x >= ((lastBounds?.origin.x ?? self.frame.origin.x) - thumbW) && (point.x <= ((lastBounds?.origin.x ?? self.frame.origin.x) + (lastBounds?.size.width ?? self.frame.size.width) + thumbW)) && point.y > 0 {
//                //在扩充范围内,返回yes
//                result = true
//            }
//        }
//        return result
    }
    
}
