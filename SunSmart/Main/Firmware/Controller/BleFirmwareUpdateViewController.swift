//
//  BleFirmwareUpdateViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/22.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON
import CoreBluetooth

internal extension Node {
    static var selectedStateKey = 1
    static var updateStateKey = 2
    static var enableUpgradeKey = 3
    static var targetFirmwareDataKey = 4
    static var peripheral = 5
    
    // 是否可以升级 设备版本小于当前升级版本 & 信号量 >= -90dB
    // 是否可以选择 可以升级 & 升级状态为待升级
    // 状态展示 待升级、升级成功、升级失败、不可用
    
    /// 更新状态
    enum UpdateState {
        
        var rawValue: Int {
            switch self {
            case .none:
                return 0
            case .successful:
                return 1
            case .failure:
                return 2
            }
        }
        
        /// 无
        case none
        /// 成功
        case successful
        /// 失败
        case failure(FirmwareUpdateError)
    }
    
    /// 设备选择状态
    enum UpdateSelectedState {
        /// 未选中
        case unselected
        /// 选中
        case selected
        /// 不可选
        case disabled
    }
    
    /// 选择状态
    var selectedState: UpdateSelectedState {
        get {
            objc_getAssociatedObject(self, &Node.selectedStateKey) as? UpdateSelectedState ?? .disabled
        }set {
            objc_setAssociatedObject(self, &Node.selectedStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 是否可以升级
    var enableUpgrade: Bool {
        get {
            objc_getAssociatedObject(self, &Node.enableUpgradeKey) as? Bool ?? false
        }set {
            objc_setAssociatedObject(self, &Node.enableUpgradeKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    
    /// 更新状态
    var updateState: UpdateState {
        get {
            objc_getAssociatedObject(self, &Node.updateStateKey) as? UpdateState ?? .none
        }set {
            objc_setAssociatedObject(self, &Node.updateStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 升级的固件数据
    var targetFirmwareData: FirmwareData? {
        get {
            objc_getAssociatedObject(self, &Node.targetFirmwareDataKey) as? FirmwareData
        }set {
            objc_setAssociatedObject(self, &Node.targetFirmwareDataKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 节点蓝牙设备
    var peripheral: CBPeripheral? {
        get {
            objc_getAssociatedObject(self, &Node.peripheral) as? CBPeripheral
        }set {
            objc_setAssociatedObject(self, &Node.peripheral, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}

internal extension FirmwareUpdateError {
    
    /// 错误标题
    var title: String {
        var localized = ""
        switch self {
        case .connectTimeout:
            localized = "firmware_update_connect_timeout"
        case .deviceNotSupported:
            localized = "firmware_update_notSupport"
        case .noApplicationKey:
            localized = "firmware_update_noBindKey"
        case .noResponse:
            localized = "firmware_update_noResponse"
        case .disconnect:
            localized = "firmware_update_disconnect"
        case .getStateFailure:
            localized = "firmware_update_state_error"
        case .checkFailure:
            localized = "firmware_update_check_error"
        case .startFailure:
            localized = "firmware_update_start_error"
        case .blobFailure:
            localized = "firmware_update_blob_error"
        case .updateFailure:
            localized = "firmware_update_error"
        case .stop:
            localized = "firmware_update_stop"
        case .underway:
            return "firmware_update_underway"
        }
        return localized.localizedString
    }
    
    /// 错误描述
    var message: String {
        var localized = ""
        switch self {
        case .connectTimeout:
            localized = "firmware_update_connect_timeout_message"
        case .deviceNotSupported:
            localized = "firmware_update_notSupport_message"
        case .noApplicationKey:
            localized = "firmware_update_noBindKey_message"
        case .noResponse:
            localized = "firmware_update_noResponse_message"
        case .disconnect:
            localized = "firmware_update_disconnect_message"
        case .getStateFailure:
            localized = "firmware_update_state_error_message"
        case .checkFailure:
            localized = "firmware_update_check_error_message"
        case .startFailure:
            localized = "firmware_update_start_error_message"
        case .blobFailure:
            localized = "firmware_update_blob_error_message"
        case .updateFailure:
            localized = "firmware_update_error_message"
        case .stop:
            localized = "firmware_update_stop_message"
        case .underway:
            localized = "firmware_update_underway_message"
        }
        return localized.localizedString
    }
    
}

class BleFirmwareUpdateViewController: UIViewController {
    
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var bottomView: UIView!
    private var selectAllBtn: UIButton!
    private var selectAllLabel: UILabel!
    private var selectCountLabel: UILabel!
    private var upgradeBtn: UIButton!
    private weak var upgradeView: FirmwareUpdateStateView?
    private var showData: [UInt16: Bool] = [:]
    private var refreshControl: UIRefreshControl!
    private var scanAnimationView: UIImageView!
    
    private var firmwareTypeDatas: [FirmwareUpdateTypeData] = []
    private var selectNodes: [Node] = []
    /// 上一个升级失败的设备list
    private var failedNodes: [Node] = []
    /// 需要恢复的设备list
    private var restoreNodes: [Node] = []
    /// 是否展开恢复数据提示
    private var unfold: Bool = true
    private weak var restoreView: BleFirmwareUpdateRestoreView?
    /// 是否正在刷新设备信号
    private var refreshing: Bool = false
    private var rssiSortTimer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "ota_ble_title".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        
        navigationItem.rightBarButtonItems = [UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(helpAction)), UIBarButtonItem(customView: scanAnimationView)]
        setupUI()
        self.isModalInPresentation = true
//        setupData()
        
        MeshNetworkManager.instance.realNodes.forEach({
            $0.updateState = .none
            $0.selectedState = .unselected
        })
        
        refreshRSSI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        flowLayout.estimatedItemSize = CGSize(width: view.width - SCRXFrom(32), height: SCRYFrom(182))
        
        if firmwareTypeDatas.isEmpty {
            showEmptyUI()
        }
    }
    
    
    /// 获取云端固件
    private func loadCloudFirmwareRequest(type: FirmwareUpdateTypeData) {
        
        NetworkRequest.shared.request(.firmwareLatestVersion(deviceType: type.productId.hex)) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                let data = JSON(response)["data"]
                guard let version = data["version"].string,
                      let companyId = data["manufacturerId"].string,
                      let customId = data["customerId"].string,
                      let url = data["url"].string,
                      var releaseDate = data["releaseDate"].string,
                      let size = data["size"].int,
                      let deviceTypeStr = data["deviceType"].string, let pid = UInt16(hex: deviceTypeStr.replacingOccurrences(of: "0x", with: "")), pid == type.productId else {
                    return
                }
            
                releaseDate = releaseDate.replacingOccurrences(of: "T", with: " ")
                releaseDate = releaseDate.replacingOccurrences(of: "Z", with: "")
                let timeInterval = String.dateConvert(timeStr: releaseDate, dateFormat: nil)
                
                let serverData = FirmwareServerData(productId: pid, version: version.replacingOccurrences(of: "v", with: ""), companyId: UInt16(companyId) ?? CompanyId, customId: UInt16(customId) ?? 0, url: url, filename: data["filename"].stringValue, size: size, releaseDate: timeInterval, content: data["describe"].stringValue)
                type.serverData = serverData
                if let index = firmwareTypeDatas.firstIndex(where: { $0.productId == type.productId }) {
                    self.collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
                }else {
                    self.collectionView.reloadData()
                }
            case .failure(_):
                break
            }
        }
        
    }
    
    /// 刷新信号值
    @objc private func refreshRSSI() {
        guard MeshNetworkManager.instance.realNodes.count > 0 else {
            showEmptyUI()
            return
        }
        self.refreshControl.endRefreshing()
        if self.refreshing {
            return
        }
        
        MeshNetworkManager.instance.realNodes.forEach({
            $0.rssi = nil
            $0.peripheral = nil
        })
        self.setupData(loadServerData: true)
        
        
//        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
//        // 每多50个设备刷新信号时间加多1s
//        let time = ceil(Double(MeshNetworkManager.instance.realNodes.count - 100) / 50.0)
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
            self.perform(#selector(self.refreshNodesRSSIFinish), with: nil, afterDelay: 10)
        }
        self.refreshing = true
        self.scanAnimationView.isHidden = false
        self.scanAnimationView.layer.addRotationAnimation(duration: 1.2, repeatCount: 999, animationKey: "loading")
        
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 99999, nodeScan: {[weak self] data in
            
            guard let self = self, let node = MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == data.node.primaryUnicastAddress }), node.peripheral == nil else { return }
            
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
                self.perform(#selector(self.refreshNodesRSSIFinish), with: nil, afterDelay: 6)
            }
            
            node.peripheral = data.peripheral
            var enableUpgrade = false
            if let cacheVersion = node.targetFirmwareData?.version, let nodeVersion = node.firmwareVersion {
                enableUpgrade = cacheVersion.compare(nodeVersion, options: .numeric) == .orderedDescending
            }
            if enableUpgrade, let rssi = node.rssi {
                node.enableUpgrade = rssi >= -90
                if node.selectedState == .disabled {
                    node.selectedState = .unselected
                }
            }else {
                node.enableUpgrade = false
                node.selectedState = .disabled
            }
                
            // 查找完所有设备后停止搜索
            if !MeshNetworkManager.instance.realNodes.contains(where: { $0.rssi == nil || $0.peripheral == nil }) {
                DispatchQueue.main.async {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
                    self.refreshNodesRSSIFinish()
                }
                devicesRssiSort()
            }else {
                if self.rssiSortTimer == nil {
                    self.startRssiSortTimer()
                }
            }
          
            
        }, finished: nil)
        
        
//        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 6 + time) {[weak self] nodes in
//            guard let self = self else { return }
//            nodes.forEach { data in
//                let node = MeshNetworkManager.instance.realNodes.first(where: { $0.primaryUnicastAddress == data.node.primaryUnicastAddress })
//                node?.peripheral = data.peripheral
//            }
//            self.refreshControl.endRefreshing()
//            self.setupData(loadServerData: true)
//            
//            XWHUDManager.hideInView(with: self.view)
//        }
    }
    
    /// 刷新信号结束
    @objc private func refreshNodesRSSIFinish() {
        MeshLibManager.manager.stopRefreshNodesRSSI()
        refreshing = false
        scanAnimationView.layer.removeAnimation(forKey: "loading")
        scanAnimationView.isHidden = true
    }
    
    private func showEmptyUI() {
        if collectionView.frame != .zero {
            CATransaction.setDisableActions(true)
            collectionView.showEmptyDataView(frame: collectionView.frame, title: "no_data".localizedString)
            CATransaction.commit()
            bottomView.isHidden = true
        }
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 0.5, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        
        var selectNodes: [Node] = []
        var reloadTypeDatas: [FirmwareUpdateTypeData] = []
        firmwareTypeDatas.forEach { data in
            data.nodes.sort(by: { $0.rssi ?? -99 >= $1.rssi ?? -99 })
            if data.isShow {
                reloadTypeDatas.append(data)
            }
            selectNodes.append(contentsOf: data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade && $0.selectedState == .selected }))
        }
        self.selectNodes = selectNodes
        updateSelectAllState()
        
        reloadTypeDatas.forEach({
            self.reloadFirmwareUpdateTypeUI(type: $0)
        })
    }
    
    /// 初始化数据
    /// - Parameters installServerData: 加载服务器数据
    private func setupData(loadServerData: Bool = false) {
        
        var deviceTypes: [FirmwareUpdateTypeData] = []
        
        let nodes = MeshNetworkManager.instance.realNodes
        nodes.forEach { node in
            if let pid = node.productIdentifier {
//                let deviceType = DeviceType(pid: pid)
//                if deviceType != .unknown {
                    
                    // 读取本地固件包
                    let localFirmwareData = FirmwareData.load(productId: pid).first
                    let cacheVersion = localFirmwareData?.version
                    
                    var enableUpgrade = false
                    
                    if cacheVersion != nil, let nodeVersion = node.firmwareVersion {
                        enableUpgrade = cacheVersion!.compare(nodeVersion, options: .numeric) == .orderedDescending
                    }
                    if let deviceTypeData = deviceTypes.first(where: { $0.productId == node.productIdentifier }) {
                        deviceTypeData.nodes.append(node)
                        if enableUpgrade {
                            deviceTypeData.upgradedNodes.append(node)
                        }
                    }else {
                        let data = FirmwareUpdateTypeData(productId: pid, targetVersion: localFirmwareData?.version, nodes: [node])
                        data.targetVersionHash = localFirmwareData?.compositionHash
                        data.isShow = self.showData[pid] ?? false
                        if enableUpgrade {
                            data.upgradedNodes.append(node)
                        }
                        deviceTypes.append(data)
                    }
                    
                node.targetFirmwareData = localFirmwareData
                node.enableUpgrade = false
                node.selectedState = .disabled
                
                if enableUpgrade, let rssi = node.rssi {
                    node.enableUpgrade = rssi >= -90
                    if node.selectedState == .disabled {
                        node.selectedState = .unselected
                    }
                }else {
                    node.enableUpgrade = false
                    node.selectedState = .disabled
                }
            }
                
        }
        self.firmwareTypeDatas = deviceTypes
        
        if deviceTypes.isEmpty {
            collectionView.refreshControl = nil
            showEmptyUI()
        }else {
            if collectionView.refreshControl == nil {
                collectionView.refreshControl = refreshControl
            }
            bottomView.isHidden = false
            var selectNodes: [Node] = []
            firmwareTypeDatas.forEach { data in
                data.nodes.sort(by: { $0.rssi ?? -99 >= $1.rssi ?? -99 })
                selectNodes.append(contentsOf: data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade && $0.selectedState == .selected }))
            }
            self.selectNodes = selectNodes
            updateSelectAllState()
            
            if loadServerData {
                deviceTypes.forEach { data in
                    if data.targetVersion != nil {
                        loadCloudFirmwareRequest(type: data)
                    }
                }
            }
            
        }
        
        self.collectionView.reloadData()
    }
    
    /// 开始更新节点
    private func startUpgraded(nodes: [Node]) {
        
        let targets: [MeshFirmwareUpdateManager.FirmwareUpdateTarget] = nodes.compactMap({
            if let targetFirmwareData = $0.targetFirmwareData {
                return MeshFirmwareUpdateManager.FirmwareUpdateTarget(node: $0, peripheral: $0.peripheral, firmwareData: targetFirmwareData.data, firmwareID: targetFirmwareData.firmwareID, updateFirmwareImageIndex: UInt8(targetFirmwareData.updateFirmwareImageIndex), incomingFirmwareMetadata: targetFirmwareData.incomingFirmwareMetadata)
            }
            return nil
        })
        guard targets.count > 0 else {
            return
        }
        
        let stateView = FirmwareUpdateStateView(frame: UIScreen.main.bounds)
        stateView.delegate = self
        stateView.show()
        self.upgradeView = stateView
        // 设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        
        MeshFirmwareUpdateManager.shared.startFirmwareUpdate(targets: targets) {[weak self] node, state in
            guard let self = self else { return }
            switch state {
            case .connecting, .ready:
                let index = targets.firstIndex(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) ?? 0
                stateView.start(title: "\("updating".localizedString): \(index + 1)/\(targets.count)", deviceName: node.name ?? "", currentVersion: node.firmwareVersion ?? "--", targetVersion: node.targetFirmwareData?.version ?? "--")
                if case .connecting = state {
                    stateView.update(state: .connect)
                }else {
                    stateView.update(state: .start)
                }
            case .updating(let progress, let estimatedTime):
                let minutes = estimatedTime / 60
                let second = estimatedTime % 60
                let str = "\(minutes) \("minutes".localizedString) \(second) \("sec".localizedString)"
                stateView.update(state: .inProgress(progress: Int(progress), estimatedTime: str))
            case .complete:
                node.updateState = .successful
                // 判断是否升级成功后会被重置
                if !self.restoreNodes.contains(node), let type = self.firmwareTypeDatas.first(where: { $0.productId == node.productIdentifier }), node.compositionHash != nil, node.compositionHash != type.targetVersionHash {
                    self.restoreNodes.append(node)
                    if self.restoreNodes.count == 1 {
                        self.collectionView.reloadData()
                    }
                    self.restoreView?.resetDevicesCount = self.restoreNodes.count
                }
            case .failed(let error):
                node.updateState = .failure(error)
            }
            
        } complete: {[weak self] successfulList, failureList in
            
            // 关闭设置屏幕常亮
            UIApplication.shared.isIdleTimerDisabled = false
            guard let self = self else { return  }
            var selectNodes: [Node] = []
            self.firmwareTypeDatas.forEach { data in
                selectNodes.append(contentsOf: data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade && $0.selectedState == .selected }))
            }
            self.selectNodes = selectNodes
            
            if targets.count > 1 { // 多设备升级
                stateView.update(state: .result(successfuly: successfulList.count, failed: failureList.count))
            }else { // 单设备升级
                if let failedTarget = failureList.first {
                    stateView.update(state: .failure(message: failedTarget.1.message))
                }else {
                    stateView.update(state: .completed)
                }
            }
            if successfulList.count > 0 {
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
            self.failedNodes = failureList.map({ $0.0.node })
            self.setupData()
        }

    }
    
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        bottomView.isHidden = true
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFrom(60))
        }
        
        let lineView = UIView()
        lineView.backgroundColor = Line_Color1
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        selectAllBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectAllBtnAction))
        bottomView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(15))
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        bottomView.addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllBtn.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
        }
        
        selectCountLabel = UILabel(text: "3/6", textColor: Message_Color, fontSize: 14, fontWeight: .light)
        bottomView.addSubview(selectCountLabel)
        selectCountLabel.snp.makeConstraints { make in
            make.top.equalTo(selectAllLabel.snp.bottom).offset(SCRYFrom(3))
            make.left.equalTo(selectAllLabel)
        }
        
        upgradeBtn = UIButton(title: "upgrade_selected".localizedString, titleSize: 14, titleWeight: .light, titleColor: .white, target: self, action: #selector(upgradeBtnAction))
        let btnSize = CGSize(width: SCRXFrom(140), height: SCRYFrom(40))
        upgradeBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        upgradeBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color), for: .normal)
        upgradeBtn.isEnabled = false
        upgradeBtn.layer.cornerRadius = SCRYFrom(20)
        upgradeBtn.layer.masksToBounds = true
        bottomView.addSubview(upgradeBtn)
        upgradeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
            make.width.equalTo(btnSize.width)
            make.height.equalTo(btnSize.height)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        flowLayout.minimumInteritemSpacing = 0
        flowLayout.sectionInset = UIEdgeInsets(top: 16, left: 0, bottom: 0, right: 0)
        flowLayout.sectionHeadersPinToVisibleBounds = true
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(refreshRSSI), for: .valueChanged)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = Background_Color
        collectionView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        collectionView.register(BleFirmwareTypeUpdateViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.register(BleFirmwareUpdateRestoreView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
        }
        
    }
    
    private func updateSelectAllState() {
        
        var canSelectNodes: [Node] = []
        firmwareTypeDatas.forEach { data in
            canSelectNodes.append(contentsOf: data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade }))
        }
        selectAllBtn.isSelected = canSelectNodes.count > 0 && selectNodes.count == canSelectNodes.count
        selectCountLabel.text = "\(selectNodes.count)/\(canSelectNodes.count)"
        updateUpgradeBtnState()
    }
    
    private func updateUpgradeBtnState() {
        upgradeBtn.isEnabled = !selectNodes.isEmpty
    }
    
    /// 刷新设备类型UI
    private func reloadFirmwareUpdateTypeUI(type: FirmwareUpdateTypeData) {
        if type.isShow, let typeIndex = firmwareTypeDatas.firstIndex(where: { $0.productId == type.productId }) {
            if let cell = collectionView.cellForItem(at: IndexPath(row: typeIndex, section: 0)) as? BleFirmwareTypeUpdateViewCell {
                cell.firmwareTypeData = type
            }
        }
    }
    
    /// 刷新节点UI
    private func reloadNodeUI(node: Node) {
        if let typeIndex = firmwareTypeDatas.firstIndex(where: { $0.productId == node.productIdentifier }) {
            let firmwareTypeData = firmwareTypeDatas[typeIndex]
            guard firmwareTypeData.isShow else {
                return
            }
            if let cell = collectionView.cellForItem(at: IndexPath(row: typeIndex, section: 0)) as? BleFirmwareTypeUpdateViewCell,
               let row = firmwareTypeData.nodes.firstIndex(of: node) {
                cell.deviceTableView.reloadRows(at: [IndexPath(row: row, section: 0)], with: .none)
            }else {
                collectionView.reloadItems(at: [IndexPath(row: typeIndex, section: 0)])
            }
        }else {
            collectionView.reloadSections(IndexSet(integer: 0))
        }
    }
    
    // MARK: - Action
    
    /// 返回
    @objc private func backAction() {
        self.dismiss(animated: true)
        
        if refreshing {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.refreshNodesRSSIFinish), object: nil)
            MeshLibManager.manager.stopRefreshNodesRSSI()
        }
    }

    /// 帮助
    @objc private func helpAction() {
        let vc = BLEUpgradeInstructionsController()
        vc.title = "ble_upgrade_instructions".localizedString
        let datas: [BLEUpgradeInstructionsController.InstructionsData] = [
            .init(iconName: "server_download", name: "server_firmware".localizedString, message: "server_firmware_message".localizedString + "\n\n", showArrow: true, arrowX: isIPad ? SCRXFrom(200) : SCRXFrom(104), ratio: 0.333),
            .init(iconName: "initiator", name: "initiator".localizedString, message: "initiator_message".localizedString + "\n\n", showArrow: true, arrowX: isIPad ? SCRXFrom(450) : SCRXFrom(209), ratio: 0.333),
            .init(iconName: "single_device", name: "updating_node".localizedString, message: "updating_node_message".localizedString + "\n\n" + "ble_upgrade_instructions_message".localizedString, showArrow: false, arrowX: 0, ratio: 0.333)
        ]
        vc.datas = datas
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func selectAllBtnAction(sender: UIButton) {
        
        if refreshing {
            XWHUDManager.showTipHUD("device_search_disable_select".localizedString, isLineFeed: true)
            return
        }
        
        if sender.isSelected {
            selectNodes.forEach({ $0.selectedState = .unselected })
            selectNodes.removeAll()
        }else {
            var canSelectNodes: [Node] = []
            firmwareTypeDatas.forEach { data in
                let nodes = data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade })
                nodes.forEach({ $0.selectedState = .selected })
                canSelectNodes.append(contentsOf: nodes)
            }
            selectNodes = canSelectNodes
        }
        collectionView.reloadData()
        updateSelectAllState()
    }
    
    /// 开始升级
    @objc private func upgradeBtnAction() {
        guard self.selectNodes.count > 0 else {
            return
        }
        upgradeCheak(nodes: selectNodes)
    }
    
    /// 升级检查设备，升级后需要重置的设备提前提示
    private func upgradeCheak(nodes: [Node]) {
        
        // 获取升级后会重置的设备list
        let resetTypes = self.firmwareTypeDatas.filter({ type in
            return nodes.contains(where: { $0.productIdentifier == type.productId && $0.compositionHash != nil && $0.compositionHash != type.targetVersionHash })
        })
        
//        let resetNodes = nodes.filter({ node in node.compositionHash != self.firmwareTypeDatas.first(where: { $0.productId == node.productIdentifier })?.targetVersionHash })
        if resetTypes.count > 0 {
            var firmwareStr = ""
            resetTypes.forEach({ type in
                let pid = String(format: "0x%04X", type.productId)
                firmwareStr.append(String(format: "%@%@", firmwareStr.isEmpty ? "" : ",", pid))
            })
            firmwareStr = "[\(firmwareStr)]"
            let message = String(format: "firmware_update_reset_message".localizedString, firmwareStr)
            
            let messageAttStr = NSMutableAttributedString(string: message)
            messageAttStr.addAttributes([.font: FONTS(SCRYFrom(15)), .foregroundColor: TextBlack_Color], range: (message as NSString).range(of: firmwareStr))
            
            SRAlertView(title: "notification".localizedString, messageAttStr: messageAttStr, actions: [.cancelAction, SRAlertAction(title: "UPGRADE".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                self.startUpgraded(nodes: nodes)
            })]).show()
        }else {
            startUpgraded(nodes: nodes)
        }
        
    }
    
}

