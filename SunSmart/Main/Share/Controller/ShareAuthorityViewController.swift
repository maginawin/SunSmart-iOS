//
//  ShareAuthorityViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/30.
//

import UIKit
import SwiftyJSON

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
    /// 正在加载空间数据中
    private var loadingSpacesData: Bool = false
    
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

        setupUI()
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
//            allSpaces = site.spaces
//            updateUI()
        case .unbind:
            title = "unbind".localizedString
//            allSpaces = site.spaces
//            updateUI()
        }
        loadSpacesReqeust()
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        updateUI()
    }
    
    private func setupData() {
        
        self.allSpaces = self.site.spaces
        self.updateUI()
//        self.showSpaces = self.allSpaces
//        self.collectionView.reloadData()
//        self.updateBottomUI()
    }
    
    // MARK: - Request
    /// 获取spaces请求
    private func loadSpacesReqeust() {
        
        loadingSpacesData = true
        XWHUDManager.showCustomHUD(withMessage: nil, view: self.view)
//        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: false)
        navigationItem.rightBarButtonItem?.isEnabled = false
        NetworkRequest.shared.request(.siteInfo(siteId: self.site.id)) {[weak self] result in
            guard let self = self else { return }
            self.loadingSpacesData = false
            switch result {
            case .success(let response):
                if let siteData = JSON(response)["data"].dictionaryObject {
//                    let site = SiteData.import(siteJsonData: siteData)
                    Task {
                        await self.site.update(siteJsonData: siteData)
                        self.site.save()
                        XWHUDManager.hideInView(with: self.view)
                        self.navigationItem.rightBarButtonItem?.isEnabled = true
                        self.setupData()
                    }
                }else {
                    XWHUDManager.hideInView(with: self.view)
                    self.navigationItem.rightBarButtonItem?.isEnabled = true
                    self.setupData()
                }
            case .failure(_):
                XWHUDManager.hideInView(with: self.view)
                self.navigationItem.rightBarButtonItem?.isEnabled = true
                self.setupData()
            }
            
        }
    }
    
    /// 批量清除space editor
    private func clearSpacesEditorRequest(spaces: [SpaceData]) {
        
//        let deleteEditorSpaces = spaces.filter({ $0.editor != nil })

        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.clearSpacesMembers(siteId: site.id, spaces: spaces.map({ $0.id }), permission: .editor, force: false)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                // 删除成员的结果
                if let detail = JSON(response)["data"]["detail"].dictionaryObject as? [String: [String: Int]] {
                    // 删除的Editor中正在使用space
                    var usedEditorIds: [String] = []
                    // 删除成功的Editor
                    var successEditorIds: [String] = []
                    detail.forEach({ data in
                        usedEditorIds.append(contentsOf: data.value.filter({ $0.value == NetworkApiError.editorBeingUsedSpace.code }).map({ $0.key }))
                        if data.value.isEmpty {
                            if let space = spaces.first(where: { space in data.key == space.id }), let editorId = space.editor?.uuid {
                                successEditorIds.append(editorId)
                            }
                        }else {
                            successEditorIds.append(contentsOf: data.value.filter({ $0.value == 200 }).map({ $0.key }))
                        }
                    })
                    // 删除editor成功的space更新缓存
                    spaces.forEach({
                        if let editorId = $0.editor?.uuid, successEditorIds.contains(editorId) {
                            $0.editor = nil
                            $0.save()
                        }
                    })
                    self.isSelectState = false
                    self.selectSpaces.removeAll()
                    self.updateUI()
                    
                    if usedEditorIds.count > 0 { // 部分用户正在使用space，无法删除
                        SRAlertView(title: "notification".localizedString, message: "spaces_clear_editor_failed".localizedString, actions: [SRAlertAction(title: "confirm".localizedString)]).show()
                    }else {
                        XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                    }
                    
                }else {
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
    
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 批量清除space vistors
    private func clearSpacesVistorsRequest(spaces: [SpaceData], force: Bool = false) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.clearSpacesMembers(siteId: site.id, spaces: spaces.map({ $0.id }), permission: .visitor, force: force)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                // 删除成员的结果
                if let detail = JSON(response)["data"]["detail"].dictionaryObject as? [String: [String: Int]] {
                    // 删除的vistors中正在使用space
//                    let usedEditorIds = detail.filter({ $0.value == NetworkApiError.visitorBeingUsedSpace.code }).map({ $0.key })
                    // 删除成功的vistors
//                    let successVistorIds = detail.filter({ $0.value == NetworkApiError.visitorBeingUsedSpace.code }).map({ $0.key })
                    
                    // 删除的vistors中正在使用space
                    var usedVistorIds: [String] = []
                    // 删除成功的vistors
                    var successVistorIds: [String] = []
                    detail.forEach({ data in
                        usedVistorIds.append(contentsOf: data.value.filter({ $0.value == NetworkApiError.visitorBeingUsedSpace.code }).map({ $0.key }))
                        if data.value.isEmpty {
                            if let space = spaces.first(where: { space in data.key == space.id }), space.visitors.count > 0 {
                                successVistorIds.append(contentsOf: space.visitors.map({ $0.uuid }))
                            }
                        }else {
                            successVistorIds.append(contentsOf: data.value.filter({ $0.value == 200 }).map({ $0.key }))
                        }
                    })
                    
                    // 删除vistor成功的space更新缓存
                    spaces.forEach({
                        var spaceChanged = false
                        if let index = $0.visitors.firstIndex(where: { visitor in successVistorIds.contains(visitor.uuid) }) {
                            $0.visitors.remove(at: index)
                            spaceChanged = true
                        }
                        if spaceChanged {
                            $0.save()
                        }
                    })
                    
                    if usedVistorIds.count > 0 { // 部分用户正在使用space，无法删除
                        // 强制删除 / 跳过
                        SRAlertView(title: "notification".localizedString, message: "space_delete_used_visitors_message".localizedString, actions: [SRAlertAction(title: "skip".localizedString, style: .cancel, actionHandler: {[weak self] _ in
                            guard let self = self else { return }
                            
                            self.selectSpaces.removeAll()
                            self.isSelectState = false
                            self.updateUI()
                            
                        }), SRAlertAction(title: "clear".localizedString, actionHandler: {[weak self] _ in
                            // 强制删除请求
                            self?.clearSpacesVistorsRequest(spaces: spaces, force: true)
                        })]).show()
                    }else { // 删除成功
                        XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                        self.selectSpaces.removeAll()
                        self.isSelectState = false
                        self.updateUI()
                    }
                    
                }else {
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
    
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 批量分享spaces
    private func batchShareSpacesReqeust(spaces: [SpaceData]) {
        
        let password = String.generateRandomNumberString()
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.spacesShare(siteId: site.id, spaceIds: spaces.map({ $0.id }), password: password)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                guard let batchId = JSON(response)["data"]["batchId"].string else { return }
                
                let batchData = BatchSpaceData(siteId: self.site.id, code: batchId, name: JSON(response)["data"]["batchName"].string ?? "", spaces: spaces, editorPassword: password)
                
                let vc = SharingSettingViewController(type: .batchSpace(data: batchData))
                navigationController?.pushViewController(vc, animated: true)
                
                self.isSelectState = false
                self.selectSpaces.removeAll()
                self.updateUI()
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// space分享
    private func spaceShareReqeuest(space: SpaceData) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        
        var networkApi: NetowrkReqeustApi!
        // 有site转让code则读取之前的数据
        if let shareCode = space.shareCode, space.editorPassword != nil {
            networkApi = .shareInfo(shareId: shareCode)
        }else {
            // 还没有设置编辑者密码
            if space.permission == .owner && space.editorPassword == nil {
                space.editorPassword = String.generateRandomNumberString()
            }
            networkApi = .spaceShare(space: space)
        }
        
        NetworkRequest.shared.request(networkApi) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(let response):
                guard let code = JSON(response)["data"]["token"].string else {
                    return
                }
                var saveSpace = false
                if case .spaceShare = networkApi {
                    saveSpace = true
                }else {
                    // 更新owner数据
                    if let ownerData = JSON(response)["data"]["space"]["owner"].dictionaryObject {
                        if let userId = ownerData["userId"] as? String, let userName = ownerData["username"] as? String {
                            if space.owner?.uuid != userId {
                                space.owner = .init(name: userName, uuid: userId)
                                saveSpace = true
                            }
                        }
                    }
                    
                    // 更新editor数据
                    if let editorData = JSON(response)["data"]["space"]["editor"].dictionaryObject {
                        if let userId = editorData["userId"] as? String, let userName = editorData["username"] as? String {
                            if space.editor?.uuid != userId {
                                space.editor = .init(name: userName, uuid: userId)
                                saveSpace = true
                            }
                        }else {
                            if space.editor != nil {
                                space.editor = nil
                                saveSpace = true
                            }
                        }
                    }
                }
                // 邀请码
                if space.shareCode != code {
                    space.shareCode = code
                    saveSpace = true
                }
                if saveSpace {
                    space.save()
                }
                let vc = SharingSettingViewController(type: .space(site: self.site, space: space))
                self.navigationController?.pushViewController(vc, animated: true)
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    /// 批量重置space editor/vistor密码
    private func regeneratesMemberPasswordRequest(spaces: [SpaceData], permission: Permission) {
        guard spaces.count > 0, permission != .owner else {
            return
        }
        let passwordDatas = selectSpaces.map({ NetowrkReqeustApi.SpacePasswordData(spaceId: $0.id, password: String.generateRandomNumberString(), permission: permission) })
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.spacesPasswordSet(siteId: site.id, spacePasswords: passwordDatas)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                spaces.forEach({ space in
                    if let passwordData = passwordDatas.first(where: { space.id == $0.spaceId }) {
                        if passwordData.permission == .editor {
                            space.editorPassword = passwordData.password
                        }else if passwordData.permission == .visitor {
                            space.vistorPassword = passwordData.password
                        }
                        space.save()
                    }
                })
                self.isSelectState = false
                self.selectSpaces.removeAll()
                self.updateUI()
                
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    /// 清空访客密码请求
    private func clearVistorPasswordReqeust(spaces: [SpaceData]) {
        
        guard spaces.count > 0 else {
            return
        }
        let passwordDatas = spaces.map({
            return NetowrkReqeustApi.SpacePasswordData(spaceId: $0.id, password: nil, permission: .visitor)
        })
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.spacesPasswordSet(siteId: site.id, spacePasswords: passwordDatas)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            
            switch result {
            case .success(_):
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                spaces.forEach({ space in
//                    if let passwordData = passwordDatas.first(where: { space.id == $0.spaceId }) {
                        space.vistorPassword = nil
                        space.save()
//                    }
                })
                self.isSelectState = false
                self.selectSpaces.removeAll()
                self.updateUI()
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    /// 启用/禁用访客密码
//    private func setVistorPasswordStateReqeust(spaces: [SpaceData], enabled: Bool) {
//        
//        guard spaces.count > 0 else {
//            return
//        }
//        let passwordDatas = selectSpaces.map({
//            if enabled { // 启用密码
//                // 之前有设置密码使用之前的密码，没有设置密码随机生成一个
//               return NetowrkReqeustApi.SpacePasswordData(spaceId: $0.id, password: $0.vistorPassword ?? String.generateRandomNumberString(), permission: .visitor)
//            }else { // 禁用密码
//                return NetowrkReqeustApi.SpacePasswordData(spaceId: $0.id, password: nil, permission: .visitor)
//            }
//            
//        })
//        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
//        NetworkRequest.shared.request(.spacesVisitorPasswordEnabled(siteId: site.id, spacePasswords: passwordDatas, enabled: enabled)) {[weak self] result in
//            XWHUDManager.hide()
//            guard let self = self else { return }
//            
//            switch result {
//            case .success(_):
//                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
//                spaces.forEach({ space in
//                    if let passwordData = passwordDatas.first(where: { space.id == $0.spaceId }) {
//                        space.vistorPassword = passwordData.password
//                        space.save()
//                    }
//                })
//                self.isSelectState = false
//                self.selectSpaces.removeAll()
//                self.updateUI()
//            case .failure(let error):
//                XWHUDManager.showErrorTipHUD(error.localizedDescription)
//            }
//        }
//        
//    }
    
    /// spaces批量删除请求
    private func spacesDeleteRequest(spaces: [SpaceData]) {
        // 获取可以删除的space，有设备必须先删除设备
        let canDeleteSpaces = spaces.filter({ $0.deviceCount == 0 })
        // 没有可删除的space
        if canDeleteSpaces.isEmpty {
            SRAlertView(title: "notification".localizedString, message: "spaces_delete_failed".localizedString, actions: [SRAlertAction(title: "confirm".localizedString)]).show()
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: "deleting".localizedString, isWindow: true)
        NetworkRequest.shared.request(.spacesDelete(siteId: site.id, spaceIds: canDeleteSpaces.map({ $0.id }))) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
//                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                self.site.spaces.removeAll(where: { deleteSpace in canDeleteSpaces.contains(where: { deleteSpace.id == $0.id }) })
                self.allSpaces = self.site.spaces
                self.selectSpaces.removeAll()
                self.isSelectState = false
                self.updateUI()
                canDeleteSpaces.forEach({
                    $0.delete()
                })
                if canDeleteSpaces.count < spaces.count { // 有部分space删除失败
                    SRAlertView(title: "notification".localizedString, message: "spaces_delete_failed".localizedString, actions: [SRAlertAction(title: "confirm".localizedString)]).show()
                }
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
                NotificationCenter.default.post(name: .init(SpacesRefreshChangeNotificationName), object: nil)
                
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 批量解绑space请求
    private func spacesUnbindRequest(spaces: [SpaceData]) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        
        let uploadSpaces = spaces.filter({ $0.needUploadCloud })
        guard uploadSpaces.count > 0 else {
            Task {
                let siteDict = await site.export(spaceIds: uploadSpaces.map({ $0.id }))
                NetworkRequest.shared.request(.siteUpload(siteData: siteDict)) {[weak self] result in
                    XWHUDManager.hide()
                    switch result {
                    case .success(_):
                        uploadSpaces.forEach({
                            $0.lastUploadCloudTimestamp = $0.lastUpdate
                            $0.save()
                        })
                        // 同步完space数据后解绑space
                        self?.spacesUnbindRequest(spaces: spaces)
                    case .failure(let error):
                        XWHUDManager.showErrorTipHUD(error.localizedDescription)
                    }
                }
            }
            return
        }
        
        // 回收地址数据
        let recycleData = site.getRecycleAddressData(unbindSpaces: spaces)
        
        let networkApi: NetowrkReqeustApi = .unbindSpaces(siteId: site.id, spaceIds: spaces.map({ $0.id }), recycleDeviceAddresses: recycleData.deviceAddresses, recycleGroupAddresses: recycleData.groupAddresses, recycleSceneAddresses: recycleData.sceneAddresses, exclusions: recycleData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) }))
        
        NetworkRequest.shared.request(networkApi) {[weak self] result in
            XWHUDManager.hide()
            
            guard let self = self else { return }
            switch result {
            case .success(_):
//                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                // 删除回收的地址
                self.site.deleteProvisionerAddress(deviceAddresses: recycleData.deviceAddresses, groupAddresses: recycleData.groupAddresses, sceneAddresses: recycleData.sceneAddresses)
                
                spaces.forEach { deleteSpace in
                    if let spaceIndex = self.site.spaces.firstIndex(where: { $0.id == deleteSpace.id }) {
                        self.site.spaces.remove(at: spaceIndex)
                    }
                    deleteSpace.delete()
                }
                if self.site.spaces.isEmpty && self.site.permission != .owner { // 不属于site所有者并且解绑所有spaces则清空site记录
                    self.site.delete()
                    self.site.state = .waitDeleted
                    self.close()
                }else {
                    self.allSpaces = self.site.spaces
                    self.selectSpaces.removeAll()
                    self.isSelectState = false
                    self.updateUI()
                }
                NotificationCenter.default.post(name: .init(rawValue: SiteStateChangeNotificationName), object: nil)
                NotificationCenter.default.post(name: .init(rawValue: SitesDataRefreshNotifiacationName), object: nil)
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
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
        
//        $0.visitors.map({ $0.name })
        var filters: [ShareAuthorityFilterView.FilterData] = []
        if site.permission == .owner {
            var editorNames: [String] = []
            var visitorNames: [String] = []
            self.allSpaces.forEach({ space in
                if let editorName = space.editor?.name {
                    if !editorNames.contains(editorName) {
                        editorNames.append(editorName)
                    }
                }
                space.visitors.forEach({
                    if !visitorNames.contains($0.name) {
                        visitorNames.append($0.name)
                    }
                })
            })
            filters = ShareAuthorityFilterView.FilterData.defalutFilters(editorNames: editorNames, visitorNames: visitorNames)
        }else {
            filters = ShareAuthorityFilterView.FilterData.editorDefalutFilters()
        }
        
        ShareAuthorityFilterView(filters: filters, selectFilterType: self.filterType) {[weak self] selectType in
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
        if !isSelectState {
            selectSpaces.removeAll()
        }
        updateUI()
    }
    
    /// 选中全部
    @objc private func selectAllBtnAction(sender: UIButton) {
//        sender.isSelected = !sender.isSelected
        if sender.isSelected {
            selectSpaces.removeAll()
        }else {
            if type == .share {
                selectSpaces = showSpaces.filter({ ($0.permission == .owner && $0.editor == nil) || ($0.permission == .editor && $0.state == .normal) })
            }else {
                selectSpaces = showSpaces
            }
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
        
        SRAlertView(title: "notification".localizedString, message: "share_spaces_delete_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            guard let self = self else { return  }
            self.spacesDeleteRequest(spaces: self.selectSpaces)
        })]).show()
    }
    
    /// 分享
    @objc private func shareBtnAction() {
        
        guard selectSpaces.count > 0 else {
            return
        }
        batchShareSpacesReqeust(spaces: selectSpaces)
    }
    
    /// 更多
    @objc private func moreBtnAction(sender: UIButton) {
        
        var items: [MenuPopView.MenuItem] = []
        
        if site.permission == .owner {
            items.append(.init(icon: UIImage(named: "share_clear_member"), title: "clear_editor".localizedString, tapItemBack: {[weak self] _ in
                // 清空editor
                self?.showAlertNotification(message: "spaces_clear_editor_message".localizedString, doneActionHandle: {[weak self] in
                    guard let self = self, self.selectSpaces.count > 0 else { return }
                    self.clearSpacesEditorRequest(spaces: self.selectSpaces)
                })
            }))
        }
        
        // 清空visitor
        items.append(.init(icon: UIImage(named: "share_clear_member"), title: "clear_visitor".localizedString, tapItemBack: {[weak self] _ in
            self?.showAlertNotification(message: "spaces_clear_visitors_message".localizedString, doneActionHandle: {[weak self] in
                guard let self = self, self.selectSpaces.count > 0 else { return }
                self.clearSpacesVistorsRequest(spaces: self.selectSpaces)
            })
        }))
        
        // 重置访客密码
        items.append(.init(icon: UIImage(named: "reset_password"), title: "regenerates_visitor_password".localizedString, tapItemBack: {[weak self] _ in
            self?.showAlertNotification(message: "spaces_reset_visitor_password_message".localizedString) {[weak self] in
                guard let self = self, self.selectSpaces.count > 0 else { return }
                self.regeneratesMemberPasswordRequest(spaces: self.selectSpaces, permission: .visitor)
            }
        }))
        
        // 清空访客密码
        items.append(.init(icon: UIImage(named: "disable_password"), title: "clear_visitor_password".localizedString, tapItemBack: {[weak self] _ in
            self?.showAlertNotification(message: "spaces_clear_visitor_password_message".localizedString) {[weak self] in
                guard let self = self, self.selectSpaces.count > 0 else { return }
//                self.setVistorPasswordStateReqeust(spaces: self.selectSpaces, enabled: false)
                self.clearVistorPasswordReqeust(spaces: self.selectSpaces)
            }
        }))
        
        // 启用访客密码
//        items.append(.init(icon: UIImage(named: "enable_password"), title: "enable_visitor_password".localizedString, tapItemBack: {[weak self] _ in
//            self?.showAlertNotification(message: "spaces_enable_visitor_password_message".localizedString) {[weak self] in
//                guard let self = self, self.selectSpaces.count > 0 else { return }
//                self.setVistorPasswordStateReqeust(spaces: self.selectSpaces, enabled: true)
//            }
//        }))
        
        if site.permission == .owner {
            // 重置editor密码
            items.append(.init(icon: UIImage(named: "reset_password"), title: "regenerates_editor_password".localizedString, tapItemBack: {[weak self] _ in
                self?.showAlertNotification(message: "spaces_reset_editor_password_message".localizedString) {[weak self] in
                    guard let self = self, self.selectSpaces.count > 0 else { return }
                    self.regeneratesMemberPasswordRequest(spaces: self.selectSpaces, permission: .editor)
                }
            }))
        }
        
        let point = CGPoint(x: sender.center.x, y: bottomView.frame.minY) // + SCRYFrom(30)
        let viewPoint = UIApplication.shared.keyWindow().convert(point, from: view)
        
        MenuPopView.show(items: items, anchorPoint: viewPoint, direction: .up, menuWidth: SCRXFrom(220))
        
    }
    
    
    /// 解绑
    @objc private func unbindBtnAction() {
        guard selectSpaces.count > 0 else {
            return
        }
        spacesUnbindRequest(spaces: selectSpaces)
    }
    
    /// 弹窗提示
    private func showAlertNotification(message: String, doneActionHandle: (()->Void)?) {
        
        SRAlertView(title: "notification".localizedString, message: message, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: { _ in
            doneActionHandle?()
        })]).show()
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
        
        filterBtn = UIButton(normalImageName: "filter", selectedImageName: "filter_selected", target: self, action: #selector(filterBtnAction))
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
        shareBtn.isEnabled = false
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
        deleteBtn.isEnabled = false
        bottomView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(viewRecordBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
        }
        
        
        unbindBtn = UIButton(normalImageName: "share_unbind", target: self, action: #selector(unbindBtnAction))
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
        collectionView.panGestureRecognizer.cancelsTouchesInView = false
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
            showSpaces = allSpaces.filter({ $0.editor != nil })
        case .noEditor:
            showSpaces = allSpaces.filter({ $0.editor == nil })
        case .isEditor:
            showSpaces = allSpaces.filter({ $0.permission == .editor })
        case .isVisitor:
            showSpaces = allSpaces.filter({ $0.permission == .visitor })
        case .editorName(let name):
            showSpaces = allSpaces.filter({ $0.editor?.name == name })
        case .visitorName(let name):
            showSpaces = allSpaces.filter({ space in space.visitors.contains(where: { $0.name == name }) })
        case .visitorPassword:
//            showSpaces =
            showSpaces = allSpaces.filter({ $0.vistorPasswordEnable && !($0.vistorPassword?.isEmpty ?? true) })
        case .noVisitorPassword:
            showSpaces = allSpaces.filter({ !$0.vistorPasswordEnable || ($0.vistorPassword?.isEmpty ?? true) })
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
        
        if filterType == nil {
            filterBtn.isSelected = false
        }else {
            filterBtn.isSelected = true
        }
        
        updateBottomUI()
        if !loadingSpacesData {
            updateEmptyUI()
        }
        collectionView.reloadData()
        
    }
    private func updateBottomUI() {
        
        switch type {
        case .share:
            viewRecordBtn.isHidden = false
            shareBtn.isHidden = false
            if site.permission == .owner {
                moreBtn.isHidden = true
                deleteBtn.isHidden = false
            }else {
                moreBtn.isHidden = false
                deleteBtn.isHidden = true
            }
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
            var canSelectSpaces = showSpaces
            if type == .share {
                canSelectSpaces = showSpaces.filter({ ($0.permission == .owner && $0.editor == nil) || ($0.permission == .editor && $0.state == .normal) })
            }
            
            selectAllBtn.isSelected = selectSpaces.count > 0 && selectSpaces.count == canSelectSpaces.count
            editBtn.isSelected = true
        }else {
            selectAllBtn.isHidden = true
            editBtn.isSelected = false
        }
        deleteBtn.isEnabled = selectSpaces.count > 0
        shareBtn.isEnabled = selectSpaces.count > 0
        moreBtn.isEnabled = selectSpaces.count > 0
        viewRecordBtn.isEnabled = allSpaces.count > 0
        
    }
    
    private func updateEmptyUI() {
        if showSpaces.isEmpty {
            if collectionView.frame == .zero {
                view.layoutIfNeeded()
            }
            collectionView.showEmptyDataView(title: "no_spaces".localizedString)
        }else {
            collectionView.hideEmptyDataView()
        }
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
        if isSelectState {
            switch self.type {
            case .share: // 分享授权页面
                // 不是访客并且未删除
                if (space.permission == .owner && space.editor == nil) || (space.permission == .editor && space.state == .normal) {
                    cell.selectImageView.isHidden = false
                    cell.selectImageView.image = UIImage(named: selectSpaces.contains(where: { $0.id == space.id }) ? "select" : "select_un")
                }else {
                    cell.selectImageView.isHidden = true
                }
            default:
                cell.selectImageView.isHidden = false
                cell.selectImageView.image = UIImage(named: selectSpaces.contains(where: { $0.id == space.id }) ? "select" : "select_un")
            }
        }else {
            cell.selectImageView.isHidden = true
        }
        if site.permission == .owner {
            cell.editorImageView.isHidden = space.editor == nil
        }else {
            cell.permissionLabel.text = space.permission.rawString
            cell.permissionLabel.textColor = space.state == .normal ? TextBlack_Color : RGB(148, 163, 184)
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
        if type == .share && space.permission == .visitor {
            XWHUDManager.showTipHUD("no_permission".localizedString)
            return
        }
        
        // 可选择状态
        if isSelectState {
            if type == .share, space.permission == .owner, space.editor != nil { // owner不能选择已有editor的space
                return
            }
            let space = showSpaces[indexPath.item]
            if selectSpaces.contains(where: { $0.id == space.id }) {
                selectSpaces.removeAll(where: { $0.id == space.id })
            }else {
                selectSpaces.append(space)
            }
            collectionView.reloadItems(at: [indexPath])
            updateBottomUI()
            
        }else {
            spaceShareReqeuest(space: space)
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
