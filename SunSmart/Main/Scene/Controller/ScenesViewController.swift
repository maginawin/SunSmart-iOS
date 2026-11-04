//
//  ScenesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/19.
//

import UIKit
import NordicSigMeshSDK

/// Historical repair is owned by actual Scene-page entry, never by export or
/// generic sync reads. Permanent device deletion uses its own existing journal.
@MainActor
enum ScenePageMembershipCleanup {
    private struct Membership: Equatable {
        let identities: Set<TimedSchedulerNodeIdentity>
        let occupied: Set<UInt16>

        init(network: MeshNetwork) throws {
            // Presence includes offline and not-yet-configured devices.
            let nodes = network.nodes.filter { !$0.isLocalProvisioner && !$0.isProvisioner }
            let identities = nodes.compactMap(\.sceneConfigurationIdentity)
            guard identities.count == nodes.count, Set(identities).count == nodes.count else {
                throw SceneConfigurationStore.Failure.invalidTargets
            }
            self.identities = Set(identities)
            occupied = Set(network.nodes.flatMap { ProximityLightingLifecycleCoordinator.topologyAddresses(for: $0) })
        }
    }

    static func prepare(space: SpaceData, isCurrent: () -> Bool) async -> Bool {
        let manager = MeshNetworkManager.instance
        let scope = SceneScope(meshUUID: space.meshUUID, networkID: space.meshNetworkId)
        guard let activeNetwork = manager.meshNetwork, let site = SiteData.load(siteId: space.siteId),
              let context = try? SpaceConfigurationSafety.recoveryState(space) else { return false }
        func eligible() -> Bool {
            guard isCurrent(), !_Concurrency.Task<Never, Never>.isCancelled,
                  manager.meshNetwork === activeNetwork, activeNetwork.uuid.uuidString == scope.meshUUID,
                  manager.currentNetworkKey.networkId.hex == scope.networkID,
                  SpaceConfigurationSafety.isCurrent(context, space: space),
                  SpaceConfigurationSafety.canCleanSyncReferences(space),
                  !SpaceConfigurationSafety.hasPendingDeletionCleanup(space),
                  !SpaceConfigurationSafety.hasPendingUpload(space), !MeshProxyMessageCommand.shared.isBusy,
                  let saved = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
                  saved.lastUpdate == space.lastUpdate, saved.canEditing else { return false }
            return true
        }
        func membership() throws -> Membership {
            guard let persisted = MeshNetwork.load(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) else {
                throw SceneConfigurationStore.Failure.unavailable
            }
            let saved = try Membership(network: persisted)
            guard saved == (try Membership(network: activeNetwork)) else { throw SceneConfigurationStore.Failure.staleDraft }
            return saved
        }
        // An interrupted reference transaction is resumed by the existing
        // recovery/upload path; do not take ownership of another operation.
        guard eligible(), !SpaceConfigurationSafety.hasPendingReferenceCleanup(space) else { return false }
        do {
            let members = try membership()
            let protected = try SceneConfigurationStore.protectedRestoreIdentities(
                data: context.sceneRestoreReceipts, scope: scope, generation: context.generation)
            guard protected.isEmpty else { return false }
            let plan = try SceneConfigurationStore.membershipCleanup(scope: scope, current: members.identities,
                occupiedAddresses: members.occupied, protected: protected)
            guard plan.hasWork else { return true }
            let timestamp = space.lastUpdate
            let revision = SpacePageRevision()
            guard let original = await space.export(purpose: .cleanupInspection), eligible(), revision.isCurrent,
                  await SpaceConfigurationSafety.verifySyncCleanupBaseline(space, local: original), eligible(),
                  space.lastUpdate == timestamp, try membership() == members,
                  let latest = try? SpaceConfigurationSafety.recoveryState(space),
                  latest.sceneRestoreReceipts == context.sceneRestoreReceipts,
                  try SceneConfigurationStore.membershipCleanup(scope: scope, current: members.identities,
                    occupiedAddresses: members.occupied, protected: protected) == plan,
                  !SpaceConfigurationSafety.hasPendingReferenceCleanup(space),
                  SpaceConfigurationSafety.beginSyncReferenceCleanup(space, payload: original) else { return false }
            // No suspension after the journal starts. Once persisted, both
            // success and interrupted finalization remain queued after leaving UI.
            defer {
                if site.spaces.isEmpty { site.spaces = SpaceData.load(siteId: site.id) }
                if let index = site.spaces.firstIndex(where: { $0.id == space.id }) { site.spaces[index] = space }
                space.enqueueSpaceSync(site: site, level: .slow)
            }
            do {
                try SceneConfigurationStore.commitMembershipCleanup(plan) {
                    guard space.lastUpdate < Int64.max, (space.lastUploadCloudTimestamp ?? 0) < Int64.max else {
                        throw SceneConfigurationStore.Failure.persistence
                    }
                    space.lastUpdate = max(Int64(Date().timeIntervalSince1970), space.lastUpdate + 1,
                                           (space.lastUploadCloudTimestamp ?? 0) + 1)
                    guard space.save() else { throw SceneConfigurationStore.Failure.persistence }
                }
            } catch {
                // The App savepoint rolled back its version together with rows.
                space.lastUpdate = SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate ?? timestamp
                throw error
            }
            _ = try SceneConfigurationStore().finishMembershipDeletions(scope: scope)
            let remaining = try SceneConfigurationStore.membershipCleanup(scope: scope, current: members.identities,
                occupiedAddresses: members.occupied, protected: protected)
            guard !remaining.hasWork else { throw SceneConfigurationStore.Failure.persistence }
            space.refreshSummaryCountsFromSpaceMesh()
            guard space.save(), SpaceConfigurationSafety.finishSyncReferenceCleanup(space, changed: true) else {
                throw SceneConfigurationStore.Failure.persistence
            }
            return true
        } catch {
            #if DEBUG
            print("[SceneMembershipCleanup] result=deferred reason=\(error)")
            #endif
            return false
        }
    }
}

