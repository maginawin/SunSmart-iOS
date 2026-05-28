//
//  SiteViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

let SiteStateChangeNotificationName = "siteStateChangeNotification"
let spacesRefreshChangeNotificationName = "spacesRefreshChangeNotification"
let siteAddGatewaysDataNotificaitonName = "siteAddGatewaysDataNotificaiton"
let siteGatewayDataChangedNotificaitonName = "siteGatewayDataChangedNotificaiton"

class SiteViewController: UIViewController {

    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: PopGestureScrollView!
    private var allSpacesCollectionView: UICollectionView!
    private var allSpacesFlowLayout: UICollectionViewFlowLayout!
    
    private var favouritesCollectionView: UICollectionView!
    private var favouritesFlowLayout: UICollectionViewFlowLayout!
    private var allSpacesNoInternetView: NoInternetHeaderView?
    private var favouritesNoInternetView: NoInternetHeaderView?
    
    private var gatewayListView: GatewayListView!
    private var gatewayStatusView: SiteGatewayStatusView!
    
    private let noInternetHeight = SCRYFrom(54)
    
    private var addSpaceBtn: UIButton!
    
    private var allSpaces: [SpaceData] = []
    private var favouriteSpaces: [SpaceData] = []
    
    /// 所有space刷新
    private var allSpacesRefreshControl: UIRefreshControl!
    /// 喜欢的space刷新
    private var favouritesRefreshControl: UIRefreshControl!
    
    /// 每行显示几个item
    private let itemRowCount: Int = isIPad ? 2 : 1
    
    let site: SiteData
    /// 是否添加场所进入
    var addSite: Bool
    /// 进入space，space列表加载完成后自动跳转进入对应space页面
    var enterSpaceId: String?
    
//    #if DEBUG  // 测试环境展示地址数量
    private var allDeviceAddressNum: Int = 0
    private var usedDeviceAddressNum: Int = 0
    
    private var allGroupAddressNum: Int = 0
    private var usedGroupAddressNum: Int = 0
    
    private var allSceneAddressNum: Int = 0
    private var usedSceneAddressNum: Int = 0
    
    private var recycleAddressNum: Int = 0
//    #endif
    
    private var reloadData: Bool = false
    
    private var networkableObservation: NSKeyValueObservation?

    /// site内网关list
    private var gatewayModels: [Gateway] = []
    /// site内显示的网关list
    private var showGatewayModels: [Gateway] = []
    
    private var allSpaceSelectGatewayId: String?
    private var favouriteSpaceSelectGatewayId: String?
    
    private weak var allSpaceGatewayHeaderView: SiteGatewayHeaderView?
    private weak var favouriteSpaceGatewayHeaderView: SiteGatewayHeaderView?
    
    init(site: SiteData, addSite: Bool = false) {
        self.site = site
        self.addSite = addSite
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        title = site.name
        view.backgroundColor = Background_Color
        navigationController?.navigationBar.barTintColor = .clear
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(backAction)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))

        setupUI()
        
        allSpaces = site.spaces
        favouriteSpaces = allSpaces.filter({ $0.isFavourite })

        addNotificationObserver()
        
//        updateEmptyView()
        updateNoInternetUI()
        
        if NetworkRequest.shared.networkable && site.uploadCloud {
            loadSiteRequest()
        }
        
        MeshLibManager.manager.publishModelIDs = []// .genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLServerModelId
        MeshLibManager.manager.publishTimeModelIDs = []
        MeshLibManager.manager.publishModeloOnly = true
        MeshLibManager.manager.groupSubscriptionModelIDs = [.genericOnOffServerModelId, .lightLightnessServerModelId, .lightCTLTemperatureServerModelId, .lightCTLServerModelId, .sensorServerModelId, .lightLCServerModelId]
        MeshLibManager.manager.subElementGroupSubscriptionModelIDs = [.lightCTLTemperatureServerModelId, .lightLCServerModelId]
        #if DEBUG
        MeshLibManager.manager.showLogs = [.network, .access, .lowerTransport, .upperTransport, .proxy, .bearer]
        #endif
        MeshNodeHeartbeatManager.shared.openHeartbeatShare = false
        
//        MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.site.meshUUID, subNetwork: self.allSpaces.first?.meshNetworkKey, connected: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (navigationController as? NavigationViewController)?.navigationDelegate = nil

        setupData()
        SpaceDebugUARTManager.shared.activateSite(site.id)

        if reloadData {
            reloadData = false
//            allSpaces = site.spaces
//            favouriteSpaces = allSpaces.filter({ $0.isFavourite })
            loadSiteRequest()
        }
//        self.allSpacesCollectionView.reloadData()
//        self.favouritesCollectionView.reloadData()
//        self.updateEmptyView()
        
        CloudSynchronizationManager.shared.delegate = self
    }

    @objc private func backAction() {
        SpaceDebugUARTManager.shared.endSite(site.id)
        if let navigationController, navigationController.viewControllers.first != self {
            navigationController.popViewController(animated: true)
        } else {
            dismiss(animated: true)
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if addSite {
            addSite = false
            addSpace()
        }
        
        // 读取当前site网络数据
        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString != self.site.meshUUID || !MeshNetworkManager.instance.currentNetworkKey.isPrimary {
            DispatchQueue.global().async {[weak self] in
                guard let self = self else { return }
                MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.site.meshUUID, subNetworkId: self.site.meshNetworkId, connected: false)
                DispatchQueue.main.async {[weak self] in
                    guard let self = self else { return }
                    self.setupData()
                }
            }
        }
        
        if allSpacesCollectionView.firstShowFlashScrollIndicators {
            allSpacesCollectionView.flashScrollIndicatorsIfNeeded()
        }
        if favouritesCollectionView.firstShowFlashScrollIndicators {
            favouritesCollectionView.flashScrollIndicatorsIfNeeded()
        }
        
        updateSyncState()
#if DEBUG
self.updateAddressData()
#endif
//        self.showNavigationBarLoading()
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
//            if self.view.window != nil {
//                self.showNavigationBarFailure()
//            }
//        })
    }
    
    deinit {
//        NetworkRequest.shared.removeObserver(self, forKeyPath: "networkable")
        networkableObservation = nil
        SpaceDebugUARTManager.shared.endSite(site.id)

        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == site.meshUUID && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == site.meshNetworkId {
            MeshLibManager.manager.meshNetworkDisconnect()
        }
//        MeshLibManager.manager.meshNetworkDisconnect()
    }
    
    
//    #if DEBUG
    /// 更新地址数据
    private func updateAddressData() {
        
//        guard let meshNetwork = MeshNetwork.load(meshUUID: self.site.id), let localProvisioner = meshNetwork.localProvisioner else { return }
//
//        var deviceAddressCount = 0
//        localProvisioner.allocatedUnicastRange.forEach({
//            deviceAddressCount += Int(($0.highAddress - $0.lowAddress) + 1)
//        })
//        var groupAddressCount = 0
//        localProvisioner.allocatedGroupRange.forEach({
//            groupAddressCount += Int(($0.highAddress - $0.lowAddress) + 1)
//        })
//        var sceneAddressCount = 0
//        localProvisioner.allocatedSceneRange.forEach({
//            sceneAddressCount += Int(($0.lastScene - $0.firstScene) + 1)
//        })
//
//        var recycleAddressCount = 0
//        MeshAPI.getExclusionAddresses(meshUUID: self.site.id).forEach({
//            recycleAddressCount += $0.addresses.count
//        })
//
//        allDeviceAddressNum = deviceAddressCount
//        usedDeviceAddressNum = deviceAddressCount - MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.site.id)
//
//        allGroupAddressNum = groupAddressCount
//        usedGroupAddressNum = groupAddressCount - MeshAPI.getNumberOfAvailableGroupAddresses(meshUUID: self.site.id)
//
//        allSceneAddressNum = sceneAddressCount
//        usedSceneAddressNum = sceneAddressCount - MeshAPI.getNumberOfAvailableSceneAddresses(meshUUID: self.site.id)
//
//        recycleAddressNum = recycleAddressCount
//
//        self.allSpacesTableView.reloadData()
    }
