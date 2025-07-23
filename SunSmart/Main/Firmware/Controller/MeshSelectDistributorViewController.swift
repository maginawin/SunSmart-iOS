//
//  MeshSelectDistributorViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/10/31.
//

import UIKit
import NordicSigMeshSDK

/// mesh固件升级流程
enum MeshFirmwareUpgradeStep {
    /// 分发
    case distributor
    /// 更新多设备
    case upgradeNodes
}

internal extension Node {
    
    static var distributorSelectedStateKey = 1
    static var rssiStateKey = 2
    
    /// 设备选择状态
    enum DistributorSelectedState {
        /// 无（不展示选择）
        case none
        /// 未选中
        case unselected
        /// 选中
        case selected
        /// 不可选（禁用状态）
        case disabled
    }
    
    /// 信号状态
    enum RSSIState {
        /// 无信号
        case none
        /// 正常信号
        case normal
        /// 信号差
        case low
    }
    
    /// 选择状态
    var distributorSelectedState: DistributorSelectedState {
        get {
            objc_getAssociatedObject(self, &Node.distributorSelectedStateKey) as? DistributorSelectedState ?? .none
        }set {
            objc_setAssociatedObject(self, &Node.distributorSelectedStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    /// 信号状态
    var rssiState: RSSIState {
        get {
            objc_getAssociatedObject(self, &Node.rssiStateKey) as? RSSIState ?? .none
        }set {
            objc_setAssociatedObject(self, &Node.rssiStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}

class MeshSelectDistributorViewController: UIViewController {
    
    /// 操作状态
    enum OperateState {
        /// 无
        case none
        /// 上传固件
        case upload
        /// 下一步
        case next
    }

    private var tableView: UITableView!
    private var headerView: MeshFirmwareUpgradeHeaderView!
    private var bottomView: UIView!
    private var bottomLineView: UIView!
    private var bottomBtn: UIButton!
    private var nodes: [Node] = []
    private var selectNode: Node?
    /// 操作状态
    private var operateState: OperateState = .none
    
    private var refreshControl: UIRefreshControl!
    
    private weak var uploadStateView: FirmwareDistributeUpdateStateView?
    
    private var scanAnimationView: UIImageView!
    /// 是否正在刷新设备信号
    private var refreshing: Bool = false
    private var rssiSortTimer: Timer?
    
    /// 分发的固件数据
    let firmwareData: FirmwareData?
    let productId: UInt16
    
    init(productId: UInt16, firmwareData: FirmwareData?) {
        self.productId = productId
        self.firmwareData = firmwareData
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "select_distributor".localizedString
        view.backgroundColor = Background_Color
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: scanAnimationView)
        
        setupUI()
        
        nodes = MeshNetworkManager.instance.realNodes.filter({ $0.productIdentifier == productId })
//        setupData()
        refreshRSSI()
        updateUI()
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
            $0.rssiState = .none
        })
        self.tableView.reloadData()
//        self.setupData(loadServerData: true)
        
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
                self.perform(#selector(self.refreshNodesRSSIFinish), with: nil, afterDelay: 10)
            }
            
            node.peripheral = data.peripheral
           
            if let rssi = node.rssi {
                if rssi >= -90 {
                    node.rssiState = .normal
                }else {
                    node.rssiState = .low
                }
            }else {
                node.rssiState = .none
            }
            switch node.rssiState {
            case .none:
                node.distributorSelectedState = .none
            case .normal:
                if self.firmwareData == nil { // 本地没有固件包, 判断设备内是否有固件包并大于其它设备固件版本
                    if node.distributionVersion == nil || self.nodes.contains(where: { $0.distributionVersion?.compare(node.distributionVersion!, options: .numeric) == .orderedDescending }) {
                        node.distributorSelectedState = .none
                    }else {
                        node.distributorSelectedState = self.selectNode == node ? .selected : .unselected
                    }
                }else {
                    node.distributorSelectedState = self.selectNode == node ? .selected : .unselected
                }
            case .low:
                node.distributorSelectedState = .unselected
            }
            if node.primaryUnicastAddress == self.selectNode?.primaryUnicastAddress, node.rssiState != .normal {
                self.selectNode = nil
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
        
        self.updateUI()
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
        nodes.sort(by: { $0.rssi ?? -99 >= $1.rssi ?? -99 })
        tableView.reloadData()
    }
    
//    @objc private func setupData() {
//        
//        guard nodes.count > 0 else {
//            showEmptyUI()
//            return
//        }
//        
//        nodes.forEach({ 
//            $0.rssi = nil
//            $0.rssiState = .none
//            $0.distributorSelectedState = .none
//        })
//        XWHUDManager.showCustomHUD(withMessage: nil, view: view)
//        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 6) {[weak self] nodes in
//            guard let self = self else { return }
//            self.refreshControl.endRefreshing()
//            self.nodes.forEach { node in
//                if let rssi = node.rssi {
//                    if rssi >= -90 {
//                        node.rssiState = .normal
//                    }else {
//                        node.rssiState = .low
//                    }
//                }else {
//                    node.rssiState = .none
//                }
//                switch node.rssiState {
//                case .none:
//                    node.distributorSelectedState = .none
//                case .normal:
//                    if self.firmwareData == nil { // 本地没有固件包, 判断设备内是否有固件包并大于其它设备固件版本
//                        if node.distributionVersion == nil || self.nodes.contains(where: { $0.distributionVersion?.compare(node.distributionVersion!, options: .numeric) == .orderedDescending }) {
//                            node.distributorSelectedState = .none
//                        }else {
//                            node.distributorSelectedState = self.selectNode == node ? .selected : .unselected
//                        }
//                    }else {
//                        node.distributorSelectedState = self.selectNode == node ? .selected : .unselected
//                    }
//                case .low:
//                    node.distributorSelectedState = .unselected
//                }
//            }
//            if self.selectNode?.rssiState != .normal {
//                self.selectNode = nil
//            }
//            self.nodes.sort(by: { $0.rssi ?? -99 >= $1.rssi ?? -99 })
//            
//            self.updateUI()
//            XWHUDManager.hideInView(with: self.view)
//        }
//        
//    }
    
    /// 固件上传
    private func startFirmwareUpload(node: Node) {
        
        guard let firmwareData = self.firmwareData else { return }
        
        // 读取本地固件包
//            let localFirmwareData = FirmwareData.load(productId: firmwareData.productId).first
        let stateView = FirmwareDistributeUpdateStateView(frame: UIScreen.main.bounds)
        stateView.delegate = self
        stateView.show()
        self.uploadStateView = stateView
        // 设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        
        stateView.start(title: "upload_firmware".localizedString, message: "upload_firmware_message".localizedString, deviceName: node.name, distributeVersion: firmwareData.version)
        MeshFirmwareDistributionManager.shared.startUploadFirmware(node: node, firmwareData: firmwareData.data, firmwareID: firmwareData.firmwareID, uploadFirmwareImageIndex: UInt8(firmwareData.updateFirmwareImageIndex), incomingFirmwareMetadata: firmwareData.incomingFirmwareMetadata) {[weak self] node, state in
            switch state {
            case .ready, .connecting:
                stateView.update(state: .inProgress(progress: 0, estimatedTime: nil))
            case .updating(let progress, _):
                stateView.update(state: .inProgress(progress: Int(progress), estimatedTime: nil))
            case .complete:
                stateView.update(state: .completed)
                UIApplication.shared.isIdleTimerDisabled = false
                self?.updateUI()
            case .failed(let error):
                stateView.update(state: .failure(message: error.message))
                UIApplication.shared.isIdleTimerDisabled = false
                self?.updateUI()
            }
        }
    }
    
    @objc private func bottomBtnAction() {
        
        guard let selectNode = self.selectNode else {
            return
        }
        
        switch operateState {
        case .none:
            break
        case .upload:
            startFirmwareUpload(node: selectNode)
        case .next:
            
            let vc = MeshSelectUpgradeDevicesViewController(distributorNode: selectNode, distributorData: nil)
            navigationController?.pushViewController(vc, animated: true)
        }
        
    }
    
    private func updateUI() {
        
        if !refreshing, let selectNode = self.selectNode {
            if let firmwareData = self.firmwareData {
                if let distributionVersion = selectNode.distributionVersion, firmwareData.version.compare(distributionVersion, options: .numeric) != .orderedDescending {
                    self.operateState = .next
                }else {
                    self.operateState = .upload
                }
            }else {
                if selectNode.distributionVersion != nil && !self.nodes.contains(where: { $0.distributionVersion?.compare(selectNode.distributionVersion!, options: .numeric) == .orderedDescending }) {
                    self.operateState = .next
                }else {
                    self.operateState = .none
                }
            }
        }else {
            self.operateState = .none
        }
        
        switch self.operateState {
        case .none:
            bottomBtn.setTitle("UPLOAD".localizedString, for: .normal)
            bottomBtn.setTitleColor(Message_Color, for: .normal)
            bottomBtn.isUserInteractionEnabled = false
        case .upload:
            bottomBtn.setTitle("UPLOAD".localizedString, for: .normal)
            bottomBtn.setTitleColor(Bar_Color, for: .normal)
            bottomBtn.isUserInteractionEnabled = true
        case .next:
            bottomBtn.setTitle("NEXT".localizedString, for: .normal)
            bottomBtn.setTitleColor(Bar_Color, for: .normal)
            bottomBtn.isUserInteractionEnabled = true
        }
        
        self.tableView.reloadSections(IndexSet(integer: 0), with: .none)
    }
    
    private func showEmptyUI() {
        if tableView.frame == .zero {
            view.layoutIfNeeded()
        }
        tableView.showEmptyDataView(title: "no_data".localizedString)
        bottomView.isHidden = true
    }
    
    private func setupUI() {
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo((isIPad ? 0 : kSafeAreaBottomHeight) + SCRYFrom(56))
        }
        
        bottomLineView = UIView()
        bottomLineView.backgroundColor = Line_Color
        bottomView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        bottomBtn = UIButton(title: "UPLOAD".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(bottomBtnAction))
        bottomView.addSubview(bottomBtn)
        bottomBtn.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        headerView = MeshFirmwareUpgradeHeaderView(frame: CGRect(x: 0, y: 0, width: view.width, height: SCRYFrom(126)))
        headerView.step = .distributor
        headerView.promptCallback = {
            MeshFirmwareUpgradeGuideView(title: "how_to_select_a_distributor".localizedString, message: "mesh_distributor_prompt_message".localizedString, steps: [.location, .signal, .identify, .distributor], contentHeight: SCREEN_HEIGHT - SCRYFit(74)).show()
        }
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(refreshRSSI), for: .valueChanged)
        
        tableView = UITableView()
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(60)
        tableView.register(MeshFirmwareSelectDeviceViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(MeshFirmwareUpgradeSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
        tableView.tableHeaderView = headerView
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(16), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.refreshControl = refreshControl
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.bottom.equalTo(bottomView.snp.top)
        }
    }
    

}

extension MeshSelectDistributorViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return nodes.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! MeshFirmwareSelectDeviceViewCell
        let node = nodes[indexPath.row]
        cell.updateData(device: node, upgradeStep: .distributor, showSelect: node.distributorSelectedState != .none, selected: node.distributorSelectedState == .selected, enabled: node.distributorSelectedState != .disabled)
        cell.identifyCallback = {
            MeshAPI.identify(address: node.primaryUnicastAddress)
        }
        return cell
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! MeshFirmwareUpgradeSectionView

        if operateState == .upload, let firmwareData = self.firmwareData {
//            headerView.messageLabel.textColor = TextBlack_Color
            headerView.messageView.isHidden = false
            let message = "\("upload".localizedString) \(firmwareData.version) \("to".localizedString) \(self.selectNode?.name ?? "--")"
            let messageAttStr = NSMutableAttributedString(string: message)
            messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (message as NSString).range(of: "upload".localizedString))
            messageAttStr.addAttributes([.foregroundColor: Message_Color], range: (message as NSString).range(of: "to".localizedString))
            headerView.messageLabel.attributedText = messageAttStr
        }else if operateState == .none, self.firmwareData == nil {
            headerView.messageView.isHidden = false
//            headerView.messageLabel.textColor = Bar_Color
            headerView.messageLabel.attributedText = NSAttributedString(string: "download_firmware_message".localizedString, attributes: [.foregroundColor: Bar_Color])
        }else {
            headerView.messageView.isHidden = true
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if (operateState == .upload && self.firmwareData != nil) || (operateState == .none && self.firmwareData == nil) {
            return SCRYFrom(71)
        }
        return SCRYFrom(31)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        if refreshing {
            XWHUDManager.showTipHUD("device_search_disable_select".localizedString, isLineFeed: true)
            return
        }
        let node = nodes[indexPath.row]
        guard node.distributorSelectedState == .unselected else {
            return
        }
        if node.rssiState == .none {
            return
        }
        if node.rssiState == .low {
            XWHUDManager.showTipHUD("signal_below_message".localizedString, isLineFeed: true)
            return
        }
        
//        var reloadIndexPaths: [IndexPath] = [indexPath]
//        if selectNode == node {
//            selectNode = nil
//        }else {
            if let lastSeletNode = selectNode {
                lastSeletNode.distributorSelectedState = .unselected
//                reloadIndexPaths.append(IndexPath(row: lastIndex, section: 0))
            }
        node.distributorSelectedState = .selected
            selectNode = node
//        }
//        tableView.reloadRows(at: reloadIndexPaths, with: .none)
        updateUI()
    }
    
}

extension MeshSelectDistributorViewController: FirmwareDistributeUpdateStateViewDelegate {
    
    func firmwareUpdateCancelAction(_ view: FirmwareDistributeUpdateStateView) {
        self.uploadStateView = nil
        MeshFirmwareDistributionManager.shared.stopUploadFirmware(complete: nil)
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
    }
    
    func firmwareUpdateRetryAction(_ view: FirmwareDistributeUpdateStateView) {
        self.uploadStateView = nil
        guard let node = self.selectNode else {
            return
        }
        self.startFirmwareUpload(node: node)
    }
    
    func firmwareUpdateOKAction(_ view: FirmwareDistributeUpdateStateView) {
        view.hide()
        uploadStateView = nil
    }
}
