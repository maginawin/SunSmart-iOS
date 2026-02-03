//
//  SitesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/20.
//

import UIKit
import SwiftyJSON
import NordicSigMeshSDK

/// 场所列表数据刷新通知
let SitesDataRefreshNotifiacationName = "SitesRefreshNotifiacation"

class SitesViewController: UIViewController {
    
    enum SectionType {
        
        var rawString: String{
            switch self {
            case .personal:
                return "personal".localizedString
            case .received:
                return "received".localizedString
            }
        }
        /// 自己的
        case personal
        /// 收到的
        case received
    }
    /// 更新数据状态
    enum ReloadState {
        /// 列表刷新
        case list
        /// 读取本地
        case cache
        /// 服务器获取
        case server
    }

    private var showMenu: Bool = false
    
    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: UIScrollView!
    private var allSitesCollectionView: UICollectionView!
    private var allSitesFlowLayout: UICollectionViewFlowLayout!
    
    private var allSitesNoInternetView: NoInternetHeaderView?
    private var favouritesCollectionView: UICollectionView!
    private var favouritesSitesFlowLayout: UICollectionViewFlowLayout!
    
    private let noInternetHeight = SCRYFrom(54)
    
    private var favouritesNoInternetView: NoInternetHeaderView?
    
    /// 所有site刷新
    private var allSitesRefreshControl: UIRefreshControl!
    /// 喜欢的site刷新
    private var favouritesRefreshControl: UIRefreshControl!

    private var addSiteBtn: UIButton!
    
    private var allSites: [SiteData] = []
    private var favouriteSites: [SiteData] = []
    private var reloadState: ReloadState = .list
    /// 导航控制器是否点击back返回
//    private var navitionItemBack: Bool = false
    /// 扫码页面
    private weak var scanCodeVc: LBXScanViewController?
    
    private var allSections: [SectionType] = []
    private var favouriteSections: [SectionType] = []
    /// 每行显示几个item
    private let itemRowCount: Int = isIPad ? 2 : 1
    
    override func viewDidLoad() {
        super.viewDidLoad()
      
        title = "sites".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "menu_icon")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(menuClick))
