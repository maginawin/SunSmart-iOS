//
//  NavigationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/22.
//

import UIKit

protocol NavigationViewControllerBackItemDelegate: NSObjectProtocol {
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController)
}
//
//extension UIViewController: NavigationViewControllerBackItemDelegate {
//    func navigationControllerBackItemAction(_ navigationController: NavigationViewController) {
//        navigationController.popViewController(animated: true)
//    }
//}

class NavigationViewController: UINavigationController {

    weak var backItemDelegate: NavigationViewControllerBackItemDelegate?
     
    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationBar.barTintColor = .white
        let titleFont = Font_Medium_Size(18)
        let titleTextAttributes = [NSAttributedString.Key.font: titleFont,NSAttributedString.Key.foregroundColor: RGB(0, 0, 0, 0.85)]
        self.navigationBar.titleTextAttributes = titleTextAttributes
        self.navigationBar.shadowImage = UIImage()
        
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .white)
            appearance.titleTextAttributes = titleTextAttributes
            appearance.shadowImage = UIImage.image(size: CGSize(width: 1, height: 1), color: .clear)
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
        super.pushViewController(viewController, animated: animated)
    }
    
    /// 点击返回
    @objc private func backItemClick() {
        
        if let showVc = topViewController {
            backItemDelegate?.navigationController(self, backItemAction: showVc)
        }
        super.popViewController(animated: true)
    }
}

extension NavigationViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return children.count > 1
    }
}
