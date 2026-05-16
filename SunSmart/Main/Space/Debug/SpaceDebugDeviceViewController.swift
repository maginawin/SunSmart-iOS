//
//  SpaceDebugDeviceViewController.swift
//  SunSmart
//
//  Created on 2026/5/16.
//

import UIKit
import NordicSigMeshSDK

final class SpaceDebugDeviceViewController: UIViewController {
    private let session: DebugBluetoothSession
    private let space: SpaceData
    private let item: SpaceDebugNodeItem
    private let statusLabel = UILabel()
    private let stackView = UIStackView()
    private let actionStackView = UIStackView()
    private let uartStatusLabel = UILabel()
    private let uartButton = UIButton(type: .system)
    private let identifyButton = UIButton(type: .system)
    private var connectionState: SpaceDebugConnectionState = .connected
    private var uartState: SpaceDebugUARTSupportViewState = .checking

    private var isConnected: Bool {
        if case .connected = connectionState {
            return true
        }
        return false
    }

    init(session: DebugBluetoothSession, space: SpaceData, item: SpaceDebugNodeItem) {
        self.session = session
        self.space = space
        self.item = item
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = item.displayTitle
        view.backgroundColor = Background_Color
        setupUI()
        render()
        checkUARTSupport()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        installDisconnectHandler()
    }

    private func installDisconnectHandler() {
        session.onUnexpectedDisconnect = { [weak self] node in
            guard let self = self, node.primaryUnicastAddress == self.item.node.primaryUnicastAddress else {
                return
            }
            self.connectionState = .disconnected
            self.uartState = .disconnected
            self.render()
            self.showDisconnectedAlert()
        }
    }

