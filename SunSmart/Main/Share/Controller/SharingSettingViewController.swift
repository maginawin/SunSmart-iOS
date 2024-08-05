//
//  SharingSettingViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/28.
//

import UIKit
import Photos

class SharingSettingViewController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    /// 二维码view
    private var qrcodeView: UIView!
    private var qrcodeTitleLabel: UILabel!
    private var qrcodeImageView: UIImageView!
    private var uuidLabel: UILabel!
    /// 权限view
    private var permissionView: UIView?
    private var ownerLabel: UILabel?
    private var ownerNameLabel: UILabel?
    private var editorLabel: UILabel?
    private var editorNameLabel: UILabel?
    /// 功能view
    private var itemsView: UIView!
    private var tableView: UITableView!
    
    private var messageLabel: UILabel?
    /// 类型
    let type: SharingType
    /// 二维码uuid
    private let codeUUID: String
    /// 功能项
    private var options: [Options] = []
    /// 是否展示密码
    private var viewPassword: Bool = false
    /// editor密码
//    private var editorPassword: String?
//    /// visitor密码
//    private var vistorPassword: String?
    
    init(type: SharingType) {
        self.type = type
        self.codeUUID = type.data.uuid
        self.options = type.data.options
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        if case .transferSite = type {
            title = "transfer_site".localizedString
        }else {
            title = "sharing_settings".localizedString
        }
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        view.backgroundColor = Background_Color
        if navigationController?.viewControllers.count == 1 {
            navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(close))
        }
        
//        switch self.type {
//        case .transferSite(let site):
//            break
//        case .space(_, let space):
//            if space.permission == .owner {
//                editorPassword = space.editorPassword
//                vistorPassword = space.vistorPassword
//            }else if space.permission == .editor {
//                vistorPassword = space.vistorPassword
//            }
//        case .batchSpace(let data):
//            break
//        }
        setupUI()
    }
    
