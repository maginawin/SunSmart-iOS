//
//  GroupPathSequenceAddDeviceCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

class GroupPathSequenceAddDeviceCell: UICollectionViewCell {
    
    var iconImageView: UIImageView!
    var nameLabel: AdaptiveTextView!
    
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
        iconImageView.sizeToFit()
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(isIPad ? SCRYFrom(8) : SCRYFrom(3))
            make.height.equalTo(iconImageView.height)
        }
        
        nameLabel = AdaptiveTextView()
        nameLabel.textColor = Title_Color
        nameLabel.maxFontSize = FontFit(10)
        nameLabel.minFontSize = FontFit(8)
        nameLabel.lineHeightMultiple = 0.9
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(6))
            make.right.equalTo(SCRXFrom(-6))
            make.top.equalTo(iconImageView.snp.bottom)
            make.bottom.equalToSuperview()
        }
        
    }
}
