//
//  MotionSensorInstructionsViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/27.
//

import UIKit

class MotionSensorInstructionsViewCell: UITableViewCell {

    var descriptionLabel: UILabel!
    
    var desc: String? {
        didSet {
            let paragraphStyle = NSMutableParagraphStyle()
            paragraphStyle.lineSpacing = 2
            let attStr = NSAttributedString(string: desc ?? "", attributes: [.paragraphStyle: paragraphStyle])
            descriptionLabel.attributedText = attStr
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        backgroundColor = Background_Color
        
        selectionStyle = .none
        
        descriptionLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        descriptionLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        descriptionLabel.numberOfLines = 0
        contentView.addSubview(descriptionLabel)
        descriptionLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.right.equalTo(SCRXFrom(-30))
            make.top.equalTo(SCRYFrom(7))
            make.bottom.equalTo(SCRYFrom(-10))
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
}