//    #endif
    
    private func setupData() {
        
        allSpaces = site.spaces
        favouriteSpaces = allSpaces.filter({ $0.isFavourite })
        
        self.gatewayModels = self.loadGatewaysData()
        
        if site.permission == .owner {
            self.showGatewayModels = self.gatewayModels
        }else if allSpaces.contains(where: { $0.permission == .editor }) { // site内是否有可编辑的space
            self.showGatewayModels = self.gatewayModels.filter({ gateway in gateway.associatedSpaces.isEmpty || gateway.associatedSpaces.contains(where: { $0.permission != .none }) })
        }else {
            self.showGatewayModels.removeAll()
        }
        
        if let gatewayId = allSpaceSelectGatewayId, let gateway = showGatewayModels.first(where: { $0.mac == gatewayId }) {
            allSpaces = allSpaces.filter({ space in gateway.associatedSpaces.contains(where: { $0.spaceId == space.id }) })
        }else {
            allSpaceSelectGatewayId = nil
        }
        
        if let gatewayId = favouriteSpaceSelectGatewayId, let gateway = showGatewayModels.first(where: { $0.mac == gatewayId }) {
            favouriteSpaces = favouriteSpaces.filter({ space in gateway.associatedSpaces.contains(where: { $0.spaceId == space.id }) })
        }else {
            favouriteSpaceSelectGatewayId = nil
        }
        
        allSpaces.forEach({ space in
            if let gateway = self.gatewayModels.first(where: { gateway in gateway.associatedSpaces.contains(where: { $0.spaceId == space.id }) }) {
                space.gatewayStatus = gateway.connectStatus == .online ? .online : .offline
            }else {
                space.gatewayStatus = .notBound
            }
        })
        
        self.allSpacesCollectionView.reloadData()
        self.favouritesCollectionView.reloadData()
        self.updateEmptyView()
    }
    
    /// 添加通知监听
    private func addNotificationObserver() {
        
        NotificationCenter.default.addObserver(forName: .init(SiteStateChangeNotificationName), object: nil, queue: nil) {[weak self] _ in
            guard let self = self else { return }
            if self.site.state == .waitDeleted {
                NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
                self.navigationController?.popViewController(animated: true)
            }else {
                if self.view.window != nil {
                    self.reloadData = false
//                    allSpaces = site.spaces
//                    favouriteSpaces = allSpaces.filter({ $0.isFavourite })
                    self.setupData()
                    self.loadSiteRequest()
                }else {
                    self.reloadData = true
                }
            }
        }
        
        /// 刷新spaces列表通知回调
        NotificationCenter.default.addObserver(forName: .init(spacesRefreshChangeNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            if notification.object as? Bool ?? false {
                // 更新缓存数据
                self.site.spaces = SpaceData.load(siteId: site.id)
            }
            self.setupData()
        }
        
        /// 网关添加回调
        NotificationCenter.default.addObserver(forName: .init(siteAddGatewaysDataNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            guard let gatewayDatas = notification.object as? [(node: Node, model: GatewayModel)] else { return }
            gatewayDatas.forEach({ gatewayData in
                gatewayData.model.lastUpdate = Int64(Date().timeIntervalSince1970)
                gatewayData.model.save()
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(gateway: gatewayData.model, node: gatewayData.node), level: .promptly)
            })
            if self.view.window != nil {
                self.reloadData = false
                self.loadSiteRequest()
            }else {
                self.reloadData = true
            }
        }
        
        /// 网关数据更新回调
        NotificationCenter.default.addObserver(forName: .init(siteGatewayDataChangedNotificaitonName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            guard let gateway = notification.object as? Gateway else { return }
            gateway.model.lastUpdate = Int64(Date().timeIntervalSince1970)
            gateway.model.save()
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(gateway: gateway.model, node: gateway.node), level: .promptly)
            if self.view.window != nil {
                self.reloadData = false
                self.setupData()
            }else {
                self.reloadData = true
            }
        }

        // 手机网络状态观察者
        networkableObservation = NetworkRequest.shared.observe(\.networkable, options: [.new], changeHandler: {[weak self] _, _ in
            guard let self = self else { return }
            DispatchQueue.main.async {[weak self] in
                guard let self = self else { return }
                self.updateNoInternetUI()
                if !NetworkRequest.shared.networkable && SRAlertView.getCurrentAlertView() == nil {
                    // 有网络=>无网络
                        SRAlertView(title: "notification".localizedString, message: "phone_network_disconnect".localizedString, actions: [.init(title: "confirm".localizedString)]).show()
                }
            }
        })
        
    }
    
    // MARK: - Request
    /// 获取site数据请求
    @objc private func loadSiteRequest() {
        
        guard self.site.uploadCloud else { // 已上传服务器
            self.allSpacesCollectionView.refreshControl?.endRefreshing()
            self.favouritesCollectionView.refreshControl?.endRefreshing()
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        
        NetworkRequest.shared.request(.siteInfo(siteId: self.site.id)) {[weak self] result in
            guard let self = self else { return }
            self.allSpacesCollectionView.refreshControl?.endRefreshing()
            self.favouritesCollectionView.refreshControl?.endRefreshing()
            
//            let timeinterval = Date().distance(to: startDate)
            
            switch result {
            case .success(let response):
                if let siteData = JSON(response)["data"].dictionaryObject {
//                    let site = SiteData.import(siteJsonData: siteData)
                    Task {[weak self] in

                        guard let self = self else { return }
                        print("导入数据: \(Date().timeIntervalSince1970)")
                        await self.site.update(siteJsonData: siteData)
                        print("导入数据完成: \(Date().timeIntervalSince1970)")
                        guard !Task.isCancelled else { return }
                        // space已提交到服务器，但是本地有但是服务器没有
//                        let deleteSpaces = self.allSpaces.filter({ localSpace in !self.site.spaces.contains(where: { $0.id == localSpace.id }) && localSpace.uploadCloud })
//                        deleteSpaces.forEach({ space in
//                            if space.permission == .editor || space.permission == .visitor {
//                                // 设置space为待删除状态
//                                space.state = .waitDeleted
//                                space.save()
//                            }
//                        })
                        // 需要回收地址的space
                        let recyclingSpaces = self.site.spaces.filter({ $0.state == .waitDeleted  && !$0.releaseAddress })
                        if recyclingSpaces.count > 0 {
                            recyclingSpaces.forEach({
                                $0.releaseAddress = true
                                $0.save()
                            })
                            let addressData = await self.site.getRecycleAddressData(unbindSpaces: recyclingSpaces)
                            if let recycleAddressData = self.site.recycleAddressData {
                                self.site.recycleAddressData = recycleAddressData + addressData
                            }else {
                                self.site.recycleAddressData = addressData
                            }
                            self.site.save()
//                            self.recyclingAddressRequest(delete: false, recyclingSpaces: recyclingSpaces)
                        }
                        // 判断site内是否有需要回收的地址
                        if !(self.site.recycleAddressData?.isEmpty ?? true) {
                            try? await self.siteRecyclingAddressRequest(site: self.site)
                        }
                        
                        self.title = self.site.name
                        
//                        self.gatewayModels = self.loadGatewaysData()
                        
//                        self.site.save(allData: true)
//                        // 未提交到服务器的本地数据
//                        let localSpaces = self.allSpaces.filter({ localSpace in !self.site.spaces.contains(where: { $0.id == localSpace.id }) && !localSpace.uploadCloud })
//                        self.site.spaces.append(contentsOf: localSpaces)
//                        self.site.spaces.append(contentsOf: deleteSpaces)
//                        self.site.spaces.sort(by: { $0.create < $1.create })
                        if MeshNetworkManager.instance.meshNetwork?.uuid.uuidString != self.site.meshUUID || !MeshNetworkManager.instance.currentNetworkKey.isPrimary {
                            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.site.meshUUID, subNetworkId: self.site.meshNetworkId, connected: false)
                        }
                        self.setupData()
                    #if DEBUG
                        self.updateAddressData()
                    #endif
                        
                        XWHUDManager.hideInView(with: self.view)
                        
                        if self.view.window != nil && self.site.localAddress == nil { // 申请地址
                            self.requestMobileAddress()
                        }else {
                            // 自动进入space页面
                            if let spaceId = self.enterSpaceId, let space = self.allSpaces.first(where: { $0.id == spaceId }) {
                                self.enterSpaceId = nil
                                self.selectSpaceAction(space: space)
                            }
                        }
                        // 是否需要同步数据
                        let syncSpaces = self.site.spaces.filter({ $0.needUploadCloud })
                        if self.site.needUploadCloud || syncSpaces.count > 0 {
                            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: self.site, syncSpaces: syncSpaces), level: .custom(interval: 1))
                        }
                    }
                }else {
                    XWHUDManager.hideInView(with: self.view)
                }
            case .failure(let error):
                XWHUDManager.hideInView(with: self.view)
                if error == .noSitePermission || error == .userUnauthorized { // 无权限
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    if self.site.state == .normal {
                        self.site.state = .waitDeleted
                        self.site.save()
                    }
                    if self.site.permission == .owner { // 权限已转让
                        //通知site列表刷新数据
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                            self?.navigationController?.popViewController(animated: true)
                            NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
                        }
                    }else { // 权限被回收
                        Task {
                            if self.site.spaces.isEmpty {
                                self.site.delete()
                                //通知site列表刷新数据
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                                    self?.navigationController?.popViewController(animated: true)
                                    NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: nil)
                                }
                            }else {
                                self.site.spaces.forEach({
                                    if $0.state == .normal {
                                        $0.state = .waitDeleted
                                        $0.releaseAddress = true
                                        $0.save()
//                                        self.reloadSpaceData($0)
                                    }
                                })
                                self.gatewayModels.forEach { gateway in
                                    gateway.associatedSpaces.forEach {
                                        if $0.permission == .editor {
                                            $0.permission = .permissionLoss
                                        }else {
                                            $0.permission = .none
                                        }
                                    }
                                }
                                self.allSpacesCollectionView.reloadData()
                                self.favouritesCollectionView.reloadData()
                                self.site.recycleAddressData = await self.site.getRecycleAddressData(unbindSpaces: self.site.spaces)
                                self.site.save()
                            }
                            
                            // 判断site内是否有需要回收的地址
                            if !(self.site.recycleAddressData?.isEmpty ?? true) {
                                try? await self.siteRecyclingAddressRequest(site: self.site)
                            }
                        }
                    }
                    
                }else if error == .resourceNotFound, self.site.permission == .owner { // 找不到资源，说明服务器切换后新的服务器未上传site
                    self.site.lastUploadCloudTimestamp = nil
                    self.site.save()
                    CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: self.site, syncSpaces: self.site.spaces), level: .custom(interval: 0.5))
                }else {
                    if self.site.spaces.isEmpty && self.site.spaceCount != self.site.spaces.count {
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }else {
                        // 自动进入space页面
                        if let spaceId = self.enterSpaceId, let space = self.allSpaces.first(where: { $0.id == spaceId }) {
                            self.enterSpaceId = nil
                            //                        self.intoSpace(space: space)
                            self.selectSpaceAction(space: space)
                        }
                    }
                }
            }
               
        }
    }
    
    /// 删除site网络请求
    private func deleteSiteReqeust() {
        
        // 是否有同步操作正在进行,进行中则取消任务
        CloudSynchronizationManager.shared.cancelSynchronizationHandle(site: self.site)
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.siteDelete(siteId: self.site.id)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                // 删除本地数据
                self.site.delete()
                self.navigationController?.popViewController(animated: true)
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
            case .failure(let error): // 删除失败，无网络/space存在编辑者
                if error == .editorBeingUsedSpace {
                    XWHUDManager.showErrorTipHUD("site_delete_have_editor_message".localizedString)
                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
//                XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
            }
        }
    }
    
    /// 删除space网络请求
    private func deleteSpaceRequest(space: SpaceData) {
        
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.spaceDelete(siteId: self.site.id, spaceId: space.id)) {[weak self] result in
            XWHUDManager.hide()
            switch result {
            case .success(_):
                // 删除本地数据
                self?.deleteSpace(space: space)
                // 删除网关内关联的space并同步到服务器
                if let gateway = self?.gatewayModels.first(where: { $0.mac == space.relevanceGatewayId }) {
                    gateway.associatedSpaces.removeAll(where: { $0.spaceId == space.id })
                    gateway.lastUpdate = Int64(Date().timeIntervalSince1970)
                    gateway.save()
                    CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(gateway: gateway.model, node: gateway.node), level: .promptly)
                }
                
            case .failure(let error): // 删除失败，无网络/space存在编辑者
                if error == .editorBeingUsedSpace {
                    XWHUDManager.showErrorTipHUD("space_delete_have_editor_message".localizedString)
                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
        }
    }
    
    /// 获取space数据
    private func loadSpaceReqeust(space: SpaceData, verificationPassword: String? = nil, callback: ((Bool)->Void)? = nil) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id, password: verificationPassword ?? space.authorizationPassword)) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let spaceData = JSON(response)["data"].dictionaryObject {
                    Task {
                        await space.update(spaceJsonData: spaceData)
                        if verificationPassword != nil { // 验证通过
                            // 缓存密码
                            space.authorizationPassword = verificationPassword
                            space.requiresPasswordVerification = false
                            self.reloadGatewaySpacePermissionState(space: space)
                        }
                        space.save()
                        self.reloadSpaceData(space)
                        XWHUDManager.hide()
                        if callback != nil {
                            callback?(true)
                        }else {
                            self.intoSpace(space: space)
                        }
                    }
                }else {
                    XWHUDManager.hide()
                    if callback != nil {
                        callback?(false)
                    }else {
                        self.intoSpace(space: space)
                    }
                }
            case .failure(let error):
                XWHUDManager.hide()
                
                switch error {
                case .incorrectPassword:  // 密码错误
                    if verificationPassword != nil { // 正在输入密码验证
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }else { // 使用旧密码验证并发现错误后，弹出输入密码重新验证
                        self.verificationSpacePassword(space: space, callback: callback)
                        if !space.requiresPasswordVerification { // 缓存密码需要验证
                            space.requiresPasswordVerification = true
                            space.save()
                            self.reloadSpaceData(space)
                        }
                        self.reloadGatewaySpacePermissionState(space: space)
                    }
                case .noSpacePermission, .userUnauthorized: // 无权限
                    if space.permission == .editor || space.permission == .visitor {
                        // 设置space为待删除状态
                        space.state = .waitDeleted
                        space.save()
                        self.reloadSpaceData(space)
                        self.reloadGatewaySpacePermissionState(space: space)
                    }
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                default:
                    if verificationPassword != nil { // 正在输入密码验证
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }else {
                        if space.meshNetworkId.isEmpty { // 子网密钥未更新
                            XWHUDManager.showErrorTipHUD(error.localizedDescription)
                        }else {
                            if callback != nil {
                                callback?(false)
                            }else {
                                self.intoSpace(space: space)
                            }
                        }
                    }
                }
            }
            
        }
        
    }
    
    /// 申请手机地址请求
    private func requestMobileAddress() {
//        if showHUD {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
//        }
        NetworkRequest.shared.request(.applyAddress(siteId: site.id, number: 1)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let provisionerData = JSON(response)["data"]["provisioner"].dictionaryObject {
//                    self.site.insetProvisioner(provisionerData: ["device": addresses])
                    self.site.setProvisioner(provisionerData: provisionerData)
                    // 访客权限不可以提交site
                    if self.site.localAddress != nil && self.site.spaces.contains(where: { $0.permission != .visitor }) {
                        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: self.site), level: .promptly)
                    }
                #if DEBUG
                    self.updateAddressData()
                #endif
                }
            case .failure(let error): // 申请手机地址失败
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    /// 加载网关list
    private func loadGatewaysData() -> [Gateway] {
        
        // space列表内没有编辑权限
//        guard allSpaces.contains(where: { $0.canEditing }) else {
//            return []
//        }
        
        
        let gatewayModels = GatewayModel.load(siteId: site.id).compactMap({ Gateway.resolve(model: $0) })
//        var showGatewayModels = gatewayModels
//        if site.permission == .visitor { // 如果不是site的创建者，则判断网关是否有关联space，如果有则判断是否有操作权限
//            showGatewayModels = gatewayModels.filter { gateway in
//                gateway.associatedSpaces.isEmpty || gateway.associatedSpaces.contains(where: { $0.permission == .editor || $0.permission == .permissionException })
//            }
//        }
//        allSpaceSelectGatewayId = nil
//        favouriteSpaceSelectGatewayId = nil
        
        gatewayModels.forEach { gateway in
            if let space = self.allSpaces.first(where: { $0.relevanceGatewayId == gateway.mac }), space.gatewayStatus != .notBound {
                if space.gatewayStatus == .online {
                    gateway.connectStatus = .online
                }else {
                    if gateway.activate {
                        gateway.connectStatus = .offline
                    }else {
                        gateway.connectStatus = .inactive
                    }
                    if let lastOnline = space.gatewayLastOnline {
                        gateway.lastOnlineTime = String.dateConvert(timestamp: "\(lastOnline)", dateFormat: "yyyy-MM-dd HH:mm")
                    }
                }
            }else {
                if gateway.activate {
                    gateway.connectStatus = .offline
                }else {
                    gateway.connectStatus = .inactive
                }
            }
        }
        
        return gatewayModels
    }
    
    // MARK: - Action
    
    @objc private func moreClick() {

//        let vc = DeviceDongleViewController(dongleData: nil)
//        present(NavigationViewController(rootViewController: vc), animated: true)
//        return
        
        
        let touchCenterX = view.width - navigationRightItemMargin - 15

        var items: [MenuPopView.MenuItem] = []
        
        if site.permissionOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "edit"), title: "edit_site".localizedString, tapItemBack: {[weak self] item in
                self?.editSite()
            }))
        }
        
        if site.permissionOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete_site".localizedString, tapItemBack: {[weak self] item in
                self?.deleteSite()
            }))
        }
        
        items.append(.init(icon: UIImage(named: "menu_share"), title: "share_authoority".localizedString, tapItemBack: {[weak self] _ in
            self?.share()
        }))
        
        if site.permissionOperates.contains(.transfer) {
            items.append(.init(icon: UIImage(named: "menu_transfer_site"), title: "transfer_site".localizedString, tapItemBack: {[weak self] _ in
                self?.transferSite()
            }))
        }
        
        if self.showGatewayModels.count > 0 {
            if site.permissionOperates.contains(.restoreDevice) {
                items.append(.init(icon: UIImage(named: "menu_restore_device"), title: "restore_device".localizedString, tapItemBack: {[weak self] _ in
                    self?.restoreDevice()
                }))
            }
            if site.permissionOperates.contains(.firmwareUpdate) {
                items.append(.init(icon: UIImage(named: "menu_firmware_update"), title: "Firmware_update".localizedString, tapItemBack: {[weak self] _ in
                    self?.firmwareUpdate()
                }))
            }
        }
        
