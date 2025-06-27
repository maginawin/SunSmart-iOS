//
//  DeviceAddSelectAllViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/23.
//

import UIKit

protocol DeviceAddSelectAllViewCellDelegate: AnyObject {
    
    /// 设备点击选择/取消所有 事件回调
    func cell(_ cell: DeviceAddSelectAllViewCell, selectAllAction selectAll: Bool)
    
    /// 设备预选事件回调
    func selectAllCellCandidateAction(_ cell: DeviceAddSelectAllViewCell)
}

class DeviceAddSelectAllViewCell: UITableViewCell {

    var selectBtn: UIButton!
    var selectAllLabel: UILabel!
    var countLabel: UILabel!
    var candidateBtn: UIButton!
    
    weak var delegate: DeviceAddSelectAllViewCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func selectBtnAction(sender: UIButton) {
        
        sender.isSelected = !sender.isSelected
        
        delegate?.cell(self, selectAllAction: sender.isSelected)
    }
    
    @objc private func candidateBtnAction() {
        delegate?.selectAllCellCandidateAction(self)
    }
    
    private func setupUI() {
        
        selectBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectBtnAction))
        contentView.addSubview(selectBtn)
        selectBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.bottom.equalToSuperview()
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectBtn.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(selectBtn)
        }
        
        countLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(countLabel)
        countLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllLabel.snp.right).offset(SCRXFrom(11))
            make.centerY.equalTo(selectAllLabel)
        }
        
        candidateBtn = UIButton(normalImageName: "device_add_candidate", target: self, action: #selector(candidateBtnAction))
        contentView.addSubview(candidateBtn)
        candidateBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectBtn)
            make.width.height.equalTo(SCRYFrom(30))
        }
    }
}
