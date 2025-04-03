//
//  DeviceAddResultView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/21.
//

import UIKit

class DeviceAddResultView: UIView {

    var addResultLabel: UILabel!
    var successCountLabel: UILabel!
    var failedLabel: UILabel!
    var failedCountLabel: UILabel!
    
    var syncFailedLabel: UILabel!
    var syncFailedCountLabel: UILabel!
    
    var closeBtn: UIButton!
    var stopAddBtn: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(8)
        layer.shadowColor = RGB(0, 0, 0, 0.1).cgColor
        layer.shadowOffset = CGSizeMake(0,-2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 6
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        addResultLabel = UILabel(text: "add_result".localizedString, textColor: TextBlack_Color, fontSize: 16)
        addSubview(addResultLabel)
        addResultLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(14))
        }
        
        successCountLabel = UILabel(text: "\("successfully".localizedString) : 0", textColor: Message_Color, fontSize: 14)
        addSubview(successCountLabel)
        successCountLabel.snp.makeConstraints { make in
            make.left.equalTo(addResultLabel)
            make.bottom.equalTo(SCRYFrom(-14))
        }
        
        failedLabel = UILabel(text: "failed".localizedString + " : ", textColor: Message_Color, fontSize: 14)
        addSubview(failedLabel)
        failedLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(141))
            make.centerY.equalTo(successCountLabel)
        }
        
        failedCountLabel = UILabel(text: "0", textColor: Red_Color, fontSize: 14)
        addSubview(failedCountLabel)
        failedCountLabel.snp.makeConstraints { make in
            make.left.equalTo(failedLabel.snp.right)
            make.centerY.equalTo(failedLabel)
        }
        
        syncFailedLabel = UILabel(text: "sync_failed".localizedString + " : ", textColor: Message_Color, fontSize: 14)
        syncFailedLabel.isHidden = true
        addSubview(syncFailedLabel)
        syncFailedLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(226))
            make.centerY.equalTo(successCountLabel)
        }
        
        syncFailedCountLabel = UILabel(text: "0", textColor: Red_Color, fontSize: 14)
        syncFailedCountLabel.isHidden = true
        addSubview(syncFailedCountLabel)
        syncFailedCountLabel.snp.makeConstraints { make in
            make.left.equalTo(syncFailedLabel.snp.right)
            make.centerY.equalTo(syncFailedLabel)
        }
        
        closeBtn = UIButton(normalImageName: "close")
        addSubview(closeBtn)
        closeBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-4))
            make.top.equalTo(SCRYFrom(4))
        }
        
        stopAddBtn = UIButton(title: "stop_waiting".localizedString, titleSize: 14, titleColor: Red_Color)
        stopAddBtn.titleLabel?.font = Font_Medium_Size(SCRYFrom(14))
        stopAddBtn.isHidden = true
        stopAddBtn.layer.cornerRadius = SCRYFrom(5)
        stopAddBtn.layer.borderWidth = 1
        stopAddBtn.layer.borderColor = Red_Color.cgColor
        stopAddBtn.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(11), bottom: 0, right: SCRXFrom(11))
        addSubview(stopAddBtn)
        stopAddBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(32))
        }
        
    }

}
