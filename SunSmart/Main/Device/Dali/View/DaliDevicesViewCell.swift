//
//  DaliDevicesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2025/2/27.
//

import UIKit

class DaliDevicesViewCell: UICollectionViewCell {
 
    /// 图标
    var iconImageView: UIImageView!
    
    var progressView: CustomProgressView!
    /// 名称
    var nameLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        layer.shadowOffset = CGSize(width: 0,height: 2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4
        
//        clipsToBounds = true
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
        
        iconImageView = UIImageView()
        iconImageView.image = UIImage(named: "device_light")
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
//            make.left.equalTo(SCRXFrom(11))
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(10))
            make.width.height.equalTo(SCRXFrom(30))
        }
        
        progressView = CustomProgressView()
        progressView.cornerRadius = 1
        progressView.progressPadding = 0.5
        contentView.addSubview(progressView)
        progressView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(19))
            make.right.equalTo(SCRXFrom(-19))
            make.top.equalTo(self.snp.centerY).offset(SCRYFrom(8))
            //            make.bottom.equalTo(SCRYFrom(-40))
            make.height.equalTo(2)
        }
        
        nameLabel = UILabel(text: "ID001", textColor: Title_Color, fontSize: 14, fontWeight: .light)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-13))
            make.bottom.equalTo(SCRYFit(-9))
        }
    }
    
}
