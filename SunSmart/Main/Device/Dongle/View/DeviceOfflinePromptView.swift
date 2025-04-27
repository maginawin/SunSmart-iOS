//
//  DeviceOfflinePromptView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

class DeviceOfflinePromptView: UIView {

    private var offlineBtn: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = Background_Color
        layer.cornerRadius = SCRYFrom(13)
        layer.borderWidth = 0.5
        layer.borderColor = RGB(220, 220, 220).cgColor
        
        offlineBtn = UIButton(title: "device_offline_message".localizedString, titleSize: 14, titleWeight: .light, titleColor: Red_Color, normalImageName: "schedule_sync_failed")
        offlineBtn.isUserInteractionEnabled = false
        offlineBtn.setImagePosition(position: .left, spacing: SCRXFrom(8))
        addSubview(offlineBtn)
        offlineBtn.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
