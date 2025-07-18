//
//  ProfileSensitivityView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/10.
//

import UIKit

protocol ProfileSensitivityViewDelegate: AnyObject {
    
    /// 灵敏度修改
    /// - Parameters:
    ///   - view: view
    ///   - sensitivity: 灵敏度0~100%
    func view(_ view: ProfileSensitivityView, sensitivityValueChanged sensitivity: UInt8)
    
    /// 禁止交互下编辑事件
    func sensitivityViewDisableEditAction(view: ProfileSensitivityView)
    
}

class ProfileSensitivityView: UIView {

    private var titleLabel: UILabel!
    /// 滑条
    var sensitivitySlider: PowerUpLightSliderView!
    
    weak var delegate: ProfileSensitivityViewDelegate?
    
    /// 灵敏度
    var sensitivity: UInt8 = 100 {
        didSet {
            sensitivitySlider.valueLabel.text = "\(sensitivity)%"
            sensitivitySlider.slider.value = Float(sensitivity)
        }
    }
    
    /// 是否可编辑
    var editable: Bool = true {
        didSet {
            sensitivitySlider.editable = editable
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "relative_sensitivity".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
        }
        
        sensitivitySlider = PowerUpLightSliderView()
        sensitivitySlider.valueChangedCallback = {[weak self] value in
            guard let self = self else { return }
            self.sensitivitySlider.valueLabel.text = "\(value)%"
            self.delegate?.view(self, sensitivityValueChanged: UInt8(value))
        }
        sensitivitySlider.disableEditActionCallback = {[weak self] in
            guard let self = self else { return }
            self.delegate?.sensitivityViewDisableEditAction(view: self)
        }
        addSubview(sensitivitySlider)
        sensitivitySlider.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
//            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(SCRYFrom(76))
        }
        
    }
    
}
