//
//  GroupsViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2023/12/11.
//

import UIKit
import NordicSigMeshSDK

class GroupsViewCell: UICollectionViewCell {
    
    var imageView: UIImageView!
    var imageLabel: UILabel!
    var nameLabel: UILabel!
    var deleteBtn: UIButton!
    var deleteActionCallback: (()->Void)?
    
    var group: Group! {
        didSet {
            if let text = group.info.imageText, text.count > 0 {
                imageLabel.isHidden = false
                imageLabel.text = text
                imageView.isHidden = true
            }else {
                imageLabel.isHidden = true
                imageView.isHidden = false
                imageView.image = UIImage(named: "group_image_\(group.info.imageId)") //device_light_offline
            }
            nameLabel.text = group.name
            backgroundColor = group.isOn ? .white : RGB(226, 226, 226)
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.shadowColor = RGB(0, 0, 0, 0.07).cgColor
        layer.shadowOffset = CGSizeMake(0,2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4
        
        imageView = UIImageView()
        contentView.addSubview(imageView)
        imageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
//            make.bottom.equalTo(self.snp.centerY)
            make.centerY.equalToSuperview().offset(SCRYFrom(-10))
        }
        
        imageLabel = UILabel(text: nil, textColor: RGB(20, 46, 79))
        imageLabel.font = UIFont.systemFont(ofSize: SCRYFrom(36), weight: .thin)
        contentView.addSubview(imageLabel)
        imageLabel.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
//            make.top.equalTo(SCRYFrom(21))
            make.centerY.equalTo(imageView)
//            make.bottom.equalTo(self.snp.centerY)
        }
        
        nameLabel = UILabel(text: nil, textColor: RGB(64, 79, 102), fontSize: 14, fontWeight: .light)
        nameLabel.textAlignment = .center
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
            make.bottom.equalTo(SCRYFrom(-18))
        }
        
        deleteBtn = UIButton(normalImageName: "close", target: self, action: #selector(deleteBtnClick))
        deleteBtn.isHidden = true
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-4))
//            make.top.equalTo(SCRXFrom(-5))
            make.right.top.equalToSuperview()
        }
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.height * 0.5
    }
    
    @objc private func deleteBtnClick() {
        deleteActionCallback?()
    }
    
}
