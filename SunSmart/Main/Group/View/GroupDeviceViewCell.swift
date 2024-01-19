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
            if device.needSync {
                iconImageView.image = UIImage(named: "device_light_unsync")
            }
            
            if device.isKeybindComplete {
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
        
        iconImageView.snp.updateConstraints { make in
            make.top.equalTo(SCRYFrom(10))
            make.width.height.equalTo(SCRXFrom(30))
        }
        
//        progressBgView.layer.cornerRadius = 3
//        progressBgView.layer.masksToBounds = true
//        progressValueView.layer.cornerRadius = 3
        
//        lightnessProgressView.layer.masksToBounds = true
        
        progressView.snp.remakeConstraints({ make in
            make.left.equalTo(SCRXFrom(19))
            make.right.equalTo(SCRXFrom(-19))
//            make.bottom.equalTo(SCRYFrom(-31))
            make.top.equalTo(self.snp.centerY).offset(SCRYFrom(8))
            make.height.equalTo(1.5)
        })
        
//        progressValueView.height = 1.5
        
        nameLabel.font = FONTS(SCRYFrom(10.5))
        nameLabel.snp.updateConstraints({ make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFit(-11))
        })
    
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