//        items.append(.init(icon: UIImage(named: "energy_export")?.withTintColor(.white), title: "Import Space", tapItemBack: {[weak self] _ in
//            self?.importSpace()
//        }))
        
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: touchCenterX, y: (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight)), menuWidth: SCRXFrom(154))
    }
    
    /// 编辑场所
    private func editSite() {
        
        var imageNames: [String] = []
        for id in 1...28 {
            imageNames.append("site_\(id)")
        }
        let vc = InfoEditViewController(name: site.name, imageNames: imageNames, selectImageIndex: max(site.imageId - 1, 0), columnNum: 4)
        vc.nameEditChangedCallback = {[weak self] name in
            return SiteData.isTautonym(siteName: name) && name != self?.site.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            self.site.name = name
            self.site.imageId = imageId + 1
            self.site.lastUpdate = Int64(Date().timeIntervalSince1970)
            self.site.save()
            self.title = name
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .normal)
            return true
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除场所
    private func deleteSite() {
        
        // 上传到云端数据删除需有网络
        if !NetworkRequest.shared.networkable && site.uploadCloud {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "alert_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 场所下面空间内存在设备
            if let space = self.site.spaces.first(where: { $0.deviceCount > 0 }) {
                XWHUDManager.showTipHUD("site_delete_have_devies_message".localizedString, isLineFeed: true)
            }else { // 场所下空间未存在设备
                // site已上传到云端
                if self.site.uploadCloud {
                    // 删除site网络请求
                    self.deleteSiteReqeust()
                }else {
                    
                    // 是否有同步操作正在进行,进行中则取消任务
                    CloudSynchronizationManager.shared.cancelSynchronizationHandle(site: self.site)
                    
                    // 模拟删除过程
                    XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                        XWHUDManager.hide()
                        guard let self = self else { return }
                        // 删除本地数据
                        self.site.delete()
                        self.navigationController?.popViewController(animated: true)
                        NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                    }
                }
            }
            
        })]).show()
    }

    /// 添加空间
    @objc private func addSpace() {
        
//        let vc = BleFirmwareUpdateViewController()
//
//        present(NavigationViewController(rootViewController: vc), animated: true)
//
//        return
        
        var imageNames: [String] = []
        for id in 1...24 {
            imageNames.append("space_picture_\(id)")
        }
        let columnNum = isIPad ? 4 : 2
        let vc = InfoEditViewController(name: SpaceData.getNextSpaceName(siteId: site.id), imageNames: imageNames, selectImageIndex: 0, columnNum: columnNum, isAdd: true)
        vc.itemHeight = isIPad ? SCRYFrom(104) : nil
        vc.title = "add_space".localizedString
        vc.nameEditChangedCallback = {[weak self] name in
            guard let self = self else { return false }
            return SpaceData.isTautonym(spaceName: name, siteId: self.site.id)
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true  }
            
            guard let space = self.site.addSpace(name: name, imageId: imageId + 1) else {
                XWHUDManager.showErrorTipHUD("\("failed".localizedString)!")
                return false
            }
            // site已上传服务器
            if site.uploadCloud {
                // 添加space
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .addSpaces(site: site, spaces: [space]), level: .normal)
            }else {
                // 未上传服务器，site、space一起上传
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: .normal)
            }
            if self.allSpaceSelectGatewayId == nil {
                self.allSpaces.append(space)
                if self.allSpaces.count == 1 {
                    self.allSpacesCollectionView.reloadData()
                }else {
                    let insertPath = IndexPath(row: self.allSpaces.count - 1, section: 0)
                    self.allSpacesCollectionView.insertItems(at: [insertPath])
                    self.allSpacesCollectionView.scrollToItem(at: insertPath, at: .bottom, animated: true)
                }
                self.updateEmptyView()
            }
            return true
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 编辑空间
    private func editSpace(space: SpaceData) {
        
        var imageNames: [String] = []
        for id in 1...24 {
            imageNames.append("space_picture_\(id)")
        }
        let columnNum = isIPad ? 4 : 2
        let vc = InfoEditViewController(name: space.name, imageNames: imageNames, selectImageIndex: max(space.imageId - 1, 0), columnNum: columnNum)
        vc.itemHeight = isIPad ? SCRYFrom(104) : nil
        vc.nameEditChangedCallback = { name in
            return SpaceData.isTautonym(spaceName: name, siteId: space.siteId) && name != space.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            space.name = name
            space.imageId = imageId + 1
            space.lastUpdate = Int64(Date().timeIntervalSince1970)
            space.save()
            
            // site已上传服务器
            if site.uploadCloud {
                // 同步space
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .normal)
            }else {
                // 未上传服务器，site、space一起上传
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: .normal)
            }
            self.reloadSpaceData(space)
            return true
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除space弹窗
    private func showDeleteSpaceAlert(space: SpaceData) {
        
        SRAlertView(title: "notification".localizedString, message: "alert_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 存在设备则不能删除
            if space.deviceCount > 0 {
                XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
            }else { // 场所下空间未存在设备
                // 是否有同步操作正在进行,进行中则取消任务
                CloudSynchronizationManager.shared.cancelSynchronizationHandle(space: space)
                
                if space.uploadCloud { // space上传到云端，需要网络才能删除
                    self.deleteSpaceRequest(space: space)
                }else {
                    self.deleteSpace(space: space)
                }
            }
            
        })]).show()
        
    }
    

    /// 删除空间
    private func deleteSpace(space: SpaceData) {
        
        //            self.site.lastUpdate = Int64(Date().timeIntervalSince1970)
        space.delete()
        
        if space.permission == .owner, let gateway = self.gatewayModels.first(where: { $0.associatedSpaces.contains(where: { $0.spaceId == space.id }) }) {
            gateway.associatedSpaces.removeAll(where: { $0.spaceId == space.id })
            gateway.save()
        }
        
        self.site.spaces.removeAll(where: { $0.id == space.id })
        // 删除数据
//        var index: Int?
//        var currentCollectionView: UICollectionView?
//        var otherCollectionView: UICollectionView?
//        if self.segmentedControl.selectedIndex == 0 {
//            index = allSpaces.firstIndex(where: { $0.id == space.id })
//            currentCollectionView = allSpacesCollectionView
//            otherCollectionView = favouritesCollectionView
//        }else {
//            index = favouriteSpaces.firstIndex(where: { $0.id == space.id })
//            currentCollectionView = favouritesCollectionView
//            otherCollectionView = allSpacesCollectionView
//        }
        self.allSpaces.removeAll(where: { $0.id == space.id })
        self.favouriteSpaces.removeAll(where: { $0.id == space.id })
        if space.gatewayStatus == .notBound {
//            if let index = index, let collectionView = currentCollectionView {
//                collectionView.deleteItems(at: [IndexPath(row: index, section: 0)])
//                otherCollectionView?.reloadData()
//            }else {
                self.allSpacesCollectionView.reloadData()
                self.favouritesCollectionView.reloadData()
//            }
            self.updateEmptyView()
        }else {
            self.setupData()
        }
    }
    
    
    /// 分享&权限
    private func share() {
        
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        if let handle = CloudSynchronizationManager.shared.getSiteCurrentSyncHandle(site) {
            // site正在排队
            if case .wait = handle.state {
                XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
                // 修改任务等级为紧急
                CloudSynchronizationManager.shared.setSynchronizationHandleLevel(handle: handle, level: .promptly)
                return
            }
            // site正在同步中
            if case .inProgress = handle.state {
                XWHUDManager.showTipHUD("syncing_data_message".localizedString, isLineFeed: true)
                return
            }
        }
        // site下spaces未上传最新数据
        let needUploadSpaces = site.spaces.filter({ $0.needUploadCloud })
        // site或者site下spaces需要提交数据
        if site.needUploadCloud || needUploadSpaces.count > 0 {
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: needUploadSpaces), level: .promptly)
            XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
            return
        }
        
        let vc = ShareAuthorityViewController(site: site, type: .share)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 转让Site
    private func transferSite() {
    
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        if let handle = CloudSynchronizationManager.shared.getSiteCurrentSyncHandle(site) {
            // site正在排队
            if case .wait = handle.state {
                XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
                // 修改任务等级为紧急
                CloudSynchronizationManager.shared.setSynchronizationHandleLevel(handle: handle, level: .promptly)
                return
            }
            // site正在同步中
            if case .inProgress = handle.state {
                XWHUDManager.showTipHUD("syncing_data_message".localizedString, isLineFeed: true)
                return
            }
        }
        // site下spaces未上传最新数据
        let needUploadSpaces = site.spaces.filter({ $0.needUploadCloud })
        // site或者site下spaces需要提交数据
        if site.needUploadCloud || needUploadSpaces.count > 0 {
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: needUploadSpaces), level: .promptly)
            XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
            return
        }
        
        var networkApi: NetowrkReqeustApi!
        // 有site转让code则读取之前的数据
        if let transferCode = site.transferCode {
            networkApi = .shareInfo(shareId: transferCode)
        }else { // 第一次转让site则新建一个记录
            if site.transferPassword == nil || site.transferPassword?.isEmpty ?? true {
                site.transferPassword = String.generateRandomNumberString()
                site.save()
            }
            networkApi = .transferSite(siteId: site.id, password: site.transferPassword!)
        }
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(networkApi) {[weak self] result in
            
            guard let self = self else {
                XWHUDManager.hide()
                return
            }
            switch result {
            case .success(let response):
                guard let code = JSON(response)["data"]["token"].string else {
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                    return
                }
                // 转让码
                if self.site.transferCode != code {
                    self.site.transferCode = code
                    self.site.save()
                }
                // 转让密码
                if let password = JSON(response)["data"]["transPasswd"].string {
                    if self.site.transferPassword != password {
                        self.site.transferPassword = password
                        self.site.save()
                    }
                }
                
                let vc = SharingSettingViewController(type: .transferSite(site: site))
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                self.present(NavigationViewController(rootViewController: vc), animated: true) {
                    XWHUDManager.hide()
                }
            case .failure(let error):
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 恢复site设备
    private func restoreDevice() {
        
        let vc = DeviceRestoreViewController(
            site: site,
            space: nil,
            restoreMode: .default,
            restoreFilter: .gatewaysOnly
        )
        vc.deviceRestoreCallback = {[weak self] nodes, _ in
            let gateways = nodes.compactMap({ GatewayModel.resolve(node: $0) })
            self?.gatewaysSyncToCloud(gateways)
            self?.setupData()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 固件升级
    private func firmwareUpdate() {
        
        let gateways = self.showGatewayModels.filter({ $0.associatedSpaces.contains(where: { $0.permission == .editor }) })
        let gatewayNodes = gateways.compactMap({ $0.node })
        let vc = BleFirmwareUpdateViewController(site: site, space: nil, nodes: gatewayNodes)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        vc.deviceUpdateCompleteCallback = {[weak self] nodes in
            let successGateways = gateways.filter({ gateway in nodes.contains(where: { $0.primaryUnicastAddress == gateway.node.primaryUnicastAddress }) })
            self?.gatewaysSyncToCloud(successGateways)
            self?.setupData()
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
//        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 分享space
    private func shareSpace(_ space: SpaceData) {
        
        guard NetworkRequest.shared.networkable else {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        if space.permission != .owner && space.requiresPasswordVerification {
//            XWHUDManager.showTipHUD("space_password_overdue".localizedString)
            verificationSpacePassword(space: space) {[weak self] result in
                if result {
                    self?.shareSpace(space)
                }
            }
            return
        }
        
        if let handle = CloudSynchronizationManager.shared.getSpaceCurrentSyncState(space) {
            // site正在排队
            if case .wait = handle.state {
                XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
                // 修改任务等级为紧急
                CloudSynchronizationManager.shared.setSynchronizationHandleLevel(handle: handle, level: .promptly)
                return
            }
            // site正在同步中
            if case .inProgress = handle.state {
                XWHUDManager.showTipHUD("syncing_data_message".localizedString, isLineFeed: true)
                return
            }
        }
        // space需要提交数据
        if space.needUploadCloud {
            
            // site已上传服务器
            if site.uploadCloud {
                // 同步space
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .promptly)
            }else {
                // 未上传服务器，site、space一起上传
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: .promptly)
            }
            XWHUDManager.showTipHUD("sync_data_unfinished_message".localizedString, isLineFeed: true)
            return
        }
        
        var networkApi: NetowrkReqeustApi!
        // 有site转让code则读取之前的数据
        if let shareCode = space.shareCode { // , space.editorPassword != nil || space.permission == .editor
            networkApi = .shareInfo(shareId: shareCode)
        }else {
            // 还没有设置编辑者密码
            if space.permission == .owner && space.editorPassword == nil {
                space.editorPassword = String.generateRandomNumberString()
            }
            networkApi = .spaceShare(space: space)
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(networkApi) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                guard let code = JSON(response)["data"]["token"].string else {
                    XWHUDManager.hide()
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                    return
                }
                var spaceSave = false
                // 更新owner数据
                if let ownerData = JSON(response)["data"]["space"]["owner"].dictionaryObject {
                    if let userId = ownerData["userId"] as? String, let userName = ownerData["username"] as? String {
                        if space.owner?.uuid != userId {
                            space.owner = .init(name: userName, uuid: userId)
                            spaceSave = true
                        }
                    }
                }
                
                // 更新editor数据
                if let editorData = JSON(response)["data"]["space"]["editor"].dictionaryObject {
                    if let userId = editorData["userId"] as? String, let userName = editorData["username"] as? String {
                        if space.editor?.uuid != userId {
                            space.editor = .init(name: userName, uuid: userId)
                            spaceSave = true
                        }
                    }else {
                        if space.editor != nil {
                            space.editor = nil
                            spaceSave = true
                        }
                    }
                }
                
                if space.permission == .owner, let editorPassword = JSON(response)["data"]["space"]["editorPasswd"].string, space.editorPassword != editorPassword {
                    space.editorPassword = editorPassword
                    spaceSave = true
                }
                
                if let visitorPassword = JSON(response)["data"]["space"]["visitorPasswd"].string {
                    if space.vistorPassword ?? "" != visitorPassword {
                        if visitorPassword.isEmpty {
                            space.vistorPassword = nil
//                                space.vistorPasswordEnable = false
                        }else {
                            space.vistorPassword = visitorPassword
//                                space.vistorPasswordEnable = true
                        }
                        spaceSave = true
                    }
                }
                
                if case .spaceShare = networkApi {
                    spaceSave = true
                }
                // 邀请码
                if space.shareCode != code {
                    space.shareCode = code
                    spaceSave = true
                }
                if spaceSave {
                    space.save()
                    self.reloadSpaceData(space)
                }
                
                let vc = SharingSettingViewController(type: .space(site: self.site, space: space))
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                self.present(NavigationViewController(rootViewController: vc), animated: true) {
                    XWHUDManager.hide()
                }
            case .failure(let error):
                if error == .resourceNotFound {
                    space.shareCode = nil
                    space.save()
                }
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    
    }
    
    private func exportSpace(_ space: SpaceData) {
        Task {
            let spaceJsonDict = await space.export()
            let name = space.name
            guard let data = try? JSONSerialization.data(withJSONObject: spaceJsonDict) else {
                XWHUDManager.showErrorTipHUD("导出数据失败")
                return
            }
            
            XWHUDManager.showCustomHUD(withMessage: nil, view: view)
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                guard let self = self else { return }
                // 文件名称 site名称+space名称
                let name = "\(self.site.name)_\(name)"
                
                let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).json")
                try? data.write(to: fileURL)
                
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    
                    let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                    // 适配 iPad
                    if let popoverController = controller.popoverPresentationController {
                        // 设置 sourceView（可以是按钮或视图）
                        popoverController.sourceView = self.view
                        
                        // 设置 sourceRect（浮层的锚点位置）
                        popoverController.sourceRect = CGRect(x: self.view.bounds.midX, y: self.view.bounds.midY, width: 0, height: 0)
                        
                        // 或者设置 barButtonItem（如果是导航栏按钮）
                        // popoverController.barButtonItem = self.shareButton
                    }
                    controller.completionWithItemsHandler = { type, success, items, error in
                        if success {
                            XWHUDManager.showSuccessTipHUD("done!".localizedString)
                        }
                    }
                    self.present(controller, animated: true)
                    
                    XWHUDManager.hide()
                }
            }
            
            
        }
    }
    
    private func importSpace() {
        
        let picker = UIDocumentPickerViewController(documentTypes: ["public.data", "public.content"], in: .import)
        picker.delegate = self
        present(picker, animated: true, completion: nil)
    }
    
    /// 解绑space
    private func unbindSpace(_ space: SpaceData) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        
        // 是否有同步操作正在进行,进行中则取消任务
        CloudSynchronizationManager.shared.cancelSynchronizationHandle(space: space)
        // 数据有更新没提交,先提交完成数据再解绑
        if space.permission == .editor && space.needUploadCloud {
            Task {
                let spaceData = await space.export()
                // 数据不完整则不上传直接解绑
                if spaceData.isEmpty || !spaceData.keys.contains("netKey") {
                    space.lastUploadCloudTimestamp = space.lastUpdate
                    self.unbindSpace(space)
                    return
                }
                NetworkRequest.shared.request(.spaceUpload(siteId: space.siteId, spaceData: spaceData)) {[weak self] result in
                    switch result {
                    case .success(_):
                        space.lastUploadCloudTimestamp = space.lastUpdate
                        self?.unbindSpace(space)
                    case .failure(let error):
                        XWHUDManager.hide()
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }
                }
            }
            return
        }
        
        Task {
            let recycleData = await site.getRecycleAddressData(unbindSpaces: [space])
            
            let networkApi: NetowrkReqeustApi = .unbindSpaces(siteId: site.id, spaceIds: [space.id], recycleDeviceAddresses: recycleData.deviceAddresses, recycleGroupAddresses: recycleData.groupAddresses, recycleSceneAddresses: recycleData.sceneAddresses, exclusions: recycleData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) }), provisionerData: recycleData.provisionerData)
            
            NetworkRequest.shared.request(networkApi) {[weak self] result in
                XWHUDManager.hide()
                
                guard let self = self else { return }
                switch result {
                case .success(_):
                    //                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                    // 删除回收的地址
                    self.site.deleteProvisionerAddress(deviceAddresses: recycleData.deviceAddresses, groupAddresses: recycleData.groupAddresses, sceneAddresses: recycleData.sceneAddresses)
                    
                    self.deleteSpace(space: space)
                    //                space.delete()
                    if self.site.spaces.isEmpty && self.site.permission != .owner { // 不属于site所有者并且解绑所有spaces则清空site记录
                        self.site.delete()
                        self.site.state = .waitDeleted
                        self.navigationController?.popViewController(animated: true)
                    }
                    NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                    
                case .failure(let error):
                    //                if error == .resourceNotFound { // 找不到资源
                    //                    self.deleteSpace(space: space)
                    //                    if self.site.spaces.isEmpty && self.site.permission != .owner { // 不属于site所有者并且解绑所有spaces则清空site记录
                    //                        self.site.delete()
                    //                        self.site.state = .waitDeleted
                    //                        self.navigationController?.popViewController(animated: true)
                    //                    }
                    //                    NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                    //
                    //                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    //                }
                }
            }
        }
    }
    
    /// site回收地址请求
    @MainActor
    private func siteRecyclingAddressRequest(site: SiteData) async throws {
        try await withCheckedThrowingContinuation { continuation in
            guard let recycleAddressData = site.recycleAddressData, !recycleAddressData.isEmpty else {
                site.recycleAddressData = nil
                site.save()
                continuation.resume()
                return
            }
            let provisionerData = recycleAddressData.getResultProvisionerData(meshUUID: site.meshUUID)
            NetworkRequest.shared.request(.recyclingAddress(siteId: site.id, recycleDeviceAddresses: recycleAddressData.deviceAddresses, recycleGroupAddresses: recycleAddressData.groupAddresses, recycleSceneAddresses: recycleAddressData.sceneAddresses, exclusions: recycleAddressData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) }), provisionerData: provisionerData)) { result in
           
                switch result {
                case .success(_):
                    // 删除回收的地址
                    site.deleteProvisionerAddress(deviceAddresses: recycleAddressData.deviceAddresses, groupAddresses: recycleAddressData.groupAddresses, sceneAddresses: recycleAddressData.sceneAddresses)
                    site.recycleAddressData = nil
                    site.save()
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// 回收放弃的地址请求（接收转让site，拿到之前owner数据，放弃自己之前其他身份持有的地址）
    private func recyclingAddressRequest(abandonAddressData: SiteData.RecycleAddressData) {
        
        NetworkRequest.shared.request(.recyclingAddress(siteId: site.id, recycleDeviceAddresses: abandonAddressData.deviceAddresses, recycleGroupAddresses: abandonAddressData.groupAddresses, recycleSceneAddresses: abandonAddressData.sceneAddresses, exclusions: nil)) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(_):
                self.site.recycleAddressData = nil
                self.site.save()
            case .failure(_):
                break
            }
        }
    }
    
    /// 回收地址请求
    private func recyclingAddressRequest(delete: Bool, recyclingSpaces: [SpaceData]) {
        
        if delete {
            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        }
        
        Task {
            let addressData = await site.getRecycleAddressData(unbindSpaces: recyclingSpaces)
            NetworkRequest.shared.request(.recyclingAddress(siteId: site.id, recycleDeviceAddresses: addressData.deviceAddresses, recycleGroupAddresses: addressData.groupAddresses, recycleSceneAddresses: addressData.sceneAddresses, exclusions: addressData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) }), provisionerData: addressData.provisionerData)) {[weak self] result in
                guard let self = self else { return }
                if delete {
                    XWHUDManager.hide()
                }
                switch result {
                case .success(_):
                    // 删除回收的地址
                    self.site.deleteProvisionerAddress(deviceAddresses: addressData.deviceAddresses, groupAddresses: addressData.groupAddresses, sceneAddresses: addressData.sceneAddresses)
#if DEBUG
                    self.updateAddressData()
#endif
                    if delete {
                        recyclingSpaces.forEach({
                            self.deleteSpace(space: $0)
                        })
                        // 删除site数据
                        if self.site.permission != .owner && self.site.spaces.isEmpty {
                            self.site.delete()
                            NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: false)
                            self.navigationController?.popViewController(animated: true)
                        }
                    }else {
                        // 只回收地址不删除space记录一下，下次删除不用再回收
                        recyclingSpaces.forEach({
                            $0.releaseAddress = true
                            $0.save()
                        })
                        //                    CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
                    }
                    
                case .failure(let error):
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
        }
        
    }
    
    /// space菜单
    private func spaceMenu(space: SpaceData, point: CGPoint) {
        
        var items: [MenuPopView.MenuItem] = []
        
        if space.spaceOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] _ in
                self?.editSpace(space: space)
            }))
        }
        if space.spaceOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] _ in
                self?.showDeleteSpaceAlert(space: space)
            }))
        }
        if space.spaceOperates.contains(.shareEditor) || space.spaceOperates.contains(.shareVisitor) {
            items.append(.init(icon: UIImage(named: "menu_share"), title: "share".localizedString, tapItemBack: {[weak self] _ in
                self?.shareSpace(space)
            }))
        }
       
