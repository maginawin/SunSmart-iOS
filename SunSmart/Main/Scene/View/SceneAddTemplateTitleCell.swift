//
//  SceneAddTemplateTitleCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/20.
//

import UIKit

class SceneAddTemplateTitleCell: UITableViewCell {

    var titleLabel: UILabel!
    var lineView: UIView!
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(32))
            make.centerY.equalToSuperview().offset(0.5)
        }
        
        lineView = UIView()
        lineView.backgroundColor = RGB(243, 243, 243)
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.bottom.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
