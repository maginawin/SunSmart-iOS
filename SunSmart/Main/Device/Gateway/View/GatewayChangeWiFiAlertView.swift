//
//  GatewayChangeWiFiAlertView.swift
//  SunSmart
//

import UIKit

final class GatewayChangeWiFiAlertView: UIView {

    private let shadeView = UIView()
    private let contentView = UIView()
    private let titleLabel = UILabel()
    private let introImageView = UIImageView()
    private let settingsButton = UIButton(type: .custom)
    private var settingsCallback: (() -> Void)?

    static func show(settingsCallback: @escaping () -> Void) {
        let alertView = GatewayChangeWiFiAlertView(frame: UIScreen.main.bounds)
        alertView.settingsCallback = settingsCallback
        UIApplication.shared.keyWindow().addSubview(alertView)
        alertView.showAnimation()
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setupUI() {
        shadeView.backgroundColor = UIColor.black.withAlphaComponent(0.3)
        shadeView.alpha = 0
        shadeView.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(shadeTapAction)))
        addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(15)
        contentView.layer.masksToBounds = true
        contentView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.left.right.equalToSuperview().inset(SCRXFrom(30))
            make.height.equalTo(SCRYFrom(380))
        }

        titleLabel.text = "connect_to_24ghz_wifi_network".localizedString
        titleLabel.textColor = TextBlack_Color
        titleLabel.font = UIFont.systemFont(ofSize: 16, weight: .medium)
        titleLabel.textAlignment = .center

        introImageView.image = UIImage(named: "connect_wifi_intro")
        introImageView.contentMode = .scaleAspectFit

        settingsButton.backgroundColor = Bar_Color
        settingsButton.layer.cornerRadius = SCRYFrom(20)
        settingsButton.setTitle("go_to_system_settings".localizedString, for: .normal)
        settingsButton.setTitleColor(.white, for: .normal)
        settingsButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        settingsButton.addTarget(self, action: #selector(settingsButtonAction), for: .touchUpInside)

        contentView.addSubview(titleLabel)
        contentView.addSubview(introImageView)
        contentView.addSubview(settingsButton)

        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(30))
            make.left.right.equalToSuperview().inset(SCRXFrom(32))
        }
        introImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(102))
            make.centerX.equalToSuperview()
            make.width.equalTo(SCRXFrom(260))
            make.height.equalTo(SCRYFrom(152))
        }
        settingsButton.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.bottom.equalToSuperview().offset(SCRYFrom(-40))
            make.width.equalTo(SCRXFrom(248))
            make.height.equalTo(SCRYFrom(40))
        }
    }

    private func showAnimation() {
        UIView.animate(withDuration: 0.2) {
            self.shadeView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    private func dismissThenRunCallback() {
        dismiss(runCallback: true)
    }

    private func dismissWithoutCallback() {
        dismiss(runCallback: false)
    }

    private func dismiss(runCallback: Bool) {
        UIView.animate(withDuration: 0.15) {
            self.shadeView.alpha = 0
            self.contentView.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        } completion: { _ in
            let callback = self.settingsCallback
            self.removeFromSuperview()
            if runCallback {
                callback?()
            }
        }
    }

    @objc private func settingsButtonAction() {
        dismissThenRunCallback()
    }

    @objc private func shadeTapAction() {
        dismissWithoutCallback()
    }
}
