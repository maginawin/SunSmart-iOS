//
//  SceneViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/25.
//

import UIKit
import NordicSigMeshSDK

/// Presentation follows saved intent, not online/resolvable Mesh targets.
enum SceneDetailLayout {
    case groups, devices, emptyDevices, unavailable

    static func resolve(configuration: SceneConfiguration?, loadFailed: Bool, draftAvailable: Bool) -> Self {
        guard !loadFailed else { return .unavailable }
        guard configuration?.kind == .devices else { return .groups }
        guard draftAvailable else { return .unavailable }
        return configuration?.deviceMembers.isEmpty == true ? .emptyDevices : .devices
    }
}

class SceneViewController: UIViewController {

    private var titleLabel: UILabel!
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var pageControl: UIPageControl!
    /// 是否需要更新数据源
    private var refreshData: Bool = true
    private var renderedRevision: SpacePageRevision?
    private var isPageVisible = false
    private var groups: [Group] = []
    private var devicesView: SceneDevicesSelectionView?
    private var detailLayout: SceneDetailLayout = .groups
    private var deviceMode: Bool { detailLayout == .devices }
    private let detailStatusLabel = UILabel()
    private let syncDisplay = SceneGroupDisplayState()
    private var appearances: [ObjectIdentifier: SceneGroupAppearance] = [:]
    
    /// 列数
    private var columnNum: Int = isIPad ? 4 : 3
    private var rowNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: SCRYFrom(44), left: SCRXFrom(40), bottom: SCRYFrom(44), right: SCRXFrom(40)) : UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(14)
    
    let space: SpaceData
    let scene: Scene
    
    init(space: SpaceData, scene: Scene) {
        self.space = space
        self.scene = scene
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

//        self.title = scene.name
        
        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close)).withoutSharedBackground()
        if space.sceneOperates.contains(.edit) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick)).withoutSharedBackground()
        }
        setupUI()
        
