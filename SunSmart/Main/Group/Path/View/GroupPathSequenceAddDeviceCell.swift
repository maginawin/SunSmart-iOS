//
//  GroupPathSequenceAddDeviceCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

class GroupPathSequenceAddDeviceCell: UICollectionViewCell {
    
    var iconImageView: UIImageView!
    var nameLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        layer.borderWidth = 1
        layer.borderColor = RGB(241, 242, 244).cgColor
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        layer.cornerRadius = height * 0.5
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "path_device"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(isIPad ? SCRYFrom(8) : SCRYFrom(3))
        }
        
        nameLabel = UILabel(text: "ID001", textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-4))
            make.bottom.equalTo(SCRYFrom(-7))
        }
        
    }
}
