//
//  DeviceAllOnOffViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/1/11.
//

import UIKit

class DeviceAllOnOffViewCell: DevicesViewCell {
    
    var state: DeviceAllOnOffState = .disable {
        didSet {
            self.progressView.isHidden = true
            nameLabel.text = "all".localizedString
            switch state {
            case .on:
                backgroundColor = .white
                iconImageView.image = UIImage(named: "device_all_on")
                nameLabel.textColor = Title_Color
            case .off:
                iconImageView.image = UIImage(named: "device_all_on")
                nameLabel.textColor = Title_Color
                backgroundColor = RGB(226, 226, 226)
            case .disable:
                nameLabel.textColor = RGB(148, 163, 184)
                backgroundColor = .white
                iconImageView.image = UIImage(named: "device_all_off")
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        self.iconImageView.snp.updateConstraints { make in
            make.top.equalTo(SCRYFrom(24))
        }
        self.progressView.isHidden = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