extension BleFirmwareUpdateViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return firmwareTypeDatas.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! BleFirmwareTypeUpdateViewCell
        cell.firmwareTypeData = firmwareTypeDatas[indexPath.row]
        cell.delegate = self
//        cell.isShow = showData[indexPath.item] ?? false
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! BleFirmwareUpdateRestoreView
        headerView.unfold = unfold
        headerView.resetDevicesCount = self.restoreNodes.count
        headerView.delegate = self
        self.restoreView = headerView
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        if self.restoreNodes.count > 0 {
            return CGSize(width: collectionView.width, height: BleFirmwareUpdateRestoreView.getSectionHeight(unfold: self.unfold))
        }else {
            return .zero
        }
    }

    
//    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
//        var itemH = SCRYFrom(182)
//        if showData[indexPath.item] ?? false {
//            itemH += (SCRYFrom(44) + SCRYFrom(60 + 18))
//        }
//        return CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: itemH)
//    }
    
}

extension BleFirmwareUpdateViewController: BleFirmwareTypeUpdateViewCellDelegate {
    
    /// 选择设备更新回调
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, selectDevicesDidChange selectDevices: [NordicSigMeshSDK.Node]) {
        
        if refreshing {
            XWHUDManager.showTipHUD("device_search_disable_select".localizedString, isLineFeed: true)
            selectDevices.forEach({ $0.selectedState = .unselected })
            cell.deviceTableView.reloadData()
            return
        }
        
        var selectNodes: [Node] = []
        firmwareTypeDatas.forEach { data in
            selectNodes.append(contentsOf: data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade && $0.selectedState == .selected }))
        }
        self.selectNodes = selectNodes
        updateSelectAllState()
    }
    
    /// 展开/收起设备列表
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, didShowDevices show: Bool) {
        if let indexPath = collectionView.indexPath(for: cell) {
            let productId = firmwareTypeDatas[indexPath.item].productId
            self.showData.updateValue(show, forKey: productId)
            firmwareTypeDatas[indexPath.row].isShow = show
//            collectionView.reloadItems(at: [indexPath])
            UIView.animate(withDuration: 0.2) {
                self.collectionView.collectionViewLayout.invalidateLayout()
                self.collectionView.layoutIfNeeded()
            }
        }
    }
    
    /// 设备开始升级
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, startUpgraded device: Node) {
        
        if refreshing {
            XWHUDManager.showTipHUD("device_search_disable_select".localizedString, isLineFeed: true)
            return
        }
        
        upgradeCheak(nodes: [device])
//        startUpgraded(nodes: [device])
    }
    
    /// 设备升级失败原因
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, failureReasonAction device: Node) {
        if case .failure(let error) = device.updateState {
            SRAlertView(title: error.title, message: error.message, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                device.updateState = .none
                self.reloadNodeUI(node: device)
//                if let row = self.collectionView.indexPath(for: cell)?.item {
//                    self.collectionView.reloadItems(at: [IndexPath(row: row, section: 0)])
//                }
                if device.selectedState == .selected {
                    //                self.firmwareTypeDatas.forEach { data in
                    //                    self.selectNodes.append(contentsOf: data.nodes.filter({ $0.updateState.rawValue == Node.UpdateState.none.rawValue && $0.enableUpgrade && $0.selectedState == .selected }))
                    //                }
                    if !self.selectNodes.contains(device) {
                        self.selectNodes.append(device)
                    }
                }
                self.updateSelectAllState()
                
            })]).show()
        }
    }
    
    /// 设备识别
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, identifying device: Node) {
        MeshAPI.identify(address: device.primaryUnicastAddress)
    }
    
    /// 固件版本查看
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, viewCurrentTargetVersion firmwareTypeData: FirmwareUpdateTypeData) {
        
        let vc = FirmwareVersionViewController(type: firmwareTypeData)
        vc.localFirmwareData = FirmwareData.load(productId: firmwareTypeData.productId).first
        vc.updateLocalFirmwareDataCallback = {[weak self] updateFirmwareData in
            guard let self = self else { return }
//            firmwareTypeData.targetVersion = updateFirmwareData?.version
//            cell.firmwareTypeData = firmwareTypeData
            MeshNetworkManager.instance.realNodes.forEach({
                $0.updateState = .none
                $0.selectedState = .unselected
            })
            self.failedNodes.removeAll()
            self.setupData()
        }
        navigationController?.pushViewController(vc, animated: true)
        
    }
    
}

