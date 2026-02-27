//
//  DeviceParameterSettingsViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/14.
//

import UIKit

protocol DeviceParameterSettingsViewCellDelegate: AnyObject {
    
    /// 设置参数
    func cell(_ cell: DeviceParameterSettingsViewCell, settingParameters data: DeviceParameterData)
    
    /// 修改启用/禁用开关
    func cell(_ cell: DeviceParameterSettingsViewCell, parameterEnableStateChanged enable: Bool)
    
}

class DeviceParameterSettingsViewCell: UITableViewCell {

    private var containerView: UIView!
    var titleLabel: UILabel!
    var textField: UITextField!
    var unitLabel: UILabel!
    var messageLabel: UILabel!
    var enableSwitch: UISwitch!
    weak var delegate: DeviceParameterSettingsViewCellDelegate?
    
    var parameterData: DeviceParameterData! {
        didSet {
            
            let data = parameterData.type.data
            titleLabel.text = data.title
            
            enableSwitch.isOn = parameterData.enable
            
            messageLabel.isHidden = false
            textField.isHidden = false
            unitLabel.isHidden = false
            messageLabel.isHidden = false
            
            messageLabel.text = data.message
            if let range = data.range {
                textField.placeholder = "\(range.lowerBound)~\(range.upperBound)"
            }else {
                textField.placeholder = nil
            }
            if let value = parameterData.data as? Int {
                textField.text = "\(value)"
            }else {
                textField.text = nil
            }
            unitLabel.text = data.unit
            
            updateParameterEnable(enable: parameterData.enable)
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = .clear
        selectionStyle = .none
//        layer.cornerRadius = SCRYFrom(10)
//        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func updateParameterEnable(enable: Bool) {
        enableSwitch.isOn = enable
        if enable {
            
            messageLabel.isHidden = false
            textField.isHidden = false
            unitLabel.isHidden = false
            messageLabel.isHidden = false
            
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
            }
            
            messageLabel.snp.remakeConstraints { make in
                make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10)).priority(.high)
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.bottom.equalTo(SCRYFrom(-22)).priority(.high)
            }
        }else {
            
            messageLabel.isHidden = true
            textField.isHidden = true
            unitLabel.isHidden = true
            messageLabel.isHidden = true
            
            titleLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.top.equalTo(SCRYFrom(24)).priority(.high)
                make.bottom.equalTo(SCRYFrom(-23))
            }
            
            messageLabel.snp.remakeConstraints { make in
                make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10)).priority(.high)
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            
        }
    }
    
    @objc private func enableSwitchValueChanged(sender: UISwitch) {
        updateParameterEnable(enable: sender.isOn)
        
        delegate?.cell(self, parameterEnableStateChanged: sender.isOn)
    }
    
    private func setupUI() {
        
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(24)).priority(.high)
        }
        
        enableSwitch = UISwitch()
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.addTarget(self, action: #selector(enableSwitchValueChanged), for: .valueChanged)
        containerView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
        
        textField = UITextField()
        textField.font = UIFont.systemFont(ofSize: SCRYFrom(13), weight: .light)
//        textField.placeholder = "password".localizedString
        textField.textColor = TextBlack_Color
        textField.layer.cornerRadius = SCRYFrom(5)
        textField.layer.borderColor = RGB(220, 220, 220).cgColor
        textField.layer.borderWidth = 0.6
        textField.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 12, height: 0))
        textField.leftViewMode = .always
        textField.textAlignment = .center
        textField.backgroundColor = Background_Color
        textField.delegate = self
        containerView.addSubview(textField)
        textField.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(16)).priority(.high)
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(96))
            make.height.equalTo(SCRYFrom(32))
        }
        
        unitLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        containerView.addSubview(unitLabel)
        unitLabel.snp.makeConstraints { make in
            make.left.equalTo(textField.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(textField).offset(SCRYFrom(1))
        }
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        containerView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10)).priority(.high)
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-22))
        }
        
    }
    
}

extension DeviceParameterSettingsViewCell: UITextFieldDelegate {
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        delegate?.cell(self, settingParameters: parameterData)
        return false
    }
    
}

protocol DeviceParameterBehaviorAfterSetupViewCellDelegate: AnyObject {
    func cell(_ cell: DeviceParameterBehaviorAfterSetupViewCell, didSelect mode: DeviceBlinkMode)
    func cell(_ cell: DeviceParameterBehaviorAfterSetupViewCell, detailsExpandedChanged expanded: Bool)
}

class DeviceParameterBehaviorAfterSetupViewCell: UITableViewCell {
   
    
    private var containerView: UIView!
    private var titleLabel: UILabel!
    private var optionButtons: [UIButton] = []
    private var detailsRow: UIControl!
    private var detailsTitleLabel: UILabel!
    private var detailsArrowImageView: UIImageView!
    private var noteLabel: UILabel!
    
    weak var delegate: DeviceParameterBehaviorAfterSetupViewCellDelegate?
    
