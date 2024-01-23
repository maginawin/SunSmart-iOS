//
//  SceneAddTemplateInfoSectionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/21.
//

import UIKit

protocol SceneAddTemplateInfoSectionViewDelegate: AnyObject {
    
    /// 图标点击回调
    func sectionViewDidImageAction(_ sectionView: SceneAddTemplateInfoSectionView)
    
    /// 重置点击回调
    func sectionViewDidResetAction(_ sectionView: SceneAddTemplateInfoSectionView)
    
    /// 名称修改回调
    /// - Parameters:
    ///   - name: 输入文本
    /// - Returns: 提示内容（不合法）
    func sectionView(_ sectionView: SceneAddTemplateInfoSectionView, didNameChanged name: String) -> String?
    
}

extension SceneAddTemplateInfoSectionViewDelegate {
    
    /// 图标点击回调
    func sectionViewDidImageAction(_ sectionView: SceneAddTemplateInfoSectionView) {}
    
    /// 重置点击回调
    func sectionViewDidResetAction(_ sectionView: SceneAddTemplateInfoSectionView) {}
    
    /// 名称修改回调
    func sectionView(_ sectionView: SceneAddTemplateInfoSectionView, didNameChanged name: String) {}
}

class SceneAddTemplateInfoSectionView: UICollectionReusableView {
        
    var templateTitleLabel: UILabel!
    var templateLabel: UILabel!
    var resetBtn: UIButton!
    
    private var infoView: UIView!
    var iconImageView: UIImageView!
    private var iconBgView: UIView!
    var nameField: UITextField!
    private var tipTextLabel: UILabel!
    
    private var messageLabel: UILabel!
    
    weak var delegate: SceneAddTemplateInfoSectionViewDelegate?
    
    var name: String? {
        get {
            return nameField.text
        }set {
            nameField.text = newValue
            nameFieldEditChanged(sender: nameField)
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func resetBtnAction() {
        delegate?.sectionViewDidResetAction(self)
    }
    
    @objc private func iconBgViewAction() {
        delegate?.sectionViewDidImageAction(self)
    }
    
    @objc private func nameFieldEditChanged(sender: UITextField) {
        guard let text = sender.text else {
            return
        }
        let tipText = delegate?.sectionView(self, didNameChanged: text)
        tipTextLabel.text = tipText
    }
    
    private func setupUI() {
        
        templateTitleLabel = UILabel(text: "template:".localizedString, textColor: Title_Color, fontSize: 15)
        addSubview(templateTitleLabel)
        templateTitleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.top.equalTo(SCRYFrom(26))
        }
        
        templateLabel = UILabel(text: "Office->PPT", textColor: Title_Color, fontSize: 15, fontWeight: .light)
        
        addSubview(templateLabel)
        templateLabel.snp.makeConstraints { make in
            make.left.equalTo(templateTitleLabel.snp.right).offset(SCRXFrom(6))
//            make.right.equalTo(SCRXFrom(-60))
            make.width.lessThanOrEqualTo(SCRXFrom(230))
            make.centerY.equalTo(templateTitleLabel)
        }
        
        resetBtn = UIButton(normalImageName: "reset", target: self, action: #selector(resetBtnAction))
        addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalTo(templateLabel)
        }
        
        infoView = UIView()
        infoView.backgroundColor = .white
        infoView.layer.cornerRadius = SCRYFrom(10)
        addSubview(infoView)
        infoView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(16))
//            make.right.equalTo(SCRXFrom(-16))
            make.left.right.equalToSuperview()
            make.top.equalTo(templateTitleLabel.snp.bottom).offset(SCRYFrom(22))
            make.height.equalTo(SCRYFrom(56))
        }
        
        iconBgView = UIView()
        iconBgView.layer.cornerRadius = SCRYFrom(22)
        iconBgView.layer.borderWidth =  0.5
        iconBgView.layer.borderColor = Bar_Color.cgColor
        iconBgView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(iconBgViewAction)))
        infoView.addSubview(iconBgView)
        iconBgView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(44))
        }
        
        iconImageView = UIImageView()
        iconBgView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        
        nameField = UITextField()
        nameField.text = "PPT"
        nameField.textColor = RGB(30, 35, 41)
        nameField.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
//        nameField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(8), height: 0))
//        nameField.leftViewMode = .always
        nameField.clearButtonMode = .always
//        nameField.rightViewMode = .always
        nameField.returnKeyType = .done
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        nameField.delegate = self
        infoView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(iconBgView.snp.right).offset(SCRXFrom(10))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(8))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 13, fontWeight: .light)
        addSubview(tipTextLabel)
        tipTextLabel.snp.makeConstraints { make in
            make.left.equalTo(infoView).offset(SCRXFrom(12))
            make.top.equalTo(infoView.snp.bottom).offset(SCRYFrom(1))
            make.right.equalTo(SCRXFrom(-24))
        }
        
        messageLabel = UILabel(text: "scene_prameters_message".localizedString, textColor: RGB(100, 116, 139), fontSize: 13, fontWeight: .light)
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-12))
            make.top.equalTo(infoView.snp.bottom).offset(SCRYFrom(16))
        }
        
    }
    
}

extension SceneAddTemplateInfoSectionView: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endEditing(true)
        return true
    }
    
    
    
}
