//
//  GatewaySectionHeaderView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/7/31.
//

import UIKit

class GatewaySectionHeaderView: UITableViewHeaderFooterView {

    var titleLabel: UILabel!
    var messageLabel: UILabel!
    var operationBtn: UIButton!
    var operationActionCallback: (()->Void)?

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func operationBtnAction() {
        operationActionCallback?()
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 14)
        addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(16))
            make.bottom.equalTo(SCRYFrom(-8))
        }
        
        messageLabel = UILabel(text: "", textColor: Red_Color, fontSize: 12, fontWeight: .light)
        messageLabel.numberOfLines = 0
        addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(8))
            make.left.equalTo(titleLabel)
            make.right.equalTo(SCRXFrom(-102))
        }
        
        operationBtn = UIButton(titleSize: 14, titleWeight: .light, titleColor: Bar_Color, target: self, action: #selector(operationBtnAction))
        addSubview(operationBtn)
        operationBtn.snp.makeConstraints { make in
            make.centerY.equalTo(titleLabel)
            make.right.equalTo(SCRXFrom(-12))
        }
        
    }
    
}
