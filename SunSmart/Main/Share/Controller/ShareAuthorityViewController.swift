//
//  ShareAuthorityViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/30.
//

import UIKit

class ShareAuthorityViewController: UIViewController {

    /// 顶部栏
    private var topBarView: UIView!
    /// 排序
    private var sortBtn: UIButton!
    /// 排序正序/倒序
    private var sortOrderBtn: UIButton!
    /// 筛选
    private var filterBtn: UIButton!
    /// space列表
    private var collectionView: UICollectionView!
    private var flowLayout: UICollectionViewFlowLayout!
    /// 底部操作栏
    private var bottomView: UIView!
    /// 编辑，开始选择/取消选择
    private var editBtn: UIButton!
    /// 选中所有
    private var selectAllBtn: UIButton!
    /// 删除
    private var deleteBtn: UIButton!
    /// 查看记录
    private var viewRecordBtn: UIButton!
    /// 分享
    private var shareBtn: UIButton!
    /// 更多
    private var moreBtn: UIButton!
    /// 解绑
    private var unbindBtn: UIButton!
    
    /// 操作类型
    let type: OperationType
    
    let site: SiteData
    /// 所有spaces
    private var allSpaces: [SpaceData] = []
    /// 展示的spaces
    private var showSpaces: [SpaceData] = []
    /// 选中的spaces
    private var selectSpaces: [SpaceData] = []
    /// 是否在选择状态
    private var isSelectState: Bool = false
    /// 筛选类型
    private var filterType: ShareAuthorityFilterView.FilterType?
    /// 排序类型
    private var sortType: SortType = .createdDate
    /// 排序方式
    private var orderedType: SortOrder = .descending
    
    init(site: SiteData, type: OperationType) {
        self.site = site
        self.type = type
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        switch self.type {
        case .share:
            title = "share_authoority".localizedString
            navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
            if site.permission == .owner {
                navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "share_management")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(management))
            }else {
                navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "share_unbind")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(unbindItemAction))
            }
        case .management:
            title = "management".localizedString
        case .unbind:
            title = "unbind".localizedString
        }
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        
        allSpaces = site.spaces
        setupUI()
        updateUI()
    }
    
    // MARK: - Action
    
    @objc private func close() {
        
        dismiss(animated: true)
    }
    
    /// 管理
    @objc private func management() {
        let vc = ShareAuthorityViewController(site: site, type: .management)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 解绑页面
    @objc private func unbindItemAction() {
        let vc = ShareAuthorityViewController(site: site, type: .unbind)
        navigationController?.pushViewController(vc, animated: true)
    }
    

    /// 排序
    @objc private func sortBtnAction(sender: UIButton) {
        
        let point = CGPoint(x: sender.frame.minX, y: topBarView.frame.maxY)
        
//        let tableviewPoint = tableView.convert(point, from: cell)
        let viewPoint = view.convert(point, from: topBarView)
        
        let items: [TableSelectView.TableItem] = [
            .init(icon: UIImage(named: "sort_create"), title: "created_date".localizedString, tapItemBack: {[weak self] _ in
                print("create")
                self?.sortType = .createdDate
                self?.updateUI()
            }),
            .init(icon: UIImage(named: "sort_update"), title: "updated_date".localizedString, tapItemBack: {[weak self] _ in
                print("updated")
                self?.sortType = .updatedDate
                self?.updateUI()
            }),
            .init(icon: UIImage(named: "sort_alphabetical"), title: "alphabetical".localizedString, tapItemBack: {[weak self] _ in
                print("alphabetical")
                self?.sortType = .alphabetical
                self?.updateUI()
            }),
            .init(icon: UIImage(named: "sort_device_quantity"), title: "device_quantity".localizedString, tapItemBack: {[weak self] _ in
                print("device_quantity")
                self?.sortType = .deviceQuantity
                self?.updateUI()
            })
        ]
        
        let sortTypes: [SortType] = [.createdDate, .updatedDate, .alphabetical, .deviceQuantity]
        
        TableSelectView.show(items: items, anchorPoint: viewPoint, selectIndex: sortTypes.firstIndex(of: self.sortType) ?? 0, menuWidth: SCRXFrom(154), titleFont: UIFont.systemFont(ofSize: 13, weight: .light), backgroundColor: RGB(89, 87, 86))
        
//        MenuPopView.show(items: items, anchorPoint: CGPoint(x: sender.frame.minX, y: sender.frame.maxY), animation: .none, bgImage: UIImage.image(size: CGSize(width: SCRXFrom(140), height: SCRYFrom(152)), color: RGB(89, 87, 86)), menuWidth: SCRXFrom(154))
    }
    
    /// 排序顺序切换
    @objc private func sortOrderBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            orderedType = .ascending
        }else {
            orderedType = .descending
        }
        updateUI()
    }
    
    /// 过滤
    @objc private func filterBtnAction() {
        ShareAuthorityFilterView(selectFilterType: self.filterType, editorNames: ["Jesse's iphone 13", "Jesse's iphone 14", "Jesse's iphone 15"], visitorNames: ["iPhone 1"]) {[weak self] selectType in
//            print(selectType)
            self?.filterType = selectType
            self?.updateUI()
        }.show()
    }
    
    /// 选中/取消选中
    @objc private func editBtnAction(sender: UIButton) {
        // 判断是否有可选择的内容
        sender.isSelected = !sender.isSelected
       
        isSelectState = sender.isSelected
        updateUI()
    }
    
    /// 选中全部
    @objc private func selectAllBtnAction(sender: UIButton) {
//        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            selectSpaces.removeAll()
        }else {
            selectSpaces = allSpaces
        }
        collectionView.reloadData()
        updateBottomUI()
