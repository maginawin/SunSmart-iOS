//
//  ShareChangePasswordController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/29.
//

import UIKit

class ShareChangePasswordController: UIViewController {

    /// 操作类型
    enum OperationType {
        /// 转移site密码
        case transferPassword(site: SiteData)
        /// space密码
        case spacePassword(space: SpaceData)
        /// batch space密码
        case batchSpacePassword(data: BatchSpaceData)
    }
    
    private var scrollView: UIScrollView!
    private var contentView: UIView!
    
    private var editorPassword: ShareChangePasswordView!
    private var visitorPassword: ShareChangePasswordView!
    /// 正在输入的密码框
    private var activeField: UITextField?
    
    /// 设置密码回调 permission: owner-转让site  editor：修改编辑者密码  visitor：修改访客密码
    var passwordSetCallback: ((Permission, String?)->Void)?
    
    
    let type: OperationType
    
    init(type: OperationType) {
        self.type = type
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "change_password".localizedString
        view.backgroundColor = Background_Color
                
        setupUI()
        
        addKeyboardNotification()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        if self.scrollView.firstShowFlashScrollIndicators {
            self.scrollView.flashScrollIndicatorsIfNeeded()
        }
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
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
    
    /// 修改转移site密码
    private func changeSiteTransferPasswordRequest(_ password: String) {
        
        guard case .transferPassword(let site) = type else {
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.transferSite(siteId: site.id, password: password)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + " !")
                self.passwordSetCallback?(.owner, password)
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 修改编辑者密码
    private func changeEditorPasswordRequest(_ password: String) {
        
        guard case .spacePassword(let space) = type else {
            return
        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.spacePasswordSet(siteId: space.siteId, spacePassword: .init(spaceId: space.id, password: password, permission: .editor))) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
                self.passwordSetCallback?(.editor, password)
            case .failure(let error):
                if error == .editorBeingUsedSpace { // space正在被editor使用
                    SRAlertView(title: "notification".localizedString, message: "editor_password_change_failed".localizedString, actions: [SRAlertAction(title: "confirm".localizedString)]).show()
                }else {
                    XWHUDManager.showErrorTipHUD(error.localizedDescription)
                }
            }
        }
    }
    
    /// 修改访客密码  password：有值则设置密码，没值则不需要密码
    private func changeVistorPasswordRequest(_ password: String?) {
        
        guard case .spacePassword(let space) = type else {
            return
        }
        
        let api: NetowrkReqeustApi = .spacePasswordSet(siteId: space.siteId, spacePassword: .init(spaceId: space.id, password: password, permission: .visitor))
//        if password != nil {
//            api = .spacePasswordSet(siteId: space.siteId, spacePassword: .init(spaceId: space.id, password: password, permission: .visitor))
//        }else {
//            api = .spacePasswordClear(siteId: space.siteId, spaceId: space.id, permission: .visitor)
//        }
        
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(api) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                self.passwordSetCallback?(.visitor, password)
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
    }
    
    /// 修改批量分享space密码
    private func changeBatchSpacePasswordReqeuest(_ password: String) {
        
        guard case .batchSpacePassword(let data) = type else {
            return
        }
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.batchSpacesPasswordSet(batchId: data.code, password: password)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            switch result {
            case .success(_):
                self.passwordSetCallback?(.visitor, password)
                XWHUDManager.showSuccessTipHUD("successfully".localizedString + "!")
            case .failure(let error):
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
        
    }
    
    @objc private func hideKeyboard() {
        view.endEditing(true)
    }
    
    private func setupUI() {
        
        scrollView = UIScrollView()
//        scrollView.showsVerticalScrollIndicator = false
        scrollView.alwaysBounceVertical = true
        scrollView.delegate = self
        scrollView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo((view.safeAreaLayoutGuide))
        }
        
        contentView = UIView()
        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.width.equalToSuperview()
        }
        
