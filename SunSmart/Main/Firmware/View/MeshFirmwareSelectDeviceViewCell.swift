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
    
    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        
        setupUI()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    /// 更新数据
    /// - Parameters:
    ///   - device: 设备
    ///   - upgradeStep: 升级步骤
    ///   - selected: 是否选中
    func updateData(device: Node, upgradeStep: MeshFirmwareUpgradeStep, selected: Bool) {
        
        if upgradeStep == .distributor {
            rssiLabel.isHidden = false
            selectImageView.image = UIImage(named: selected ? "schedule_target_select" : "schedule_target_select_un")
            
            if let rssi = device.rssi {
                nameLabel.textColor = TextBlack_Color
                rssiLabel.text = "\(rssi)dB"
                if rssi >= -80 {
                    rssiLabel.textColor = SubText_Color
                    selectImageView.isHidden = false
                }else {
                    rssiLabel.textColor = Red_Color
                    selectImageView.isHidden = true
                }
                deviceImageView.image = UIImage(named: device.iconName)
            }else {
                nameLabel.textColor = SubText_Color
                deviceImageView.image = UIImage(named: device.iconName)?.withTintColor(SubText_Color)
                rssiLabel.text = "--"
                rssiLabel.textColor = SubText_Color
                selectImageView.isHidden = true
            }
            distributorLabel.isHidden = !selected
            if selected {
                firmwareVersionLabel.snp.remakeConstraints { make in
                    make.top.equalTo(SCRYFrom(12))
                    make.centerX.equalToSuperview().offset(SCRXFrom(13))
                }
            }else {
                firmwareVersionLabel.snp.remakeConstraints { make in
                    make.centerY.equalToSuperview()
                    make.centerX.equalToSuperview().offset(SCRXFrom(13))
                }
            }
        }else {
            rssiLabel.isHidden = true
            selectImageView.image = UIImage(named: selected ? "device_select" : "device_select_un")
            nameLabel.snp.remakeConstraints { make in
                make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
                make.centerY.equalToSuperview()
                make.width.lessThanOrEqualTo(SCRXFrom(99))
            }
        }
        if let distributionVersion = device.distributionVersion {
            firmwareVersionLabel.text = distributionVersion
        }
        deviceVersionLabel.text = device.firmwareVersion
        
    }
    
    private func setupUI() {
        
        selectImageView = UIImageView()
        contentView.addSubview(selectImageView)
        selectImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(8))
            make.centerY.equalToSuperview()
        }
        
        deviceImageView = UIImageView()
        contentView.addSubview(deviceImageView)
        deviceImageView.snp.makeConstraints { make in
            make.left.equalTo(selectImageView.snp.right).offset(SCRXFrom(2))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        
        nameLabel = UILabel(text: "ID001", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(deviceImageView.snp.right).offset(SCRXFrom(8))
            make.top.equalTo(SCRYFrom(12))
            make.width.lessThanOrEqualTo(SCRXFrom(99))
        }
        
        rssiLabel = UILabel(text: "-99", textColor: SubText_Color, fontSize: 13, fontWeight: .light)
        contentView.addSubview(rssiLabel)
        rssiLabel.snp.makeConstraints { make in
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(3))
            make.left.equalTo(rssiLabel)
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
            make.right.equalTo(SCRXFrom(-41))
            make.centerY.equalToSuperview()
        }
        
    }
    
    
}
