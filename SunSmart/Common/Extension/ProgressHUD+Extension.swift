//
//  ProgressHUD+Extension.swift
//  SunSmart
//
//  Created by yuankehong on 2025/11/4.
//

import Foundation

extension WYProgressHUD {
    
    static var closeCallback = 100
    static var closeButton = 101
    
    /// HUD添加关闭按钮
    func addCloseButton(closeCallback: (()->Void)?) {
        
        removeExistingCloseButton()
        
        let closeButton = UIButton()
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setImage(UIImage(named: "close"), for: .normal)
        closeButton.addTarget(self, action: #selector(closeButtonTapped), for: .touchUpInside)
        self.bezelView.addSubview(closeButton)
        
        NSLayoutConstraint.activate([
            closeButton.rightAnchor.constraint(equalTo: self.bezelView.rightAnchor, constant: -8),
            closeButton.topAnchor.constraint(equalTo: self.bezelView.topAnchor, constant: 8)
        ])
        
        // 存储回调
        if let closeCallback = closeCallback {
            objc_setAssociatedObject(self,
                                   &WYProgressHUD.closeCallback,
                                   closeCallback,
                                   .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
        
        // 存储按钮引用
        objc_setAssociatedObject(self,
                               &WYProgressHUD.closeButton,
                               closeButton,
                               .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
    }

    
    private func removeExistingCloseButton() {
        // 移除按钮视图
        if let existingButton = objc_getAssociatedObject(self, &WYProgressHUD.closeButton) as? UIButton {
            existingButton.removeFromSuperview()
        }
        
        // 清理关联对象
        objc_setAssociatedObject(self, &WYProgressHUD.closeButton, nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(self, &WYProgressHUD.closeCallback, nil, .OBJC_ASSOCIATION_COPY_NONATOMIC)
    }
    
    @objc private func closeButtonTapped() {
        // 执行关闭回调
        if let callback = objc_getAssociatedObject(self, &WYProgressHUD.closeCallback) as? () -> Void {
            callback()
        }
        
        // 隐藏HUD
        self.hide(animated: true)
    }
    
    
}
