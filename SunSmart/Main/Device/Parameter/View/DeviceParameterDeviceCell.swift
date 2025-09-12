//
//  DeviceParameterDeviceCell.swift
//  SunSmart
//
//  Created by yuankehong on 2025/4/11.
//

import UIKit
import NordicSigMeshSDK

protocol DeviceParameterDeviceCellDelegate: AnyObject {
    
    /// 设备identity事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceIdentifyAction device: Node)
    
    /// 设备onoff事件
    func cell(_ cell: DeviceParameterDeviceCell, deviceOnOffAction device: Node, isOn: Bool)
}

class DeviceParameterDeviceCell: UITableViewCell {
    /// 选择状态
    enum SelectState {
        /// 未选中
        case none
        /// 选中
        case selected
        /// 不可选
        case disable
    }

    var selectImageView: UIImageView!
    var deviceImageView: UIImageView!
    var nameLabel: UILabel!
//    private var contentLabel: UILabel!
    var pwmLabel: UILabel!
    var pwmFailedImageView: UIImageView!
    var ratedPowerLabel: UILabel!
    var ratedPowerFailedImageView: UIImageView!
    var sensitivityLabel: UILabel!
    var sensitivityImageView: UIImageView!
    
    var transitionTimeLabel: UILabel!
    var transitionTimeImageView: UIImageView!
    
    var identifyBtn: UIButton!
//    private var onoffBtn: UIButton!
    var onBtn: UIButton!
    var offBtn: UIButton!
    var groupNameLabel: UILabel!
    private var lineView: UIView!
    
    weak var delegate: DeviceParameterDeviceCellDelegate?
    
    var device: Node! {
        didSet {
            
            nameLabel.text = device.name
            onBtn.isSelected = device.selectOn
            offBtn.isSelected = device.selectOff
            
//            onBtn.backgroundColor = onBtn.isSelected ? Bar_Color : Background_Color
            
            if device.supportPwmFrequency {
                ratedPowerLabel.snp.updateConstraints { make in
                    make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(18))
                }
            }else {
                ratedPowerLabel.snp.updateConstraints { make in
                    make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(2))
                }
            }
            
            if let group = device.group {
                groupNameLabel.text = group.name
            }else {
                groupNameLabel.text = "not_in_group".localizedString
            }
        }
    }

    var selectState: SelectState = .none {
        didSet {
            if selectState == .disable {
                deviceImageView.image = UIImage(named: "device_light_gray")
                nameLabel.textColor = SubText_Color
                selectImageView.isHidden = true
            }else {
                deviceImageView.image = UIImage(named: device.iconName)
                nameLabel.textColor = TextBlack_Color
                selectImageView.isHidden = false
                selectImageView.image = UIImage(named: selectState == .selected ? "device_select" : "device_select_un")
            }
        }
    }
    
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
        delegate?.cell(self, deviceOnOffAction: device, isOn: false)
    }
    
    @objc private func onBtnAction(sender: UIButton) {
        sender.isSelected = true
//        sender.backgroundColor = sender.isSelected ? Bar_Color : Background_Color
        delegate?.cell(self, deviceOnOffAction: device, isOn: true)
    }
    
    @objc private func identifyBtnAction() {
        
        delegate?.cell(self, deviceIdentifyAction: device)
    }
    
    
    
    private func setupUI() {
        
        selectImageView = UIImageView(image: UIImage(named: "device_select_un"))
        selectImageView.sizeToFit()
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.width.equalTo(selectImageView.width)
        }
        
        deviceImageView = UIImageView()
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalTo(selectImageView)
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
        
        pwmLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(pwmLabel)
        pwmLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(2))
        }
        
        pwmFailedImageView = UIImageView(image: UIImage(named: "setting_failed"))
        pwmFailedImageView.isHidden = true
        contentView.addSubview(pwmFailedImageView)
        pwmFailedImageView.snp.makeConstraints { make in
            make.centerY.equalTo(pwmLabel)
            make.left.equalTo(pwmLabel.snp.right).offset(SCRXFrom(4))
        }
        
        groupNameLabel = UILabel(text: "not_in_group".localizedString, textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(groupNameLabel)
        groupNameLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(onBtn.snp.bottom).offset(SCRYFrom(4))
        }
        
        ratedPowerLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        ratedPowerLabel.numberOfLines = 2
        contentView.addSubview(ratedPowerLabel)
        ratedPowerLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(18))
            make.left.equalTo(pwmLabel)
            make.width.lessThanOrEqualTo(SCRXFrom(220))
        }
        
        ratedPowerFailedImageView = UIImageView(image: UIImage(named: "setting_failed"))
        ratedPowerFailedImageView.isHidden = true
        contentView.addSubview(ratedPowerFailedImageView)
        ratedPowerFailedImageView.snp.makeConstraints { make in
            make.centerY.equalTo(ratedPowerLabel)
            make.left.equalTo(ratedPowerLabel.snp.right).offset(SCRXFrom(6))
        }
        
        sensitivityLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(sensitivityLabel)
        sensitivityLabel.snp.makeConstraints { make in
            make.left.equalTo(ratedPowerLabel)
            make.top.equalTo(ratedPowerLabel.snp.bottom).offset(SCRYFrom(2))
        }
        
        sensitivityImageView = UIImageView(image: UIImage(named: "setting_failed"))
        sensitivityImageView.isHidden = true
        contentView.addSubview(sensitivityImageView)
        sensitivityImageView.snp.makeConstraints { make in
            make.centerY.equalTo(sensitivityLabel)
            make.left.equalTo(sensitivityLabel.snp.right).offset(SCRXFrom(4))
        }
        
        transitionTimeLabel = UILabel(text: "", textColor: Message_Color, fontSize: 12, fontWeight: .light)
        contentView.addSubview(transitionTimeLabel)
        transitionTimeLabel.snp.makeConstraints { make in
            make.left.equalTo(sensitivityLabel)
            make.top.equalTo(sensitivityLabel.snp.bottom).offset(SCRYFrom(2))
        }
        
        transitionTimeImageView = UIImageView(image: UIImage(named: "setting_failed"))
        transitionTimeImageView.isHidden = true
        contentView.addSubview(transitionTimeImageView)
        transitionTimeImageView.snp.makeConstraints { make in
            make.centerY.equalTo(transitionTimeLabel)
            make.left.equalTo(transitionTimeLabel.snp.right).offset(SCRXFrom(4))
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView)
            make.bottom.right.equalToSuperview()
            make.height.equalTo(0.5)
        }
        
    }
    
}
