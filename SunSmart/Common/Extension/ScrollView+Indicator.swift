//
//  ScrollView+Indicator.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/5.
//

import Foundation

// UIScrollView 扩展
extension UIScrollView {
    
    static var firstShowFlashScrollIndicators: UInt8 = 0
    
    /// 是否首次显示滑动指示器
    var firstShowFlashScrollIndicators: Bool {
        get {
            objc_getAssociatedObject(self, &UIScrollView.firstShowFlashScrollIndicators) as? Bool ?? true
        }set {
            objc_setAssociatedObject(self, &UIScrollView.firstShowFlashScrollIndicators, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    func flashScrollIndicatorsIfNeeded() {
        let shouldFlash = contentSize.height > bounds.height + 1 ||
                         contentSize.width > bounds.width + 1
        
        if shouldFlash {
            firstShowFlashScrollIndicators = false
            flashScrollIndicators()
        }
    }
}
