//
//  DeviceParameterSettingsViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/14.
//

import UIKit

protocol DeviceParameterSettingsViewCellDelegate: AnyObject {
    
    /// 设置参数
    func cell(_ cell: DeviceParameterSettingsViewCell, settingParameters type: DeviceParameterSettingsController.ParameterType)
    
}

class DeviceParameterSettingsViewCell: UITableViewCell {

    private var bgView: UIView!
    var titleLabel: UILabel!
    var textField: UITextField!
    var unitLabel: UILabel!
    var messageLabel: UILabel!
    weak var delegate: DeviceParameterSettingsViewCellDelegate?
    
    var parameterType: DeviceParameterSettingsController.ParameterType! {
        didSet {
            let data = parameterType.data
            titleLabel.text = data.title
            messageLabel.text = data.message
            if let range = data.range {
                textField.placeholder = "\(range.lowerBound)~\(range.upperBound)"
            }else {
                textField.placeholder = nil
            }
            if let value = data.value {
                textField.text = "\(value)"
            }else {
                textField.text = nil
            }
            unitLabel.text = data.unit
        }
    }
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        bgView = UIView()
        bgView.backgroundColor = .white
        bgView.layer.cornerRadius = SCRYFrom(10)
        contentView.addSubview(bgView)
        bgView.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRXFrom(-16))
        }
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        bgView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(20))
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
        textField.backgroundColor = Background_Color
        textField.delegate = self
        bgView.addSubview(textField)
        textField.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(20))
            make.right.equalTo(SCRXFrom(-39))
            make.width.equalTo(SCRXFrom(96))
            make.height.equalTo(SCRYFrom(32))
        }
        
        unitLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light)
        bgView.addSubview(unitLabel)
        unitLabel.snp.makeConstraints { make in
            make.left.equalTo(textField.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(textField).offset(SCRYFrom(1))
        }
        
        messageLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        bgView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(textField.snp.bottom).offset(SCRYFrom(10))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-22))
        }
        
    }
    
}

extension DeviceParameterSettingsViewCell: UITextFieldDelegate {
    
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        delegate?.cell(self, settingParameters: parameterType)
        return false
    }
    
}
