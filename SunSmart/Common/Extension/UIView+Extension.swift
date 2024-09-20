//
//  UIView+Extension.swift
//  HomeeMesh
//
//  Created by 袁科鸿 on 2023/1/4.
//

import Foundation

extension UIView {
    
    
    /// 设置view圆角
    /// - Parameters:
    ///   - corners: 圆角位置
    ///   - cornerRadii: 圆角半径
    ///   - rect: 圆角view的rect
    func addRoundedCorners(corners: UIRectCorner, cornerRadii: CGSize, rect: CGRect? = nil) {
        let frame = rect ?? self.bounds
        let rounded = UIBezierPath(roundedRect: frame, byRoundingCorners: corners, cornerRadii: cornerRadii)
        
        let shape = CAShapeLayer()
        shape.path = rounded.cgPath
        shape.frame = frame
        self.layer.mask = shape
//        self.layer.addSublayer(shape)
    }
    
    func snapshotImage() -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(self.frame.size, false, UIScreen.main.scale)
        let context = UIGraphicsGetCurrentContext()!
//        context.setShadow(offset: self.frame.size, blur: 0.3, color: UIColor.black.cgColor)
        layer.render(in: context)
        var image = UIGraphicsGetImageFromCurrentImageContext()
        if let data = image?.pngData() {
            image = UIImage(data: data)
        }
        UIGraphicsEndImageContext()
        return image
    }
    
    
    func addDashedBorder() {
        
        deleteDashedBorder()
        
        // 创建 CAShapeLayer
        let dashedBorder = CAShapeLayer()
        dashedBorder.name = "deshed"
        // 定义路径：使用 UIBezierPath 绘制边框路径
        dashedBorder.path = UIBezierPath(roundedRect: self.bounds, cornerRadius: self.layer.cornerRadius).cgPath
        
        // 设置边框的属性
        dashedBorder.strokeColor = RGB(174, 186, 226).cgColor  // 虚线的颜色
        dashedBorder.fillColor = nil  // 确保填充颜色为空
        
        dashedBorder.lineWidth = 1  // 虚线的宽度
        dashedBorder.lineDashPattern = [3, 3]  // 虚线的样式，6表示每段虚线的长度，3表示空白的长度
        
        // 设置CAShapeLayer的frame
        dashedBorder.frame = self.bounds
        
        // 添加到视图的layer上
        self.layer.addSublayer(dashedBorder)
    }
    
    func deleteDashedBorder() {
        if let deshedLayer = self.layer.sublayers?.first(where: { $0.name == "deshed" }) {
            deshedLayer.removeFromSuperlayer()
        }
    }
    
}

