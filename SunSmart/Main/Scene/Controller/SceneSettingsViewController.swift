//
//  SceneSettingsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/26.
//

import UIKit
import NordicSigMeshSDK

class SceneSettingsViewController: UIViewController {

    /// 模式
    enum Mode {
        /// 设置
        case settings
        /// 成员（创建场景后添加组）
        case members
    }
    
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    
    private var bottomView: UIView!
    private var syncBtn: UIButton!
    private var previewBtn: UIButton!
    
    let space: SpaceData
    let scene: Scene
    
    let mode: Mode
//    /// 场景更新回调
    var sceneUpdateCallback: ((Scene)->Void)?
//    /// 场景删除回调
//    var sceneDeleteCallback: ((Scene)->Void)?
    /// 选择的组
//    private var selectGroups: [Group] = []
    
    /// 列数
//    private var columnNum: Int = isIPad ? 4 : 3
    private var rowNum: Int = isIPad ? 5 : 3
    /// collectionview边距
    private var collectionViewInsets: UIEdgeInsets = isIPad ? UIEdgeInsets(top: 0, left: SCRXFrom(30), bottom: 0, right: SCRXFrom(30)) : UIEdgeInsets(top: 0, left: SCRXFrom(15), bottom: 0, right: SCRXFrom(15))
    
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(20) : SCRXFrom(13)
    
    init(space: SpaceData, scene: Scene, mode: Mode = .settings) {
        self.space = space
        self.scene = scene
        self.mode = mode
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        setupUI()
        
        
        MeshNetworkManager.instance.groups.forEach({
            if scene.info.groups.contains($0) {
                $0.isSelected = true
                if let data = $0.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                    $0.executeSceneData = .init(data: data)
                }
//                    .first(where: { $0.key == scene.number })
            }else {
                $0.isSelected = false
                $0.executeSceneData = nil
            }
        })
        
