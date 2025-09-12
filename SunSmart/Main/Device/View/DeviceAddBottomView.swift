//
//  DeviceAddBottomView.swift
//  SunSmart
//
//  Created by yuankehong on 2025/3/21.
//

import UIKit

class DeviceAddBottomView: UIView {

    var selectAllBtn: UIButton!
    var selectAllLabel: UILabel!
    var selectCountLabel: UILabel!
    var addSelectedBtn: UIButton!
    var syncBtn: UIButton!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupUI() {
        
        selectAllBtn = UIButton(normalImageName: "device_select_un", selectedImageName: "device_select")
        addSubview(selectAllBtn)
        selectAllBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(15))
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        selectAllLabel = UILabel(text: "select_all".localizedString, textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        addSubview(selectAllLabel)
        selectAllLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllBtn.snp.right).offset(SCRXFrom(4))
            make.bottom.equalTo(selectAllBtn.snp.centerY)
        }
        
        selectCountLabel = UILabel(text: "3/6", textColor: RGB(148, 163, 184), fontSize: 14, fontWeight: .light)
        addSubview(selectCountLabel)
        selectCountLabel.snp.makeConstraints { make in
            make.left.equalTo(selectAllLabel)
            make.top.equalTo(selectAllLabel.snp.bottom).offset(SCRYFrom(3))
        }
        let btnSize = CGSize(width: CGFloat(Int(SCRXFrom(114))), height: CGFloat(Int(SCRYFrom(40))))
        
        addSelectedBtn = UIButton(title: "add_selected".localizedString, titleSize: 14, titleColor: .white)
//        addSelectedBtn.titleLabel?.font = Font_Medium_Size(14)
        addSelectedBtn.layer.cornerRadius = btnSize.height * 0.5
        addSelectedBtn.clipsToBounds = true
        
        addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color), for: .normal)
        addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        addSubview(addSelectedBtn)
        addSelectedBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(selectAllBtn)
            make.size.equalTo(btnSize)
        }
        
        syncBtn = UIButton(title: "sync_all".localizedString, titleSize: 14, titleColor: .white)
        syncBtn.titleLabel?.font = Font_Medium_Size(14)
        let syncBtnSize = CGSize(width: CGFloat(Int(SCRXFrom(80))), height: CGFloat(Int(SCRYFrom(40))))
        syncBtn.layer.cornerRadius = syncBtnSize.height / 2
        syncBtn.clipsToBounds = true
        syncBtn.setBackgroundImage(UIImage.image(size: syncBtnSize, color: Bar_Color), for: .normal)
        syncBtn.setBackgroundImage(UIImage.image(size: syncBtnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        syncBtn.isHidden = true
        addSubview(syncBtn)
        syncBtn.snp.makeConstraints { make in
            make.right.equalTo(addSelectedBtn.snp.left).offset(SCRXFrom(-16))
            make.centerY.equalTo(addSelectedBtn)
            make.size.equalTo(syncBtnSize)
        }
        
    }
    
}
