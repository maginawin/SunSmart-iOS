//
//  OthersViewController.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import UIKit

final class OthersViewController: UIViewController {

    private enum Layout {
        static let animationDuration: TimeInterval = 0.25
        static let contentHeight = SCRYFrom(460)
    }

    private let onBack: (() -> Void)?
    private let onDongles: (() -> Void)?
    private let onFireAlarm: (() -> Void)?

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
        let label = UILabel(text: "others".localizedString, textColor: Title_Color, fontSize: 18)
        label.textAlignment = .center
        return label
    }()

    private lazy var donglesView: PJTopbtBoLabView = {
        PJTopbtBoLabView(
            imageName: "device_menu_dongle",
            title: "dongles".localizedString,
            target: self,
            action: #selector(donglesAction)
        )
    }()

    private lazy var fireAlarmView: PJTopbtBoLabView = {
        return PJTopbtBoLabView(
            imageName:"space_device",
            title: "efc_entry_title".localizedString,
            target: self,
            action: #selector(fireAlarmAction)
        )
    }()

    init(
        onBack: (() -> Void)? = nil,
        onDongles: (() -> Void)? = nil,
        onFireAlarm: (() -> Void)? = nil
    ) {
        self.onBack = onBack
        self.onDongles = onDongles
        self.onFireAlarm = onFireAlarm
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func makePopupViewController(
        onBack: (() -> Void)? = nil,
        onDongles: (() -> Void)? = nil,
        onFireAlarm: (() -> Void)? = nil
    ) -> OthersViewController {
        let controller = OthersViewController(
            onBack: onBack,
            onDongles: onDongles,
            onFireAlarm: onFireAlarm
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

    @objc private func donglesAction() {
        dismissSheet { [onDongles] in
            onDongles?()
        }
    }

    @objc private func fireAlarmAction() {
        dismissSheet { [onFireAlarm] in
            onFireAlarm?()
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

        contentView.addSubview(donglesView)
        donglesView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(30))
            make.top.equalTo(backButton.snp.bottom).offset(SCRYFrom(28))
            make.width.equalTo(SCRYFrom(76))
        }

        contentView.addSubview(fireAlarmView)
        fireAlarmView.snp.makeConstraints { make in
            make.left.equalTo(donglesView.snp.right).offset(SCRXFrom(20))
            make.top.width.equalTo(donglesView)
        }
    }
}