//        items.append(.init(icon: UIImage(named: "menu_share"), title: "Export", tapItemBack: {[weak self] _ in
//            self?.exportSpace(space)
//        }))
        
        if space.spaceOperates.contains(.exit) {
            items.append(.init(icon: UIImage(named: "menu_unbind"), title: "unbind".localizedString, tapItemBack: { _ in
                
                SRAlertView(title: "notification".localizedString, message: "space_unbind_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                    self?.unbindSpace(space)
                })]).show()
            }))
        }
        
        MenuPopView.show(items: items, anchorPoint: point)
    }
    
    /// 更新同步状态
    private func updateSyncState() {
        guard view.window != nil else {
            return
        }
        if let state = CloudSynchronizationManager.shared.getSiteCurrentSyncState(site) {
            switch state {
                case .inProgress:
                self.showNavigationBarLoading()
            case .successful:
                if allSpaces.contains(where: { $0.showSyncCloudError != nil }) { // site或者site下space存在同步错误
                    self.showNavigationBarFailure {[weak self] in
                        self?.showSpacesBatchesSyncAlert()
                    }
                }else {
                    self.showNavigationBarSuccessful()
                }
            case .failure:
                self.showNavigationBarFailure {[weak self] in
                    guard let self = self else { return }
                    if self.allSpaces.contains(where: { $0.showSyncCloudError != nil }) { // spaces 存在同步错误
                        self.showSpacesBatchesSyncAlert()
                    }else { // site存在同步错误
                        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
                    }
                }
            case .cancel:
                self.hideNavigationBarState()
            default:
                break
            }
        }else if site.showSyncCloudError != nil || allSpaces.contains(where: { $0.showSyncCloudError != nil }) { // site或者site下space存在同步错误
            self.showNavigationBarFailure {[weak self] in
                guard let self = self else { return }
                if self.allSpaces.contains(where: { $0.showSyncCloudError != nil }) { // spaces 存在同步错误
                    self.showSpacesBatchesSyncAlert()
                }else { // site存在同步错误
                    CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
                }
            }
        }
    }
    
    /// 更新网关同步状态
    private func updateGatewaySyncState(gateway: Gateway, state: CloudSynchronizationState?) {
        
        var gatewayStatus: GatewayStatusType = .online
        switch gateway.connectStatus {
        case .online:
            gatewayStatus = .online
        case .offline:
            gatewayStatus = .offline(lastOnlineTime: gateway.lastOnlineTime ?? "")
        case .inactive:
            gatewayStatus = .noActivated
        case .reset:
            gatewayStatus = .reset(resetTime: gateway.resetTime ?? "")
        }
        
        let permissionState: GatewayPermissionState = (site.permission == .owner || gateway.associatedSpaces.compactMap({ data in allSpaces.first(where: { $0.id == data.spaceId }) }).contains(where: { $0.state == .normal })) ? .normal : .noPermission
        
        if gateway.mac == allSpaceSelectGatewayId {
            allSpaceGatewayHeaderView?.gatewayStatusView.updateGatewayStatus(gatewayStatus, syncState: state, permissionState: permissionState)
            if case .successful = state { // 同步成功后清除状态
//                if gateway.syncCloudError != nil {
//                    gateway.syncCloudError = nil
                var items = showGatewayModels.map({ GatewayListItem(id: $0.mac, title: $0.name, status: $0.connectStatus, gatewayModel: $0.model)})
                if items.count > 0 {
                    items.insert(.init(id: "", title: "overview".localizedString), at: 0)
                }
                allSpaceGatewayHeaderView?.gatewayListView.updateItems(items)
//                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                    guard let self = self else { return }
                    if gateway.mac == self.allSpaceSelectGatewayId, self.allSpaceGatewayHeaderView?.gatewayStatusView.gatewaySyncState?.rawValue == CloudSynchronizationState.successful.rawValue {
                        self.allSpaceGatewayHeaderView?.gatewayStatusView.updateGatewayStatus(gatewayStatus, syncState: nil, permissionState: permissionState)
                    }
                }
            }
        }else if gateway.mac == favouriteSpaceSelectGatewayId {
            favouriteSpaceGatewayHeaderView?.gatewayStatusView.updateGatewayStatus(gatewayStatus, syncState: state, permissionState: permissionState)
            
            if gateway.syncCloudError != nil {
                gateway.syncCloudError = nil
                var items = gatewayModels.map({ GatewayListItem(id: $0.mac, title: $0.name, status: $0.connectStatus, gatewayModel: $0.model)})
                if items.count > 0 {
                    items.insert(.init(id: "", title: "overview".localizedString), at: 0)
                }
                favouriteSpaceGatewayHeaderView?.gatewayListView.updateItems(items)
            }
            
            if case .successful = state { // 同步成功后清除状态
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                    guard let self = self else { return }
                    if gateway.mac == self.favouriteSpaceSelectGatewayId, self.favouriteSpaceGatewayHeaderView?.gatewayStatusView.gatewaySyncState?.rawValue == CloudSynchronizationState.successful.rawValue {
                        self.favouriteSpaceGatewayHeaderView?.gatewayStatusView.updateGatewayStatus(gatewayStatus, syncState: nil, permissionState: permissionState)
                    }
                }
            }
        }
        
        
    }

    /// spaces批量同步提示
    private func showSpacesBatchesSyncAlert() {
        
        SRAlertView(title: "notification".localizedString, message: "spaces_batches_sync_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            let failedSpaces = self.allSpaces.filter({ $0.showSyncCloudError != nil })
            
            // site已上传服务器
            if site.uploadCloud {
                // 同步space
                failedSpaces.forEach({
                    CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: $0), level: .promptly)
                })
            }else {
                // 未上传服务器，site、space一起上传
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: .promptly)
            }
          
        })]).show()
        
    }
    
    /// space权限被清空提示
    private func showPermissionClearedMessage(space: SpaceData) {
        
        SRAlertView(title: "notification".localizedString, message: "space_permission_cleared_message".localizedString, actions: [SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            Task {
                // 未记录释放的地址
                if !space.releaseAddress {
                    XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
                    let addressData = await self.site.getRecycleAddressData(unbindSpaces: [space])
                    XWHUDManager.hide()
                    if let recycleAddressData = self.site.recycleAddressData {
                        self.site.recycleAddressData = recycleAddressData + addressData
                    }else {
                        self.site.recycleAddressData = addressData
                    }
                    self.site.save()
                }
                // 回收地址
                if !(self.site.recycleAddressData?.isEmpty ?? true) {
                    do {
                        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
                        try await self.siteRecyclingAddressRequest(site: self.site)
                        XWHUDManager.hide()
                    } catch let error {
                        XWHUDManager.hide()
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }
                }
                //            guard space.releaseAddress else {
                //                // 释放地址并删除space
                //                self.recyclingAddressRequest(delete: true, recyclingSpaces: [space])
                //                return
                //            }
                
                self.deleteSpace(space: space)
                // 删除site数据
                if self.site.permission != .owner && self.site.spaces.isEmpty {
                    self.site.delete()
                    NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: false)
                    self.navigationController?.popViewController(animated: true)
                }
            }
            
        })]).show()
        
    }
    
    /// 点击space事件
    private func selectSpaceAction(space: SpaceData) {
        
        // 判断是否还有space权限
        guard space.state == .normal else {
            // 权限被删除
            showPermissionClearedMessage(space: space)
            return
        }
        
        // 未上传到服务器，直接进入space
        if space.permission == .owner && !space.uploadCloud {
            intoSpace(space: space)
            return
        }

        // 手机节点地址未分配
        guard site.localAddress != nil else {
            self.requestMobileAddress()
            return
        }
        
        switch space.permission {
        case .editor:
            if (space.authorizationPassword?.isEmpty ?? true || space.requiresPasswordVerification) {
                // 编辑者没有密码/修改密码时需要验证密码
                verificationSpacePassword(space: space)
                return
            }
        case .visitor:
            if space.vistorPasswordEnable && (space.authorizationPassword?.isEmpty ?? true || space.requiresPasswordVerification) {
                // 访客需要密码并修改密码/没有密码时需要验证密码
                verificationSpacePassword(space: space)
                return
            }
        default:
            break
        }
        if NetworkRequest.shared.networkable {
            loadSpaceReqeust(space: space)
        }else {
            intoSpace(space: space)
        }
        
    }
    
    /// 进入space
    private func intoSpace(space: SpaceData) {
        
        guard self.view.window != nil else {
            return
        }
        // 判断如果有编辑权限的成员进入space前是否拉过space数据，未拉取服务器space数据不让进入space防止数据覆盖
        if space.permission == .owner || space.permission == .editor, space.uploadCloud, space.lastUploadCloudTimestamp == nil {
            XWHUDManager.showTipHUD("space_unsynchronized_cloud_message".localizedString, isLineFeed: true, afterDelay: 2)
            return
        }
        
        MenuPopView.hide()
        
        let spaceVc = SpaceViewController(space: space)
        spaceVc.site = site
        spaceVc.deleteSpaceCallback = {[weak self] in
            guard let self = self else { return  }
            self.site.spaces.removeAll(where: { $0.id == space.id })
            self.allSpaces.removeAll(where: { $0.id == space.id })
            self.favouriteSpaces.removeAll(where: { $0.id == space.id })
            if self.view.window != nil {
                self.allSpacesCollectionView.reloadData()
                self.favouritesCollectionView.reloadData()
                self.updateEmptyView()
            }
        }
        navigationController?.pushViewController(spaceVc, animated: true)
    }
    
    /// 验证space密码
    private func verificationSpacePassword(space: SpaceData, callback:((Bool)->Void)? = nil) {
        let message = space.permission == .editor ? "space_editor_password_changed_message".localizedString : "space_vistor_password_changed_message".localizedString
        SRAlertView(title: "notification".localizedString, message: message, inputText: nil, inputFieldStyle: .init(placeholder: "Password".localizedString, keyboardType: .numberPad, margin: SCRXFrom(56), height: SCRYFrom(32), minInputLength: 4, maxInputLength: 4, borderColor: RGB(153, 153, 153, 0.3), textAlignment: .center, secret: true, showClear: false), showPrompt: false, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString)], textValueChangedBack: nil) {[weak self] password in
            guard let self = self else { return }
            self.loadSpaceReqeust(space: space, verificationPassword: password, callback: callback)
        }.show()
    }
    
    /// 刷新space
    private func reloadSpaceData(_ space: SpaceData) {
        
        // 刷新数据
        var index: Int?
        var currentCollectionView: UICollectionView?
        if self.segmentedControl.selectedIndex == 0 {
            index = allSpaces.firstIndex(where: { $0.id == space.id })
            currentCollectionView = allSpacesCollectionView
        }else {
            index = favouriteSpaces.firstIndex(where: { $0.id == space.id })
            currentCollectionView = favouritesCollectionView
        }
        CATransaction.setDisableActions(true)
        if let index = index, let collectionView = currentCollectionView {
            collectionView.reloadItems(at: [IndexPath(row: index, section: 0)])
        }else {
            self.allSpacesCollectionView.reloadData()
            self.favouritesCollectionView.reloadData()
        }
        CATransaction.commit()
    }
    
    /// 添加网关
    private func addGateway() {
        
        guard self.site.permission == .owner || self.site.spaces.contains(where: { $0.canEditing }) else {
            // 无权限
            XWHUDManager.showTipHUD(inView: "no_permission".localizedString, isLineFeed: true)
            return
        }
        // 查询editor是否还有space没有被网关绑定
        if self.site.permission != .owner, !self.site.spaces.contains(where: { $0.permission == .editor && $0.gatewayStatus == .notBound }) {
            XWHUDManager.showTipHUD("gateway_add_no_editor_spaces_message".localizedString, isLineFeed: true)
            return
        }
        let vc = SiteDeviceAddViewController(site: self.site)
        vc.deviceAddCallback = {[weak self] _ in
            self?.loadSiteRequest()
        }
        self.navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 网关同步到云
    private func gatewaysSyncToCloud(_ gateways: [Gateway]) {
        gateways.forEach({
                $0.lastUpdate = Int64(Date().timeIntervalSince1970)
                $0.save()
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(gateway: $0.model, node: $0.node), level: .promptly)
        })
    }
    
    /// 刷新网关内关联space的权限状态
    private func reloadGatewaySpacePermissionState(space: SpaceData) {
        
        guard let gateway = gatewayModels.first(where: { $0.mac == space.relevanceGatewayId }) else {
            return
        }
        
        let gatewaySpace = gateway.associatedSpaces.first(where: { $0.spaceId == space.id })
        if space.canEditing {
            gatewaySpace?.permission = .editor
        }else {
            if space.state == .normal {
                gatewaySpace?.permission = space.requiresPasswordVerification ? .permissionException : .none
            }else {
                gatewaySpace?.permission = .permissionLoss
            }
        }
    }
    
    // MARK: - UI
    
    /// 更新无网络UI
    private func updateNoInternetUI() {
        
        if NetworkRequest.shared.networkable {
            
            allSpacesNoInternetView?.removeFromSuperview()
            favouritesNoInternetView?.removeFromSuperview()
            
            allSpacesCollectionView.contentInset.top = 0
            favouritesCollectionView.contentInset.top = 0
            
//            allSitesTableView.tableHeaderView = nil
//            favouritesTableView.tableHeaderView = nil
        }else {
            if allSpacesCollectionView.frame == .zero {
                allSpacesCollectionView.layoutIfNeeded()
            }
            if favouritesCollectionView.frame == .zero {
                favouritesCollectionView.layoutIfNeeded()
            }
            
            if allSpacesNoInternetView == nil || favouritesNoInternetView == nil {
                allSpacesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: -noInternetHeight, width: self.allSpacesCollectionView.width, height: noInternetHeight))
                favouritesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: -noInternetHeight, width: self.favouritesCollectionView.width, height: noInternetHeight))
            }
            allSpacesCollectionView.addSubview(allSpacesNoInternetView!)
            allSpacesCollectionView.contentInset.top = noInternetHeight

            favouritesCollectionView.addSubview(favouritesNoInternetView!)
            favouritesCollectionView.contentInset.top = noInternetHeight
            
            allSpacesCollectionView.setContentOffset(CGPoint(x: allSpacesCollectionView.contentOffset.x, y: -noInternetHeight), animated: false)
            favouritesCollectionView.setContentOffset(CGPoint(x: favouritesCollectionView.contentOffset.x, y: -noInternetHeight), animated: false)
            
