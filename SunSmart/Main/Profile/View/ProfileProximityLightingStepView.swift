//
//  ProfileProximityLightingStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/14.
//

import UIKit

class ProfileProximityLightingStepView: UIView {

    var messageLabel: UILabel!
    var stepView: GroupPathSequenceDeviceAddStepView!
    
    var message: String? {
        didSet {
            guard let string = message else {
                messageLabel.attributedText = nil
                return
            }
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 4
            paragraphStyle.alignment = .center
            messageLabel.attributedText = NSAttributedString(string: string, attributes: [.paragraphStyle: paragraphStyle])
        }
    }
    
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
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light, fit: false)
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.alignment = .center
        messageLabel.attributedText = NSAttributedString(string: "profile_predictive_lighting_message".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-8))
            make.top.equalTo(SCRYFrom(12))
        }
        
        stepView = GroupPathSequenceDeviceAddStepView(frame: .zero, steps: [
            .init(imageName: "proximity_lighting_step1", title: "save_profile".localizedString, textColor: TextBlack_Color),
            .init(imageName: "proximity_lighting_step2", title: "add_devices_to_the_group".localizedString, textColor: TextBlack_Color),
            .init(imageName: "proximity_lighting_step3", title: "set_the_path_sequence".localizedString, textColor: TextBlack_Color)
        ])
        addSubview(stepView)
        stepView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(messageLabel.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(SCRYFrom(56))
        }
    }
    
    
}
