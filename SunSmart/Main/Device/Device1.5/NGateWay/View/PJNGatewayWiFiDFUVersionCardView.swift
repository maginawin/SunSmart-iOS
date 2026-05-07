//
//  PJNGatewayWiFiDFUVersionCardView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayWiFiDFUVersionCardView: UIView {

    private let cardView = PJNGatewayCardView()
    private let titleLabel = UILabel()
    private let versionLabel = UILabel()
    private let sizeLabel = UILabel()
    private let releaseDateLabel = UILabel()
    private let notesLabel = UILabel()
    private let toggleButton = UIButton(type: .system)
    var toggleExpandAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, version: String, packageSizeText: String, releaseDateText: String, releaseNotes: [String], isExpanded: Bool) {
        titleLabel.text = title
        versionLabel.text = version
        sizeLabel.text = packageSizeText
        releaseDateLabel.text = releaseDateText
        notesLabel.text = releaseNotes.map { "•  \($0)" }.joined(separator: "\n")
        notesLabel.numberOfLines = isExpanded ? 0 : 4
        toggleButton.isHidden = releaseNotes.joined().count <= 120
        let toggleTitle = isExpanded ? "ngateway_wifi_dfu_close".localizedString : "ngateway_wifi_dfu_more".localizedString
        toggleButton.setTitle(toggleTitle, for: .normal)
    }

    private func setupUI() {
        addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        titleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        titleLabel.textColor = UIColor(hex: 0x3E4664)

        versionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        versionLabel.textColor = UIColor(hex: 0x6C7592)

        sizeLabel.font = .systemFont(ofSize: 16, weight: .regular)
        sizeLabel.textColor = UIColor(hex: 0x6C7592)

        releaseDateLabel.font = .systemFont(ofSize: 16, weight: .regular)
        releaseDateLabel.textColor = UIColor(hex: 0x6C7592)

        notesLabel.font = .systemFont(ofSize: 16, weight: .regular)
        notesLabel.textColor = UIColor(hex: 0x6C7592)
        notesLabel.numberOfLines = 0
        toggleButton.setTitleColor(UIColor(hex: 0x6F78D8), for: .normal)
        toggleButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        toggleButton.contentHorizontalAlignment = .right
        toggleButton.addTarget(self, action: #selector(toggleButtonTapped), for: .touchUpInside)

        cardView.embed(titleLabel)
        cardView.embed(versionLabel)
        cardView.embed(sizeLabel)
        cardView.embed(releaseDateLabel)
        cardView.embed(notesLabel)
        cardView.embed(toggleButton)
    }

    @objc private func toggleButtonTapped() {
        toggleExpandAction?()
    }
}

final class PJNGatewayWiFiDFUCurrentVersionView: UIView {

    private let cardView = PJNGatewayCardView()
    private let titleLabel = UILabel()
    private let versionLabel = UILabel()
    let deleteButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, version: String) {
        titleLabel.text = title
        versionLabel.text = version
    }

    private func setupUI() {
        addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let row = UIStackView()
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = SCRXFrom(12)

        titleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        titleLabel.textColor = UIColor(hex: 0x3E4664)

        versionLabel.font = .systemFont(ofSize: 16, weight: .regular)
        versionLabel.textColor = UIColor(hex: 0x8B95A7)
        versionLabel.textAlignment = .right

        deleteButton.setImage(UIImage(named: "firmware_delete")?.withRenderingMode(.alwaysOriginal), for: .normal)

        row.addArrangedSubview(titleLabel)
        row.addArrangedSubview(UIView())
        row.addArrangedSubview(versionLabel)
        row.addArrangedSubview(deleteButton)
        cardView.embed(row)

        deleteButton.snp.makeConstraints { make in
            make.width.height.equalTo(SCRXFrom(30))
        }
    }
}
