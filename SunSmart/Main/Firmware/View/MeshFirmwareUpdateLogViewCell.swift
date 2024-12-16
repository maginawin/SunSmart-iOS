//
//  MeshFirmwareUpdateLogViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/12/9.
//

import UIKit

class MeshFirmwareUpdateLogViewCell: UITableViewCell {

    var logLabel: UILabel!
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        logLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 13, fontWeight: .light, fit: false)
        logLabel.numberOfLines = 0
        contentView.addSubview(logLabel)
        logLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(1.5))
            make.bottom.equalTo(SCRYFrom(-1.5))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
