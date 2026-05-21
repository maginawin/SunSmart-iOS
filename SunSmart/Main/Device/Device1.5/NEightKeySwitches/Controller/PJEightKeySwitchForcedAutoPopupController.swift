//
//  PJEightKeySwitchForcedAutoPopupController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchForcedAutoPopupController: UIViewController {

    var autoAction: (() -> Void)?

    private enum Layout {
        static let cardHorizontalInset = SCRXFrom(8)
        static let cardBottomInset = SCRYFrom(32)
        static let cardHeight = SCRYFrom(144)
        static let cardCornerRadius = SCRYFrom(26)
        static let titleTop = SCRYFrom(24)
        static let titleLeftInset = SCRXFrom(20)
        static let buttonTop = SCRYFrom(20)
        static let buttonSize = SCRXFrom(40)
    }

    private enum AutoButtonState {
        case normal
        case loading
    }

    private let dimmingView = UIView()
    private let cardView = UIView()
    private let titleLabel = UILabel(
        text: "neightkeyswitches_forced_auto_mode".localizedString,
        textColor: Title_Color,
        fontSize: 15,
        fontWeight: .medium,
        fit: false
    )
    private let autoButton = UIButton(type: .custom)

    private var autoButtonState: AutoButtonState = .normal

    init() {
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .overFullScreen
        modalTransitionStyle = .crossDissolve
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        updateAutoButtonUI()
    }

    private var isIPad: Bool {
        UIDevice.current.userInterfaceIdiom == .pad
    }

    private func setupUI() {
        view.backgroundColor = .clear

        dimmingView.backgroundColor = UIColor.black.withAlphaComponent(0.36)
        view.addSubview(dimmingView)
        dimmingView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(dismissSelf))
        dimmingView.addGestureRecognizer(tapGesture)

        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = Layout.cardCornerRadius
        cardView.clipsToBounds = true
        view.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(Layout.cardHorizontalInset)
            make.right.equalToSuperview().offset(-Layout.cardHorizontalInset)
            make.bottom.equalTo(view.safeAreaLayoutGuide).offset(-Layout.cardBottomInset)
            make.height.equalTo(Layout.cardHeight)
        }

        titleLabel.textAlignment = .left
        cardView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(Layout.titleTop)
            make.left.equalToSuperview().offset(Layout.titleLeftInset)
            make.right.lessThanOrEqualToSuperview().offset(-Layout.titleLeftInset)
        }

        autoButton.addTarget(self, action: #selector(autoButtonAction), for: .touchUpInside)
        cardView.addSubview(autoButton)
        autoButton.snp.makeConstraints { make in
            make.top.equalTo(titleLabel.snp.bottom).offset(Layout.buttonTop)
            make.centerX.equalToSuperview()
            make.width.height.equalTo(Layout.buttonSize)
        }
    }

    @objc private func dismissSelf() {
        dismiss(animated: true)
    }

    @objc private func autoButtonAction() {
        guard autoButtonState == .normal else { return }
        autoAction?()
        autoButtonState = .loading
        updateAutoButtonUI()

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            guard let self else { return }
            self.autoButtonState = .normal
            self.updateAutoButtonUI()
        }
    }

    private func updateAutoButtonUI() {
        if autoButtonState == .normal {
            autoButton.layer.removeAnimation(forKey: "loading")
            autoButton.setImage(UIImage(named: isIPad ? "auto_big" : "auto"), for: .normal)
        } else {
            autoButton.setImage(UIImage(named: isIPad ? "group_auto_progress_big" : "group_auto_progress")?.withTintColor(Bar_Color), for: .normal)
            autoButton.layer.addRotationAnimation(duration: 1, repeatCount: 10, animationKey: "loading")
        }
    }
}
