//
//  BleFirmwareUpdateViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/8/22.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

internal extension Node {
    static var selectedStateKey = 1
    static var updateStateKey = 2
    static var enableUpgradeKey = 3
    static var targetFirmwareDataKey = 4
    
    // 是否可以升级 设备版本小于当前升级版本 & 信号量 >= -80dB
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
        case failure(MeshFirmwareUpdateManager.FirmwareUpdateError)
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
    
}

internal extension MeshFirmwareUpdateManager.FirmwareUpdateError {
    
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
    
    private var firmwareTypeDatas: [FirmwareUpdateTypeData] = []
    private var selectNodes: [Node] = []
    /// 上一个升级失败的设备list
    private var failedNodes: [Node] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "ota_ble_title".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "help")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(helpAction))
        setupUI()
        self.isModalInPresentation = true
//        setupData()
        
        MeshNetworkManager.instance.realNodes.forEach({
            $0.updateState = .none
            $0.selectedState = .unselected
        })
        
        refreshRSSI()
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
        
        MeshNetworkManager.instance.realNodes.forEach({ $0.rssi = nil })
        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 6) {[weak self] nodes in
            guard let self = self else { return }
//            self.firmwareTypeDatas.forEach({
//                $0.nodes.sort(by: { $0.rssi ?? 0 >= $1.rssi ?? 0 })
//            })
            self.refreshControl.endRefreshing()
            self.setupData(loadServerData: true)
            
            XWHUDManager.hideInView(with: self.view)
        }
    }
    
    private func showEmptyUI() {
        
        view.layoutIfNeeded()
        collectionView.showEmptyDataView(title: "no_devices".localizedString)
        bottomView.isHidden = true
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
                        enableUpgrade = cacheVersion!.compare(nodeVersion) == .orderedDescending
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
                    if enableUpgrade, let rssi = node.rssi {
                        node.enableUpgrade = rssi >= -80
                        if node.selectedState == .disabled {
                            node.selectedState = .unselected
                        }
                    }else {
                        node.enableUpgrade = false
                        node.selectedState = .disabled
                    }
//                }
                
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
                return MeshFirmwareUpdateManager.FirmwareUpdateTarget(node: $0, firmwareData: targetFirmwareData.data, firmwareID: targetFirmwareData.firmwareID, updateFirmwareImageIndex: UInt8(targetFirmwareData.updateFirmwareImageIndex), incomingFirmwareMetadata: targetFirmwareData.incomingFirmwareMetadata)
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
        
        MeshFirmwareUpdateManager.shared.startFirmwareUpdate(targets: targets) { node, state in
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
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(60))
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
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(refreshRSSI), for: .valueChanged)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(BleFirmwareTypeUpdateViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
            make.top.equalTo((navigationController?.navigationBar.height ?? 0) + SCRYFrom(7))
        }
        
        flowLayout.estimatedItemSize = CGSize(width: view.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(182))
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
    
    // MARK: - Action
    
    /// 返回
    @objc private func backAction() {
        self.dismiss(animated: true)
    }

    /// 帮助
    @objc private func helpAction() {
        let vc = BLEUpgradeInstructionsController()
        navigationController?.pushViewController(vc, animated: true)
    }

    @objc private func selectAllBtnAction(sender: UIButton) {
        
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
        collectionView.reloadSections(IndexSet(integer: 0))
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
        upgradeCheak(nodes: [device])
//        startUpgraded(nodes: [device])
    }
    
    /// 设备升级失败原因
    func cell(_ cell: BleFirmwareTypeUpdateViewCell, failureReasonAction device: Node) {
        if case .failure(let error) = device.updateState {
            SRAlertView(title: error.title, message: error.message, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                guard let self = self else { return }
                device.updateState = .none
                if let row = self.collectionView.indexPath(for: cell)?.item {
                    self.collectionView.reloadItems(at: [IndexPath(row: row, section: 0)])
                }
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
