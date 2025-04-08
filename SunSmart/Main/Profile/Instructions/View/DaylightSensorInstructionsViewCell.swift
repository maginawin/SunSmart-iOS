//
//  DaylightSensorInstructionsViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/28.
//

import UIKit

class DaylightSensorInstructionsViewCell: UICollectionViewCell {
    
    var nameLabel: UILabel!
    var imageView: UIImageView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        nameLabel = UILabel(text: "Scheme 1", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
        }
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(8))
//            make.height.equalTo(imageView.snp.width).multipliedBy(120.0 / 156.0)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
