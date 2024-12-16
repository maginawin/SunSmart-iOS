//
//  MeshFirmwareSelectDeviceViewCell.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/4.
//

import UIKit
import NordicSigMeshSDK

class MeshFirmwareSelectDeviceViewCell: UITableViewCell {

    private var selectImageView: UIImageView!
    private var deviceImageView: UIImageView!
    private var nameLabel: UILabel!
    private var rssiLabel: UILabel!
    private var firmwareVersionLabel: UILabel!
    private var distributorLabel: UILabel!
    private var deviceVersionLabel: UILabel!
    /// 识别点击回调
    var identifyCallback: (()->Void)?
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        selectionStyle = .none
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// 更新数据
    /// - Parameters:
    ///   - device: 设备
    ///   - upgradeStep: 升级步骤
    ///   - showSelect: 是否展示选择
    ///   - selected: 是否选中
    ///   - enabled: 是否可以选择
    ///   - isDistributor: 是否是分发者（选择升级设备流程）
    func updateData(device: Node, upgradeStep: MeshFirmwareUpgradeStep, showSelect: Bool, selected: Bool, enabled: Bool, isDistributor: Bool = false) {
        
        selectImageView.isHidden = !showSelect
        if selected {
            selectImageView.image = UIImage(named: "schedule_target_select")
        }else {
            selectImageView.image = UIImage(named: "schedule_target_select_un")
        }
        if !enabled {
            selectImageView.image = selectImageView.image?.withTintColor(RGB(216, 216, 216, 0.5))
            deviceImageView.isUserInteractionEnabled = false
        }else {
            deviceImageView.isUserInteractionEnabled = true
        }
        nameLabel.text = device.name
        
//        switch device.distributorSelectedState {
//        case .none:
//            selectImageView.isHidden = true
//        case .unselected:
//            selectImageView.image = UIImage(named: "schedule_target_select_un")
//        case .selected:
//            selectImageView.image = UIImage(named: "schedule_target_select")
//        case .disabled:
//            selectImageView.image = UIImage(named: "schedule_target_select")?.withTintColor(RGB(216, 216, 216, 0.5))
//        }
        
        if upgradeStep == .distributor {
            rssiLabel.isHidden = false
            
            switch device.rssiState {
            case .none:
                nameLabel.textColor = SubText_Color
                deviceImageView.image = UIImage(named: device.iconName)?.withTintColor(SubText_Color)
                rssiLabel.text = "--"
                rssiLabel.textColor = SubText_Color
            case .normal:
                nameLabel.textColor = TextBlack_Color
                rssiLabel.text = "\(device.rssi ?? -99)dB"
                rssiLabel.textColor = SubText_Color
                deviceImageView.image = UIImage(named: device.iconName)
            case .low:
                nameLabel.textColor = TextBlack_Color
                rssiLabel.text = "\(device.rssi ?? -99)dB"
                rssiLabel.textColor = Red_Color
                deviceImageView.image = UIImage(named: device.iconName)
            }
            
//            if let rssi = device.rssi {
//                nameLabel.textColor = TextBlack_Color
//                rssiLabel.text = "\(rssi)dB"
//                if rssi >= -80 {
//                    rssiLabel.textColor = SubText_Color
//                    selectImageView.isHidden = false
//                }else {
//                    rssiLabel.textColor = Red_Color
//                    selectImageView.isHidden = true
//                }
//                deviceImageView.image = UIImage(named: device.iconName)
//            }else {
//                nameLabel.textColor = SubText_Color
//                deviceImageView.image = UIImage(named: device.iconName)?.withTintColor(SubText_Color)
//                rssiLabel.text = "--"
//                rssiLabel.textColor = SubText_Color
//                selectImageView.isHidden = true
//            }
//            distributorLabel.isHidden = !selected
            if device.distributorSelectedState == .selected {
                distributorLabel.isHidden = false
                firmwareVersionLabel.snp.remakeConstraints { make in
                    make.top.equalTo(SCRYFrom(12))
                    make.centerX.equalToSuperview().offset(SCRXFrom(13))
                }
            }else {
                distributorLabel.isHidden = true
                firmwareVersionLabel.snp.remakeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.centerX.equalToSuperview().offset(SCRXFrom(13))
                }
            }
        }else {
            rssiLabel.isHidden = true
//            selectImageView.image = UIImage(named: selected ? "device_select" : "device_select_un")
            
            if device.state {
                deviceImageView.image = UIImage(named: device.iconName)
                nameLabel.textColor = TextBlack_Color
            }else {
                deviceImageView.image = UIImage(named: device.iconName)?.withTintColor(SubText_Color)
                nameLabel.textColor = SubText_Color
            }
            nameLabel.snp.remakeConstraints { make in
                make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
                make.centerY.equalToSuperview()
                make.width.lessThanOrEqualTo(SCRXFrom(99))
            }
            
            if isDistributor {
                distributorLabel.isHidden = false
                firmwareVersionLabel.snp.remakeConstraints { make in
                    make.top.equalTo(SCRYFrom(12))
                    make.centerX.equalToSuperview().offset(SCRXFrom(13))
                }
            }else {
                distributorLabel.isHidden = true
                firmwareVersionLabel.snp.remakeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.centerX.equalToSuperview().offset(SCRXFrom(13))
                }
            }
            
        }
        
        
        if let distributionVersion = device.distributionVersion {
            firmwareVersionLabel.text = distributionVersion
        }else {
            firmwareVersionLabel.text = nil
        }
        deviceVersionLabel.text = device.firmwareVersion
        
    }
    
    /// 点击图标
    @objc private func deviceImageViewAction() {
        identifyCallback?()
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView()
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }
        
        deviceImageView = UIImageView()
        deviceImageView.isUserInteractionEnabled = true
        deviceImageView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(deviceImageViewAction)))
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        nameLabel = UILabel(text: "ID001", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
//            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.centerX.equalTo(self.snp.left).offset(SCRXFrom(94))
            make.top.equalTo(SCRYFrom(12))
            make.width.lessThanOrEqualTo(SCRXFrom(99))
        }
        
        rssiLabel = UILabel(text: "-99", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(rssiLabel)
        rssiLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(3))
            make.left.equalTo(nameLabel)
        }
        
        firmwareVersionLabel = UILabel(text: "1.0.0", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(firmwareVersionLabel)
        firmwareVersionLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.centerX.equalToSuperview().offset(SCRXFrom(13))
        }
        
        distributorLabel = UILabel(text: "distributor".localizedString, textColor: Bar_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(distributorLabel)
        distributorLabel.snp.makeConstraints { make in
            make.centerX.equalTo(firmwareVersionLabel)
            make.bottom.equalTo(SCRYFrom(-11))
        }
        
        deviceVersionLabel = UILabel(text: "1.0.0", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(deviceVersionLabel)
        deviceVersionLabel.snp.makeConstraints { make in
//            make.right.equalTo(SCRXFrom(-41))
            make.centerX.equalTo(self.snp.right).offset(SCRXFrom(-52))
            make.centerY.equalToSuperview()
        }
        
    }
    
    
}
