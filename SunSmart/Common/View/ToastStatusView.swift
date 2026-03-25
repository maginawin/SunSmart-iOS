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
            switch self {
            case .success: return UIImage(named: "toast_success")
            case .failure: return UIImage(named: "toast_failed")
            }
        }

        var tintColor: UIColor {
            switch self {
            case .success: return .systemGreen
            case .failure: return .systemRed
            }
        }
    }

    enum Position {
        case top
        case center
        case bottom
    }

    // MARK: - UI

    private let blurView: UIVisualEffectView
    private let iconView = UIImageView()
    private let messageLabel = UILabel()
    private let stackView = UIStackView()

    // MARK: - Init

    private init(message: String, type: ToastType) {
        self.blurView = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
        super.init(frame: .zero)
        setupUI(message: message, type: type)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup UI

    private func setupUI(message: String, type: ToastType) {
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
        messageLabel.numberOfLines = 2
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
            make.top.greaterThanOrEqualToSuperview().offset(12)
            make.bottom.greaterThanOrEqualToSuperview().offset(-12)
            make.center.equalToSuperview()
        }
    }

    // MARK: - Show

    static func show(
        in superview: UIView,
        message: String,
        type: ToastType,
        position: Position = .bottom,
        duration: TimeInterval = 1.5
    ) {
        let toast = ToastStatusView(message: message, type: type)
        superview.addSubview(toast)

        // SnapKit layout
        toast.snp.makeConstraints { make in
//            make.centerX.equalToSuperview()
//            make.width.lessThanOrEqualToSuperview().multipliedBy(0.85)
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.height.greaterThanOrEqualTo(44)

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