//        navigationItem.rightBarButtonItems = [
//            UIBarButtonItem(customView: UIButton(normalImageName: "more_vertical", target: self, action: #selector(moreClick))),
//            UIBarButtonItem(customView: UIButton(normalImageName: "import", target: self, action: #selector(importClick))),
//        ]
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: UIButton(normalImageName: "import", target: self, action: #selector(importClick)))

        NotificationCenter.default.addObserver(self, selector: #selector(refreshData), name: .init(SitesDataRefreshNotifiacationName), object: nil)
        
        NetworkRequest.shared.addObserver(self, forKeyPath: "networkable", context: nil)
        
        setupUI()
        setupData()
        
        
//        let reinstallation = UserData.isReinstallation
//        print(UserData.currentUserId, UserData.currentUserName, UserData.currentServerRegion)
        
     
//        allSitesTableView.tableHeaderView = allSitesNoInternetView
//        favouritesTableView.tableHeaderView = favouritesNoInternetView
        
        // 重装APP把服务器内的site本地地址都切换
        if UserData.isReinstallation {
            UserData.siteChangeAddressRegions = ServerRegion.defaultRegions
        }
        
        if Keychain.getServerRegion() == nil { // 还未选择服务器地区
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                let defalutRegion = ServerRegion(regionCode: Locale.current.regionCode) ?? .northAmerica
                ServerSelectionView(selectRegion: defalutRegion) {[weak self] region in
                    UserData.currentServerRegion = region
                    self?.setupData()
                    self?.loadSitesRequest()
                    // 获取设备配置数据
                    self?.loadMeshDeviceConfigRequest()
                }.show()
            }
        }else if NetworkRequest.shared.networkable {
            loadSitesRequest()
            // 获取设备配置数据
            loadMeshDeviceConfigRequest()
        }
      
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
//        (navigationController as? NavigationViewController)?.navigationDelegate = self
        
        switch reloadState {
        case .list:
            allSitesCollectionView.reloadData()
            favouritesCollectionView.reloadData()
        case .cache:
            setupData()
            reloadState = .list
        case .server:
            loadSitesRequest()
            reloadState = .list
        }
        
        // 点击back返回，回到menu页面
//        if navitionItemBack && showMenu {
//            showMenu = false
//            menuClick()
//        }
//        navitionItemBack = false
        
        CloudSynchronizationManager.shared.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // pop手势返回，回到menu页面
        if showMenu {
            showMenu = false
            menuClick()
        }
        updateSyncState()
        
        if allSitesCollectionView.firstShowFlashScrollIndicators {
            allSitesCollectionView.flashScrollIndicatorsIfNeeded()
        }
        
        if favouritesCollectionView.firstShowFlashScrollIndicators {
            favouritesCollectionView.flashScrollIndicatorsIfNeeded()
        }
//        self.showNavigationBarLoading()
        
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
//            if self.view.window != nil {
//                self.showNavigationBarSuccessful()
//            }
//        })
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
//        (navigationController as? NavigationViewController)?.navigationDelegate = nil
    }
    
    /// KVO监听
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "networkable" { // 手机网络连接状态
            updateNoInternetUI()
            if NetworkRequest.shared.networkable { // 无网络=>有网络
                // 自动上传
                if view.window != nil, Keychain.getServerRegion() != nil {
                    loadSitesRequest()
                    // 获取设备配置数据
                    loadMeshDeviceConfigRequest()
                }
                
            }else { // 有网络=>无网络
                if SRAlertView.getCurrentAlertView() == nil {
                    SRAlertView(title: "notification".localizedString, message: "phone_network_disconnect".localizedString, actions: [.init(title: "confirm".localizedString)]).show()
                }
                if view.window !=  nil, XWHUDManager.isVisible() {
                    XWHUDManager.hideInView(with: self.view)
                }
            }
        }
    }
    
    
    /// 数据源
    private func setupData() {
        let sites = SiteData.loadAll()
        allSites = sites
        favouriteSites = sites.filter({ $0.isFavourite })
        
//        allSites.forEach { site in
//            site.state = .normal
//            site.lastUploadCloudTimestamp = nil
//            site.save()
//            site.spaces.forEach({
//                $0.lastUploadCloudTimestamp = nil
//                $0.save()
//            })
//        }
        
        setupSectionsData()
        
        allSitesCollectionView.reloadData()
        favouritesCollectionView.reloadData()
        
        updateEmptyView()
    }
    
    private func setupSectionsData() {
        
//        allSections.removeAll()
//        favouriteSites.removeAll()
        var allSections: [SectionType] = []
        var favouriteSections: [SectionType] = []
        
        if allSites.contains(where: { $0.permission == .owner }) {
            allSections.append(.personal)
        }
        if allSites.contains(where: { $0.permission != .owner }) {
            allSections.append(.received)
        }
        
        if favouriteSites.contains(where: { $0.permission == .owner }) {
            favouriteSections.append(.personal)
        }
        if favouriteSites.contains(where: { $0.permission != .owner }) {
            favouriteSections.append(.received)
        }
        
        self.allSections = allSections
        self.favouriteSections = favouriteSections
    }
    
    /// 刷新数据通知回调
    @objc private func refreshData(notification: Notification) {
        // 需要读取服务器
        if notification.object as? Bool ?? false {
            if view.window != nil {
                loadSitesRequest()
            }else {
                reloadState = .server
            }
        }else { // 读取本地数据库
            if view.window != nil {
                setupData()
            }else {
                reloadState = .cache
            }
        }
    }
    
    // MARK: - Reqeuest
    /// 获取site列表请求
    @objc private func loadSitesRequest() {
        
        // 判断是否联网
//        guard NetworkRequest.shared.networkable else {
//            return
//        }
        XWHUDManager.showCustomHUD(withMessage: nil, view: self.view)
        NetworkRequest.shared.request(.sites) {[weak self] result in
            guard let self = self else { return }
            
            self.allSitesRefreshControl.endRefreshing()
            self.favouritesRefreshControl.endRefreshing()
            switch result {
            case .success(let response):
                if let siteDatas = JSON(response)["data"]["sites"].arrayObject as? [[String: Any]] {
                    Task {
                        var sites: [SiteData] = []
                        // 是否修改site本地地址
                        var changeAddress = false
                        // 服务器地区需要修改site地址
                        if let index = UserData.siteChangeAddressRegions.firstIndex(of: UserData.currentServerRegion) {
                            changeAddress = true
                            var regions = UserData.siteChangeAddressRegions
                            regions.remove(at: index)
                            UserData.siteChangeAddressRegions = regions
                        }
                        
                        // 导入site数据属于耗时操作，等待异步线程完成
                        print("导入数据: \(Date().timeIntervalSince1970)")

                        await withTaskGroup(of: SiteData?.self) { group in
                            for data in siteDatas {
                                group.addTask {
                                    // 异步处理每个数据
                                    return await SiteData.import(siteJsonData: data, changeAddress: changeAddress)
                                }
                            }
                            // 收集结果
                            for await site in group {
                                if let site = site {
                                    sites.append(site)
                                }
                            }
                        }
                        print("导入数据完成: \(Date().timeIntervalSince1970)")
//                        if UserData.isReinstallation {
//                           _ = Keychain.saveLastVendorIdentifier()
//                        }
                        
                        // 转移site事件信息
                        let transferredEvents: [(siteId: String, username: String)] = JSON(response)["data"]["events"].arrayValue.filter({ $0["eventType"].string == "OwnerTransfer" }).compactMap({
                            if let siteId = $0["siteId"].string, let username = $0["props"]["username"].string {
                                return (siteId, username)
                            }
                            return nil
                        })
                        // site已提交到服务器，但是本地有但是服务器没有
                        let deleteSites = self.allSites.filter({ localSite in !sites.contains(where: { $0.id == localSite.id }) && localSite.uploadCloud })
                        // 需要提示已被转让的site
                        var showTransferredDatas: [SitesTransferredView.TransferredData] = []
                        deleteSites.forEach({ site in
                            if site.permission != .owner {
                                // 如果site本地有space数据，则设置space为待删除状态，删除space后site自动删除
                                if site.spaces.count > 0 {
                                    site.spaces.forEach({
                                        $0.state = .waitDeleted
                                        $0.save()
                                    })
                                }else { // site不存在space则自动删除
                                    site.delete()
                                }
                            }else { // 待删除的site如果是owner，则保存待删除记录
                                if let eventInfo = transferredEvents.first(where: { $0.siteId == site.id }) { // 判断是否被转让了
                                    // 设置site为待删除
                                    site.state = .waitDeleted
                                    site.save()
                                    showTransferredDatas.append(.init(siteId: site.id, siteName: site.name, receiveName: eventInfo.username))
                                }
                            }
                        })
                        sites.forEach({ $0.save() })
                        self.setupData()
                        XWHUDManager.hideInView(with: self.view)
                        // 展示已被转让的site信息
                        if showTransferredDatas.count > 0 {
                            SitesTransferredView(datas: showTransferredDatas, doneBack: nil).show()
                        }
                        
                        // 上传到云端
                        self.allSites.filter({ $0.needUploadCloud && $0.state == .normal }).forEach { site in
                            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
                        }
                        
                    }
                }else {
                    XWHUDManager.hideInView(with: self.view)
                }
            case .failure(_):
                XWHUDManager.hideInView(with: self.view)
            }
        }
        
    }
    
    /// 获取扫码分享内容请求  qrCode: 是否扫码
    private func loadShareInfoRequest(shareId: String, qrCode: Bool, sharePermission: Permission? = nil) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.shareInfo(shareId: shareId)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                guard let data = JSON(response)["data"].dictionaryObject,
                      let type = SharePermissionSelectionController.ReceivingType(shareData: data, sharePermission: sharePermission) else {
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                        self?.scanCodeVc?.startScan()
                    }
                    return
                }
                // 判断是否是自己分享的内容
                switch type {
                case .site(let site, let owner, _):
                    // 自己的site转让且未转让出去，跳转到site页面
                    if let mySite = self.allSites.first(where: { $0.id == site.id && $0.permission == .owner && $0.state == .normal }) {
                        self.navigationController?.popViewController(animated: false)
                        let vc = SiteViewController(site: mySite)
                        self.navigationController?.pushViewController(vc, animated: true)
                        return
                    }
                case .space(_, let space, _, _):
                    // 已存在的space分享数据，跳转到site->space页面
                    if let mySite = self.allSites.first(where: { $0.id == space.siteId  && $0.state == .normal }), let mySpace = mySite.spaces.first(where: { $0.id == space.id }), mySpace.state == .normal {
                        self.navigationController?.popViewController(animated: false)
                        let vc = SiteViewController(site: mySite)
                        vc.enterSpaceId = space.id
                        self.navigationController?.pushViewController(vc, animated: true)
                        return
                    }
                case .spaceList(let data, _, _):
                    // 自己分享的space，并且owner权限，跳转到site页面
                    if let mySite = self.allSites.first(where: { $0.id == data.siteId && $0.permission == .owner && $0.state == .normal }) {
                        self.navigationController?.popViewController(animated: false)
                        let vc = SiteViewController(site: mySite)
                        self.navigationController?.pushViewController(vc, animated: true)
                        return
                    }
                }
                self.navigationController?.popViewController(animated: false)
                
                let vc = SharePermissionSelectionController(type: type)
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                }
                self.present(NavigationViewController(rootViewController: vc), animated: true)
                self.scanCodeVc = nil
                
            case .failure(let error):
                if error == .resourceNotFound {
                    var title = "qr_code_invalid".localizedString
                    var message = "invalid_qr_code_message".localizedString
                    if !qrCode {
                        title = "shared_code_invalid".localizedString
                        message = "invalid_invitation_code_message".localizedString
                    }
                    self.showQRCodeFailed(title: title, message: message, messageAlignment: .left)
//                    XWHUDManager.showErrorTipHUD("shared_code_invalid".localizedString)
                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                        self?.scanCodeVc?.startScan()
                    }
                }
            }
        }
        
    }
    
    /// 加载mesh网络设备配置数据请求
    private func loadMeshDeviceConfigRequest() {
        
        NetworkRequest.shared.request(.devicesConfig) { result in
            switch result {
            case .success(let response):
                let list: [MeshDeviceConfigInfo] = JSON(response)["data"].arrayValue.compactMap({ json in
                    guard let companyIdHex = json["companyId"].string, let companyId = UInt16(hex: companyIdHex),
                          let productIdHex = json["productId"].string, let productId = UInt16(hex: productIdHex),
                          let categoryName = json["categoryName"].string, let elementCount = json["elementCount"].int,
                          let iconCategory = json["iconCategory"].string, let deviceCategory = json["deviceCategory"].string else {
                        return nil
                    }
                    var sensitivityRange: ClosedRange<UInt16>?
                    if let min = json["sensitivityRangeMin"].uInt16, let max = json["sensitivityRangeMax"].uInt16 {
                        sensitivityRange = min...max
                    }
                    
                    let modelName = json["modelName"].string
                    return MeshDeviceConfigInfo(companyId: companyId, productId: productId, categoryName: categoryName, elementCount: elementCount, iconCategory: iconCategory, deviceCategory: deviceCategory, modelName: modelName, sensitivityRange: sensitivityRange)
                })
                MeshLibManager.manager.supportDeviceInfos = list
                MeshDeviceConfigInfo.saveAll(list: list)
            case .failure(_):
                break
            }
        }
        
    }
    
    /// 菜单
    @objc private func menuClick() {
        if XWHUDManager.isVisible() {
            return
        }
        MainMenuView.show {[weak self] option in
            
            guard let self = self else { return }
            switch option {
            case .serverSelection:
                let vc = ServerSelectionViewController()
                // 选择别的地区回调
                vc.selectRegionCallback = {[weak self] _ in
                    self?.setupData()
                    self?.loadSitesRequest()
                }
                self.navigationController?.pushViewController(vc, animated: true)
            case .about:
                self.navigationController?.pushViewController(AboutViewController(), animated: true)
                self.showMenu = true
            case .user:
                self.navigationController?.pushViewController(UserSettingsViewController(), animated: true)
                self.showMenu = true
            }
        }
        
    }
    
    /// 导入
    @objc private func importClick() {
        
        
//        guard let space = favouriteSites.first?.spaces.last else {
//            return
//        }
//        guard let space = favouriteSites.last?.spaces.first else { return }
        
//        DispatchQueue.global().async {
//            MeshLibManager.manager.setMeshNetworkConnected(meshUUID: space.meshUUID, subNetworkId: space.meshNetworkId)
//            MeshLibManager.manager.publishModelIDs = []
//            MeshNetworkManager.instance.loadExtensionData { _ in
//                DispatchQueue.main.async {
//                    let group = MeshNetworkManager.instance.groups.first!
////                    let vc = ProfileDayNightLuxViewController(group: group)
//                    let vc = ProfileSettingsViewController(group: group, profile: group.info.profile)
//    //                let vc = GroupPathSequencePageController(group: group)
////                    let vc = DaliMasterViewController(space: space, node: MeshNetworkManager.instance.realNodes[0])
////                    let vc = DeviceRatedPowerCalibrationController(devices: MeshNetworkManager.instance.realNodes)
////                    let vc = DeviceParameterSettingsController(devices: MeshNetworkManager.instance.realNodes)
//                    self.present(NavigationViewController(rootViewController: vc), animated: true)
//                }
//            }
//        }
        
//        let vc = DeviceForceResetDevicePageController()
//        let vc = DeviceParameterSettingsController(devices: [])
//        let vc = DeviceRatedPowerCalibrationController(devices: [])
//        let vc = DeviceMeshNetworkResetController()
//        if isIPad {
//            vc.preferredContentSize = iPadStandardSize
//        }
//        self.present(NavigationViewController(rootViewController: vc), animated: true)
        
        ImportProjectView {[weak self] mode in
            if mode == .scanQRCode {
                self?.scanQRCode()
            }else {
                self?.uuidImport()
            }
        }.show()

    }
    
    /// 扫码导入数据
    private func scanQRCode() {
        
        LBXPermissions.authorizeCameraWith {[weak self] authorize in
            guard let self = self else { return }
            
            guard authorize else {
                let alertVc = UIAlertController(title: "camera_requires_alert_title".localizedString, message: "camera_requires_alert_message".localizedString, preferredStyle: .alert)
                alertVc.addAction(UIAlertAction(title: "alert_item_cancel".localizedString, style: .default))
                alertVc.addAction(UIAlertAction(title: "Settings".localizedString, style: .cancel, handler: { _ in
                    LBXPermissions.jumpToSystemPrivacySetting()
                }))
                present(alertVc, animated: true)
                return
            }
            
            var style = LBXScanViewStyle()
            style.xScanRetangleOffset = 30
            //            style.whRatio = 0.8
            //            style.isNeedShowScanBorder = false
            style.anmiationStyle = LBXScanViewAnimationStyle.None
            style.animationImage = UIImage(named: "scan_animation_line")
            style.photoframeAngleStyle = .Outer
            style.colorAngle = .white
            style.photoframeLineW = 3
            style.centerUpOffset = SCRYFit(80)
            
            let vc = LBXScanViewController()
            vc.scanStyle = style
            vc.isOpenInterestRect = true
            vc.scanResultDelegate = self
            vc.scanFineshedExit = false
            navigationController?.pushViewController(vc, animated: true)
            scanCodeVc = vc
        }
    }
    
    /// 输入uuid导入数据
    private func uuidImport() {
    
        SRAlertView(title: "invitation_code".localizedString, inputFieldStyle: .init(keyboardType: .asciiCapable, minInputLength: 8, maxInputLength: 8), actions: [.cancelAction, SRAlertAction(title: "add".localizedString)], textValueChangedBack: nil) {[weak self] uuid in
            // 是否有效邀请码
            guard uuid.isValidInvitationCode() else {
                self?.showQRCodeFailed(message: "shared_code_unknown".localizedString)
                return
            }
            self?.loadShareInfoRequest(shareId: uuid, qrCode: false)
        }.show()
        
    }
    
    @objc private func moreClick() {
        
//        guard let space = SpaceData.load(siteId: "25300E88-41F0-456E-A0A9-AD615069017C", spaceId: "88BF1DEC-264E-4D00-A93C-729A88030D58").first else {
//            return
//        }
//        
//        MeshLibManager.manager.setMeshNetworkConnected(meshUUID: space.meshUUID, subNetworkId: space.meshNetworkId)
//        let vc = DeviceAddViewController(space: space)
//        navigationController?.pushViewController(vc, animated: true)
        
//        return
        let touchCenterX = view.width - navigationRightItemMargin - 15
        
        let items: [MenuPopView.MenuItem] = [
            .init(icon: UIImage(named: "menu_nearby_network"), title: "nearby_network".localizedString, tapItemBack: { item in
                XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
            }),
            .init(icon: UIImage(named: "menu_transfer_account"), title: "transfer_account".localizedString, tapItemBack: { item in
                XWHUDManager.showTipHUD("under_development".localizedString, isLineFeed: true)
            })
        ]
        
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: touchCenterX, y: (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight)), menuWidth: SCRXFrom(154))
        
    }
    
    /// 添加场所
    @objc private func addSite() {
        
        
//        // 创建一个场所
        let site = SiteData.add(name: SiteData.getNextSiteName())
        allSites.append(site)
        setupSectionsData()
//        let insertPath = IndexPath(row: allSites.count - 1, section: 0)
//        allSitesTableView.insertRows(at: [insertPath], with: .none)
//        allSitesTableView.scrollToRow(at: insertPath, at: .bottom, animated: true)
        allSitesCollectionView.reloadData()
        updateEmptyView()
        
//        
//        // 跳转到场所页面
        let vc = SiteViewController(site: site, addSite: true)
        navigationController?.pushViewController(vc, animated: true)
        
        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .normal)
    }
    
    /// 编辑场所
    private func editSite(site: SiteData) {
        
        var imageNames: [String] = []
        for id in 1...28 {
            imageNames.append("site_\(id)")
        }
        let vc = InfoEditViewController(name: site.name, imageNames: imageNames, selectImageIndex: max(site.imageId - 1, 0), columnNum: 4)
        vc.nameEditChangedCallback = { name in
            return SiteData.isTautonym(siteName: name) && name != site.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            site.name = name
            site.imageId = imageId + 1
            site.lastUpdate = Int64(Date().timeIntervalSince1970)
            guard site.save() else {
                return true
            }
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .normal)
            self.reloadSiteData(site)
            
            return true
        }
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除场所
    private func deleteSite(site: SiteData) {
        
        // 上传到云端数据删除需有网络
        if !NetworkRequest.shared.networkable && site.uploadCloud {
            XWHUDManager.showTipHUD("phone_no_network".localizedString, isLineFeed: true)
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "alert_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            // 场所下面空间内存在设备
            if let space = site.spaces.first(where: { $0.deviceCount > 0 }) {
                // 删除不存在设备的空间list
//                    let emptySpaces = site.spaces.filter({ $0.deviceCount == 0 })
//                    emptySpaces.forEach { emptySpace in
//                        emptySpace.delete()
//                        site.spaces.removeAll(where: { $0.id == emptySpace.id })
//                    }
//                    site.save()
//                XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
                XWHUDManager.showTipHUD("site_delete_have_devies_message".localizedString, isLineFeed: true)
            }else { // 场所下空间未存在设备
                // site已上传到云端
                if site.uploadCloud {
                    // 删除site网络请求
                    self.deleteSiteReqeust(site: site)
                }else {
                    // 模拟删除过程
                    XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                        XWHUDManager.hide()
                        // 删除本地数据
                        self?.delteSiteLocalData(site: site)
                    }
                }
            }
            
        })]).show()
    }
    
    /// 删除site网络请求
    private func deleteSiteReqeust(site: SiteData) {
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.siteDelete(siteId: site.id)) {[weak self] result in
            XWHUDManager.hide()
            switch result {
            case .success(_):
                self?.delteSiteLocalData(site: site)
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
    
    /// 删除site本地数据
    private func delteSiteLocalData(site: SiteData) {
        // 是否有同步操作正在进行,进行中则取消任务
        CloudSynchronizationManager.shared.cancelSynchronizationHandle(site: site)
        
        site.delete()
//        var index: Int?
//        var currentTableView: UITableView?
//        var otherTableView: UITableView?
//        if self.segmentedControl.selectedIndex == 0 {
//            index = allSites.firstIndex(where: { $0.id == site.id })
//            currentTableView = allSitesTableView
//            otherTableView = favouritesTableView
//        }else {
//            index = favouriteSites.firstIndex(where: { $0.id == site.id })
//            currentTableView = favouritesTableView
//            otherTableView = allSitesTableView
//        }
        self.allSites.removeAll(where: { $0.id == site.id })
        self.favouriteSites.removeAll(where: { $0.id == site.id })
        
        self.setupSectionsData()
//        if let index = index, let tableView = currentTableView {
//            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
//            otherTableView?.reloadData()
//        }else {
        self.allSitesCollectionView.reloadData()
        self.favouritesCollectionView.reloadData()
//         }
        self.updateEmptyView()
        
    }
    
    /// 分享
    private func share(site: SiteData) {
        
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
        
        // 获取邀请信息
        
        let vc = ShareAuthorityViewController(site: site, type: .share)
        if isIPad {
            vc.preferredContentSize = iPadPreferredContentSize
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
//        let dict = site.export()
////        print(dict)
//        if let data = try? JSONSerialization.data(withJSONObject: dict) {
//            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(site.name).json")
//            try? data.write(to: fileURL)
//            let controller = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
//            controller.completionWithItemsHandler = { type, success, items, error in
//                if success {
//                    XWHUDManager.showSuccessTipHUD("successful")
//                }
//            }
//            self.present(controller, animated: true)
//        }
        
    }
    
    /// 转让Site
    private func transferSite(site: SiteData) {
        
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
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        
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
                if let password = JSON(response)["data"]["transPasswd"].string {
                    if site.transferPassword != password {
                        site.transferPassword = password
                        site.save()
                    }
                }
                
                // 转让码
                if site.transferCode != code {
                    site.transferCode = code
                    site.save()
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
    
    
    /// site菜单
    private func siteMenu(site: SiteData, point: CGPoint) {
        
        var items: [MenuPopView.MenuItem] = []
             
        if site.permissionOperates.contains(.edit) {
            items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit_site".localizedString, tapItemBack: {[weak self] item in
                self?.editSite(site: site)
            }))
        }
        
        if site.permissionOperates.contains(.delete) {
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete_site".localizedString, tapItemBack: {[weak self] item in
                self?.deleteSite(site: site)
            }))
        }
        
        items.append(.init(icon: UIImage(named: "menu_share"), title: "share_authoority".localizedString, tapItemBack: {[weak self] _ in
            self?.share(site: site)
        }))
        
        if site.permissionOperates.contains(.transfer) {
            items.append(.init(icon: UIImage(named: "menu_transfer_site"), title: "transfer_site".localizedString, tapItemBack: {[weak self] _ in
                self?.transferSite(site: site)
            }))
        }
        
        if site.state == .waitDeleted && site.permission == .owner { // 清空数据
            items.removeAll()
            items.append(.init(icon: UIImage(named: "menu_delete"), title: "clear_cache_site".localizedString, tapItemBack: {[weak self] _ in
                self?.delteSiteLocalData(site: site)
            }))
        }
        
        MenuPopView.show(items: items, anchorPoint: point, menuWidth: SCRXFrom(144))
    }
    
    /// 更新同步状态
    private func updateSyncState() {
        
        if view.window != nil, let state = CloudSynchronizationManager.shared.getSitesCurrentSyncState() {
            switch state {
            case .inProgress:
                self.showNavigationBarLoading()
            case .successful:
                self.showNavigationBarSuccessful()
            case .failure:
                self.showNavigationBarFailure(duration: 2, actionCallback: nil)
            case .cancel:
                self.hideNavigationBarState()
            default:
                break
            }
        }
    }
    
    /// 没有网络UI
    private func updateNoInternetUI() {
        if NetworkRequest.shared.networkable {
            
            allSitesNoInternetView?.removeFromSuperview()
            favouritesNoInternetView?.removeFromSuperview()
            
            allSitesCollectionView.contentInset.top = 0
            favouritesCollectionView.contentInset.top = 0
            
//            allSitesTableView.tableHeaderView = nil
//            favouritesTableView.tableHeaderView = nil
        }else {
            if allSitesNoInternetView == nil || favouritesNoInternetView == nil {
                allSitesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: -noInternetHeight, width: self.allSitesCollectionView.width, height: noInternetHeight))
                favouritesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: -noInternetHeight, width: self.favouritesCollectionView.width, height: noInternetHeight))
            }
            allSitesCollectionView.addSubview(allSitesNoInternetView!)
            allSitesCollectionView.contentInset.top = noInternetHeight

            favouritesCollectionView.addSubview(favouritesNoInternetView!)
            favouritesCollectionView.contentInset.top = noInternetHeight
            
            allSitesCollectionView.setContentOffset(CGPoint(x: allSitesCollectionView.contentOffset.x, y: -noInternetHeight), animated: false)
            favouritesCollectionView.setContentOffset(CGPoint(x: favouritesCollectionView.contentOffset.x, y: -noInternetHeight), animated: false)
            
