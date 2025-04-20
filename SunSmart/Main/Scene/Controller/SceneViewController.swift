//
//  SceneViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/25.
//

import UIKit
import NordicSigMeshSDK


class SceneViewController: UIViewController {

    private var titleLabel: UILabel!
    private var collectionView: UICollectionView!
    private var flowLayout: AlignCenterFlowLayout!
    private var pageControl: UIPageControl!
    /// 是否需要更新数据源
    private var refreshData: Bool = false
    
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
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        if space.sceneOperates.contains(.edit) {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))
        }
        setupUI()
        
//        for i in 1...30 {
//            devices.append("ID \(i)")
//        }
        
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
        
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing * CGFloat(rowNum - 1) - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / CGFloat(rowNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        let itemSize = CGSize(width: itemW, height: itemW + SCRYFrom(16))
        flowLayout.itemSize = itemSize
        
        collectionView.snp.updateConstraints { make in
            let height = itemSize.height * CGFloat(columnNum) + flowLayout.minimumLineSpacing * CGFloat(columnNum - 1) + collectionView.contentInset.top + collectionView.contentInset.bottom + flowLayout.sectionInset.top + flowLayout.sectionInset.bottom
//            ceil(height)
//            height = CGFloat(ceil(Float(height) * 100) / 100.0)
            make.height.equalTo(ceil(height))
        }
        collectionView.layoutIfNeeded()
        updateUI()
    }
    
    /// 添加通知监听
    private func addNotification() {
        
        NotificationCenter.default.addObserver(forName: .init(sceneDataUpdateNotificationName), object: nil, queue: nil) {[weak self] _ in
            self?.titleLabel.text = self?.scene.name
            if self?.view.window != nil {
                self?.updateUI()
            }else {
                self?.refreshData = true
            }
        }
        
        NotificationCenter.default.addObserver(forName: .init(groupsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            if self?.view.window != nil {
                self?.collectionView.reloadData()
                self?.updateEmptyUI()
            }else {
                self?.refreshData = true
            }
        }
        
        NotificationCenter.default.addObserver(forName: .init(groupDataUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self, let group = notification.object as? Group else { return }
//            CATransaction.setDisableActions(true)
            if let index = self.scene.info.groups.firstIndex(of: group), let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? SceneGroupsViewCell {
                let data = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == self.scene.number })
                item.updateData(group: group, sceneData: data != nil ? .init(data: data!) : nil)
            }else {
                collectionView.reloadData()
            }
//            CATransaction.commit()
        }
        
    }
    
    
    private func updateUI() {
        collectionView.reloadData()
        updateEmptyUI()
        pageControl.numberOfPages = Int(ceil(Double(scene.info.groups.count) / Double(columnNum * rowNum)))
    }
    
    @objc private func close() {
        dismiss(animated: true)
    }
    
    @objc private func moreClick() {
        
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
            self.scene.name = name
            self.scene.info.imageId = imageId + 1
            self.scene.save()
            self.scene.info.save()
            self.titleLabel.text = name
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
            if !MeshLibManager.manager.isMeshNetworkConnected && self.scene.info.groups.contains(where: { $0.nodes.count > 0 }) { // 未连接mesh网络
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                return
            }
            
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
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            SceneServer.deleteScene(scene: self.scene, success: nil, failed: nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                NotificationCenter.default.post(name: .init(scenesRefreshNotificationName), object: nil)
                self.close()
            }
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
        
        let vc = SceneSettingsViewController(space: space, scene: scene)
        
//        let vc = GroupMembersViewController(space: space, group: group)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < scene.info.groups.count {
            
            let group = scene.info.groups[indexPath.item]
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
        
        if scene.info.groups.isEmpty {
            collectionView.showEmptyDataView(title: "No Members!", position: .center, bottomMargin: 3.5)
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
        collectionView.showsHorizontalScrollIndicator = false
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
    }

}

extension SceneViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
//        return 9
        return scene.info.groups.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SceneGroupsViewCell
        let group = scene.info.groups[indexPath.item]
        let data = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number })
        cell.updateData(group: group, sceneData: data != nil ? .init(data: data!) : nil)
        // 获取组是否需要同步
        if scene.needSyncGroups.contains(group) {
            cell.iconImageView.image = UIImage(named: "sync_failed")
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let group = scene.info.groups[indexPath.item]
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
        
        group.isOn = !group.isOn
        MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
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
