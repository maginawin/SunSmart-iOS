//
//  CALayer+Animations.swift
//  BLE-OTA
//
//  Created by 袁科鸿 on 2022/12/9.
//

import UIKit

extension CALayer {
    
    /// 添加转场渐变动画
    /// @param duration 动画时长 默认0.25s
    func addFadeAnimation(duration: TimeInterval = 0.25, animationKey: String? = nil) {
        let transition = CATransition()
        transition.type = .fade
        transition.duration = duration
        self.add(transition, forKey: animationKey)
    }
    
    /// 添加平移动画
    /// @param duration 动画时长 建议0.3s
    /// @param animationOrientation 动画方向
    func addMoveInAnimation(duration: TimeInterval = 0.3, animationOrientation: CATransitionSubtype = .fromRight, animationKey: String? = nil) {
        
        let transition = CATransition()
        transition.type = .moveIn
        transition.subtype = animationOrientation
        transition.duration = duration;
        self.add(transition, forKey: animationKey)
    }

    /// 添加旋转动画
    /// @param startLocation 起点  0~1
    /// @param endLocation 终点  0~1
    /// @param duration 动画时长
    /// @param repeatCount 重复次数
    /// @param animationKey 动画key
    func addRotationAnimation(startLocation: CGFloat = 0, endLocation: CGFloat = 1, duration: TimeInterval, repeatCount: Int = 1, animationKey: String? = nil) {
        
        let animation = CABasicAnimation()
        //旋转必须在前面加上transform
        animation.keyPath = "transform.rotation.z"
        animation.fromValue = .pi * startLocation * 2
        animation.toValue = .pi * endLocation * 2
        animation.duration = duration
        animation.isRemovedOnCompletion = false
        animation.fillMode = .forwards
        animation.repeatCount = Float(repeatCount)
        self.add(animation, forKey: animationKey)
    }
    
    /// 添加缩放动画
    /// - parameter fromScale 起始比例 0~1
    /// - parameter toScale 结束比例 0~1
    /// - parameter duration 动画时长 默认0.3
    /// - parameter animationKey 动画key
    func addScaleAnimation(fromScale: CGFloat, toScale: CGFloat, duration: TimeInterval, animationKey: String? = nil) {
        let scaleAnimation = CABasicAnimation(keyPath: "transform.scale.xy")
        scaleAnimation.fromValue = fromScale
        scaleAnimation.toValue = toScale
        scaleAnimation.duration = duration
        scaleAnimation.autoreverses = false
        self.add(scaleAnimation, forKey: animationKey)
    }
    
    /// 添加透明度动画
    /// - parameter fromOpacity 起始透明度 0~1
    /// - parameter toScale 结束透明度 0~1
    /// - parameter repeatCount 重复时间
    /// - parameter duration 动画时长 默认0.3
    /// - parameter animationKey 动画key
    func addOpacityAnimation(fromOpacity: CGFloat, toOpacity: CGFloat, duration: TimeInterval, repeatCount: Int = 1, animationKey: String? = nil) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = fromOpacity
        animation.toValue = toOpacity
        animation.duration = duration
        animation.isRemovedOnCompletion = false
        animation.autoreverses = true
        animation.fillMode = .forwards
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.repeatCount = Float(repeatCount)
        self.add(animation, forKey: animationKey)
    }
    
}
