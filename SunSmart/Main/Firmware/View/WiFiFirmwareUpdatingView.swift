//
//  WiFiFirmwareUpdatingView.swift
//  SunSmart
//
//  Created by Codex on 2026/7/15.
//

import UIKit

final class WiFiFirmwareUpdatingView: UIView {

    private let progressContainer = UIView()
    private let progressView = UIView()
    private let percentLabel = UILabel()
    private let resultStackView = UIStackView()
    private let resultImageView = UIImageView()
    private let resultLabel = UILabel()
    private let detailLabel = UILabel()
    private var progressWidthConstraint: NSLayoutConstraint!
    private var percent = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    override var intrinsicContentSize: CGSize {
        return CGSize(width: UIView.noIntrinsicMetric, height: 94)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        progressWidthConstraint.constant = progressContainer.bounds.width * CGFloat(percent) / 100
    }

    func configure(state: WiFiFirmwareUpdatingState) {
        percent = min(100, max(0, state.percent))
        percentLabel.text = "\(percent)%"
        applyContent(for: state.kind)
        setNeedsLayout()
    }

    private func setupUI() {
        progressContainer.backgroundColor = Line_Color1
        progressView.backgroundColor = Blue_Color

        percentLabel.font = FONTS(12)
        percentLabel.textColor = SubText_Color
        percentLabel.textAlignment = .right

        resultStackView.axis = .horizontal
        resultStackView.alignment = .center
        resultStackView.spacing = 8

        resultImageView.contentMode = .scaleAspectFit
        resultImageView.setContentHuggingPriority(.required, for: .horizontal)

        resultLabel.font = FONTS(14)
        resultLabel.textColor = ImportantText_Color
        resultLabel.textAlignment = .center

        detailLabel.font = FONTS(13)
        detailLabel.textColor = SubText_Color
        detailLabel.textAlignment = .center

        [progressContainer, percentLabel, resultStackView, detailLabel].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            addSubview($0)
        }
        progressView.translatesAutoresizingMaskIntoConstraints = false
        progressContainer.addSubview(progressView)
        resultImageView.translatesAutoresizingMaskIntoConstraints = false
        resultLabel.translatesAutoresizingMaskIntoConstraints = false
        resultStackView.addArrangedSubview(resultImageView)
        resultStackView.addArrangedSubview(resultLabel)

        progressWidthConstraint = progressView.widthAnchor.constraint(equalToConstant: 0)
        NSLayoutConstraint.activate([
            progressContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            progressContainer.topAnchor.constraint(equalTo: topAnchor, constant: 7),
            progressContainer.trailingAnchor.constraint(equalTo: percentLabel.leadingAnchor, constant: -10),
            progressContainer.heightAnchor.constraint(equalToConstant: 2),

            progressView.leadingAnchor.constraint(equalTo: progressContainer.leadingAnchor),
            progressView.topAnchor.constraint(equalTo: progressContainer.topAnchor),
            progressView.bottomAnchor.constraint(equalTo: progressContainer.bottomAnchor),
            progressWidthConstraint,

            percentLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            percentLabel.centerYAnchor.constraint(equalTo: progressContainer.centerYAnchor),
            percentLabel.widthAnchor.constraint(equalToConstant: 40),

            resultStackView.centerXAnchor.constraint(equalTo: centerXAnchor),
            resultStackView.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            resultStackView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor),
            resultStackView.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor),

            resultImageView.widthAnchor.constraint(equalToConstant: 20).withPriority(.defaultHigh),
            resultImageView.heightAnchor.constraint(equalToConstant: 20).withPriority(.defaultHigh),

            detailLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            detailLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            detailLabel.topAnchor.constraint(equalTo: topAnchor, constant: 65),
            detailLabel.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor)
        ])
    }

    private func applyContent(for kind: WiFiFirmwareUpdatingKind) {
        let titleKey: String
        let detailKey: String?
        let imageName: String?

        switch kind {
        case .connFailedTimeout:
            titleKey = "wifi_firmware_connection_failed"
            detailKey = "wifi_firmware_communication_timeout"
            imageName = "alert_failed"
        case .connFailedServerUnable:
            titleKey = "wifi_firmware_connection_failed"
            detailKey = "wifi_firmware_server_unable"
            imageName = "alert_failed"
        case .downloading:
            titleKey = "wifi_firmware_downloading"
            detailKey = nil
            imageName = nil
        case .downloadFailed:
            titleKey = "wifi_firmware_download_failed"
            detailKey = nil
            imageName = "alert_failed"
        case .updating:
            titleKey = "wifi_firmware_updating"
            detailKey = nil
            imageName = nil
        case .upgradeFailed:
            titleKey = "wifi_firmware_upgrade_failed"
            detailKey = nil
            imageName = "alert_failed"
        case .upgradeComplete:
            titleKey = "wifi_firmware_upgrade_complete"
            detailKey = nil
            imageName = "sync_success_small"
        case .cancelled:
            titleKey = "wifi_firmware_upgrade_cancelled"
            detailKey = nil
            imageName = "alert_failed"
        case .communicationUnknown:
            titleKey = "wifi_firmware_connection_failed"
            detailKey = "wifi_firmware_communication_timeout"
            imageName = "alert_failed"
        }

        resultLabel.text = titleKey.localizedString
        detailLabel.text = detailKey?.localizedString
        detailLabel.isHidden = detailKey == nil
        resultImageView.image = imageName.flatMap(UIImage.init(named:))
        resultImageView.isHidden = imageName == nil
    }
}

private extension NSLayoutConstraint {
    func withPriority(_ priority: UILayoutPriority) -> NSLayoutConstraint {
        self.priority = priority
        return self
    }
}