//            allSitesTableView.tableHeaderView = allSitesNoInternetView
//            favouritesTableView.tableHeaderView = favouritesNoInternetView
        }
//        allSitesCollectionView.reloadData()
//        favouritesCollectionView.reloadData()
//        if let emptyView = allSitesCollectionView.emptyView {
//            emptyView.contentView.snp.updateConstraints({ make in
//                let margin = NetworkRequest.shared.networkable ? 0 : noInternetHeight
//                make.top.equalTo(SCRYFrom(7) + margin)
//            })
//        }
    }
    
    private func updateEmptyView() {
        
        if scrollView.frame == .zero {
            view.layoutIfNeeded()
        }
        
        if allSites.isEmpty {
             var frame = allSitesCollectionView.bounds
            frame.origin.y = allSitesCollectionView.y
            allSitesCollectionView.showEmptyDataView(frame: frame, imageName: "site_empty", title: "no_sites_title".localizedString, tipText: nil)
            if let emptyView = allSitesCollectionView.emptyView {
//                let margin = NetworkRequest.shared.networkable ? 0 : noInternetHeight
                
                
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
                let attStr = NSAttributedString(string: "no_sites_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
                emptyView.tipLabel.attributedText = attStr
            }
           
        }else {
            allSitesCollectionView.hideEmptyDataView()
        }
        
        if favouriteSites.isEmpty {
            favouritesCollectionView.showEmptyDataView(frame: favouritesCollectionView.bounds, title: "no_favourites_sites".localizedString)
        }else {
            favouritesCollectionView.hideEmptyDataView()
        }
        
    }
    
    /// 刷新site
    private func reloadSiteData(_ site: SiteData) {
        
        // 刷新数据
        var indexPath: IndexPath?
        var currentCollectionView: UICollectionView?
        if self.segmentedControl.selectedIndex == 0 {
            if let index = allSites.filter({ $0.permission == .owner }).firstIndex(where: { $0.id == site.id }) {
                indexPath = IndexPath(row: index, section: 0)
            }else if let index = allSites.filter({ $0.permission == .visitor }).firstIndex(where: { $0.id == site.id }) {
                indexPath = IndexPath(row: index, section: 1)
            }
            currentCollectionView = allSitesCollectionView
        }else {
            if let index = favouriteSites.filter({ $0.permission == .owner }).firstIndex(where: { $0.id == site.id }) {
                indexPath = IndexPath(row: index, section: 0)
            }else if let index = favouriteSites.filter({ $0.permission == .visitor }).firstIndex(where: { $0.id == site.id }) {
                indexPath = IndexPath(row: index, section: 1)
            }
            currentCollectionView = favouritesCollectionView
        }
        CATransaction.setDisableActions(true)
        if let reloadIndexPath = indexPath, let collectionView = currentCollectionView {
            collectionView.reloadItems(at: [reloadIndexPath])
        }else {
            self.allSitesCollectionView.reloadData()
            self.favouritesCollectionView.reloadData()
        }
        CATransaction.commit()
    }
    
    

    private func setupUI() {
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: ["all_sites".localizedString, "favourites_sites".localizedString])
//        segmented.selectedIndex = 1
        segmentedControl.delegate = self
        view.addSubview(segmentedControl)
//        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(16))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(44))
        }
        
        scrollView = UIScrollView()
        scrollView.isPagingEnabled = true
        scrollView.bounces = false
        scrollView.delegate = self
        scrollView.showsHorizontalScrollIndicator = false
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(segmentedControl.snp.bottom).offset(SCRYFrom(20))
        }
        
        allSitesRefreshControl = UIRefreshControl()
        allSitesRefreshControl.tintColor = UIColor.lightGray
        allSitesRefreshControl.addTarget(self, action: #selector(loadSitesRequest), for: .valueChanged)
        
        allSitesFlowLayout = UICollectionViewFlowLayout()
        if isIPad {
            allSitesFlowLayout.minimumLineSpacing = SCRXFrom(18)
            allSitesFlowLayout.minimumInteritemSpacing = SCRXFrom(18)
        }else {
            allSitesFlowLayout.minimumLineSpacing = SCRXFrom(16)
            allSitesFlowLayout.minimumInteritemSpacing = SCRXFrom(16)
        }
        
        allSitesCollectionView = UICollectionView(frame: .zero, collectionViewLayout: allSitesFlowLayout)
        allSitesCollectionView.backgroundColor = .clear
        allSitesCollectionView.register(SitesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        allSitesCollectionView.register(CollectionTitleHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "title")
//        allSitesCollectionView.rowHeight = SCRYFrom(92)
        allSitesCollectionView.dataSource = self
        allSitesCollectionView.delegate = self
        allSitesCollectionView.refreshControl = allSitesRefreshControl
        scrollView.addSubview(allSitesCollectionView)
        allSitesCollectionView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        favouritesRefreshControl = UIRefreshControl()
        favouritesRefreshControl.tintColor = UIColor.lightGray
        favouritesRefreshControl.addTarget(self, action: #selector(loadSitesRequest), for: .valueChanged)
        
        favouritesSitesFlowLayout = UICollectionViewFlowLayout()
        if isIPad {
            favouritesSitesFlowLayout.minimumLineSpacing = SCRXFrom(18)
            favouritesSitesFlowLayout.minimumInteritemSpacing = SCRXFrom(18)
        }else {
            favouritesSitesFlowLayout.minimumLineSpacing = SCRXFrom(16)
            favouritesSitesFlowLayout.minimumInteritemSpacing = SCRXFrom(16)
        }
      
        favouritesCollectionView = UICollectionView(frame: .zero, collectionViewLayout: favouritesSitesFlowLayout)
        favouritesCollectionView.backgroundColor = .clear
        favouritesCollectionView.register(SitesViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        favouritesCollectionView.register(CollectionTitleHeaderView.classForCoder(), forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "title")
//        allSitesCollectionView.rowHeight = SCRYFrom(92)
        favouritesCollectionView.dataSource = self
        favouritesCollectionView.delegate = self
        favouritesCollectionView.refreshControl = favouritesRefreshControl
        scrollView.addSubview(favouritesCollectionView)
        favouritesCollectionView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.left.equalTo(allSitesCollectionView.snp.right)
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        addSiteBtn = UIButton(normalImageName: "add", target: self, action: #selector(addSite))
        view.addSubview(addSiteBtn)
        addSiteBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-38))
        }
        
        if isIPad {
            allSitesCollectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(20), bottom: SCRYFrom(38) + 20, right: SCRXFrom(20))
        }else {
            allSitesCollectionView.contentInset = UIEdgeInsets(top: 0, left: SCRXFrom(16), bottom: SCRYFrom(38) + 20, right: SCRXFrom(16))
        }
        favouritesCollectionView.contentInset = allSitesCollectionView.contentInset
        
//        buoySliderView = BuoySliderView(frame: .zero, functionType: .level())
//        view.addSubview(buoySliderView)
//        buoySliderView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(30))
//            make.right.equalTo(SCRXFrom(-29))
//            make.bottom.equalTo(-173)
//            make.height.equalTo(SCRYFrom(40) + 36)
//        }
    }
    
    
    /// 提示扫码失败
    private func showQRCodeFailed(title: String? = nil, message: String, messageAlignment: NSTextAlignment = .center) {
        let alertView = SRAlertView(title: title, message: message, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            self?.scanCodeVc?.startScan()
        })])
        alertView.messageLabel.textAlignment = messageAlignment
        alertView.show()
        
    }

}

