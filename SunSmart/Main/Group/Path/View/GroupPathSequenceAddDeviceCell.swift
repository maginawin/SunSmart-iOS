//
//  GroupPathSequenceAddDeviceCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/19.
//

import UIKit

class GroupPathSequenceAddDeviceCell: UICollectionViewCell {
    
    var boxView: UIView!
    var iconImageView: UIImageView!
    var nameLabel: AdaptiveTextView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        boxView = UIView()
        boxView.layer.borderWidth = 1
        boxView.layer.borderColor = RGB(241, 242, 244).cgColor
        boxView.layer.cornerRadius = GroupPathSequenceDeviceItemMetrics.controlCornerRadius
        contentView.addSubview(boxView)
        boxView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.controlSize)
        }
        
        iconImageView = UIImageView(image: UIImage(named: "path_device"))
        boxView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(GroupPathSequenceDeviceItemMetrics.imageTopSpacing)
            make.width.height.equalTo(GroupPathSequenceDeviceItemMetrics.imageSize)
        }
        
        nameLabel = AdaptiveTextView()
        nameLabel.textColor = Title_Color
        nameLabel.maxFontSize = FontFit(10)
        nameLabel.minFontSize = FontFit(8)
        nameLabel.lineHeightMultiple = 0.9
        boxView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(6)
            make.right.equalTo(-6)
            make.top.equalTo(iconImageView.snp.bottom).offset(
                GroupPathSequenceDeviceItemMetrics.imageNameSpacing
            )
            make.bottom.equalToSuperview()
        }
        
    }
}
