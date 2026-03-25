//
//  UITableView+Keyboard.swift
//  SunSmart
//
//  Created by yuankehong on 2025/8/7.
//

import Foundation

extension UIScrollView {
    /// 启用点击空白处隐藏键盘功能
    func enableKeyboardDismissal() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tapGesture.cancelsTouchesInView = true
        
        let delegateProxy = TapGestureDelegateProxy(scrollView: self)
        tapGesture.delegate = delegateProxy
        
        self.addGestureRecognizer(tapGesture)
        
        // 同时启用拖动时隐藏键盘
        self.keyboardDismissMode = .onDrag
        
        // 存储手势和代理
        objc_setAssociatedObject(self, &AssociatedKeys.tapGesture, tapGesture, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &AssociatedKeys.gestureDelegate, delegateProxy, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
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
        static var tapGesture: UInt8 = 0
        static var gestureDelegate: UInt8 = 0
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


private class TapGestureDelegateProxy: NSObject, UIGestureRecognizerDelegate {
    weak var scrollView: UIScrollView?

    init(scrollView: UIScrollView) {
        self.scrollView = scrollView
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
          guard let scrollView = scrollView else { return false }

          // ✅ 键盘没弹出（没有第一响应者）就别参与，完全不拦截
          guard scrollView.firstResponder != nil else { return false }

          let location = touch.location(in: scrollView)
          let touchedView = scrollView.hitTest(location, with: nil)

          // ✅ 键盘弹出时：
          if let v = touchedView {
              // 点到输入控件本身：不收起（继续编辑体验）
              if v is UITextField || v is UITextView || v is UISearchBar {
                  return false
              }

              // 点到 UIControl（比如 UIButton）：要收起键盘，但不能吞掉点击
              if v is UIControl {
                  gestureRecognizer.cancelsTouchesInView = false
                  return true
              }
          }

          // 点到空白/Cell背景等：收起键盘，并吞掉点击，避免“点透”触发选中/按钮等
          gestureRecognizer.cancelsTouchesInView = true
          return true
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


/// 键盘弹出后scrollview自动跟随到对应位置
protocol KeyboardScrollable: AnyObject {
    var keyboardScrollView: UIScrollView { get }
    func registerForKeyboardNotifications()
    func unregisterFromKeyboardNotifications()
}

extension KeyboardScrollable where Self: UIViewController {
    func registerForKeyboardNotifications() {
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillShowNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.keyboardWillShow(notification)
        }
        
        NotificationCenter.default.addObserver(
            forName: UIResponder.keyboardWillHideNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.keyboardWillHide(notification)
        }
    }
    
    func unregisterFromKeyboardNotifications() {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func keyboardWillShow(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let keyboardFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let activeView = view.firstResponder else {
            return
        }
        
        if keyboardScrollView.originalContentInset == nil {
            keyboardScrollView.originalContentInset = keyboardScrollView.contentInset
        }
        
        let keyboardHeight = keyboardFrame.height
        let contentInsets = UIEdgeInsets(top: keyboardScrollView.contentInset.top, left: keyboardScrollView.contentInset.left, bottom: keyboardHeight, right: keyboardScrollView.contentInset.right)
        
        keyboardScrollView.contentInset = contentInsets
        
        // 滚动到可见
        var visibleRect = keyboardScrollView.frame
        visibleRect.size.height -= keyboardHeight
        
        let activeRect = activeView.convert(activeView.bounds, to: keyboardScrollView)
        
        if !visibleRect.contains(activeRect.origin) {
            keyboardScrollView.scrollRectToVisible(activeRect, animated: true)
        }
    }
    
    private func keyboardWillHide(_ notification: Notification) {
        keyboardScrollView.contentInset = keyboardScrollView.originalContentInset ?? .zero
    }
}

// MARK: - UIScrollView扩展，用于保存原始contentInset
private var originalContentInsetKey: Void?

extension UIScrollView {
    // 保存原始的contentInset
    var originalContentInset: UIEdgeInsets? {
        get {
            return objc_getAssociatedObject(self, &originalContentInsetKey) as? UIEdgeInsets
        }
        set {
            objc_setAssociatedObject(self, &originalContentInsetKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
}
