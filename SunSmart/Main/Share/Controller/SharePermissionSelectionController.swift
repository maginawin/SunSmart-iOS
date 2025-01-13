//
//  SharePermissionSelectionController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/29.
//

import UIKit
import SwiftyJSON
import NordicSigMeshSDK

class SharePermissionSelectionController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var tableView: UITableView!
    private var ownerMessageLabel: UILabel?

    private let shareId: String
    private var options: [Options] = []
    private var selectionTypes: [PermissionSelection] = []
    /// 展示导入结果弹窗
    private var showResultAlert: Bool = false
    /// 批量导入的spaces结果
    private var batchImportResults: [BatchSpaceImportResult]?
    
    /// 正在输入的密码框
    private var activeField: UITextField?
    
    
    let type: ReceivingType
    
    init(type: ReceivingType) {
        self.type = type
        self.shareId = type.data.shareId
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    
    override func viewDidLoad() {
        super.viewDidLoad()

//        title = "receiving_site".localizedString
        
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        if case .site = type {
            title = "receiving_site".localizedString
        }else {
            title = "permission_selection".localizedString
        }
        
        options = type.data.options
//        [.title("Batch 53487"), .invitationCode(code: "xxxxxxxx"), .owner(name: "Jesse's iphone 13"), .spaces]
//        selectionTypes = [.init(permission: .owner, requirePwd: true)]
        selectionTypes = type.data.selectTypes
//        [.init(permission: .visitor, requirePwd: false), .init(permission: .editor, requirePwd: true)]
        
        addKeyboardNotification()
        
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if showResultAlert {
            showResultAlert = false
            if let results = batchImportResults {
                showImportResult(results: results)
            }
        }
    }
    
    @objc private func back() {
        dismiss(animated: true)
    }
    
    /// 监听键盘通知
    private func addKeyboardNotification() {
        
        // 键盘弹出通知
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillShowNotification, object: nil, queue: nil) {[weak self] notification in
            guard let self = self, let keyboardFrame = (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? NSValue)?.cgRectValue else { return }
            
            let keyboardHeight = keyboardFrame.height
            var contentInset = scrollView.contentInset
            contentInset.bottom = keyboardHeight
            
            self.scrollView.contentInset = contentInset
            self.scrollView.scrollIndicatorInsets = contentInset
            
            // Optional: 滚动到活跃的文本输入视图
            if let activeField = self.activeField, let superView = activeField.superview {
                let visibleRect = self.scrollView.frame.inset(by: self.scrollView.contentInset)
                let point = superView.convert(activeField.frame.origin, to: self.scrollView)
                if !visibleRect.contains(point) {
                    let scrollPoint = CGPoint(x: 0, y: point.y - visibleRect.height + activeField.frame.height)
                    self.scrollView.setContentOffset(scrollPoint, animated: true)
                }
            }
        }
        
        // 键盘收起通知
        NotificationCenter.default.addObserver(forName: UIResponder.keyboardWillHideNotification, object: nil, queue: nil) {[weak self] notification in
            guard let self = self else { return }
            let contentInset = UIEdgeInsets.zero
            self.scrollView.contentInset = contentInset
            self.scrollView.scrollIndicatorInsets = contentInset
        }
    }
    
    // MARK: - Request
    /// 加入space请求
    private func spaceJoinRequest(space: SpaceData, password: String?, permission: Permission) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
            
        NetworkRequest.shared.request(.joinSpace(shareId: self.shareId, password: password, permission: permission)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                Task {
                    let cacheSpace = SpaceData.load(siteId: space.siteId, spaceId: space.id).first
                    if cacheSpace != nil, let site = SiteData.load(siteId: space.siteId) {
                        // 回收之前清空权限时的地址
                        var recycleAddressData = await site.getRecycleAddressData(unbindSpaces: [cacheSpace!])
                        recycleAddressData.provisionerData = nil
                        recycleAddressData.exclusionAddresses = nil
                        if !recycleAddressData.isEmpty {
//                            let result = await self.recycleAddressReqeust(site: site, recycleData:recycleAddressData)
//                            if !result {
                            // 回收地址数据合并，在打开site时回收
                                if let existRecycleAddressData = site.recycleAddressData {
                                    site.recycleAddressData = existRecycleAddressData + recycleAddressData
                                }else {
                                    site.recycleAddressData = recycleAddressData
                                }
//                            }
                        }
//                        site.state = .normal
                        site.save()
                    }
                    
                    let localSpace = cacheSpace ?? space
                    localSpace.authorizationPassword = password
                    localSpace.permission = permission
                    localSpace.requiresPasswordVerification = false
                    localSpace.applyDeviceAddressCount = nil
                    localSpace.releaseAddress = false
                    localSpace.state = .normal
                    localSpace.save()
                    
                    XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                        NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
                        self?.back()
                    }
                }
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
            
        
        
        
    }
    
    /// 批量加入space请求
    private func spacesJoinRequest(spaces: [SpaceData], password: String?, permission: Permission) {
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.joinSpace(shareId: self.shareId, password: password, permission: permission)) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
//                XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
                
                if let spaceDatas = JSON(response)["data"]["spaces"].arrayObject as? [[String: Any]] {
                    Task {
                        // 之前已移除权限并未回收地址的space
                        var recycleSpaces: [SpaceData] = []
                        let results: [BatchSpaceImportResult] = spaceDatas.compactMap({ spaceData in
                            guard let spaceId = spaceData["spaceId"] as? String, let spaceName = spaceData["spaceName"] as? String else { return nil }
                            
                            var status: BatchSpaceImportResult.Status = .successfully
                            if let statusCode = spaceData["importStatus"] as? Int, let resultStatus = BatchSpaceImportResult.Status(rawValue: statusCode) {
                                status = resultStatus
                            }
                            if status == .successfully {
                                let space = spaces.first(where: { $0.id == spaceId })
                                space?.permission = permission
                                if permission == .editor {
                                    space?.authorizationPassword = spaceData["editorPasswd"] as? String
                                    space?.requiresPasswordVerification = false
                                    space?.applyDeviceAddressCount = nil
                                    space?.releaseAddress = false
                                }
                                // 是否之前存在该space，并且处理权限回收未清空地址状态
                                if let siteId = space?.siteId, let spaceId = space?.id,
                                   let oldSpace = SpaceData.load(siteId: siteId, spaceId: spaceId).first, !oldSpace.releaseAddress {
                                    recycleSpaces.append(oldSpace)
                                }
                                space?.state = .normal
                                space?.save()
                            }
                            
                            let result = BatchSpaceImportResult(spaceId: spaceId, spaceName: spaceName, editorPassword: spaceData["editorPasswd"] as? String, status: status)
                            return result
                        })
                        
                        if let siteId = spaces.first?.siteId, let site = SiteData.load(siteId: siteId) {
                            // 回收之前清空权限时的地址
                            if recycleSpaces.count > 0 {
                                var recycleAddressData = await site.getRecycleAddressData(unbindSpaces: recycleSpaces)
                                recycleAddressData.provisionerData = nil
                                recycleAddressData.exclusionAddresses = nil
                                if !recycleAddressData.isEmpty {
                                    
                                    // 回收地址数据合并，在打开site时回收
                                    if let existRecycleAddressData = site.recycleAddressData {
                                        site.recycleAddressData = existRecycleAddressData + recycleAddressData
                                    }else {
                                        site.recycleAddressData = recycleAddressData
                                    }
                                    //                                let result = await self.recycleAddressReqeust(site: site, recycleData: recycleAddressData)
                                    //                                if !result {
                                    //                                    site.recycleAddressData = recycleAddressData
                                    //                                }
                                }
                            }
//                            site.state = .normal
                            site.save()
                        }
                        XWHUDManager.hide()
                        self.batchImportResults = results
                        self.showImportResult(results: results)
                    }
                }
                
                NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
    
            case .failure(let error):
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 接收site请求
    private func receiveSiteRequest(password: String) {
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.receiveSite(shareId: self.shareId, password: password)) {[weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(let response):
//                没有site   切换一个与之前owner不重复的地址，并回收之前owner的手机地址
//                已有site   使用之前的手机地址，并回收之前owner的手机地址
                if var siteData = JSON(response)["data"]["site"].dictionaryObject {
                    if let provisionerDict = JSON(response)["data"]["provisioner"].dictionaryObject {
                        siteData.updateValue(provisionerDict, forKey: "provisioner")
                    }
                    if let exclusions = JSON(response)["data"]["exclusions"].arrayObject {
                        siteData.updateValue(exclusions, forKey: "exclusions")
                    }
                    Task {
                        var recycleAddressData: SiteData.RecycleAddressData?
                        if let siteId = siteData["uuid"] as? String, let localSite = SiteData.load(siteId: siteId), localSite.permission != .owner {
                            // 判断是否存在这个site，如果有则主动回收自己之前拥有的地址
                            var recycleData = await localSite.getRecycleAddressData(unbindSpaces: localSite.spaces)
                            recycleData.provisionerData = nil
                            if !recycleData.isEmpty {
                                let result = await self.recycleAddressReqeust(site: localSite, recycleData: recycleData)
                                localSite.delete()
                                if !result {
                                    recycleAddressData = recycleData
                                }
                            }
                                // 回收之前owner的手机地址
//                                if let ivIndex = JSON(siteData)["ivIndex"].uInt32, let addressHex = JSON(siteData)["provisioner"]["address"].string, let localAddress = Address(hex: addressHex) {
//                                    site.insetExclusionAddresses(list: [(ivIndex, [localAddress])])
//                                }
//                                // 合并废弃地址数据
//                                if let exclusionAddresses: [(ivIndex: UInt32, addresses: [UInt16])] = recycleData.exclusionAddresses?.map({ (UInt32($0.ivIndex), $0.addresses.map({ UInt16($0) })) }) {
//                                    site.insetExclusionAddresses(list: exclusionAddresses)
//                                    recycleData.exclusionAddresses = nil
//                                }
//                                // 回收未使用的地址
//                                if !recycleData.isEmpty {
//                                    let result = await self.recycleAddressReqeust(site: site, recycleData: recycleData)
//                                    if !result {
//                                        site.recycleAddressData = recycleData
//                                    }
//                                    site.save()
//                                }
//                                // 立即将合并废弃地址/修改的手机地址数据同步到云端
//                                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
//                            }else {
//                                site.save()
//                                // 立即将合并废弃地址/修改的手机地址数据同步到云端
//                                CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
//                            }
//                            localSite = SiteData.load(siteId: siteId)
                            
//                            if localSite != nil && localSite?.localAddress != nil && localSite?.state == .normal {
//                                changeAddress = false
//                            }
                        }
                        
                        if let site = await SiteData.import(siteJsonData: siteData, changeAddress: true) {
                            site.state = .normal
                            site.permission = .owner
                            site.recycleAddressData = recycleAddressData
                            site.save()
                            // 修改手机地址需要合并到服务器
                            CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: []), level: .promptly)
                        }
                         
                        XWHUDManager.hide()
                        XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                            NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
                            self?.back()
                        }
                        
                    }
                }else {
                    XWHUDManager.hide()
                    XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {[weak self] in
                        NotificationCenter.default.post(name: .init(SitesDataRefreshNotifiacationName), object: true)
                        self?.back()
                    }
                }
               
                
            case .failure(let error):
                XWHUDManager.hide()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    
    /// 回收地址请求（接收转让的Site后，如之前在这个Site内需回收之前分配的地址 / 导入已存在且未回收地址的space）
    /// - Parameters:
    ///   - site: site
    ///   - recycleData: 回收地址数据
    private func recycleAddressReqeust(site: SiteData, recycleData: SiteData.RecycleAddressData) async -> Bool {
        
        let networkApi: NetowrkReqeustApi = .recyclingAddress(siteId: site.id, recycleDeviceAddresses: recycleData.deviceAddresses, recycleGroupAddresses: recycleData.groupAddresses, recycleSceneAddresses: recycleData.sceneAddresses, exclusions: recycleData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) }), provisionerData: recycleData.provisionerData)
