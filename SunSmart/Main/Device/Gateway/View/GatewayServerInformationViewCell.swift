//
//  GatewayServerInformationViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

class GatewayServerInformationViewCell: UITableViewCell {

    private var serverAddressLabel: UILabel!
    var serverAddressField: UITextField!
    private var portLabel: UILabel!
    var portField: UITextField!
    private var clientIdLabel: UILabel!
    var clientIdField: UITextField!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        serverAddressLabel = UILabel(text: "server_address".localizedString, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(serverAddressLabel)
        serverAddressLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(23))
        }
        
        serverAddressField = UITextField()
        serverAddressField.backgroundColor = Background_Color
        serverAddressField.layer.borderColor = RGB(220, 220, 220).cgColor
        serverAddressField.layer.borderWidth = 0.5
        serverAddressField.textColor = Message_Color
        serverAddressField.textAlignment = .right
        serverAddressField.isEnabled = false
        contentView.addSubview(serverAddressField)
        serverAddressField.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(serverAddressLabel)
            make.height.equalTo(SCRYFrom(32))
            make.width.equalTo(SCRXFrom(156))
        }
        
        portLabel = UILabel(text: "port".localizedString, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(portLabel)
        portLabel.snp.makeConstraints { make in
            make.left.equalTo(serverAddressLabel)
            make.top.equalTo(serverAddressField.snp.bottom).offset(SCRYFrom(17))
        }
        
        portField = UITextField()
        portField.backgroundColor = Background_Color
        portField.layer.borderColor = RGB(220, 220, 220).cgColor
        portField.layer.borderWidth = 0.5
        portField.textColor = Message_Color
        portField.textAlignment = .right
        portField.isEnabled = false
        contentView.addSubview(portField)
        portField.snp.makeConstraints { make in
            make.right.equalTo(serverAddressField)
            make.centerY.equalTo(portLabel)
            make.width.height.equalTo(serverAddressField)
        }
        
        clientIdLabel = UILabel(text: "client_id".localizedString, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(clientIdLabel)
        clientIdLabel.snp.makeConstraints { make in
            make.left.equalTo(portLabel)
            make.top.equalTo(portField.snp.bottom).offset(SCRYFrom(16))
        }
        
        clientIdField = UITextField()
        clientIdField.backgroundColor = Background_Color
        clientIdField.layer.borderColor = RGB(220, 220, 220).cgColor
        clientIdField.layer.borderWidth = 0.5
        clientIdField.textColor = Message_Color
        clientIdField.textAlignment = .right
        clientIdField.isEnabled = false
        contentView.addSubview(clientIdField)
        clientIdField.snp.makeConstraints { make in
            make.right.equalTo(portField)
            make.centerY.equalTo(clientIdLabel)
            make.height.equalTo(portField)
            make.width.equalTo(SCRXFrom(248))
        }
        
    }
    
}
