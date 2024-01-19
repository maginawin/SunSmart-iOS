//
//  GroupAddHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit

class GroupAddHeaderView: UICollectionReusableView {
        
    private var headerView: UIView!
    private var nameLabel: UILabel!
    var nameField: UITextField!
    private var tipTextLabel: UILabel!
    
    var profileLabel: UILabel!
    var profileBtn: UIButton!
    var profileEditBtn: UIButton!
    
    /// 名称编辑回调
    var nameEditChangedCallback: ((String)->String?)?
 
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        profileBtn.setImagePosition(position: .right, spacing: 0)
    }
    
    @objc private func hideKeyboard() {
        endEditing(true)
    }
    
    @objc private func textExceededHide() {
        nameFieldEditChanged(sender: nameField)
    }
    
    @objc private func nameFieldEditChanged(sender: UITextField) {
        guard let text = sender.text else {
            return
        }
        
        if let message = nameEditChangedCallback?(text) {
            if text.count > 32 { // 是否超限
                sender.text = text.subString(rang: NSMakeRange(0, 32))
            }
            tipTextLabel.text = message
//            "text_length_exceeded".localizedString
//            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
//            self.perform(#selector(textExceededHide), with: nil, afterDelay: 2)
        }else {
            tipTextLabel.text = nil
        }
        
//        if text.count > 32 { // 是否超限
//            sender.text = text.subString(rang: NSMakeRange(0, 32))
//            tipTextLabel.text = "text_length_exceeded".localizedString
//            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(textExceededHide), object: nil)
//            self.perform(#selector(textExceededHide), with: nil, afterDelay: 2)
//        }else {
//            // 是否重名
//            if let result = nameEditChangedCallback?(text) {
//                tipTextLabel.text = result ? "name_already_exists".localizedString : nil
//                self.isTautonym = result
//                if result {
//                    doneBtn.isEnabled = false
//                }else {
//                    doneBtn.isEnabled = true
//                }
//            }else {
//                doneBtn.isEnabled = true
//            }
//            if text.isEmpty {
//                doneBtn.isEnabled = false
//            }
//        }
    }
    
    @objc private func profileBtnClick() {
        
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "name".localizedString, textColor: TextBlack_Color, fontSize: 15)
        addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(16))
        }
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        nameField.layer.cornerRadius = 5
        nameField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        nameField.layer.borderWidth = 1
        nameField.clearButtonMode = .always
        nameField.rightViewMode = .always
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
        nameField.leftViewMode = .always
        nameField.returnKeyType = .done
        nameField.backgroundColor = .white
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        nameField.delegate = self
        addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
        }
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 12, fontWeight: .light)
        addSubview(tipTextLabel)
        tipTextLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(2))
            make.right.equalTo(SCRXFrom(-24))
        }
        
        profileLabel = UILabel(text: "profile".localizedString, textColor: RGB(72, 72, 74), fontSize: 15)
        addSubview(profileLabel)
        profileLabel.snp.makeConstraints { make in
            make.top.equalTo(nameField.snp.bottom).offset(SCRYFrom(18))
            make.left.equalTo(nameField)
        }
        
        profileBtn = UIButton(title: "Occupancy sensing with daylight harvesting", titleSize: 14, titleWeight: .light, titleColor: RGB(72, 72, 74), normalImageName: "arrow_down_small", target: self, action: #selector(profileBtnClick))
        profileBtn.layer.cornerRadius = 5
        profileBtn.layer.borderWidth = 0.5
        profileBtn.titleLabel?.adjustsFontSizeToFitWidth = true
        profileBtn.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        profileBtn.backgroundColor = .white
        profileBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(6), bottom: 0, right: SCRXFrom(1))
        addSubview(profileBtn)
        profileBtn.snp.makeConstraints { make in
            make.left.equalTo(profileLabel)
            make.top.equalTo(profileLabel.snp.bottom).offset(SCRYFrom(9))
            make.height.equalTo(SCRYFrom(40))
            make.right.equalTo(SCRXFrom(-54))
        }
        
        profileEditBtn = UIButton(normalImageName: "edit_icon", target: nil, action: nil)
        addSubview(profileEditBtn)
        profileEditBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-24))
            make.centerY.equalTo(profileBtn)
        }
    }
    
}

extension GroupAddHeaderView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
}
