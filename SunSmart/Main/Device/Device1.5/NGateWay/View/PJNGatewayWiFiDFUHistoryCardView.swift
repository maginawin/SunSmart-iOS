//
//  PJNGatewayWiFiDFUHistoryCardView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayWiFiDFUHistoryCardView: UIView {

    private let cardView = PJNGatewayCardView()
    private let versionLabel = UILabel()
    private let releaseDateLabel = UILabel()
    private let notesLabel = UILabel()
    private let moreButton = UIButton(type: .system)
    var moreAction: (() -> Void)?

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(item: PJNGatewayWiFiDFUHistoryItem) {
        versionLabel.text = item.version
        releaseDateLabel.text = item.releaseDateText
        notesLabel.text = item.releaseNotes.map { "•  \($0)" }.joined(separator: "\n")
        notesLabel.numberOfLines = item.isExpanded ? 0 : 4
        moreButton.isHidden = item.releaseNotes.joined().count <= 120
        moreButton.setTitle(item.isExpanded ? "ngateway_wifi_dfu_close".localizedString : "ngateway_wifi_dfu_more".localizedString, for: .normal)
    }

    private func setupUI() {
        addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        versionLabel.font = .systemFont(ofSize: 20, weight: .regular)
        versionLabel.textColor = UIColor(hex: 0x6F78D8)

        releaseDateLabel.font = .systemFont(ofSize: 16, weight: .regular)
        releaseDateLabel.textColor = UIColor(hex: 0x6C7592)

        notesLabel.font = .systemFont(ofSize: 16, weight: .regular)
        notesLabel.textColor = UIColor(hex: 0x6C7592)
        notesLabel.numberOfLines = 0

        moreButton.setTitleColor(UIColor(hex: 0x6F78D8), for: .normal)
        moreButton.titleLabel?.font = .systemFont(ofSize: 16, weight: .regular)
        moreButton.contentHorizontalAlignment = .right
        moreButton.addTarget(self, action: #selector(moreTapped), for: .touchUpInside)

        cardView.addSubview(versionLabel)
        cardView.addSubview(releaseDateLabel)
        cardView.addSubview(notesLabel)
        cardView.addSubview(moreButton)

        versionLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(20))
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.lessThanOrEqualToSuperview().offset(SCRXFrom(-16))
        }

        releaseDateLabel.snp.makeConstraints { make in
            make.top.equalTo(versionLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(versionLabel)
            make.right.equalToSuperview().offset(SCRXFrom(-16))
        }

        notesLabel.snp.makeConstraints { make in
            make.top.equalTo(releaseDateLabel.snp.bottom).offset(SCRYFrom(12))
            make.left.equalTo(versionLabel)
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.bottom.lessThanOrEqualTo(moreButton.snp.top).offset(SCRYFrom(-8))
        }

        moreButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-20))
            make.bottom.equalToSuperview().offset(SCRYFrom(-20))
            make.height.equalTo(SCRYFrom(20))
        }
    }

    @objc private func moreTapped() {
        moreAction?()
    }
}
