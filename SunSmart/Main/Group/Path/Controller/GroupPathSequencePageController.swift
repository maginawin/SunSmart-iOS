//
//  GroupPathSequencePageController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/16.
//

import UIKit
import NordicSigMeshSDK

class GroupPathSequencePageController: WMPageController {

    let space: SpaceData
    let group: Group
    let groupPath: GroupProximityLightingPathData
    private let deviceNameFilterSession = DeviceNameFilterSession()
    private let vcTitles: [String] = ["sequence".localizedString, "trigger_zone".localizedString]
    private var addBtn: UIButton!
    private var segmentedControl: CustomSegmentedControl!
    private var syncFailedBtn: UIButton!
    
    private weak var sequenceVc: GroupPathSequenceViewController?
    private weak var triggerZoneVc: GroupPathSequenceTriggerZoneController?
    
    init(space: SpaceData, group: Group) {
        self.space = space
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
        
        let plan = ProximityLightingTopologyPlanner.makePlan(space: space)
        updateSyncFailedState(using: plan)
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
        let plan = ProximityLightingTopologyPlanner.makePlan(space: space)
        guard !showCapacityLimitIfNeeded(for: plan) else {
            return
        }
        let syncDatas = makeSyncDatas(using: plan)
        guard !syncDatas.isEmpty else {
            syncFailedBtn.isHidden = true
            return
        }

        let vc = SyncDevicesViewController(
            type: .proximityLightingPath(datas: syncDatas),
            reSync: true
        )
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
        let savedPath = group.info.proximityLightingPath?.copy()
            ?? GroupProximityLightingPathData(paths: [], zones: [])
        let proposedPath = groupPath.copy()
        if let vc = self.sequenceVc {
            vc.stopSetPath()
            proposedPath.paths = vc.setPaths
        }
        if let vc = self.triggerZoneVc {
            vc.stopSetZone()
            proposedPath.zones = vc.setZones
        }
        let edit = !(savedPath == proposedPath)
        let plan = ProximityLightingTopologyPlanner.makePlan(
            space: space,
            groupPathOverrides: [group.address.address: proposedPath]
        )
        guard !showCapacityLimitIfNeeded(for: plan) else {
            return
        }
        let syncDatas = makeSyncDatas(using: plan)

        if edit {
            space.markLocalChangePendingCloudSync()
        }
        groupPath.paths = proposedPath.paths
        groupPath.zones = proposedPath.zones
        group.info.proximityLightingPath = groupPath
        group.info.save()
        group.updateGroupSyncState()

        guard !syncDatas.isEmpty else {
            navigationController?.popViewController(animated: true)
            if edit {
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            }
            return
        }
        
        let vc = SyncDevicesViewController(
            type: .proximityLightingPath(datas: syncDatas)
        )
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                self?.navigationController?.popToViewController(vcClass: GroupViewController.classForCoder())
            }
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }

    private func makeSyncDatas(
        using plan: ProximityLightingTopologyPlanner.Plan
    ) -> [(node: Node, syncData: NodeSyncData)] {
        return group.nodes.compactMap { node in
            guard let syncData = node.getNodeSyncProximityLighting(
                group: group,
                topologyPlan: plan
            ) else {
                return nil
            }
            return (node, syncData)
        }
    }

    private func updateSyncFailedState(
        using plan: ProximityLightingTopologyPlanner.Plan
    ) {
        syncFailedBtn.isHidden = !plan.hasCapacityViolation
            && makeSyncDatas(using: plan).isEmpty
    }

    @discardableResult
    private func showCapacityLimitIfNeeded(
        for plan: ProximityLightingTopologyPlanner.Plan
    ) -> Bool {
        guard let message = ProximityLightingTopologyPlanner.capacityLimitMessage(
            for: plan
        ) else {
            return false
        }
        XWHUDManager.showTipHUD(message, isLineFeed: true)
        return true
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
            let vc = GroupPathSequenceViewController(
                group: group,
                groupPath: groupPath,
                deviceNameFilterSession: deviceNameFilterSession
            )
            self.sequenceVc = vc
            return vc
        case 1:
            let vc = GroupPathSequenceTriggerZoneController(
                group: group,
                zones: groupPath.zones,
                deviceNameFilterSession: deviceNameFilterSession
            )
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
    
    override func pageController(_ pageController: WMPageController, didEnter viewController: UIViewController, withInfo info: [AnyHashable : Any]) {
        segmentedControl?.selectedIndex = Int(self.selectIndex)
        if self.selectIndex == 0 {
            self.triggerZoneVc?.deselectZone()
        }else {
            self.sequenceVc?.deselectPath()
        }
    }
    
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
