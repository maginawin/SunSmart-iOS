//
//  SitesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/20.
//

import UIKit
import SwiftyJSON

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

    private var showMenu: Bool = false
    
    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: UIScrollView!
    private var allSitesTableView: UITableView!
    private var allSitesNoInternetView: NoInternetHeaderView?
    private var favouritesTableView: UITableView!
    private var favouritesNoInternetView: NoInternetHeaderView?
    
    /// 所有site刷新
    private var allSitesRefreshControl: UIRefreshControl!
    /// 喜欢的site刷新
    private var favouritesRefreshControl: UIRefreshControl!

    private var addSiteBtn: UIButton!
    
    private var allSites: [SiteData] = []
    private var favouriteSites: [SiteData] = []
    private var reloadData: Bool = false
    /// 导航控制器是否点击back返回
    private var navitionItemBack: Bool = false
    
    private var allSections: [SectionType] = []
    private var favouriteSections: [SectionType] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
      
        title = "sites".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "menu_icon")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(menuClick))
        navigationItem.rightBarButtonItems = [
            UIBarButtonItem(customView: UIButton(normalImageName: "more_vertical", target: self, action: #selector(moreClick))),
            UIBarButtonItem(customView: UIButton(normalImageName: "import", target: self, action: #selector(importClick))),
        ]

        NotificationCenter.default.addObserver(self, selector: #selector(refreshData), name: .init(SitesDataRefreshNotifiacationName), object: nil)
        
        NetworkRequest.shared.addObserver(self, forKeyPath: "networkable", context: nil)
        
        
        setupUI()
        setupData()
        
//        allSitesTableView.tableHeaderView = allSitesNoInternetView
//        favouritesTableView.tableHeaderView = favouritesNoInternetView
        
        if Keychain.getServerRegion() == nil { // 还未选择服务器地区
            let defalutRegion = ServerRegion(regionCode: Locale.current.regionCode) ?? .northAmerica
            ServerSelectionView(selectRegion: defalutRegion) {[weak self] region in
                UserData.currentServerRegion = region
                self?.setupData()
                self?.loadSitesRequest()
            }.show()
        }
        
//        Task {
//            let site = allSites.first!
//            let data = await site.export(spaceIds: [site.spaces.first!.id])
//            print("1111")
//        }
//        print("2222")
//        if let contentView = navigationController?.navigationBar.subviews[1], let titleLabel = contentView.subviews.first(where: { $0.isKind(of: UILabel.classForCoder()) }) {
//            let icon = UIImageView(image: UIImage(named: "sync_loading_small"))
//            icon.layer.addRotationAnimation(duration: 1.2, repeatCount: 999)
//            contentView.addSubview(icon)
//            icon.snp.makeConstraints { make in
//                make.right.equalTo(titleLabel.snp.left).offset(SCRXFrom(-3))
//                make.centerY.equalToSuperview()
//            }
//        
//        }
        
//        loadSitesRequest()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        (navigationController as? NavigationViewController)?.navigationDelegate = self
        
        if reloadData {
            reloadData = false
            setupData()
        }else {
            allSitesTableView.reloadData()
            favouritesTableView.reloadData()
        }
        // 点击back返回，回到menu页面
        if navitionItemBack && showMenu {
            showMenu = false
            menuClick()
        }
        navitionItemBack = false
        
        CloudSynchronizationManager.shared.delegate = self
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // pop手势返回，回到menu页面
        if showMenu {
            showMenu = false
            menuClick()
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
        
        (navigationController as? NavigationViewController)?.navigationDelegate = nil
    }
    
    /// KVO监听
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "networkable" { // 手机网络连接状态
            updateNoInternetUI()
            if view.window != nil {
                loadSitesRequest()
            }
        }
    }
    
    
    /// 数据源
    private func setupData() {
        let sites = SiteData.loadAll()
        allSites = sites
        favouriteSites = sites.filter({ $0.isFavourite })
        
        setupSectionsData()
        
        allSitesTableView.reloadData()
        favouritesTableView.reloadData()
        
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
    
    /// 刷新数据通知回掉
    @objc private func refreshData() {
        reloadData = true
    }
    
    // MARK: - Reqeuest
    /// 获取site列表请求
    @objc private func loadSitesRequest() {
        
        // 判断是否联网
        guard NetworkRequest.shared.networkable else {
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        NetworkRequest.shared.request(.sites) {[weak self] result in
            guard let self = self else { return }
            
            self.allSitesRefreshControl.endRefreshing()
            self.favouritesRefreshControl.endRefreshing()
            switch result {
            case .success(let response):
                if var siteDatas = JSON(response)["data"].arrayObject as? [[String: Any]] {
                    Task {
                        var sites: [SiteData] = []
                        // 导入site数据属于耗时操作，等待异步线程完成
                        while let data = siteDatas.first {
                            if let site = await SiteData.import(siteJsonData: data) {
                                sites.append(site)
                            }
                            siteDatas.removeFirst()
                        }
                            
                        // site已提交到服务器，但是本地有但是服务器没有
                        let deleteSites = self.allSites.filter({ localSite in !sites.contains(where: { $0.id == localSite.id }) && localSite.uploadCloud })
                        
                        deleteSites.forEach({ site in
                            if site.permission == .visitor {
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
                                // 设置site为待删除
                                site.state = .waitDeleted
                                site.save()
                            }
                        })
                        sites.forEach({ $0.save() })
                        self.setupData()
                        XWHUDManager.hideInView(with: self.view)
                    }
                }else {
                    XWHUDManager.hideInView(with: self.view)
                }
            case .failure(_):
                XWHUDManager.hideInView(with: self.view)
            }
        }
        
    }
    
    
    /// 菜单
    @objc private func menuClick() {
        
//        SRAlertView(title: "notification".localizedString, message: "device_sync_message".localizedString + "\n\n", messageColor: Title_Color, messageFont: UIFont.systemFont(ofSize: 14, weight: .light), messageAttBtnStyle: SRAlertMessageAttBtnStyle(offset: CGPoint(x: 0, y: 30), text: "device_sync_message_more".localizedString, textColor: SubText_Color, textFont: UIFont.systemFont(ofSize: FontFit(14), weight: .light), imageName: "space_arrow_down",selectImageName: "space_arrow_up", underline: false, actionHandler: {
//            guard let alertView = SRAlertView.getCurrentAlertView() else { return }
//            if alertView.messageAttStrBtn.isSelected {
//                alertView.messageLabel.text = "device_sync_message".localizedString + "\n\n\n\n" + "device_sync_sub_message".localizedString
//                alertView.messageAttStrBtn.snp.updateConstraints { make in
//                    make.centerX.equalTo(alertView.messageLabel).offset(0)
//                    make.centerY.equalTo(alertView.messageLabel).offset(-10)
//                }
//            }else {
//                alertView.messageLabel.text = "device_sync_message".localizedString + "\n\n"
//                alertView.messageAttStrBtn.snp.updateConstraints { make in
//                    make.centerX.equalTo(alertView.messageLabel).offset(0)
//                    make.centerY.equalTo(alertView.messageLabel).offset(30)
//                }
//            }
//            
//        }), actions: [SRAlertAction(title: "confirm".localizedString, style: .cancel, actionHandler: {[weak self] _ in
//            guard let self = self else { return }
//            
//        }), SRAlertAction(title: "still_to_set".localizedString)]).show()
        
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
            }
        }
        
    }
    
    /// 导入
    @objc private func importClick() {
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
            vc.scanFineshedExit = true
            navigationController?.pushViewController(vc, animated: true)
//            scanCodeVc = vc
        }
    }
    
    /// 输入uuid导入数据
    private func uuidImport() {
    
        SRAlertView(title: "invitation_code".localizedString, inputFieldStyle: .init(keyboardType: .asciiCapable, minInputLength: 8, maxInputLength: 32), actions: [.cancelAction, SRAlertAction(title: "add".localizedString, actionHandler: { _ in
            
        })], textValueChangedBack: nil) { uuid in
            print(uuid)
        }.show()
        
    }
    
    @objc private func moreClick() {
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "menu_nearby_network"), title: "nearby_network".localizedString, tapItemBack: { item in
                print(item.title)
            }),
            .init(icon: UIImage(named: "menu_transfer_account"), title: "transfer_account".localizedString, tapItemBack: { item in
                print(item.title)
            }),
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(20) - 15, y: kNavigationHeight), menuWidth: SCRXFrom(154))
        
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
        allSitesTableView.reloadData()
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
            guard site.save() else {
                return true
            }
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .normal)
            // 刷新数据
