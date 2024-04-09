//
//  PopGestureScrollView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/10/18.
//

import UIKit

class PopGestureScrollView: UIScrollView, UIGestureRecognizerDelegate {

    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // 判断是否是系统的pop手势
        if let popClass = NSClassFromString("UILayoutContainerView"), otherGestureRecognizer.view?.isKind(of: popClass) ?? false, otherGestureRecognizer.isKind(of: UIPanGestureRecognizer.classForCoder()) {
            return true
        }
        return false
    }
    
}