/// 场景列表刷新通知名称
let scenesRefreshNotificationName = "scenesRefreshNotificationName"
/// 场景数据更新通知名称
let sceneDataUpdateNotificationName = "scenesDataUpdateNotificationName"
/// 场景图标
var sceneImageNames: [String] = {
    var imageNames: [String] = []
    for id in 1...30 {
        imageNames.append("scene_image_\(id)")
    }
    return imageNames
}()

class ScenesViewController: UIViewController {
    
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    
    let space: SpaceData
    /// 底部
    private var footerView: SpaceFunctionFooterView!
    // 编辑
    private var editView: UIView!
    private var doneBtn: UIButton!
    /// 是否需要更新数据源
    private var refreshData: Bool = true
    private var renderedRevision: SpacePageRevision?
    private var isPageVisible = false
    private var isSelectedPage = false
    private var membershipRevision: SpacePageRevision?
    private var membershipTask: _Concurrency.Task<Void, Never>?
    private var membershipPreparationRequested = false
    
    private var isEdit: Bool = false
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    private var scenes: [Scene] = []
    private var visibleScenes: [Scene] {
        Scene.sortedForDisplay(MeshNetworkManager.instance.scenes.filter { !DeviceEmerFireData.reservedSceneNumbers.contains($0.number) })
    }

    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        
        view.backgroundColor = Background_Color
        setupUI()
//        updateUI()
        addNotification()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        isPageVisible = true
        if refreshData || renderedRevision?.isCurrent != true {
            updateUI()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        prepareMembershipIfNeeded()
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        isPageVisible = false
        membershipTask?.cancel()
    }

    /// WMPageController preloads neighbours. Only didEnter grants selection.
    func setScenePageSelected(_ selected: Bool) {
        isSelectedPage = selected
        if selected { prepareMembershipIfNeeded() }
        else { membershipTask?.cancel() }
    }

