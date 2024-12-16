//
//  ProfileSettingsHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

protocol ProfileSettingsHeaderViewDelegate: AnyObject {
    
    /// 名称编辑回调
    /// - Parameters:
    ///   - view: view
    ///   - name: 名称
    /// - Returns: 返回错误提示（可选）
    func view(_ view: ProfileSettingsHeaderView, nameEditChanged name: String) -> String?
    
    /// 选择配置文件回调
    func headerViewDidSelectProfile(_ view: ProfileSettingsHeaderView, profileRect: CGRect)
    
    /// 点击帮助回调
    func headerViewHelpAction(_ view: ProfileSettingsHeaderView)
    
}

class ProfileSettingsHeaderView: UIView {

//    private var nameLabel: UILabel!
//    private var nameField: UITextField!
//    private var tipTextLabel: UILabel!
    
    private var profileLabel: UILabel!
    private var profileHelpBtn: UIButton!
    var profileBtn: UIButton!
    private var selectImageView: UIImageView!
    
    weak var delegate: ProfileSettingsHeaderViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
//    @objc private func nameFieldEditChanged(sender: UITextField) {
//        guard let text = sender.text else {
//            return
//        }
//        
//        if let message = delegate?.view(self, nameEditChanged: text) {
//            if text.count > 32 { // 是否超限
//                sender.text = text.subString(rang: NSMakeRange(0, 32))
//            }
//            tipTextLabel.text = message
//        }else {
//            tipTextLabel.text = nil
//        }
//        
//    }
    
    @objc private func profileBtnClick(sender: UIButton) {
        
        delegate?.headerViewDidSelectProfile(self, profileRect: sender.frame)
    }
    
    @objc private func profileHelpBtnAction() {
        delegate?.headerViewHelpAction(self)
    }
    
    private func setupUI() {
        
//        nameLabel = UILabel(text: "name".localizedString, textColor: TextBlack_Color, fontSize: 15)
//        addSubview(nameLabel)
//        nameLabel.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(20))
//            make.top.equalToSuperview()
//        }
//        
//        nameField = UITextField()
//        nameField.text = "Profile 1"
//        nameField.textColor = TextBlack_Color
//        nameField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
//        nameField.layer.cornerRadius = 5
//        nameField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
//        nameField.layer.borderWidth = 0.5
//        nameField.clearButtonMode = .always
//        nameField.rightViewMode = .always
//        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
//        nameField.leftViewMode = .always
//        nameField.returnKeyType = .done
//        nameField.backgroundColor = .white
//        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
//        nameField.delegate = self
//        addSubview(nameField)
//        nameField.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(20))
//            make.right.equalTo(SCRXFrom(-20))
//            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
//            make.height.equalTo(SCRYFrom(40))
//        }
//        
//        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 12, fontWeight: .light)
//        addSubview(tipTextLabel)
//        tipTextLabel.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(24))
//            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(2))
//            make.right.equalTo(SCRXFrom(-24))
//        }
        
        profileLabel = UILabel(text: "profile".localizedString, textColor: RGB(72, 72, 74), fontSize: 15)
        addSubview(profileLabel)
        profileLabel.snp.makeConstraints { make in
//            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(18))
//            make.left.equalTo(nameField)
            make.left.equalTo(SCRXFrom(20))
            make.top.equalToSuperview()
        }
        
        profileHelpBtn = UIButton(normalImageName: "help", target: self, action: #selector(profileHelpBtnAction))
        addSubview(profileHelpBtn)
        profileHelpBtn.snp.makeConstraints { make in
            make.left.equalTo(profileLabel.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(profileLabel)
        }
        
        profileBtn = UIButton(title: "Occupancy sensing with daylight harvesting", titleSize: 14, titleWeight: .light, titleColor: RGB(72, 72, 74), target: self, action: #selector(profileBtnClick))
        profileBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        profileBtn.layer.cornerRadius = 5
        profileBtn.layer.borderWidth = 0.6
//        profileBtn.titleLabel?.adjustsFontSizeToFitWidth = true
        profileBtn.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        profileBtn.contentHorizontalAlignment = .left
        profileBtn.backgroundColor = .white
        profileBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 30)
        addSubview(profileBtn)
        profileBtn.snp.makeConstraints { make in
            make.left.equalTo(profileLabel)
            make.top.equalTo(profileLabel.snp.bottom).offset(SCRYFrom(9))
            make.height.equalTo(SCRYFrom(40))
            make.right.equalTo(SCRXFrom(-16))
        }
        
        selectImageView = UIImageView(image: UIImage(named: "arrow_down_small"))
        profileBtn.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalToSuperview()
        }
    }
    
}

//extension ProfileSettingsHeaderView: UITextFieldDelegate {
//    
//    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
//        textField.resignFirstResponder()
//        return true
//    }
//    
//}
