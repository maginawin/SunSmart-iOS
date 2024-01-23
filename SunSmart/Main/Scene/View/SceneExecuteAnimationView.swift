//
//  SceneExecuteAnimationView.swift
//  TestDemo
//
//  Created by 袁科鸿 on 2024/1/22.
//

import UIKit

class SceneExecuteAnimationView: UIView {

    private lazy var rippleLayer: CAShapeLayer = {
        
        //最初半径
        let radius = self.frame.size.width * 0.5
        //开始角
        var startAngle: CGFloat = 0
        //结束角
        var endAngle = 2 * Double.pi
        //中心点
        let center = CGPointMake(self.frame.size.width*0.5, self.frame.size.height*0.5);
        //画圆
        let bezierPath = UIBezierPath(arcCenter: center, radius: radius, startAngle: startAngle, endAngle: endAngle, clockwise: true)
        //生成layer对象
        let shapeLayer = CAShapeLayer()
        shapeLayer.path = bezierPath.cgPath//设置path
        shapeLayer.strokeColor = UIColor(red: 130 / 255.0, green: 130 / 255.0, blue: 130 / 255.0, alpha: 1).cgColor//圆边框颜色
        shapeLayer.fillColor = UIColor(red: 130 / 255.0, green: 130 / 255.0, blue: 130 / 255.0, alpha: 1).cgColor//圆填充颜色
        return shapeLayer
    }()
    
    private lazy var successfulLayer: CAShapeLayer = {
        
        //1、设置路线
        let path = UIBezierPath()
        path.lineWidth = 2
        
        path.move(to: CGPoint(x: self.center.x - 10, y: self.center.y))
        path.addLine(to: CGPoint(x: self.center.x, y: self.center.y + 10))
        path.addLine(to: CGPoint(x: self.center.x + 15, y: self.center.y - 7))
        //2、创建CAShapeLayer
        let shape = CAShapeLayer()
        shape.path = path.cgPath;
        shape.lineWidth = path.lineWidth
        shape.fillColor = UIColor.clear.cgColor
        shape.strokeColor = UIColor(red: 0, green: 209 / 255.0, blue: 124 / 255.0, alpha: 1).cgColor
        shape.lineCap = .round//线帽(线的端点)呈圆角状
        shape.lineJoin = .round//线连接处呈圆角状
        return shape
    }()
    
    private var shadeView: UIView!
    private var rippleView: UIView!
    
    /// 是否正在动画
    private(set) var animation: Bool = false
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        rippleView = UIView(frame: bounds)
        rippleView.alpha = 0
        addSubview(rippleView)
        
        shadeView = UIView(frame: bounds)
        shadeView.backgroundColor = UIColor.white.withAlphaComponent(0.5)
        
        shadeView.isHidden = true
        addSubview(shadeView)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        rippleView.frame = bounds
        shadeView.frame = bounds
        shadeView.layer.cornerRadius = bounds.height * 0.5
    }
    
    /// 开始动画
    func startAnimation() {
        // 动画中
        guard !animation else {
            return
        }
        
        self.animation = true
        self.isHidden = false
        self.shadeView.isHidden = false
        rippleView.layer.addSublayer(rippleLayer)
        rippleView.transform = .init(scaleX: 0.2, y: 0.2)
        rippleView.alpha = 1
        
        UIView.animate(withDuration: 1) {
            self.rippleView.transform = .init(scaleX: 1, y: 1)
            self.rippleView.alpha = 0
        } completion: { _ in
            self.rippleLayer.removeFromSuperlayer()
            
            self.shadeView.layer.addSublayer(self.successfulLayer)
            
            //给CAShapeLayer添加动画
            let checkAnimation = CABasicAnimation(keyPath: "strokeEnd")
            checkAnimation.duration = 0.5
            checkAnimation.fromValue = 0.0
            checkAnimation.toValue = 1.0
            checkAnimation.delegate = self
            self.successfulLayer.add(checkAnimation, forKey: "successful")
        }
        
    }
    
}

extension SceneExecuteAnimationView: CAAnimationDelegate {
    
    /// 动画结束回调
    func animationDidStop(_ anim: CAAnimation, finished flag: Bool) {
        // 动画完成隐藏动画view
        if (anim as? CABasicAnimation)?.keyPath == "strokeEnd" {
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 0.5) {
                self.successfulLayer.removeFromSuperlayer()
                self.isHidden = true
                self.animation = false
            }
        }
    }
    
}