//        recycleData.exclusionAddresses?.map({ ($0.ivIndex, $0.addresses) })
        return await withCheckedContinuation { continuation in
            NetworkRequest.shared.request(networkApi) { result in
                switch result {
                case .success(_):
                    continuation.resume(returning: true)
                case .failure(_):
                    continuation.resume(returning: false)
                }
            }
        }
        
    }
    
    
    /// 申请权限
    private func applyPermission(_ permission: Permission, password: String?) {
        
        switch self.type {
        case .site:
            guard let receivePassword = password else { return }
            receiveSiteRequest(password: receivePassword)
        case .space(_, let space, _, _):
            spaceJoinRequest(space: space, password: password, permission: permission)
        case .spaceList(let data, _, _):
            spacesJoinRequest(spaces: data.spaces, password: password, permission: permission)
        }
    }
    
    private func showImportResult(results: [BatchSpaceImportResult]) {
        
        BatchImportResultView(results: results, helpCallback: {[weak self] in
            self?.showResultAlert = true
            
            let vc = BatchImportResultHelpController()
            self?.navigationController?.pushViewController(vc, animated: true)
        }, closeCallback: {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {[weak self] in
                self?.back()
            }
        }).show()
        
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo((navigationController?.navigationBar.height ?? 0))
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.layer.cornerRadius = SCRYFrom(15)
        tableView.rowHeight = SCRYFrom(31)
        tableView.backgroundColor = .white
        tableView.contentInset = UIEdgeInsets(top: SCRYFrom(9), left: 0, bottom: SCRYFrom(13), right: 0)
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        tableView.isScrollEnabled = false
        contentView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(7))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(CGFloat(self.options.count) * tableView.rowHeight + tableView.contentInset.top + tableView.contentInset.bottom)
        }
        
        // 是否接收site的owner权限
        let isReceivingSite = selectionTypes.contains(where: { $0.permission == .owner })
        
        var lastPermissionView: SharePermissionSelectionView?
        for index in 0..<selectionTypes.count {
            let type = selectionTypes[index]
            let permissionView = SharePermissionSelectionView(frame: .zero, require: type.requirePwd, permission: type.permission)
            permissionView.doneCallback = {[weak self] password in
                self?.applyPermission(type.permission, password: password)
//                self?.showImportResult()
            }
            permissionView.keyboardEditChangeCallback = {[weak self] (textField, isShow) in
                if isShow {
                    self?.activeField = textField
                }else {
                    self?.activeField = nil
                }
            }
            contentView.addSubview(permissionView)
            permissionView.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.height.equalTo(type.requirePwd ? SCRYFrom(264) : SCRYFrom(220))
                if let view = lastPermissionView {
                    make.top.equalTo(view.snp.bottom).offset(SCRYFrom(16))
                }else {
                    make.top.equalTo(tableView.snp.bottom).offset(SCRYFrom(16))
                }
                if !isReceivingSite && index == selectionTypes.count - 1 {
                    make.bottom.equalTo(SCRYFrom(-16))
                }
                lastPermissionView = permissionView
            }
        }
        
        if isReceivingSite {
            ownerMessageLabel = UILabel(text: "site_receiving_message".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light, fit: false)
            ownerMessageLabel?.textAlignment = .center
            ownerMessageLabel?.numberOfLines = 2
            contentView.addSubview(ownerMessageLabel!)
            ownerMessageLabel!.snp.makeConstraints { make in
                make.top.equalTo((lastPermissionView ?? tableView).snp.bottom).offset(SCRYFrom(40))
                make.left.equalTo(SCRXFrom(40))
                make.right.equalTo(SCRXFrom(-40))
                make.bottom.equalTo(SCRYFrom(-16))
            }
        }
        
    }

}

