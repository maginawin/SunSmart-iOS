//
//  UIViewController+Extension.swift
//  LightControl
//
//  Created by APPLE on 2019/8/28.
//  Copyright © 2019 qiongliao. All rights reserved.
//

import UIKit

extension UIViewController {
    
    
    /** 获取当前显示的控制器 */
    static func getVisibleVc() -> UIViewController? {
        let rootVc = UIApplication.shared.keyWindow().rootViewController
        if rootVc?.isKind(of: UITabBarController.self) ?? false {
            
            let tabbarVc = (rootVc as! UITabBarController)
            
            let childVc = tabbarVc.children[tabbarVc.selectedIndex]
            if childVc.isKind(of: UINavigationController.self) {
                
                return (childVc as? UINavigationController)?.visibleViewController
            }else {
                return childVc
            }
        }else {
            if rootVc?.isKind(of: UINavigationController.self) ?? false {
                let topVc = (rootVc as? UINavigationController)?.visibleViewController
//                if topVc?.presentedViewController != nil {
//                    return topVc?.presentedViewController
//                }else {
//                    if let childVc = topVc?.children.first {
                        if let presentingVc = topVc?.presentedViewController {
                            if presentingVc.isKind(of: UINavigationController.self) {
                                return (presentingVc as! UINavigationController).topViewController
                            }else {
                                return presentingVc
                            }
                        }
//                        return childVc
//                    }
//                }
                return topVc
            }else {
                return rootVc
            }
        }

    }
    
    func showNavigationBarLoading() {
        showNavigationBarState(.loading)
    }
    
    func showNavigationBarSuccessful() {
        showNavigationBarState(.successful)
        self.perform(#selector(navigationBarStateFinished), with: nil, afterDelay: 2)
    }
    
    func showNavigationBarFailure(duration: TimeInterval = .infinity, actionCallback: (()->Void)?) {
        showNavigationBarState(.failure, actionCallback: actionCallback)
        self.perform(#selector(navigationBarStateFinished), with: nil, afterDelay: duration)
    }
    
    func showNavigationBarState(_ state: NavigationBarState, actionCallback: (()->Void)? = nil) {
        
        guard let navVc = navigationController, navVc.interactivePopGestureRecognizer?.state == .possible, let contentView = navVc.navigationBarContentView, let titleView = navVc.navigationBarTitleView else { return  }
        
        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(navigationBarStateFinished), object: nil)
        
        var stateImageView = navVc.stateImageView
        if stateImageView == nil {
            stateImageView = UIImageView()
            navVc.stateImageView = stateImageView
        }
        
        if stateImageView?.superview == nil {
            contentView.addSubview(stateImageView!)
//            navVc.navigationBar.setNeedsFocusUpdate()
            stateImageView!.snp.makeConstraints { make in
                make.right.equalTo(titleView.snp.left).offset(SCRXFrom(-4))
                make.centerY.equalToSuperview()
            }
        }
        
        navVc.stateImageActionCallback = actionCallback
        if actionCallback != nil {
            stateImageView?.isUserInteractionEnabled = true
            stateImageView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(stateImageViewAction)))
        }else {
            stateImageView?.isUserInteractionEnabled = false
        }
        
        switch state {
        case .loading:
            if !(stateImageView?.layer.animationKeys()?.contains("loading") ?? false) {
                stateImageView?.image = UIImage(named: "sync_loading_small")
                stateImageView?.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
            }
        case .successful:
            stateImageView?.image = UIImage(named: "sync_success_small")
            stateImageView?.layer.removeAnimation(forKey: "loading")
        case .failure:
            stateImageView?.image = UIImage(named: "cloud_sync_failed")
            stateImageView?.layer.removeAnimation(forKey: "loading")
            stateImageView!.snp.remakeConstraints { make in
                make.right.equalTo(titleView.snp.left) 
                make.centerY.equalToSuperview()
            }
        }
     
    }
    
    /// 点击事件
    @objc private func stateImageViewAction() {
        guard let navVc = navigationController else {
            return
        }
        navVc.stateImageActionCallback?()
    }
    
    /// 导航条状态展示完成
    @objc private func navigationBarStateFinished() {
        hideNavigationBarState()
    }
    
    func hideNavigationBarState() {
        navigationController?.stateImageView?.removeFromSuperview()
        navigationController?.stateImageView = nil
       NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(navigationBarStateFinished), object: nil)
    }
    
    enum NavigationBarState {
        case loading
        case successful
        case failure
    }
    
}


extension UINavigationController {
    
    static var stateImageKey = 1
    static var stateImageActionCallbackKey = 2
    
    typealias StateImageActionCallback = (()->Void)
    
    /// 导航条状态图标
    var stateImageView: UIImageView? {
        get  {
//            guard let imageView = objc_getAssociatedObject(self, &UINavigationController.stateImageKey) as? UIImageView else {
//                self.stateImageView = UIImageView()
//                return self.stateImageView
//            }
            objc_getAssociatedObject(self, &UINavigationController.stateImageKey) as? UIImageView
        }set {
            objc_setAssociatedObject(self, &UINavigationController.stateImageKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 状态图标点击事件回调
   fileprivate var stateImageActionCallback: StateImageActionCallback? {
        get {
            objc_getAssociatedObject(self, &UINavigationController.stateImageActionCallbackKey) as? StateImageActionCallback
        }set {
            objc_setAssociatedObject(self, &UINavigationController.stateImageActionCallbackKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
    /// 导航条内容view
    var navigationBarContentView: UIView? {
        guard let contentClass = NSClassFromString("_UINavigationBarContentView") else { return nil }
        return navigationBar.subviews.first(where: { $0.isKind(of: contentClass) })
    }
    
    /// 导航条标题
    var navigationBarTitleView: UIView? {
        let titleViewClass: AnyClass? = NSClassFromString("_UINavigationBarTitleControl")
        return navigationBarContentView?.subviews.first(where: { $0.isKind(of: titleViewClass ?? UILabel.classForCoder()) }) as? UIView
    }
    
    
    /// 设置导航条颜色
    /// - Parameter showShadow: 是否显示分割线
    /// - Parameter color: 颜色
    func setNavigationBarBackgroundColor(color: UIColor, showShadow: Bool = false) {
        
        let appearance = navigationBar.standardAppearance 
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = color
        if !showShadow {
            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
        }
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
    }
    
    
    /// 移除栈内控制器
    func removeVc(vc: UIViewController) {
        
        removeViewControllers(viewControllers: [vc])
    }
    
    /// 移除栈内控制器list
    func removeViewControllers(viewControllers: [UIViewController]) {
        
        var vcArray = self.viewControllers
        vcArray.removeAll(where: { viewControllers.contains($0) })
        self.viewControllers = vcArray
    }
    
    /// 根据控制器类名返回到对应控制器
    func popToViewController(vcClass: AnyClass, animated: Bool = true) {
        if let vc = viewControllers.first(where: {$0.isKind(of: vcClass)}) {
            self.popToViewController(vc, animated: true)
        }else {
            self.popViewController(animated: true)
        }
    }
    
    
}