//            var index: Int?
            var currentTableView: UITableView?
            if self.segmentedControl.selectedIndex == 0 {
//                index = allSites.firstIndex(where: { $0.id == site.id })
                currentTableView = allSitesTableView
            }else {
//                index = favouriteSites.firstIndex(where: { $0.id == site.id })
                currentTableView = favouritesTableView
            }
//            if let index = index, let tableView = currentTableView {
//                tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
//            }else {
            currentTableView?.reloadData()
//                self.favouritesTableView.reloadData()
//            }
            
            
            
            return true
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
                XWHUDManager.showTipHUD(error.localizedDescription, isLineFeed: true)
//                XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
            }
        }
    }
    
    /// 删除site本地数据
    private func delteSiteLocalData(site: SiteData) {
        
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
        self.allSitesTableView.reloadData()
        self.favouritesTableView.reloadData()
//         }
        self.updateEmptyView()
        
    }
    
    /// 分享
    private func share(site: SiteData) {
        
        let vc = ShareAuthorityViewController(site: site, type: .share)
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
        
        let vc = SharingSettingViewController(type: .transferSite(site: site))
        present(NavigationViewController(rootViewController: vc), animated: true)
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
            default:
                break
            }
        }
    }
    
    /// 没有网络UI
    private func updateNoInternetUI() {
        if NetworkRequest.shared.networkable {
            allSitesTableView.tableHeaderView = nil
            favouritesTableView.tableHeaderView = nil
        }else {
            if allSitesNoInternetView == nil || favouritesNoInternetView == nil {
                allSitesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: 0, width: self.view.width, height: SCRYFrom(54)))
                favouritesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: 0, width: self.view.width, height: SCRYFrom(54)))
            }
            allSitesTableView.tableHeaderView = allSitesNoInternetView
            favouritesTableView.tableHeaderView = favouritesNoInternetView
        }
    }
    
    private func updateEmptyView() {
        
        if scrollView.frame == .zero {
            view.layoutIfNeeded()
        }
        
        if allSites.isEmpty {
            allSitesTableView.showEmptyDataView(imageName: "site_empty", title: "no_sites_title".localizedString, tipText: nil)
            if let emptyView = allSitesTableView.emptyView {
                emptyView.contentView.snp.remakeConstraints({ make in
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
            allSitesTableView.hideEmptyDataView()
        }
        
        if favouriteSites.isEmpty {
            favouritesTableView.showEmptyDataView(title: "no_favourites_sites".localizedString)
        }else {
            favouritesTableView.hideEmptyDataView()
        }
        
    }
    

    private func setupUI() {
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: ["all_sites".localizedString, "favourites_sites".localizedString])
//        segmented.selectedIndex = 1
        segmentedControl.delegate = self
        view.addSubview(segmentedControl)
//        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(16) + kNavigationHeight)
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
        
        allSitesTableView = UITableView()
        allSitesTableView.separatorStyle = .none
        allSitesTableView.backgroundColor = .clear
        allSitesTableView.register(SitesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        allSitesTableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "title")
        allSitesTableView.rowHeight = SCRYFrom(92)
        allSitesTableView.dataSource = self
        allSitesTableView.delegate = self
        allSitesTableView.refreshControl = allSitesRefreshControl
        scrollView.addSubview(allSitesTableView)
        allSitesTableView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        favouritesRefreshControl = UIRefreshControl()
        favouritesRefreshControl.tintColor = UIColor.lightGray
        favouritesRefreshControl.addTarget(self, action: #selector(loadSitesRequest), for: .valueChanged)
        
        favouritesTableView = UITableView()
        favouritesTableView.separatorStyle = .none
        favouritesTableView.backgroundColor = .clear
        favouritesTableView.dataSource = self
        favouritesTableView.delegate = self
        favouritesTableView.register(SitesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        favouritesTableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "title")
        favouritesTableView.rowHeight = SCRYFrom(92)
        favouritesTableView.refreshControl = favouritesRefreshControl
        scrollView.addSubview(favouritesTableView)
        favouritesTableView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.left.equalTo(allSitesTableView.snp.right)
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        addSiteBtn = UIButton(normalImageName: "add", target: self, action: #selector(addSite))
        view.addSubview(addSiteBtn)
        addSiteBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-38))
        }
        
        allSitesTableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(38) + 20, right: 0)
        favouritesTableView.contentInset = allSitesTableView.contentInset
        
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
    private func showQRCodeFailed(_ message: String) {
        SRAlertView(message: message, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            
        })]).show()
    }

}