extension SharePermissionSelectionController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let option = options[indexPath.row]
        cell.titleLabel.text = option.data.title
        cell.contentLabel.text = option.data.content
        if case .spaces = option {
            cell.cellStyle = .arrow
        }else {
            cell.cellStyle = .none
        }
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.contentLabel.textColor = Message_Color
        cell.lineView.isHidden = true
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let option = options[indexPath.row]
        if case .spaces = option {
            if case .spaceList(let data, _, _) = self.type {
                let vc = ShareSpaceListViewController(spaces: data.spaces)
                navigationController?.pushViewController(vc, animated: true)
            }
        }
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }

}

extension SharePermissionSelectionController {
    
    /// 接收数据类型
    enum ReceivingType {
        
        var data: (shareId: String, options: [Options], selectTypes: [PermissionSelection]) {
            
            switch self {
            case .site(let site, let owner, let shareId):
                return (shareId, [.title(site.name), .invitationCode(code: shareId), .owner(name: owner.name)],
                        [.init(permission: .owner, requirePwd: true)])
            case .space(let siteName, let space, let shareId, let sharePermission):
                
                var permissionTypes: [PermissionSelection] = [.init(permission: .visitor, requirePwd: space.vistorPasswordEnable)]
                if sharePermission == .owner {
                    permissionTypes.append(.init(permission: .editor, requirePwd: true))
                }
                return (shareId, [.title("\(siteName) > \(space.name)"), .invitationCode(code: shareId), .owner(name: space.owner?.name ?? ""), .editor(name: space.editor?.name)],
                        permissionTypes)
            case .spaceList(let data, let shareId, let sharePermission):
                let ownerName = data.spaces.first(where: { $0.owner != nil })?.owner?.name
                
                var permissionTypes: [PermissionSelection] = [.init(permission: .visitor, requirePwd: false)]
                if sharePermission == .owner {
                    permissionTypes.append(.init(permission: .editor, requirePwd: true))
                }
                var options: [Options] = [.title(data.name), .invitationCode(code: shareId), .owner(name: ownerName ?? ""), .spaces]
                // editor分享时显示editor名称
                if sharePermission == .editor, let name = data.spaces.first(where: { $0.editor != nil })?.editor?.name {
                    options.insert(.editor(name: name), at: 3)
                }
                return (shareId, options, permissionTypes)
            }
        }
        
