//
//  DeviceParameterBottomView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit

class DeviceParameterBottomView: UIView {
    
    var leftBtn: UIButton!
    var rightBtn: UIButton!
    var lineView: UIView!
    var hlineView: UIView!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
        hlineView = UIView()
        hlineView.backgroundColor = Line_Color
        addSubview(hlineView)
        hlineView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(40))
            make.width.equalTo(1)
        }
        
        leftBtn = UIButton(title: "READ".localizedString, titleSize: 16, titleWeight: .light, titleColor: TextBlack_Color)
        leftBtn.setTitleColor(Message_Color, for: .disabled)
        addSubview(leftBtn)
        leftBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(0.5)
            make.width.equalTo(SCRXFrom(120))
            make.centerY.height.equalTo(hlineView)
        }
        
        rightBtn = UIButton(title: "NEXT".localizedString, titleSize: 16, titleWeight: .light, titleColor: TextBlack_Color)
        rightBtn.setTitleColor(Message_Color, for: .disabled)
        addSubview(rightBtn)
        rightBtn.snp.makeConstraints { make in
            make.centerX.equalToSuperview().multipliedBy(1.5)
            make.width.centerY.height.equalTo(leftBtn)
        }
        
    }
}