extension SitesViewController {
    
    override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
        return CGSize(width: 0, height: 0)
    }
}

//extension SitesViewController: NavigationViewControllerDelegate {
//    /// 导航控制器点击back事件
//    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
//        if navigationController.children.count > 1 {
//            navitionItemBack = true
//        }
//    }
//}

extension SitesViewController: CustomSegmentedControlDelegate {
    
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        
        scrollView.setContentOffset(CGPoint(x: CGFloat(index) * scrollView.frame.size.width, y: 0), animated: true)
    }
}

extension SitesViewController: UIScrollViewDelegate {
    
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

extension SitesViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        if collectionView == allSitesCollectionView {
            return allSections.count
        }else {
            return favouriteSections.count
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if collectionView == allSitesCollectionView {
            switch allSections[section] {
            case .personal:
                return allSites.filter({ $0.permission == .owner }).count
            case .received:
                return allSites.filter({ $0.permission != .owner }).count
            }
        }else {
            switch favouriteSections[section] {
            case .personal:
                return favouriteSites.filter({ $0.permission == .owner }).count
            case .received:
                return favouriteSites.filter({ $0.permission != .owner }).count
            }
        }
    }
 
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! SitesViewCell
        var site: SiteData!
        if collectionView == allSitesCollectionView {
            let section = allSections[indexPath.section]
            if section == .personal {
                site = allSites.filter({ $0.permission == .owner })[indexPath.row]
            }else {
                site = allSites.filter({ $0.permission != .owner })[indexPath.row]
            }
        }else {
            let section = favouriteSections[indexPath.section]
            if section == .personal {
                site = favouriteSites.filter({ $0.permission == .owner })[indexPath.row]
            }else {
                site = favouriteSites.filter({ $0.permission != .owner })[indexPath.row]
            }
        }
        cell.nameLabel.text = site.name
        cell.iconImageView.image = UIImage(named: "site_\(site.imageId)")
        cell.timeLabel.text = String.dateConvert(timestamp: "\(site.create)", dateFormat: "M/d/yyyy hh:mm a")
        if site.spaces.isEmpty {
            cell.spaceNumLabel.text = "\(site.spaceCount ?? site.spaces.count) \("spaces".localizedString)"
        }else {
            cell.spaceNumLabel.text = "\(site.spaces.count) \("spaces".localizedString)"
        }
        