//    override func viewDidAppear(_ animated: Bool) {
//        super.viewDidAppear(animated)
//        // 生成二维码，耗时操作避免影响页面展示
//        if self.qrcodeImageView.image == nil {
//            XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
//            DispatchQueue.global().async {
//                var qrcodeColor: UIColor = .black
//                if case .transferSite = self.type {
//                    qrcodeColor = Bar_Color
//                }
//                let image = LBXScanWrapper.createCode(codeType: "CIQRCodeGenerator", codeString: self.codeUUID, size: CGSize(width: SCRYFrom(160), height: SCRYFrom(160)), qrColor: qrcodeColor, bkColor: .white)!
//                DispatchQueue.main.async {
//                    XWHUDManager.hide()
//                    self.qrcodeImageView.image = image
//                }
//            }
//        }
//    }
    
    @objc private func close() {
        dismiss(animated: true)
    }
    
    // MARK: -- Request
    
    /// 清除space editor
    private func clearSpaceEditorRequest(space: SpaceData) {
        
        guard let editor = space.editor else {
            return
        }
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.clearSpaceMember(siteId: space.siteId, spaceId: space.id, userId: editor.uuid, permission: .editor, force: false)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                space.editor = nil
                space.save()
                self.options = self.type.data.options
                self.tableView.reloadData()
                self.editorNameLabel?.text = "no_editor_yet".localizedString
                
            case .failure(let error):
                if error == .editorBeingUsedSpace { // 正在使用空间
                    SRAlertView(title: "notification".localizedString, message: "space_clear_editor_failed".localizedString, actions: [SRAlertAction(title: "confirm".localizedString)]).show()
                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
        }
    }
    
    
    
    // MARK: -- Options
    
    /// 保存二维码到相册
    private func qrCodeSaveToAlbum() {
        LBXPermissions.authorizePhotoWith {[weak self] authorized in
            guard let self = self else { return }
            guard authorized else {
                let alertVc = UIAlertController(title: "photos_requires_alert_title".localizedString, message: "photos_requires_alert_message".localizedString, preferredStyle: .alert)
                alertVc.addAction(UIAlertAction(title: "alert_item_cancel".localizedString, style: .default))
                alertVc.addAction(UIAlertAction(title: "Settings".localizedString, style: .cancel, handler: { _ in
                    LBXPermissions.jumpToSystemPrivacySetting()
                }))
                self.present(alertVc, animated: true)
                return
            }
            
            guard let image = self.qrcodeView.snapshotImage() else {
                XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                return
            }
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
            XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
        }
    }

    /// 分享二维码
    private func shareQRCode() {
        
        guard let image = self.qrcodeView.snapshotImage() else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        
//        let item = CustomActivityItemSource(image: image, text: "This is the content to share.", title: "Custom Title")
        
        let vc = UIActivityViewController(activityItems: [image], applicationActivities: nil)
        vc.completionWithItemsHandler = { (type, completion, _, error) in
            if completion {
                if error == nil {
                    XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                }else {
                    XWHUDManager.showSuccessTipHUD("failed".localizedString)
                }
                vc.dismiss(animated: true)
            }
        }
        present(vc, animated: true)
    }
    
    /// 修改密码
    private func changePassword() {
        
        var operationType: ShareChangePasswordController.OperationType!
        
        switch type {
        case .transferSite(let site):
            operationType = .transferPassword(site: site)
        case .space(let site, let space):
            operationType = .spacePassword(space: space)
        case .batchSpace(let data):
//            operationType = .spacePassword(space: )
            operationType = .batchSpacePassword(data: data)
        }
        
        let vc = ShareChangePasswordController(type: operationType)
        vc.passwordSetCallback = {[weak self] (permisson, password) in
            guard let self = self else { return }
            switch self.type {
            case .transferSite(let site):
                site.transferPassword = password
                site.save()
            case .space(let site, let space):
                if permisson == .editor {
                    space.editorPassword = password
                }else if permisson == .visitor {
                    space.vistorPassword = password
                }
                space.save()
            case .batchSpace(let data):
                if password != nil {
                    data.editorPassword = password!
                }
            }
            if let index = self.options.firstIndex(of: .viewHidePassword) {
                self.tableView.reloadRows(at: [IndexPath(row: index, section: 0)], with: .none)
            }else {
                self.tableView.reloadData()
            }
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    /// 清空编辑者
    private func clearEditor(space: SpaceData) {
        SRAlertView(title: "notification".localizedString, message: "space_clear_editor_message".localizedString, actions: [.cancelAction, SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
            self?.clearSpaceEditorRequest(space: space)
        })]).show()
    }
    
    /// space list
    private func pushToSpaceList(spaces: [SpaceData]) {
        
        navigationController?.pushViewController(ShareSpaceListViewController(spaces: spaces), animated: true)
    }
    
    /// 查看访客list
    private func viewVisitorList(space: SpaceData) {
        
        let vc = SpaceVisitorListViewController(space: space)
        navigationController?.pushViewController(vc, animated: true)
    }
    
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(navigationController?.navigationBar.height ?? 0)
        }
        
        contentView = UIView()
        contentView.backgroundColor = Background_Color
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.width.edges.equalToSuperview()
            make.height.greaterThanOrEqualToSuperview()
        }
        
        qrcodeView = UIView()
        qrcodeView.layer.cornerRadius = SCRYFrom(15)
        qrcodeView.layer.masksToBounds = true
        qrcodeView.backgroundColor = .white
        contentView.addSubview(qrcodeView)
        qrcodeView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(7))
            make.height.equalTo(SCRYFrom(268))
        }
        
        qrcodeTitleLabel = UILabel(text: self.type.data.title, textColor: TextBlack_Color, fontSize: 15, fit: true)
        qrcodeView.addSubview(qrcodeTitleLabel)
        qrcodeTitleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(22))
        }
        
        let qrcodeW = SCRYFrom(160)
        let qrcodeH = SCRYFrom(160)
        
        var qrcodeColor: UIColor = .black
        if case .transferSite = self.type {
            qrcodeColor = Bar_Color
        }
        let image = LBXScanWrapper.createCode(codeType: "CIQRCodeGenerator", codeString: self.codeUUID, size: CGSize(width: SCRYFrom(160), height: SCRYFrom(160)), qrColor: qrcodeColor, bkColor: .white)!
