//
//  EnergyStaticDataDeviceViewCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/5/13.
//

import UIKit

protocol EnergyStaticDataDeviceViewCellDelegate: AnyObject {
    
    /// 设备identity事件
    func deviceCellIdentifyAction(_ cell: EnergyStaticDataDeviceViewCell)
    
    /// 设备onoff事件
    func cell(_ cell: EnergyStaticDataDeviceViewCell, deviceOnOffAction isOn: Bool)
}

class EnergyStaticDataDeviceViewCell: UITableViewCell {

    var deviceImageView: UIImageView!
    var nameLabel: UILabel!
    var energyLabel: UILabel!
    var identifyBtn: UIButton!
//    private var onoffBtn: UIButton!
    var onBtn: UIButton!
    var offBtn: UIButton!
    var groupNameLabel: UILabel!
    private var lineView: UIView!
    
    weak var delegate: EnergyStaticDataDeviceViewCellDelegate?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        selectionStyle = .none
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    @objc private func offBtnAction(sender: UIButton) {
        sender.isSelected = true
//        sender.backgroundColor = sender.isSelected ? Bar_Color : Background_Color
        delegate?.cell(self, deviceOnOffAction: false)
    }
    
    @objc private func onBtnAction(sender: UIButton) {
        sender.isSelected = true
//        sender.backgroundColor = sender.isSelected ? Bar_Color : Background_Color
        delegate?.cell(self, deviceOnOffAction: true)
    }
    
    @objc private func identifyBtnAction() {
        
        delegate?.deviceCellIdentifyAction(self)
    }
    
    
    
    private func setupUI() {
        
        deviceImageView = UIImageView()
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(12))
            make.width.height.equalTo(30)
        }
        
        let height = Int(SCRYFrom(30))
        let onoffSize = CGSize(width: height, height: height)
        
        offBtn = UIButton(title: "Off".localizedString, titleSize: 13, titleWeight: .light, titleColor: RGB(20, 46, 79), target: self, action: #selector(offBtnAction))
        offBtn.setTitleColor(.white, for: .selected)
        offBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Background_Color), for: .normal)
        offBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Bar_Color), for: .selected)
        offBtn.backgroundColor = Background_Color
        offBtn.layer.cornerRadius = CGFloat(height) * 0.5
        offBtn.layer.masksToBounds = true
        contentView.addSubview(offBtn)
        offBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(deviceImageView)
            make.size.equalTo(onoffSize)
        }
        
        onBtn = UIButton(title: "On".localizedString, titleSize: 13, titleWeight: .light, titleColor: RGB(20, 46, 79), target: self, action: #selector(onBtnAction))
        onBtn.setTitleColor(.white, for: .selected)
        onBtn.backgroundColor = Background_Color
        onBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Background_Color), for: .normal)
        onBtn.setBackgroundImage(UIImage.image(size: onoffSize, color: Bar_Color), for: .selected)
        onBtn.layer.cornerRadius = CGFloat(height) * 0.5
        onBtn.layer.masksToBounds = true
        contentView.addSubview(onBtn)
        onBtn.snp.makeConstraints { make in
            make.right.equalTo(offBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.size.equalTo(offBtn)
        }
        
        identifyBtn = UIButton(target: self, action: #selector(identifyBtnAction))
        identifyBtn.setBackgroundImage(UIImage(named: "device_identify"), for: .normal)
        contentView.addSubview(identifyBtn)
        identifyBtn.snp.makeConstraints { make in
            make.right.equalTo(onBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.size.equalTo(onBtn)
        }
        
        nameLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
//            make.top.equalTo(deviceImageView).offset(SCRYFrom(-3))
            make.centerY.equalTo(deviceImageView)
            make.right.equalTo(identifyBtn.snp.left).offset(SCRXFrom(-30)).priority(.low)
        }
    
        energyLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(energyLabel)
        energyLabel.snp.makeConstraints { make in
            make.bottom.equalTo(SCRYFrom(-10))
            make.left.equalTo(nameLabel)
        }
        
        groupNameLabel = UILabel(text: "not_in_group".localizedString, textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(groupNameLabel)
        groupNameLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(energyLabel)
        }
     
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(14.6))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
    }
    
}