        cell.favoriteBtn.isSelected = site.isFavourite

        // 已转让site待删除缓存
        if site.permission == .owner && site.state == .waitDeleted {
            cell.syncFailedImageView.isHidden = false
            cell.syncFailedImageView.image = UIImage(named: "site_transferred")
            cell.iconImageView.alpha = 0.5
        }else {
            cell.syncFailedImageView.image = UIImage(named: "cloud_sync_failed")
            // 自己有同步错误 / 自己有需要同步但是不在同步中 / 下面space有同步错误
            if site.showSyncCloudError != nil || site.spaces.contains(where: { $0.showSyncCloudError != nil }) {
                cell.syncFailedImageView.isHidden = false
            }else {
                cell.syncFailedImageView.isHidden = true
            }
            cell.iconImageView.alpha = 1
        }
//        cell.syncFailedImageView.isHidden = !(site.syncCloudError != nil || site.spaces.contains(where: { $0.syncCloudError != nil }))
        cell.clickMoreCallback = {[weak self] point in
            guard let self = self else { return }
            let tableviewPoint = collectionView.convert(point, from: cell)
            let viewPoint = view.convert(tableviewPoint, from: collectionView)
    //        [weakself.view convertPoint:tableviewPoint fromView:tableView];
            self.siteMenu(site: site, point: viewPoint)
        }
        cell.clickFavouriteCallback = {[weak self] isFavourite in
            guard let self = self else { return }
            site.isFavourite = isFavourite
//            site.lastUpdate = Int64(Date().timeIntervalSince1970)
            site.save()
            if isFavourite {
                self.favouriteSites.append(site)
                // 创建时间排序
                self.favouriteSites = self.favouriteSites.sorted { site1, site2 in
                    return site1.create < site2.create
                }
            }else {
                self.favouriteSites.removeAll(where: { $0.id == site.id })
            }
            self.setupSectionsData()
            self.allSitesCollectionView.reloadData()
            self.favouritesCollectionView.reloadData()
            self.updateEmptyView()
//            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .normal)
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let headerView = collectionView.dequeueReusableSupplementaryView(ofKind: UICollectionView.elementKindSectionHeader, withReuseIdentifier: "title", for: indexPath) as! CollectionTitleHeaderView
        var sectionType: SectionType = .personal
        if collectionView == allSitesCollectionView {
            sectionType = allSections[indexPath.section]
        }else {
            sectionType = favouriteSections[indexPath.section]
        }
        headerView.titleLabel.text = sectionType.rawString
        headerView.titleLeftMargin = SCRXFrom(12)
        return headerView
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        return CGSize(width: collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right, height: section == 0 ? SCRYFrom(25) : SCRYFrom(41))
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let padding = (collectionViewLayout as? UICollectionViewFlowLayout)?.minimumLineSpacing ?? 0
        var itemW = ((collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right) - CGFloat(self.itemRowCount - 1) * padding) / CGFloat(self.itemRowCount)
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSizeMake(itemW, SCRYFrom(76))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        var site: SiteData!
//        if tableView == allSitesTableView {
//            site = allSites[indexPath.row]
//        }else {
//            site = favouriteSites[indexPath.row]
//        }
        if collectionView == allSitesCollectionView {
            let section = allSections[indexPath.section]
            if section == .personal {
                site = allSites.filter({ $0.permission == .owner })[indexPath.row]
            }else {
                site = allSites.filter({ $0.permission != .owner })[indexPath.row]
            }
        }else {
            let section = favouriteSections[indexPath.section]
            if section == .personal {
                site = favouriteSites.filter({ $0.permission == .owner })[indexPath.row]
            }else {
                site = favouriteSites.filter({ $0.permission != .owner })[indexPath.row]
            }
        }
        if site.state == .waitDeleted && site.permission == .owner { // 已转让
            XWHUDManager.showTipHUD("have_been_transferred".localizedString, isLineFeed: true)
            return
        }
        ImportProjectView.dismiss()
        MenuPopView.hide()
        
        let vc = SiteViewController(site: site)
        navigationController?.pushViewController(vc, animated: true)
    }

}