        /// 接收项目
        case site(site: SiteData, owner: UserData, shareId: String)
        /// 接收space
        case space(siteName: String, space: SpaceData, shareId: String, sharePermission: Permission)
        /// 接收space list
        case spaceList(data: BatchSpaceData, shareId: String, sharePermission: Permission)
        
        init?(shareData: [String: Any], sharePermission: Permission? = nil) {
            
            let data = JSON(shareData)
            guard let shareId = data["token"].string,
                  let type = data["type"].string else {
                return nil
            }
            
            switch type {
            case "single":
                
                guard let siteId = data["siteId"].string,
                      let spaceDict = data["space"].dictionaryObject,
                      let spaceId = JSON(spaceDict)["spaceId"].string,
                      let owner = data["owner"].dictionaryObject else { return nil }
                
                let spaceJson = JSON(spaceDict)
                
                let space = SpaceData(name: spaceJson["spaceName"].stringValue, id: spaceId, siteId: siteId, imageId: spaceJson["imageId"].intValue, create: 0, isFavourite: false, permission: .visitor, sourceType: .share, meshUUID: siteId, meshNetworkId: "")
                if let userId = owner["userId"] as? String, let userName = owner["username"] as? String {
                    space.owner = .init(name: userName, uuid: userId)
                }
                if let userId = spaceJson["editor"]["userId"].string, let userName = spaceJson["editor"]["username"].string {
                    space.editor = .init(name: userName, uuid: userId)
                }
                if let visitorPasswordEnable = spaceJson["visitProtected"].bool {
                    space.vistorPasswordEnable = visitorPasswordEnable
                }
                // 分享人权限
                var shareRole: Permission = .owner
                if sharePermission != nil {
                    shareRole = sharePermission!
                }else if let roleString = data["sharerRole"].string, let permission = Permission(permissionString: roleString) {
                    shareRole = permission
                }
                self = .space(siteName: data["site"]["siteName"].stringValue, space: space, shareId: shareId, sharePermission: shareRole)
            case "batch":
                
                guard let siteId = data["siteId"].string,
                      let batchName = data["batchName"].string,
                      let spaceDicts = data["spaces"].arrayObject as? [[String: Any]] else { return nil }
                
                let spaces: [SpaceData] = spaceDicts.compactMap({ spaceDict in
                    let spaceData = JSON(spaceDict)
                    guard let spaceId = spaceData["spaceId"].string,
                          let spaceName = spaceData["spaceName"].string else {
                        return nil
                    }
                    
                    let deviceCount = spaceData["nodeCount"].intValue
                    let imageId = spaceData["imageId"].int ?? 1
                    let space = SpaceData(name: spaceName, id: spaceId, siteId: siteId, imageId: imageId, create: 0, isFavourite: false, permission: .visitor, sourceType: .share, meshUUID: siteId, meshNetworkId: spaceId)
                    space.deviceCount = deviceCount
                    if let userId = spaceData["owner"]["userId"].string, let username = spaceData["owner"]["username"].string {
                        space.owner = .init(name: username, uuid: userId)
                    }
                    if let userId = spaceData["editor"]["userId"].string, let username = spaceData["editor"]["username"].string {
                        space.editor = .init(name: username, uuid: userId)
                    }
                    space.vistorPasswordEnable = spaceData["visitProtected"].boolValue
                    return space
                })
                
                // 分享人权限
                var sharePermission: Permission = .owner
                if let roleString = data["sharerRole"].string, let permission = Permission(permissionString: roleString) {
                    sharePermission = permission
                }
                
                self = .spaceList(data: BatchSpaceData(siteId: siteId, code: shareId, name: batchName, spaces: spaces, editorPassword: ""), shareId: shareId, sharePermission: sharePermission)
            case "ownertrans":
                guard let siteId = data["siteId"].string, 
                        let siteName = data["siteName"].string,
                      let userId = data["owner"]["userId"].string,
                      let username = data["owner"]["username"].string else { return nil }
                let site = SiteData(id: siteId, meshUUID: siteId, name: siteName, type: .office, permission: userId == UserData.currentUserId ? .owner : .visitor, create: 0, isFavourite: false, sourceType: .share)
                self = .site(site: site, owner: UserData(name: username, uuid: userId), shareId: shareId)
            default:
                return nil
            }
            
        }
        
    }
    
