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
    let groupPath: GroupProximityLightingPathData
    private let vcTitles: [String] = ["sequence".localizedString, "trigger_zone".localizedString]
    private var addBtn: UIButton!
    private var segmentedControl: CustomSegmentedControl!
    private var syncFailedBtn: UIButton!
    
    private weak var sequenceVc: GroupPathSequenceViewController?
    private weak var triggerZoneVc: GroupPathSequenceTriggerZoneController?
    
    init(group: Group) {
        self.group = group
        self.groupPath = group.info.proximityLightingPath ?? .init(paths: [], zones: [])
        super.init(nibName: nil, bundle: nil)
        
        self.scrollEnable = false
//        self.menuViewLayoutMode = .center
//        self.titleSizeNormal = 15
//        self.titleSizeSelected = 15
//        self.titleColorNormal = SubText_Color
//        self.titleColorSelected = Bar_Color
//        self.menuItemWidth = SCRXFrom(90)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "path_sequence".localizedString
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(title: "save".localizedString, color: TextBlack_Color, target: self, sel: #selector(saveAction)),
            UIBarButtonItem(image: UIImage(named: "path_add")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(addItemAction))
        ]
        self.isModalInPresentation = true
        
//        navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: TextBlack_Color, target: self, sel: #selector(saveAction))
        setupUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        navigationController?.navigationBar.addSubview(syncFailedBtn)
        syncFailedBtn.snp.makeConstraints { make in
            make.centerX.bottom.equalToSuperview()
        }
        
        syncFailedBtn.isHidden = !group.nodes.contains(where: { $0.getNodeSyncProximityLighting() != nil })
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        syncFailedBtn.removeFromSuperview()
    }
    
    private func setupUI() {
        
        syncFailedBtn = UIButton(title: "devices_not_synced".localizedString, titleSize: 14, titleWeight: .light, titleColor: Red_Color, fit: false, normalImageName: "schedule_sync_failed", target: self, action: #selector(syncFailedBtnAction))
        syncFailedBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        syncFailedBtn.isHidden = true
        
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
    
    @objc private func syncFailedBtnAction() {
        
        let vc = SyncDevicesViewController(type: .proximityLightingPath(group: group, path: groupPath), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    @objc private func saveAction() {
   
        if let vc = self.sequenceVc {
            vc.stopSetPath()
            groupPath.paths = vc.setPaths
        }
        if let vc = self.triggerZoneVc {
            vc.stopSetZone()
            groupPath.zones = vc.setZones
        }
        group.info.proximityLightingPath = groupPath
        group.info.save()

        guard group.nodes.contains(where: { $0.getNodeSyncProximityLighting() != nil }) else {
            navigationController?.popViewController(animated: true)
            return
        }
        
        let vc = SyncDevicesViewController(type: .proximityLightingPath(group: group, path: groupPath))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popToViewController(vcClass: GroupViewController.classForCoder())
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
            let vc = GroupPathSequenceViewController(group: group, groupPath: groupPath)
            self.sequenceVc = vc
            return vc
        case 1:
            let vc = GroupPathSequenceTriggerZoneController(group: group, zones: groupPath.zones)
            self.triggerZoneVc = vc
            return vc
        default:
            return UIViewController()
        }
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

extension GroupPathSequencePageController: CustomSegmentedControlDelegate {
    
    /// 分段控制器切换item回调
    /// - Parameters:
    ///   - segmentedControl: 分段控制器
    ///   - index: 点击索引
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        self.selectIndex = Int32(index)
    }
    
}