extension SitesViewController: LBXScanViewControllerDelegate {
    
    /// 扫码结果
    func scanFinished(scanResult: LBXScanResult, error: String?) {
        
        guard let content = scanResult.strScanned, let code = content.components(separatedBy: "/").first, code.isValidInvitationCode() else {
            showQRCodeFailed(message: "unknown_qr_code".localizedString)
            return
        }
        // 二维码分享人权限
        var sharePermission: Permission?
        let array = content.components(separatedBy: "/")
        if array.count == 2, let type = array.last, let value = Int(type), let permission = Permission(rawValue: value) {
            sharePermission = permission
        }
        loadShareInfoRequest(shareId: code, qrCode: true, sharePermission: sharePermission)
        
    }
}

extension SitesViewController: CloudSynchronizationManagerDelegate {
    /// 开始同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle) {
        updateSyncState()
        switch handle.operation {
        case .syncSite(let site, _):
            reloadSiteData(site)
        case .syncSpace(let space):
            if let site = allSites.first(where: { $0.id == space.siteId }) {
                reloadSiteData(site)
            }
        case .addSpaces(let site, _):
            reloadSiteData(site)
        }
    }
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSyncManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError) {
        updateSyncState()
        
        switch handle.operation {
        case .syncSite(let site, _):
            reloadSiteData(site)
        case .syncSpace(let space):
            if let site = allSites.first(where: { $0.id == space.siteId }) {
                reloadSiteData(site)
            }
        case .addSpaces(let site, _):
            reloadSiteData(site)
        }
    }
    
    /// 同步数据操作取消回调
    func cloudSyncManager(_ manager: CloudSynchronizationManager, cancelSyncHandle handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
}

