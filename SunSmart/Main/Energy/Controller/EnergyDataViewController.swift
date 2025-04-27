//
//  EnergyDataViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/27.
//

import UIKit

class EnergyDataViewController: WMPageController {

    let space: SpaceData
    
    private var menuTitles: [String] = ["static_data".localizedString, "time_series_data".localizedString]
    private var menuHeight = SCRYFrom(25)
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
        self.menuViewLayoutMode = .center
        self.itemMargin = SCRXFrom(53)
        self.progressWidth = SCRXFrom(115)
        self.progressHeight = 2
        self.progressColor = Bar_Color
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "energy_data".localizedString
        view.backgroundColor = Background_Color
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(help))
        
    }
    
    @objc private func back() {
        dismiss(animated: true)
    }
    
    @objc private func help() {
        
        
    }

}

extension EnergyDataViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return menuTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        
        switch index {
        case 0:
            let vc = DeviceLightsViewController(space: space)
            return vc
        case 1:
            let vc = DeviceSwitchesViewController(space: space)
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
//        let y = SCRYFrom(42)
//        let footerH = SCRYFrom(44) + kSafeAreaBottomHeight
        return CGRect(x: 0, y: 0, width: view.width, height: view.height)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: SCRYFrom(isIPad ? 20 : 10), width: view.width, height: menuHeight)
    }
    
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return !XWHUDManager.isVisible()
//        return index < 3
    }
    
    
    
}

extension EnergyDataViewController {
    
    override func numbersOfTitles(in menu: WMMenuView!) -> Int {
        return menuTitles.count
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return menuTitles[index]
    }
    
    override func menuView(_ menu: WMMenuView!, titleSizeFor state: WMMenuItemState, at index: Int) -> CGFloat {
        return state == .selected ? 15 : 14.5
    }
    
    override func menuView(_ menu: WMMenuView!, titleColorFor state: WMMenuItemState, at index: Int) -> UIColor! {
        return state == .selected ? Bar_Color : Title_Color
    }
    
    override func menuView(_ menu: WMMenuView!, widthForItemAt index: Int) -> CGFloat {
        return SCRXFrom(120)
//        isIPad ? SCRXFrom(120) : SCRXFrom(80)
    }
}
