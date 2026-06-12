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
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    /// 底部
    private var footerView: SpaceFunctionFooterView!
    /// 刷新
    private var refreshControl: UIRefreshControl!
    
//    private var switches: [DeviceSwitchData] = []
    
    /// 是否正在编辑
    private var isEdit: Bool = false
    
    let space: SpaceData

    private var canEditSwitches: Bool {
        space.deviceOperates.contains(.edit)
    }

    private var canDeleteSwitches: Bool {
        space.deviceOperates.contains(.delete)
    }

    private var acPowerSwitchNodes: [Node] {
        var addressSet: Set<Address> = []
        return MeshNetworkManager.instance.switchs.compactMap { switchData in
            guard let node = switchData.proxyNode, node.isACPowerSwitch else {
                return nil
            }
            guard !addressSet.contains(node.primaryUnicastAddress) else {
                return nil
            }
            addressSet.insert(node.primaryUnicastAddress)
            return node
        }
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
        setupCollectionView()
        
        addNotificationObserver()
        
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        updateUI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        MeshLibManager.manager.messageDelegate = self
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
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

        // 设备状态更新通知
        NotificationCenter.default.addObserver(forName: .init(deviceStateUpdateNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self, let node = notification.object as? Node else { return }
            self.reloadSwitchItem(node: node)
        }
    }

    private func setupCollectionView() {
        
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.enableTestDelete = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = itemMargin
        flowLayout.minimumInteritemSpacing = itemMargin
        flowLayout.itemRowCount = columnNum
//        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
//        flowLayout.offsetY = flowLayout.sectionInset.top
//        UIEdgeInsets(top: 0, left: SCRXFrom(12), bottom: <#T##CGFloat#>, right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(40 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: collectionViewMargin, right: collectionViewMargin)
        collectionView.backgroundColor = Background_Color
        collectionView.register(DeviceSwitchesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(PJEightKeySwitchesViewCell.self, forCellWithReuseIdentifier: "eightKeyCell")
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(refreshControlAction), for: .valueChanged)
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

    private func eightKeySwitchData(for switchData: DeviceSwitchData) -> PJEightKeySwitchData? {
        if let eightKeySwitch = switchData as? PJEightKeySwitchData {
            return eightKeySwitch
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: switchData)
    }

    private func isUnlinkedVirtualBatteryPowerSwitch(_ switchData: DeviceSwitchData) -> Bool {
        guard let eightKeySwitch = eightKeySwitchData(for: switchData) else {
            return false
        }
        return eightKeySwitch.proxyNode?.isBatteryPowerSwitch != true
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
            footerView.editBtn.isEnabled = !isEdit && canEditSwitches
        }
    }
    
    private func updateUI() {
        
        if isEdit, !canEditSwitches {
            isEdit = false
        }
        MeshNetworkManager.instance.normalizeInvalidBatteryPowerSwitchProxyLinks()
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.switchs.count)/16", for: .normal)
        updateRefreshControlAvailability()
        
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
        
        footerView.addBtn.isEnabled = space.deviceOperates.contains(.add)
        footerView.editBtn.isEnabled = canEditSwitches
        
        self.updateDevicesEmptyUI()
        
//        if !space.deviceOperates.contains(.add) {
//            footerView.addBtn.isEnabled = false
//        }
//        if !space.deviceOperates.contains(.edit) {
//            footerView.editBtn.isEnabled = false
//        }
//        CATransaction.commit()
        self.collectionView.reloadData()
    }

    private func updateRefreshControlAvailability() {
        if acPowerSwitchNodes.isEmpty {
            if refreshControl.isRefreshing {
                refreshControl.endRefreshing()
            }
            collectionView.refreshControl = nil
        } else {
            collectionView.refreshControl = refreshControl
        }
    }

    @objc private func refreshControlAction() {
        let nodes = acPowerSwitchNodes
        guard MeshLibManager.manager.isMeshNetworkConnected, !nodes.isEmpty else {
            refreshControl.endRefreshing()
            return
        }

        if refreshControl.isRefreshing {
            let duration = max(2, min(Double(nodes.count) * 0.3, 5))
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
                guard let self = self else { return }
                self.refreshControl.endRefreshing()
                self.collectionView.reloadData()
            }
        }

        MeshNodeHeartbeatManager.shared.refresh(nodes: nodes)
    }

    private func reloadSwitchItem(node: Node) {
        guard node.isACPowerSwitch else {
            return
        }

        guard let index = MeshNetworkManager.instance.switchs.firstIndex(where: { switchData in
            guard let eightKeySwitch = eightKeySwitchData(for: switchData),
                  eightKeySwitch.isACPowerSwitch else {
                return false
            }
            return eightKeySwitch.proxyNode?.primaryUnicastAddress == node.primaryUnicastAddress
        }) else {
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        if let cell = collectionView.cellForItem(at: indexPath) as? PJEightKeySwitchesViewCell {
            let switchData = MeshNetworkManager.instance.switchs[index]
            guard let eightKeySwitch = eightKeySwitchData(for: switchData) else {
                return
            }
            cell.configure(with: switchData, eightKeySwitch: eightKeySwitch, editing: isEdit)
        } else {
            collectionView.reloadItems(at: [indexPath])
        }
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
    private func deleteSwitchData(_ switchData: DeviceSwitchData, source: UIViewController?) {

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
        vc.syncSuccessCallback = { [weak self, weak source] _ in
            guard let self else { return }
            if let navigationController = source?.navigationController {
                navigationController.popViewController(animated: true)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self, weak source] in
                    self?.completeConfirmedSwitchDelete(switchData, source: source)
                }
            } else {
                self.dismiss(animated: true) { [weak self] in
                    self?.completeConfirmedSwitchDelete(switchData, source: nil)
                }
            }
        }
        vc.backActionCallback = { [weak self, weak vc] _ in
            guard let vc else { return }
            self?.closeSwitchDeleteSyncController(vc)
        }

        if let source, let navigationController = source.navigationController {
            navigationController.pushViewController(vc, animated: true)
        } else {
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
    }

    private func closeSwitchDeleteSyncController(_ syncController: UIViewController) {
        if let navigationController = syncController.navigationController {
            if navigationController.viewControllers.first === syncController,
               navigationController.presentingViewController != nil {
                navigationController.dismiss(animated: true)
            } else {
                navigationController.popViewController(animated: true)
            }
        } else {
            syncController.dismiss(animated: true)
        }
    }
    
    private func deleteCache(switchData: DeviceSwitchData) {
        MeshNetworkManager.instance.deleteSwitch(switchData: switchData)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        
        if MeshNetworkManager.instance.switchs.isEmpty {
            isEdit = false
        }
        updateUI()
        
    }

    private func completeConfirmedSwitchDelete(_ switchData: DeviceSwitchData, source: UIViewController?) {
        deleteCache(switchData: switchData)

        guard let source else {
            return
        }

        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self, weak source] in
            self?.closeDeletedSwitchSource(source)
        }
    }

    private func closeDeletedSwitchSource(_ source: UIViewController?) {
        guard let source else {
            return
        }

        if let navigationController = source.navigationController,
           navigationController.presentingViewController != nil {
            navigationController.dismiss(animated: true)
        } else {
            source.dismiss(animated: true)
        }
    }

    private func requestDeleteSwitch(_ switchData: DeviceSwitchData) {
        guard canDeleteSwitches else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }

        if let eightKeySwitch = eightKeySwitchData(for: switchData) {
            SRAlertView(
                title: "notification".localizedString,
                message: eightKeySwitch.powerSwitchKind.deleteConfirmationMessage,
                actions: [
                    .cancelAction,
                    SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                        guard let self else { return }
                        if self.isUnlinkedVirtualBatteryPowerSwitch(switchData) {
                            self.deleteCache(switchData: switchData)
                            XWHUDManager.showSuccessTipHUD("done!".localizedString)
                        } else {
                            self.deleteConfirmedSwitch(switchData)
                        }
                    })
                ]
            ).show()
            return
        }

        SRAlertView(title: "notification".localizedString, message: "switchs_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
            self?.deleteConfirmedSwitch(switchData)
        })]).show()
    }

    private func deleteConfirmedSwitch(_ switchData: DeviceSwitchData, source: UIViewController? = nil) {
        guard canDeleteSwitches else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }

        guard !switchData.getNeedSyncDatas(deleteSwitch: true).isEmpty() else {
            completeConfirmedSwitchDelete(switchData, source: source)
            return
        }
        deleteSwitchData(switchData, source: source)
    }
    
    /// 长按事件，跳转到开关详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        if let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < MeshNetworkManager.instance.switchs.count {
            let switche = MeshNetworkManager.instance.switchs[indexPath.item]
            if let eightKeySwitch = eightKeySwitchData(for: switche) {
                guard space.deviceOperates.contains(.edit) else {
                    XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
                    return
                }
                let vc = PJPreAddEightKeySwitchesVC(space: space, switchData: eightKeySwitch)
                vc.editable = space.deviceOperates.contains(.edit)
                vc.deleteSwitchAction = { [weak self] switchData, source in
                    guard let self else { return }
                    self.deleteConfirmedSwitch(switchData, source: source)
                }
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                present(NavigationViewController(rootViewController: vc), animated: true)
                return
            }
            let vc = DeviceSwitchViewController(space: self.space,switchData: switche)
            vc.editable = space.deviceOperates.contains(.edit)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
    }
}


