//
//  GroupSwitchPanelViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/12.
//

import UIKit

protocol GroupSwitchPanelViewCellDelegate: AnyObject {
    
    /// 删除事件
    func switchPanelViewCellDeleteAction(_ cell: GroupSwitchPanelViewCell)
    /// 保存事件
    func switchPanelViewCellSaveAction(_ cell: GroupSwitchPanelViewCell)
    
}

class GroupSwitchPanelViewCell: UITableViewCell {

    private var panelImageView: UIImageView!
    private var deleteBtn: UIButton!
    var saveBtn: UIButton!
    weak var delegate: GroupSwitchPanelViewCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = Background_Color
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func deleteBtnAction() {
        delegate?.switchPanelViewCellDeleteAction(self)
    }
    
    @objc private func saveBtnAction() {
        delegate?.switchPanelViewCellSaveAction(self)
    }
    
    private func setupUI() {
        
        panelImageView = UIImageView(image: UIImage(named: "switch_panel"))
        contentView.addSubview(panelImageView)
        panelImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(panelImageView.snp.width).multipliedBy(288.0 / 343)
//            make.bottom.equalTo(SCRYFrom(-68))
        }
        
        deleteBtn = UIButton(normalImageName: "switch_delete", target: self, action: #selector(deleteBtnAction))
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(56))
            make.top.equalTo(panelImageView.snp.bottom).offset(SCRYFrom(16))
//            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(40)
        }
        
        saveBtn = UIButton(normalImageName: "switch_save", target: self, action: #selector(saveBtnAction))
        saveBtn.setImage(UIImage(named: "switch_save_un"), for: .disabled)
        contentView.addSubview(saveBtn)
        saveBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-56))
            make.centerY.height.equalTo(deleteBtn)
        }
        
    }
    
}