//        DispatchQueue.global().async {
//            let image = LBXScanWrapper.createCode(codeType: "CIQRCodeGenerator", codeString: self.codeUUID, size: CGSize(width: qrcodeW, height: qrcodeH), qrColor: qrcodeColor, bkColor: .white)!
//            DispatchQueue.main.async {
//                self.qrcodeImageView.image = image
//            }
//        }
        qrcodeImageView = UIImageView(image: image)
        qrcodeView.addSubview(qrcodeImageView)
        qrcodeImageView.snp.makeConstraints { make in
            make.top.equalTo(qrcodeTitleLabel.snp.bottom).offset(SCRYFrom(12))
            make.centerX.equalToSuperview()
            make.width.equalTo(qrcodeW)
            make.height.equalTo(qrcodeH)
        }
        
        uuidLabel = UILabel(text: self.codeUUID, textColor: RGB(72, 72, 74), fontSize: 14, fontWeight: .light, fit: true)
        uuidLabel.textAlignment = .center
        qrcodeView.addSubview(uuidLabel)
        uuidLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(qrcodeImageView.snp.bottom).offset(SCRYFrom(12))
        }
        
        if case .space(_, let space) = type {
            permissionView = UIView()
            permissionView!.layer.cornerRadius = SCRYFrom(15)
            permissionView!.backgroundColor = .white
            contentView.addSubview(permissionView!)
            permissionView!.snp.makeConstraints { make in
                make.left.right.equalTo(qrcodeView)
                make.top.equalTo(qrcodeView.snp.bottom).offset(SCRYFrom(16))
                make.height.equalTo(SCRYFrom(52))
            }
            
            if space.permission == .owner {
                
                editorLabel = UILabel(text: "editor".localizedString + ":", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
                permissionView!.addSubview(editorLabel!)
                editorLabel!.snp.makeConstraints { make in
                    make.left.equalTo(SCRXFrom(20))
                    make.top.equalTo(SCRYFrom(16))
                }
                
                editorNameLabel = UILabel(text: space.editor?.name ?? "no_editor_yet".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
                permissionView!.addSubview(editorNameLabel!)
                editorNameLabel!.snp.makeConstraints { make in
                    make.centerY.equalTo(editorLabel!)
                    make.right.equalTo(SCRXFrom(-20))
                }
                
            }else if space.permission == .editor {
                
                ownerLabel = UILabel(text: "owner".localizedString + ":", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
                permissionView!.addSubview(ownerLabel!)
                ownerLabel!.snp.makeConstraints { make in
                    make.left.equalTo(SCRXFrom(20))
                    make.top.equalTo(SCRYFrom(16))
                }
                
                ownerNameLabel = UILabel(text: space.owner?.name ?? "no_owner_yet".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
                permissionView!.addSubview(ownerNameLabel!)
                ownerNameLabel!.snp.makeConstraints { make in
                    make.centerY.equalTo(ownerLabel!)
                    make.right.equalTo(SCRXFrom(-20))
                }
                
                editorLabel = UILabel(text: "editor".localizedString + ":", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
                permissionView!.addSubview(editorLabel!)
                editorLabel!.snp.makeConstraints { make in
                    make.left.equalTo(ownerLabel!)
                    make.top.equalTo(ownerLabel!.snp.bottom).offset(SCRYFrom(8))
                }
                
                editorNameLabel = UILabel(text: "you".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
                permissionView!.addSubview(editorNameLabel!)
                editorNameLabel!.snp.makeConstraints { make in
                    make.centerY.equalTo(editorLabel!)
                    make.right.equalTo(SCRXFrom(-20))
                }
                
                permissionView!.snp.updateConstraints { make in
                    make.height.equalTo(SCRYFrom(80))
                }
                
            }
          
        }
        
        itemsView = UIView()
        itemsView.layer.cornerRadius = SCRYFrom(15)
        itemsView.backgroundColor = .white
        contentView.addSubview(itemsView)
        itemsView.snp.makeConstraints { make in
            make.left.right.equalTo(qrcodeView)
            make.top.equalTo((permissionView ?? qrcodeView).snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-16)).priority(.low)
        }
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.dataSource = self
        tableView.delegate = self
        itemsView.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(20))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-20)).priority(.low)
            make.height.equalTo(CGFloat(self.options.count) * SCRYFrom(32))
        }
        
        if case .transferSite = type {
            messageLabel = UILabel(text: "site_transfer_message".localizedString, textColor: RGB(143, 168, 184), fontSize: 14, fontWeight: .light, fit: false)
            messageLabel?.numberOfLines = 0
            messageLabel?.textAlignment = .center
            contentView.addSubview(messageLabel!)
            messageLabel!.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(44))
                make.right.equalTo(SCRXFrom(-43))
                make.top.equalTo(tableView.snp.bottom).offset(SCRYFrom(36))
                make.bottom.equalTo(SCRYFrom(-20)).priority(.low)
            }
        }

    }

}

