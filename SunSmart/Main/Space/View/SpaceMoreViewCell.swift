//
//  SpaceMoreViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/22.
//

import UIKit

class SpaceMoreViewCell: UICollectionViewCell {
    
    var iconImageView: UIImageView!
    var titleLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        
        layer.cornerRadius = SCRYFrom(12)
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        layer.shadowOpacity = 1
        layer.shadowRadius = 5
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView()
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(iconImageView)
        }
        
    }
    
    
}
