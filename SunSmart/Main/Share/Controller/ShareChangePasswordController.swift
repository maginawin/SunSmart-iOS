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
        case transferPassword
        /// space密码
        case spacePassword
    }
    
    private var editorPassword: ShareChangePasswordView!
    private var visitorPassword: ShareChangePasswordView!
    
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
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }
    
    private func setupUI() {
        
        editorPassword = ShareChangePasswordView(frame: .zero, require: true)
        editorPassword.titleLabel.text = "transfer_password".localizedString
        editorPassword.confirmPasswordCallback = { password in
            print(password)
        }
        view.addSubview(editorPassword)
        editorPassword.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo((navigationController?.navigationBar.height ?? 0) + SCRYFrom(7))
            make.height.equalTo(SCRYFrom(226))
        }
        
        if type == .spacePassword {
            editorPassword.titleLabel.text = "editor_password".localizedString
            
            visitorPassword = ShareChangePasswordView(frame: .zero, require: true)
            visitorPassword.titleLabel.text = "visitor_password".localizedString
            visitorPassword.confirmPasswordCallback = { password in
                print(password)
            }
            view.addSubview(visitorPassword)
            visitorPassword.snp.makeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(editorPassword.snp.bottom).offset(SCRYFrom(16))
                make.height.equalTo(SCRYFrom(308))
            }
        }
        
    }
    

}



class ShareChangePasswordView: UIView {
    
    var titleLabel: UILabel!
    var passwordField: UITextField!
    var randomBtn: UIButton!
    var segmentedControl: CustomSegmentedControl!
    var notPasswordLabel: UILabel!
    var okBtn: UIButton!
    
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
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func hideKeyboard() {
        self.endEditing(true)
    }
    
    @objc private func randomBtnAction() {
        
        let randomNumber = arc4random_uniform(10000)
        passwordField.text = String(format: "%04d", randomNumber)
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
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
        }
        
        segmentedControl = CustomSegmentedControl(frame: .zero, titles: ["no_password".localizedString, "password_protection".localizedString])
        segmentedControl.margin = 0
        segmentedControl.selectBgColor = .white
        segmentedControl.selectTitleColor = Bar_Color
        segmentedControl.selectBorderColor = Bar_Color
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
        passwordField.layer.borderWidth = 0.5
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
        return true
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        textField.placeholder = "new_password".localizedString
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
        
        if index == 0 {
            notPasswordLabel.isHidden = false
            passwordField.isHidden = true
            randomBtn.isHidden = true
        }else {
            notPasswordLabel.isHidden = true
            passwordField.isHidden = false
            randomBtn.isHidden = false
        }
    }
}
