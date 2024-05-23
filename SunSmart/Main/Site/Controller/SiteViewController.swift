//
//  SiteViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/25.
//

import UIKit
import NordicSigMeshSDK

class SiteViewController: UIViewController {

    private var segmentedControl: CustomSegmentedControl!
    private var scrollView: PopGestureScrollView!
    private var allSpacesTableView: UITableView!
    private var favouritesTableView: UITableView!                   

    private var addSpaceBtn: UIButton!
    
    private var allSpaces: [SpaceData] = []
    private var favouriteSpaces: [SpaceData] = []
    
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
        
//        MeshLibManager.manager.setMeshNetworkConnected(meshUUID: site.meshUUID, connected: false)
        
//        updateEmptyView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.allSpacesTableView.reloadData()
        self.favouritesTableView.reloadData()
        self.updateEmptyView()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if addSite {
            addSite = false
            addSpace()
        }
    }
    
    @objc private func moreClick() {
        
        MenuPopView.show(items: [
            .init(icon: UIImage(named: "edit"), title: "edit_site".localizedString, tapItemBack: {[weak self] item in
                self?.editSite()
            }),
            .init(icon: UIImage(named: "menu_delete"), title: "delete_site".localizedString, tapItemBack: {[weak self] item in
                self?.deleteSite()
            }),
        ], anchorPoint: CGPoint(x: view.width - SCRXFrom(17) - 15, y: kNavigationHeight), menuWidth: SCRXFrom(154))
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
            guard let self = self else { return }
            self.site.name = name
            self.site.imageId = imageId + 1
            self.site.save()
            self.title = name
        }
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除场所
    private func deleteSite() {
        
        SRAlertView(title: "notification".localizedString, message: "alert_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { _ in
            // 提示1s
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                XWHUDManager.hide()
                guard let self = self else { return }
                
                // 场所下面空间内存在设备
                if let space = site.spaces.first(where: { $0.deviceCount > 0 }) {
                    // 删除不存在设备的空间list
                    let emptySpaces = site.spaces.filter({ $0.deviceCount == 0 })
                    emptySpaces.forEach { emptySpace in
                        emptySpace.delete()
                        self.site.spaces.removeAll(where: { $0.id == emptySpace.id })
                    }
                    site.save()
                    XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
                }else { // 场所下空间未存在设备，删除成功
                    self.site.delete()
                    self.navigationController?.popViewController(animated: true)
                }
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
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
            guard let self = self else { return }
            
            guard let space = self.site.addSpace(name: name, imageId: imageId + 1) else {
                XWHUDManager.showErrorTipHUD("\("failed".localizedString)!")
                return
            }
            
            self.allSpaces.append(space)
            let insertPath = IndexPath(row: self.allSpaces.count - 1, section: 0)
            self.allSpacesTableView.insertRows(at: [insertPath], with: .automatic)
            self.allSpacesTableView.scrollToRow(at: insertPath, at: .bottom, animated: true)
            self.updateEmptyView()
        }
        
        present(NavigationViewController(rootViewController: vc), animated: true)
        
//        SRAlertView(title: "add_space".localizedString, inputText: SpaceData.getNextSpaceName(siteId: site.id), placeholder: "", actions: [.cancelAction, .init(title: "add".localizedString, style: .default)]) { text, validRange in
//            if !validRange && !text.isEmpty { // 长度超限
//                return "text_length_exceeded".localizedString
//            }else if SiteData.isTautonym(siteName: text) { // 重名
//                return "name_already_exists".localizedString
//            }
//            return nil
//        } inputDoneBack: {[weak self] text in
//            guard let self = self else { return }
//            let space = self.site.addSpace(name: text)
//            self.allSpaces.append(space)
//            self.allSpacesTableView.insertRows(at: [IndexPath(row: self.allSpaces.count - 1, section: 0)], with: .automatic)
//            self.updateEmptyView()
//        }.show()
        
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
            guard let self = self else { return }
            space.name = name
            space.imageId = imageId + 1
            space.save()
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
        present(NavigationViewController(rootViewController: vc), animated: true)
    }
    
    /// 删除空间
    private func deleteSpace(space: SpaceData) {
        
        SRAlertView(title: "notification".localizedString, message: "alert_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "alert_item_delete".localizedString, style: .destructive, actionHandler: { _ in
            // 提示1s
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                XWHUDManager.hide()
                guard let self = self else { return }
                if space.deviceCount > 0 {
                    XWHUDManager.showErrorTipHUD("site_delete_fail".localizedString)
                }else { // 场所下空间未存在设备，删除成功
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
            }
        })]).show()
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
        
        allSpacesTableView = UITableView()
        allSpacesTableView.separatorStyle = .none
        allSpacesTableView.backgroundColor = .clear
        allSpacesTableView.register(SpacesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        allSpacesTableView.rowHeight = SCRYFrom(208)
        allSpacesTableView.dataSource = self
        allSpacesTableView.delegate = self
        scrollView.addSubview(allSpacesTableView)
        allSpacesTableView.snp.makeConstraints { make in
            make.left.top.equalToSuperview()
            make.height.equalToSuperview()
            make.width.equalToSuperview()
        }
        
        favouritesTableView = UITableView()
        favouritesTableView.separatorStyle = .none
        favouritesTableView.backgroundColor = .clear
        favouritesTableView.dataSource = self
        favouritesTableView.delegate = self
        favouritesTableView.register(SpacesViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        favouritesTableView.rowHeight = SCRYFrom(208)
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
        cell.nameLabel.text = space.name
        cell.iconImageView.image = UIImage(named: "space_picture_\(space.imageId)")
        cell.timeLabel.text = String.dateConvert(timestamp: space.create, dateFormat: "M/d/yyyy hh:mm a")
        cell.luminairesLabel.text = "luminaires".localizedString + ":\(space.luminairesCount)"
        cell.switchesLabel.text = "switches".localizedString + ":\(space.switchesCount)"
        cell.groupsLabel.text = "groups".localizedString + ":\(space.groupCount)"
        cell.scenesLabel.text = "scenes".localizedString + ":\(space.sceneCount)"
        cell.schedulesLabel.text = "schedules".localizedString + ":\(space.scheheduleCount)"
        cell.favoriteBtn.isSelected = space.isFavourite
        
        cell.clickMoreCallback = {[weak self] point in
            guard let self = self else { return }
            let tableviewPoint = tableView.convert(point, from: cell)
            let viewPoint = view.convert(tableviewPoint, from: tableView)
    //        [weakself.view convertPoint:tableviewPoint fromView:tableView];
            MenuPopView.show(items: [
                .init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: {[weak self] item in
                    self?.editSpace(space: space)
                }),
                .init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: {[weak self] item in
                    self?.deleteSpace(space: space)
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
            space.isFavourite = isFavourite
            space.save()
            if isFavourite {
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
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        var space: SpaceData!
        if tableView == allSpacesTableView {
            space = allSpaces[indexPath.row]
        }else {
            space = favouriteSpaces[indexPath.row]
        }
        let spaceVc = SpaceViewController(space: space)
        spaceVc.deleteSpaceCallback = {[weak self] in
            guard let self = self else { return  }
            self.allSpaces.removeAll(where: { $0.id == space.id })
            self.favouriteSpaces.removeAll(where: { $0.id == space.id })
            self.allSpacesTableView.reloadData()
            self.favouritesTableView.reloadData()
            self.updateEmptyView()
        }
        navigationController?.pushViewController(spaceVc, animated: true)
    }
}