        switch type {
        case .transferPassword(let site):
            
            editorPassword = ShareChangePasswordView(frame: .zero, require: true)
            editorPassword.titleLabel.text = "transfer_password".localizedString
            editorPassword.password = site.transferPassword
            editorPassword.keyboardEditChangeCallback = {[weak self] (textField, isShow) in
                if isShow {
                    self?.activeField = textField
                }else {
                    self?.activeField = nil
                }
            }
            editorPassword.confirmPasswordCallback = {[weak self] password in
                guard let transferPassword = password else { return }
                self?.changeSiteTransferPasswordRequest(transferPassword)
            }
            contentView.addSubview(editorPassword)
            editorPassword.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
//                make.top.equalTo((view.safeAreaLayoutGuide) + SCRYFrom(7))
                make.top.equalTo(SCRYFrom(7))
                make.height.equalTo(SCRYFrom(226))
                make.bottom.equalToSuperview()
            }
        case .batchSpacePassword(let data):
            
            editorPassword = ShareChangePasswordView(frame: .zero, require: true)
            editorPassword.titleLabel.text = "editor_password".localizedString
            editorPassword.password = data.editorPassword
            editorPassword.keyboardEditChangeCallback = {[weak self] (textField, isShow) in
                if isShow {
                    self?.activeField = textField
                }else {
                    self?.activeField = nil
                }
            }
            editorPassword.confirmPasswordCallback = {[weak self] password in
                guard let editorPassword = password else { return }
                self?.changeBatchSpacePasswordReqeuest(editorPassword)
            }
            contentView.addSubview(editorPassword)
            editorPassword.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(SCRYFrom(7))
                make.height.equalTo(SCRYFrom(226))
                make.bottom.equalToSuperview()
            }
            
        case .spacePassword(let space):
            if space.permission == .owner {
                editorPassword = ShareChangePasswordView(frame: .zero, require: true)
                editorPassword.titleLabel.text = "editor_password".localizedString
                editorPassword.password = space.editorPassword
                editorPassword.keyboardEditChangeCallback = {[weak self] (textField, isShow) in
                    if isShow {
                        self?.activeField = textField
                    }else {
                        self?.activeField = nil
                    }
                }
                editorPassword.confirmPasswordCallback = {[weak self] password in
                    guard let editorPassword = password else { return }
                    self?.changeEditorPasswordRequest(editorPassword)
                }
                contentView.addSubview(editorPassword)
                editorPassword.snp.makeConstraints { make in
                    make.left.equalTo(SCRXFrom(16))
                    make.right.equalTo(SCRXFrom(-16))
                    make.top.equalTo(SCRYFrom(7))
                    make.height.equalTo(SCRYFrom(226))
                }
            }
            
            visitorPassword = ShareChangePasswordView(frame: .zero, require: false)
            visitorPassword.titleLabel.text = "visitors_password".localizedString
            visitorPassword.password = space.vistorPassword?.count ?? 0 > 0 ? space.vistorPassword : nil
            visitorPassword.keyboardEditChangeCallback = {[weak self] (textField, isShow) in
                if isShow {
                    self?.activeField = textField
                }else {
                    self?.activeField = nil
                }
            }
            visitorPassword.confirmPasswordCallback = {[weak self] password in
                self?.changeVistorPasswordRequest(password)
            }
            contentView.addSubview(visitorPassword)
            visitorPassword.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                if space.permission == .owner {
                    make.top.equalTo(editorPassword.snp.bottom).offset(SCRYFrom(16))
                }else {
                    make.top.equalTo(SCRYFrom(7))
                }
                make.height.equalTo(SCRYFrom(308))
                make.bottom.equalToSuperview()
            }
        }
    
    }
    

}

extension ShareChangePasswordController: UIScrollViewDelegate {
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        view.endEditing(true)
    }

}



class ShareChangePasswordView: UIView {
    
    var titleLabel: UILabel!
    var passwordField: UITextField!
    var randomBtn: UIButton!
    var segmentedControl: CustomSegmentedControl!
    var notPasswordLabel: UILabel!
    var okBtn: UIButton!
    
    var password: String? {
        didSet {
            passwordField.text = password
            
            if !require {
                if password != nil {
                    self.segmentedControl.selectedIndex = 1
                }else {
                    self.segmentedControl.selectedIndex = 0
                }
                updateSegmentedUI()
            }
        }
    }
    
    /// 开始输入编辑回调
    var keyboardEditChangeCallback: ((UITextField, Bool)->Void)?
    
    /// 确认密码回调
    var confirmPasswordCallback: ((String?)->Void)?
    
    private var require: Bool = true
    
