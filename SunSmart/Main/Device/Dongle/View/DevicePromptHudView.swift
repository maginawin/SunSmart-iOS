//
//  DevicePromptHudView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

class DevicePromptHudView: UIView {

    var promptLabel: UILabel!
    private var closeBtn: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = RGB(149, 150, 151)
        layer.cornerRadius = SCRYFrom(13)
        layer.shadowColor = RGB(0, 0, 0, 0.15).cgColor
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 6
        
        promptLabel = UILabel(text: "Please note that energy consumption collection is disabled by default.", textColor: .white, fontSize: 15, fontWeight: .light, fit: false)
        promptLabel.numberOfLines = 0
        promptLabel.textAlignment = .center
        addSubview(promptLabel)
        promptLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.right.equalTo(SCRXFrom(-24))
            make.top.equalTo(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-12))
        }
        
        closeBtn = UIButton(normalImageName: "close", target: self, action: #selector(closeBtnAction))
        addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.centerX.equalTo(self.snp.right)
            make.centerY.equalTo(self.snp.top)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func closeBtnAction() {
        self.removeFromSuperview()
    }
    
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        var result = super.point(inside: point, with: event)
        if !result {
            // 判断是否在关闭按键点击范围内
            if point.x <= self.frame.maxX + closeBtn.width * 0.5 && point.y >= -closeBtn.height * 0.5 {
                result = true
            }
        }
        return result
    }
        
        
}
