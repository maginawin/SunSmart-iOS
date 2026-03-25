//
//  ProfileLightSensorTemplateViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/12/22.
//

import UIKit

class ProfileLightSensorTemplateViewCell: UICollectionViewCell {
    
    private var titleLabel: UILabel!
    private var luxLabel: UILabel!
    private var deviceCountLabel: UILabel!
    private var arrowImageView: UIImageView!
    private var syncFailBtn: UIButton!
    
    var resyncActionCallback: (()->Void)?
    
    var templateModel: ProfileLightSensorTemplate! {
        didSet {
            titleLabel.text = templateModel.name
            luxLabel.text = "\("threshold".localizedString): \("night".localizedString)-\(templateModel.nightStartsBelowLux) lux/\("day".localizedString)-\(templateModel.dayStartsAboveLux) lux"
            deviceCountLabel.text = "\("applied_to".localizedString): \(templateModel.devices.count) \("devices".localizedString)"
            syncFailBtn.isHidden = !templateModel.devices.contains(where: { $0.getSyncDayNightLuxProfiles().count > 0 })
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func syncFailBtnAction() {
        resyncActionCallback?()
    }
    
    private func setupUI() {
        
        titleLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(12))
            make.right.equalTo(SCRXFrom(-75))
        }
        
        luxLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(luxLabel)
        luxLabel.snp.makeConstraints { make in
            make.left.right.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(4))
        }
        
        deviceCountLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(deviceCountLabel)
        deviceCountLabel.snp.makeConstraints { make in
            make.left.equalTo(luxLabel)
            make.top.equalTo(luxLabel.snp.bottom).offset(SCRYFrom(4))
        }
        
        arrowImageView = UIImageView(image: UIImage(named: "arrow_right_black"))
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }
        
        syncFailBtn = UIButton(normalImageName: "sync_failed_small", target: self, action: #selector(syncFailBtnAction))
        syncFailBtn.isHidden = true
        contentView.addSubview(syncFailBtn)
        syncFailBtn.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalTo(arrowImageView)
        }
                               
        
    }
    
}
