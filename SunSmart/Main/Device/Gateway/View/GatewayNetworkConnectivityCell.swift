//
//  GatewayNetworkConnectivityCell.swift
//  SunSmart
//

import UIKit

final class GatewayNetworkConnectivityCell: UITableViewCell, UITextFieldDelegate {
    static let reuseIdentifier = "GatewayNetworkConnectivityCell"

    enum ConnectState {
        case disabled
        case available
        case connecting
        case connected
    }

    var selectWiFiCallback: (() -> Void)?
    var refreshCallback: (() -> Void)?
    var ssidClearCallback: (() -> Void)?
    var passwordChangedCallback: ((String) -> ConnectState)?
    var togglePasswordVisibilityCallback: (() -> Void)?
    var connectActionCallback: (() -> Void)?

    private let containerView = UIView()
    private let ssidTitleLabel = UILabel()
    private let ssidValueLabel = UILabel()
    private let ssidInputView = UIView()
    private let selectWiFiButton = UIButton(type: .custom)
    private let ssidClearButton = UIButton(type: .custom)
    private let noteLabel = UILabel()
    private let refreshButton = UIButton(type: .custom)
    private let passwordTitleLabel = UILabel()
    private let passwordInputView = UIView()
    private let passwordTextField = UITextField()
    private let passwordVisibilityButton = UIButton(type: .custom)
    private let connectButton = UIButton(type: .custom)
    private let loadingImageView = UIImageView()
    private var currentPassword: String = ""

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        selectWiFiCallback = nil
        refreshCallback = nil
        ssidClearCallback = nil
        passwordChangedCallback = nil
        togglePasswordVisibilityCallback = nil
        connectActionCallback = nil
        loadingImageView.layer.removeAnimation(forKey: "loading")
    }

    func update(ssid: String, password: String, passwordVisible: Bool, connectState: ConnectState) {
        update(
            ssid: ssid,
            password: password,
            passwordVisible: passwordVisible,
            connectState: connectState,
            showsSSIDClearButton: false,
            canSelectWiFi: connectState != .connected,
            canRefresh: connectState != .connected,
            canEditPassword: true
        )
    }

    func update(
        ssid: String,
        password: String,
        passwordVisible: Bool,
        connectState: ConnectState,
        showsSSIDClearButton: Bool,
        canSelectWiFi: Bool,
        canRefresh: Bool,
        canEditPassword: Bool
    ) {
        ssidValueLabel.text = ssid
        currentPassword = password
        passwordTextField.text = password
        passwordTextField.isSecureTextEntry = !passwordVisible
        passwordVisibilityButton.setImage(UIImage(named: passwordVisible ? "show_password" : "hide_password"), for: .normal)
        ssidClearButton.isHidden = !showsSSIDClearButton
        apply(
            connectState: connectState,
            canSelectWiFi: canSelectWiFi,
            canRefresh: canRefresh,
            canEditPassword: canEditPassword
        )
    }

    private func setupUI() {
        backgroundColor = .clear
        contentView.backgroundColor = .clear

        containerView.backgroundColor = .white
        containerView.layer.cornerRadius = SCRYFrom(10)
        containerView.layer.masksToBounds = true
        contentView.addSubview(containerView)
        containerView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.left.right.equalToSuperview()
        }

        [ssidTitleLabel, passwordTitleLabel].forEach {
            $0.font = UIFont.systemFont(ofSize: 14, weight: .light)
            $0.textColor = ImportantText_Color
        }
        ssidTitleLabel.text = "ssid".localizedString
        passwordTitleLabel.text = "Password".localizedString

        [ssidInputView, passwordInputView].forEach {
            $0.backgroundColor = RGB(248, 250, 252)
            $0.layer.cornerRadius = SCRYFrom(5)
            $0.layer.borderWidth = 0.5
            $0.layer.borderColor = RGB(236, 236, 236).cgColor
        }

        ssidValueLabel.font = UIFont.systemFont(ofSize: 14, weight: .light)
        ssidValueLabel.textColor = TextBlack_Color
        ssidValueLabel.lineBreakMode = .byTruncatingTail

        selectWiFiButton.setImage(UIImage(named: "select_wifi"), for: .normal)
        selectWiFiButton.addTarget(self, action: #selector(selectWiFiAction), for: .touchUpInside)

        ssidClearButton.setImage(UIImage(named: "nameField_clear") ?? UIImage(named: "close"), for: .normal)
        ssidClearButton.addTarget(self, action: #selector(clearSSIDAction), for: .touchUpInside)
        ssidClearButton.isHidden = true

        noteLabel.font = UIFont.systemFont(ofSize: 12, weight: .light)
        noteLabel.textColor = SubText_Color
        noteLabel.text = "only_supports_24ghz_networks".localizedString

        refreshButton.titleLabel?.font = UIFont.systemFont(ofSize: 13, weight: .medium)
        refreshButton.setTitle("refresh".localizedString, for: .normal)
        refreshButton.setTitleColor(Bar_Color, for: .normal)
        refreshButton.addTarget(self, action: #selector(refreshAction), for: .touchUpInside)

        passwordTextField.font = UIFont.systemFont(ofSize: 14, weight: .light)
        passwordTextField.textColor = TextBlack_Color
        passwordTextField.isSecureTextEntry = true
        passwordTextField.textContentType = .password
        passwordTextField.autocorrectionType = .no
        passwordTextField.autocapitalizationType = .none
        passwordTextField.returnKeyType = .done
        passwordTextField.delegate = self
        passwordTextField.addTarget(self, action: #selector(passwordChanged), for: .editingChanged)

        passwordVisibilityButton.addTarget(self, action: #selector(togglePasswordVisibilityAction), for: .touchUpInside)

        connectButton.layer.cornerRadius = SCRYFrom(15)
        connectButton.layer.borderWidth = 1
        connectButton.layer.borderColor = Bar_Color.withAlphaComponent(0.5).cgColor
        connectButton.backgroundColor = .white
        connectButton.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .medium)
        connectButton.addTarget(self, action: #selector(connectAction), for: .touchUpInside)

        loadingImageView.image = UIImage(named: "loading_16")
        loadingImageView.isHidden = true

        layoutViews()
    }

    private func layoutViews() {
        containerView.addSubview(ssidTitleLabel)
        containerView.addSubview(ssidInputView)
        ssidInputView.addSubview(ssidValueLabel)
        ssidInputView.addSubview(ssidClearButton)
        ssidInputView.addSubview(selectWiFiButton)
        containerView.addSubview(noteLabel)
        containerView.addSubview(refreshButton)
        containerView.addSubview(passwordTitleLabel)
        containerView.addSubview(passwordInputView)
        passwordInputView.addSubview(passwordTextField)
        passwordInputView.addSubview(passwordVisibilityButton)
        containerView.addSubview(connectButton)
        connectButton.addSubview(loadingImageView)

        ssidTitleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.top.equalToSuperview().offset(SCRYFrom(16))
            make.width.equalTo(SCRXFrom(62))
            make.height.equalTo(SCRYFrom(32))
        }
        ssidInputView.snp.makeConstraints { make in
            make.left.equalTo(ssidTitleLabel.snp.right).offset(SCRXFrom(8))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.centerY.equalTo(ssidTitleLabel)
            make.height.equalTo(SCRYFrom(32))
        }
        selectWiFiButton.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        ssidClearButton.snp.makeConstraints { make in
            make.right.equalTo(selectWiFiButton.snp.left)
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        ssidValueLabel.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(8))
            make.right.equalTo(ssidClearButton.snp.left).offset(SCRXFrom(-4))
            make.centerY.equalToSuperview()
        }
        noteLabel.snp.makeConstraints { make in
            make.left.equalTo(ssidInputView)
            make.top.equalTo(ssidInputView.snp.bottom).offset(SCRYFrom(4))
            make.height.equalTo(SCRYFrom(24))
        }
        refreshButton.snp.makeConstraints { make in
            make.right.equalTo(ssidInputView)
            make.centerY.equalTo(noteLabel)
        }
        passwordTitleLabel.snp.makeConstraints { make in
            make.left.width.height.equalTo(ssidTitleLabel)
            make.top.equalTo(noteLabel.snp.bottom).offset(SCRYFrom(12))
        }
        passwordInputView.snp.makeConstraints { make in
            make.left.right.height.equalTo(ssidInputView)
            make.centerY.equalTo(passwordTitleLabel)
        }
        passwordVisibilityButton.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(30))
        }
        passwordTextField.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(8))
            make.right.equalTo(passwordVisibilityButton.snp.left).offset(SCRXFrom(-4))
            make.top.bottom.equalToSuperview()
        }
        connectButton.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(16))
            make.right.equalToSuperview().offset(SCRXFrom(-16))
            make.top.equalTo(passwordInputView.snp.bottom).offset(SCRYFrom(10))
            make.height.equalTo(SCRYFrom(32))
            make.bottom.equalToSuperview().offset(SCRYFrom(-16))
        }
        loadingImageView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.width.height.equalTo(SCRYFrom(24))
        }
    }

    private func apply(
        connectState: ConnectState,
        canSelectWiFi: Bool,
        canRefresh: Bool,
        canEditPassword: Bool
    ) {
        let isConnecting = connectState == .connecting
        let isConnected = connectState == .connected

        selectWiFiButton.isEnabled = canSelectWiFi && !isConnecting
        refreshButton.isEnabled = canRefresh && !isConnecting
        passwordTextField.isEnabled = canEditPassword && !isConnecting && !isConnected
        passwordVisibilityButton.isEnabled = canEditPassword && !isConnecting && !isConnected
        ssidClearButton.isEnabled = !isConnecting

        loadingImageView.isHidden = !isConnecting
        if isConnecting {
            loadingImageView.layer.addRotationAnimation(duration: 1.2, repeatCount: .max, animationKey: "loading")
        } else {
            loadingImageView.layer.removeAnimation(forKey: "loading")
        }

        let title: String?
        if isConnecting {
            title = nil
        } else if isConnected {
            title = "disconnect".localizedString
        } else {
            title = "connect_to_wifi".localizedString
        }
        connectButton.setTitle(title, for: .normal)
        connectButton.setTitleColor(connectState == .disabled ? RGB(147, 148, 196) : Bar_Color, for: .normal)
        connectButton.isEnabled = connectState != .disabled && !isConnecting
    }

    @objc private func selectWiFiAction() {
        selectWiFiCallback?()
    }

    @objc private func refreshAction() {
        refreshCallback?()
    }

    @objc private func passwordChanged() {
        let password = passwordTextField.text ?? ""
        guard password.canBeConverted(to: .ascii) else {
            passwordTextField.text = currentPassword
            _ = passwordChangedCallback?(password)
            return
        }
        currentPassword = password
        let nextState = passwordChangedCallback?(password) ?? .disabled
        apply(
            connectState: nextState,
            canSelectWiFi: selectWiFiButton.isEnabled,
            canRefresh: refreshButton.isEnabled,
            canEditPassword: passwordTextField.isEnabled
        )
    }

    @objc private func togglePasswordVisibilityAction() {
        togglePasswordVisibilityCallback?()
    }

    @objc private func clearSSIDAction() {
        ssidClearCallback?()
    }

    @objc private func connectAction() {
        connectActionCallback?()
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        endEditing(true)
        return true
    }
}
