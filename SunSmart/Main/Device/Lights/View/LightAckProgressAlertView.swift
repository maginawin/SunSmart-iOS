//
//  LightAckProgressAlertView.swift
//  SunSmart
//

import UIKit

final class LightAckProgressAlertView: UIView {

    private static weak var current: LightAckProgressAlertView?

    private let shadeView = UIView()
    private let contentView = UIView()
    private let titleLabel = UILabel(text: nil, textColor: Title_Color, fontSize: 15, fontWeight: .medium, fit: false)
    private let messageLabel = UILabel(text: nil, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
    private let closeButton = UIButton(title: "close".localizedString, titleSize: 15, titleWeight: .light, titleColor: Bar_Color)

    static func show(title: String, message: String) -> LightAckProgressAlertView? {
        let window = UIApplication.shared.windows.first { $0.isKeyWindow }
        guard let window = window else { return nil }

        current?.dismiss()

        let alert = LightAckProgressAlertView(frame: window.bounds)
        alert.update(title: title, message: message)
        window.addSubview(alert)
        alert.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        current = alert
        return alert
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(title: String, message: String) {
        titleLabel.text = title
        messageLabel.text = message
    }

    func dismiss() {
        removeFromSuperview()
    }

    private func setupUI() {
        shadeView.backgroundColor = RGB(0, 0, 0, 0.3)
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(8)
        contentView.layer.masksToBounds = true
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(36))
            make.right.equalTo(SCRXFrom(-36))
            make.centerY.equalToSuperview()
            make.height.greaterThanOrEqualTo(SCRYFrom(160))
        }

        titleLabel.textAlignment = .center
        titleLabel.numberOfLines = 2
        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(24))
            make.left.equalTo(SCRXFrom(24))
            make.right.equalTo(SCRXFrom(-24))
        }

        messageLabel.numberOfLines = 0
        messageLabel.textAlignment = .left
        contentView.addSubview(messageLabel)
        messageLabel.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(20))
            make.left.right.equalTo(titleLabel)
        }

        let lineView = UIView()
        lineView.backgroundColor = Line_Color
        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.top.greaterThanOrEqualTo(messageLabel.snp.bottom).offset(SCRYFrom(20))
            make.left.right.equalToSuperview()
            make.height.equalTo(1)
        }

        closeButton.addTarget(self, action: #selector(closeButtonAction), for: .touchUpInside)
        contentView.addSubview(closeButton)
        closeButton.snp.makeConstraints { make in
            make.top.equalTo(lineView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(52))
        }
    }

    @objc private func closeButtonAction() {
        dismiss()
    }
}
