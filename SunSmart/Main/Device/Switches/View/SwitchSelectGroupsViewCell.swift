//
//  SwitchSelectGroupsViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/6.
//

import UIKit

class SwitchSelectGroupsViewCell: UITableViewCell {

    var selectImageView: UIImageView!
    var nameLabel: UILabel!
    var onoffBtn: UIButton!
    var lineView: UIView!
    
    var onOffCallback: ((Bool)->Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func onoffBtnAction(sender: UIButton) {
        onOffCallback?(!sender.isSelected)
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        
        onoffBtn = UIButton(normalImageName: "scene_group_off", selectedImageName: "scene_group_on", target: self, action: #selector(onoffBtnAction))
//        onoffBtn.setImage(UIImage(named: "scene_group_disable"), for: .disabled)
        onoffBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        onoffBtn.setContentHuggingPriority(.required, for: .horizontal)
        contentView.addSubview(onoffBtn)
        onoffBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(8))
            make.right.lessThanOrEqualTo(onoffBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }

        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(15))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
    }
    
}
