//
//  ScenesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/19.
//

import UIKit
import NordicSigMeshSDK

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
    private var refreshData: Bool = false
    
    private var isEdit: Bool = false
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)

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
        
//        if refreshData {
//            refreshData = false
            updateUI()
//        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
//        updateScenesEmptyUI()
    }
    
    /// 添加通知监听
    private func addNotification() {
        
        NotificationCenter.default.addObserver(forName: .init(scenesRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }else {
                self.refreshData = true
            }
            self.space.sceneCount = MeshNetworkManager.instance.scenes.count
            self.space.save()
        }
        
        NotificationCenter.default.addObserver(forName: .init(sceneDataUpdateNotificationName), object: nil, queue: nil) { [weak self] notification in
            guard let self = self, let scene = notification.object as? Scene else {
                return
            }
            self.reloadCollectionItem(scene: scene)
        }
        
        // space编辑权限变更回调
        NotificationCenter.default.addObserver(forName: .init(spacePermissionChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            self.updateUI()
        }
        
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < MeshNetworkManager.instance.scenes.count {
            let scene = MeshNetworkManager.instance.scenes[indexPath.item]
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
        
        SRAlertView(title: "notification".localizedString, message: "scene_delete_message".localizedString, messageFont: FONTS(15), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 存在设备并且网络未连接
            if scene.nodes.count > 0 && !MeshLibManager.manager.isMeshNetworkConnected {
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                return
            }

            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            // 测试数据
//            scene.nodes.forEach({
//                scene.remove(node: $0)
//            })
//            scene.delete()
            let existNode: Bool = scene.addresses.count > 0
            SceneServer.deleteScene(scene: scene) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.updateUI()
                // 通知space数据修改
                let type: SpaceChangeDataType = existNode ? .device : .common
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: type)
                
            } failed: {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD("scene_delete_failed".localizedString)
                // 跳转同步页面
                if scene.needSyncGroups.count > 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self?.pushToSyncDevicesVc(scene: scene)
                    }
                }
            }
            
        })]).show()
        
    }
    
    /// 跳到同步数据页面
    private func pushToSyncDevicesVc(scene: Scene) {
        
        let vc = SyncDevicesViewController(type: .scene(scene))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5) {
                self.dismiss(animated: true)
            }
            SceneServer.deleteScene(scene: scene, success: nil, failed: nil)
            self.updateUI()
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
    private func updateUI() {
        
        let scenes = MeshNetworkManager.instance.scenes
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
        footerView.countBtn.setTitle("\(scenes.count)/16", for: .normal)
        
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
        
        if MeshNetworkManager.instance.scenes.isEmpty {
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
        if let index = MeshNetworkManager.instance.scenes.firstIndex(where: {$0.number == scene.number}) {
            CATransaction.setDisableActions(true)
            collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
            CATransaction.commit()
//            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? GroupsViewCell {
//                item. = group
//            }
        }
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
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleWeight: .light, titleColor: Title_Color, target: self, action: #selector(doneBtnAction))
        editView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = columnNum
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRXFrom(16), left: SCRXFrom(12), bottom: SCRXFrom(16), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: collectionViewMargin, left: collectionViewMargin, bottom: collectionViewMargin + 10, right: collectionViewMargin)
        collectionView.register(ScenesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.showsVerticalScrollIndicator = false
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
        return MeshNetworkManager.instance.scenes.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ScenesViewCell
        let scene = MeshNetworkManager.instance.scenes[indexPath.item]
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
        
        let scene = MeshNetworkManager.instance.scenes[indexPath.item]
        if scene.nodes.count > 0 && !MeshLibManager.manager.isMeshNetworkConnected {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        if let cell = collectionView.cellForItem(at: indexPath) as? ScenesViewCell, !cell.isExecuting {
            // 执行场景
            
            MeshAPI.startScene(sceneNumber: scene.number)
            
            scene.info.groups.forEach { group in
                if let data = group.info.sceneExecuteDatas.first(where: { scene.number == $0.sceneNumber }) {
                    group.lightness = data.lightness
                    group.cct = Int(data.cct)
                    group.isOn = data.lightness > 0
                }
                
                group.nodes.forEach({
                    if let sceneData = $0.sceneExecuteDatas.first(where: { scene.number == $0.sceneNumber }) {
                        $0.lightness = sceneData.lightness
                        $0.isOn = $0.lightness > 0
                        $0.temperature = UInt16(sceneData.cct)
                    }
                })
            }
            
            cell.showExecuteAnimation()
        }
    }
    
}

extension ScenesViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        guard MeshNetworkManager.instance.scenes.count < 16 else {
            SRAlertView(title: "notification".localizedString, message: "scenes_overrun_message".localizedString, actions: [SRAlertAction(title: "GOT_IT".localizedString)]).show()
            return
        }
        
        let vc = SceneAddViewController(space: space)
        vc.createSceneCallback = {[weak self] _ in
            guard let self = self else { return }
            self.collectionView.reloadData()
            self.space.sceneCount = MeshNetworkManager.instance.scenes.count
            self.space.save()
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

