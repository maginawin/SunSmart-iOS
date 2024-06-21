//
//  NavigationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/22.
//

import UIKit

protocol NavigationViewControllerDelegate: NSObjectProtocol {
    
    /// 点击返回item回调
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController)
    
    /// pop手势begin回调，返回是否可以pop
    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool
}

extension NavigationViewControllerDelegate {
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
        
    }
    
    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool {
        return navigationController.children.count > 1
    }
}

//
//extension UIViewController: NavigationViewControllerBackItemDelegate {
//    func navigationControllerBackItemAction(_ navigationController: NavigationViewController) {
//        navigationController.popViewController(animated: true)
//    }
//}

class NavigationViewController: UINavigationController {

    weak var navigationDelegate: NavigationViewControllerDelegate?
     
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationBar.barTintColor = .white
        let titleFont = FONTS(18)
        let titleTextAttributes = [NSAttributedString.Key.font: titleFont,NSAttributedString.Key.foregroundColor: RGB(30, 35, 41)]
        self.navigationBar.titleTextAttributes = titleTextAttributes
        self.navigationBar.shadowImage = UIImage()
        
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .white)
            appearance.titleTextAttributes = titleTextAttributes
            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
            appearance.titleTextAttributes = titleTextAttributes
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            
        }
        interactivePopGestureRecognizer?.delegate = self
    }
    
    
    override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        if viewControllers.count > 0 {
            viewController.hidesBottomBarWhenPushed = true
            
            let backItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backItemClick))
            viewController.navigationItem.leftBarButtonItem = backItem
        }else {
            viewController.hidesBottomBarWhenPushed = false
        }
        visibleViewController?.hideNavigationBarState()
        super.pushViewController(viewController, animated: animated)
    }
    
    override func popViewController(animated: Bool) -> UIViewController? {
        
        visibleViewController?.hideNavigationBarState()
        return super.popViewController(animated: animated)
    }
    
    /// 点击返回
    @objc private func backItemClick() {
        
        if let showVc = topViewController, let delegate = self.navigationDelegate {
            delegate.navigationController(self, backItemAction: showVc)
        }else {
            _ = popViewController(animated: true)
        }
    }
}

extension NavigationViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        
        let result = self.navigationDelegate?.navigationController(self, gestureRecognizerShould: gestureRecognizer) ?? (self.children.count > 1)
        if result {
            visibleViewController?.hideNavigationBarState()
        }
        return result
    }
}