extension SitesViewController {
    
    override func size(forChildContentContainer container: UIContentContainer, withParentContainerSize parentSize: CGSize) -> CGSize {
        return CGSize(width: 0, height: 0)
    }
}

extension SitesViewController: NavigationViewControllerDelegate {
    /// 导航控制器点击back事件
    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
        if navigationController.children.count > 1 {
            navitionItemBack = true
        }
    }
}

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

extension SitesViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        if tableView == allSitesTableView {
            return allSections.count
        }else {
            return favouriteSections.count
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == allSitesTableView {
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
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SitesViewCell
        cell.selectionStyle = .none
        var site: SiteData!
        if tableView == allSitesTableView {
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
//        cell.timeLabel.text = String.dateConvert(timestamp: site.create, dateFormat: "M/d/yyyy hh:mm a")
        cell.spaceNumLabel.text = "\(site.spaceCount ?? site.spaces.count) \("spaces".localizedString)"
        cell.favoriteBtn.isSelected = site.isFavourite

        // 自己有同步错误 / 自己有需要同步但是不在同步中 / 下面space有同步错误
        if site.showSyncCloudError != nil || site.spaces.contains(where: { $0.showSyncCloudError != nil }) {
            cell.syncFailedImageView.isHidden = false
        }else {
            cell.syncFailedImageView.isHidden = true
        }
//        cell.syncFailedImageView.isHidden = !(site.syncCloudError != nil || site.spaces.contains(where: { $0.syncCloudError != nil }))
        cell.clickMoreCallback = {[weak self] point in
            guard let self = self else { return }
            let tableviewPoint = tableView.convert(point, from: cell)
            let viewPoint = view.convert(tableviewPoint, from: tableView)
    //        [weakself.view convertPoint:tableviewPoint fromView:tableView];
            self.siteMenu(site: site, point: viewPoint)
        }
        cell.clickFavouriteCallback = {[weak self] isFavourite in
            guard let self = self else { return }
            site.isFavourite = isFavourite
            site.lastUpdate = Int64(Date().timeIntervalSince1970)
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
            self.allSitesTableView.reloadData()
            self.favouritesTableView.reloadData()
            self.updateEmptyView()
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site), level: .normal)
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var site: SiteData!
        if tableView == allSitesTableView {
            site = allSites[indexPath.row]
        }else {
            site = favouriteSites[indexPath.row]
        }
        let vc = SiteViewController(site: site)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "title") as! SyncDevicesTitleHeaderView
        var sectionType: SectionType = .personal
        if tableView == allSitesTableView {
            sectionType = allSections[section]
        }else {
            sectionType = favouriteSections[section]
        }
        headerView.titleLabel.text = sectionType.rawString
        headerView.titleLeftMargin = SCRXFrom(28)
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(25)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
}

extension SitesViewController: LBXScanViewControllerDelegate {
    
    /// 扫码结果
    func scanFinished(scanResult: LBXScanResult, error: String?) {
        
        guard let content = scanResult.strScanned, content.count == 8 else {
            showQRCodeFailed("unknown_qr_code".localizedString)
            return
        }
        
        let vc = SharePermissionSelectionController()
        present(NavigationViewController(rootViewController: vc), animated: true)
        
        
    }
}

extension SitesViewController: CloudSynchronizationManagerDelegate {
    /// 开始同步数据回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didStartSync handle: CloudSynchronizationHandle) {
        updateSyncState()
    }
    
    /// 同步数据成功回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didSyncFinished handle: CloudSynchronizationHandle) {
        updateSyncState()
        
    }
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError) {
        updateSyncState()
    }
}
