//
//  NoInternetHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/5/28.
//

import UIKit

class NoInternetHeaderView: UIView {

    var imageView: UIImageView!
    
    var messageLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        imageView = UIImageView(image: UIImage(named: "no_Internet"))
        addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(4))
            make.top.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        messageLabel = UILabel(text: "no_internet_message".localizedString, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: true)
        messageLabel.numberOfLines = 2
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(imageView.snp.right).offset(SCRXFrom(4))
            make.right.equalTo(SCRXFrom(-4))
            make.centerY.equalTo(imageView)
        }
    }
    
}
