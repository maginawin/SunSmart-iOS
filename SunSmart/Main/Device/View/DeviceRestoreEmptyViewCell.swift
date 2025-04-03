//
//  DeviceRestoreEmptyViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/21.
//

import UIKit

class DeviceRestoreEmptyViewCell: UITableViewCell {
    
    var titleLabel: UILabel!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        backgroundColor = .white
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "device_restore_empty_message".localizedString, textColor: Message_Color, fontSize: 14, fontWeight: .light)
        titleLabel.textAlignment = .center
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
    }
    
}
