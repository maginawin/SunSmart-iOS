//
//  DeviceAddSectionBackgroundView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/9/2.
//

import UIKit

class DeviceAddSectionBackgroundView: UIView {

    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.borderWidth = 1
        layer.borderColor = RGB(0, 0, 0, 0.1).cgColor
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .clear
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