//        updateUI()
    }
    
    /// 查看记录
    @objc private func viewRecordBtnAction() {
        let vc = ShareBacthListViewController(site: site)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 删除
    @objc private func deleteBtnAction() {
        
        guard selectSpaces.count > 0 else {
            return
        }
        
        SRAlertView(title: "notification".localizedString, message: "share_spaces_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: { _ in
            // 提示1s
            XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                XWHUDManager.hide()
                guard let self = self else { return }
                
                self.selectSpaces.removeAll { space in
                    // 空间未存在设备，删除成功
                    if space.deviceCount == 0 {
                        space.delete()
                        self.site.spaces.removeAll(where: { $0.id == space.id })
                        return true
                    }
                    return false
                }
                self.allSpaces = self.site.spaces
                if self.selectSpaces.count > 0 {
                    SRAlertView(title: "notification".localizedString, message: "share_spaces_delete_failed_message".localizedString, actions: [SRAlertAction(title: "confirm".localizedString, actionHandler: {[weak self] _ in
                        self?.updateUI()
                    })]).show()
                }else {
                    self.updateUI()
                }
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
            }
        })]).show()
    }
    
    /// 分享
    @objc private func shareBtnAction() {
        
        guard selectSpaces.count > 0 else {
            return
        }
        
        let vc = SharingSettingViewController(type: .batchSpace(data: BatchSpaceData(site: site, uuid: site.id, name: "Batch 53487", spaces: selectSpaces)))
        navigationController?.pushViewController(vc, animated: true)
        
        selectSpaces.removeAll()
        updateUI()
        
    }
    
    /// 更多
    @objc private func moreBtnAction(sender: UIButton) {
        
        var items: [MenuPopView.MenuItem] = []
        if site.permission == .owner {
            items = [
                .init(icon: UIImage(named: "share_clear_member"), title: "clear_editor".localizedString, tapItemBack: {[weak self] _ in
                    
                }),
                .init(icon: UIImage(named: "reset_password"), title: "regenerates_editor_password".localizedString, tapItemBack: {[weak self] _ in
                    
                }),
                .init(icon: UIImage(named: "share_clear_member"), title: "clear_visitor".localizedString, tapItemBack: {[weak self] _ in
                    
                }),
                .init(icon: UIImage(named: "reset_password"), title: "regenerates_visitor_password".localizedString, tapItemBack: {[weak self] _ in
                    
                }),
                .init(icon: UIImage(named: "disable_password"), title: "disable_visitor_password".localizedString, tapItemBack: {[weak self] _ in
                    
                }),
                .init(icon: UIImage(named: "enable_password"), title: "enable_visitor_password".localizedString, tapItemBack: {[weak self] _ in
                    
                })
            ]
        }else {
            items = [
                .init(icon: UIImage(named: "share_clear_member"), title: "clear_visitor".localizedString, tapItemBack: {[weak self] _ in
                        // 删除访客
                }),
                .init(icon: UIImage(named: "reset_password"), title: "regenerates_visitor_password".localizedString, tapItemBack: {[weak self] _ in
                    // 修改访客密码
                }),
                .init(icon: UIImage(named: "disable_password"), title: "disable_visitor_password".localizedString, tapItemBack: {[weak self] _ in
                    
                }),
                .init(icon: UIImage(named: "enable_password"), title: "enable_visitor_password".localizedString, tapItemBack: {[weak self] _ in
                    
                })
            ]
        }
        
        let point = CGPoint(x: sender.center.x, y: bottomView.frame.minY + SCRYFrom(30))
        let viewPoint = UIApplication.shared.keyWindow().convert(point, from: view)
        
        MenuPopView.show(items: items, anchorPoint: viewPoint, menuWidth: SCRXFrom(220))
        
    }
    
    /// 解绑
    @objc private func unbindBtnAction() {
        // 网络请求
    }
    
    private func setupUI() {
        
        topBarView = UIView()
        view.addSubview(topBarView)
        topBarView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo((navigationController?.navigationBar.height ?? 0) + SCRYFrom(7))
            make.height.equalTo(SCRYFrom(30))
        }
        sortBtn = UIButton(title: "created_date".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "arrow_down_black", target: self, action: #selector(sortBtnAction))
        sortBtn.setImagePosition(position: .right, spacing: SCRXFrom(4))
        topBarView.addSubview(sortBtn)
        sortBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        sortOrderBtn = UIButton(normalImageName: "order_down", selectedImageName: "order_up", target: self, action: #selector(sortOrderBtnAction))
        topBarView.addSubview(sortOrderBtn)
        sortOrderBtn.snp.makeConstraints { make in
            make.left.equalTo(sortBtn.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(sortBtn)
        }
        
        filterBtn = UIButton(normalImageName: "filter", target: self, action: #selector(filterBtnAction))
        topBarView.addSubview(filterBtn)
        filterBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(sortOrderBtn)
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(44) + kSafeAreaBottomHeight)
        }
        
        editBtn = UIButton(title: "select".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(editBtnAction))
        editBtn.setTitle("Cancel".localizedString, for: .selected)
        editBtn.layer.cornerRadius = SCRYFrom(15)
        editBtn.layer.borderWidth = 0.5
        editBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.5).cgColor
        bottomView.addSubview(editBtn)
        editBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(7))
            make.width.equalTo(SCRXFrom(70))
            make.height.equalTo(SCRYFrom(30))
        }
        
        selectAllBtn = UIButton(title: "select_all".localizedString, titleSize: 14, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "select_un", selectedImageName: "select", target: self, action: #selector(selectAllBtnAction))
        selectAllBtn.setImage(UIImage(named: "select_disable"), for: .disabled)
        selectAllBtn.isHidden = true
        bottomView.addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(editBtn.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(editBtn)
        }
        
        moreBtn = UIButton(normalImageName: "share_more", target: self, action: #selector(moreBtnAction))
        bottomView.addSubview(moreBtn)
        moreBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        shareBtn = UIButton(normalImageName: "share", target: self, action: #selector(shareBtnAction))
        bottomView.addSubview(shareBtn)
        shareBtn.snp.makeConstraints { make in
            if site.permission == .owner {
                make.right.equalTo(SCRXFrom(-16))
                make.centerY.equalTo(selectAllBtn)
            }else {
                make.right.equalTo(moreBtn.snp.left).offset(SCRXFrom(-16))
                make.centerY.equalTo(selectAllBtn)
            }
        }
        
        viewRecordBtn = UIButton(normalImageName: "share_check", target: self, action: #selector(viewRecordBtnAction))
        bottomView.addSubview(viewRecordBtn)
        viewRecordBtn.snp.makeConstraints { make in
            make.right.equalTo(shareBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        deleteBtn = UIButton(normalImageName: "share_delete", target: self, action: #selector(deleteBtnAction))
        bottomView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(viewRecordBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        
        unbindBtn = UIButton(normalImageName: "", target: self, action: #selector(unbindBtnAction))
        bottomView.addSubview(unbindBtn)
        unbindBtn.snp.makeConstraints { make in
            make.center.equalTo(moreBtn)
        }
        
        flowLayout = UICollectionViewFlowLayout()
        flowLayout.minimumLineSpacing = SCRYFrom(14)
        flowLayout.minimumInteritemSpacing = SCRXFrom(15)
        
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: flowLayout)
        collectionView.contentInset = UIEdgeInsets(top: SCRYFrom(22), left: SCRXFrom(16), bottom: SCRXFrom(16), right: SCRXFrom(16))
        collectionView.register(ShareAuthoritySpaceViewCell.classForCoder(), forCellWithReuseIdentifier: "cell")
        collectionView.backgroundColor = Background_Color
        collectionView.alwaysBounceVertical = true
        collectionView.dataSource = self
        collectionView.delegate = self
        view.addSubview(collectionView)
        collectionView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(topBarView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
    }
    
    
    private func updateUI() {
        
        
        // 筛选
        switch filterType {
        case .favorite:
            showSpaces = allSpaces.filter({ $0.isFavourite })
        case .editor:
            showSpaces = allSpaces.filter({ $0.isFavourite })
        case .noEditor:
            showSpaces = allSpaces.filter({ $0.editor == nil })
        case .editorName(let name):
            showSpaces = allSpaces.filter({ $0.editor?.name == name })
        case .visitorName(let name):
            showSpaces = allSpaces.filter({ space in space.visitors.contains(where: { $0.name == name }) })
        case .visitorPassword:
//            showSpaces =
            showSpaces = allSpaces
        case .noVisitorPassword:
            showSpaces = allSpaces
        case .devicesExists:
            showSpaces = allSpaces.filter({ $0.deviceCount > 0 })
        case .noDevices:
            showSpaces = allSpaces.filter({ $0.deviceCount == 0 })
        default:
            showSpaces = allSpaces
        }
        
        // 排序
        switch orderedType {
        case .ascending: // 升序
            switch sortType {
            case .createdDate:
                showSpaces.sort(by: { $0.create > $1.create })
                
            case .updatedDate:
                showSpaces.sort(by: { $0.lastUpdate > $1.lastUpdate })
                
            case .alphabetical:
                showSpaces.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
                
            case .deviceQuantity:
                showSpaces.sort(by: { $0.deviceCount < $1.deviceCount })
            }
        case .descending: // 降序
            switch sortType {
            case .createdDate:
                showSpaces.sort(by: { $0.create < $1.create })
                
            case .updatedDate:
                showSpaces.sort(by: { $0.lastUpdate < $1.lastUpdate })

            case .alphabetical:
                showSpaces.sort(by: { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedDescending })

            case .deviceQuantity:
                showSpaces.sort(by: { $0.deviceCount > $1.deviceCount })
            }
        }
        
        selectSpaces = showSpaces.filter({ space in selectSpaces.contains(where: { $0.id == space.id }) })
        
        sortBtn.setTitle(sortType.rawString, for: .normal)
        sortBtn.sizeToFit()
        sortBtn.setImagePosition(position: .right, spacing: SCRXFrom(4))
        
        updateBottomUI()
        
        collectionView.reloadData()
        
        if showSpaces.isEmpty {
            collectionView.showEmptyDataView(title: "no_spaces".localizedString)
        }else {
            collectionView.hideEmptyDataView()
        }
        
    }
    private func updateBottomUI() {
        
        switch type {
        case .share:
            viewRecordBtn.isHidden = false
            shareBtn.isHidden = false
//            if site.permission == .owner {
                moreBtn.isHidden = true
                deleteBtn.isHidden = false
//            }else {
//                moreBtn.isHidden = false
//                deleteBtn.isHidden = true
//            }
            unbindBtn.isHidden = true
        case .management:
            deleteBtn.isHidden = true
            viewRecordBtn.isHidden = true
            shareBtn.isHidden = true
            moreBtn.isHidden = false
            unbindBtn.isHidden = true
        case .unbind:
            deleteBtn.isHidden = true
            viewRecordBtn.isHidden = true
            shareBtn.isHidden = true
            moreBtn.isHidden = true
            unbindBtn.isHidden = false
        }
        
        if isSelectState {
            selectAllBtn.isHidden = false
            // 判断是否选中所有可选space
            selectAllBtn.isSelected = selectSpaces.count == showSpaces.count
        }else {
            selectAllBtn.isHidden = true
        }
        deleteBtn.isEnabled = selectSpaces.count > 0
        shareBtn.isEnabled = selectSpaces.count > 0
        moreBtn.isEnabled = selectSpaces.count > 0
        viewRecordBtn.isEnabled = allSpaces.count > 0
    }
    
}

extension ShareAuthorityViewController: UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return showSpaces.count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "cell", for: indexPath) as! ShareAuthoritySpaceViewCell
        let space = showSpaces[indexPath.item]
        cell.nameLabel.text = space.name
        cell.iconImageView.image = UIImage(named: "space_picture_\(space.imageId)")
        cell.deviceCountLabel.text = "\(space.deviceCount)"
        if isSelectState && space.permission != .visitor {
            cell.selectImageView.isHidden = false
            cell.selectImageView.image = UIImage(named: selectSpaces.contains(where: { $0.id == space.id }) ? "select" : "select_un")
        }else {
            cell.selectImageView.isHidden = true
        }
        if site.permission == .owner {
            cell.editorImageView.isHidden = space.editor == nil
        }else {
            cell.permissionLabel.text = space.permission.rawString
            cell.permissionLabel.isHidden = false
        }
        
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        var itemW = (collectionView.width - collectionView.contentInset.left - collectionView.contentInset.right - flowLayout.minimumInteritemSpacing) / 2.0
        itemW = CGFloat(floorf(Float(itemW) * 100) / 100.0)
        return CGSize(width: itemW , height: SCRYFrom(156))
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        
        let space = showSpaces[indexPath.item]
        guard space.permission != .visitor else {
            XWHUDManager.showTipHUD("no_permission".localizedString)
            return
        }
        
        // 可选择状态
        if isSelectState {
            
            let space = showSpaces[indexPath.item]
            if selectSpaces.contains(where: { $0.id == space.id }) {
                selectSpaces.removeAll(where: { $0.id == space.id })
            }else {
                selectSpaces.append(space)
            }
            collectionView.reloadItems(at: [indexPath])
            updateBottomUI()
            
        }else {
            // 跳转到二维码分享页面
            let vc = SharingSettingViewController(type: .space(site: site, space: space))
            navigationController?.pushViewController(vc, animated: true)
        }
    }
}

extension ShareAuthorityViewController {
    
    /// 操作类型
    enum OperationType {
        /// 分享
        case share
        /// 管理
        case management
        /// 解绑
        case unbind
    }
    
    /// 排序类型
    enum SortType {
        
        var rawString: String {
            switch self {
            case .createdDate:
                return "created_date".localizedString
            case .updatedDate:
                return "updated_date".localizedString
            case .alphabetical:
                return "alphabetical".localizedString
            case .deviceQuantity:
                return "device_quantity".localizedString
            }
        }
        
        /// 创建时间
        case createdDate
        /// 更新时间
        case updatedDate
        /// 字母顺序
        case alphabetical
        /// 设备数量
        case deviceQuantity
    }
    
    /// 排序方式
    enum SortOrder {
        /// 升序
        case ascending
        /// 降序
        case descending
    }

    
}
