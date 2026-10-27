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
    
    /// 帮助
    func sensitivityViewHelpAction(_ view: ProfileSensitivityView)
    
}

class ProfileSensitivityView: UIView {

    private var titleLabel: UILabel!
    /// 滑条
    var sensitivitySlider: PowerUpLightSliderView!
    private var helpBtn: UIButton!
    private var lackSensitivityLabel: UILabel!
    
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
    
    /// 是否显示部分设备缺少灵敏度提示
    var showLackSensitivityNotice: Bool = false {
        didSet {
            lackSensitivityLabel.isHidden = !showLackSensitivityNotice
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
    
    @objc private func helpBtnAction() {
        delegate?.sensitivityViewHelpAction(self)
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "relative_sensitivity".localizedString, textColor: TextBlack_Color, fontSize: 16, fontWeight: .light)
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        titleLabel.setContentHuggingPriority(.required, for: .horizontal)
        titleLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        
        helpBtn = UIButton(normalImageName: "help", target: self, action: #selector(helpBtnAction))
        helpBtn.setContentCompressionResistancePriority(.required, for: .horizontal)
        helpBtn.setContentHuggingPriority(.required, for: .horizontal)
        helpBtn.setContentCompressionResistancePriority(.required, for: .vertical)
        
        lackSensitivityLabel = UILabel(text: "profile_some_devices_lack_sensitivity".localizedString, textColor: RGB(255, 167, 44), fontSize: 12, fontWeight: .regular, fit: false)
        lackSensitivityLabel.textAlignment = .right
        lackSensitivityLabel.numberOfLines = 0
        lackSensitivityLabel.isHidden = true
        lackSensitivityLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        lackSensitivityLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        lackSensitivityLabel.setContentCompressionResistancePriority(.required, for: .vertical)

        // 提示换行时撑高标题行；隐藏时由 stack 自动移除其占位。
        let spacer = UIView()
        let headerView = UIStackView(arrangedSubviews: [titleLabel, helpBtn, spacer, lackSensitivityLabel])
        headerView.axis = .horizontal
        headerView.alignment = .center
        headerView.spacing = SCRXFrom(8)
        headerView.setCustomSpacing(0, after: spacer)
        addSubview(headerView)
        spacer.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(0)
            make.height.equalTo(0)
        }
        headerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
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
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(8))
            make.bottom.equalTo(SCRYFrom(-16))
            make.height.equalTo(SCRYFrom(76))
        }
        
    }
    
}
