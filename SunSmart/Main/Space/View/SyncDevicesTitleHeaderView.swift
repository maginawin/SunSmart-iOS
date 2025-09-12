//
//  SyncDevicesTitleHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/27.
//

import UIKit

class SyncDevicesTitleHeaderView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    
    var titleLeftMargin: CGFloat = SCRXFrom(20) {
        didSet {
            titleLabel.snp.updateConstraints { make in
                make.left.equalTo(titleLeftMargin)
            }
        }
    }
    
    var bottomMargin: CGFloat = SCRYFrom(8) {
        didSet {
            titleLabel.snp.updateConstraints { make in
                make.bottom.equalTo(-bottomMargin)
            }
        }
    }
    
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
     
        
        backgroundView = UIView()
         
        contentView.backgroundColor = .clear
        
        
        titleLabel = UILabel(text: "Remove", textColor: RGB(100, 136, 139), fontSize: 14, fontWeight: .light)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLeftMargin)
            make.bottom.equalTo(-bottomMargin)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    
}