    private func setupUI() {
        statusLabel.font = Font_Medium_Size(15)
        statusLabel.textColor = Title_Color
        statusLabel.textAlignment = .center
        view.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top).offset(SCRYFrom(16))
        }

        stackView.axis = .vertical
        stackView.spacing = SCRYFrom(10)
        view.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(statusLabel.snp.bottom).offset(SCRYFrom(16))
        }

        actionStackView.axis = .vertical
        actionStackView.spacing = SCRYFrom(12)
        view.addSubview(actionStackView)
        actionStackView.snp.makeConstraints { make in
            make.left.right.equalToSuperview().inset(SCRXFrom(16))
            make.top.equalTo(stackView.snp.bottom).offset(SCRYFrom(16))
            make.bottom.lessThanOrEqualTo(view.safeAreaLayoutGuide.snp.bottom).offset(-SCRYFrom(16))
        }

        uartStatusLabel.font = Font_Medium_Size(14)
        uartStatusLabel.textColor = SubText_Color
        uartStatusLabel.textAlignment = .center
        uartStatusLabel.numberOfLines = 0
        actionStackView.addArrangedSubview(uartStatusLabel)

        uartButton.setTitle("debug_uart".localizedString, for: .normal)
        uartButton.setTitleColor(.white, for: .normal)
        uartButton.setTitleColor(.white.withAlphaComponent(0.6), for: .disabled)
        uartButton.titleLabel?.font = Font_Medium_Size(15)
        uartButton.backgroundColor = Bar_Color
        uartButton.layer.cornerRadius = SCRXFrom(8)
        uartButton.addTarget(self, action: #selector(openUARTAction), for: .touchUpInside)
        actionStackView.addArrangedSubview(uartButton)
        uartButton.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(48))
        }

        identifyButton.setTitle("identify".localizedString, for: .normal)
        identifyButton.setTitleColor(.white, for: .normal)
        identifyButton.setTitleColor(.white.withAlphaComponent(0.6), for: .disabled)
        identifyButton.titleLabel?.font = Font_Medium_Size(15)
        identifyButton.backgroundColor = Bar_Color
        identifyButton.layer.cornerRadius = SCRXFrom(8)
        identifyButton.addTarget(self, action: #selector(identifyAction), for: .touchUpInside)
        actionStackView.addArrangedSubview(identifyButton)
        identifyButton.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(48))
        }
    }

    private func render() {
        statusLabel.text = connectionState.title
        updateIdentifyButtonState()
        updateUARTState()
        stackView.arrangedSubviews.forEach { view in
            stackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        addInfoRow(title: "debug_node_address".localizedString, value: "\(item.node.primaryUnicastAddress)")
        addInfoRow(title: "mac".localizedString, value: item.node.macAddressResult ?? item.node.macAddress ?? "--")
        addInfoRow(title: "RSSI", value: item.rssi.map { "\($0)dBm" } ?? "--")
        addInfoRow(title: "debug_pid".localizedString, value: item.node.productIdentifier.map { String(format: "0x%04X", $0) } ?? "--")
        addInfoRow(title: "debug_cid".localizedString, value: item.node.companyIdentifier.map { String(format: "0x%04X", $0) } ?? "--")
        addInfoRow(title: "device_type".localizedString, value: item.category.title)
        addInfoRow(title: "debug_ble_services".localizedString, value: "debug_ble_services_empty".localizedString)
    }

    private func updateIdentifyButtonState() {
        identifyButton.isEnabled = isConnected
        identifyButton.alpha = isConnected ? 1 : 0.45
    }

    private func updateUARTState() {
        uartButton.isEnabled = isConnected
        uartButton.alpha = isConnected ? 1 : 0.45

        switch uartState {
        case .checking:
            uartStatusLabel.isHidden = false
            uartStatusLabel.text = "debug_uart_checking".localizedString
            uartButton.isHidden = true
        case .supported:
            uartStatusLabel.isHidden = true
            uartStatusLabel.text = nil
            uartButton.isHidden = false
        case .unsupported:
            uartStatusLabel.isHidden = false
            uartStatusLabel.text = "debug_uart_unsupported_message".localizedString
            uartButton.isHidden = true
        case .disconnected:
            uartStatusLabel.isHidden = false
            uartStatusLabel.text = "debug_uart_disconnected".localizedString
            uartButton.isHidden = true
        case .failed(let message):
            uartStatusLabel.isHidden = false
            uartStatusLabel.text = message
            uartButton.isHidden = true
        }
    }

    private func addInfoRow(title: String, value: String) {
        let row = UIView()
        row.backgroundColor = .white
        row.layer.cornerRadius = SCRXFrom(8)

        let titleLabel = UILabel()
        titleLabel.font = FONTS(SCRXFrom(13))
        titleLabel.textColor = SubText_Color
        titleLabel.text = title
        row.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(12))
        }

        let valueLabel = UILabel()
        valueLabel.font = FONTS(SCRXFrom(13))
        valueLabel.textColor = Title_Color
        valueLabel.textAlignment = .right
        valueLabel.numberOfLines = 0
        valueLabel.text = value
        row.addSubview(valueLabel)
        valueLabel.snp.makeConstraints { make in
            make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(12))
            make.right.equalTo(SCRXFrom(-16))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(12))
        }

        stackView.addArrangedSubview(row)
    }

    private func showDisconnectedAlert() {
        SRAlertView(title: "notification".localizedString, message: "debug_connection_disconnected_message".localizedString, actions: [
            SRAlertAction(title: "close".localizedString, actionHandler: { [weak self] _ in
                self?.navigationController?.popViewController(animated: true)
            }),
            SRAlertAction(title: "debug_reconnect".localizedString, actionHandler: { [weak self] _ in
                self?.reconnect()
            })
        ]).show()
    }

    @objc private func identifyAction() {
        guard case .connected = connectionState else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        MeshAPI.identify(address: item.node.primaryUnicastAddress, attentionTimer: 6)
    }

    @objc private func openUARTAction() {
        guard isConnected else {
            XWHUDManager.showTipHUD("device_notconnect_message".localizedString, isLineFeed: true)
            return
        }
        guard case .supported = uartState else {
            XWHUDManager.showTipHUD("debug_uart_unsupported_message".localizedString, isLineFeed: true)
            return
        }
        let controller = SpaceDebugUARTViewController(session: session, space: space, item: item)
        navigationController?.pushViewController(controller, animated: true)
    }

    private func reconnect() {
        connectionState = .reconnecting
        render()
        session.reconnect { [weak self] success in
            guard let self = self else {
                return
            }
            self.connectionState = success ? .connected : .disconnected
            self.uartState = success ? .checking : .disconnected
            self.render()
            if success {
                self.checkUARTSupport()
            } else {
                self.showDisconnectedAlert()
            }
        }
    }

    private func checkUARTSupport() {
        guard isConnected else {
            uartState = .disconnected
            render()
            return
        }
        uartState = .checking
        render()
        session.checkUARTSupport { [weak self] state in
            guard let self = self else {
                return
            }
            self.uartState = state
            self.render()
        }
    }
}
