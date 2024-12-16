//
//  MeshFirmwareUpdateStepHeaderView.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/12/9.
//

import UIKit

class MeshFirmwareUpdateStepHeaderView: UITableViewHeaderFooterView {

    private var dotView: UIView!
    var titleLabel: UILabel!
    var progressLabel: UILabel!

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "Distribute firmware...", textColor: TextBlack_Color, fontSize: 14)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(24))
            make.top.equalToSuperview()
            make.right.equalTo(SCRXFrom(-60))
        }
        
        dotView = UIView()
        dotView.backgroundColor = TextBlack_Color
        dotView.layer.cornerRadius = 2
        contentView.addSubview(dotView)
        dotView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(12))
            make.centerY.equalTo(titleLabel)
            make.width.height.equalTo(4)
        }
        
        progressLabel = UILabel(text: "85%", textColor: TextBlack_Color, fontSize: 14, fontWeight: .light)
        contentView.addSubview(progressLabel)
        progressLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(titleLabel)
        }
    }
}
