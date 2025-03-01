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
let SpacesRefreshChangeNotificationName = "SpacesRefreshChangeNotification"

class SiteViewController: UIViewController {

    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: PopGestureScrollView!
    private var allSpacesCollectionView: UICollectionView!
    private var allSpacesFlowLayout: UICollectionViewFlowLayout!
    
    private var favouritesCollectionView: UICollectionView!
    private var favouritesFlowLayout: UICollectionViewFlowLayout!
    private var allSpacesNoInternetView: NoInternetHeaderView?
    private var favouritesNoInternetView: NoInternetHeaderView?
    
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
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))

        setupUI()
        
        allSpaces = site.spaces
        favouriteSpaces = allSpaces.filter({ $0.isFavourite })
        
        NetworkRequest.shared.addObserver(self, forKeyPath: "networkable", context: nil)
//        MeshLibManager.manager.setMeshNetworkConnected(meshUUID: site.meshUUID, connected: false)
        
        NotificationCenter.default.addObserver(forName: .init(SiteStateChangeNotificationName), object: nil, queue: nil) {[weak self] _ in
            guard let self = self else { return }
            if self.site.state == .waitDeleted {
                NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
                self.navigationController?.popViewController(animated: true)
            }else {
                if self.view.window != nil {
                    self.reloadData = false
                    allSpaces = site.spaces
                    favouriteSpaces = allSpaces.filter({ $0.isFavourite })
                    loadSiteRequest()
                }else {
                    self.reloadData = true
                }
            }
        }
        
        /// 刷新spaces列表通知回调
        NotificationCenter.default.addObserver(forName: .init(SpacesRefreshChangeNotificationName), object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            if notification.object as? Bool ?? false {
                // 更新缓存数据
                site.spaces = SpaceData.load(siteId: site.id)
            }
            allSpaces = site.spaces
            favouriteSpaces = allSpaces.filter({ $0.isFavourite })
            if self.view.window != nil {
                self.allSpacesCollectionView.reloadData()
                self.favouritesCollectionView.reloadData()
                self.updateEmptyView()
            }
        }
        
//        updateEmptyView()
        updateNoInternetUI()
        
        if NetworkRequest.shared.networkable && site.uploadCloud {
            loadSiteRequest()
            // 判断是否有放弃的地址需要回收
//            if let addressData = site.recycleAddressData {
//                recyclingAddressRequest(abandonAddressData: addressData)
//            }
        }
        