//            allSitesTableView.tableHeaderView = allSitesNoInternetView
//            favouritesTableView.tableHeaderView = favouritesNoInternetView
        }
        
//        if let emptyView = allSpacesCollectionView.emptyView {
//            emptyView.contentView.snp.updateConstraints({ make in
//                let margin = NetworkRequest.shared.networkable ? 0 : (allSpacesNoInternetView?.height ?? 0)
//                make.top.equalTo(SCRYFrom(7) + margin)
//            })
//        }
    }
    
    /// 判断是否显示空数据页
    private func updateEmptyView() {
        
        if scrollView.frame == .zero {
            view.layoutIfNeeded()
        }
        
        if allSpaces.isEmpty {
            if site.spaces.isEmpty {
                var frame = allSpacesCollectionView.bounds
                frame.origin.y = 0
                if showGatewayModels.count > 0 {
                    frame.origin.y += SCRYFrom(48)
                }
                allSpacesCollectionView.showEmptyDataView(frame: frame,imageName: "space_empty", title: "no_spaces_title".localizedString, tipText: nil)
                if let emptyView = allSpacesCollectionView.emptyView {
    //                let margin = NetworkRequest.shared.networkable ? 0 : (allSpacesNoInternetView?.height ?? 0)
                    
                    if isIPad {
                        
                        emptyView.contentView.snp.remakeConstraints({ make in
                            make.centerX.equalToSuperview()
                            make.centerY.equalToSuperview().offset(SCRYFit(-80))
                            make.width.equalToSuperview().multipliedBy(0.7)
                        })
                        emptyView.imageView.snp.remakeConstraints { make in
                            make.top.equalToSuperview()
                            make.centerX.equalToSuperview()
                            make.left.equalTo(SCRXFrom(-10))
                            make.right.equalTo(SCRXFrom(10))
                            make.height.equalTo(emptyView.imageView.snp.width).multipliedBy(298.0 / 353)
                        }
                        
                    }else {
                        
                        emptyView.contentView.snp.remakeConstraints({ make in
                            //                    make.top.equalTo(SCRYFrom(7) + margin)
                            make.top.equalTo(SCRYFrom(7))
                            make.left.equalTo(SCRXFrom(20))
                            make.right.equalTo(-SCRXFrom(20))
                        })
                        emptyView.imageView.snp.remakeConstraints { make in
                            make.top.equalToSuperview()
                            make.centerX.equalToSuperview()
                            make.left.equalTo(SCRXFrom(-10))
                            make.right.equalTo(SCRXFrom(10))
                            make.height.equalTo(emptyView.snp.width).multipliedBy(298.0 / 353)
                        }
                    }
                    emptyView.titleLabel.snp.updateConstraints { make in
                        make.top.equalTo(emptyView.imageView.snp.bottom).offset(SCRYFrom(9))
                    }
                    emptyView.tipLabel.textAlignment = .left
                    
                    
                    let paragraphStyle = NSMutableParagraphStyle()
                    paragraphStyle.lineSpacing = 6
                    let attStr = NSAttributedString(string: "no_spaces_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
                    emptyView.tipLabel.attributedText = attStr
                }
            }else {
                allSpacesCollectionView.showEmptyDataView(frame: favouritesCollectionView.bounds.offsetBy(dx: 0, dy: SCRYFrom(96)), title: "no_spaces_title".localizedString, bottomMargin: SCRYFrom(32))
            }
        }else {
            allSpacesCollectionView.hideEmptyDataView()
        }
        
        if favouriteSpaces.isEmpty {
            favouritesCollectionView.showEmptyDataView(frame: favouritesCollectionView.bounds.offsetBy(dx: 0, dy: site.spaces.count > 0 ? SCRYFrom(96) : 0), title: "no_favourites_spaces".localizedString, bottomMargin: SCRYFrom(32))
        }else {
            favouritesCollectionView.hideEmptyDataView()
        }
        
    }
    
    private func setupUI() {
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: ["all_spaces".localizedString, "favourites_spaces".localizedString])
//        segmented.selectedIndex = 1
        segmentedControl.delegate = self
        view.addSubview(segmentedControl)
//        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
//            make.top.equalTo(SCRYFrom(16) + (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight))
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(44))
        }
        
        scrollView = PopGestureScrollView()
        scrollView.isPagingEnabled = true
        scrollView.bounces = false
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(segmentedControl.snp.bottom).offset(SCRYFrom(8))
        }
        
        allSpacesRefreshControl = UIRefreshControl()
        allSpacesRefreshControl.tintColor = UIColor.lightGray
        allSpacesRefreshControl.addTarget(self, action: #selector(loadSiteRequest), for: .valueChanged)
        
        allSpacesFlowLayout = UICollectionViewFlowLayout()
        if isIPad {
            allSpacesFlowLayout.minimumLineSpacing = SCRXFrom(20)
            allSpacesFlowLayout.minimumInteritemSpacing = SCRXFrom(20)
        }else {
            allSpacesFlowLayout.minimumLineSpacing = SCRXFrom(16)
            allSpacesFlowLayout.minimumInteritemSpacing = SCRXFrom(16)
        }
        
        allSpacesCollectionView = UICollectionView(frame: .zero, collectionViewLayout: allSpacesFlowLayout)
        allSpacesCollectionView.backgroundColor = .clear
        allSpacesCollectionView.register(SpacesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        allSpacesCollectionView.register(SiteGatewayHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
//#if DEBUG
//        allSpacesCollectionView.register(SiteAddressDataHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
//#endif
//        allSitesCollectionView.rowHeight = SCRYFrom(92)
        allSpacesCollectionView.dataSource = self
        allSpacesCollectionView.delegate = self
        allSpacesCollectionView.refreshControl = allSpacesRefreshControl
        scrollView.addSubview(allSpacesCollectionView)
        allSpacesCollectionView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        favouritesRefreshControl = UIRefreshControl()
        favouritesRefreshControl.tintColor = UIColor.lightGray
        favouritesRefreshControl.addTarget(self, action: #selector(loadSiteRequest), for: .valueChanged)
        
        favouritesFlowLayout = UICollectionViewFlowLayout()
        if isIPad {
            favouritesFlowLayout.minimumLineSpacing = SCRXFrom(20)
            favouritesFlowLayout.minimumInteritemSpacing = SCRXFrom(20)
        }else {
            favouritesFlowLayout.minimumLineSpacing = SCRXFrom(16)
            favouritesFlowLayout.minimumInteritemSpacing = SCRXFrom(16)
        }
        
        favouritesCollectionView = UICollectionView(frame: .zero, collectionViewLayout: favouritesFlowLayout)
        favouritesCollectionView.backgroundColor = .clear
        favouritesCollectionView.register(SiteGatewayHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "header")
        favouritesCollectionView.register(SpacesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        favouritesCollectionView.dataSource = self
        favouritesCollectionView.delegate = self
        favouritesCollectionView.refreshControl = favouritesRefreshControl
        scrollView.addSubview(favouritesCollectionView)
        favouritesCollectionView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.left.equalTo(allSpacesCollectionView.snp.right)
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        if isIPad {
            allSpacesCollectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(20), bottom: 0, right: SCRXFrom(20))
        }else {
            allSpacesCollectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: 0, right: SCRXFrom(16))
        }
        favouritesCollectionView.contentInset = allSpacesCollectionView.contentInset
        
        addSpaceBtn = UIButton(normalImageName: "add", target: self, action: #selector(addSpace))
        if !site.permissionOperates.contains(.edit) {
            addSpaceBtn.isHidden = true
        }
        view.addSubview(addSpaceBtn)
        addSpaceBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-38))
        }
    }


}

