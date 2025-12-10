//
//  DeviceRatedPowerCalibrationSetAllViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/8.
//

import UIKit

class DeviceRatedPowerCalibrationSetAllViewCell: UITableViewCell {

    private var setAllNoteLabel: UILabel!
    var powerField: UITextField!
    private var unitLabel: UILabel!
    private let maxIntegerDigits = 7
    var powerEditCallback: ((String)->Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = .clear
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func powerFieldEditChanged() {
        powerEditCallback?(powerField.text ?? "")
    }
    
    private func setupUI() {
        
        setAllNoteLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 12, fontWeight: .light, fit: false)
        setAllNoteLabel.numberOfLines = 0
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 4
        setAllNoteLabel.attributedText = NSAttributedString(string: "set_all_note".localizedString, attributes: [.paragraphStyle: paragraphStyle])
        contentView.addSubview(setAllNoteLabel)
        setAllNoteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalToSuperview()
        }
        
        powerField = UITextField()
        powerField.textAlignment = .center
        powerField.textColor = ImportantText_Color
        powerField.font = UIFont.systemFont(ofSize: FontFit(12))
        powerField.layer.cornerRadius = SCRYFrom(5)
        powerField.layer.borderColor = RGB(220, 220, 220).cgColor
        powerField.layer.borderWidth = 0.5
        powerField.backgroundColor = .white
        powerField.keyboardType = .decimalPad
        powerField.returnKeyType = .done
        powerField.addTarget(self, action: #selector(powerFieldEditChanged), for: .editingChanged)
        powerField.delegate = self
        contentView.addSubview(powerField)
        powerField.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(setAllNoteLabel.snp.bottom).offset(SCRYFrom(46))
            make.width.equalTo(SCRXFrom(136))
            make.height.equalTo(SCRYFrom(36))
            make.bottom.equalToSuperview()
        }
        
        unitLabel = UILabel(text: "W", textColor: ImportantText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(unitLabel)
        unitLabel.snp.makeConstraints { make in
            make.left.equalTo(powerField.snp.right).offset(SCRXFrom(8))
            make.centerY.equalTo(powerField)
        }
        
    }
    
}

extension DeviceRatedPowerCalibrationSetAllViewCell: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
    
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
//        if !string.isPureNumandCharacters() && string != "" {
//            return false
//        }
//        return true
        
        guard let currentText = textField.text else { return true }
        
        // 允许删除操作
        if string.isEmpty { return true }
        
        // 如果已经包含小数点且尝试输入另一个小数点，拒绝
        if string == ".", currentText.contains(".") {
            return false
        }
        
        // 如果当前没有小数点且尝试输入小数点，检查整数部分长度
        if string == ".", !currentText.contains(".") {
            let integerPart = currentText
            return integerPart.count <= maxIntegerDigits
        }
        
        // 构建新文本
        let newText = (currentText as NSString).replacingCharacters(in: range, with: string)
        
        // 验证新文本是否符合数字格式
        guard newText.isValidDecimal(maxIntegerDigits: maxIntegerDigits, maxFractionDigits: 2) else {
            return false
        }
        
        return true
        
    }
    
    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        
        if let text = textField.text, let power = Double(text) {
            textField.text = String(format: "%.2f", power)
        }
        
        return true
    }
    
}
