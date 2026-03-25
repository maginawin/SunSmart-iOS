//
//  DeviceParameterTitleHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/5.
//

import UIKit

class DeviceParameterTitleHeaderView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    
    var bottomMargin: CGFloat = SCRYFrom(8) {
        didSet {
            titleLabel.snp.updateConstraints { make in
                make.bottom.equalTo(-bottomMargin)
            }
        }
    }

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 15)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.equalTo(-bottomMargin)
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
