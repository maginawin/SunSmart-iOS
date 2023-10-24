//
//  SitesViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/20.
//

import UIKit

/// 场所列表数据刷新通知
let SitesDataRefreshNotifiacationName = "SitesRefreshNotifiacation"

class SitesViewController: UIViewController {

    private var showMenu: Bool = false
    
    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: UIScrollView!
    private var allSitesTableView: UITableView!
    private var favouritesTableView: UITableView!

    private var addSiteBtn: UIButton!
    
    private var allSites: [SiteData] = []
    private var favouriteSites: [SiteData] = []
    private var reloadData: Bool = false
    /// 导航控制器是否点击back返回
    private var navitionItemBack: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()
      
        title = "sites".localizedString
        view.backgroundColor = Background_Color
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "menu_icon")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(menuClick))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreClick))

        NotificationCenter.default.addObserver(self, selector: #selector(refreshData), name: .init(SitesDataRefreshNotifiacationName), object: nil)
        
//        navigationController?.interactivePopGestureRecognizer?.delegate = self
        (navigationController as? NavigationViewController)?.backItemDelegate = self
        
        setupUI()
        setupData()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
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
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // pop手势返回，回到menu页面
        if showMenu {
            showMenu = false
            menuClick()
        }
    }
    
    
    
    /// 数据源
    private func setupData() {
        let sites = SiteData.loadAll()
        allSites = sites
        favouriteSites = sites.filter({ $0.isFavourite })
        allSitesTableView.reloadData()
        favouritesTableView.reloadData()
        
        updateEmptyView()
    }
    
    /// 刷新数据通知回掉
    @objc private func refreshData() {
        reloadData = true
    }
    
    /// 菜单
    @objc private func menuClick() {

        MainMenuView.show {[weak self] index in
            print(index)
            guard let self = self else { return }
            self.navigationController?.pushViewController(AboutViewController(), animated: true)
            self.showMenu = true
        }
    }
    
    /// 添加场所
    @objc private func addSite() {
        // 创建一个场所
        let site = SiteData.add(name: SiteData.getNextSiteName())
        allSites.append(site)
        allSitesTableView.insertRows(at: [IndexPath(row: allSites.count - 1, section: 0)], with: .none)
        updateEmptyView()
        
        
        // 跳转到场所页面
        let vc = SiteViewController(site: site, addSite: true)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 编辑场所
    private func editSite(site: SiteData) {
        
        var imageNames: [String] = []
        for id in 1...24 {
            imageNames.append("site_image\(id)")
        }
        let vc = InfoEditViewController(name: site.name, imageNames: imageNames, selectImageIndex: max(site.imageId - 1, 0), columnNum: 4)
        vc.nameEditChangedCallback = { name in
            return SiteData.isTautonym(siteName: name) && name != site.name
        }
        vc.doneCallback = {[weak self] (name, imageId) in
            guard let self = self else { return }
            site.name = name
            site.imageId = imageId + 1
            site.save()
            // 刷新数据
            var index: Int?
            var currentTableView: UITableView?
            if self.segmentedControl.selectedIndex == 0 {
                index = allSites.firstIndex(where: { $0.id == site.id })
                currentTableView = allSitesTableView
            }else {
                index = favouriteSites.firstIndex(where: { $0.id == site.id })
                currentTableView = favouritesTableView
            }
            if let index = index, let tableView = currentTableView {
                tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }else {
                self.allSitesTableView.reloadData()
                self.favouritesTableView.reloadData()
            }
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除场所
    private func deleteSite(site: SiteData) {
        
        SRAlertView(title: "notification".localizedString, message: "alert_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { _ in
            // 提示1s，
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindiw: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                XWHUDManager.hide()
                guard let self = self else { return }
                
                // 场所下面空间内存在设备
                if let space = site.spaces.first(where: { $0.deviceCount > 0 }) {
                    // 删除不存在设备的空间list
                    let emptySpaces = site.spaces.filter({ $0.deviceCount == 0 })
                    emptySpaces.forEach { emptySpace in
                        emptySpace.delete()
                        site.spaces.removeAll(where: { $0.id == emptySpace.id })
                    }
                    site.save()
                    XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
                }else { // 场所下空间未存在设备，删除成功
                    site.delete()
                    var index: Int?
                    var currentTableView: UITableView?
                    var otherTableView: UITableView?
                    if self.segmentedControl.selectedIndex == 0 {
                        index = allSites.firstIndex(where: { $0.id == site.id })
                        currentTableView = allSitesTableView
                        otherTableView = favouritesTableView
                    }else {
                        index = favouriteSites.firstIndex(where: { $0.id == site.id })
                        currentTableView = favouritesTableView
                        otherTableView = allSitesTableView
                    }
                    self.allSites.removeAll(where: { $0.id == site.id })
                    self.favouriteSites.removeAll(where: { $0.id == site.id })
                    if let index = index, let tableView = currentTableView {
                        tableView.deleteRows(at: [IndexPath(row: index, section: 0)], with: .fade)
                        otherTableView?.reloadData()
                    }else {
                        self.allSitesTableView.reloadData()
                        self.favouritesTableView.reloadData()
                    }
                    self.updateEmptyView()
                }
            }
        })]).show()
    }
    
    private func updateEmptyView() {
        
        if scrollView.frame == .zero {
            view.layoutIfNeeded()
        }
        
        if allSites.isEmpty {
            allSitesTableView.showEmptyDataView(imageName: "site_structure", title: "no_sites_title".localizedString, tipText: nil)
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
        
        allSitesTableView = UITableView()
        allSitesTableView.separatorStyle = .none
        allSitesTableView.backgroundColor = .clear
        allSitesTableView.register(SitesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        allSitesTableView.rowHeight = SCRYFrom(92)
        allSitesTableView.dataSource = self
        allSitesTableView.delegate = self
        scrollView.addSubview(allSitesTableView)
        allSitesTableView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        favouritesTableView = UITableView()
        favouritesTableView.separatorStyle = .none
        favouritesTableView.backgroundColor = .clear
        favouritesTableView.dataSource = self
        favouritesTableView.delegate = self
        favouritesTableView.register(SitesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        favouritesTableView.rowHeight = SCRYFrom(92)
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
    }
    
    @objc private func moreClick() {
        
//        MenuPopView.show(items: [
//            .init(icon: UIImage(named: "edit"), title: "edit_site".localizedString, tapItemBack: { item in
//                print(item.title)
//            }),
//            .init(icon: UIImage(named: "edit"), title: "delete_site".localizedString, tapItemBack: { item in
//                print(item.title)
//            }),
//        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(20) - 15, y: kNavigationHeight), menuWidth: SCRXFrom(154))
        
        
    }
    

}

extension SitesViewController: NavigationViewControllerBackItemDelegate {
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
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if tableView == allSitesTableView {
            return allSites.count
        }
        return favouriteSites.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! SitesViewCell
        cell.selectionStyle = .none
        var site: SiteData!
        if tableView == allSitesTableView {
            site = allSites[indexPath.row]
        }else {
            site = favouriteSites[indexPath.row]
        }
        cell.nameLabel.text = site.name
        cell.iconImageView.image = UIImage(named: "site_image\(site.imageId)")
        cell.timeLabel.text = String.dateConvert(timestamp: site.create, dateFormat: "M/d/yyyy hh:mm a")
        cell.spaceNumLabel.text = "\(site.spaces.count) \("spaces".localizedString)"
        cell.favoriteBtn.isSelected = site.isFavourite
        cell.clickMoreCallback = {[weak self] point in
            guard let self = self else { return }
            let tableviewPoint = tableView.convert(point, from: cell)
            let viewPoint = view.convert(tableviewPoint, from: tableView)
    //        [weakself.view convertPoint:tableviewPoint fromView:tableView];
            MenuPopView.show(items: [
                .init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                    self?.editSite(site: site)
                }),
                .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
                    self?.deleteSite(site: site)
                }),
//                .init(icon: UIImage(named: "menu_clone"), title: "clone".localizedString, tapItemBack: { item in
//                    print(item.title)
//                }),
//                .init(icon: UIImage(named: "menu_share"), title: "share".localizedString, tapItemBack: { item in
//                    print(item.title)
//                })
            ], anchorPoint: viewPoint)
        }
        cell.clickFavouriteCallback = {[weak self] isFavourite in
            guard let self = self else { return }
            site.isFavourite = isFavourite
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
            self.allSitesTableView.reloadData()
            self.favouritesTableView.reloadData()
            self.updateEmptyView()
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
}