extension DeviceSwitchesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return MeshNetworkManager.instance.switchs.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
   
        let switche = MeshNetworkManager.instance.switchs[indexPath.item]
        let deleteAction: (DeviceSwitchData) -> Void = { [weak self] switche in
            guard let self = self else { return }
            self.requestDeleteSwitch(switche)
        }

        if let eightKeySwitch = eightKeySwitchData(for: switche) {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "eightKeyCell", for: indexPath) as! PJEightKeySwitchesViewCell
            cell.configure(with: switche, eightKeySwitch: eightKeySwitch, editing: isEdit)
            cell.deleteActionCallback = deleteAction
            return cell
        }

        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DeviceSwitchesViewCell
        cell.switche = switche
        cell.deleteBtn.isHidden = !isEdit
        cell.deleteActionCallback = deleteAction
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.sectionInset.left - flowLayout.sectionInset.right - flowLayout.minimumInteritemSpacing * CGFloat(columnNum - 1)) / CGFloat(columnNum)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW, height: itemW)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard !isEdit else {
            return
        }
        let switche = MeshNetworkManager.instance.switchs[indexPath.item]
        if let eightKeySwitch = eightKeySwitchData(for: switche) {
            let vc = PJEightKeySwitchMonitorVC(space: space, switchData: eightKeySwitch)
            vc.deleteSwitchAction = { [weak self] switchData, source in
                guard let self else { return }
                self.deleteConfirmedSwitch(switchData, source: source)
            }
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
            return
        }
        let vc = DeviceSwitchViewController(space: self.space,switchData: switche)
        vc.editable = space.deviceOperates.contains(.edit)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
}

extension DeviceSwitchesViewController: SpaceFunctionFooterViewDelegate {
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
        guard space.deviceOperates.contains(.add) else {
            return
        }

        let point = CGPoint(x: view.addBtn.center.x, y: SCREEN_HEIGHT - footerView.height)
        (self.parent as? DevicesViewController)?.addAction(point: point)
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
        guard canEditSwitches else {
            view.isEditing = false
            return
        }

        view.isEditing = false
        isEdit = editing
        updateUI()
    }
}

extension DeviceSwitchesViewController: MeshLibManagerMessageDelegate {

    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        if view.window != nil {
            reloadSwitchItem(node: node)
        }
    }
}
