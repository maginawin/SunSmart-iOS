//
//  DeviceForceResetStepView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/16.
//

import UIKit

protocol DeviceForceResetStepViewDelegate: AnyObject {
    
    /// 开始事件
    func resetStepViewStartAction(_ view: DeviceForceResetStepView)
    
    /// 参数选择事件
    func resetStepViewSelectParameterAction(_ view: DeviceForceResetStepView)
    
}

class DeviceForceResetStepView: UIView {

    var titleLabel: UILabel!
    var noteLabel: UILabel!
    var stepView: GroupPathSequenceDeviceAddStepView!
    var startBtn: UIButton!
    var parameterBtn: UIButton!
    var settingsTipView: UIView!
    weak var delegate: DeviceForceResetStepViewDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.cornerRadius = SCRYFrom(10)
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func startBtnAction() {
        
        delegate?.resetStepViewStartAction(self)
    }
    
    @objc private func parameterBtnAction() {
        
        delegate?.resetStepViewSelectParameterAction(self)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "safe_mode".localizedString, textColor: ImportantText_Color, fontSize: 14)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(16))
        }
        
        noteLabel = UILabel(text: nil, textColor: ImportantText_Color, fontSize: 12, fontWeight: .light)
        noteLabel.numberOfLines = 0
        noteLabel.textAlignment = .center
        addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14))
            make.right.equalTo(SCRXFrom(-14))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
        }
        
        stepView = GroupPathSequenceDeviceAddStepView(frame: .zero, steps: [])
        addSubview(stepView)
        stepView.snp.makeConstraints { make in
//            if isIPad {
//                make.left.equalTo(SCRXFrom(100))
//                make.right.equalTo(SCRXFrom(-100))
//            }else {
                make.left.equalTo(SCRXFrom(14))
                make.right.equalTo(SCRXFrom(-14))
//            }
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(16))
            make.height.greaterThanOrEqualTo(SCRYFrom(56))
        }
//        stepView.step1View.snp.updateConstraints { make in
//            make.top.equalTo(stepView.step2View)
//        }
        
        startBtn = UIButton(title: "START".localizedString, titleSize: 16, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(startBtnAction))
        startBtn.layer.cornerRadius = SCRYFrom(10)
        startBtn.layer.borderColor = Bar_Color.cgColor
        startBtn.layer.borderWidth = 0.5
        addSubview(startBtn)
        startBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(180))
            make.height.equalTo(SCRYFrom(32))
            make.top.equalTo(stepView.snp.bottom).offset(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-27))
        }
        
        parameterBtn = UIButton(normalImageName: "device_parameter", target: self, action: #selector(parameterBtnAction))
        addSubview(parameterBtn)
        parameterBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-20))
            make.centerY.equalTo(startBtn)
        }
        
        settingsTipView = UIView()
        settingsTipView.layer.cornerRadius = 2.5
        settingsTipView.backgroundColor = RGB(255, 167, 44)
        settingsTipView.isUserInteractionEnabled = false
        settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        parameterBtn.addSubview(settingsTipView)
        settingsTipView.snp.makeConstraints { make in
            make.right.equalTo(-8.5)
            make.centerY.equalToSuperview().offset(0.5)
            make.width.height.equalTo(5)
        }
        
    }
    
}
