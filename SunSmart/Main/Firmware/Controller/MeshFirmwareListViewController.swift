//
//  MeshFirmwareListViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/23.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

internal extension FirmwareUpdateTypeData {
    
    /// 设备版本状态
    enum DeviceVersionState {
        /// 无
        case none
        /// 可升级
        case updatable
        /// 已是最新版本
        case latest
    }
    
    /// 升级状态
    enum UpdateState {
        /// 等待
        case wait
        /// 升级中
        case updating(progress: Int)
        /// 完成
        case complete
        /// 失败
        case failure
    }
    static var versionStateKey: UInt8 = 0
    static var updateStateKey: UInt8 = 0
    static var distributorDataKey: UInt8 = 0
    
    var versionState: DeviceVersionState {
        get {
            objc_getAssociatedObject(self, &FirmwareUpdateTypeData.versionStateKey) as? DeviceVersionState ?? .none
        }set {
            objc_setAssociatedObject(self, &FirmwareUpdateTypeData.versionStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
//    var updateState: UpdateState? {
//        get {
//            objc_getAssociatedObject(self, &FirmwareUpdateTypeData.updateStateKey) as? UpdateState
//        }set {
//            objc_setAssociatedObject(self, &FirmwareUpdateTypeData.updateStateKey, newValue, .OBJC_ASSOCIATION_RETAIN)
//        }
//    }
    
    
    /// 分发数据
    var distributorData: MeshDistributionData? {
        get {
            objc_getAssociatedObject(self, &FirmwareUpdateTypeData.distributorDataKey) as? MeshDistributionData
        }set {
            objc_setAssociatedObject(self, &FirmwareUpdateTypeData.distributorDataKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
}

/// 设备固件类型列表刷新通知
let firmwareListRefreshNotificationName = "firmwareListRefreshNotification"

class MeshFirmwareListViewController: UIViewController {
    
    private var flowLayout: UICollectionViewFlowLayout!
    private var collectionView: UICollectionView!
    private var refreshControl: UIRefreshControl!
    
    private var firmwareTypeDatas: [FirmwareUpdateTypeData] = []
    /// 是否刷新列表
    private var refreshData: Bool = false
    
    private var helpBtn: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = "ota_mesh_title".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpAction))
//        #if DEBUG
//        let testTap = ContinuousTapGestureRecognizer(target: self, action: #selector(test), numberOfTouchesRequired: 3, duration: 2)
        let testTap = UILongPressGestureRecognizer(target: self, action: #selector(test))
        helpBtn.addGestureRecognizer(testTap)
//        #endif
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: helpBtn)
        setupUI()
        self.isModalInPresentation = true
        
        setupData(loadServerData: true)
        
        NotificationCenter.default.addObserver(forName: .init(firmwareListRefreshNotificationName), object: nil, queue: nil) {[weak self] _ in
            guard let self = self else { return }
            if self.view.window != nil {
                setupData(loadServerData: true)
                self.refreshData = false
            }else {
                self.refreshData = true
            }
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if self.refreshData {
            setupData(loadServerData: true)
            self.refreshData = false
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if collectionView.firstShowFlashScrollIndicators {
            collectionView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        if firmwareTypeDatas.isEmpty {
            showEmptyUI()
        }
        
        flowLayout.itemSize = CGSize(width: view.width - collectionView.contentInset.left - collectionView.contentInset.right, height: SCRYFrom(206))
    }
    
    @objc private func test(sender: UIGestureRecognizer) {
        guard sender.state == .began else {
            return
        }
        let vc = ReadDevicesDataViewController(type: .parameters(nodes: MeshNetworkManager.instance.realNodes, parameters: [.firmwareVension]))
        vc.readSuccessCallback = {[weak self] _ in
            self?.setupData(loadServerData: true)
            self?.navigationController?.popViewController(animated: true)
        }
        vc.backActionCallback = {[weak self] _ in
            self?.setupData(loadServerData: true)
            self?.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
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
    
    private func showEmptyUI() {
        if collectionView.frame != .zero {
            CATransaction.setDisableActions(true)
            collectionView.showEmptyDataView(frame: collectionView.frame, title: "no_data".localizedString)
            CATransaction.commit()
        }
    }
    
    @objc private func refresh() {
        setupData(loadServerData: true)
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
                node.enableUpgrade = enableUpgrade
                if let deviceTypeData = deviceTypes.first(where: { $0.productId == node.productIdentifier }) {
                    deviceTypeData.nodes.append(node)
                }else {
                    let data = FirmwareUpdateTypeData(productId: pid, targetVersion: localFirmwareData?.version, nodes: [node])
                    data.targetVersionHash = localFirmwareData?.compositionHash
                    deviceTypes.append(data)
                }
                //                }
            }
        }
        
        
        
        if deviceTypes.isEmpty {
            collectionView.refreshControl = nil
            showEmptyUI()
        }else {
            if collectionView.refreshControl == nil {
                collectionView.refreshControl = refreshControl
            }
            deviceTypes.forEach({
                if $0.targetVersion == nil {
                    $0.versionState = .none
                }else {
                    if $0.canUpgradNodes.count > 0 {
                        $0.versionState = .updatable
                    }else {
                        $0.versionState = .latest
                    }
                }
                
                let distributionData = self.firmwareTypeDatas.first(where: { $0.productId == $0.productId })?.distributorData ?? MeshDistributionData.load(productId: $0.productId)
        
                if distributionData?.distributionNode != nil {
                    $0.distributorData = distributionData
                }
            })
            
            if loadServerData {
                deviceTypes.forEach { data in
                    if data.targetVersion != nil {
                        loadCloudFirmwareRequest(type: data)
                    }
                }
            }
        }
        
        self.firmwareTypeDatas = deviceTypes
        getDistributorState()
        self.collectionView.reloadData()
    }
    
    /// 获取分发状态
    private func getDistributorState() {
        
        let distributorTypeDatas = firmwareTypeDatas.filter({ $0.distributorData != nil })
        guard distributorTypeDatas.count > 0, MeshLibManager.manager.isMeshNetworkConnected else {
            refreshControl.endRefreshing()
            return
        }
        XWHUDManager.showCustomHUD(withMessage: nil, view: self.view, afterDelay: TimeInterval(distributorTypeDatas.count * 3))
        DispatchQueue.global().async {
            let semphore = DispatchSemaphore(value: 0)
            for data in distributorTypeDatas {
                if let distributionNode = data.distributorData?.distributionNode {
                    MeshFirmwareDistributionManager.shared.getDistributionState(distributionNode: distributionNode) {[weak self] _, state in
                        guard let self = self else { return }
                        if state != nil {
                            data.distributorData?.distributionState = state!
                            data.distributorData?.save(productId: data.productId)
                            
                            if let index = self.firmwareTypeDatas.firstIndex(where: { $0.productId == data.productId }) {
                                DispatchQueue.main.async {
                                    self.collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
                                }
                            }
                        }
                        semphore.signal()
                    }
                    semphore.wait()
                }
            }
            DispatchQueue.main.async {
                XWHUDManager.hideInView(with: self.view)
                self.refreshControl.endRefreshing()
            }
        }
        
    }
    
    // MARK: - Action
    
    /// 返回
    @objc private func backAction() {
        
        /// 是否mesh分发升级中
        var meshDistribution: Bool = false
        for data in self.firmwareTypeDatas {
            switch data.distributorData?.distributionState {
            case .updating(let updatePhase):
                switch updatePhase {
                case .blob:
                    meshDistribution = true
                default:
                    break
                }
            case .complete, .failure: // 成功及失败状态退出页面后删除缓存数据
                data.distributorData?.delete(productId: data.productId)
            default:
                break
            }
        }
        
        /// mesh分发升级中
        if meshDistribution {
            guard let space = SpaceViewController.currentSpaceVc()?.space, !space.meshOTADistribution else {
                self.dismiss(animated: true)
                return
            }
            SRAlertView(title: "notification".localizedString, message: "mesh_distributor_permission_changed_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, hideAnimation: false, actionHandler: {[weak self] _ in
                // 禁用编辑权限
                space.meshOTADistribution = true
                NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
                self?.dismiss(animated: true)
            })]).show()
            
        }else {
            // 开启编辑权限
            if let space = SpaceViewController.currentSpaceVc()?.space, space.meshOTADistribution {
                space.meshOTADistribution = false
                NotificationCenter.default.post(name: .init(spacePermissionChangedNotificaitonName), object: nil)
            }
            self.dismiss(animated: true)
        }
    }
    
    /// 帮助
    @objc private func helpAction() {
        
        //        let  MeshSelectDistributorViewController()
        
        
        let vc = BLEUpgradeInstructionsController()
        let datas: [BLEUpgradeInstructionsController.InstructionsData] = [
            .init(iconName: "server_download", name: "server_firmware".localizedString, message: "server_firmware_message".localizedString + "\n\n", showArrow: true, arrowX: isIPad ? SCRXFrom(170) : SCRXFrom(82), ratio: 0.3),
            .init(iconName: "initiator", name: "initiator".localizedString, message: "initiator_message".localizedString + "\n\n", showArrow: true, arrowX: isIPad ? SCRXFrom(300) : SCRXFrom(149), ratio: 0.17),
            .init(iconName: "single_device", name: "Distributor".localizedString, message: "distributor_message".localizedString + "\n\n", showArrow: true, arrowX: isIPad ? SCRXFrom(440) : SCRXFrom(219), ratio: 0.18),
            .init(iconName: "updatating_nodes", name: "updatating_nodes".localizedString, message: "updatating_nodes_message".localizedString + "\n\n" + "mesh_upgrade_instructions_message".localizedString, showArrow: false, arrowX: 0, ratio: 0.35)
        ]
        vc.title = "mesh_upgrade_instructions".localizedString
        vc.datas = datas
        navigationController?.pushViewController(vc, animated: true)
        // Do any additional setup after loading the view.
    }
    
    private func setupUI() {
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(16)
        flowLayout.minimumInteritemSpacing = 0
        
        refreshControl = UIRefreshControl()
        refreshControl.tintColor = UIColor.lightGray
        refreshControl.addTarget(self, action: #selector(refresh), for: .valueChanged)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.backgroundColor = .clear
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(16), bottom: SCRYFrom(16), right: SCRXFrom(16))
        collectionView.register(MeshFirmwareTypeUpdateViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(7))
        }
        
    }
    
    private func firmwareVersionInfo(firmwareTypeData: FirmwareUpdateTypeData) {
        
        let vc = FirmwareVersionViewController(type: firmwareTypeData)
        vc.localFirmwareData = FirmwareData.load(productId: firmwareTypeData.productId).first
        vc.updateLocalFirmwareDataCallback = {[weak self] updateFirmwareData in
            guard let self = self else { return }
//            firmwareTypeData.targetVersion = updateFirmwareData?.version
//            cell.firmwareTypeData = firmwareTypeData
#if DEBUG
            // 下载/导入重复固件版本包时清空同一个pid下分发者缓存数据（测试马甲包外部版本2.0.0重复升级需要清空缓存重新上传固件到分发者）
            if let firmwareData = updateFirmwareData {
                MeshNetworkManager.instance.realNodes.filter({ $0.productIdentifier == firmwareData.productId && $0.distributionVersion == firmwareData.version }).forEach { node in
                    node.distributionFirmwareID = nil
                    node.distributionFirmwareSize = nil
                    node.distributionIncomingFirmwareMetadata = nil
                    node.savePropertys()
                    if let firmwareDistributionModel = node.firmwareDistributionServerModel {
                        MeshAPI.sendMessage(message: FirmwareDistributionFirmwareDelete(firmwareID: firmwareData.firmwareID), model: firmwareDistributionModel)
                    }
                }
            } 
#endif
            self.setupData()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
}

// MARK: - Navigation

extension MeshFirmwareListViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return firmwareTypeDatas.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! MeshFirmwareTypeUpdateViewCell
        let firmwareTypeData = firmwareTypeDatas[indexPath.row]
        cell.firmwareTypeData = firmwareTypeData
        cell.currentVersionCallback = {[weak self] in
            self?.firmwareVersionInfo(firmwareTypeData: firmwareTypeData)
        }
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let firmwareTypeData = firmwareTypeDatas[indexPath.row]
        if let distributionData = firmwareTypeData.distributorData { // 分发状态
            switch distributionData.distributionState {
            case .none:
                // 未发现可更新设备
                if firmwareTypeData.versionState == .latest {
                    XWHUDManager.showTipHUD("the_latest_version".localizedString, isLineFeed: true)
                    return
                }
                let firmwareData = FirmwareData.load(productId: firmwareTypeData.productId).first
                let vc = MeshSelectDistributorViewController(productId: firmwareTypeData.productId, firmwareData: firmwareData)
                navigationController?.pushViewController(vc, animated: true)
                
            case .await:
                if let distributionNode = distributionData.distributionNode {
                    let vc = MeshSelectUpgradeDevicesViewController(distributorNode: distributionNode, distributorData: distributionData)
                    navigationController?.pushViewController(vc, animated: true)
                }else {
                    let firmwareData = FirmwareData.load(productId: firmwareTypeData.productId).first
                    let vc = MeshSelectDistributorViewController(productId: firmwareTypeData.productId, firmwareData: firmwareData)
                    navigationController?.pushViewController(vc, animated: true)
                }
            case .updating:
               fallthrough
            case .waitingInstall:
                fallthrough
            case .complete:
                fallthrough
            case .failure:
                let vc = MeshFirmwareUpdateViewController(distributorData: distributionData)
                vc.distributorDataUpdateCallback = { data in
                    firmwareTypeData.distributorData = data
                    collectionView.reloadItems(at: [indexPath])
                }
                navigationController?.pushViewController(vc, animated: true)
            }
        }else { // 未在分发状态
            // 未发现可更新设备
            if firmwareTypeData.versionState == .latest {
                XWHUDManager.showTipHUD("the_latest_version".localizedString, isLineFeed: true)
                return
            }
            let firmwareData = FirmwareData.load(productId: firmwareTypeData.productId).first
            let vc = MeshSelectDistributorViewController(productId: firmwareTypeData.productId, firmwareData: firmwareData)
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

