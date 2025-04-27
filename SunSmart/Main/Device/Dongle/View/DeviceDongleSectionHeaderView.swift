//
//  DeviceDongleSectionHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

class DeviceDongleSectionHeaderView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    var contentLabel: UILabel!
    
    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        contentLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(contentLabel)
        contentLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.bottom.equalTo(titleLabel)
        }
    }
    
}