    private func prepareMembershipIfNeeded() {
        guard isSelectedPage, isPageVisible, viewIfLoaded?.window != nil else { return }
        if membershipTask != nil { membershipPreparationRequested = true; return }
        guard membershipRevision?.isCurrent != true else { return }
        membershipPreparationRequested = false
        collectionView.isUserInteractionEnabled = false
        footerView.isUserInteractionEnabled = false
        membershipTask = _Concurrency.Task { @MainActor [weak self] in
            guard let self else { return }
            let succeeded = await ScenePageMembershipCleanup.prepare(space: self.space) { [weak self] in
                self?.isSelectedPage == true && self?.isPageVisible == true
            }
            self.membershipTask = nil
            self.collectionView.isUserInteractionEnabled = true
            self.footerView.isUserInteractionEnabled = true
            self.refreshVisibleUI()
            if succeeded { self.membershipRevision = SpacePageRevision() }
            // A completion/import notification received during an await gets one
            // new attempt. Failure alone never starts a retry loop.
            if self.membershipPreparationRequested {
                self.membershipPreparationRequested = false
                self.prepareMembershipIfNeeded()
            }
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
//        updateScenesEmptyUI()
    }
    
    /// 添加通知监听
    private func addNotification() {
        
        NotificationCenter.default.addObserver(forName: .init(scenesRefreshNotificationName), object: nil, queue: .main) {[weak self] _ in
            guard let self = self else { return }
            if self.isPageVisible && self.viewIfLoaded?.window != nil {
                self.refreshVisibleUI()
            }else {
                self.refreshData = true
            }
            self.space.sceneCount = self.visibleScenes.count
            self.space.save()
        }
        
        NotificationCenter.default.addObserver(forName: .init(sceneDataUpdateNotificationName), object: nil, queue: .main) { [weak self] notification in
            guard let self = self, let scene = notification.object as? Scene else {
                return
            }
            self.reloadCollectionItem(scene: scene)
        }
        
        // space编辑权限变更回调
        NotificationCenter.default.addObserver(forName: .init(spacePermissionChangedNotificaitonName), object: nil, queue: .main) {[weak self] notification in
            guard let self = self else { return }
            if let changed = notification.object as? SpaceData,
               changed.id != self.space.id || changed.siteId != self.space.siteId { return }
            self.refreshVisibleUI()
            self.prepareMembershipIfNeeded()
        }
        
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < scenes.count {
            let scene = scenes[indexPath.item]
            let sceneVc = SceneViewController(space: space, scene: scene)
            if isIPad {
                sceneVc.preferredContentSize = iPadPreferredContentSize
            }
            let navVc = NavigationViewController(rootViewController: sceneVc)
            present(navVc, animated: true)
            
//            let groupVc = GroupViewController(space: space, group: group)
//            groupVc.groupDeleteCallback = {[weak self] _ in
//                self?.refreshData = true
//            }
//            groupVc.groupUpdateCallback = {[weak self] _ in
//                self?.refreshData = true
////                self?.updateUI()
//            }
//            let navVc = NavigationViewController(rootViewController: groupVc)
//            present(navVc, animated: true)
        }
    }
    
    private func deleteScene(scene: Scene) {
        let submit = { [weak self] in
            guard let self else { return }
            do {
                let completed = try SceneServer.requestDeletion(scene: scene)
                self.updateUI()
                if completed { XWHUDManager.showSuccessTipHUD("done!".localizedString) }
                else if MeshLibManager.manager.isMeshNetworkConnected { self.pushToSyncDevicesVc(scene: scene) }
                else { XWHUDManager.showTipHUD("scene_deletion_pending".localizedString, isLineFeed: true) }
            } catch { XWHUDManager.showErrorTipHUD("scene_delete_failed".localizedString) }
        }
        if scene.info.configuration?.isDeleting == true { submit(); return }
        SRAlertView(title: "notification".localizedString, message: SceneDeletionCascade.confirmationMessage(scene: scene),
                    messageFont: FONTS(15), actions: [.cancelAction,
                    SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: { _ in submit() })]).show()
    }

