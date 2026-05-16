//
//  SpaceDebugDeviceCell.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import UIKit

final class SpaceDebugDeviceCell: UITableViewCell {
    static let reuseIdentifier = "SpaceDebugDeviceCell"

    private let iconImageView = UIImageView()
    private let nameLabel = UILabel()
    private let statusLabel = UILabel()
    private let signalStrengthView = DeviceSignalStrengthView()
    private let rssiLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        contentView.layer.cornerRadius = SCRXFrom(8)
    }

    func update(item: SpaceDebugNodeItem) {
        iconImageView.image = UIImage(named: item.isFound ? item.node.iconName : item.node.offlineIconName)
        nameLabel.text = item.displayTitle

        if item.isConnecting {
            statusLabel.text = "connecting".localizedString
        } else {
            statusLabel.text = item.isFound ? "debug_found".localizedString : "debug_not_found".localizedString
        }

        if let rssi = item.rssi {
            signalStrengthView.setSignalStrength(rssi: rssi)
            rssiLabel.text = "\(rssi)dBm"
        } else {
            signalStrengthView.setSignalStrength(rssi: -120)
            rssiLabel.text = "--"
        }

        let enabled = item.isFound && !item.isConnecting
        contentView.alpha = enabled ? 1.0 : 0.45
        selectionStyle = enabled ? .gray : .none
        isUserInteractionEnabled = enabled
    }

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .white
        contentView.clipsToBounds = true

        iconImageView.contentMode = .scaleAspectFit
        contentView.addSubview(iconImageView)
        iconImageView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: SCRXFrom(36), height: SCRXFrom(36)))
        }

        signalStrengthView.setSignalStrength(rssi: -120)
        contentView.addSubview(signalStrengthView)
        signalStrengthView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview().offset(SCRYFrom(-8))
            make.size.equalTo(CGSize(width: SCRXFrom(56), height: SCRYFrom(14)))
        }

        nameLabel.font = FONTS(SCRXFrom(15))
        nameLabel.textColor = Title_Color
        nameLabel.numberOfLines = 2
        contentView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconImageView.snp.right).offset(SCRXFrom(12))
            make.right.lessThanOrEqualTo(signalStrengthView.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(SCRYFrom(12))
        }

        statusLabel.font = FONTS(SCRXFrom(12))
        statusLabel.textColor = SubText_Color
        contentView.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(4))
            make.bottom.lessThanOrEqualTo(SCRYFrom(-12))
        }

        rssiLabel.font = FONTS(SCRXFrom(12))
        rssiLabel.textColor = SubText_Color
        rssiLabel.textAlignment = .right
        contentView.addSubview(rssiLabel)
        rssiLabel.snp.makeConstraints { make in
            make.right.equalTo(signalStrengthView)
            make.top.equalTo(signalStrengthView.snp.bottom).offset(SCRYFrom(4))
        }
    }
}
