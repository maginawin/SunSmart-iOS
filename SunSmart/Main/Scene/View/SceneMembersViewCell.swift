//
//  SceneMembersViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/26.
//

import UIKit

class SceneMembersViewCell: SceneGroupsViewCell {
    
    var selectBtn: UIButton!
    
    var selectActionCallBack: ((Bool)->Void)?
 
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        iconImageView.snp.updateConstraints { make in
//            make.bottom.equalTo(bgView.snp.centerY)
            make.centerY.equalToSuperview().offset(SCRYFrom(-12))
        }
    
//        imageLabel.snp.updateConstraints { make in
//            make.top.equalTo(SCRYFrom(21))
//        }
        
        nameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        nameLabel.snp.updateConstraints({ make in
            make.bottom.equalTo(SCRYFrom(-18))
        })
        
        selectBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select", target: self, action: #selector(selectBtnClick))
        contentView.addSubview(selectBtn)
        selectBtn.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-4))
//            make.top.equalTo(SCRXFrom(-5))
            make.right.top.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func selectBtnClick(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        selectActionCallBack?(sender.isSelected)
    }
}