        if mode == .members {
            title = "settings".localizedString
            navigationItem.leftBarButtonItem = UIBarButtonItem()
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "done".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(doneAction))
            bottomView.isHidden = true
        }else {
            
            title = "settings".localizedString
            navigationItem.rightBarButtonItem = UIBarButtonItem(title: "save".localizedString, color: RGB(0, 0, 0, 0.85), font: UIFont.systemFont(ofSize: 16, weight: .light), target: self, sel: #selector(saveAction))
//            selectGroups = scene.info.groups
            scene.info.groups.forEach({
//                if let group = space.groups.first(where: { $0.add })
                $0.isSelected = true
                if let sceneData = $0.info.sceneExecuteDatas.first(where: { scene.number == $0.sceneNumber }) {
                    $0.executeSceneData = .init(data: sceneData)
                }
            })
        }
        
        addNotificationObserver()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if mode == .settings {
            syncBtn.isHidden = scene.needSyncGroups.isEmpty
            collectionView.reloadData()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateEmptyUI()
    }
    
    deinit {
        if self.mode == .members && self.space.isConfiguring { // 未创建场景退出页面，停止引导配置流程
            self.space.isConfiguring = false
        }
    }
    
    /// 添加组/编辑通知监听
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(groupsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
//            self?.refreshData = true
            guard let self = self else { return }
            self.updateEmptyUI()
            self.collectionView.reloadData()
        }
        
    }
    
    private func addSuccessHandle() {
        
        NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
        
//        let spaceVc = UIViewController.getVisibleVc()?.presentingViewController
        if self.space.isConfiguring { // && spaceVc?.isKind(of: SpaceViewController.classForCoder()) ?? false // 在引导配置流程中 
            dismiss(animated: false)
            // 跳转到连续创建页面
            let vc = SpaceNewCreationProcessController(space: space, options: .scene)
            NotificationCenter.default.post(name: .init(spaceModalViewControllerNotificaitonName), object: NavigationViewController(rootViewController: vc))
//            spaceVc?.present(NavigationViewController(rootViewController: vc), animated: true)
        }else {
            dismiss(animated: true)
        }
        
    }
    
    /// 完成（添加成员模式）
    @objc private func doneAction() {
        
        // 获取已选择的组
        let selectGroups = MeshNetworkManager.instance.groups.filter({ $0.isSelected && $0.executeSceneData != nil })
        // 有设备的组
        let existNodeGroups = selectGroups.filter({ $0.nodes.count > 0 })
        // 网络未连接
        if existNodeGroups.count > 0 && !MeshLibManager.manager.isMeshNetworkConnected {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        selectGroups.forEach({
            let executeSceneData = $0.executeSceneData!
            let isOn = executeSceneData.isOn
            let lightness = isOn ? Node.getLightness(lightness100: executeSceneData.lightness) : 0
            let cct = $0.clampEffectiveCct(UInt16(executeSceneData.cct))
            if let data = $0.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                data.isOn = isOn
                data.lightness = lightness
                data.cct = cct
            }else {
                $0.info.sceneExecuteDatas.append(SceneExecuteData(sceneNumber: scene.number, isOn: isOn, lightness: lightness, cct: cct))
            }
            $0.info.save()
            $0.updateGroupSyncState()
//            scene.info.groups.sort(by: { $0.address.address < $1.address.address })
        })
        
        if existNodeGroups.isEmpty { // 都是空组
//            scene.info.groups = selectGroups
//            dismiss(animated: true)
            addSuccessHandle()
            
        }else { // 去同步
            
            let vc = SyncDevicesViewController(type: .scene(scene))
            vc.syncSuccessCallback = {[weak self] _ in
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                guard let self = self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
//                    self.dismiss(animated: true)
                    self?.addSuccessHandle()
                }
            }
            vc.backActionCallback = {[weak self] _ in
//                self?.dismiss(animated: true)
                self?.addSuccessHandle()
            }
            navigationController?.pushViewController(vc, animated: true)
        }
        
    }
    
    /// 保存（设置模式）
    @objc private func saveAction() {
        
        // 获取已选择的组
        let selectGroups = MeshNetworkManager.instance.groups.filter({ $0.isSelected && $0.executeSceneData != nil })
        // 有设备的组
//        let existNodeGroups = selectGroups.filter({ $0.nodes.count > 0 })
       
        // 获取新增的组
        let addGroups = selectGroups.filter({ !scene.info.groups.contains($0) })
//        scene.info.groups.filter({ selectGroups.contains($0) })
        // 删除的组
        let deleteGroups = scene.info.groups.filter({ !selectGroups.contains($0) })
        
        // 修改数据的组
        let updateGroups = selectGroups.filter({ group in
            
            guard let oldData = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) else {
                return true
            }
            if scene.info.groups.contains(group), let newData = group.executeSceneData {
                return newData.isOn != oldData.isOn || newData.lightness != Node.getLightness100(lightness: oldData.lightness) || newData.cct != oldData.cct
            }
            return false
        })
        // 组是否存在设备
        let existNodes = addGroups.contains(where: { $0.nodes.count > 0 }) || deleteGroups.contains(where: { $0.nodes.count > 0 }) || updateGroups.contains(where: { $0.nodes.count > 0 })
        
        guard MeshLibManager.manager.isMeshNetworkConnected || !existNodes else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        // 需要同步的节点
        var syncNodes: [Node] = []
        
        addGroups.forEach({
//            scene.info.groups.append($0)
//            scene.info.groups.sort(by: { $0.address.address < $1.address.address })
            let isOn = $0.executeSceneData!.isOn
            let lightness = isOn ? Node.getLightness(lightness100: $0.executeSceneData!.lightness) : 0
            let cct = $0.clampEffectiveCct(UInt16($0.executeSceneData!.cct))
            $0.info.sceneExecuteDatas.append(SceneExecuteData(sceneNumber: scene.number, isOn: isOn, lightness: lightness, cct: cct))
            $0.info.save()
            syncNodes.append(contentsOf: $0.getNeedSyncDataNodes(scene: scene).syncNodes)
            $0.updateGroupSyncState()
        })
        
        updateGroups.forEach({
            if let data = $0.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                data.isOn = $0.executeSceneData!.isOn
                data.lightness = data.isOn ? Node.getLightness(lightness100: $0.executeSceneData!.lightness) : 0
                data.cct = $0.clampEffectiveCct(UInt16($0.executeSceneData!.cct))
                $0.info.save()
                $0.updateGroupSyncState()
            }
            syncNodes.append(contentsOf: $0.getNeedSyncDataNodes(scene: scene).syncNodes)
        })
        
        deleteGroups.forEach({
            var deleteNodes: [Node] = []
            // 同步过场景则去同步删除设备场景
            if let sceneData = $0.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                sceneData.state = .waitDelete
                // 判断组内是否有设备同步过该场景
                deleteNodes = $0.getNeedSyncDataNodes(scene: scene).deleteNodes
                if deleteNodes.isEmpty {
                    $0.info.sceneExecuteDatas.removeAll(where: { $0.sceneNumber == sceneData.sceneNumber })
                }
                $0.info.save()
                $0.updateGroupSyncState()
            }
            // 未同步则直接删除组场景
//            if deleteNodes.isEmpty {
//                if let index = scene.info.groups.firstIndex(of: $0) {
//                    scene.info.groups.remove(at: index)
//                }
//                SceneExecuteData.deleteData(meshUUID: space.meshUUID, address: $0.address.address, sceneId: Int(scene.number))
//            }
            syncNodes.append(contentsOf: deleteNodes)
            
        })
        
        // 未编辑
        if addGroups.isEmpty && deleteGroups.isEmpty && updateGroups.isEmpty {
            navigationController?.popViewController(animated: true)
            return
        }
        
        if syncNodes.isEmpty { // 都是空组/无设备操作
//            scene.info.groups = selectGroups
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: scene)
            // 通知space数据修改
            NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }else {
            
            let vc = SyncDevicesViewController(type: .scene(scene))
            vc.syncSuccessCallback = {[weak self] _ in
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                guard let self = self else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: self.scene)
                    self.navigationController?.popToRootViewController(animated: true)
                }
            }
            vc.backActionCallback = {[weak self] _ in
//                self?.dismiss(animated: true)
                guard let self = self else { return }
                NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: self.scene)
                self.navigationController?.popToRootViewController(animated: true)
            }
            navigationController?.pushViewController(vc, animated: true)
        }
    }
    
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < MeshNetworkManager.instance.groups.count {
            
            let group = MeshNetworkManager.instance.groups[indexPath.item]
//            let data = group.info.bindSceneDatas.first(where: { $0.sceneId == scene.number })?.data
            updateGroupSceneExecuteData(group: group)
        }
        
    }
    
    /// 同步
    @objc private func syncBtnAction() {

        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        let vc = SyncDevicesViewController(type: .scene(scene), reSync: true)
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: self.scene)
                self.dismiss(animated: true)
            }
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            NotificationCenter.default.post(name: .init(sceneDataUpdateNotificationName), object: self.scene)
            self.dismiss(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
    @objc private func previewBtnTouchDown(sender: UIButton) {
//        sender.isHighlighted = true
        sender.setImage(UIImage(named: "scene_preview")?.withTintColor(RGB(155, 155, 155)), for: .normal)
        sender.setTitleColor(RGB(155, 155, 155), for: .normal)
    }
    
    @objc private func previewBtnTouchEnd(sender: UIButton) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            sender.setImage(UIImage(named: "scene_preview"), for: .normal)
            sender.setTitleColor(TextBlack_Color, for: .normal)
        }
    }
    
    /// 预览
    @objc private func previewBtnAction(sender: UIButton) {
      
        previewBtnTouchEnd(sender: sender)
        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        // 有设备的组
        let controlGroups = MeshNetworkManager.instance.groups.filter({ $0.isSelected && $0.nodes.count > 0 })
        guard !showEmergencyControlBlockedIfNeeded(groups: controlGroups) else {
            return
        }
        controlGroups.forEach({
            if let data = $0.executeSceneData {
                previewSceneData(data, for: $0)
            }
        })
        
    }
    
    private func previewSceneData(_ data: ExecuteSceneData, for group: Group) {
        guard group.nodes.count > 0 else { return }
        guard data.isOn else {
            MeshAPI.setGroupOnOffState(address: group.address.address, isOn: false)
            return
        }
        // 判断组内是否有色温灯
        let effectiveCctCount = group.nodes.filter({ $0.effectiveSupportCct }).count
        if effectiveCctCount > 0 {
            MeshAPI.setGroupCTLState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness), temperature: group.clampEffectiveCct(UInt16(data.cct)))
        }
        // 判断组内是否有仅支持调光灯
        if effectiveCctCount < group.lightnessNodes.count {
            MeshAPI.setGroupLightnessState(address: group.address.address, lightness: Node.getLightness(lightness100: data.lightness))
        }
    }
    
    /// 创建组
    private func addGroup() {
        
        let vc = GroupAddViewController(space: space)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 更新组的场景参数
    private func updateGroupSceneExecuteData(group: Group) {
        
        let data = group.executeSceneData
//        group.info.bindSceneDatas.first(where: { $0.sceneId == scene.number })?.data
        let groupLightData = group.info.profile.lightControlData
        let isOn = data?.isOn ?? true
        let initialLightness = isOn ? (data?.lightness ?? 100) : 0
        SceneExecuteDataPickerView.show(lightness: initialLightness, isOn: isOn, cct: data?.cct ?? 4500, lightnessLimitRange: 0...groupLightData.highEndTrim, cctRange: group.effectiveCctRange, showCct: group.effectiveSupportCct, showDelete: false) {[weak self] isOn, lightness, cct in
            guard let self = self else { return }
            let cct = Int(group.clampEffectiveCct(UInt16(cct)))
            if let sceneData = data { // 修改
                sceneData.isOn = isOn
                sceneData.lightness = isOn ? lightness : 0
                sceneData.cct = cct
            }else { // 新增
                group.executeSceneData = ExecuteSceneData(isOn: isOn, lightness: lightness, cct: cct)
//                SceneExecuteData(lightness: lightness, cct: cct)
//                group.info.bindSceneDatas.append((self.scene.number, SceneExecuteData(lightness: lightness, cct: cct)))
            }
            group.isSelected = true
//            if !self.selectGroups.contains(group) {
//                self.selectGroups.append(group)
//            }
            if let index = MeshNetworkManager.instance.groups.firstIndex(of: group) {
                CATransaction.setDisableActions(true)
                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
                CATransaction.commit()
            }else {
                self.collectionView.reloadData()
            }
        }
        
    }
    
    private func updateEmptyUI() {
        
        if MeshNetworkManager.instance.groups.isEmpty {
            view.showEmptyDataView(title: "no_groups".localizedString, tipText: "scene_not_groups_message".localizedString, buttonText: "create_group".localizedString, buttomWidth: SCRXFrom(216), position: .center, bottomMargin: SCRYFit(50), btnClickBack: {[weak self] in
                self?.addGroup()
            })
            
            if let emptyView = view.emptyView {
                emptyView.tipLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
                emptyView.tipLabel.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(16))
                }
                
                emptyView.button.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
                emptyView.button.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(78))
                }
            }
            bottomView.isHidden = true
            
        }else {
            view.hideEmptyDataView()
            if mode == .settings {
                bottomView.isHidden = false
            }
        }
        
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFrom(44))
        }
        
        syncBtn = UIButton(title: "sync".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(30, 35, 41), normalImageName: "scene_sync", target: self, action: #selector(syncBtnAction))
        syncBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        bottomView.addSubview(syncBtn)
        syncBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(5))
        }
        
        previewBtn = UIButton(title: "preview".localizedString, titleSize: 14, titleWeight: .light, titleColor: RGB(30, 35, 41), normalImageName: "scene_preview", target: self, action: #selector(previewBtnAction))
        previewBtn.addTarget(self, action: #selector(previewBtnTouchDown), for: .touchDown)
        previewBtn.addTarget(self, action: #selector(previewBtnTouchEnd), for: .touchCancel)
        previewBtn.addTarget(self, action: #selector(previewBtnTouchEnd), for: .touchUpOutside)
        previewBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        bottomView.addSubview(previewBtn)
        previewBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(5))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = rowNum
//        flowLayout.itmeColCount = columnNum
//        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: 0, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = collectionViewInsets
        collectionView.register(SceneMembersViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = .clear
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
     
        
    }


}

extension SceneSettingsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
   
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MeshNetworkManager.instance.groups.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SceneMembersViewCell
        let group = MeshNetworkManager.instance.groups[indexPath.item]
        cell.updateData(group: group, sceneData: group.executeSceneData)
        if group.isSelected {
            cell.selectBtn.isSelected = true
            cell.progressView.isHidden = false
        }else {
            cell.selectBtn.isSelected = false
            cell.progressView.isHidden = true
        }
        // 获取组是否需要同步
        if scene.needSyncGroups.contains(group) {
            cell.iconImageView.image = UIImage(named: "sync_failed")
        }
        
        cell.selectActionCallBack = {[weak self] isSelected in
            guard let self = self else { return }
            group.isSelected = isSelected
            if isSelected {
//                self.selectGroups.append(group)
                self.updateGroupSceneExecuteData(group: group)
//                cell.progressView.isHidden = false
            }else {
//                self.selectGroups.removeAll(where: { $0.address.address == group.address.address })
                group.executeSceneData = nil
                cell.progressView.isHidden = true
            }
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * CGFloat(rowNum - 1) - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(rowNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW + SCRYFrom(16))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
           
        let group = MeshNetworkManager.instance.groups[indexPath.item]
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
        CATransaction.setDisableActions(true)
        collectionView.reloadItems(at: [indexPath])
        CATransaction.commit()
        if group.nodes.count > 0 {
            MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
        }
        
    }
    
}

private extension SceneSettingsViewController {
    func showEmergencyControlBlockedIfNeeded(group: Group) -> Bool {
        showEmergencyControlBlockedIfNeeded(groups: [group])
    }

    func showEmergencyControlBlockedIfNeeded(groups: [Group]) -> Bool {
        guard EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: groups) else {
            return false
        }
        XWHUDManager.showTipHUD("Uncontrollable in emergency situations".localizedString, isLineFeed: true)
        return true
    }
}

private extension Group {
    
    static var executeSceneDataKey: UInt8 = 0
    
    static var isSelectedKey: UInt8 = 0
    
    /// 赋值的场景数据
    var executeSceneData: ExecuteSceneData? {
        get {
            objc_getAssociatedObject(self, &Group.executeSceneDataKey) as? ExecuteSceneData
        }set {
            objc_setAssociatedObject(self, &Group.executeSceneDataKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否选中
    var isSelected: Bool {
        get {
            objc_getAssociatedObject(self, &Group.isSelectedKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Group.isSelectedKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}
