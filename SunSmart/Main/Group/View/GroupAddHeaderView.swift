//
//  GroupAddHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit

protocol GroupAddHeaderViewDelegate: AnyObject {
    
    /// 名称编辑回调
    /// - Parameters:
    ///   - view: view
    ///   - name: 名称
    /// - Returns: 返回错误提示（可选）
    func view(_ view: GroupAddHeaderView, nameEditChanged name: String) -> String?
    
    /// 选择配置文件回调
    func headerViewDidSelectProfile(_ view: GroupAddHeaderView, profileRect: CGRect)
    
    /// 编辑配置文件回调
    func headerViewDidEditProfile(_ view: GroupAddHeaderView)
}

class GroupAddHeaderView: UICollectionReusableView {
        
    private var headerView: UIView!
    private var nameLabel: UILabel!
    var nameField: UITextField!
    private var tipTextLabel: UILabel!
    
    var profileLabel: UILabel!
    var profileBtn: UIButton!
    private var selectImageView: UIImageView!
    var profileEditBtn: UIButton!
    
    weak var delegate: GroupAddHeaderViewDelegate?
    
 
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
//        profileBtn.setImagePosition(position: .right, spacing: 0)
    }
    
    /// 未输入名称
    func showEmptyState() {
        if nameField.text == nil || nameField.text?.isAllInputTextEmpty() ?? true {
            tipTextLabel.text = "name_empty".localizedString
//            nameField.layer.borderColor = Red_Color.cgColor
        }else {
            tipTextLabel.text = nil
//            nameField.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        }
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
        
        if let message = delegate?.view(self, nameEditChanged: text) {
//            if text.count > 32 { // 是否超限
//                sender.text = text.subString(rang: NSMakeRange(0, 32))
//                DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1.5) {
//                    self.tipTextLabel.isHidden = true
//                }
//            }
            tipTextLabel.text = message
        }else {
            tipTextLabel.text = nil
        }
    
    }
    
    @objc private func profileBtnClick(sender: UIButton) {
        
        delegate?.headerViewDidSelectProfile(self, profileRect: sender.frame)
    }
    
    @objc private func profileEditBtnAction() {
        delegate?.headerViewDidEditProfile(self)
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
        nameField.layer.borderWidth = 0.6
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
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 13, fontWeight: .light)
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
        
        profileBtn = UIButton(title: "Occupancy sensing with daylight harvesting", titleSize: 14, titleWeight: .light, titleColor: RGB(72, 72, 74), target: self, action: #selector(profileBtnClick))
//        profileBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        profileBtn.layer.cornerRadius = 5
        profileBtn.layer.borderWidth = 0.6
        profileBtn.titleLabel?.adjustsFontSizeToFitWidth = true
        profileBtn.layer.borderColor = RGB(151, 151, 151, 0.3).cgColor
        profileBtn.backgroundColor = .white
        profileBtn.contentHorizontalAlignment = .left
        profileBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 30)
        addSubview(profileBtn)
        profileBtn.snp.makeConstraints { make in
            make.left.equalTo(profileLabel)
            make.top.equalTo(profileLabel.snp.bottom).offset(SCRYFrom(9))
            make.height.equalTo(SCRYFrom(40))
            make.right.equalTo(SCRXFrom(-54))
        }
        
        selectImageView = UIImageView(image: UIImage(named: "arrow_down_small"))
        profileBtn.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalToSuperview()
        }
        
        profileEditBtn = UIButton(normalImageName: "edit_icon", target: self, action: #selector(profileEditBtnAction))
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
