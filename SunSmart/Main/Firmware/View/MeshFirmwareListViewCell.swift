//
//  MeshFirmwareListViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/7/23.
//

import UIKit

class MeshFirmwareListViewCell: UICollectionViewCell {
 
    private var iconImageView: UIImageView!
    var titleLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.shadowOffset = CGSize(width: 0, height: 3)
        layer.shadowOpacity = 1
        layer.shadowRadius = SCRYFrom(10)
        layer.shadowColor = RGB(0, 0, 0, 0.05).cgColor
        layer.cornerRadius = SCRYFrom(10)
        
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "firmware"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(30)
        }
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-30))
        }
        
    }
    
}
