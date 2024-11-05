//
//  DeviceSwitchesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/5.
//

import UIKit
import NordicSigMeshSDK

/// 开关列表刷新通知
let switchsRefreshNotificationName = "switchsRefreshNotification"

class DeviceSwitchesViewController: UIViewController {

    // 设备列表
    private var flowLayout: AlignCenterFlowLayout!
    private var collectionView: UICollectionView!
    // 编辑
    private var editView: UIView!
    private var doneBtn: UIButton!
    
    /// 底部
    private var footerView: SpaceFunctionFooterView!
    
//    private var switches: [DeviceSwitchData] = []
    
    /// 是否正在编辑
    private var isEdit: Bool = false
    
    let space: SpaceData

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
        setupCollectionView()
        
        addNotificationObserver()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        updateUI()
    }
    
    
    private func addNotificationObserver() {
        NotificationCenter.default.addObserver(forName: .init(switchsRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            //            self?.refreshData = true
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }
        }
        
        // space编辑权限变更回调
        NotificationCenter.default.addObserver(forName: .init(spacePermissionChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            self.updateUI()
        }
    }

    private func setupCollectionView() {
        
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
//        flowLayout.offsetY = flowLayout.sectionInset.top
//        UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: <#T##CGFloat#>, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
        collectionView.backgroundColor = Background_Color
        collectionView.register(DeviceSwitchesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(collectionLongPressAction))
        longPress.minimumPressDuration = 0.5
        collectionView.addGestureRecognizer(longPress)
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.top.right.equalToSuperview()
//            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(footerView.snp.top)
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
        
    }
    
    private func updateDevicesEmptyUI() {
        
        footerView.sortBtn.isHidden = true
        
        if MeshNetworkManager.instance.switchs.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }

            collectionView.showEmptyDataView(title: "no_switches".localizedString, tipText: "no_switches_message".localizedString, position: .center, bottomMargin: SCRYFit(30))
            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            footerView.editBtn.isEnabled = false
        }else {
//            headerView.isHidden = false
            collectionView.hideEmptyDataView()
            footerView.editBtn.isEnabled = !isEdit
        }
    }
    
    private func updateUI() {
        
        self.updateDevicesEmptyUI()
        
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.switchs.count)/16", for: .normal)
        
        var inset = self.collectionView.contentInset
        inset.bottom = SCRYFrom(16)
        if isEdit {
            self.editView.isHidden = false
            footerView.isHidden = true
        }else {
            self.editView.isHidden = true
//            self.settingBtn.isEnabled = true
            footerView.isHidden = false
        }
        
        if !space.deviceOperates.contains(.add) {
            footerView.addBtn.isEnabled = false
        }
        if !space.deviceOperates.contains(.edit) {
            footerView.editBtn.isEnabled = false
        }
//        CATransaction.commit()
        self.collectionView.reloadData()
    }
    
    /// 点击编辑事件
//    func footerView(_ footerView: SpaceFunctionFooterView, didEditAction edit: Bool) {
//        footerView.isEditing = false
//        isEdit = true
//        updateUI()
//    }
    
    @objc private func doneBtnAction() {
        
        self.isEdit = false
        updateUI()
    }
    
    /// 删除动能开关
    private func deleteSwitchData(_ switchData: DeviceSwitchData) {

        guard MeshLibManager.manager.isMeshNetworkConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        
        // 删除开关先将组解除订阅
//        switchData.bindGroupAddresses.forEach { address in
//            if !switchData.unbindGroupAddresses.contains(address) {
//                switchData.unbindGroupAddresses.append(address)
//            }
//        }
//        switchData.save()
        
        let vc = SyncDevicesViewController(type: .enOceanSwitch(switchData, deleteSwitch: true))
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            self.dismiss(animated: true)
            self.deleteCache(switchData: switchData)
        }
        vc.backActionCallback = {[weak self] in
            guard let self = self else { return }
            self.dismiss(animated: true)
            if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
                self.collectionView.reloadItems(at: [IndexPath(item: index, section: 0)])
            }
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    private func deleteCache(switchData: DeviceSwitchData) {
        let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id })
        MeshNetworkManager.instance.deleteSwitch(switchData: switchData)
        if index != nil {
            collectionView.deleteItems(at: [IndexPath(item: index!, section: 0)])
        }else {
            collectionView.reloadData()
        }
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        
        if MeshNetworkManager.instance.switchs.isEmpty {
            isEdit = false
            updateUI()
        }
        
    }
    
    /// 长按事件，跳转到开关详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < MeshNetworkManager.instance.switchs.count {
            let switche = MeshNetworkManager.instance.switchs[indexPath.item]
            let vc = DeviceSwitchViewController(space: self.space,switchData: switche)
            vc.editable = space.deviceOperates.contains(.edit)
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
    }
}


extension DeviceSwitchesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MeshNetworkManager.instance.switchs.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
   
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DeviceSwitchesViewCell
        let switche = MeshNetworkManager.instance.switchs[indexPath.item]
        cell.switche = switche
        cell.deleteBtn.isHidden = !isEdit
        // 删除
        cell.deleteActionCallback = {[weak self] switche in
            guard let self = self else { return }
            
            SRAlertView(title: "notification".localizedString, message: "switchs_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: {[weak self] _ in
                
                // 是否已绑定开关
                guard !switche.getNeedSyncDatas(deleteSwitch: true).isEmpty() else {
                    // 空数据直接删除
                    self?.deleteCache(switchData: switche)
                    return
                }
                self?.deleteSwitchData(switche)
            })]).show()
//            self.updateEditUI()
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * CGFloat(2)) / CGFloat(3)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isEdit else {
            return
        }
        let switche = MeshNetworkManager.instance.switchs[indexPath.item]
        let vc = DeviceSwitchViewController(space: self.space,switchData: switche)
        vc.editable = space.deviceOperates.contains(.edit)
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
}

extension DeviceSwitchesViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        let point = CGPoint(x: view.addBtn.center.x, y: SCREEN_HEIGHT - footerView.height)
        (self.parent as? DevicesViewController)?.addAction(point: point)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
        view.isEditing = false
        isEdit = true
        updateUI()
    }
}