extension SharingSettingViewController: UITableViewDataSource, UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return options.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        let option = options[indexPath.row]
        cell.cellStyle = .icon
        cell.titleLabel.text = option.data.name
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.titleLabel.textColor = RGB(72, 72, 74)
        cell.iconImageView.image = UIImage(named: option.data.icon)
        cell.iconX = 0
        cell.titleX = SCRXFrom(38)
        if option == .viewHidePassword, viewPassword {
            cell.cellStyle = .iconAddBottomSubtitle
            cell.iconY = SCRYFrom(3)
            cell.titleLabel.text = "hide_password".localizedString
            var content = ""
            switch self.type {
            case .space(_, let space):
                if space.permission == .owner {
                    content = "\("editor".localizedString): \(space.editorPassword ?? "no_password".localizedString)    \("visitor".localizedString): \(space.vistorPassword ?? "no_password".localizedString)"
                }else if space.permission == .editor {
                    content = "\("visitor".localizedString): \(space.vistorPassword ?? "no_password".localizedString)"
                }
            case .transferSite(let site):
                content = "\("transfer_password".localizedString): \(site.transferPassword ?? "")"
            case .batchSpace(let data):
                content = "\("editor".localizedString): \(data.editorPassword)"
            }
            
            cell.contentLabel.text = content
            cell.contentLabel.textColor = RGB(148, 163, 184)
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        }else {
            cell.contentLabel.text = nil
        }
        cell.arrowImageView.isHidden = true
        cell.lineView.isHidden = true
        cell.selectionStyle = .none
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let option = options[indexPath.row]
        if option == .viewHidePassword && viewPassword {
            return SCRYFrom(49)
        }
        return SCRYFrom(32)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let option = options[indexPath.row]
        switch option {
           
        case .copyUUID:  /// 复制uuid
            UIPasteboard.general.string = self.codeUUID
            XWHUDManager.showTipHUD("copy_success".localizedString, isLineFeed: false)
        case .saveQRCode: /// 保存二维码到相册
            qrCodeSaveToAlbum()
        case .shareQRCode: /// 分享二维码
            shareQRCode()
        case .spaces: /// 批量打包的space list
            if case .batchSpace(let data) = type {
                pushToSpaceList(spaces: data.spaces)
            }
        case .clearEditor: /// 清除管理员
            if case .space(_, let space) = type {
                clearEditor(space: space)
            }
        case .visitors: /// 访客list
            if case .space(_, let space) = type {
                viewVisitorList(space: space)
            }
        case .changePassword: /// 修改密码
            changePassword()
        case .viewHidePassword: /// 展示/隐藏密码
            viewPassword = !viewPassword
            tableView.reloadRows(at: [indexPath], with: .none)
            tableView.snp.updateConstraints { make in
                var height = CGFloat(self.options.count) * SCRYFrom(32)
                if viewPassword {
                    height += SCRYFrom(17)
                }
                make.height.equalTo(height)
            }
        }
    }
    
}


extension SharingSettingViewController {
   
    /// 分享数据类型
    enum SharingType {
        /// title：二维码标题  uuid：二维码id  options：功能项
        var data: (title: String, uuid: String, options: [Options]) {
            switch self {
            case .transferSite(let site):
                return (site.name, site.transferCode ?? "", [.copyUUID, .saveQRCode, .shareQRCode, .changePassword, .viewHidePassword])
            case .space(let site, let space):
                var options: [Options] = [.copyUUID, .saveQRCode, .shareQRCode, .visitors, .changePassword, .viewHidePassword]
                if space.spaceOperates.contains(.editorOperate) && space.editor != nil {
                    options.insert(.clearEditor, at: 3)
                }
                return ("\(site.name) > \(space.name)", space.shareCode ?? "", options)
            case .batchSpace(let data):
                var options: [Options] = [.copyUUID, .saveQRCode, .shareQRCode, .spaces]
                if data.spaces.contains(where: { $0.permission == .owner }) {
                    options.append(contentsOf: [.changePassword, .viewHidePassword])
                }
                return (data.name, data.code, options)
            }
        }
        
        /// 转移site
        case transferSite(site: SiteData)
        /// 分享space
        case space(site: SiteData, space: SpaceData)
        /// 批量分享space
        case batchSpace(data: BatchSpaceData)
    }

    enum Options {
        
        var data: (icon: String, name: String) {
            switch self {
            case .copyUUID:
                return ("share_copy", "copy_invitation_code".localizedString)
            case .saveQRCode:
                return ("share_save", "save_qrcode_to_album".localizedString)
            case .shareQRCode:
                return ("share", "share_qrcode".localizedString)
            case .spaces:
                return ("share_spaces", "space_list".localizedString)
            case .clearEditor:
                return ("share_clear_editor", "clear_editor".localizedString)
            case .visitors:
                return ("share_visitors", "visitor_list".localizedString)
            case .changePassword:
                return ("share_change_password", "change_password".localizedString)
            case .viewHidePassword:
                return ("share_viewhide_password", "view_password".localizedString)
            }
        }
        
        /// 复制uuid
        case copyUUID
        /// 保存二维码到相册
        case saveQRCode
        /// 分享二维码
        case shareQRCode
        /// 批量打包的space list
        case spaces
        /// 清除管理员
        case clearEditor
        /// 访客list
        case visitors
        /// 修改密码
        case changePassword
        /// 展示/隐藏密码
        case viewHidePassword
    }
    
}
