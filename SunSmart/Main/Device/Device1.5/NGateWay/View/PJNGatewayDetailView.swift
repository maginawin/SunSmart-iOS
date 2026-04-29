//
//  PJNGatewayDetailView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJNGatewayDetailView: UIView {

    var nameChanged: ((String) -> Void)?
    var activateChanged: ((Bool) -> Void)?
    var ssidChangeTapped: (() -> Void)?
    var refreshTapped: (() -> Void)?
    var advancedTapped: (() -> Void)?
    var ipModeChanged: ((PJNGatewayModel.NetworkIPMode) -> Void)?
    var ipAddressChanged: ((String) -> Void)?
    var subnetMaskChanged: ((String) -> Void)?
    var gatewayAddressChanged: ((String) -> Void)?
    var primaryDNSChanged: ((String) -> Void)?
    var secondaryDNSChanged: ((String) -> Void)?
    var connectTapped: (() -> Void)?
    var addSpaceTapped: (() -> Void)?
    var deleteSpaceTapped: ((Int) -> Void)?
    var authorizeTapped: (() -> Void)?
    var copyInformationTapped: (() -> Void)?
    var saveTapped: (() -> Void)?

    private let scrollView = UIScrollView()
    private let stackView = UIStackView()
    private let statusCard = PJNGatewayStatusCardView()
    private let nameHeader = PJNGatewaySectionHeaderView()
    private let nameCard = PJNGatewayCardView()
    private let nameRow = PJNGatewayEditableRowView()
    private let activateCard = PJNGatewayCardView()
    private let activateRow = PJNGatewaySwitchRowView()
    private let networkHeader = PJNGatewaySectionHeaderView()
    private let networkCard = PJNGatewayCardView()
    private let ssidRow = PJNGatewayDisplayRowView()
    private let passwordRow = PJNGatewayDisplayRowView()
    private let advancedHeader = PJNGatewayAdvancedHeaderView()
    private let advancedStack = UIStackView()
    private let ipModeView = PJNGatewayIPModeView()
    private let ipAddressRow = PJNGatewayDisplayRowView()
    private let subnetMaskRow = PJNGatewayDisplayRowView()
    private let gatewayAddressRow = PJNGatewayDisplayRowView()
    private let primaryDNSRow = PJNGatewayDisplayRowView()
    private let secondaryDNSRow = PJNGatewayDisplayRowView()
    private let connectButton = PJNGatewayActionButton()
    private let associatedCard = PJNGatewayCardView()
    private let associatedHeader = PJNGatewaySectionHeaderView()
    private let associatedStack = UIStackView()
    private let serverCard = PJNGatewayCardView()
    private let serverHeader = PJNGatewaySectionHeaderView()
    private let serverWarningView = PJNGatewayWarningView()
    private let serverAddressRow = PJNGatewayDisplayRowView()
    private let portRow = PJNGatewayDisplayRowView()
    private let clientIdRow = PJNGatewayDisplayRowView()
    private let copyInformationView = PJNGatewayCopyInformationView()
    private let bottomSaveView = PJNGatewayBottomSaveView()
    private var keyboardInsetBottom: CGFloat = 0

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        bindActions()
        registerKeyboardNotifications()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func render(_ viewModel: PJNGatewayDetailViewModel) {
        statusCard.configure(
            meshAssetName: viewModel.meshAssetName,
            meshStatusText: viewModel.meshStatusText,
            meshStatusColor: UIColor(hex: viewModel.meshStatusColorHex),
            nodeText: viewModel.nodeText,
            wifiAssetName: viewModel.wifiAssetName,
            wifiStatusText: viewModel.wifiStatusText,
            wifiStatusColor: UIColor(hex: viewModel.wifiStatusColorHex),
            wifiSignalQuality: viewModel.wifiSignalQuality
        )
        nameHeader.configure(title: "name".localizedString, actionTitle: nil, showsAction: false)
        networkHeader.configure(title: "ngateway_network_connectivity".localizedString, actionTitle: nil, showsAction: false)
        nameRow.configure(title: "", text: viewModel.name, enabled: viewModel.canEditName)
        activateRow.configure(title: "activate".localizedString, isOn: viewModel.activate, enabled: viewModel.canEditActivate)
        ssidRow.configure(title: "ngateway_ssid".localizedString, value: viewModel.ssidText, trailingImageName: "change", actionInsideField: true, valueWidth: SCRXFrom(240), valueHeight: SCRYFrom(32))
        ssidRow.setHint(viewModel.supportsHintText, actionText: "ngateway_refresh".localizedString, actionLoading: viewModel.isSSIDRefreshing)
        passwordRow.configure(title: "ngateway_password".localizedString, value: viewModel.passwordText, trailingImageName: "eye", actionInsideField: true, isEditable: true, isSecureEntry: true, valueWidth: SCRXFrom(240), valueHeight: SCRYFrom(32))
        passwordRow.setHint(nil)
        advancedHeader.configure(expanded: viewModel.isAdvancedExpanded)
        advancedStack.isHidden = !viewModel.isAdvancedExpanded
        ipModeView.configure(mode: viewModel.ipMode)
        ipAddressRow.configure(title: "ngateway_ip_address".localizedString, value: viewModel.ipAddressText, isEditable: viewModel.canEditNetworkFields, keyboardType: .numbersAndPunctuation, valueWidth: SCRXFrom(182), valueHeight: SCRYFrom(32))
        subnetMaskRow.configure(title: "ngateway_subnet_mask".localizedString, value: viewModel.subnetMaskText, isEditable: viewModel.canEditNetworkFields, keyboardType: .numbersAndPunctuation, valueWidth: SCRXFrom(182), valueHeight: SCRYFrom(32))
        gatewayAddressRow.configure(title: "ngateway_gateway_address".localizedString, value: viewModel.gatewayAddressText, isEditable: viewModel.canEditNetworkFields, keyboardType: .numbersAndPunctuation, valueWidth: SCRXFrom(182), valueHeight: SCRYFrom(32))
        primaryDNSRow.configure(title: "ngateway_primary_dns".localizedString, value: viewModel.primaryDNSText, isEditable: viewModel.canEditNetworkFields, keyboardType: .numbersAndPunctuation, valueWidth: SCRXFrom(182), valueHeight: SCRYFrom(32))
        secondaryDNSRow.configure(title: "ngateway_secondary_dns".localizedString, value: viewModel.secondaryDNSText, isEditable: viewModel.canEditNetworkFields, keyboardType: .numbersAndPunctuation, valueWidth: SCRXFrom(182), valueHeight: SCRYFrom(32))
        connectButton.configure(title: viewModel.connectButtonTitle, loading: viewModel.isConnectButtonLoading)
        associatedHeader.configure(title: "associated_spaces".localizedString, actionTitle: "ngateway_add_action".localizedString, showsAction: viewModel.canAddAssociatedSpace)
        rebuildAssociatedSpaces(viewModel.associatedSpaces)
        serverWarningView.isHidden = !viewModel.showServerWarning
        serverWarningView.configure(text: viewModel.serverWarningText, canAuthorize: viewModel.canAuthorize)
        serverAddressRow.configure(title: "server_address".localizedString, value: viewModel.serverAddressText, valueWidth: SCRXFrom(191), valueHeight: SCRYFrom(32))
        portRow.configure(title: "port".localizedString, value: viewModel.portText, valueWidth: SCRXFrom(191), valueHeight: SCRYFrom(32))
        clientIdRow.configure(title: "client_id".localizedString, value: viewModel.clientIdText, valueWidth: SCRXFrom(248), valueHeight: SCRYFrom(32))
        bottomSaveView.configure(enabled: viewModel.canEditName || viewModel.canEditActivate || viewModel.canAuthorize || viewModel.canAddAssociatedSpace)
    }

    private func rebuildAssociatedSpaces(_ items: [PJNGatewayDetailViewModel.SpaceItem]) {
        associatedStack.arrangedSubviews.forEach {
            associatedStack.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if items.isEmpty {
            let label = UILabel()
            label.text = "ngateway_no_associated_spaces".localizedString
            label.font = .systemFont(ofSize: 13, weight: .regular)
            label.textColor = UIColor(hex: 0xB6BDCB)
            associatedStack.addArrangedSubview(label)
            return
        }

        for (index, item) in items.enumerated() {
            let row = PJNGatewaySpaceRowView()
            row.configure(name: item.name, nodesText: item.nodesText, showsDelete: item.canDelete)
            row.deleteTapped = { [weak self] in
                self?.deleteSpaceTapped?(index)
            }
            associatedStack.addArrangedSubview(row)
        }
    }

    private func setupUI() {
        backgroundColor = UIColor(hex: 0xF5F7FB)

        addSubview(bottomSaveView)
        bottomSaveView.backgroundColor = .white
        bottomSaveView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(56))
        }

        addSubview(scrollView)
        scrollView.showsVerticalScrollIndicator = false
        scrollView.enableKeyboardDismissal()
        scrollView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.bottom.equalTo(bottomSaveView.snp.top)
        }

        scrollView.addSubview(stackView)
        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(12)
        stackView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(12), left: SCRXFrom(16), bottom: SCRYFrom(24), right: SCRXFrom(16)))
            make.width.equalTo(scrollView.snp.width).offset(SCRXFrom(-32))
        }

        stackView.addArrangedSubview(statusCard)

        stackView.addArrangedSubview(nameHeader)
        nameCard.embed(nameRow)
        stackView.addArrangedSubview(nameCard)

        activateCard.embed(activateRow)
        stackView.addArrangedSubview(activateCard)

        stackView.addArrangedSubview(networkHeader)
        networkCard.contentStack.addArrangedSubview(ssidRow)
        networkCard.contentStack.addArrangedSubview(passwordRow)
        networkCard.contentStack.addArrangedSubview(advancedHeader)

        advancedStack.axis = .vertical
        advancedStack.spacing = SCRYFrom(10)
        advancedStack.addArrangedSubview(ipModeView)
        advancedStack.addArrangedSubview(ipAddressRow)
        advancedStack.addArrangedSubview(subnetMaskRow)
        advancedStack.addArrangedSubview(gatewayAddressRow)
        advancedStack.addArrangedSubview(primaryDNSRow)
        advancedStack.addArrangedSubview(secondaryDNSRow)
        advancedStack.addArrangedSubview(connectButton)
        networkCard.contentStack.addArrangedSubview(advancedStack)
        stackView.addArrangedSubview(networkCard)

        associatedHeader.configure(title: "associated_spaces".localizedString, actionTitle: "ngateway_add_action".localizedString, showsAction: true)
        stackView.addArrangedSubview(associatedHeader)
        associatedStack.axis = .vertical
        associatedStack.spacing = SCRYFrom(8)
        associatedCard.contentStack.addArrangedSubview(associatedStack)
        stackView.addArrangedSubview(associatedCard)

        serverHeader.configure(title: "server_information".localizedString, actionTitle: nil, showsAction: false)
        stackView.addArrangedSubview(serverHeader)
        serverCard.contentStack.addArrangedSubview(serverWarningView)
        serverCard.contentStack.addArrangedSubview(serverAddressRow)
        serverCard.contentStack.addArrangedSubview(portRow)
        serverCard.contentStack.addArrangedSubview(clientIdRow)
        stackView.addArrangedSubview(serverCard)

        stackView.addArrangedSubview(copyInformationView)
    }

    private func bindActions() {
        nameRow.textChanged = { [weak self] in self?.nameChanged?($0) }
        activateRow.switchChanged = { [weak self] in self?.activateChanged?($0) }
        ssidRow.topActionTapped = { [weak self] in self?.ssidChangeTapped?() }
        ssidRow.bottomActionTapped = { [weak self] in self?.refreshTapped?() }
        advancedHeader.tapped = { [weak self] in self?.advancedTapped?() }
        ipModeView.modeChanged = { [weak self] in self?.ipModeChanged?($0) }
        ipAddressRow.valueChanged = { [weak self] in self?.ipAddressChanged?($0) }
        subnetMaskRow.valueChanged = { [weak self] in self?.subnetMaskChanged?($0) }
        gatewayAddressRow.valueChanged = { [weak self] in self?.gatewayAddressChanged?($0) }
        primaryDNSRow.valueChanged = { [weak self] in self?.primaryDNSChanged?($0) }
        secondaryDNSRow.valueChanged = { [weak self] in self?.secondaryDNSChanged?($0) }
        connectButton.tapped = { [weak self] in self?.connectTapped?() }
        associatedHeader.actionTapped = { [weak self] in self?.addSpaceTapped?() }
        serverWarningView.authorizeTapped = { [weak self] in self?.authorizeTapped?() }
        copyInformationView.tapped = { [weak self] in self?.copyInformationTapped?() }
        bottomSaveView.tapped = { [weak self] in self?.saveTapped?() }
    }

    private func registerKeyboardNotifications() {
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillChangeFrame(_:)), name: UIResponder.keyboardWillChangeFrameNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(keyboardWillHide(_:)), name: UIResponder.keyboardWillHideNotification, object: nil)
    }

    @objc private func keyboardWillChangeFrame(_ notification: Notification) {
        guard let keyboardFrame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
            return
        }
        let keyboardFrameInView = convert(keyboardFrame, from: nil)
        let overlap = max(0, scrollView.frame.maxY - keyboardFrameInView.minY)
        updateKeyboardInset(overlap, notification: notification)
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        updateKeyboardInset(0, notification: notification)
    }

    private func updateKeyboardInset(_ bottomInset: CGFloat, notification: Notification) {
        keyboardInsetBottom = bottomInset
        let animationDuration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? TimeInterval ?? 0.25
        let animationCurve = notification.userInfo?[UIResponder.keyboardAnimationCurveUserInfoKey] as? UInt ?? 7
        let options = UIView.AnimationOptions(rawValue: animationCurve << 16)

        UIView.animate(withDuration: animationDuration, delay: 0, options: options) {
            self.scrollView.contentInset.bottom = bottomInset + SCRYFrom(24)
            self.scrollView.verticalScrollIndicatorInsets.bottom = bottomInset + SCRYFrom(24)
            self.scrollActiveFieldIfNeeded()
            self.layoutIfNeeded()
        }
    }

    private func scrollActiveFieldIfNeeded() {
        guard let activeView = firstResponder, activeView.isDescendant(of: scrollView) else {
            return
        }
        let activeRect = activeView.convert(activeView.bounds, to: scrollView)
        let expandedRect = activeRect.insetBy(dx: -SCRXFrom(8), dy: -SCRYFrom(12))
        scrollView.scrollRectToVisible(expandedRect, animated: false)
    }
}
