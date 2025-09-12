//
//  GroupDeviceViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/13.
//

import UIKit
import NordicSigMeshSDK

class GroupDeviceViewCell: DevicesViewCell {
    
    override var device: Node! {
        didSet {
            super.device = device
            
//            DispatchQueue.global().async {
//                if self.device.needSync && self.device.state {
//                    DispatchQueue.main.async {
//                        self.iconImageView.image = UIImage(named: self.device.unsyncIconName)
//                    }
//                }
//            }
            
            if device.isKeybindComplete && device.state {
                iconImageView.snp.updateConstraints { make in
                    make.top.equalTo(SCRYFrom(10))
                }
            }else {
                iconImageView.snp.updateConstraints { make in
                    make.top.equalTo(SCRYFrom(17))
                }
            }
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        proxyFlagView.snp.updateConstraints { make in
            make.left.equalTo(SCRXFrom(12))
        }
        
        iconImageView.snp.updateConstraints { make in
            make.top.equalTo(SCRYFrom(10))
            make.width.height.equalTo(SCRXFrom(30))
        }
        
//        progressBgView.layer.cornerRadius = 3
//        progressBgView.layer.masksToBounds = true
//        progressValueView.layer.cornerRadius = 3
        
//        lightnessProgressView.layer.masksToBounds = true
        progressView.cornerRadius = 1.5
        progressView.snp.remakeConstraints({ make in
            make.left.equalTo(SCRXFrom(19))
            make.right.equalTo(SCRXFrom(-19))
//            make.bottom.equalTo(SCRYFrom(-31))
            make.top.equalTo(self.snp.centerY).offset(SCRYFrom(8))
            make.height.equalTo(3)
        })
        
//        progressValueView.height = 1.5
        
        nameLabel.maxFontSize = FontFit(12)
        nameLabel.minFontSize = FontFit(8.5)
        nameLabel.snp.updateConstraints({ make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
//            make.bottom.equalTo(SCRYFit(-11))
            make.top.equalTo(contentView.snp.bottom).offset(SCRYFrom(-23))
//            make.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(20))
        })
    
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
