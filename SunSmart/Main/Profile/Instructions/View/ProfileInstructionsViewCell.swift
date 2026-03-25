//
//  ProfileInstructionsViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/2/27.
//

import UIKit

class ProfileInstructionsViewCell: UITableViewCell {

    private var guideImageView: UIImageView!
    private var descLabel: UILabel!
    private var requiredLabel: UILabel!
    private var requiredView: UIView!
    private var requiredItems: [UIButton] = []
    
    var type: Profile.ProfileType! {
        didSet {
            let data = type.instruction
            let image = UIImage(named: data.imageName)
            guideImageView.image = image
            
            guideImageView.snp.remakeConstraints({ make in
                if isIPad {
                    make.top.equalTo(SCRYFrom(12))
                    make.centerX.equalToSuperview()
                    make.width.equalTo(SCRXFrom(343))
                }else {
                    make.left.equalTo(SCRXFrom(16))
                    make.right.equalTo(SCRXFrom(-16))
                    make.top.equalTo(SCRYFrom(8))
                }
                if let image = image {
                    make.height.equalTo(guideImageView.snp.width).multipliedBy(image.size.height / image.size.width)
                }else {
                    make.height.equalTo(guideImageView.snp.width).multipliedBy(138 / 343.0)
                }
            })
            
            
//            let paragraphStyle = NSMutableParagraphStyle()
//            paragraphStyle.lineSpacing = 2
//            let attStr = NSAttributedString(string: data.description, attributes: [.paragraphStyle: paragraphStyle])
            descLabel.attributedText = data.descriptionAttStr
            
            setupRequiredItems()
        }
    }
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        backgroundColor = Background_Color
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        guideImageView = UIImageView()
        contentView.addSubview(guideImageView)
        guideImageView.snp.makeConstraints { make in
            if isIPad {
                make.top.equalTo(SCRYFrom(12))
                make.centerX.equalToSuperview()
                make.width.equalTo(SCRXFrom(343))
            }else {
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
                make.top.equalTo(SCRYFrom(8))
            }
            make.height.equalTo(guideImageView.snp.width).multipliedBy(138 / 343.0)
        }
        
        descLabel = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        descLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        descLabel.numberOfLines = 0
        contentView.addSubview(descLabel)
        descLabel.snp.makeConstraints { make in
            make.left.equalTo(guideImageView).offset(SCRXFrom(16))
            make.right.equalTo(guideImageView).offset(SCRXFrom(-16))
            make.top.equalTo(guideImageView.snp.bottom).offset(SCRYFrom(8))
        }
        
        requiredLabel = UILabel(text: "profile_required_title".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(requiredLabel)
        requiredLabel.snp.makeConstraints { make in
            make.left.equalTo(descLabel)
            make.top.equalTo(descLabel.snp.bottom).offset(SCRYFrom(8))
        }
        
        requiredView = UIView()
        contentView.addSubview(requiredView)
        requiredView.snp.makeConstraints { make in
            make.left.equalTo(requiredLabel).offset(SCRXFrom(6))
            make.top.equalTo(requiredLabel.snp.bottom).offset(SCRYFrom(10))
            make.right.equalTo(descLabel)
            make.bottom.equalToSuperview().offset(SCRYFrom(-16))
        }
        
    }
    
    private func setupRequiredItems() {
        
        while requiredItems.count > 0 {
            requiredItems.first?.removeFromSuperview()
            requiredItems.removeFirst()
        }
        
        let data = type.instruction
        
        for index in 0..<data.requireds.count {
            let required = data.requireds[index]
            
            let item = UIButton(title: required.data.name, titleSize: 14, titleColor: TextBlack_Color, normalImageName: required.data.imageName)
            item.isUserInteractionEnabled = false
            item.setImagePosition(position: .left, spacing: SCRXFrom(8))
            requiredView.addSubview(item)
            requiredItems.append(item)
            let height: CGFloat = 30
            item.snp.makeConstraints { make in
                if index % 2 == 0 {
                    make.left.equalToSuperview()
                }else {
                    make.left.equalTo(requiredView.snp.centerX)
                }
                let row = Int(Double(index) / 2)
                make.top.equalTo(CGFloat(row) * (height + SCRYFrom(13)))
                make.height.equalTo(height)
                if index == data.requireds.count - 1 {
                    make.bottom.equalToSuperview()
                }
            }
            
        }
        
        
    }
    
}
