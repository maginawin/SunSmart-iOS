//
//  MeshFirmwareUpgradeSectionView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/4.
//

import UIKit

class MeshFirmwareUpgradeSectionView: UITableViewHeaderFooterView {

    private var messageView: UIView!
    var messageLabel: UILabel!
    private var nameLabel: UILabel!
    private var firmwareVersionLabel: UILabel!
    private var deviceVersionLabel: UILabel!

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        messageView = UIView()
        messageView.backgroundColor = .white
        messageView.layer.cornerRadius = SCRYFrom(10)
        addSubview(messageView)
        messageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(SCRYFrom(3))
            make.height.equalTo(SCRYFrom(32))
        }
        
        messageLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 13, fontWeight: .light, fit: false)
        messageView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(40))
            make.right.equalTo(SCRXFrom(-40))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "name".localizedString, textColor: .black, fontSize: 13, fontWeight: .light)
        addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(78))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        firmwareVersionLabel = UILabel(text: "firmware_package".localizedString, textColor: .black, fontSize: 13, fontWeight: .light)
        addSubview(firmwareVersionLabel)
        firmwareVersionLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview().offset(SCRXFrom(12.5))
            make.centerY.equalTo(nameLabel)
        }
        
        deviceVersionLabel = UILabel(text: "device_version".localizedString, textColor: .black, fontSize: 13, fontWeight: .light)
        addSubview(deviceVersionLabel)
        deviceVersionLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(firmwareVersionLabel)
        }
        
    }
    
}