extension BleFirmwareUpdateViewController: FirmwareUpdateStateViewDelegate {
    
    /// 点击取消更新回调
    func firmwareUpdateCancelAction(_ view: FirmwareUpdateStateView) {
        self.upgradeView = nil
        MeshFirmwareUpdateManager.shared.stopFirmwareUpdate(complete: nil)
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
        
        self.setupData()
    }
    
    /// 点击重试回调
    func firmwareUpdateRetryAction(_ view: FirmwareUpdateStateView) {
        self.upgradeView = nil
        
        guard self.failedNodes.count > 0 else {
            return
        }
        self.startUpgraded(nodes: failedNodes)
    }
    
    /// 点击ok回调
    func firmwareUpdateOKAction(_ view: FirmwareUpdateStateView) {
        self.upgradeView = nil
    }
    
}


extension BleFirmwareUpdateViewController: BleFirmwareUpdateRestoreViewDelegate {
    
    /// 点击恢复数据
    func firmwareUpdateDidRestoreAction(_ view: BleFirmwareUpdateRestoreView) {
//        self.failedNodes
        guard self.restoreNodes.count > 0 else {
            return
        }
        let vc = DeviceRestoreViewController(restoreMode: .specified(nodes: self.restoreNodes))
        vc.deviceRestoreCallback = {[weak self] nodes in
            guard let self = self else { return }
            self.restoreNodes.removeAll(where: { oldNode in nodes.contains(where: { $0.macAddress == oldNode.macAddress }) })
            if self.restoreNodes.isEmpty {
                self.collectionView.reloadData()
            }else {
                self.restoreView?.resetDevicesCount = self.restoreNodes.count
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 点击展开/收起
    func firmwareUpdateDidUnfoldAction(_ view: BleFirmwareUpdateRestoreView) {
        self.unfold = !self.unfold
        self.collectionView.reloadSections(IndexSet(integer: 0))
    }
}