//        for i in 1...30 {
//            devices.append("ID \(i)")
//        }
        
        addNotification()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isPageVisible = true
        if refreshData || renderedRevision?.isCurrent != true {
            updateUI()
        } else {
            refreshVisibleAppearance()
        }
        refreshSyncStatus()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        isPageVisible = false
        syncDisplay.cancel()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        guard !deviceMode else { return }
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(rowNum - 1) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(rowNum)
        guard itemW > 0 else { return }
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let itemSize = CGSize(width: itemW, height: itemW + SCRYFrom(16))
        guard flowLayout.itemSize != itemSize else { return }
        flowLayout.itemSize = itemSize
        
        collectionView.snp.updateConstraints { make in
            let height = itemSize.height * CGFloat(columnNum) + flowLayout.minimumLineSpacing * CGFloat(columnNum - 1) + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom
//            ceil(height)
//            height = CGFloat(ceil(Float(height) * 100) / 100.0)
            make.height.equalTo(ceil(height))
        }
    }
    
    /// 添加通知监听
    private func addNotification() {
        
        NotificationCenter.default.addObserver(forName: .init(sceneDataUpdateNotificationName), object: nil, queue: .main) {[weak self] notification in
            guard let self else { return }
            if let changed = notification.object as? Scene, changed !== self.scene { return }
            self.refreshVisibleUI()
        }
        
        NotificationCenter.default.addObserver(forName: .init(groupsRefreshNotificationName), object: nil, queue: .main) {[weak self] _ in
            self?.refreshVisibleUI()
        }
        
        NotificationCenter.default.addObserver(forName: .init(groupDataUpdateNotificationName), object: nil, queue: .main) {[weak self] _ in
            guard let self else { return }
            guard self.isPageVisible else { self.refreshData = true; return }
            if self.renderedRevision?.isCurrent != true { self.updateUI() }
            else { self.refreshVisibleAppearance(); self.refreshSyncStatus() }
        }
        for name in [devicesUpdateNotificationName, deviceStateUpdateNotificationName, spacePermissionChangedNotificaitonName] {
            NotificationCenter.default.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] _ in self?.refreshVisibleUI() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refreshVisibleUI()
        }
        
    }
    
    
    private func updateUI() {
        let draft = scene.info.configuration?.kind == .devices ? try? SceneDraft(scene: scene) : nil
        detailLayout = SceneDetailLayout.resolve(configuration: scene.info.configuration,
            loadFailed: scene.info.configurationLoadFailed, draftAvailable: draft != nil)
        groups = detailLayout == .groups ? scene.info.groups : []
        titleLabel.text = scene.name
        titleLabel.isHidden = deviceMode
        navigationItem.title = deviceMode ? scene.name : nil
        navigationItem.rightBarButtonItem?.isEnabled = space.sceneOperates.contains(.edit)
        collectionView.isHidden = deviceMode; pageControl.isHidden = deviceMode
        if deviceMode, let draft {
            if let devicesView {
                devicesView.updateSavedConfiguration(draft, snapshot: syncDisplay.currentSnapshot)
            } else {
                let details = SceneDevicesSelectionView(selection: SceneDraftSelection(draft: draft), displayingSavedConfiguration: true)
                details.syncSnapshot = syncDisplay.currentSnapshot
                view.addSubview(details)
                details.snp.makeConstraints { make in make.top.equalTo(view.safeAreaLayoutGuide).offset(12); make.left.right.bottom.equalTo(view.safeAreaLayoutGuide) }
                devicesView = details
            }
        } else {
            devicesView?.removeFromSuperview(); devicesView = nil
        }
        updateDetailStatus()
        view.setNeedsLayout()
        appearances = NodeSyncStatusRefresh.sceneGroupAppearances(groups)
        refreshData = false
        renderedRevision = SpacePageRevision()
        collectionView.reloadData()
        updateEmptyUI()
        pageControl.numberOfPages = Int(ceil(Double(groups.count) / Double(columnNum * rowNum)))
        refreshSyncStatus()
    }

    private func refreshVisibleUI() {
        refreshData = true
        guard isPageVisible, isViewLoaded else { return }
        updateUI()
    }

    private func refreshSyncStatus() {
        guard isPageVisible else { return }
        syncDisplay.refresh(scene: scene) { [weak self] in
            guard let self, self.isPageVisible else { return }
            self.refreshVisibleAppearance()
        }
    }

    private func refreshVisibleAppearance() {
        devicesView?.syncSnapshot = syncDisplay.currentSnapshot
        updateDetailStatus()
        appearances = NodeSyncStatusRefresh.sceneGroupAppearances(groups)
        for indexPath in collectionView.indexPathsForVisibleItems where indexPath.item < groups.count {
            if let cell = collectionView.cellForItem(at: indexPath) as? SceneGroupsViewCell {
                configure(cell, group: groups[indexPath.item])
            }
        }
    }

    private func updateDetailStatus() {
        detailStatusLabel.text = detailLayout == .emptyDevices
            ? SceneDevicesSelectionView.savedStatus(configuration: scene.info.configuration, snapshot: syncDisplay.currentSnapshot) : nil
        detailStatusLabel.isHidden = detailStatusLabel.text == nil
    }

    private func configure(_ cell: SceneGroupsViewCell, group: Group) {
        let data = group.info.sceneExecuteDatas.first { $0.sceneNumber == scene.number }
        // An invalidated or in-flight read is not evidence of pending sync work.
        let needsSync = syncDisplay.currentSnapshot?.needsSync.contains(ObjectIdentifier(group)) == true
        cell.updateData(group: group, sceneData: data.map { .init(data: $0) },
                        appearance: appearances[ObjectIdentifier(group)], needsSync: needsSync)
    }
    
    @objc private func close() {
        dismiss(animated: true)
    }
    
    @objc private func moreClick() {
        guard space.sceneOperates.contains(.edit) else { return }
        if scene.info.configuration?.isDeleting == true { deleteScene(); return }
        
//        let margin: CGFloat = SCRXFrom(15.5)
////        isIphoneX ? 18 : 15
//        let touchCenterX = view.width - SCRXFrom(margin) - 15
//        let touchCenterY = SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        
        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
//        SCREEN_HEIGHT - view.height + view.safeAreaInsets.top - 15
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                self?.editScene()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
//                self?.deleteSite()
                self?.deleteScene()
            }),
            .init(icon: UIImage(named: "settings"), title: "settings".localizedString, hideAnimation: false, tapItemBack: {[weak self] item in
                self?.settings()
            })
            
        ], anchorPoint: windowPoint)
        
    }
    
    /// 编辑场景
    private func editScene() {
        guard space.sceneOperates.contains(.edit), scene.info.configuration?.isDeleting != true else { return }
        let original: SceneDraft
        do { original = try SceneConfigurationStore().editingDraft(for: scene) }
        catch { XWHUDManager.showErrorTipHUD("save_failure".localizedString); return }
        let vc = InfoEditViewController(name: scene.name, imageNames: sceneImageNames, selectImageIndex: max(scene.info.imageId - 1, 0), columnNum: 4)
        vc.title = "edit_scene".localizedString
        vc.itemRound = true
        vc.nameEditChangedCallback = {[weak self] name in
            guard let self = self else {
                return false
            }
            return MeshNetworkManager.instance.isSceneTautonym(name: name) && name != self.scene.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            do {
                guard self.space.sceneOperates.contains(.edit), self.scene.info.configuration?.isDeleting != true else { return false }
                var draft = original
                draft.setMetadata(name: name, imageId: imageId + 1)
                let result = try SceneConfigurationStore().commitMetadata(draft: draft, expectedRevision: draft.revision)
                guard case .ready = result else {
                    XWHUDManager.showErrorTipHUD("save_failure".localizedString)
                    return false
                }
            } catch {
                XWHUDManager.showErrorTipHUD("save_failure".localizedString)
                return false
            }
            self.titleLabel.text = name
            self.navigationItem.title = self.deviceMode ? name : nil
//            self.sceneUpdateCallback?(self.scene)
            NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            return true
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        let navVc = NavigationViewController(rootViewController: vc)
        present(navVc, animated: true)
    }
    
    /// 删除场景
    private func deleteScene() {
        
        SRAlertView(title: "notification".localizedString, message: "scene_delete_message".localizedString, contentPadding: SCRXFrom(25), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            // 测试数据
//            scene.nodes.forEach({
//                self.scene.remove(node: $0)
//            })
//            scene.delete()
            let existNode: Bool = self.scene.addresses.count > 0
            SceneServer.deleteScene(scene: self.scene) {[weak self] _ in
                XWHUDManager.hide()
                guard let self = self else { return }
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
//                self.groupDeleteCallback?(self.group)
                NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
                // 通知space数据修改
                let type: SpaceChangeDataType = existNode ? .device : .common
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: type)
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5, execute: {[weak self] in
                    self?.close()
                })
                
            } failed: { _ in
                // 跳转到同步数据页面
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("scene_delete_failed".localizedString)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                    self?.pushToSyncDevicesVc()
                }
            }
            
        })]).show()
        
    }
    
    /// 跳到同步数据页面
    private func pushToSyncDevicesVc() {
        
        let vc = SyncDevicesViewController(type: .scene(scene))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            SceneServer.deleteScene(scene: self.scene, success: { [weak self] _ in
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
                self?.close()
            }, failed: { _ in
                XWHUDManager.showErrorTipHUD("scene_delete_failed".localizedString)
            })
        }
        vc.backActionCallback = {[weak self] _ in
//                self?.dismiss(animated: true)
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: self.scene)
            self.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    /// 设置
    private func settings() {
        guard space.sceneOperates.contains(.edit), scene.info.configuration?.isDeleting != true else { return }
        let vc = SceneSettingsViewController(space: space, scene: scene)
        vc.enablesGroupLiveControl = true
        
//        let vc = GroupMembersViewController(space: space, group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard !deviceMode, sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < groups.count {
            
            let group = groups[indexPath.item]
//            let data = group.info.bindSceneDatas.first(where: { $0.sceneId == scene.number })?.data
            let vc = GroupViewController(space: space, group: group)
            navigationController?.pushViewController(vc, animated: true)
//            present(NavigationViewController(rootViewController: vc), animated: true)
        }
        
    }
    
    /// 分页页码编辑回调
    @objc private func pageControlValueChanged() {
        collectionView.setContentOffset(CGPoint(x: CGFloat(pageControl.currentPage) * collectionView.width, y: 0), animated: true)
    }

    private func updateEmptyUI() {
        
        if detailLayout == .unavailable {
            collectionView.showEmptyDataView(title: "scene_details_unavailable".localizedString, position: .center, bottomMargin: 3.5)
        } else if groups.isEmpty {
            collectionView.showEmptyDataView(title: "scene_no_members".localizedString, position: .center, bottomMargin: 3.5)
        }else {
            collectionView.hideEmptyDataView()
        }
        
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: scene.name, textColor: RGB(30, 35, 41), fontSize: 18, fontWeight: .light)
        titleLabel.textAlignment = .center
        view.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo(SCRYFit(60) + (navigationController?.navigationBar.frame.maxY ?? 0))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.scrollDirection = .horizontal
        flowLayout.itemRowCount = rowNum
        flowLayout.itmeColCount = columnNum
        flowLayout.sectionInset = collectionViewInsets //UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
