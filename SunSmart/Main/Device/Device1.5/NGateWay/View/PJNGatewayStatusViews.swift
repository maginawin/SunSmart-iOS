//
//  PJNGatewayStatusViews.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayStatusCardView: UIView {

    private let meshView = PJNGatewayStatusItemView(title: "ngateway_sig_mesh".localizedString)
    private let nodeView = PJNGatewayCenterStatusView()
    private let wifiView = PJNGatewayStatusItemView(title: "ngateway_wifi".localizedString)
    private let row = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .white
        layer.cornerRadius = SCRYFrom(18)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(hex: 0xE4E8F1).cgColor
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(96))
        }

        row.addArrangedSubview(meshView)
        row.addArrangedSubview(nodeView)
        row.addArrangedSubview(wifiView)
        row.axis = .horizontal
        row.distribution = .fillEqually
        row.alignment = .fill
        addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(18), left: SCRXFrom(12), bottom: SCRYFrom(18), right: SCRXFrom(12)))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(
        meshAssetName: String,
        meshStatusText: String,
        meshStatusColor: UIColor,
        nodeText: String,
        wifiAssetName: String,
        wifiStatusText: String,
        wifiStatusColor: UIColor,
        wifiSignalQuality: PJNGatewayModel.WiFiSignalQuality
    ) {
        meshView.configure(assetName: meshAssetName, statusText: meshStatusText, statusColor: meshStatusColor)
        nodeView.configure(text: nodeText)
        wifiView.configure(
            assetName: wifiAssetName,
            statusText: wifiStatusText,
            statusColor: wifiStatusColor
        )
    }
}

final class PJNGatewayStatusItemView: UIView {

    private let iconView = UIImageView()
    private let titleLabel = UILabel()
    private let statusLabel = UILabel()
    private let topRow = UIStackView()
    private let contentStack = UIStackView()

    init(title: String) {
        super.init(frame: .zero)
        titleLabel.text = title
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(assetName: String, statusText: String, statusColor: UIColor) {
        iconView.image = UIImage(named: assetName)
        statusLabel.text = statusText
        statusLabel.textColor = statusColor
    }

    private func setupUI() {
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(SCRYFrom(72))
        }
        iconView.contentMode = .scaleAspectFit
        titleLabel.font = .systemFont(ofSize: 13, weight: .regular)
        titleLabel.textColor = UIColor(hex: 0x8B95A7)
        statusLabel.font = .systemFont(ofSize: 12, weight: .regular)
        statusLabel.textColor = UIColor(hex: 0x2F3555)

        topRow.axis = .horizontal
        topRow.alignment = .center
        topRow.distribution = .equalCentering
        topRow.spacing = SCRXFrom(6)
        topRow.addArrangedSubview(iconView)
        topRow.addArrangedSubview(titleLabel)

        contentStack.axis = .vertical
        contentStack.alignment = .center
        contentStack.spacing = SCRYFrom(8)
        contentStack.addArrangedSubview(topRow)
        contentStack.addArrangedSubview(statusLabel)

        addSubview(contentStack)
        contentStack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview()
            make.right.lessThanOrEqualToSuperview()
        }
        iconView.snp.makeConstraints { make in
            make.width.equalTo(SCRXFrom(23))
            make.height.equalTo(SCRYFrom(23))
        }
        titleLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        statusLabel.textAlignment = .center
    }
}

final class PJNGatewayCenterStatusView: UIView {

    private let topLabel = UILabel()
    private let bottomLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        snp.makeConstraints { make in
            make.height.greaterThanOrEqualTo(SCRYFrom(72))
        }
        topLabel.font = .systemFont(ofSize: 15, weight: .regular)
        topLabel.textColor = UIColor(hex: 0x8B95A7)
        bottomLabel.font = .systemFont(ofSize: 12, weight: .regular)
        bottomLabel.textColor = UIColor(hex: 0x2F3555)

        let stack = UIStackView(arrangedSubviews: [topLabel, bottomLabel])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = SCRYFrom(8)
        addSubview(stack)
        stack.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.greaterThanOrEqualToSuperview()
            make.right.lessThanOrEqualToSuperview()
        }
        topLabel.textAlignment = .center
        bottomLabel.textAlignment = .center
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String) {
        let parts = text.components(separatedBy: "\n")
        topLabel.text = parts.first
        bottomLabel.text = parts.count > 1 ? parts[1] : nil
    }
}
