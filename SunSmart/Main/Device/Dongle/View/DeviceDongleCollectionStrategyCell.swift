//
//  DeviceDongleCollectionStrategyCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/22.
//

import UIKit

class DeviceDongleCollectionStrategyCell: UITableViewCell {

    private var iconImageView: UIImageView!
    var stage1Label: UILabel!
    var stage2Label: UILabel!
    
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        iconImageView = UIImageView(image: UIImage(named: "dongle_collecion_strategy"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
        }
        
        stage1Label = UILabel(text: "collection_strategy_1".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        stage1Label.textAlignment = .center
        contentView.addSubview(stage1Label)
        stage1Label.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(60))
            make.right.equalTo(SCRXFrom(-60))
            make.bottom.equalTo(self.snp.centerY).offset(SCRYFrom(-4.5))
        }
        
        stage2Label = UILabel(text: "collection_strategy_2".localizedString, textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        stage2Label.textAlignment = .center
        contentView.addSubview(stage2Label)
        stage2Label.snp.makeConstraints { make in
            make.left.right.equalTo(stage1Label)
            make.top.equalTo(self.snp.centerY).offset(SCRYFrom(4.5))
        }
    }
    
}