extension SiteViewController: GatewayListViewDelegate {
    
    /// 点击网关项回调
    func gatewayListView(_ view: GatewayListView, didSelectItem item: GatewayListItem, at index: Int) {
        if segmentedControl.selectedIndex == 0 {
            if index == 0 || index > showGatewayModels.count {
                allSpaceSelectGatewayId = nil
            }else {
                allSpaceSelectGatewayId = showGatewayModels[index - 1].mac
            }
        }else {
            if index == 0 || index > showGatewayModels.count {
                favouriteSpaceSelectGatewayId = nil
            }else {
                favouriteSpaceSelectGatewayId = showGatewayModels[index - 1].mac
            }
        }
        setupData()
    }
    
    /// 点击菜单按钮回调
    func gatewayListViewDidClickMenu(_ view: GatewayListView) {
        let datas = showGatewayModels.map({ SiteGatewaysMenuView.GatewayMenuData(name: $0.name, status: $0.connectStatus) })
        
        let menuPoint = CGPoint(x: view.width - SiteGatewaysMenuView.defalutWidth, y: view.frame.maxY + SCRYFrom(4))
        let windowPoint = view.convert(menuPoint, to: UIApplication.shared.keyWindow())
        
        var selectIndex: Int?
        if segmentedControl.selectedIndex == 0 {
            selectIndex = showGatewayModels.firstIndex(where: { $0.mac == allSpaceSelectGatewayId })
        }else {
            selectIndex = showGatewayModels.firstIndex(where: { $0.mac == favouriteSpaceSelectGatewayId })
        }
        
        SiteGatewaysMenuView.show(datas: datas, anchorPoint: windowPoint, selectIndex: selectIndex) {[weak self] index in
            guard let self = self else { return }
            if self.segmentedControl.selectedIndex == 0 {
                self.allSpaceSelectGatewayId = self.showGatewayModels[safe: index]?.mac
            }else {
                self.favouriteSpaceSelectGatewayId = self.showGatewayModels[safe: index]?.mac
            }
            self.setupData()
        } addCallback: {[weak self] in
            guard let self = self else { return }
            self.addGateway()
        }
    }
    
