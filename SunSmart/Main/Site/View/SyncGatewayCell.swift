//
//  SyncGatewayCell.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import UIKit
import SnapKit

final class SyncGatewayCell: UIView {

    var onAction: (() -> Void)?

    private let iconView = UIImageView()
    private let nameLabel = UILabel()
    private let signalView = DeviceSignalStrengthView()
    private let signalLabel = UILabel()
    private let actionButton = UIButton(type: .system)
    private let syncedLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        item: SyncGatewayItemState,
        action: SyncGatewayAction
    ) {
        nameLabel.text = SyncGatewaysCopy.gatewayName(item)
        iconView.image = UIImage(
            named: item.device == .failed
                ? "gateway_sync_tz_fail"
                : "time-zone-sync-status-gateway"
        )

        if let rssi = item.rssi, !item.isNoSignal {
            signalView.isHidden = false
            signalView.setSignalStrength(rssi: rssi)
            signalLabel.text = "\(rssi)dB"
            updateSignalLabelConstraints(showsSignal: true)
        } else {
            signalView.isHidden = true
            signalLabel.text = "site_sync_gateways_no_signal".localizedString
            updateSignalLabelConstraints(showsSignal: false)
        }

        syncedLabel.isHidden = action != .synced
        actionButton.isHidden = action == .synced || action == .unavailable
        actionButton.isEnabled = action == .sync || action == .retry
        actionButton.alpha = actionButton.isEnabled ? 1 : 0.35

        switch action {
        case .sync, .disabledSync:
            actionButton.setTitle("site_sync_gateways_sync".localizedString, for: .normal)
        case .syncing:
            actionButton.setTitle("site_sync_gateways_syncing".localizedString, for: .normal)
        case .retry, .disabledRetry:
            actionButton.setTitle("site_sync_gateways_retry".localizedString, for: .normal)
        case .synced:
            syncedLabel.text = "site_sync_gateways_synced".localizedString
        case .unavailable:
            break
        }
    }

    private func setupUI() {
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(10)
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(60))
        }

        iconView.contentMode = .scaleAspectFit
        addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.centerY.equalToSuperview()
            make.size.equalTo(SCRYFrom(30))
        }

        addSubview(actionButton)

        nameLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
        nameLabel.textColor = RGB(30, 35, 41)
        nameLabel.lineBreakMode = .byTruncatingTail
        addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(iconView.snp.right).offset(SCRXFrom(12))
            make.top.equalToSuperview().offset(SCRYFrom(8))
            make.right.lessThanOrEqualTo(actionButton.snp.left).offset(SCRXFrom(-8))
            make.height.equalTo(SCRYFrom(23))
        }

        signalView.setSignalStrength(rssi: -120)
        addSubview(signalView)
        signalView.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(4))
            make.size.equalTo(CGSize(width: SCRXFrom(56), height: SCRYFrom(2)))
        }

        signalLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        signalLabel.textColor = RGB(154, 171, 194)
        addSubview(signalLabel)
        updateSignalLabelConstraints(showsSignal: true)

        actionButton.layer.cornerRadius = SCRYFrom(15)
        actionButton.layer.borderWidth = 1
        actionButton.layer.borderColor = RGB(102, 103, 171).cgColor
        actionButton.setTitleColor(RGB(102, 103, 171), for: .normal)
        actionButton.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        actionButton.addTarget(self, action: #selector(actionDidTap), for: .touchUpInside)
        actionButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: SCRXFrom(64), height: SCRYFrom(30)))
        }

        syncedLabel.backgroundColor = RGB(100, 116, 139, 0.1)
        syncedLabel.layer.cornerRadius = SCRYFrom(12)
        syncedLabel.clipsToBounds = true
        syncedLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
        syncedLabel.textColor = RGB(148, 163, 184)
        syncedLabel.textAlignment = .center
        syncedLabel.isHidden = true
        addSubview(syncedLabel)
        syncedLabel.snp.makeConstraints { make in
            make.right.equalTo(actionButton)
            make.centerY.equalToSuperview()
            make.size.equalTo(CGSize(width: SCRXFrom(64), height: SCRYFrom(24)))
        }
    }

    private func updateSignalLabelConstraints(showsSignal: Bool) {
        signalLabel.snp.remakeConstraints { make in
            if showsSignal {
                make.left.equalTo(signalView.snp.right).offset(SCRXFrom(6))
            } else {
                make.left.equalTo(nameLabel)
            }
            make.centerY.equalTo(signalView)
            make.right.lessThanOrEqualTo(actionButton.snp.left).offset(SCRXFrom(-8))
        }
    }

    @objc private func actionDidTap() {
        onAction?()
    }
}
