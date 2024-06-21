//
//  ShareAuthoritySpaceViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/30.
//

import UIKit

class ShareAuthoritySpaceViewCell: UICollectionViewCell {

    var nameLabel: UILabel!
    var iconImageView: UIImageView!
    var bottomView: UIView!
    var deviceImageView: UIImageView!
    var deviceCountLabel: UILabel!
    var editorImageView: UIImageView!
    var selectImageView: UIImageView!
    var permissionLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(10)
        clipsToBounds = true
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        nameLabel = UILabel(text: "Space 1", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.top.equalTo(SCRYFrom(8))
            make.right.equalTo(SCRXFrom(-12))
        }
        
        iconImageView = UIImageView(image: UIImage(named: "space_picture_1"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalToSuperview().offset(SCRYFrom(-2))
            make.width.equalTo(SCRYFrom(96))
            make.height.equalTo(iconImageView.snp.width).offset(96.0 / 120)
        }
        
        selectImageView = UIImageView(image: UIImage(named: "select_un"))
        selectImageView.isHidden = true
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.top.right.equalToSuperview()
        }
        
        bottomView = UIView()
        bottomView.backgroundColor = RGB(148, 163, 184, 0.1)
        contentView.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
        }
        
        deviceImageView = UIImageView(image: UIImage(named: "space_device_count"))
        bottomView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalToSuperview()
        }
      
        deviceCountLabel = UILabel(text: "0", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        bottomView.addSubview(deviceCountLabel)
        deviceCountLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(4))
            make.centerY.equalTo(deviceImageView).offset(SCRYFrom(2))
        }
        
        editorImageView = UIImageView(image: UIImage(named: "space_editor"))
        editorImageView.isHidden = true
        bottomView.addSubview(editorImageView)
        editorImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }
        
        permissionLabel = UILabel(text: "Visitor", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        permissionLabel.isHidden = true
        bottomView.addSubview(permissionLabel)
        permissionLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalTo(deviceCountLabel)
        }
        
    }
    
}