//        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(36), left: SCRXFrom(24), bottom: SCRYFit(36), right: SCRXFrom(24))
        collectionView.backgroundColor = RGB(0, 0, 0, 0.05)
        collectionView.layer.cornerRadius = SCRYFrom(40)

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.isPagingEnabled = true
//        collectionView.showsHorizontalScrollIndicator = false
        collectionView.register(SceneGroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-29))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFit(45))
            make.height.equalTo(SCRYFrom(392))
        }
        
        pageControl = UIPageControl()
        pageControl.currentPageIndicatorTintColor = Bar_Color
        pageControl.pageIndicatorTintColor = RGB(216, 216, 216)
        pageControl.addTarget(self, action: #selector(pageControlValueChanged), for: .valueChanged)
        pageControl.hidesForSinglePage = true
        view.addSubview(pageControl)
        pageControl.snp.makeConstraints { make in
            make.bottom.equalTo(collectionView)
            make.centerX.equalToSuperview()
//            make.width.equalTo(SCRXFrom(40))
//            make.height.equalTo(4)
        }
        detailStatusLabel.font = .systemFont(ofSize: 12, weight: .light)
        detailStatusLabel.textColor = RGB(148, 163, 184)
        detailStatusLabel.textAlignment = .center
        detailStatusLabel.numberOfLines = 0
        view.addSubview(detailStatusLabel)
        detailStatusLabel.snp.makeConstraints { make in
            make.top.equalTo(collectionView.snp.bottom).offset(12)
            make.left.right.equalTo(collectionView)
        }
    }

}

