//
//  UITableView+Keyboard.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/7.
//

import Foundation

extension UITableView {
    /// 启用点击空白处隐藏键盘功能
    func enableKeyboardDismissal() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        self.addGestureRecognizer(tapGesture)
        
        // 同时启用拖动时隐藏键盘
        self.keyboardDismissMode = .onDrag
        
        // 存储手势以避免重复添加
        objc_setAssociatedObject(self, &AssociatedKeys.tapGesture, tapGesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// 禁用点击空白处隐藏键盘功能
    func disableKeyboardDismissal() {
        if let gesture = objc_getAssociatedObject(self, &AssociatedKeys.tapGesture) as? UITapGestureRecognizer {
            self.removeGestureRecognizer(gesture)
        }
    }
    
    @objc private func dismissKeyboard() {
        self.window?.endEditing(true)
    }
    
    private struct AssociatedKeys {
        static var tapGesture = 100
    }
}

extension UICollectionView {
    
    /// 启用点击空白处隐藏键盘功能
    func enableKeyboardDismissal() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = false
        self.addGestureRecognizer(tapGesture)
        
        // 同时启用拖动时隐藏键盘
        self.keyboardDismissMode = .onDrag
        
        // 存储手势以避免重复添加
        objc_setAssociatedObject(self, &AssociatedKeys.tapGesture, tapGesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    /// 禁用点击空白处隐藏键盘功能
    func disableKeyboardDismissal() {
        if let gesture = objc_getAssociatedObject(self, &AssociatedKeys.tapGesture) as? UITapGestureRecognizer {
            self.removeGestureRecognizer(gesture)
        }
    }
    
    @objc private func dismissKeyboard() {
        self.window?.endEditing(true)
    }
    
    private struct AssociatedKeys {
        static var tapGesture = 100
    }
}


