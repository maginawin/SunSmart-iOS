//
//  DeviceMeshNetworkResetBottomView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/10/21.
//

import UIKit

class DeviceMeshNetworkResetBottomView: UIView {

    var lineView: UIView!
    var button: UIButton!
    var noteLabel: UILabel!

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
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }
        
        button = UIButton(title: "", titleSize: 16, titleWeight: .light, titleColor: Bar_Color)
        button.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        addSubview(button)
        button.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }
        
        noteLabel = UILabel(text: "mesh_network_reset_scan_note".localizedString, textColor: Message_Color, fontSize: 12, fontWeight: .light, fit: false)
        noteLabel.numberOfLines = 2
        noteLabel.textAlignment = .center
        addSubview(noteLabel)
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(42))
        }
        
    }
    
}
