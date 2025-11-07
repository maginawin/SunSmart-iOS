//
//  FlashlightSwingView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/20.
//

import UIKit

class FlashlightSwingView: UIView {
    
    private var flashlightImageView: UIImageView!
    private var lightImageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        
        startSwingAnimation()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        lightImageView = UIImageView(image: UIImage(named: "flashlight_droplight"))
        lightImageView.sizeToFit()
        addSubview(lightImageView)
        lightImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(8))
            make.width.equalTo(lightImageView.width)
            make.height.equalTo(lightImageView.height)
        }
        
        flashlightImageView = UIImageView(image: UIImage(named: "flashlight"))
        // 设置锚点为中心底部（假设灯光从底部照出）
        flashlightImageView.layer.anchorPoint = CGPoint(x: 0.5, y: 1)
        addSubview(flashlightImageView)
        flashlightImageView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(SCRYFrom(23))
        }
        
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        flashlightImageView.layer.position = CGPoint(x: bounds.midX, y: bounds.maxY)
    }
    
    private func startSwingAnimation() {
        // 清理旧动画
        flashlightImageView.layer.removeAllAnimations()
        
        // =====  摇晃动画 (左右3次) =====
        let swingAnimation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        swingAnimation.values = [
               15 * (Double.pi / 180),   // 起点：右倾 15°
               -15 * (Double.pi / 180),  // 左倾
                15 * (Double.pi / 180),  // 右倾
               -15 * (Double.pi / 180),  // 左倾
                15 * (Double.pi / 180),  // 右倾
               -15 * (Double.pi / 180),  // 左倾
                15 * (Double.pi / 180)   // 回到起点（右倾15°）
           ]
           
           // 边缘减速关键帧分布（时间占比）
           swingAnimation.keyTimes = [
               0.0, 0.16, 0.33, 0.5, 0.66, 0.82, 1.0
           ] as [NSNumber]
        
//        swingAnimation.values = [
//            0,
//            -15 * (Double.pi / 180),
//             15 * (Double.pi / 180),
//            0,
//            -15 * (Double.pi / 180),
//             15 * (Double.pi / 180),
//            0,
//            -15 * (Double.pi / 180),
//             15 * (Double.pi / 180),
//            0
//        ]
//        // 使用关键帧时间点来平滑过渡，让边缘减速（0 -> 1之间）
//        swingAnimation.keyTimes = [
//            0.0,
//            0.1, 0.25,
//            0.35,
//            0.45, 0.60,
//            0.70,
//            0.80, 0.95,
//            1.0
//        ] as [NSNumber]

        swingAnimation.duration = 5.0
        swingAnimation.repeatCount = 1
        swingAnimation.isRemovedOnCompletion = true
        swingAnimation.fillMode = .forwards
        swingAnimation.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .linear), count: swingAnimation.values!.count - 1)

        
        // =====  动画组（摇动 + 停2秒）=====
        let group = CAAnimationGroup()
        group.animations = [swingAnimation]
        group.duration = swingAnimation.beginTime + swingAnimation.duration + 2.0 // +2s停顿
        group.isRemovedOnCompletion = false
        group.fillMode = .forwards
        group.repeatCount = .infinity
        group.timingFunction = CAMediaTimingFunction(name: .linear)
        
        flashlightImageView.layer.add(group, forKey: "flashlightSwing")
    }

}