    enum Options {
        
        /// 数据 title：标题  content：内容
        var data: (title: String, content: String?) {
            switch self {
            case .title(let title):
                return (title, nil)
            case .invitationCode(let code):
                return ("invitation_code".localizedString + ":", code)
            case .owner(let name):
                return ("owner".localizedString + ":", name)
            case .editor(let name):
                return ("editor".localizedString + ":", name ?? "no_editor_yet".localizedString)
            case .spaces:
                return ("space_list".localizedString, nil)
            }
        }

        /// 标题
        case title(_ title: String)
        /// 分享code
        case invitationCode(code: String)
        /// 所有者
        case owner(name: String)
        /// 管理者
        case editor(name: String?)
        /// 空间list（批量分享）
        case spaces //(data: BatchSpaceData)
    }
    
    /// 授权类型选择
    struct PermissionSelection {
        /// 授权类型
        let permission: Permission
        /// 必须密码
        let requirePwd: Bool
    }
    
}


class SharePermissionSelectionView: UIView {
    
    var permissionLabel: UILabel!
    var permissionImageView: UIImageView!
    var permissionInfoLabel: UILabel!
    var passwordField: UITextField!
    var okBtn: UIButton!
    /// 完成回调  password
    var doneCallback: ((String?)->Void)?
    
