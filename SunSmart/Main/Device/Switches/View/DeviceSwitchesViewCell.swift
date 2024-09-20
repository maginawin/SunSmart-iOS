//
//  DeviceSwitchesViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/9/5.
//

import UIKit

class DeviceSwitchesViewCell: UICollectionViewCell {
    
    /// 图标
    var iconImageView: UIImageView!
    /// 名称
    var nameLabel: UILabel!
    var deleteBtn: UIButton!
    var failedImageView: UIImageView!
    
    var deleteActionCallback: ((DeviceSwitchData)->Void)?
    
    var switche: DeviceSwitchData! {
        didSet {
            nameLabel.text = switche.name
            iconImageView.image = UIImage(named: switche.needSyncData ? "sync_failed_big" : "device_switch")
            updateUI()
        }
    }
    
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.shadowColor = RGB(0, 0, 0, 0.07).cgColor
        layer.shadowOffset = CGSizeMake(0,2)
        layer.shadowOpacity = 1
        layer.shadowRadius = 4
        
        iconImageView = UIImageView(image: UIImage(named: "device_switch"))
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
//            make.bottom.equalTo(self.snp.centerY)
            make.centerY.equalToSuperview().offset(SCRYFrom(-10))
        }
        
        nameLabel = UILabel(text: nil, textColor: RGB(64, 79, 102), fontSize: 14, fontWeight: .light)
        nameLabel.textAlignment = .center
        nameLabel.lineBreakMode = .byTruncatingHead
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.right.equalTo(SCRXFrom(-18))
            make.bottom.equalTo(SCRYFrom(-17))
        }
        
        deleteBtn = UIButton(normalImageName: "scene_delete", target: self, action: #selector(deleteBtnClick))
        deleteBtn.isHidden = true
        contentView.addSubview(deleteBtn)
        deleteBtn.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-4))
//            make.top.equalTo(SCRXFrom(-5))
            make.right.top.equalToSuperview()
        }
        
        failedImageView = UIImageView(image: UIImage(named: "schedule_sync_failed"))
        failedImageView.isHidden = true
        contentView.addSubview(failedImageView)
        failedImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(18))
            make.top.equalTo(SCRYFrom(18))
        }
        
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = frame.height * 0.5
        
        updateUI()
    }
    
    private func updateUI() {
        
        if self.switche.proxyNode != nil { // 已设备代理设备
            self.deleteDashedBorder()
        }else { // 未设置代理设备
            self.addDashedBorder()
        }
        backgroundColor = switche.enabled ? .white : RGB(226, 226, 226)
    }
    
    @objc private func deleteBtnClick() {
        deleteActionCallback?(switche)
    }
    
}
