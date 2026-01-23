//
//  GatewayAssociatedSpacesViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/28.
//

import UIKit

class GatewayAssociatedSpacesViewCell: UICollectionViewCell {

    var selectImageView: UIImageView!
    var nameLabel: UILabel!
    var nodesLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "schedule_target_select_un"))
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(10))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(30)
        }
        
        nodesLabel = UILabel(text: "", textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(nodesLabel)
        nodesLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(8))
            make.right.equalTo(SCRXFrom(-100))
            make.centerY.equalToSuperview()
        }
        
    }

}
