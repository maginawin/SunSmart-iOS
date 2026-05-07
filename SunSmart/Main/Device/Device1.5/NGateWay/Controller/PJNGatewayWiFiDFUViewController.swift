//
//  PJNGatewayWiFiDFUViewController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class PJNGatewayWiFiDFUViewController: UIViewController {

    private let viewModel: PJNGatewayWiFiDFUViewModel
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let cloudImageView = UIImageView()
    private let subtitleLabel = UILabel()
    private let versionCardView = PJNGatewayWiFiDFUVersionCardView()
    private let currentVersionView = PJNGatewayWiFiDFUCurrentVersionView()
    private let statusView = PJNGatewayWiFiDFUStatusView()
    private let actionContainerView = UIView()
    private let actionButton = UIButton(type: .system)

    init(node: Node) {
        self.viewModel = PJNGatewayWiFiDFUViewModel(node: node)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(hex: 0xF5F7FB)
        setupNavigation()
        setupUI()
        bindActions()
        render()
    }

    private func setupNavigation() {
        title = viewModel.model.title
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "history_infos")?.withRenderingMode(.alwaysOriginal),
            style: .plain,
            target: self,
            action: #selector(historyAction)
        )
    }

    private func setupUI() {
        view.addSubview(scrollView)
        view.addSubview(actionContainerView)
        scrollView.showsVerticalScrollIndicator = false
        scrollView.addSubview(contentView)

        scrollView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.bottom.equalTo(actionContainerView.snp.top)
        }

        actionContainerView.backgroundColor = .white
        actionContainerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }

        let actionSeparator = UIView()
        actionSeparator.backgroundColor = UIColor(hex: 0xE8ECF4)
        actionContainerView.addSubview(actionSeparator)
        actionSeparator.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(0.5)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalToSuperview()
        }

        cloudImageView.image = UIImage(named: "version")
        cloudImageView.contentMode = .scaleAspectFit

        subtitleLabel.font = .systemFont(ofSize: 15, weight: .regular)
        subtitleLabel.textColor = UIColor(hex: 0x8B95A7)
        subtitleLabel.textAlignment = .center

        actionButton.backgroundColor = .white
        actionButton.setTitleColor(UIColor(hex: 0x6F78D8), for: .normal)
        actionButton.titleLabel?.font = .systemFont(ofSize: 17, weight: .light)

        [cloudImageView, subtitleLabel, versionCardView, currentVersionView, statusView].forEach {
            contentView.addSubview($0)
        }
        actionContainerView.addSubview(actionButton)

        cloudImageView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(28))
            make.centerX.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(68))
        }

        subtitleLabel.snp.makeConstraints { make in
            make.top.equalTo(cloudImageView.snp.bottom).offset(SCRYFrom(12))
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.right.equalToSuperview().offset(SCRXFrom(-24))
        }

        versionCardView.snp.makeConstraints { make in
            make.top.equalTo(subtitleLabel.snp.bottom).offset(SCRYFrom(22))
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
        }

        currentVersionView.snp.makeConstraints { make in
            make.top.equalTo(versionCardView.snp.bottom).offset(SCRYFrom(12))
            make.left.right.equalTo(versionCardView)
        }

        statusView.snp.makeConstraints { make in
            make.top.equalTo(currentVersionView.snp.bottom).offset(SCRYFrom(24))
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.right.equalToSuperview().offset(SCRXFrom(-24))
            make.bottom.equalToSuperview().offset(SCRYFrom(-24))
        }

        actionButton.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
            make.bottom.equalTo(view.safeAreaLayoutGuide)
        }
    }

    private func bindActions() {
        versionCardView.toggleExpandAction = { [weak self] in
            self?.viewModel.toggleReleaseNotesExpanded()
            self?.render()
        }
        currentVersionView.deleteButton.addTarget(self, action: #selector(deleteAction), for: .touchUpInside)
        actionButton.addTarget(self, action: #selector(actionButtonTapped), for: .touchUpInside)
    }

    private func render() {
        let model = viewModel.model
        subtitleLabel.text = model.subtitle
        versionCardView.configure(
            title: model.newVersionTitle,
            version: model.newVersion,
            packageSizeText: model.packageSizeText,
            releaseDateText: model.releaseDateText,
            releaseNotes: model.releaseNotes,
            isExpanded: model.isReleaseNotesExpanded
        )
        currentVersionView.configure(title: model.currentVersionTitle, version: model.currentVersion)
        statusView.configure(status: model.status)
        actionButton.setTitle(model.status.actionTitle, for: .normal)
    }

    @objc private func historyAction() {
        navigationController?.pushViewController(PJNGatewayWiFiDFUHistoryViewController(), animated: true)
    }

    @objc private func deleteAction() {
        XWHUDManager.showTipHUD("ngateway_wifi_dfu_delete_placeholder".localizedString, isLineFeed: false)
    }

    @objc private func actionButtonTapped() {
        viewModel.cycleStatus()
        render()
    }
}
