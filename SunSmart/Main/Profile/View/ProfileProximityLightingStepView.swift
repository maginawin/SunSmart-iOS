//
//  ProfileProximityLightingStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/14.
//

import UIKit

class ProfileProximityLightingStepView: UIView {

    private var messageLabel: UILabel!
    private var step1Btn: UIButton!
    private var step2Btn: UIButton!
    private var step3Btn: UIButton!
    private var step1LineView: UIView!
    private var step2LineView: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(5)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        messageLabel = UILabel(text: "profile_predictive_lighting_message".localizedString, textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(12))
        }
        
        step2Btn = UIButton(title: "add_devices_to_the_group".localizedString, titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "proximity_lighting_step2")
        step2Btn.isUserInteractionEnabled = false
        step2Btn.titleLabel?.numberOfLines = 2
        step2Btn.titleLabel?.textAlignment = .center
        step2Btn.sizeToFit()
        step2Btn.setImagePosition(position: .top, spacing: SCRYFrom(8))
        addSubview(step2Btn)
        step2Btn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
        step1Btn = UIButton(title: "save_profile".localizedString, titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "proximity_lighting_step1")
        step1Btn.isUserInteractionEnabled = false
        step1Btn.titleLabel?.numberOfLines = 2
        step1Btn.titleLabel?.textAlignment = .center
        step1Btn.sizeToFit()
        step1Btn.setImagePosition(position: .top, spacing: SCRYFrom(8))
        addSubview(step1Btn)
        step1Btn.snp.makeConstraints { make in
            make.right.equalTo(step2Btn.snp.left).offset(SCRXFrom(-38))
            make.top.equalTo(step2Btn).offset(SCRYFrom(3))
        }
        
        step1LineView = UIView()
        step1LineView.backgroundColor = AssistText_Color
        addSubview(step1LineView)
        step1LineView.snp.makeConstraints { make in
            make.left.equalTo(step1Btn.snp.right).offset(SCRXFrom(3))
            make.right.equalTo(step2Btn.snp.left).offset(SCRXFrom(-5))
            make.top.equalTo(step2Btn).offset(10)
            make.height.equalTo(1)
        }
        
        step3Btn = UIButton(title: "set_the_path_sequence".localizedString, titleSize: 12, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "proximity_lighting_step3")
        step3Btn.isUserInteractionEnabled = false
        step3Btn.titleLabel?.numberOfLines = 2
        step3Btn.titleLabel?.textAlignment = .center
        step3Btn.sizeToFit()
        step3Btn.setImagePosition(position: .top, spacing: SCRYFrom(8))
        addSubview(step3Btn)
        step3Btn.snp.makeConstraints { make in
            make.left.equalTo(step2Btn.snp.right).offset(SCRXFrom(38))
            make.centerY.equalTo(step2Btn)
        }
        
        step2LineView = UIView()
        step2LineView.backgroundColor = AssistText_Color
        addSubview(step2LineView)
        step2LineView.snp.makeConstraints { make in
            make.left.equalTo(step2Btn.snp.right).offset(SCRXFrom(-5))
            make.right.equalTo(step3Btn.snp.left).offset(SCRXFrom(2))
            make.top.height.equalTo(step1LineView)
        }
    }
    
    
}