    init(frame: CGRect, require: Bool = true) {
        super.init(frame: frame)
        self.require = require
        
        layer.cornerRadius = SCRYFrom(15)
        backgroundColor = .white
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        
        setupUI()
        if require {
            segmentedControl.isHidden = true
            notPasswordLabel.isHidden = true
        }else {
            updateSegmentedUI()
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func hideKeyboard() {
        UIApplication.shared.keyWindow().endEditing(true)
    }
    
    @objc private func randomBtnAction() {
        passwordField.text = String.generateRandomNumberString()
    }
    
    @objc private func okBtnAction() {
        
        hideKeyboard()
        
        if !require && segmentedControl.selectedIndex == 0 { // 无密码
            confirmPasswordCallback?(nil)
            return
        }
        
        guard let password = passwordField.text, password.count == 4 else {
            XWHUDManager.showTipHUD("share_password_invalid_message".localizedString, isLineFeed: true)
            return
        }
        
        confirmPasswordCallback?(password)
    }
    
    private func updateSegmentedUI() {
        
        if segmentedControl.selectedIndex == 0 {
            notPasswordLabel.isHidden = false
            passwordField.isHidden = true
            randomBtn.isHidden = true
        }else {
            notPasswordLabel.isHidden = true
            passwordField.isHidden = false
            randomBtn.isHidden = false
        }
        
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
        }
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: ["no_password".localizedString, "password_protection".localizedString])
        segmentedControl.backgroundColor = Background_Color
        segmentedControl.selectBgColor = .white
        segmentedControl.selectTitleColor = Bar_Color
        segmentedControl.selectBorderColor = Bar_Color
        segmentedControl.titleFont = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        segmentedControl.margin = 1
        segmentedControl.selectBorderWidth = 0.5
        segmentedControl.showShadow = false
        segmentedControl.delegate = self
        addSubview(segmentedControl)
        //        CGRect(x: SCRXFrom(16), y: SCRYFrom(16) + kNavigationHeight, width: view.width - SCRXFrom(32), height: SCRYFrom(44))
        segmentedControl.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(24))
            make.left.equalTo(SCRXFrom(24))
            make.right.equalTo(SCRXFrom(-24))
            make.height.equalTo(SCRYFrom(36))
        }
        
        passwordField = UITextField()
        passwordField.placeholder = "new_password".localizedString
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
            make.left.equalTo(SCRXFrom(24))
            make.right.equalTo(SCRXFrom(-128))
            make.height.equalTo(SCRYFrom(32))
            if require {
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(34))
            }else {
                make.top.equalTo(segmentedControl.snp.bottom).offset(SCRYFrom(34))
            }
        }
        
        randomBtn = UIButton(title: "random".localizedString, titleSize: 15, titleWeight: .light, titleColor: RGB(46, 49, 93), target: self, action: #selector(randomBtnAction))
        randomBtn.backgroundColor = Background_Color
        randomBtn.layer.cornerRadius = SCRYFrom(8)
        addSubview(randomBtn)
        randomBtn.snp.makeConstraints { make in
            make.left.equalTo(passwordField.snp.right).offset(SCRXFrom(8))
            make.width.equalTo(SCRXFrom(96))
            make.height.equalTo(SCRYFrom(32))
            make.centerY.equalTo(passwordField)
        }
        
        notPasswordLabel = UILabel(text: "share_not_password_message".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light)
        notPasswordLabel.textAlignment = .center
        addSubview(notPasswordLabel)
        notPasswordLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(segmentedControl.snp.bottom).offset(SCRYFrom(32))
        }
        
        okBtn = UIButton(title: "ok".localizedString, titleSize: 15, titleWeight: .light, titleColor: .white, target: self, action: #selector(okBtnAction))
        okBtn.backgroundColor = Bar_Color
        okBtn.layer.cornerRadius = SCRYFrom(8)
        addSubview(okBtn)
        okBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-38))
            make.height.equalTo(SCRYFrom(32))
            make.width.equalTo(SCRXFrom(120))
        }
    }
    
}

extension ShareChangePasswordView: UITextFieldDelegate {
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        textField.placeholder = nil
        keyboardEditChangeCallback?(textField, true)
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        textField.placeholder = "new_password".localizedString
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

extension ShareChangePasswordView: CustomSegmentedControlDelegate {
    func segmentedControl(_ segmentedControl: CustomSegmentedControl, didSelectedItem index: Int) {
        updateSegmentedUI()
    }
}
