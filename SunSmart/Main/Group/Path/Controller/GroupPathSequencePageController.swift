//
//  GroupPathSequencePageController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/16.
//

import UIKit
import NordicSigMeshSDK

class GroupPathSequencePageController: WMPageController {

    let group: Group
    let groupPath: GroupProximityLightingPathData?
    private let vcTitles: [String] = ["sequence".localizedString, "trigger_zone".localizedString]
    private var addBtn: UIButton!
    
    private weak var sequenceVc: GroupPathSequenceViewController?
    private weak var triggerZoneVc: GroupPathSequenceTriggerZoneController?
    
    init(group: Group, groupPath: GroupProximityLightingPathData?) {
        self.group = group
        self.groupPath = groupPath
        super.init(nibName: nil, bundle: nil)
        
        self.menuViewStyle = .line
        self.progressHeight = 2
        self.progressWidth = SCRXFrom(90)
        self.menuViewLayoutMode = .center
        self.progressColor = Bar_Color
        self.progressViewBottomSpace = SCRYFrom(6)
        self.titleSizeNormal = 15
        self.titleSizeSelected = 15
        self.titleColorNormal = SubText_Color
        self.titleColorSelected = Bar_Color
        self.menuItemWidth = SCRXFrom(90)
        self.itemMargin = SCRXFrom(20)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "path_sequence".localizedString
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
//        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "path_add")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(addItemAction))
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: TextBlack_Color, target: self, sel: #selector(saveAction))
        
        addBtn = UIButton(normalImageName: "path_add", target: self, action: #selector(addItemAction))
        menuView?.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(-20)
            make.centerY.equalToSuperview()
        }
    }
    
    @objc private func saveAction() {
        
        let groupPath = groupPath ?? .init(paths: [], zones: [])
        
        if let vc = self.sequenceVc {
            groupPath.paths = vc.setPaths
        }
        if let vc = self.triggerZoneVc {
            groupPath.zones = vc.setZones
        }
        group.info.proximityLightingPath = groupPath
        group.info.save()
        
        let vc = SyncDevicesViewController(type: .proximityLightingPath(path: groupPath))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    @objc private func addItemAction() {
        
        switch currentViewController {
        case let vc as GroupPathSequenceViewController:
            vc.addPath()
        case let vc as GroupPathSequenceTriggerZoneController:
            vc.addZone()
        default:
            break
        }
        
    }
    
}

extension GroupPathSequencePageController {
    
    override func numbersOfChildControllers(in pageController: WMPageController) -> Int {
        return vcTitles.count
    }
    
    override func pageController(_ pageController: WMPageController, viewControllerAt index: Int) -> UIViewController {
        switch index {
        case 0:
            let vc = GroupPathSequenceViewController(group: group, paths: groupPath?.paths ?? [])
            self.sequenceVc = vc
            return vc
        case 1:
            let vc = GroupPathSequenceTriggerZoneController(group: group, zones: groupPath?.zones ?? [])
            self.triggerZoneVc = vc
            return vc
        default:
            return UIViewController()
        }
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameForContentView contentView: WMScrollView) -> CGRect {
        let y = view.safeAreaInsets.top + SCRYFrom(45)
        return CGRect(x: 0, y: y, width: view.width, height: view.height - y)
    }
    
    override func pageController(_ pageController: WMPageController, preferredFrameFor menuView: WMMenuView) -> CGRect {
        return CGRect(x: 0, y: view.safeAreaInsets.top, width: view.width, height: SCRYFrom(45))
    }
    
    override func menuView(_ menu: WMMenuView!, titleAt index: Int) -> String! {
        return vcTitles[index]
    }
    
//    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
//        mainMenuView.selectIndex = Int(self.selectIndex)
//        if let disablePageIndex = self.disablePageIndex, selectIndex == disablePageIndex {
//            self.scrollEnable = false
//        }
//    }
    
    
//    override func menuView(_ menu: WMMenuView!, didSelectedIndex index: Int, currentIndex: Int) {
//        super.menuView(menu, didSelectedIndex: index, currentIndex: currentIndex)
//
//        if let disablePageIndex = self.disablePageIndex, index == disablePageIndex {
//            self.scrollEnable = false
//        }else {
//            self.scrollEnable = true
//        }
//    }
    
}

