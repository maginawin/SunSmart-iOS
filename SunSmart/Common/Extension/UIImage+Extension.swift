//
//  UIImage+Extension.swift
//  BLE-OTA
//
//  Created by 袁科鸿 on 2022/12/8.
//

import UIKit

extension UIImage {
    
    /// 根据size和color生成图片
    /// - Parameters:
    ///   - size: 图片大小
    ///   - color: 颜色
    /// - Returns: 图片
    static func image(size: CGSize, color: UIColor) -> UIImage {
        let frame = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        UIGraphicsBeginImageContext(frame.size)
        let context = UIGraphicsGetCurrentContext()
        context?.setFillColor(color.cgColor)
        context?.fill([frame])
        let image = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return image ?? UIImage()
    }
    
    
    /// 根据信号值获取对应信号强度图片
    /// - Parameter signal: 信号值
    /// - Returns: 图片
    static func getSignalImage(signal: Int) -> UIImage {
        // 信号等级
        var level = 0
        switch signal {
        case -40 ... -1:
            level = 5
        case -50 ... -40:
            level = 4
        case -65 ... -50:
            level = 3
        case -75 ... -65:
            level = 2
        case -90 ... -75:
            level = 1
        default:
            break
        }
        return UIImage(named: "signal_\(level)") ?? UIImage()
    }
    
    
    
}