    /// 点击添加网关
    func gatewayListViewDidClickAdd(_ view: GatewayListView) {
        addGateway()
    }
    
}

extension SiteViewController: SiteGatewayStatusViewDelegate {
    
    /// 网关状态view点击回调
    func gatewayStatusViewClickAction(_ view: SiteGatewayStatusView) {
        if case .failure = view.gatewaySyncState {
            var selectGatewayId: String?
            if segmentedControl.selectedIndex == 0 {
                selectGatewayId = allSpaceSelectGatewayId
            }else {
                selectGatewayId = favouriteSpaceSelectGatewayId
            }
            if let gateway = showGatewayModels.first(where: { $0.mac == selectGatewayId }) {
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncGateway(gateway: gateway.model, node: gateway.node), level: .promptly)
            }
        }
    }
    
    func gatewayOperationClickAction(_ view: SiteGatewayStatusView) {
        
        let selectGatewayId = segmentedControl.selectedIndex == 0 ? allSpaceSelectGatewayId : favouriteSpaceSelectGatewayId
        guard let gateway = showGatewayModels.first(where: { $0.mac == selectGatewayId }) else {
            return
        }
        
        // 网关内绑定的space无权限
        if site.permission != .owner, gateway.associatedSpaces.count > 0, !gateway.associatedSpaces.contains(where: { $0.permission == .editor }) {
            XWHUDManager.showTipHUD(inView: "gateway_no_authority".localizedString, isLineFeed: true)
            return
        }
        
        guard let gatewayVc = GatewayViewController(site: site, gateway: gateway) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString + " !")
            return
        }
        if isIPad {
            gatewayVc.preferredContentSize = iPadStandardSize
        }
        //测试v1.5网桥
       // let gatewayVc = PJNGatewayViewController(site: site, gateway: gateway)
        present(NavigationViewController(rootViewController: gatewayVc), animated: true)
        
    }
    
}

extension SiteViewController: CustomSegmentedControlDelegate {
    
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        
        scrollView.setContentOffset(CGPoint(x: CGFloat(index) * scrollView.frame.size.width, y: 0), animated: true)
    }
}

extension SiteViewController: UIScrollViewDelegate {
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView == self.scrollView, scrollView.isTracking || scrollView.isDragging else {
            return
        }
        let index = Int(scrollView.contentOffset.x / scrollView.frame.size.width + 0.5)
        guard index != segmentedControl.selectedIndex else {
            return
        }
        segmentedControl.selectedIndex = index
    }

}

