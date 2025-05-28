//
//  GroupPathSequencePathHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

class GroupPathSequencePathHeaderView: UITableViewHeaderFooterView {

    /// 操作类型
    enum OperationType {
        /// 保存
        case save
        /// 测试
        case test
        /// 重置
        case reset
        /// 删除
        case delete
    }
    
    var nameLabel: UILabel!
    var saveBtn: UIButton!
    var testBtn: UIButton!
    var resetBtn: UIButton!
    var deleteBtn: UIButton!
    
    var operationActionCallback: ((OperationType)->Void)?
    var viewSelectActionCallback: (()->Void)?
    
    
    var isSelect: Bool = false {
        didSet {
//            saveBtn.isHidden = !isSelect
            testBtn.isHidden = !isSelect
            resetBtn.isHidden = !isSelect
            deleteBtn.isHidden = !isSelect
            
        }
    }
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(viewClickAction)))
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func viewClickAction() {
        viewSelectActionCallback?()
    }
    
    @objc private func deleteBtnAction() {
        operationActionCallback?(.delete)
    }
    
    @objc private func resetBtnAction() {
        operationActionCallback?(.reset)
    }
    
    @objc private func testBtnAction() {
        operationActionCallback?(.test)
    }
    
    @objc private func saveBtnAction() {
        operationActionCallback?(.save)
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "Path 1", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(15))
        }
        
        let btnSize = CGSize(width: SCRXFrom(44), height: CGFloat(Int(SCRYFrom(28))))
        
        deleteBtn = UIButton(title: "delete".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(deleteBtnAction))
        deleteBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        deleteBtn.isHidden = true
        deleteBtn.layer.cornerRadius = SCRYFrom(5)
        deleteBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        deleteBtn.layer.borderWidth = 1
        deleteBtn.layer.masksToBounds = true
        deleteBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white), for: .normal)
        deleteBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white.withAlphaComponent(0.5)), for: .disabled)
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-9))
            make.top.equalTo(SCRYFrom(8))
            make.size.equalTo(btnSize)
        }
        
        resetBtn = UIButton(title: "reset".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(resetBtnAction))
        resetBtn.isHidden = true
        resetBtn.layer.cornerRadius = SCRYFrom(5)
        resetBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        resetBtn.layer.borderWidth = 1
        resetBtn.layer.masksToBounds = true
        resetBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        resetBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white), for: .normal)
        resetBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white.withAlphaComponent(0.5)), for: .disabled)
        contentView.addSubview(resetBtn)
        resetBtn.snp.makeConstraints { make in
            make.right.equalTo(deleteBtn.snp.left).offset(SCRXFrom(-8))
            make.width.height.centerY.equalTo(deleteBtn)
        }
        
        testBtn = UIButton(title: "test".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(testBtnAction))
        testBtn.isHidden = true
        testBtn.layer.cornerRadius = SCRYFrom(5)
        testBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        testBtn.layer.borderWidth = 1
        testBtn.layer.masksToBounds = true
        testBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        testBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white), for: .normal)
        testBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white.withAlphaComponent(0.5)), for: .disabled)
        contentView.addSubview(testBtn)
        testBtn.snp.makeConstraints { make in
            make.right.equalTo(resetBtn.snp.left).offset(SCRXFrom(-8))
            make.width.height.centerY.equalTo(resetBtn)
        }
        
        saveBtn = UIButton(title: "Save".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(saveBtnAction))
        saveBtn.isHidden = true
        saveBtn.layer.cornerRadius = SCRYFrom(5)
        saveBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        saveBtn.layer.borderWidth = 1
        saveBtn.layer.masksToBounds = true
        saveBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        saveBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white), for: .normal)
        saveBtn.setBackgroundImage(UIImage.image(size: btnSize, color: .white.withAlphaComponent(0.5)), for: .disabled)
        contentView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.equalTo(testBtn.snp.left).offset(SCRXFrom(-8))
            make.width.height.centerY.equalTo(testBtn)
        }
    }
    
}