    var keyboardEditChangeCallback: ((UITextField, Bool)->Void)?
    
    /// 是否必须输入密码
    let require: Bool
    /// 权限
    let permission: Permission
    
    init(frame: CGRect, require: Bool, permission: Permission) {
        self.permission = permission
        self.require = require
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(15)
        setupUI()
        if require {
            passwordField.isHidden = false
        }else {
            passwordField.isHidden = true
        }
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func hideKeyboard() {
        UIApplication.shared.keyWindow().endEditing(true)
//        self.endEditing(true)
    }
    
    
    @objc private func okBtnAction() {
        
        hideKeyboard()
        
        if !require { // 无密码
            doneCallback?(nil)
            return
        }
        
        guard let password = passwordField.text, password.count == 4 else {
            XWHUDManager.showTipHUD("share_password_invalid_message".localizedString, isLineFeed: true)
            return
        }
        
        doneCallback?(password)
    }
    
    private func setupUI() {
        
        permissionLabel = UILabel(text: permission.data.title, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        addSubview(permissionLabel)
        permissionLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        permissionImageView = UIImageView(image: UIImage(named: permission.data.icon))
        addSubview(permissionImageView)
        permissionImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(permissionLabel.snp.bottom).offset(SCRYFrom(14))
            make.width.height.equalTo(SCRYFrom(60))
        }
        
        permissionInfoLabel = UILabel(text: permission.data.details, textColor: Message_Color, fontSize: 14, fontWeight: .light)
        permissionInfoLabel.textAlignment = .center
        addSubview(permissionInfoLabel)
        permissionInfoLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(permissionImageView.snp.bottom).offset(SCRYFrom(12))
        }
        
        passwordField = UITextField()
        passwordField.placeholder = "password".localizedString
        passwordField.textColor = TextBlack_Color
        passwordField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        passwordField.layer.cornerRadius = SCRYFrom(8)
        passwordField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        passwordField.layer.borderWidth = 0.6
        passwordField.returnKeyType = .done
        passwordField.keyboardType = .numberPad
        passwordField.textAlignment = .center
        passwordField.delegate = self
//        passwordField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        addSubview(passwordField)
        passwordField.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(160))
            make.height.equalTo(SCRYFrom(30))
            make.top.equalTo(permissionInfoLabel.snp.bottom).offset(SCRYFrom(26))
        }
        
        okBtn = UIButton(title: "ok".localizedString, titleSize: 15, titleWeight: .light, titleColor: .white, target: self, action: #selector(okBtnAction))
        okBtn.backgroundColor = Bar_Color
        okBtn.layer.cornerRadius = SCRYFrom(8)
        addSubview(okBtn)
        okBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-20))
            make.height.equalTo(SCRYFrom(32))
            make.width.equalTo(SCRXFrom(160))
        }
        
        
        
    }
    
}

internal extension Permission {
   
    var data: (title: String, icon: String, details: String) {
        switch self {
        case .owner:
            return ("\("As a".localizedString) \("owner".localizedString)", "permission_owner", "owner_permission_message".localizedString)
        case .editor:
            return ("\("As a".localizedString) \("editor".localizedString)", "permission_editor", "editor_permission_message".localizedString)
        case .visitor:
            return ("\("As a".localizedString) \("visitor".localizedString)", "permission_visitor", "visitor_permission_message".localizedString)
        }
    }
    
}
extension SharePermissionSelectionView: UITextFieldDelegate {
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        textField.placeholder = nil
        keyboardEditChangeCallback?(textField, true)
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        textField.placeholder = "password".localizedString
        keyboardEditChangeCallback?(textField, false)
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endEditing(true)
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        // 密码需位数字
        guard string.isPureNumandCharacters() || string.isEmpty else {
            return false
        }
        // 输入长度限制
        let realText = (textField.text ?? "") + string
        if realText.count > 4 {
            return false
        }
        return true
    }
    
}
