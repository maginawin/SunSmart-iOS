//
//  SpaceFunctionFooterView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/9/27.
//

import UIKit

protocol SpaceFunctionFooterViewDelegate: AnyObject {
    
    /// 点击排序回调
    func functionDidClickSort(view: SpaceFunctionFooterView)
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView)
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool)
    
    /// 点击删除回调
    func functionDidClickDelete(view: SpaceFunctionFooterView)
}

extension SpaceFunctionFooterViewDelegate {
    
    /// 点击排序回调
    func functionDidClickSort(view: SpaceFunctionFooterView) {
        
    }
    
    /// 点击添加回调
    func functionDidClickAdd(view: SpaceFunctionFooterView) {
        
    }
    
    /// 编辑/取消编辑状态修改  editing：是否正在编辑
    func function(view: SpaceFunctionFooterView, editStateChanged editing: Bool) {
        
    }
    
    /// 点击删除回调
    func functionDidClickDelete(view: SpaceFunctionFooterView) {
        
    }

}


class SpaceFunctionFooterView: UIView {

    var countBtn: UIButton!
    var switchCountBtn: UIButton!
    var sortBtn: UIButton!
    var editBtn: UIButton!
    var addBtn: UIButton!
    
    var cancelBtn: UIButton!
    var lineView: UIView!
    var deleteBtn: UIButton!
    
    /// 是否正在编辑
    var isEditing: Bool = false {
        didSet {
            updateUI()
        }
    }
    
    weak var delegate: SpaceFunctionFooterViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// 排序
    @objc private func sortBtnClick() {
        delegate?.functionDidClickSort(view: self)
    }
    
    /// 编辑
    @objc private func editBtnClick() {
        
        isEditing = true
        delegate?.function(view: self, editStateChanged: true)
    }
    
    /// 添加
    @objc private func addBtnClick() {
        delegate?.functionDidClickAdd(view: self)
    }
    
    /// 取消
    @objc private func cancelBtnClick() {
            
        isEditing = false
        delegate?.function(view: self, editStateChanged: false)
    }
    
    /// 删除
    @objc private func deleteBtnClick() {
        delegate?.functionDidClickDelete(view: self)
    }
    
    /// 更新UI
    private func updateUI() {
        if isEditing {
            
            cancelBtn.isHidden = false
            lineView.isHidden = false
            deleteBtn.isHidden = false
            countBtn.isHidden = true
            editBtn.isHidden = true
            addBtn.isHidden = true
            sortBtn.isHidden = true
//            switchCountBtn.isHidden = true
        }else {
            cancelBtn.isHidden = true
            lineView.isHidden = true
            deleteBtn.isHidden = true
            countBtn.isHidden = false
            editBtn.isHidden = false
            addBtn.isHidden = false
            sortBtn.isHidden = false
//            switchCountBtn.isHidden = false
        }
    }
    
    private func setupUI() {
        
        countBtn = UIButton(title: "25/100", titleSize: 12, titleColor: TextBlack_Color, normalImageName: "space_device_count")
        countBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        countBtn.isUserInteractionEnabled = false
        addSubview(countBtn)
        countBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.top.equalTo(SCRYFrom(5))
        }
        
        switchCountBtn = UIButton(title: "0/16", titleSize: 12, titleColor: TextBlack_Color, normalImageName: "space_switch_count")
        switchCountBtn.setImagePosition(position: .left, spacing: SCRXFrom(2))
        switchCountBtn.isUserInteractionEnabled = false
        switchCountBtn.isHidden = true
        addSubview(switchCountBtn)
        switchCountBtn.snp.makeConstraints { make in
            make.left.equalTo(countBtn.snp.right).offset(SCRXFrom(20))
            make.centerY.equalTo(countBtn)
        }
        
        cancelBtn = UIButton(title: "cancel".localizedString, titleSize: 17, titleWeight: .light, titleColor: TextBlack_Color, target: self, action: #selector(cancelBtnClick))
        cancelBtn.isHidden = true
        addSubview(cancelBtn)
        cancelBtn.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(34))
            make.centerX.equalTo(self).multipliedBy(0.5)
            make.top.equalTo(SCRYFrom(14))
            make.width.equalTo(SCRXFrom(120))
            make.height.equalTo(SCRYFrom(30))
        }
        
        lineView = UIView()
        lineView.isHidden = true
        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(cancelBtn)
            make.width.equalTo(1)
            make.height.equalTo(SCRYFrom(40))
        }
        
        deleteBtn = UIButton(title: "DELETE".localizedString, titleSize: 17, titleWeight: .light, titleColor: Red_Color, target: self, action: #selector(deleteBtnClick))
//        deleteBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(17))
        deleteBtn.setTitleColor(RGB(147, 146, 154), for: .disabled)
        deleteBtn.isHidden = true
        addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
//            make.left.equalTo(lineView.snp.right).offset(SCRXFrom(34))
            make.centerX.equalTo(self).multipliedBy(1.5)
            make.width.height.centerY.equalTo(cancelBtn)
        }
        
        
        addBtn = UIButton(normalImageName: "space_add", target: self, action: #selector(addBtnClick))
        addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-30))
            make.centerY.equalTo(countBtn)
        }
        
        editBtn = UIButton(normalImageName: "space_edit", target: self, action: #selector(editBtnClick))
        addSubview(editBtn)
        editBtn.snp.makeConstraints { make in
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(addBtn)
        }
        
        sortBtn = UIButton(normalImageName: "space_sort", target: self, action: #selector(sortBtnClick))
        addSubview(sortBtn)
        sortBtn.snp.makeConstraints { make in
            make.right.equalTo(editBtn.snp.left).offset(SCRXFrom(-20))
            make.centerY.equalTo(editBtn)
        }
        
    }

}
