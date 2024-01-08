//
//  SyncDevicesTitleHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit

class SyncDevicesTitleHeaderView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
     
        
        backgroundView = UIView()
         
        contentView.backgroundColor = Background_Color
        
        
        titleLabel = UILabel(text: "Remove", textColor: RGB(100, 136, 139), fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.bottom.equalTo(SCRYFrom(-8))
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
}
