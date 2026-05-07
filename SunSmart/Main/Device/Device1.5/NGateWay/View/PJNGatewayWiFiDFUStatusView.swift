//
//  PJNGatewayWiFiDFUStatusView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayWiFiDFUStatusView: UIView {

    private let progressTrackView = UIView()
    private let progressFillView = UIView()
    private let progressValueLabel = UILabel()
    private let statusIconView = UIImageView()
    private let statusLabel = UILabel()
    private let statusRow = UIStackView()
    private let statusContainerView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(status: PJNGatewayWiFiDFUStatus) {
        let progress = max(0, min(100, status.progress))
        progressValueLabel.text = "\(progress)%"
        progressFillView.snp.remakeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.width.equalToSuperview().multipliedBy(CGFloat(progress) / 100.0)
        }

        switch status {
        case .readyToUpgrade:
            statusIconView.isHidden = true
            statusLabel.textColor = UIColor(hex: 0xA7AFBE)
            statusLabel.text = nil
        case .updating(_, let message):
            statusIconView.isHidden = true
            statusLabel.textColor = UIColor(hex: 0xA7AFBE)
            statusLabel.text = message
        case .upgradeComplete(_, let message):
            statusIconView.isHidden = false
            statusIconView.image = UIImage(named: "Upgrade complete")
            statusLabel.textColor = UIColor(hex: 0x66D49C)
            statusLabel.text = message
        case .downloadFailed(_, let message), .upgradeFailed(_, let message):
            statusIconView.isHidden = false
            statusIconView.image = UIImage(named: "Download failed")
            statusLabel.textColor = UIColor(hex: 0xFF7D73)
            statusLabel.text = message
        }
    }

    private func setupUI() {
        progressTrackView.backgroundColor = UIColor(hex: 0xE8ECF4)
        progressTrackView.layer.cornerRadius = SCRYFrom(1.5)
        progressFillView.backgroundColor = UIColor(hex: 0x6F78D8)
        progressFillView.layer.cornerRadius = SCRYFrom(1.5)

        progressValueLabel.font = .systemFont(ofSize: 14, weight: .regular)
        progressValueLabel.textColor = UIColor(hex: 0x6C7592)
        progressValueLabel.textAlignment = .right

        statusIconView.contentMode = .scaleAspectFit
        statusIconView.snp.makeConstraints { make in
            make.width.height.equalTo(SCRXFrom(24))
        }

        statusLabel.font = .systemFont(ofSize: 14, weight: .regular)
        statusLabel.textAlignment = .left
        statusLabel.setContentHuggingPriority(.required, for: .horizontal)
        statusLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        statusRow.axis = .horizontal
        statusRow.alignment = .center
        statusRow.distribution = .fillProportionally
        statusRow.spacing = SCRXFrom(10)
        statusRow.addArrangedSubview(statusIconView)
        statusRow.addArrangedSubview(statusLabel)

        statusContainerView.addSubview(statusRow)
        statusRow.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview()
            make.right.lessThanOrEqualToSuperview()
            make.top.bottom.equalToSuperview()
        }

        let topRow = UIStackView(arrangedSubviews: [progressTrackView, progressValueLabel])
        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.spacing = SCRXFrom(12)

        let rootStack = UIStackView(arrangedSubviews: [topRow, statusContainerView])
        rootStack.axis = .vertical
        rootStack.alignment = .fill
        rootStack.spacing = SCRYFrom(12)
        addSubview(rootStack)
        rootStack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        progressTrackView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(3))
        }
        progressValueLabel.snp.makeConstraints { make in
            make.width.equalTo(SCRXFrom(40))
        }

        progressTrackView.addSubview(progressFillView)
        progressFillView.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.width.equalTo(0)
        }
    }
}
