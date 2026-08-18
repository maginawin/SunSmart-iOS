//
//  ToastStatusView.swift
//  SunSmart
//
//  Created by yuankehong on 2026/2/2.
//

import UIKit

class ToastStatusView: UIView {

    // MARK: - Public Types

    enum ToastType {
        case success
        case failure

        var icon: UIImage? {
            return icon(for: .standard)
        }

        func icon(for appearance: Appearance) -> UIImage? {
            switch (self, appearance) {
            case (.success, .standard):
                return UIImage(named: "toast_success")
            case (.failure, .standard):
                return UIImage(named: "toast_failed")
            case (.success, .siteUpdate):
                return UIImage(named: "site_update_toast_success")
            case (.failure, .siteUpdate):
                return UIImage(named: "site_update_toast_failure")
            }
        }

        var tintColor: UIColor {
            switch self {
            case .success: return .systemGreen
            case .failure: return .systemRed
            }
        }
    }

    enum Appearance {
        case standard
        case siteUpdate
    }

    enum Position {
        case top
        case center
        case bottom
    }

    // MARK: - UI

    private let blurView: UIVisualEffectView
    private let siteContentView = UIView()
    private let overlayView = UIView()
    private let iconContainerView = UIView()
    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let stackView = UIStackView()

    // MARK: - Init

    private init(message: String, type: ToastType, appearance: Appearance) {
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        super.init(frame: .zero)
        switch appearance {
        case .standard:
            setupStandardUI(message: message, type: type)
        case .siteUpdate:
            setupSiteUpdateUI(message: message, type: type)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup UI

    private func setupStandardUI(message: String, type: ToastType) {
//        backgroundColor = .black
        layer.cornerRadius = 13
        layer.masksToBounds = true
//        layer.shadowColor = UIColor.black.cgColor
//        layer.shadowOpacity = 0.12
//        layer.shadowOffset = CGSize(width: 0, height: 4)
//        layer.shadowRadius = 10

        isUserInteractionEnabled = false
        
        addSubview(blurView)
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.image = type.icon
//        iconView.tintColor = type.tintColor
//        iconView.contentMode = .scaleAspectFit

        messageLabel.text = message
        messageLabel.font = .systemFont(ofSize: 13, weight: .medium)
        messageLabel.textColor = .white
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
//        messageLabel.textAlignment = .center

        stackView.axis = .horizontal
        stackView.spacing = SCRXFrom(10)
        stackView.alignment = .center
//        stackView.distribution = .equalCentering

        addSubview(stackView)
        stackView.addArrangedSubview(iconView)
        stackView.addArrangedSubview(messageLabel)

        iconView.snp.makeConstraints { make in
            make.size.equalTo(CGSize(width: 14, height: 14))
        }

        blurView.contentView.addSubview(stackView)

        stackView.snp.makeConstraints { make in
//            make.leading.trailing.equalToSuperview().inset(16)
            make.width.lessThanOrEqualToSuperview().offset(-32)
            make.top.equalToSuperview().offset(12)
            make.bottom.equalToSuperview().offset(-12)
            make.centerX.equalToSuperview()
        }
    }

    private func setupSiteUpdateUI(message: String, type: ToastType) {
        layer.cornerRadius = 13
        layer.masksToBounds = false
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.15
        layer.shadowOffset = CGSize(width: 0, height: 2)
        layer.shadowRadius = 2.5

        isUserInteractionEnabled = false

        siteContentView.layer.cornerRadius = 13
        siteContentView.layer.masksToBounds = true
        addSubview(siteContentView)
        siteContentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        siteContentView.addSubview(blurView)
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        overlayView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        siteContentView.addSubview(overlayView)
        overlayView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        iconView.image = type.icon(for: .siteUpdate)
        iconView.contentMode = .scaleAspectFit
        iconContainerView.addSubview(iconView)
        iconView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.size.equalTo(16)
        }

        let font = UIFont.systemFont(ofSize: 15, weight: .light)
        messageLabel.text = message
        messageLabel.font = font
        messageLabel.textColor = .white
        messageLabel.textAlignment = .center
        messageLabel.numberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        stackView.axis = .horizontal
        stackView.spacing = 10
        stackView.alignment = .center
        stackView.addArrangedSubview(iconContainerView)
        stackView.addArrangedSubview(messageLabel)
        siteContentView.addSubview(stackView)

        iconContainerView.snp.makeConstraints { make in
            make.size.equalTo(30)
        }
        stackView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.leading.greaterThanOrEqualToSuperview().offset(22)
            make.trailing.lessThanOrEqualToSuperview().offset(-22)
            make.top.equalToSuperview().offset(7)
            make.bottom.equalToSuperview().offset(-7)
        }
    }

    // MARK: - Show

    static func show(
        in superview: UIView,
        message: String,
        type: ToastType,
        appearance: Appearance = .standard,
        position: Position = .bottom,
        duration: TimeInterval = 1.5
    ) {
        let toast = ToastStatusView(
            message: message,
            type: type,
            appearance: appearance
        )
        superview.addSubview(toast)

        // SnapKit layout
        toast.snp.makeConstraints { make in
//            make.centerX.equalToSuperview()
//            make.width.lessThanOrEqualToSuperview().multipliedBy(0.85)
            make.height.greaterThanOrEqualTo(44)
            switch appearance {
            case .standard:
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
            case .siteUpdate:
                make.centerX.equalToSuperview()
                make.width.equalToSuperview().offset(-32).priority(.high)
                make.width.lessThanOrEqualTo(343)
            }

            switch position {
            case .top:
                make.top.equalTo(superview.safeAreaLayoutGuide.snp.top).offset(24)
            case .center:
                make.centerY.equalToSuperview()
            case .bottom:
                make.bottom.equalTo(superview.safeAreaLayoutGuide.snp.bottom).offset(-24)
            }
        }

        // Initial state
        toast.alpha = 0
        let offsetY: CGFloat = (position == .bottom ? 10 : -10)
        toast.transform = CGAffineTransform(translationX: 0, y: offsetY)

        // Show animation
        UIView.animate(withDuration: 0.25, delay: 0, options: [.curveEaseOut]) {
            toast.alpha = 1
            toast.transform = .identity
        }

        // Auto dismiss
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            UIView.animate(withDuration: 0.25, animations: {
                toast.alpha = 0
                toast.transform = CGAffineTransform(translationX: 0, y: 10)
            }, completion: { _ in
                toast.removeFromSuperview()
            })
        }
    }
}
