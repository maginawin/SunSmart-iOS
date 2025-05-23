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
        
        deleteBtn = UIButton(title: "delete".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(deleteBtnAction))
        deleteBtn.isHidden = true
        deleteBtn.layer.cornerRadius = SCRYFrom(5)
        deleteBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        deleteBtn.layer.borderWidth = 1
        deleteBtn.backgroundColor = .white
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-9))
            make.top.equalTo(SCRYFrom(8))
            make.width.equalTo(SCRXFrom(44))
            make.height.equalTo(SCRYFrom(28))
        }
        
        resetBtn = UIButton(title: "reset".localizedString, titleSize: 12, titleColor: Bar_Color, target: self, action: #selector(resetBtnAction))
        resetBtn.isHidden = true
        resetBtn.layer.cornerRadius = SCRYFrom(5)
        resetBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        resetBtn.layer.borderWidth = 1
        resetBtn.backgroundColor = .white
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
        testBtn.backgroundColor = .white
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
        saveBtn.backgroundColor = .white
        contentView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.equalTo(testBtn.snp.left).offset(SCRXFrom(-8))
            make.width.height.centerY.equalTo(testBtn)
        }
    }
    
}
