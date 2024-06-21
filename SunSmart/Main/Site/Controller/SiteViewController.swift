//
//  SiteViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

class SiteViewController: UIViewController {

    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: PopGestureScrollView!
    private var allSpacesTableView: UITableView!
    private var favouritesTableView: UITableView!                
    private var allSpacesNoInternetView: NoInternetHeaderView?
    private var favouritesNoInternetView: NoInternetHeaderView?

    private var addSpaceBtn: UIButton!
    
    private var allSpaces: [SpaceData] = []
    private var favouriteSpaces: [SpaceData] = []
    
    /// 所有space刷新
    private var allSpacesRefreshControl: UIRefreshControl!
    /// 喜欢的space刷新
    private var favouritesRefreshControl: UIRefreshControl!
    
    let site: SiteData
    /// 是否添加场所进入
    var addSite: Bool
    
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
        
//        updateEmptyView()
        
        if NetworkRequest.shared.networkable {
            loadSiteRequest()
        }
    }
    
    deinit {
        print("111")
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.allSpacesTableView.reloadData()
        self.favouritesTableView.reloadData()
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
        
//        self.showNavigationBarLoading()
//        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: {
//            if self.view.window != nil {
//                self.showNavigationBarFailure()
//            }
//        })
    }
    
    /// KVO监听
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "networkable" { // 手机网络连接状态
            updateNoInternetUI()
        }
    }
    
    
    // MARK: - Request
    /// 获取site数据请求
    @objc private func loadSiteRequest() {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        NetworkRequest.shared.request(.siteInfo(siteId: self.site.id)) {[weak self] result in
            guard let self = self else { return }
            self.allSpacesTableView.refreshControl?.endRefreshing()
            self.favouritesTableView.refreshControl?.endRefreshing()
            
            switch result {
            case .success(let response):
                if let siteData = JSON(response)["data"].dictionaryObject {
//                    let site = SiteData.import(siteJsonData: siteData)
                    Task {
                        await self.site.update(siteJsonData: siteData)
                        self.title = self.site.name
                        self.site.save()
                        self.allSpaces = self.site.spaces
                        self.favouriteSpaces = self.allSpaces.filter({ $0.isFavourite })
                        self.allSpacesTableView.reloadData()
                        self.favouritesTableView.reloadData()
                        self.updateEmptyView()
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
    
    /// 删除site网络请求
    private func deleteSiteReqeust() {
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.siteDelete(siteId: self.site.id)) {[weak self] result in
            XWHUDManager.hide()
            switch result {
            case .success(_):
                // 删除本地数据
                self?.site.delete()
                self?.navigationController?.popViewController(animated: true)
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
            case .failure(let error): // 删除失败，无网络/space存在编辑者
                XWHUDManager.showTipHUD(error.localizedDescription, isLineFeed: true)
//                XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
            }
        }
    }
    
    /// 删除space网络请求
    private func deleteSpaceRequest(space: SpaceData) {
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.siteDelete(siteId: self.site.id)) {[weak self] result in
            XWHUDManager.hide()
            switch result {
            case .success(_):
                // 删除本地数据
                self?.deleteSpace(space: space)
            case .failure(let error): // 删除失败，无网络/space存在编辑者
                XWHUDManager.showTipHUD(error.localizedDescription, isLineFeed: true)
                //                XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
            }
        }
    }
    
    /// 获取space数据
    private func loadSpaceReqeust(space: SpaceData) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id, password: "")) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
                if let spaceData = JSON(response)["data"].dictionaryObject {
                    Task {
                        await space.update(spaceJsonData: spaceData)
                        space.save()
                        self.reloadSpaceData(space)
                        XWHUDManager.hideInView(with: self.view)
                        self.intoSpace(space: space)
                    }
                }else {
                    XWHUDManager.hideInView(with: self.view)
                    self.intoSpace(space: space)
                }
            case .failure(_):
                XWHUDManager.hideInView(with: self.view)
                self.intoSpace(space: space)
            }
            
        }
        
    }
    
    // MARK: - Action
    
    @objc private func moreClick() {
        
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
        
        MenuPopView.show(items: items, anchorPoint: CGPoint(x: view.width - SCRXFrom(17) - 15, y: kNavigationHeight), menuWidth: SCRXFrom(154))
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
                    // 模拟删除过程
                    XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                        XWHUDManager.hide()
                        // 删除本地数据
                        self?.site.delete()
                        self?.navigationController?.popViewController(animated: true)
                        NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                    }
                }
            }
            
        })]).show()
    }

    /// 添加空间
    @objc private func addSpace() {
        
        var imageNames: [String] = []
        for id in 1...24 {
            imageNames.append("space_picture_\(id)")
        }
        let vc = InfoEditViewController(name: SpaceData.getNextSpaceName(siteId: site.id), imageNames: imageNames, selectImageIndex: 0, columnNum: 2, isAdd: true)
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
            
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .addSpaces(site: site, spaces: [space]), level: .normal)
            
            self.allSpaces.append(space)
            let insertPath = IndexPath(row: self.allSpaces.count - 1, section: 0)
            self.allSpacesTableView.insertRows(at: [insertPath], with: .automatic)
            self.allSpacesTableView.scrollToRow(at: insertPath, at: .bottom, animated: true)
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
        let vc = InfoEditViewController(name: space.name, imageNames: imageNames, selectImageIndex: max(space.imageId - 1, 0), columnNum: 2)
        vc.nameEditChangedCallback = { name in
            return SpaceData.isTautonym(spaceName: name, siteId: space.siteId) && name != space.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return true }
            space.name = name
            space.imageId = imageId + 1
            space.lastUpdate = Int64(Date().timeIntervalSince1970)
            space.save()
            self.reloadSpaceData(space)
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .normal)
            
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
        var currentTableView: UITableView?
        var otherTableView: UITableView?
        if self.segmentedControl.selectedIndex == 0 {
            index = allSpaces.firstIndex(where: { $0.id == space.id })
            currentTableView = allSpacesTableView
            otherTableView = favouritesTableView
        }else {
            index = favouriteSpaces.firstIndex(where: { $0.id == space.id })
            currentTableView = favouritesTableView
            otherTableView = allSpacesTableView
        }
        self.allSpaces.removeAll(where: { $0.id == space.id })
        self.favouriteSpaces.removeAll(where: { $0.id == space.id })
        if let index = index, let tableView = currentTableView {
            tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
            otherTableView?.reloadData()
        }else {
            self.allSpacesTableView.reloadData()
            self.favouritesTableView.reloadData()
        }
        self.updateEmptyView()
        
    }
    
    
    /// 分享&权限
    private func share() {
        
        let vc = ShareAuthorityViewController(site: site, type: .share)
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 转让Site
    private func transferSite() {
        
        let vc = SharingSettingViewController(type: .transferSite(site: site))
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 分享space
    private func shareSpace(_ space: SpaceData) {
        let vc = SharingSettingViewController(type: .space(site: site, space: space))
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 解绑space
    private func unbindSpace(_ space: SpaceData) {
        
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
            items.append(.init(icon: UIImage(named: "menu_unbind"), title: "unbind".localizedString, tapItemBack: {[weak self] _ in
                self?.unbindSpace(space)
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
                    self?.showSpacesBatchesSyncAlert()
                }
            default:
                break
            }
        }else if allSpaces.contains(where: { $0.showSyncCloudError != nil }) { // site或者site下space存在同步错误
            self.showNavigationBarFailure {[weak self] in
                self?.showSpacesBatchesSyncAlert()
            }
        }
    }
    
    /// spaces批量同步提示
    private func showSpacesBatchesSyncAlert() {
        
        SRAlertView(title: "notification".localizedString, message: "spaces_batches_sync_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return }
            let failedSpaces = self.allSpaces.filter({ $0.showSyncCloudError != nil })
            failedSpaces.forEach({
                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: $0), level: .promptly)
            })
        })]).show()
        
    }
    
    /// 进入space
    private func intoSpace(space: SpaceData) {
        
        let spaceVc = SpaceViewController(space: space)
        spaceVc.site = site
        spaceVc.deleteSpaceCallback = {[weak self] in
            guard let self = self else { return  }
            self.allSpaces.removeAll(where: { $0.id == space.id })
            self.favouriteSpaces.removeAll(where: { $0.id == space.id })
            if self.view.window != nil {
                self.allSpacesTableView.reloadData()
                self.favouritesTableView.reloadData()
                self.updateEmptyView()
            }
        }
        navigationController?.pushViewController(spaceVc, animated: true)
    }
    
    /// 刷新space
    private func reloadSpaceData(_ space: SpaceData) {
        
        // 刷新数据
        var index: Int?
        var currentTableView: UITableView?
        if self.segmentedControl.selectedIndex == 0 {
            index = allSpaces.firstIndex(where: { $0.id == space.id })
            currentTableView = allSpacesTableView
        }else {
            index = favouriteSpaces.firstIndex(where: { $0.id == space.id })
            currentTableView = favouritesTableView
        }
        if let index = index, let tableView = currentTableView {
            tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
        }else {
            self.allSpacesTableView.reloadData()
            self.favouritesTableView.reloadData()
        }
        
    }
    
    /// 更新无网络UI
    private func updateNoInternetUI() {
        if NetworkRequest.shared.networkable {
            allSpacesTableView.tableHeaderView = nil
            favouritesTableView.tableHeaderView = nil
        }else {
            if allSpacesNoInternetView == nil || favouritesNoInternetView == nil {
                allSpacesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: 0, width: self.view.width, height: SCRYFrom(54)))
                favouritesNoInternetView = NoInternetHeaderView(frame: CGRect(x: 0, y: 0, width: self.view.width, height: SCRYFrom(54)))
            }
            allSpacesTableView.tableHeaderView = allSpacesNoInternetView
            favouritesTableView.tableHeaderView = favouritesNoInternetView
        }
    }
    
    /// 判断是否显示空数据页
    private func updateEmptyView() {
        
        if scrollView.frame == .zero {
            view.layoutIfNeeded()
        }
        
        if allSpaces.isEmpty {
            allSpacesTableView.showEmptyDataView(imageName: "space_empty", title: "no_spaces_title".localizedString, tipText: nil)
            if let emptyView = allSpacesTableView.emptyView {
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
                let attStr = NSAttributedString(string: "no_spaces_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
                emptyView.tipLabel.attributedText = attStr
            }
           
        }else {
            allSpacesTableView.hideEmptyDataView()
        }
        
        if favouriteSpaces.isEmpty {
            favouritesTableView.showEmptyDataView(title: "no_favourites_spaces".localizedString, bottomMargin: SCRYFrom(32))
        }else {
            favouritesTableView.hideEmptyDataView()
        }
        
    }
    
    private func setupUI() {
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: ["all_spaces".localizedString, "favourites_spaces".localizedString])
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
        
        allSpacesTableView = UITableView()
        allSpacesTableView.separatorStyle = .none
        allSpacesTableView.backgroundColor = .clear
        allSpacesTableView.register(SpacesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        allSpacesTableView.rowHeight = SCRYFrom(208)
        allSpacesTableView.dataSource = self
        allSpacesTableView.delegate = self
        allSpacesTableView.refreshControl = allSpacesRefreshControl
        scrollView.addSubview(allSpacesTableView)
        allSpacesTableView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        favouritesRefreshControl = UIRefreshControl()
        favouritesRefreshControl.tintColor = UIColor.lightGray
        favouritesRefreshControl.addTarget(self, action: #selector(loadSiteRequest), for: .valueChanged)
        
        favouritesTableView = UITableView()
        favouritesTableView.separatorStyle = .none
        favouritesTableView.backgroundColor = .clear
        favouritesTableView.dataSource = self
        favouritesTableView.delegate = self
        favouritesTableView.register(SpacesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        favouritesTableView.rowHeight = SCRYFrom(208)
        favouritesTableView.refreshControl = favouritesRefreshControl
        scrollView.addSubview(favouritesTableView)
        favouritesTableView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
            make.left.equalTo(allSpacesTableView.snp.right)
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        addSpaceBtn = UIButton(normalImageName: "add", target: self, action: #selector(addSpace))
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

extension SiteViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == allSpacesTableView {
            return allSpaces.count
        }
        return favouriteSpaces.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SpacesViewCell
        cell.selectionStyle = .none
        var space: SpaceData!
        if tableView == allSpacesTableView {
            space = allSpaces[indexPath.row]
        }else {
            space = favouriteSpaces[indexPath.row]
        }
        cell.space = space
        cell.delegate = self
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var space: SpaceData!
        if tableView == allSpacesTableView {
            space = allSpaces[indexPath.row]
        }else {
            space = favouriteSpaces[indexPath.row]
        }
        // 判断是否还有space权限
        guard space.state == .normal else {
            // 权限被删除
            
            
            
            
            return
        }
//        space_editor_password_change_message
//        SRAlertView(title: "notification".localizedString, message: "Space editor password changed, please re-enter the correct password to access.", inputText: nil, inputFieldStyle: .init(placeholder: "Password".localizedString, keyboardType: .numberPad, margin: SCRXFrom(56), height: SCRYFrom(32), minInputLength: 4, maxInputLength: 4, borderColor: RGB(153, 153, 153, 0.3), textAlignment: .center, secret: true, showClear: false), actions: [.cancelAction, SRAlertAction(title: "SYNC".localizedString)], textValueChangedBack: nil) { password in
//            
//        }.show()
        
        loadSpaceReqeust(space: space)
        
//        let spaceVc = SpaceViewController(space: space)
//        spaceVc.site = site
//        spaceVc.deleteSpaceCallback = {[weak self] in
//            guard let self = self else { return  }
//            self.allSpaces.removeAll(where: { $0.id == space.id })
//            self.favouriteSpaces.removeAll(where: { $0.id == space.id })
//            if self.view.window != nil {
//                self.allSpacesTableView.reloadData()
//                self.favouritesTableView.reloadData()
//                self.updateEmptyView()
//            }
//        }
//        navigationController?.pushViewController(spaceVc, animated: true)
    }
}

extension SiteViewController: SpacesViewCellDelegate {
    
    /// 点击更多回调
    func cell(_ cell: SpacesViewCell, moreAction point: CGPoint) {
        var tableView: UITableView!
        if segmentedControl.selectedIndex == 0 {
            tableView = allSpacesTableView
        }else {
            tableView = favouritesTableView
        }
        
        let tableviewPoint = tableView.convert(point, from: cell)
        let viewPoint = view.convert(tableviewPoint, from: tableView)
//        [weakself.view convertPoint:tableviewPoint fromView:tableView];
        self.spaceMenu(space: cell.space, point: viewPoint)
    }
    
    /// 点击收藏回调
    func cell(_ cell: SpacesViewCell, favouriteChanged favourite: Bool) {
        
        let space = cell.space!
        space.isFavourite = favourite
        space.lastUpdate = Int64(Date().timeIntervalSince1970)
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
        self.allSpacesTableView.reloadData()
        self.favouritesTableView.reloadData()
        self.updateEmptyView()
        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .normal)
        
    }
    
    /// 点击同步异常回调
    func spacesViewCellSyncFailedAction(_ cell: SpacesViewCell) {
        
        guard let space = cell.space, let error = space.showSyncCloudError else {
            return
        }
        SRAlertView(title: "synchronization_failure".localizedString, message: error.localizedDescription, actions: [.cancelAction, SRAlertAction(title: "SYNC".localizedString, actionHandler: { _ in
            cell.syncFailedImageBtn.isHidden = true
            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSpace(space: space), level: .promptly)
            
        })]).show()
        
    }
}

extension SiteViewController: CloudSynchronizationManagerDelegate {
    
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
    
    /// 同步数据失败回调
    /// - Parameters:
    ///   - manager: 同步管理
    ///   - handle: 同步数据操作
    func cloudSynchManager(_ manager: CloudSynchronizationManager, didSyncFailure handle: CloudSynchronizationHandle, error: NetworkApiError) {
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
}