    /// 跳到同步数据页面
    private func pushToSyncDevicesVc(scene: Scene) {
        
        let vc = SyncDevicesViewController(type: .scene(scene))
        vc.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            do {
                guard try SceneServer.completePreparedDeletion(scene: scene) else {
                    XWHUDManager.showTipHUD("scene_deletion_pending".localizedString, isLineFeed: true); return
                }
                self.updateUI()
                self.dismiss(animated: true)
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
            } catch { XWHUDManager.showErrorTipHUD("scene_delete_failed".localizedString) }
        }
        vc.backActionCallback = {[weak self] _ in
//                self?.dismiss(animated: true)
            guard let self = self else { return }
            self.dismiss(animated: true)
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
        
    }
    
    /// 编辑完成
    @objc private func doneBtnAction() {
        isEdit = false
        updateUI()
    }
    
    /// 刷新UI
    private func refreshVisibleUI() {
        refreshData = true
        guard isPageVisible, viewIfLoaded?.window != nil else { return }
        updateUI()
    }

    private func updateUI() {
        guard isViewLoaded else { refreshData = true; return }
        defer { refreshData = false; renderedRevision = SpacePageRevision() }
        
        let scenes = visibleScenes
        self.scenes = scenes
        if isEdit && scenes.isEmpty {
            isEdit = false
        }
        
        if isEdit {
            editView.isHidden = false
            footerView.isHidden = true
        }else {
            editView.isHidden = true
            footerView.isHidden = false
        }
        footerView.sortBtn.isHidden = true
        footerView.countBtn.setTitle("\(scenes.count)", for: .normal)
        
        footerView.editBtn.isEnabled = space.sceneOperates.contains(.edit)
        footerView.addBtn.isEnabled = space.sceneOperates.contains(.add)
        
        if self.space.sceneCount != scenes.count {
            self.space.sceneCount = scenes.count
            self.space.save()
        }
        
        updateScenesEmptyUI()
        
        collectionView.reloadData()
    }
  
    /// 更新空页面UI
    private func updateScenesEmptyUI() {
        
        if scenes.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }
//            collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString)
//            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            collectionView.showEmptyDataView(imageName: "scene_empty", title: "no_scenes".localizedString, tipText: "no_scenes_message".localizedString, margin: SCRXFrom(20))
            if let emptyView = collectionView.emptyView {
                
                if isIPad {
                    
                    emptyView.contentView.snp.remakeConstraints({ make in
                        make.centerX.equalToSuperview()
                        make.centerY.equalToSuperview().offset(SCRYFit(-60))
                        make.width.equalToSuperview().multipliedBy(0.7)
                    })
                    emptyView.imageView.snp.remakeConstraints { make in
                        make.top.equalToSuperview()
                        make.centerX.equalToSuperview()
                        make.left.equalTo(SCRXFrom(-4))
                        make.right.equalTo(SCRXFrom(4))
                        make.height.equalTo(emptyView.imageView.snp.width).multipliedBy(288.0 / 343)
                    }
                    
                }else {
                    
                    emptyView.contentView.snp.remakeConstraints({ make in
                        make.top.equalTo(SCRYFrom(39))
                        make.left.equalTo(SCRXFrom(20))
                        make.right.equalTo(-SCRXFrom(20))
                    })
                    emptyView.imageView.snp.remakeConstraints { make in
                        make.top.equalToSuperview()
                        make.centerX.equalToSuperview()
                        make.left.equalTo(SCRXFrom(-4))
                        make.right.equalTo(SCRXFrom(4))
                        make.height.equalTo(emptyView.snp.width).multipliedBy(288.0 / 343)
                    }
                }
                emptyView.titleLabel.font = FONTS(SCRYFrom(15))
                emptyView.titleLabel.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.imageView.snp.bottom).offset(SCRYFrom(24))
                }
                emptyView.tipLabel.font = UIFont.systemFont(ofSize: 15, weight: .light)
                emptyView.tipLabel.lineBreakMode = .byCharWrapping
                
            }
            
            
            footerView.editBtn.isHidden = true
        }else {
            collectionView.hideEmptyDataView()

            footerView.editBtn.isHidden = false
        }
    }
    
    private func reloadCollectionItem(scene: Scene) {
        guard !DeviceEmerFireData.reservedSceneNumbers.contains(scene.number) else {
            return
        }
        let latestScenes = visibleScenes
        guard isPageVisible, viewIfLoaded?.window != nil else {
            refreshData = true
            scenes = latestScenes
            return
        }
        guard let oldIndex = scenes.firstIndex(where: { $0.number == scene.number }),
              let newIndex = latestScenes.firstIndex(where: { $0.number == scene.number }),
              oldIndex == newIndex,
              scenes.count == latestScenes.count,
              collectionView.numberOfSections > 0,
              collectionView.numberOfItems(inSection: 0) == scenes.count,
              oldIndex < collectionView.numberOfItems(inSection: 0) else {
            updateUI()
            return
        }
        scenes = latestScenes
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: [IndexPath(row: oldIndex, section: 0)])
        CATransaction.commit()