//        MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.site.meshUUID, subNetwork: self.allSpaces.first?.meshNetworkKey, connected: true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if reloadData {
            reloadData = false
            allSpaces = site.spaces
            favouriteSpaces = allSpaces.filter({ $0.isFavourite })
            loadSiteRequest()
        }
        self.allSpacesCollectionView.reloadData()
        self.favouritesCollectionView.reloadData()
        self.updateEmptyView()
     
        CloudSynchronizationManager.shared.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if addSite {
            addSite = false
            addSpace()
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
        NetworkRequest.shared.removeObserver(self, forKeyPath: "networkable")
//        MeshLibManager.manager.meshNetworkDisconnect()
    }
    
    /// KVO监听
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "networkable" { // 手机网络连接状态
            updateNoInternetUI()
            
            if NetworkRequest.shared.networkable { // 无网络=>有网络
                // 自动上传
                
                
            }else { // 有网络=>无网络
                SRAlertView(title: "notification".localizedString, message: "phone_network_disconnect".localizedString, actions: [.init(title: "confirm".localizedString)]).show()
            }
        }
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
            
            switch result {
            case .success(let response):
                if let siteData = JSON(response)["data"].dictionaryObject {
//                    let site = SiteData.import(siteJsonData: siteData)
                    Task {
                        print("导入数据: \(Date().timeIntervalSince1970)")
                        await self.site.update(siteJsonData: siteData)
                        print("导入数据完成: \(Date().timeIntervalSince1970)")
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
//                        self.site.save(allData: true)
//                        // 未提交到服务器的本地数据
//                        let localSpaces = self.allSpaces.filter({ localSpace in !self.site.spaces.contains(where: { $0.id == localSpace.id }) && !localSpace.uploadCloud })
//                        self.site.spaces.append(contentsOf: localSpaces)
//                        self.site.spaces.append(contentsOf: deleteSpaces)
//                        self.site.spaces.sort(by: { $0.create < $1.create })
                        
                        self.allSpaces = self.site.spaces
                        self.favouriteSpaces = self.allSpaces.filter({ $0.isFavourite })
                        self.allSpacesCollectionView.reloadData()
                        self.favouritesCollectionView.reloadData()
                        self.updateEmptyView()
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
                                        self.reloadSpaceData($0)
                                    }
                                })
                                self.site.recycleAddressData = await self.site.getRecycleAddressData(unbindSpaces: self.site.spaces)
                                self.site.save()
                            }
                            
                            // 判断site内是否有需要回收的地址
                            if !(self.site.recycleAddressData?.isEmpty ?? true) {
                                try? await self.siteRecyclingAddressRequest(site: self.site)
                            }
                        }
                    }
                    
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
                    }
                case .noSpacePermission, .userUnauthorized: // 无权限
                    if space.permission == .editor || space.permission == .visitor {
                        // 设置space为待删除状态
                        space.state = .waitDeleted
                        space.save()
                        self.reloadSpaceData(space)
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
    
    // MARK: - Action
    
    @objc private func moreClick() {
        // item距离右边间距 iphone6s 8 iphone12promax 12
        // 19 * 0.5 = 9.5 + 12
//        let margin: CGFloat = SCRXFrom(15.5)
//        isIphoneX ? 18 : 15
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
            
            self.allSpaces.append(space)
            let insertPath = IndexPath(row: self.allSpaces.count - 1, section: 0)
            self.allSpacesCollectionView.insertItems(at: [insertPath])
            self.allSpacesCollectionView.scrollToItem(at: insertPath, at: .bottom, animated: true)
            self.updateEmptyView()
            
            return true
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
        self.site.spaces.removeAll(where: { $0.id == space.id })
        // 删除数据
        var index: Int?
        var currentCollectionView: UICollectionView?
        var otherCollectionView: UICollectionView?
        if self.segmentedControl.selectedIndex == 0 {
            index = allSpaces.firstIndex(where: { $0.id == space.id })
            currentCollectionView = allSpacesCollectionView
            otherCollectionView = favouritesCollectionView
        }else {
            index = favouriteSpaces.firstIndex(where: { $0.id == space.id })
            currentCollectionView = favouritesCollectionView
            otherCollectionView = allSpacesCollectionView
        }
        self.allSpaces.removeAll(where: { $0.id == space.id })
        self.favouriteSpaces.removeAll(where: { $0.id == space.id })
        if let index = index, let collectionView = currentCollectionView {
            collectionView.deleteItems(at: [IndexPath(row: index, section: 0)])
            otherCollectionView?.reloadData()
        }else {
            self.allSpacesCollectionView.reloadData()
            self.favouritesCollectionView.reloadData()
        }
        self.updateEmptyView()
        
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
                self.present(NavigationViewController(rootViewController: vc), animated: true) {
                    XWHUDManager.hide()
                }
            case .failure(let error):
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
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
        if let shareCode = space.shareCode, space.editorPassword != nil || space.permission == .editor {
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
                self.present(NavigationViewController(rootViewController: vc), animated: true) {
                    XWHUDManager.hide()
                }
            case .failure(let error):
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    
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
                if self.site.permission == .visitor && self.site.spaces.isEmpty {
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

        loadSpaceReqeust(space: space)
    }
    
    /// 进入space
    private func intoSpace(space: SpaceData) {
        
        guard self.view.window != nil else {
            return
        }
        
        let spaceVc = SpaceViewController(space: space)
        spaceVc.site = site
        spaceVc.deleteSpaceCallback = {[weak self] in
            guard let self = self else { return  }
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
        SRAlertView(title: "notification".localizedString, message: message, inputText: nil, inputFieldStyle: .init(placeholder: "Password".localizedString, keyboardType: .numberPad, margin: SCRXFrom(56), height: SCRYFrom(32), minInputLength: 4, maxInputLength: 4, borderColor: RGB(153, 153, 153, 0.3), textAlignment: .center, secret: true, showClear: false), actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString)], textValueChangedBack: nil) {[weak self] password in
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
            var frame = allSpacesCollectionView.bounds
            frame.origin.y = 0
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
            allSpacesCollectionView.hideEmptyDataView()
        }
        
        if favouriteSpaces.isEmpty {
            favouritesCollectionView.showEmptyDataView(frame: favouritesCollectionView.bounds, title: "no_favourites_spaces".localizedString, bottomMargin: SCRYFrom(32))
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
            make.top.equalTo(segmentedControl.snp.bottom).offset(SCRYFrom(20))
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
        if favourite {
            self.favouriteSpaces.append(space)
            // 创建时间排序
            self.favouriteSpaces = self.favouriteSpaces.sorted { space1, space2 in
                return space1.create < space2.create
            }
        }else {
            self.favouriteSpaces.removeAll(where: { $0.id == space.id })
        }
        self.allSpacesCollectionView.reloadData()
        self.favouritesCollectionView.reloadData()
        self.updateEmptyView()
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
        }
        
    }
    
    /// 同步数据操作取消回调
    func cloudSyncManager(_ manager: CloudSynchronizationManager, cancelSyncHandle handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
}
