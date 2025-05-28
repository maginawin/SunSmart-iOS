//
//  ProfileProximityLightingStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/14.
//

import UIKit

class ProfileProximityLightingStepView: UIView {

    private var messageLabel: UILabel!
    private var stepView: GroupPathSequenceDeviceAddStepView!
//    private var step1Btn: UIButton!
//    private var step2Btn: UIButton!
//    private var step3Btn: UIButton!
//    private var step1LineView: UIView!
//    private var step2LineView: UIView!
    
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
        
        stepView = GroupPathSequenceDeviceAddStepView()
        stepView.step1View.titleLabel.text = "save_profile".localizedString
        stepView.step1View.titleLabel.textColor = TextBlack_Color
        stepView.step2View.titleLabel.text = "add_devices_to_the_group".localizedString
        stepView.step2View.titleLabel.textColor = TextBlack_Color
        stepView.step3View.titleLabel.text = "set_the_path_sequence".localizedString
        stepView.step3View.titleLabel.textColor = TextBlack_Color
        addSubview(stepView)
        stepView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(SCRYFrom(56))
        }
    }
    
    
}
