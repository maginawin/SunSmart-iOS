//
//  UITableView+Keyboard.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/7.
//

import Foundation

//extension UITableView {
//    /// 启用点击空白处隐藏键盘功能
//    func enableKeyboardDismissal() {
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
//        tapGesture.cancelsTouchesInView = false
//        self.addGestureRecognizer(tapGesture)
//        
//        // 同时启用拖动时隐藏键盘
//        self.keyboardDismissMode = .onDrag
//        
//        // 存储手势以避免重复添加
//        objc_setAssociatedObject(self, &AssociatedKeys.tapGesture, tapGesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
//    }
//    
//    /// 禁用点击空白处隐藏键盘功能
//    func disableKeyboardDismissal() {
//        if let gesture = objc_getAssociatedObject(self, &AssociatedKeys.tapGesture) as? UITapGestureRecognizer {
//            self.removeGestureRecognizer(gesture)
//        }
//    }
//    
//    @objc private func dismissKeyboard() {
//        self.window?.endEditing(true)
//    }
//    
//    private struct AssociatedKeys {
//        static var tapGesture = 100
//    }
//}
//
//extension UICollectionView {
//    
//    /// 启用点击空白处隐藏键盘功能
//    func enableKeyboardDismissal() {
//        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
//        tapGesture.cancelsTouchesInView = false
//        self.addGestureRecognizer(tapGesture)
//        
//        // 同时启用拖动时隐藏键盘
//        self.keyboardDismissMode = .onDrag
//        
//        // 存储手势以避免重复添加
//        objc_setAssociatedObject(self, &AssociatedKeys.tapGesture, tapGesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
//    }
//    
//    /// 禁用点击空白处隐藏键盘功能
//    func disableKeyboardDismissal() {
//        if let gesture = objc_getAssociatedObject(self, &AssociatedKeys.tapGesture) as? UITapGestureRecognizer {
//            self.removeGestureRecognizer(gesture)
//        }
//    }
//    
//    @objc private func dismissKeyboard() {
//        self.window?.endEditing(true)
//    }
//    
//    private struct AssociatedKeys {
//        static var tapGesture = 100
//    }
//}
//
//


extension UIScrollView {
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
    
    @objc private func dismissKeyboard(sender: UIGestureRecognizer) {
        guard sender.state == .ended else { return }
        
        let point = sender.location(in: self)
        
        // 检查是否点击了 Cell
        if let tableView = self as? UITableView {
            if let indexPath = tableView.indexPathForRow(at: point),
               let cell = tableView.cellForRow(at: indexPath) {
                // 检查是否点击了可编辑的视图（TextField 等）
                if isTouchingEditableView(at: point, in: cell) {
                    return // 点击了可编辑视图，不隐藏键盘
                }
            }
        }
        // 点击了空白区域，隐藏键盘
        self.endEditing(true)
    }
    
    private struct AssociatedKeys {
        static var tapGesture = 100
    }
    
    /// 检查是否点击了可编辑的视图
      private func isTouchingEditableView(at point: CGPoint, in cell: UITableViewCell) -> Bool {
          
          let cellPoint = self.convert(point, to: cell)
          
          // 检查所有子视图
          for subview in cell.allSubviews {
              let subviewPoint = cell.convert(cellPoint, to: subview)
              
              if subview.isFirstResponder && subview.point(inside: subviewPoint, with: nil) {
                  return true // 点击了第一响应者
              }
              
              if let textField = subview as? UITextField,
                 textField.isFirstResponder,
                 isTouchingClearButton(in: textField, at: subviewPoint) {
                  return true // 点击了 TextField 的 Clear 按钮
              }
              
              if (subview is UITextField) || (subview is UITextView) || (subview is UISearchBar) {
                  if subview.point(inside: subviewPoint, with: nil) {
                      return true // 点击了可编辑视图
                  }
              }
          }
          
          return false
      }
      
      /// 检查是否点击了 TextField 的 Clear 按钮
      private func isTouchingClearButton(in textField: UITextField, at point: CGPoint) -> Bool {
          let clearButtonRect = textField.clearButtonRect(forBounds: textField.bounds)
          return clearButtonRect.contains(point)
      }
    
}

// UIView 扩展，用于查找第一响应者
extension UIView {
    var firstResponder: UIView? {
        guard !isFirstResponder else { return self }
        for subview in subviews {
            if let firstResponder = subview.firstResponder {
                return firstResponder
            }
        }
        return nil
    }
    
    /// 获取所有子视图（递归）
    var allSubviews: [UIView] {
        var allSubviews = self.subviews
        for subview in self.subviews {
            allSubviews.append(contentsOf: subview.allSubviews)
        }
        return allSubviews
    }
}
