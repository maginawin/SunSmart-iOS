//
//  DeviceOthersViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/24.
//

import UIKit
import NordicSigMeshSDK

let deviceOthersRefreshNotificationName = "switchsRefreshNotification"

private enum DeviceOthersListItem {
    case dongle(DeviceDongleData)
    case emergencyFireController(DeviceEmerFireData)
}

class DeviceOthersViewController: UIViewController, DeviceProtocol {

    // 设备列表
    private var flowLayout: AlignCenterFlowLayout!
    private var collectionView: UICollectionView!

    private var footerView: SpaceFunctionFooterView!
    private var editView: UIView!
    private var doneBtn: UIButton!
    /// 是否正在编辑
    private var isEdit: Bool = false
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    let space: SpaceData
    private var showItems: [DeviceOthersListItem] = []
    
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
        
        addNotificationObserver()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
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
        NotificationCenter.default.addObserver(forName: .init(deviceOthersRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }
        }
        NotificationCenter.default.addObserver(forName: .deviceEmerFireDataDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }
        }
        NotificationCenter.default.addObserver(forName: .linkedEmerFireConfigDidChange, object: nil, queue: nil) { [weak self] _ in
            guard let self = self else { return }
            if self.view.window != nil {
                self.updateUI()
            }
        }
        NotificationCenter.default.addObserver(forName: .init(deviceStateUpdateNotificationName), object: nil, queue: .main) { [weak self] notification in
            guard let self,
                  self.view.window != nil,
                  let node = notification.object as? Node else {
                return
            }
            self.reloadEmergencyFireItem(for: node)
        }
    }

    private func reloadShowItems() {
        let dongleItems = MeshNetworkManager.instance.dongles.map { DeviceOthersListItem.dongle($0) }
        let emerFireDevices = DeviceEmerFireStore.shared.devices(in: space)
        let emergencyItems = emerFireDevices.map { DeviceOthersListItem.emergencyFireController($0) }
        showItems = dongleItems + emergencyItems
    }

    private func reloadEmergencyFireItem(for node: Node) {
        guard let index = showItems.firstIndex(where: { item in
            guard case .emergencyFireController(let device) = item else {
                return false
            }
            return device.bindNodeAddress == node.primaryUnicastAddress
        }) else {
            return
        }

        let indexPath = IndexPath(item: index, section: 0)
        if let cell = collectionView.cellForItem(at: indexPath) as? EmerFireAlarmDeviceCell,
           case .emergencyFireController(let device) = showItems[index] {
            cell.configCell(device: device, editing: isEdit)
        } else {
            collectionView.reloadItems(at: [indexPath])
        }
    }

    private func updateUI() {
        reloadShowItems()
        footerView.countBtn.setTitle("\(MeshNetworkManager.instance.realNodes.count)/\(space.maxDevicesCount)", for: .normal)
//        if !space.deviceOperates.contains(.add) {
//            footerView.addBtn.isEnabled = false
//        }
//        if !space.deviceOperates.contains(.edit) {
//            footerView.editBtn.isEnabled = false
//        }
        footerView.addBtn.isEnabled = space.deviceOperates.contains(.add)
        footerView.editBtn.isEnabled = space.deviceOperates.contains(.edit)
        footerView.sortBtn.isHidden = true
        editView.isHidden = !isEdit
        footerView.isHidden = isEdit
        
        updateDevicesEmptyUI()
        self.collectionView.reloadData()
    }
    
    private func updateDevicesEmptyUI() {
        if showItems.isEmpty {
            if collectionView.frame.isEmpty {
                view.layoutIfNeeded()
            }
            collectionView.showEmptyDataView(title: "no_others".localizedString, tipText: "no_others_message".localizedString, position: .center, bottomMargin: SCRYFit(30))
            collectionView.emptyView?.titleLabel.font = Font_Medium_Size(SCRYFrom(14))
            
            footerView.editBtn.isEnabled = false
        }else {
//            headerView.isHidden = false
            collectionView.hideEmptyDataView()
            footerView.editBtn.isEnabled = !isEdit
        }
    }

    private func makeLinkedEmerFireConfig(from device: DeviceEmerFireData) -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceId: device.id,
            spaceId: device.spaceId,
            meshUUID: device.meshUUID,
            meshNetworkId: device.meshNetworkId,
            deviceName: device.name,
            isSynced: device.isSynced,
            controllerSelfSyncPending: device.controllerSelfSyncPending,
            reportToGateway: device.reportToGateway,
            publishGroupAddress: device.publishGroupAddress,
            configuration: device.configuration
        )
    }

    private func openEmergencyFireEdit(for device: DeviceEmerFireData) {
        guard space.deviceOperates.contains(.edit) else {
            XWHUDManager.showTipHUD("no_permission".localizedString, isLineFeed: true)
            return
        }
        let config = makeLinkedEmerFireConfig(from: device)
        let vc = LinkedEmerFireEditVC(config: config, space: space)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }

    private func confirmDeleteDongle(_ dongle: DeviceDongleData) {
        SRAlertView(title: "notification".localizedString, message: "device_delete_message".localizedString, actions: [
            .cancelAction,
            SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                self?.deleteDongle(dongle)
            })
        ]).show()
    }

    private func deleteDongle(_ dongle: DeviceDongleData) {
        guard let node = dongle.bindNode else {
            MeshNetworkManager.instance.deleteDongle(dongleData: dongle)
            finishDeleteOthersItem()
            return
        }
        deleteNodes(nodes: [node]) { [weak self] successNodes, _ in
            guard successNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) else {
                return
            }
            MeshNetworkManager.instance.deleteDongle(dongleData: dongle)
            self?.finishDeleteOthersItem()
        }
    }

    private func confirmDeleteEmergencyFireController(_ device: DeviceEmerFireData) {
        confirmDeleteEmergencyFireControllerDeviceOrVirtual(
            device,
            space: space,
            presentsSyncModally: true,
            preferredContentSize: isIPad ? iPadPreferredContentSize : nil
        ) { [weak self] in
            self?.finishDeleteOthersItem()
        }
    }

    private func finishDeleteOthersItem() {
        space.commitLocalChangeForCloudSync(changeType: .network(type: .address))
        reloadShowItems()
        if showItems.isEmpty {
            isEdit = false
        }
        updateUI()
        NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(devicesUpdateNotificationName), object: nil)
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.editBtn.isEnabled = false
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
        flowLayout.sectionInset = UIEdgeInsets(top: 0, left: 0, bottom: collectionViewMargin, right: 0)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(50 + (isIPad ? 22 : 10)), left: collectionViewMargin, bottom: 0, right: collectionViewMargin)
        collectionView.backgroundColor = Background_Color
        collectionView.register(DeviceOthersCollectionViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(EmerFireAlarmDeviceCell.self, forCellWithReuseIdentifier: "emerFireCell")
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
            //            make.bottom.equalToSuperview()
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

    @objc private func doneBtnAction() {
        isEdit = false
        updateUI()
    }
    
    /// 长按事件，跳转到 Others 设备详情或 EFC 编辑页
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < showItems.count else {
            return
        }
        switch showItems[indexPath.item] {
        case .dongle(let dongle):
            let vc = DeviceDongleViewController(space: self.space, dongleData: dongle)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .emergencyFireController(let device):
            openEmergencyFireEdit(for: device)
        }
    }
    

}

