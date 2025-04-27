//
//  DeviceDongleScheduleHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

protocol DeviceDongleScheduleHeaderViewDelegate: AnyObject {
    
    /// 编辑/取消编辑回调
    func headerView(_ headerView: DeviceDongleScheduleHeaderView, didEditAction edit: Bool)
    
    /// 点击添加回调
    func headerViewAddAction(_ headerView: DeviceDongleScheduleHeaderView)
    
    /// 点击删除回调
    func headerViewDeleteAction(_ headerView: DeviceDongleScheduleHeaderView)
    
}

class DeviceDongleScheduleHeaderView: UITableViewHeaderFooterView {

    var startCollectLabel: UILabel!
    var titleLabel: UILabel!
    var addBtn: UIButton!
    var minusBtn: UIButton!
    var backBtn: UIButton!
    var deleteBtn: UIButton!
    
    weak var delegate: DeviceDongleScheduleHeaderViewDelegate?
    
    var isEdit: Bool = false {
        didSet {
            
            addBtn.isHidden = isEdit
            minusBtn.isHidden = isEdit
            backBtn.isHidden = !isEdit
            deleteBtn.isHidden = !isEdit
        }
    }
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func addBtnAction() {
        delegate?.headerViewAddAction(self)
    }
    
    @objc private func minusBtnAction() {
        delegate?.headerView(self, didEditAction: true)
    }
    
    @objc private func backBtnAction() {
        delegate?.headerView(self, didEditAction: false)
    }
    
    @objc private func deleteBtnAction() {
        delegate?.headerViewDeleteAction(self)
    }
    
    private func setupUI() {
        
        startCollectLabel = UILabel(text: "Start from 6/10/2025 06:02:34 PM", textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        startCollectLabel.isHidden = true
        contentView.addSubview(startCollectLabel)
        startCollectLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(4))
        }
        
        titleLabel = UILabel(text: "collection_schedule".localizedString, textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.equalTo(SCRYFrom(-9))
        }
        
        addBtn = UIButton(title: "\("Add".localizedString) ＋", titleSize: 14, titleColor: Bar_Color, target: self, action: #selector(addBtnAction))
        contentView.addSubview(addBtn)
        addBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(titleLabel)
            make.width.greaterThanOrEqualTo(SCRXFrom(38))
            make.height.equalTo(SCRYFrom(30))
        }
        
        minusBtn = UIButton(title: "－", titleSize: 14, titleColor: Bar_Color, target: self, action: #selector(minusBtnAction))
        contentView.addSubview(minusBtn)
        minusBtn.snp.makeConstraints { make in
            make.right.equalTo(addBtn.snp.left).offset(SCRXFrom(-4))
            make.centerY.height.equalTo(addBtn)
            make.width.equalTo(SCRXFrom(38))
        }
        
        deleteBtn = UIButton(title: "delete".localizedString, titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(deleteBtnAction))
        deleteBtn.setTitleColor(Message_Color, for: .disabled)
        deleteBtn.isHidden = true
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.height.equalTo(addBtn)
        }
        
        backBtn = UIButton(normalImageName: "revoke", target: self, action: #selector(backBtnAction))
        backBtn.isHidden = true
        contentView.addSubview(backBtn)
        backBtn.snp.makeConstraints { make in
            make.right.equalTo(deleteBtn.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalTo(deleteBtn)
        }
        
    }

}
