//
//  ShareBacthListViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/6/4.
//

import UIKit

class ShareBacthListViewCell: UICollectionViewCell {
    
    /// 名称
    var nameLabel: UILabel!
    /// 分享id
    var shareIdLabel: UILabel!
    /// 撤回按键
    var withdrawBtn: UIButton!
    /// 撤回回调
    var withdrawCallback: (()->Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // 撤回
    @objc private func withdrawBtnAction() {
        withdrawCallback?()
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "Bacth 253487", textColor: TextBlack_Color, fontSize: 14)
        nameLabel.sizeToFit()
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(13))
            make.width.lessThanOrEqualTo(SCRXFrom(240))
            make.height.equalTo(nameLabel.height)
        }
        
        shareIdLabel = UILabel(text: "XXXXXXXX", textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(shareIdLabel)
        shareIdLabel.snp.makeConstraints { make in
            make.left.width.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(6))
        }
        
        withdrawBtn = UIButton(normalImageName: "withdraw", target: self, action: #selector(withdrawBtnAction))
        contentView.addSubview(withdrawBtn)
        withdrawBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
    }
    
}
