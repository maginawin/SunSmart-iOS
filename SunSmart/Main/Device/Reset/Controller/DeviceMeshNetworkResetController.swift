//
//  DeviceMeshNetworkResetController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/20.
//

import UIKit

class DeviceMeshNetworkResetController: WMPageController {

    private var segmentedControl: CustomSegmentedControl!
    /// 加载条
    private var loadingBar: GradientLoadingBar!
    
    private let vcTitles: [String] = ["configured".localizedString, "not_configured".localizedString]
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "mesh_network_reset".localizedString
        view.backgroundColor = Background_Color
            
        self.scrollEnable = false
        
        loadingBar = GradientLoadingBar()
        loadingBar.isHidden = true
        view.addSubview(loadingBar)
        loadingBar.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-6))
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.height.equalTo(6)
        }
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: vcTitles)
        segmentedControl.margin = 0
        segmentedControl.cornerRadius = SCRYFrom(8)
        segmentedControl.titleFont = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
//        segmented.selectedIndex = 1
        segmentedControl.delegate = self
        menuView?.addSubview(segmentedControl)
//        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(16)).priority(.low)
            make.right.equalTo(SCRXFrom(-16)).priority(.low)
            make.height.equalToSuperview()
        }
        
    }

    func startScanAnimation() {
        loadingBar.isHidden = false
        loadingBar.startAnimating()
    }
    
    func stopScanAnimation() {
        loadingBar.stopAnimating()
        loadingBar.isHidden = true
    }

}

extension DeviceMeshNetworkResetController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return vcTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        
        switch index {
        case 0:
            let vc = DeviceMeshNetworkResetConfiguredController()
            vc.stateCallback = {[weak self] state in
                guard let self = self else { return }
                switch state {
                case .none:
                    self.stopScanAnimation()
                    self.menuView?.isUserInteractionEnabled = true
                    self.scrollEnable = true
                case .scanning:
                    self.startScanAnimation()
                    self.menuView?.isUserInteractionEnabled = true
                    self.scrollEnable = false
                case .identifying, .reseting:
                    self.menuView?.isUserInteractionEnabled = false
                    self.scrollEnable = false
                }
            }
            return vc
        case 1:
            let vc = DeviceMeshNetworkResetNotConfiguredController()
            vc.stateCallback = {[weak self] state in
                guard let self = self else { return }
                switch state {
                case .none:
                    self.stopScanAnimation()
                    self.menuView?.isUserInteractionEnabled = true
                    self.scrollEnable = true
                case .scanning:
                    self.startScanAnimation()
                    self.menuView?.isUserInteractionEnabled = true
                    self.scrollEnable = false
                case .identifying:
                    self.menuView?.isUserInteractionEnabled = false
                    self.scrollEnable = false
                }
            }
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(32 + 16)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top + SCRYFrom(16), width: view.width, height: SCRYFrom(32))
    }
    
    override func menuView(_ menu: WMMenuView!, shouldSelesctedIndex index: Int) -> Bool {
        return true
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
        segmentedControl?.selectedIndex = Int(self.selectIndex)
    }
}

extension DeviceMeshNetworkResetController: CustomSegmentedControlDelegate {
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        self.selectIndex = Int32(index)
    }
    
}
