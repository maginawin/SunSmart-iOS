//
//  DeviceOthersViewController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/24.
//

import UIKit
import NordicSigMeshSDK

let deviceOthersRefreshNotificationName = "switchsRefreshNotification"

class DeviceOthersViewController: UIViewController {

    private enum DeviceOtherItem {
        case dongle(DeviceDongleData)
        case emerFire(DeviceEmerFireData)
    }

    // 设备列表
    private var flowLayout: AlignCenterFlowLayout!
    private var collectionView: UICollectionView!
    
    private var footerView: SpaceFunctionFooterView!
    /// 是否正在编辑
    private var isEdit: Bool = false
    
    /// 列数
    private var columnNum: Int = isIPad ? 6 : 3
    /// collectionview边距
    private var collectionViewMargin: CGFloat = isIPad ? SCRXFrom(24) : SCRXFrom(12)
    /// item间距
    private var itemMargin: CGFloat = isIPad ? SCRXFrom(30) : SCRXFrom(16)
    
    let space: SpaceData
    private var items: [DeviceOtherItem] = []
    
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
    }
    
    private func updateUI() {
        let emerFireDevices = DeviceEmerFireStore.shared.devices(in: space)
        items = MeshNetworkManager.instance.dongles.map { .dongle($0) } + emerFireDevices.map { .emerFire($0) }
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
        
        updateDevicesEmptyUI()
        self.collectionView.reloadData()
    }
    
    private func updateDevicesEmptyUI() {
        if items.isEmpty {
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
            reportToGateway: device.reportToGateway,
            enablePowerLossEmergency: device.enablePowerLossEmergency,
            enableFireAlarmEmergency: device.enableFireAlarmEmergency,
            powerLossGroupIndex: device.powerLossGroupIndex,
            fireAlarmGroupIndex: device.fireAlarmGroupIndex,
            powerLossGroupAddresses: device.powerLossGroupAddresses,
            fireAlarmGroupAddresses: device.fireAlarmGroupAddresses,
            powerLossBrightness: device.powerLossBrightness,
            powerLossResuming: device.powerLossResuming,
            powerLossSendCount: device.powerLossSendCount,
            fireAlarmBrightness: device.fireAlarmBrightness,
            fireAlarmResuming: device.fireAlarmResuming,
            fireAlarmSendCount: device.fireAlarmSendCount
        )
    }
    
    private func setupUI() {
        
        footerView = SpaceFunctionFooterView()
        footerView.sortBtn.isHidden = true
        footerView.editBtn.isEnabled = false
        footerView.enableTestDelete = true
        footerView.delegate = self
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        flowLayout = AlignCenterFlowLayout()
        flowLayout.minimumLineSpacing = SCRXFrom(16)
        flowLayout.minimumInteritemSpacing = SCRXFrom(16)
        flowLayout.sectionInset = UIEdgeInsets(top: SCRYFrom(16) + SCRYFrom(42), left: SCRXFrom(12), bottom: SCRYFrom(16), right: SCRXFrom(12))
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        //        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(16), left: 0, bottom: SCRYFrom(16), right: 0)
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
    }
    
    /// 长按事件，跳转到开关详情
    @objc private func collectionLongPressAction(sender: UIGestureRecognizer) {
        
        guard sender.state == .began, !isEdit else {
            return
        }
        let point = sender.location(in: collectionView)
        guard let indexPath = collectionView.indexPathForItem(at: point), indexPath.item < items.count else {
            return
        }
        switch items[indexPath.item] {
        case .dongle(let dongle):
            let vc = DeviceDongleViewController(space: self.space, dongleData: dongle)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .emerFire(let device):
            let config = makeLinkedEmerFireConfig(from: device)
            let vc = EmerFireAlarmMonitorVC(space: space, device: device, config: config)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        }
    }
    

}

extension DeviceOthersViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return items.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        switch items[indexPath.row] {
        case .dongle(let dongle):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! DeviceOthersCollectionViewCell
            cell.dongle = dongle
            return cell
        case .emerFire(let device):
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "emerFireCell", for: indexPath) as! EmerFireAlarmDeviceCell
            cell.configCell(name: device.name, status: device.displayStatus)
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
        switch items[indexPath.item] {
        case .dongle(let dongle):
            let vc = DeviceDongleViewController(space: self.space, dongleData: dongle)
            if isIPad {
                vc.preferredContentSize = iPadPreferredContentSize
            }
            present(NavigationViewController(rootViewController: vc), animated: true)
        case .emerFire(let device):
            if [.offlineBoundDevice, .repairRequiredDevice].contains(device.displayStatus) {
                let config = makeLinkedEmerFireConfig(from: device)
                let vc = EmerFireAlarmMonitorVC(space: space, device: device, config: config)
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                present(NavigationViewController(rootViewController: vc), animated: true)
                return
            }
            if device.bindNode == nil {
                let config = makeLinkedEmerFireConfig(from: device)
                let vc = LinkedEmerFireEditVC(config: config, isLinkedToRealDevice: false, space: space)
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                present(NavigationViewController(rootViewController: vc), animated: true)
                return
            }
            let vc = PreCreateEmerFireVC(space: space, deviceData: device)
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
