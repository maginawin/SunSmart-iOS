//
//  PJNGatewayWarningView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayWarningView: UIView {

    var authorizeTapped: (() -> Void)?

    private let messageLabel = UILabel()
    private let authorizeButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        messageLabel.font = .systemFont(ofSize: 12, weight: .regular)
        messageLabel.textColor = UIColor(hex: 0xF05A5A)
        messageLabel.numberOfLines = 0
        authorizeButton.setTitle("ngateway_authorize".localizedString, for: .normal)
        authorizeButton.setTitleColor(UIColor(hex: 0x6366C8), for: .normal)
        authorizeButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        authorizeButton.layer.cornerRadius = SCRYFrom(16)
        authorizeButton.layer.borderWidth = 0.5
        authorizeButton.layer.borderColor = UIColor(hex: 0x6366C8).cgColor
        if #available(iOS 15.0, *) {
            var configuration = UIButton.Configuration.plain()
            configuration.contentInsets = NSDirectionalEdgeInsets(top: 7, leading: 12, bottom: 7, trailing: 12)
            authorizeButton.configuration = configuration
        } else {
            authorizeButton.contentEdgeInsets = UIEdgeInsets(top: 7, left: 12, bottom: 7, right: 12)
        }
        authorizeButton.addTarget(self, action: #selector(authorizeAction), for: .touchUpInside)

        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        authorizeButton.setContentCompressionResistancePriority(.required, for: .horizontal)

        let row = UIStackView(arrangedSubviews: [messageLabel, authorizeButton])
        row.axis = .horizontal
        row.alignment = .center
        row.spacing = SCRXFrom(10)
        addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(text: String, canAuthorize: Bool) {
        messageLabel.text = text
        authorizeButton.isEnabled = canAuthorize
        authorizeButton.alpha = canAuthorize ? 1 : 0.5
    }

    @objc private func authorizeAction() {
        authorizeTapped?()
    }
}
