//
//  SharePermissionSelectionController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/29.
//

import UIKit

class SharePermissionSelectionController: UIViewController {

    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var tableView: UITableView!
    private var ownerMessageLabel: UILabel?

    private var options: [Options] = []
    private var selectionTypes: [PermissionSelection] = []
    /// 展示导入结果弹窗
    private var showResultAlert: Bool = false
    
    override func viewDidLoad() {
        super.viewDidLoad()

//        title = "receiving_site".localizedString
        title = "permission_selection".localizedString
        view.backgroundColor = Background_Color
        navigationController?.setNavigationBarBackgroundColor(color: .clear)
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(back))
        
        options = [.title("Batch 53487"), .invitationCode(code: "xxxxxxxx"), .owner(name: "Jesse's iphone 13"), .spaces]
//        selectionTypes = [.init(permission: .owner, requirePwd: true)]
        selectionTypes = [.init(permission: .visitor, requirePwd: false), .init(permission: .editor, requirePwd: true)]
        
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if showResultAlert {
            showResultAlert = false
            showImportResult()
        }
    }
    
    @objc private func back() {
        dismiss(animated: true)
    }
    
    private func showImportResult() {
        
        BatchImportResultView(helpCallback: {[weak self] in
            self?.showResultAlert = true
            
            let vc = BatchImportResultHelpController()
            self?.navigationController?.pushViewController(vc, animated: true)
        }, closeCallback: {[weak self] in
            self?.back()
        }).show()
        
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
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
                print(password)
                self?.showImportResult()
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
    
}

extension SharePermissionSelectionController {
    
    /// 接收数据类型
    enum ReceivingType {
        
        var data: (options: [Options], selectTypes: [PermissionSelection]) {
            
            switch self {
            case .site(let site):
                return ([.title(site.name), .invitationCode(code: site.id), .owner(name: "Jesse's iphone 13")],
                        [.init(permission: .owner, requirePwd: true)])
            case .space(let site, let space):
                return ([.title(site.name), .invitationCode(code: site.id), .owner(name: "Jesse's iphone 13"), .editor(name: nil)],
                        [.init(permission: .owner, requirePwd: true)])
            case .spaceList:
                return ([],
                        [.init(permission: .owner, requirePwd: true)])
            }
        }
        
        /// 接收项目
        case site(site: SiteData)
        /// 接收space
        case space(site: SiteData, space: SpaceData)
        /// 接收space list
        case spaceList(data: BatchSpaceData)
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
        self.endEditing(true)
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
        passwordField.layer.borderWidth = 0.5
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
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        textField.placeholder = "password".localizedString
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
