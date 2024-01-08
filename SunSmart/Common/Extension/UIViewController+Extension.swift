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
                
                return (rootVc as? UINavigationController)?.visibleViewController
            }else {
                return rootVc
            }
        }

    }
    
}


extension UINavigationController {
    
    /// 设置导航条颜色
    /// - Parameter showShadow: 是否显示分割线
    /// - Parameter color: 颜色
    func setNavigationBarBackgroundColor(color: UIColor, showShadow: Bool = false) {
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .clear
        if !showShadow {
            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
        }
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
    }
    
    /// 移除栈内控制器
    func removeVc(vc: UIViewController) {
        
        let vcArray = NSMutableArray.init(array: self.viewControllers)
        vcArray.remove(vc)
        self.viewControllers = vcArray as! [UIViewController]
    }
    
    /// 根据控制器类名返回到对应控制器
    func popToViewController(vcClass: AnyClass, animated: Bool = true) {
        if let vc = viewControllers.first(where: {$0.isKind(of: vcClass)}) {
            self.popToViewController(vc, animated: true)
        }
    }
    
}
