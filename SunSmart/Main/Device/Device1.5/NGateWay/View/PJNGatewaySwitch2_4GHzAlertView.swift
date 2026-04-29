//
//  PJNGatewaySwitch2_4GHzAlertView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewaySwitch2_4GHzAlertView: UIView {

    var settingsTapped: (() -> Void)?

    private let dimView = UIControl()
    private let cardView = UIView()
    private let titleLabel = UILabel()
    private let wifiImageView = UIImageView()
    private let settingsButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(in view: UIView) {
        alpha = 0
        frame = view.bounds
        view.addSubview(self)
        UIView.animate(withDuration: 0.2) {
            self.alpha = 1
        }
    }

    func dismiss() {
        UIView.animate(withDuration: 0.2, animations: {
            self.alpha = 0
        }, completion: { _ in
            self.removeFromSuperview()
        })
    }

    private func setupUI() {
        backgroundColor = .clear

        dimView.backgroundColor = UIColor.black.withAlphaComponent(0.26)
        dimView.addTarget(self, action: #selector(dismissAction), for: .touchUpInside)
        addSubview(dimView)
        dimView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = SCRYFrom(20)
        addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.right.equalToSuperview().inset(SCRXFrom(28))
        }

        titleLabel.text = "ngateway_switch_2_4g_title".localizedString
        titleLabel.font = .systemFont(ofSize: 16, weight: .semibold)
        titleLabel.textColor = UIColor(hex: 0x2F3555)
        titleLabel.textAlignment = .center

        wifiImageView.contentMode = .scaleAspectFit
        wifiImageView.image = UIImage(named: "wifi_2.4G") ?? UIImage(systemName: "wifi")
        wifiImageView.tintColor = UIColor(hex: 0x6366C8)

        settingsButton.setTitle("ngateway_go_to_system_settings".localizedString, for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        settingsButton.backgroundColor = UIColor(hex: 0x6366C8)
        settingsButton.layer.cornerRadius = SCRYFrom(22)
        settingsButton.addTarget(self, action: #selector(settingsAction), for: .touchUpInside)

        cardView.addSubview(titleLabel)
        cardView.addSubview(wifiImageView)
        cardView.addSubview(settingsButton)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(34))
            make.left.right.equalToSuperview().inset(SCRXFrom(24))
        }
        wifiImageView.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(34))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(290))
            make.height.equalTo(SCRYFit(152))
        }
        settingsButton.snp.makeConstraints { make in
            make.top.equalTo(wifiImageView.snp.bottom).offset(SCRYFrom(42))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(240))
            make.height.equalTo(SCRYFrom(40))
            make.bottom.equalToSuperview().offset(SCRYFrom(-32))
        }
    }

    @objc private func dismissAction() {
        dismiss()
    }

    @objc private func settingsAction() {
        settingsTapped?()
    }
}
