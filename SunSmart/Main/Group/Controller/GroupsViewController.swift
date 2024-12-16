//
//  GroupsViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit
import NordicSigMeshSDK

/// 组列表刷新通知
let groupsRefreshNotificationName = "groupsRefreshNotification"
/// 组状态刷新通知
let groupDataUpdateNotificationName = "groupDataUpdateNotification"

class GroupsViewController: UIViewController {

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
        
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.groups.count)/16", for: .normal)
        
        addNotificationObserver()
        
  
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateUI()
//        if refreshData {
//            refreshData = false
//            collectionView.reloadData()
//            updateGroupesEmptyUI()
//        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        updateGroupesEmptyUI()
    }

    
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(groupsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
//            self?.refreshData = true
            guard let self = self else { return }
            self.updateUI()
        }
        
        NotificationCenter.default.addObserver(forName: .init(groupDataUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            if let group = notification.object as? Group {
                self?.reloadCollectionItem(group: group)
            }
        }
        
        // space编辑权限变更回调
        NotificationCenter.default.addObserver(forName: .init(spacePermissionChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            self.updateUI()
        }
        
    }
    
    /// 长按事件，跳转到组详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < MeshNetworkManager.instance.groups.count {
            let group = MeshNetworkManager.instance.groups[indexPath.item]
            
            let groupVc = GroupViewController(space: space, group: group)
//            groupVc.groupDeleteCallback = {[weak self] _ in
//    //            self?.refreshData = true
//                self?.collectionView.reloadData()
//            }
//            groupVc.groupUpdateCallback = {[weak self] _ in
//    //            self?.refreshData = true
//                self?.collectionView.reloadData()
//                self?.updateGroupesEmptyUI()
//            }
            let navVc = NavigationViewController(rootViewController: groupVc)
            
            present(navVc, animated: true)
        }
    }
    
    private func deleteGroup(group: Group) {
        
        SRAlertView(title: "notification".localizedString, message: "group_delete_message".localizedString, messageFont: FONTS(15), actions: [.cancelAction, SRAlertAction(title: "DELETE".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
         
            guard group.nodes.isEmpty || MeshLibManager.manager.isMeshNetworkConnected else {
                XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
                return
            }
            
            guard group.nodes.isEmpty || group.nodes.contains(where: { $0.state }) else { // 是否有设备在线
                SRAlertView(title: "notification".localizedString, message: "group_delete_offline".localizedString, actions:[SRAlertAction(title: "confirm".localizedString, actionHandler: nil)]).show()
                return
            }
            
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
//            group.nodes.forEach({ node in
//                node.unsubscribe(from: group)
//                node.sceneDatas.removeAll()
//                // 删除设备场景数据
//                SceneExecuteData.deleteData(meshUUID: self.space.meshUUID, address: node.primaryUnicastAddress)
//                // 删除设备关联组的日程数据
//                group.info.bindSchedules.forEach{ schedule in
//                    Node.deleteSchedule(meshUUID: self.space.meshUUID, address: node.primaryUnicastAddress, scheduleId: schedule.id)
//                }
//            })
//            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5, execute: {
            let exitsNode: Bool = group.nodes.count > 0
                GroupServer.deleteGroup(group: group, progress: nil) {[weak self] _ in
                    XWHUDManager.hide()
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    self?.updateUI()
                    // 通知space数据修改
                    let type: SpaceChangeDataType = exitsNode ? .device : .common
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: type)
//                    MeshNetworkManager.instance.scenes.forEach({
//                        if let index = $0.info.groups.firstIndex(of: group) {
//                            $0.info.groups.remove(at: index)
//                        }
//                    })
                    
                } failed: {[weak self] _ in
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD("group_delete_failed".localizedString)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        XWHUDManager.hide()
                        // 跳转到检查页面
                        self?.deleteFailedCheck(group: group)
                    }
                }
//            })
            
        })]).show()
    }

    /// 删除失败检查设备
    private func deleteFailedCheck(group: Group) {
        
        let vc = SyncDevicesViewController(type: .group(group, outNodes: group.nodes))
        vc.syncSuccessCallback = {[weak self] _ in
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            guard let self = self else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.dismiss(animated: true)
            }
            GroupServer.deleteGroup(group: group, progress: nil, successful: nil, failed: nil)
            self.updateUI()
        }
        vc.backActionCallback = { [weak self] in
            self?.dismiss(animated: true)
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
//        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 编辑完成
    @objc private func doneBtnAction() {
        isEdit = false
        updateUI()
    }
    
    /// 刷新UI
    private func updateUI() {
        
        let groups = MeshNetworkManager.instance.groups
        self.footerView.countBtn.setTitle("\(groups.count)/16", for: .normal)
        if self.space.groupCount != groups.count {
            self.space.groupCount = groups.count
            self.space.save()
        }
        self.updateGroupesEmptyUI()
        if isEdit && groups.isEmpty {
            isEdit = false
        }
        if isEdit {
            editView.isHidden = false
            footerView.isHidden = true
        }else {
            editView.isHidden = true
            footerView.isHidden = false
        }
        
        footerView.addBtn.isEnabled = space.groupOperates.contains(.add)
        footerView.editBtn.isEnabled = space.groupOperates.contains(.edit)
        
//        if !space.groupOperates.contains(.edit) {
//            footerView.editBtn.isEnabled = false
//        }
//        if !space.groupOperates.contains(.add) {
//            footerView.addBtn.isEnabled = false
//        }
        
        footerView.sortBtn.isHidden = true
        collectionView.reloadData()
    }
  
    /// 更新空页面UI
    private func updateGroupesEmptyUI() {
        
        if MeshNetworkManager.instance.groups.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }

//            collectionView.showEmptyDataView(title: "no_devices".localizedString, tipText: "no_devices_message".localizedString)
//            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            collectionView.showEmptyDataView(imageName: "group_empty", title: "no_groups".localizedString, tipText: "no_groups_message".localizedString, margin: SCRXFrom(20))
            if let emptyView = collectionView.emptyView {
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
    
    private func reloadCollectionItem(group: Group) {
        if let index = MeshNetworkManager.instance.groups.firstIndex(where: {$0.address.address == group.address.address}) {
            //            CATransaction.setDisableActions(true)
            //            collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
            if let item = collectionView.cellForItem(at: IndexPath(item: index, section: 0)) as? GroupsViewCell {
                item.group = group
            }
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
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
//        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: 0, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: 0, right: SCRXFrom(12))
        collectionView.register(GroupsViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
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

extension GroupsViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    public func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MeshNetworkManager.instance.groups.count
    }
    
    public func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! GroupsViewCell
        let group = MeshNetworkManager.instance.groups[indexPath.item]
        cell.group = group
        cell.deleteBtn.isHidden = !isEdit
        cell.deleteActionCallback = {[weak self] in
            self?.deleteGroup(group: group)
        }
        return cell
    }
    
    public func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        
        var itemW = (collectionView.frame.size.width - flowLayout.minimumLineSpacing * 2.0 - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right) / 3.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100)
        return CGSizeMake(itemW, itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let group = MeshNetworkManager.instance.groups[indexPath.item]
 
        group.isOn = !group.isOn
        if group.nodes.count > 0 {
            // 修改缓存数据
            group.nodes.forEach({
                $0.isOn = group.isOn
                if !$0.isOn, $0.lightness > 0 { // 关灯，记录关灯前的亮度值
                    $0.trunOffLightness = $0.lightness
                }
            })
            MeshAPI.setGroupOnOffState(address: group.address.address, isOn: group.isOn)
        }
        reloadCollectionItem(group: group)
    }
    
}

extension GroupsViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        guard MeshNetworkManager.instance.groups.count < 16 else { return }
        
        let vc = GroupAddViewController(space: space)
//        vc.doneCallback = {[weak self] group in
//            guard let self = self else { return }
//            self.collectionView.reloadData()
//            self.space.groupCount = self.space.groups.count
//            self.space.save()
//        }
//        vc.isModalInPresentation = true
        let navVc = NavigationViewController(rootViewController: vc)
        
        present(navVc, animated: true)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
        isEdit = editing
        view.isEditing = false
        updateUI()
    }
}

