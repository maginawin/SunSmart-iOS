//
//  ProfileLightSensorTemplateViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/22.
//

import UIKit

class ProfileLightSensorTemplateViewCell: UICollectionViewCell {
    
    private var titleLabel: UILabel!
    private var luxLabel: UILabel!
    private var deviceCountLabel: UILabel!
    private var arrowImageView: UIImageView!
    
    var templateModel: ProfileLightSensorTemplate! {
        didSet {
            titleLabel.text = templateModel.name
//            luxLabel.text = templateModel
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-50))
        }
        
        luxLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(luxLabel)
        luxLabel.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(4))
        }
        
        deviceCountLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(deviceCountLabel)
        deviceCountLabel.snp.makeConstraints { make in
            make.left.equalTo(luxLabel)
            make.top.equalTo(luxLabel.snp.bottom).offset(SCRYFrom(4))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_right_black"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
    }
    
}
