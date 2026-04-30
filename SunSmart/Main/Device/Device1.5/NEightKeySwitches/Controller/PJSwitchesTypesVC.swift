//
//  PJSwitchesTypesVC.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJSwitchesTypesVC: UIViewController {

    private enum Layout {
        static let animationDuration: TimeInterval = 0.25
        static let contentHeight = SCRYFrom(460)
    }

    private let viewModel = PJSwitchesTypesViewModel()
    private let onBack: (() -> Void)?
    private let onKineticSwitch: (() -> Void)?
    private let onBatterySwitch: (() -> Void)?

    private var didAnimateIn = false
    private var isDismissingSheet = false

    private lazy var shadeView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(0, 0, 0, 0.4)
        view.alpha = 0
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissByTap)))
        return view
    }()

    private lazy var contentView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        return view
    }()

    private lazy var backButton: UIButton = {
        UIButton(normalImageName: "navigation_back", target: self, action: #selector(backAction))
    }()

    private lazy var titleLabel: UILabel = {
        let label = UILabel(text: viewModel.title, textColor: Title_Color, fontSize: 18)
        label.textAlignment = .center
        return label
    }()

    private lazy var kineticSwitchView: PJTopbtBoLabView = {
        PJTopbtBoLabView(
            imageName: viewModel.items[0].imageName,
            title: viewModel.items[0].title,
            target: self,
            action: #selector(kineticSwitchAction)
        )
    }()

    private lazy var batterySwitchView: PJTopbtBoLabView = {
        PJTopbtBoLabView(
            imageName: viewModel.items[1].imageName,
            title: viewModel.items[1].title,
            target: self,
            action: #selector(batterySwitchAction)
        )
    }()

    init(
        onBack: (() -> Void)? = nil,
        onKineticSwitch: (() -> Void)? = nil,
        onBatterySwitch: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        self.onKineticSwitch = onKineticSwitch
        self.onBatterySwitch = onBatterySwitch
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func makePopupViewController(
        onBack: (() -> Void)? = nil,
        onKineticSwitch: (() -> Void)? = nil,
        onBatterySwitch: (() -> Void)? = nil
    ) -> PJSwitchesTypesVC {
        let controller = PJSwitchesTypesVC(
            onBack: onBack,
            onKineticSwitch: onKineticSwitch,
            onBatterySwitch: onBatterySwitch
        )
        controller.modalPresentationStyle = .overFullScreen
        controller.modalTransitionStyle = .crossDissolve
        return controller
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        animateInIfNeeded()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        contentView.addRoundedCorners(corners: [.topLeft, .topRight], cornerRadii: CGSize(width: 15, height: 15))
    }

    @objc private func dismissByTap() {
        dismissSheet(completion: nil)
    }

    @objc private func backAction() {
        dismissSheet { [onBack] in
            onBack?()
        }
    }

    @objc private func kineticSwitchAction() {
        dismissSheet { [onKineticSwitch] in
            onKineticSwitch?()
        }
    }

    @objc private func batterySwitchAction() {
        dismissSheet { [onBatterySwitch] in
            onBatterySwitch?()
        }
    }

    private func animateInIfNeeded() {
        guard !didAnimateIn else { return }
        didAnimateIn = true
        view.layoutIfNeeded()
        contentView.transform = CGAffineTransform(translationX: 0, y: contentView.bounds.height)
        UIView.animate(withDuration: Layout.animationDuration) {
            self.shadeView.alpha = 1
            self.contentView.transform = .identity
        }
    }

    private func dismissSheet(completion: (() -> Void)?) {
        guard !isDismissingSheet else { return }
        isDismissingSheet = true
        UIView.animate(withDuration: Layout.animationDuration) {
            self.shadeView.alpha = 0
            self.contentView.transform = CGAffineTransform(translationX: 0, y: self.contentView.bounds.height)
        } completion: { _ in
            self.dismiss(animated: false, completion: completion)
        }
    }

    private func setupUI() {
        view.backgroundColor = .clear

        view.addSubview(shadeView)
        shadeView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        view.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(Layout.contentHeight)
        }

        contentView.addSubview(backButton)
        backButton.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(22))
            make.top.equalTo(SCRYFrom(18))
            make.width.height.equalTo(SCRXFrom(24))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(backButton)
            make.centerX.equalToSuperview()
        }

        contentView.addSubview(kineticSwitchView)
        kineticSwitchView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.top.equalTo(backButton.snp.bottom).offset(SCRYFrom(28))
            make.width.equalTo(SCRYFrom(92))
        }

        contentView.addSubview(batterySwitchView)
        batterySwitchView.snp.makeConstraints { make in
            make.left.equalTo(kineticSwitchView.snp.right).offset(SCRXFrom(28))
            make.top.width.equalTo(kineticSwitchView)
        }
    }
}