extension DeviceOthersViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return showItems.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch showItems[indexPath.row] {
        case .dongle(let dongle):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DeviceOthersCollectionViewCell
            cell.dongle = dongle
            cell.deleteBtn.isHidden = !isEdit
            cell.deleteActionCallback = { [weak self] dongle in
                self?.confirmDeleteDongle(dongle)
            }
            return cell
        case .emergencyFireController(let device):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emerFireCell", for: indexPath) as! EmerFireAlarmDeviceCell
            cell.configCell(device: device, editing: isEdit)
            cell.deleteActionCallback = { [weak self] device in
                self?.confirmDeleteEmergencyFireController(device)
            }
            return cell
        }
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
        switch showItems[indexPath.item] {
        case .dongle(let dongle):
            let vc = DeviceDongleViewController(space: self.space, dongleData: dongle)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .emergencyFireController(let device):
            if device.displayStatus == .syncIssueDevice {
                openEmergencyFireEdit(for: device)
                return
            }
            let config = makeLinkedEmerFireConfig(from: device)
            let vc = EmerFireAlarmMonitorVC(space: space, device: device, config: config)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
    }
    
    
}

extension DeviceOthersViewController: SpaceFunctionFooterViewDelegate {
    
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

extension DeviceOthersViewController: MeshLibManagerMessageDelegate {

    func meshNetworkManager(_ manager: MeshNetworkManager, deviceDataUpdate node: Node) {
        guard view.window != nil else {
            return
        }
        reloadEmergencyFireItem(for: node)
    }
}
