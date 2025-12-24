//
//  ProfileDayNightLuxViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/19.
//

import UIKit
import NordicSigMeshSDK

class ProfileDayNightLuxViewController: WMPageController {

    let group: Group
    private let vcTitles: [String] = ["light_sensor_template".localizedString, "device".localizedString]
    private var segmentedControl: CustomSegmentedControl!
    
    init(group: Group) {
        self.group = group
        super.init(nibName: nil, bundle: nil)
        
        self.scrollEnable = false
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "device_detail".localizedString
        view.backgroundColor = Background_Color
        
        setupUI()
    }
    
    private func setupUI() {
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: vcTitles)
        segmentedControl.margin = 0
        segmentedControl.titleFont = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
//        segmented.selectedIndex = 1
        segmentedControl.delegate = self
        menuView?.addSubview(segmentedControl)
//        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(8))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalToSuperview()
        }
        
    }
    
}

extension ProfileDayNightLuxViewController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return vcTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
//        switch index {
//        case 0:
//            let vc = GroupPathSequenceViewController(group: group, groupPath: groupPath)
//            self.sequenceVc = vc
//            return vc
//        case 1:
//            let vc = GroupPathSequenceTriggerZoneController(group: group, zones: groupPath.zones)
//            self.triggerZoneVc = vc
//            return vc
//        default:
            return UIViewController()
//        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(36 + 8)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top + SCRYFrom(8), width: view.width, height: SCRYFrom(36))
    }
    
    
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return ""
    }
    
//    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
//        segmentedControl?.selectedIndex = Int(self.selectIndex)
//    }
    
}

extension ProfileDayNightLuxViewController: CustomSegmentedControlDelegate {
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        self.selectIndex = Int32(index)
    }
    
}