extension SceneViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//        return 9
        return groups.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SceneGroupsViewCell
        configure(cell, group: groups[indexPath.item])
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard !deviceMode, space.sceneOperates.contains(.control), indexPath.item < groups.count else { return }
        let group = groups[indexPath.item]
        if group.nodes.isEmpty { // 空组
            XWHUDManager.showTipHUD("group_empty".localizedString, isLineFeed: true)
            return
        }
        if !MeshLibManager.manager.isMeshNetworkConnected { // 网络未连接
            XWHUDManager.showTipHUD("network_no_connnection".localizedString, isLineFeed: true)
            return
        }
        if !group.nodes.contains(where: { $0.state }) { // 组内设备全部离线
            XWHUDManager.showTipHUD("group_all_devices_offline".localizedString, isLineFeed: true)
            return
        }
        guard !showEmergencyControlBlockedIfNeeded(group: group) else {
            return
        }
        
        group.isOn = !group.isOn
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
        appearances = NodeSyncStatusRefresh.sceneGroupAppearances(groups)
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: [indexPath])
        CATransaction.commit()
        
        
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        
        pageControl.currentPage = page
        //            pageControl.setCurrentPage(page, animated: true)
    }
}

private extension SceneViewController {
    func showEmergencyControlBlockedIfNeeded(group: Group) -> Bool {
        guard EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: group) else {
            return false
        }
        XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
        return true
    }
}