    var selectedMode: DeviceBlinkMode = .breathing {
        didSet {
            updateOptionUI()
        }
    }
    
    var detailsExpanded: Bool = true {
        didSet {
            updateDetailsUI()
        }
    }
    
    func configure(mode: DeviceBlinkMode, detailsExpanded: Bool, noteText: String? = nil) {
        selectedMode = mode
        self.detailsExpanded = detailsExpanded
        if let noteText = noteText {
            noteLabel.text = noteText
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        backgroundColor = .clear
        setupUI()
        updateOptionUI()
        updateDetailsUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func optionTapped(_ sender: UIButton) {
        guard sender.tag < DeviceBlinkMode.modes.count else { return }
        let mode = DeviceBlinkMode.modes[sender.tag]
//        guard selectedMode != mode else { return }
        selectedMode = mode
        delegate?.cell(self, didSelect: mode)
    }
    
    @objc private func detailsRowTapped() {
        detailsExpanded.toggle()
        delegate?.cell(self, detailsExpandedChanged: detailsExpanded)
    }
    
    private func updateOptionUI() {
        optionButtons.enumerated().forEach { index, button in
            let isSelected = DeviceBlinkMode.modes[index] == selectedMode
            button.backgroundColor = isSelected ? Bar_Color : Background_Color
            button.setTitleColor(isSelected ? .white : AssistText_Color, for: .normal)
        }
    }
    
    private func updateDetailsUI() {
        noteLabel.isHidden = !detailsExpanded
        detailsTitleLabel.text = detailsExpanded ? "hide_details".localizedString : "show_details".localizedString
        detailsArrowImageView.image = UIImage(named: detailsExpanded ? "arrow_up_black" : "arrow_down_black")
        
        detailsRow.snp.remakeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(56))
            make.height.equalTo(SCRYFrom(30))
            if !detailsExpanded {
                make.bottom.equalTo(SCRYFrom(-16))
            }
        }
        detailsArrowImageView.snp.remakeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        detailsTitleLabel.snp.remakeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalToSuperview()
            make.right.lessThanOrEqualTo(detailsArrowImageView.snp.left).offset(SCRXFrom(-8))
        }
        
        if detailsExpanded {
            noteLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(detailsRow.snp.bottom).offset(SCRYFrom(8))
                make.bottom.equalTo(SCRYFrom(-16))
            }
        } else {
            noteLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(detailsRow.snp.bottom).offset(SCRYFrom(8))
            }
        }
    }
    
    private func setupUI() {
        containerView = UIView()
        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
            make.bottom.equalTo(SCRYFrom(-16))
        }
        
        titleLabel = UILabel(
            text: "\("behavior_after_setup_success".localizedString):",
            textColor: TextBlack_Color,
            fontSize: 14,
            fontWeight: .light
        )
        containerView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
            make.right.equalTo(SCRXFrom(-16))
        }
        
        var previousBtn: UIButton?
        for (index, mode) in DeviceBlinkMode.modes.enumerated() {
            let button = UIButton(type: .custom)
            button.tag = index
            button.layer.cornerRadius = SCRYFrom(10)
            button.clipsToBounds = true
            button.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(13))
            button.contentEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(7), bottom: 0, right: SCRXFrom(7))
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.75
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.lineBreakMode = .byClipping
            button.setTitle(mode.title, for: .normal)
            button.addTarget(self, action: #selector(optionTapped(_:)), for: .touchUpInside)
            containerView.addSubview(button)
            button.snp.makeConstraints { make in
                make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(12))
                make.height.equalTo(SCRYFrom(32))
                if let prev = previousBtn {
                    make.left.equalTo(prev.snp.right).offset(SCRXFrom(12))
                    make.width.equalTo(prev)
                } else {
                    make.left.equalTo(SCRXFrom(16))
                }
                if index == DeviceBlinkMode.modes.count - 1 {
                    make.right.equalTo(SCRXFrom(-16))
                }
            }
            optionButtons.append(button)
            previousBtn = button
        }
        
        detailsRow = UIControl()
        detailsRow.addTarget(self, action: #selector(detailsRowTapped), for: .touchUpInside)
        containerView.addSubview(detailsRow)
        
        detailsTitleLabel = UILabel(
            text: "hide_details".localizedString,
            textColor: Bar_Color,
            fontSize: 12,
            fontWeight: .regular
        )
        detailsRow.addSubview(detailsTitleLabel)
        
        detailsArrowImageView = UIImageView()
        detailsArrowImageView.contentMode = .scaleAspectFit
        detailsArrowImageView.tintColor = Bar_Color
        detailsRow.addSubview(detailsArrowImageView)
        
        noteLabel = UILabel(
            text: nil,
            textColor: AssistText_Color,
            fontSize: 12,
            fontWeight: .light,
            fit: false
        )
        noteLabel.numberOfLines = 0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        paragraphStyle.lineBreakMode = .byWordWrapping
        noteLabel.attributedText = NSAttributedString(string: "behavior_after_setup_success_note".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        containerView.addSubview(noteLabel)
    }
}
