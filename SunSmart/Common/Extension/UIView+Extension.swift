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
    
    
}

