//
//  UIColor+Extension.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/28.
//

import Foundation

extension UIColor {
    
    /// 生成一批随机颜色
    static func generateDistinctColors(count: Int) -> [UIColor] {
        var colors: [UIColor] = []

        let saturation: CGFloat = 0.7
        let brightness: CGFloat = 0.9

        for i in 0..<count {
            let hue = CGFloat(i) / CGFloat(count)  // 均匀分布在 0 ~ 1
            let color = UIColor(hue: hue, saturation: saturation, brightness: brightness, alpha: 1.0)
            colors.append(color)
        }

        return colors.shuffled()  // 如果想要打乱顺序
    }
    
}
