//
//  GatewayNameViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

class GatewayNameViewCell: UITableViewCell {

    var nameField: UITextField!
    var tipTextLabel: UILabel!
    var nameEditChangedCallback: ((String)->String?)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        nameField = UITextField()
        nameField.textColor = TextBlack_Color
        nameField.font = UIFont.systemFont(ofSize: 14)
        nameField.clearButtonMode = .whileEditing
        nameField.rightViewMode = .whileEditing
        nameField.returnKeyType = .done
        nameField.addTarget(self, action: #selector(nameFieldEditChanged), for: .editingChanged)
        nameField.delegate = self
        contentView.addSubview(nameField)
        nameField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-6))
            make.top.bottom.equalToSuperview()
        }
        
        tipTextLabel = UILabel(text: nil, textColor: Red_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(tipTextLabel)
        tipTextLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(nameField.snp.bottom)
            make.right.equalTo(SCRXFrom(-24))
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func nameFieldEditChanged() {
        let tipText = nameEditChangedCallback?(nameField.text ?? "")
        tipTextLabel.text = tipText
    }
    
}

extension GatewayNameViewCell: UITextFieldDelegate {
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endEditing(true)
        return true
    }
    
}
