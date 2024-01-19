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
        updateUI()
        addNotification()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if refreshData {
            refreshData = false
            updateUI()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
//        updateScenesEmptyUI()
    }
    
    /// 添加通知监听
    private func addNotification() {
        
        NotificationCenter.default.addObserver(forName: .init(scenesRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            if self?.view.window != nil {
                self?.updateUI()
            }else {
                self?.refreshData = true
            }
        }
        
        NotificationCenter.default.addObserver(forName: .init(sceneDataUpdateNotificationName), object: nil, queue: nil) { [weak self] notification in
            guard let self = self, let scene = notification.object as? Scene else {
                return
            }
            self.reloadCollectionItem(scene: scene)
        }
        
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < space.scenes.count {
            let scene = space.scenes[indexPath.item]
            let sceneVc = SceneViewController(space: space, scene: scene)
            
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
        
        SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, messageFont: FONTS(15), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 存在设备并且网络未连接
//            if scene.nodes.count > 0 && !MeshLibManager.manager.isMeshNetworkConnected {
//                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
//                return
//            }

            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            // 测试数据
//            scene.nodes.forEach({
//                scene.remove(node: $0)
//            })
//            scene.delete()
            SceneServer.deleteScene(scene: scene) {[weak self] _ in
                XWHUDManager.hide()
                XWHUDManager.showSuccessTipHUD("done!".localizedString)
                self?.updateUI()
                
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
        vc.backActionCallback = {[weak self] in
//                self?.dismiss(animated: true)
            guard let self = self else { return }
            self.dismiss(animated: true)
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
        
        if isEdit && space.scenes.isEmpty {
            isEdit = false
        }
        
        if isEdit {
            editView.isHidden = false
            footerView.isHidden = true
        }else {
            editView.isHidden = true
            footerView.isHidden = false
        }
        footerView.countBtn.setTitle("\(space.scenes.count)/16", for: .normal)
        
        updateScenesEmptyUI()
        
        collectionView.reloadData()
    }
  
    /// 更新空页面UI
    private func updateScenesEmptyUI() {
        
        if space.scenes.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }
//            collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString)
//            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            collectionView.showEmptyDataView(imageName: "scene_empty", title: "no_scenes".localizedString, tipText: nil)
            if let emptyView = collectionView.emptyView {
                emptyView.contentView.snp.remakeConstraints({ make in
                    make.top.equalTo(SCRYFrom(39))
                    make.left.equalTo(SCRXFrom(20))
                    make.right.equalTo(-SCRXFrom(20))
                })
                emptyView.imageView.snp.remakeConstraints { make in
                    make.top.equalToSuperview()
                    make.centerX.equalToSuperview()
                    make.left.equalTo(SCRXFrom(-11))
                    make.right.equalTo(SCRXFrom(11))
                    make.height.equalTo(emptyView.snp.width).multipliedBy(298.0 / 353)
                }
                emptyView.titleLabel.snp.updateConstraints { make in
                    make.top.equalTo(emptyView.imageView.snp.bottom).offset(SCRYFrom(9))
                }
                
                let attStr = NSAttributedString(string: "no_scenes_message".localizedString)
                emptyView.tipLabel.attributedText = attStr
            }
            
            
            footerView.editBtn.isHidden = true
        }else {
            collectionView.hideEmptyDataView()

            footerView.editBtn.isHidden = false
        }
    }
    
    private func reloadCollectionItem(scene: Scene) {
        if let index = space.scenes.firstIndex(where: {$0.number == scene.number}) {
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
        
        doneBtn = UIButton(title: "done".localizedString, titleSize: 16, titleColor: Title_Color, target: self, action: #selector(doneBtnAction))
        editView.addSubview(doneBtn)
        doneBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRXFrom(16), left: SCRXFrom(12), bottom: SCRXFrom(16), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRXFrom(16), left: SCRXFrom(12), bottom: SCRXFrom(16), right: SCRXFrom(12))
        collectionView.register(GroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
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
        return space.scenes.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupsViewCell
        let scene = space.scenes[indexPath.item]
        let imageIndex = max(min(scene.info.imageId, sceneImageNames.count) - 1, 0)
        cell.imageView.image = UIImage(named: sceneImageNames[imageIndex]) //device_light_offline
        cell.nameLabel.text = scene.info.name ?? scene.name
        cell.deleteBtn.isHidden = !isEdit
        cell.deleteActionCallback = {[weak self] in
            self?.deleteScene(scene: scene)
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * 2.0 - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let scene = space.scenes[indexPath.item]
        MeshAPI.startScene(sceneNumber: scene.number)
        
        XWHUDManager.showSuccessTipHUD("executed".localizedString)
//        let vc = SyncDevicesViewController(type: .scene(scene))
//        SceneSettingsViewController(space: space, scene: scene, mode: .members)
//        present(NavigationViewController(rootViewController: vc), animated: true)
        
        
    }
    
}

extension ScenesViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        guard self.space.scenes.count < 16 else { return }
        
        let vc = SceneAddViewController(space: space)
        vc.createSceneCallback = {[weak self] _ in
            guard let self = self else { return }
            self.collectionView.reloadData()
            self.space.sceneCount = self.space.scenes.count
            self.space.save()
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

