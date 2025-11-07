//
//  GradientLoadingBar.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/17.
//

import UIKit

class GradientLoadingBar: UIView {
    
    private let backgroundLayer = CALayer()
    private let gradientLayer = CAGradientLayer()
    private var animation: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayers()
        startAnimating()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayers()
        startAnimating()
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = bounds.height / 2
        backgroundLayer.frame = bounds
        backgroundLayer.cornerRadius = bounds.height / 2
        
        gradientLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        gradientLayer.cornerRadius = bounds.height / 2
        
        if animation {
            startAnimating()
        }
    }
    
    private func setupLayers() {
        layer.masksToBounds = true
        
        // 灰色背景
        backgroundLayer.backgroundColor = UIColor(white: 0.9, alpha: 1).cgColor
//        backgroundLayer.frame = bounds
        layer.addSublayer(backgroundLayer)
        
        // 渐变层（蓝 → 紫）
        gradientLayer.colors = [
            UIColor.systemBlue.withAlphaComponent(0.7).cgColor,
            UIColor.systemPurple.withAlphaComponent(0.7).cgColor,
            UIColor.systemBlue.withAlphaComponent(0.7).cgColor
        ]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
//        gradientLayer.frame = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        layer.addSublayer(gradientLayer)
    }
    
    /// 开始跑马灯动画
    func startAnimating() {
        
        animation = true
        guard bounds != .zero else {
            return
        }
        
        let totalWidth = bounds.width
        let startX = -totalWidth * 0.5
        let endX = totalWidth * 1.5
        
        let animation = CAKeyframeAnimation(keyPath: "position.x")
//        animation.fromValue = -bounds.width * 0.5
//        animation.toValue = bounds.width * 1.5
        animation.values = [
            startX,
            startX + totalWidth,
            endX
        ]
        animation.duration = 2.0
        // 这里定义相对时间（0~1）
        animation.keyTimes = [0.0, 0.4, 1.0]
        // 定义速度变化曲线（边缘慢，中间快）
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .linear),
            CAMediaTimingFunction(name: .easeInEaseOut),
        ]
        animation.repeatCount = .infinity
//        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        animation.isRemovedOnCompletion = false
        gradientLayer.add(animation, forKey: "marquee")
    }
    
    /// 停止动画
    func stopAnimating() {
        gradientLayer.removeAnimation(forKey: "marquee")
        animation = false
    }
}

