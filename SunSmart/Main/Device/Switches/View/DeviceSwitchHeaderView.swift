//
//  DeviceSwitchHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/6.
//

import UIKit

class DeviceSwitchHeaderView: UITableViewHeaderFooterView {

    private var nameLabel: UILabel!
    var nameField: UITextField!
    private var tipTextLabel: UILabel!
    
    var syncFailedBtn: UIButton!
    
    /// 名称编辑回调
    var nameEditChanged: ((String)->String?)?
    /// 重新同步回调
    var reSyncCallback: (()->Void)?
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(hideKeyboard)))
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
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
        
        if let message = nameEditChanged?(text) {
            if text.count > 32 { // 是否超限
                sender.text = text.subString(rang: NSMakeRange(0, 32))
                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5) {
                    self.tipTextLabel.text = nil
                }
            }
            tipTextLabel.text = message
        }else {
            tipTextLabel.text = nil
        }
        
//        if let message = delegate?.view(self, nameEditChanged: text) {
////            if text.count > 32 { // 是否超限
////                sender.text = text.subString(rang: NSMakeRange(0, 32))
////                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5) {
////                    self.tipTextLabel.isHidden = true
////                }
////            }
//            tipTextLabel.text = message
//        }else {
//            tipTextLabel.text = nil
//        }
    
    }
    
    @objc private func syncFailedBtnAction() {
        reSyncCallback?()
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "name".localizedString, textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(7))
        }
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        nameField.layer.cornerRadius = SCRYFrom(10)
        nameField.clearButtonMode = .always
//        nameField.rightView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(4), height: 0))
        nameField.rightViewMode = .always
        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(16), height: 0))
        nameField.leftViewMode = .always
        nameField.returnKeyType = .done
        nameField.backgroundColor = .white
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        nameField.delegate = self
        addSubview(nameField)
        nameField.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(20))
//            make.right.equalTo(SCRXFrom(-20))
            make.left.right.equalToSuperview()
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(44))
        }
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 12, fontWeight: .light)
        addSubview(tipTextLabel)
        tipTextLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(nameField.snp.bottom)
            make.right.equalTo(SCRXFrom(-24))
        }
        
        syncFailedBtn = UIButton(title: "devices_not_synced".localizedString, titleSize: 14, titleWeight: .light, titleColor: Red_Color, fit: false, normalImageName: "schedule_sync_failed", target: self, action: #selector(syncFailedBtnAction))
        syncFailedBtn.isHidden = true
        syncFailedBtn.setImagePosition(position: .left, spacing: SCRXFrom(4))
        addSubview(syncFailedBtn)
        syncFailedBtn.snp.makeConstraints { make in
            make.right.equalTo(nameField)
            make.centerY.equalTo(nameLabel)
        }
    }
    
}

extension DeviceSwitchHeaderView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
}
