//
//  DeviceAllOnOffViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/11.
//

import UIKit

class DeviceAllOnOffViewCell: DevicesViewCell {
    
    var state: DeviceAllOnOffState = .disable {
        didSet { updateAppearance() }
    }

    var isLoading = false {
        didSet { updateAppearance() }
    }

    private func updateAppearance() {
        progressView.isHidden = true
        nameLabel.text = "all".localizedString
        switch state {
        case .on:
            backgroundColor = .white
            nameLabel.textColor = Title_Color
        case .off:
            backgroundColor = RGB(226, 226, 226)
            nameLabel.textColor = Title_Color
        case .disable:
            backgroundColor = .white
            nameLabel.textColor = RGB(148, 163, 184)
        }
        if isLoading {
            iconImageView.image = UIImage(named: "site_entry_sync_loading")?.withTintColor(Bar_Color)
            if iconImageView.layer.animation(forKey: "allControlLoading") == nil {
                iconImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: .max, animationKey: "allControlLoading")
            }
        } else {
            iconImageView.layer.removeAnimation(forKey: "allControlLoading")
            iconImageView.image = state == .disable
                ? UIImage(named: "device_all_off")
                : UIImage(named: "device_all_on")?.withTintColor(Bar_Color)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        isLoading = false
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.iconImageView.contentMode = .scaleAspectFit
        self.iconImageView.snp.updateConstraints { make in
            make.top.equalTo(SCRYFrom(24))
        }
        self.progressView.isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
