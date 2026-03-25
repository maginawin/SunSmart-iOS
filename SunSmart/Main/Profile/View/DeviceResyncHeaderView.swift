//
//  DeviceResyncHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/31.
//

import UIKit

class DeviceResyncHeaderView: UICollectionReusableView {
 
    var iconImageView: UIImageView!
    var titleLabel: UILabel!
    var retryBtn: UIButton!
    var retryActionCallback: (()->Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = Background_Color
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func retryBtnAction() {
        retryActionCallback?()
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "sync_failed_small"))
        iconImageView.sizeToFit()
        addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.top.equalToSuperview()
            make.size.equalTo(iconImageView.frame.size)
        }
        
        retryBtn = UIButton(title: "retry".localizedString, titleSize: 12, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(retryBtnAction))
        retryBtn.layer.cornerRadius = SCRYFrom(5)
        retryBtn.layer.borderColor = Bar_Color.withAlphaComponent(0.3).cgColor
        retryBtn.layer.borderWidth = 0.6
        retryBtn.backgroundColor = .white
        addSubview(retryBtn)
        retryBtn.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(iconImageView)
            make.width.equalTo(SCRXFrom(56))
            make.height.equalTo(SCRYFrom(24))
        }
        
        titleLabel = UILabel(text: "device_settings_failed_retry_note".localizedString, textColor: Error_Red_Color, fontSize: 12, fontWeight: .light, fit: false)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(iconImageView)
            make.right.equalTo(retryBtn.snp.left).offset(SCRXFrom(-20))
        }
        
    }
    
}
