//
//  RoundProgressView.swift
//  HomeeMesh
//
//  Created by 袁科鸿 on 2023/1/5.
//

import UIKit

class RoundProgressView: UIView {

    /// 进度颜色
    var progressColor: UIColor!
    /// 圆弧颜色
    var roundColor: UIColor!
    /// 圆弧宽度
    var lineWidth: CGFloat = 2
    
    /// 进度  0.0~1.0
    var progress: Float = 0 {
        didSet {
            
//            CATransaction.begin()
//            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
//            CATransaction.setAnimationDuration(0.5)
//            self.progressLayer.strokeEnd = CGFloat(progress)
//            CATransaction.commit()
            setProgress(progress, animated: false)
        }
    }
    /// 圆弧图层
    private var roundLayer: CAShapeLayer!
    /// 进度图层
    private var progressLayer: CAShapeLayer!

    init(frame: CGRect, progressColor: UIColor, roundColor: UIColor, lineWidth: CGFloat) {
        super.init(frame: frame)
        self.progressColor = progressColor
        self.roundColor = roundColor
        self.lineWidth = lineWidth
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        guard self.bounds != .zero else {
            return
        }
        
        if roundLayer.path == nil {
            let bezierPath = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.bounds.size.height * 0.5)
            roundLayer.path = bezierPath.cgPath
            progressLayer.path = bezierPath.cgPath
        }
    }
    
    private func setProgress(_ value: Float, animated: Bool) {
        let clamped = max(0, min(1, value)) // 限制范围 0~1
        
        if animated {
            let current = progressLayer.presentation()?.strokeEnd ?? progressLayer.strokeEnd
            
            let animation = CABasicAnimation(keyPath: "strokeEnd")
            animation.fromValue = current  // 从当前显示值开始
            animation.toValue = clamped
            animation.duration = 0.25      // 缩短一点，避免积压
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            
            progressLayer.strokeEnd = CGFloat(clamped) // 最终值
            progressLayer.removeAnimation(forKey: "progress") // 防止旧动画干扰
            progressLayer.add(animation, forKey: "progress")
        } else {
            progressLayer.strokeEnd = CGFloat(clamped)
        }
    }
    
    private func setupUI() {
        
        roundLayer = CAShapeLayer()
        roundLayer.strokeColor = roundColor.cgColor
        roundLayer.lineWidth = 1
        roundLayer.fillColor = UIColor.clear.cgColor
        self.layer.addSublayer(roundLayer)
        
        
        progressLayer = CAShapeLayer()
        progressLayer.strokeColor = progressColor.cgColor
        progressLayer.lineWidth = lineWidth
        progressLayer.fillColor = UIColor.clear.cgColor
        progressLayer.strokeStart = 0
        progressLayer.strokeEnd = 0
        self.layer.addSublayer(progressLayer)
        
    }
 
}