extension SiteViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == allSpacesCollectionView {
            return allSpaces.count
        }
        return favouriteSpaces.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SpacesViewCell
        var space: SpaceData!
        if collectionView == allSpacesCollectionView {
            space = allSpaces[indexPath.row]
        }else {
            space = favouriteSpaces[indexPath.row]
        }
        cell.space = space
        cell.delegate = self
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: "header", for: indexPath) as! SiteGatewayHeaderView
        
        var selectIndex: Int = 0
        var spaces: [SpaceData] = []
        if collectionView == allSpacesCollectionView {
            if let index = showGatewayModels.firstIndex(where: { $0.mac == allSpaceSelectGatewayId }) {
                selectIndex = index + 1
            }
            spaces = allSpaces
        }else {
            if let index = showGatewayModels.firstIndex(where: { $0.mac == favouriteSpaceSelectGatewayId }) {
                selectIndex = index + 1
            }
            spaces = favouriteSpaces
        }
        
        if showGatewayModels.count > 0 {
            headerView.showGatewayListView = true
            var items = showGatewayModels.map({ GatewayListItem(id: $0.mac, title: $0.name, status: $0.connectStatus, gatewayModel: $0.model)})
            if items.count > 0 {
                items.insert(.init(id: "", title: "overview".localizedString), at: 0)
            }
            headerView.gatewayListView.updateItems(items)
            headerView.gatewayListView.selectedIndex = selectIndex
            headerView.gatewayStatusView.isHidden = site.spaces.isEmpty || showGatewayModels.isEmpty
        }else {
            if self.site.permission == .owner || self.allSpaces.contains(where: { $0.canEditing && $0.gatewayStatus == .notBound }) { // 显示添加网关UI
                headerView.showGatewayListView = true
                headerView.gatewayListView.updateItems([])
            }else {
                headerView.showGatewayListView = false
            }
            headerView.gatewayStatusView.isHidden = self.site.permission == .owner
        }
       
        if selectIndex == 0 {
            headerView.gatewayStatusView.setDisplayMode(.overview)
            
            let onlineSpaces = spaces.filter({ $0.gatewayStatus == .online })
            let offlineSpaces = spaces.filter({ $0.gatewayStatus == .offline })
            let notBoundSpaces = spaces.filter({ $0.gatewayStatus == .notBound })
            
            headerView.gatewayStatusView.updateOverviewStats(.init(internetOnlineCount: onlineSpaces.count, internetOfflineCount: offlineSpaces.count, noGatewayCount: notBoundSpaces.count))
        }else {
            headerView.gatewayStatusView.setDisplayMode(.gateway)
            if selectIndex <= showGatewayModels.count {
                let gateway = showGatewayModels[selectIndex - 1]
                var syncState = CloudSynchronizationManager.shared.getGatewayCurrentSyncState(gateway.model)?.state
                if gateway.model.syncCloudError != nil && syncState == nil {
                    syncState = .failure(error: gateway.model.syncCloudError!)
                }
                let permissionState: GatewayPermissionState = (site.permission == .owner || gateway.associatedSpaces.isEmpty || gateway.associatedSpaces.compactMap({ data in allSpaces.first(where: { $0.id == data.spaceId }) }).contains(where: { $0.canEditing })) ? .normal : .noPermission
                switch gateway.connectStatus {
                case .online:
                    headerView.gatewayStatusView.updateGatewayStatus(.online, syncState: syncState, permissionState: permissionState)
                case .offline:
                    headerView.gatewayStatusView.updateGatewayStatus(.offline(lastOnlineTime: gateway.lastOnlineTime ?? "--"), syncState: syncState, permissionState: permissionState)
                case .inactive:
                    headerView.gatewayStatusView.updateGatewayStatus(.noActivated, syncState: syncState, permissionState: permissionState)
                case .reset:
                    headerView.gatewayStatusView.updateGatewayStatus(.reset(resetTime: gateway.resetTime ?? "--"), syncState: syncState, permissionState: permissionState)
                }
            }
        }
        headerView.gatewayListView.delegate = self
        headerView.gatewayStatusView.delegate = self
        if collectionView == allSpacesCollectionView {
            allSpaceGatewayHeaderView = headerView
        }else {
            favouriteSpaceGatewayHeaderView = headerView
        }
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
          
//        guard site.spaces.count > 0 || showGatewayModels.count > 0 else {
//            return .zero
//        }
        
        let headerW = collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right
        var headerH = SCRYFrom(48)

        if site.spaces.count > 0 && (showGatewayModels.count > 0 || self.site.permission != .owner && self.allSpaces.contains(where: { $0.canEditing && $0.gatewayStatus == .notBound })) {
            headerH += SCRYFrom(48)
        }
        return CGSize(width: headerW, height: headerH)
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        var space: SpaceData!
        if collectionView == allSpacesCollectionView {
            space = allSpaces[indexPath.row]
        }else {
            space = favouriteSpaces[indexPath.row]
        }
        
        selectSpaceAction(space: space)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let padding = (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing ?? 0
        var itemW = ((collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right) - CGFloat(self.itemRowCount - 1) * padding) / CGFloat(self.itemRowCount)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSizeMake(itemW, SCRYFrom(192))
    }
    
//#if DEBUG
//    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
//        guard tableView == self.allSpacesTableView else {
//            return nil
//        }
//        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! SiteAddressDataHeaderView
//        headerView.deviceAddressLabel.text = "Device Address: \(self.usedDeviceAddressNum)/\(self.allDeviceAddressNum)"
//        headerView.groupAddressLabel.text = "Group Address: \(self.usedGroupAddressNum)/\(self.allGroupAddressNum)"
//        headerView.sceneAddressLabel.text = "Scene Address: \(self.usedSceneAddressNum)/\(self.allSceneAddressNum)"
//        headerView.recycleAddressLabel.text = "Recycle Address: \(self.recycleAddressNum)"
//        return headerView
//    }
//
//
//    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
//        guard tableView == self.allSpacesTableView else {
//            return 0
//        }
//        return SCRYFrom(44)
//    }
//
//    #endif
    
}

extension SiteViewController: SpacesViewCellDelegate {
    
    /// 点击更多回调
    func cell(_ cell: SpacesViewCell, moreAction point: CGPoint) {
        
        let space = cell.space!
        // 判断是否还有space权限
        guard space.state == .normal else {
            // 权限被删除
            showPermissionClearedMessage(space: space)
            return
        }
        
        var collectionView: UICollectionView!
        if segmentedControl.selectedIndex == 0 {
            collectionView = allSpacesCollectionView
        }else {
            collectionView = favouritesCollectionView
        }
        
        let collectionViewPoint = collectionView.convert(point, from: cell)
        let viewPoint = view.convert(collectionViewPoint, from: collectionView)
//        let windowPoint =
//        [weakself.view convertPoint:tableviewPoint fromView:tableView];
        self.spaceMenu(space: space, point: viewPoint)
    }
    
    /// 点击收藏回调
    func cell(_ cell: SpacesViewCell, favouriteChanged favourite: Bool) {
        
        let space = cell.space!
        // 判断是否还有space权限
        guard space.state == .normal else {
            // 权限被删除
            showPermissionClearedMessage(space: space)
            return
        }
        
        space.isFavourite = favourite
//        space.lastUpdate = Int64(Date().timeIntervalSince1970)
        space.save()
        setupData()
//        if favourite {
//            
//            self.favouriteSpaces.append(space)
//            // 创建时间排序
////            self.favouriteSpaces = self.favouriteSpaces.sorted { space1, space2 in
////                return space1.create < space2.create
////            }
//        }else {
//            self.favouriteSpaces.removeAll(where: { $0.id == space.id })
//        }
//        self.allSpacesCollectionView.reloadData()
//        self.favouritesCollectionView.reloadData()
//        self.updateEmptyView()
//        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .normal)
        
    }
    
    /// 点击同步异常回调
    func spacesViewCellSyncFailedAction(_ cell: SpacesViewCell) {
        
        let space = cell.space!
        // 判断是否还有space权限
        guard space.state == .normal else {
            // 权限被删除
            showPermissionClearedMessage(space: space)
            return
        }
        
        guard let error = space.showSyncCloudError else {
            return
        }
        SRAlertView(title: "synchronization_failure".localizedString, message: error.localizedDescription, actions: [.cancelAction, SRAlertAction(title: "SYNC".localizedString, actionHandler: {[weak self] _ in
            cell.syncFailedImageBtn.isHidden = true
            guard let self = self else { return }
            // site已上传服务器
            if self.site.uploadCloud {
                // 同步space
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .promptly)
            }else {
                // 未上传服务器，site、space一起上传
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: site.spaces), level: .promptly)
            }
            
        })]).show()
        
    }
}

extension SiteViewController: CloudSynchronizationManagerDelegate {
    
    /// 开始同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle) {
        updateSyncState()
        switch handle.operation {
        case .syncSpace(let space):
            reloadSpaceData(space)
        case .addSpaces(let site, let spaces):
            guard site.id == self.site.id else {
                return
            }
            spaces.forEach({
                self.reloadSpaceData($0)
            })
        case .syncGateway(let gatewayModel, _):
            if let gateway = gatewayModels.first(where: { $0.mac == gatewayModel.mac }) {
                updateGatewaySyncState(gateway: gateway, state: .inProgress)
            }
        default:
            break
        }
    }
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle) {
        updateSyncState()
        switch handle.operation {
        case .syncSpace(let space):
            reloadSpaceData(space)
        case .syncSite(let site, let spaces), .addSpaces(let site, let spaces):
            guard site.id == self.site.id else {
                return
            }
            spaces.forEach({
                self.reloadSpaceData($0)
            })
        case .syncGateway(let gatewayModel, _):
            if let gateway = gatewayModels.first(where: { $0.mac == gatewayModel.mac }) {
                updateGatewaySyncState(gateway: gateway, state: .successful)
            }
        }
    }
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError) {
        updateSyncState()
        
        switch handle.operation {
        case .syncSpace(let space):
            reloadSpaceData(space)
        case .syncSite(let site, let spaces), .addSpaces(let site, let spaces):
            guard site.id == self.site.id else {
                return
            }
            spaces.forEach({
                self.reloadSpaceData($0)
            })
        case .syncGateway(let gatewayModel, _):
            if let gateway = gatewayModels.first(where: { $0.mac == gatewayModel.mac }) {
                updateGatewaySyncState(gateway: gateway, state: .failure(error: error))
            }
        }
        
    }
    
    /// 同步数据操作取消回调
    func cloudSyncManager(_ manager: CloudSynchronizationManager, cancelSyncHandle handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
}

extension SiteViewController: UIDocumentPickerDelegate {
    
    /// 选择文件导入回调
    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        do {
            let data = try Data(contentsOf: url)
            if var json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                json.updateValue("\(Int64(Date().timeIntervalSince1970))", forKey: "updateTimestamp")
                
                Task {
                    _ = await SpaceData.import(siteId: site.id, meshUUID: site.meshUUID, spaceJsonData: json)
                    XWHUDManager.showSuccessTipHUD("done!".localizedString)
                    self.loadSiteRequest()
                }
            }
            
        } catch { // 失败提示
            XWHUDManager.showErrorTipHUD("failed".localizedString)
        }
    }
    
}