//            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? GroupsViewCell {
//                item. = group
//            }
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        editView = UIView()
        editView.backgroundColor = .white
        editView.isHidden = true
        view.addSubview(editView)
        editView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(44))
        }
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(doneBtnAction))
        editView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(44))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = columnNum
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRXFrom(16), left: SCRXFrom(12), bottom: SCRXFrom(16), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: collectionViewMargin, left: collectionViewMargin, bottom: collectionViewMargin + 10, right: collectionViewMargin)
        collectionView.register(ScenesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.showsVerticalScrollIndicator = true
        collectionView.alwaysBounceVertical = true
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(footerView.snp.top)
        }
    }


}

extension ScenesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return scenes.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ScenesViewCell
        guard indexPath.item < scenes.count else {
            return cell
        }
        let scene = scenes[indexPath.item]
        cell.scene = scene
        cell.deleteBtn.isHidden = !isEdit
        cell.deleteActionCallback = {[weak self] in
            self?.deleteScene(scene: scene)
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * CGFloat(columnNum - 1) - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(columnNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        guard indexPath.item < scenes.count else {
            return
        }
        let scene = scenes[indexPath.item]
        guard !isEdit, space.sceneOperates.contains(.control) else { return }
        guard let cell = collectionView.cellForItem(at: indexPath) as? ScenesViewCell, !cell.isExecuting else { return }
        do {
            let handles = try SceneCommandBuilder.recallHandles(scene: scene)
            if !handles.isEmpty && !MeshLibManager.manager.isMeshNetworkConnected {
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                return
            }
            for handle in handles {
                if let model = handle.model { MeshAPI.sendMessage(message: handle.message, model: model) }
                else if let address = handle.address { MeshAPI.sendMessage(message: handle.message, address: address) }
            }
            SceneCommandBuilder.applyRecallFeedback(scene: scene)
            cell.showExecuteAnimation()
        } catch SceneCommandBuilder.RecallFailure.emergency {
            XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
        } catch {
            XWHUDManager.showTipHUD("scene_unavailable".localizedString, isLineFeed: true)
        }
    }
    
}

private extension ScenesViewController {
    func showEmergencyControlBlockedIfNeeded(groups: [Group]) -> Bool {
        guard EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: groups) else {
            return false
        }
        XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
        return true
    }
}

extension ScenesViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        

        
        let vc = SceneAddViewController(space: space)
        vc.createSceneCallback = {[weak self] _ in
            guard let self = self else { return }
            self.updateUI()
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
        isEdit = editing
        view.isEditing = false
        updateUI()
    }
}
