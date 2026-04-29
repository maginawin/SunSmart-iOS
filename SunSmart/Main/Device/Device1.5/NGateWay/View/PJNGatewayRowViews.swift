//
//  PJNGatewayRowViews.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJNGatewayEditableRowView: UIView, UITextFieldDelegate {

    var textChanged: ((String) -> Void)?

    private let titleLabel = UILabel()
    private let textField = UITextField()
    private let clearButton = UIButton(type: .system)

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor(hex: 0x2F3555)
        textField.font = .systemFont(ofSize: 14, weight: .regular)
        textField.textAlignment = .right
        textField.textColor = UIColor(hex: 0x6B7280)
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(textDidChange), for: .editingChanged)
        clearButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        clearButton.tintColor = UIColor(hex: 0xC7CBD4)
        clearButton.addTarget(self, action: #selector(clearAction), for: .touchUpInside)

        addSubview(titleLabel)
        addSubview(clearButton)
        addSubview(textField)
        titleLabel.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
        }
        clearButton.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(18))
        }
        updateTextFieldConstraints(titleIsEmpty: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, text: String, enabled: Bool) {
        titleLabel.text = title
        textField.text = text
        textField.isEnabled = enabled
        clearButton.isHidden = !enabled
        titleLabel.isHidden = title.isEmpty
        textField.textAlignment = title.isEmpty ? .left : .right
        updateTextFieldConstraints(titleIsEmpty: title.isEmpty)
    }

    private func updateTextFieldConstraints(titleIsEmpty: Bool) {
        textField.snp.remakeConstraints { make in
            if titleIsEmpty {
                make.left.equalToSuperview()
            } else {
                make.left.greaterThanOrEqualTo(titleLabel.snp.right).offset(SCRXFrom(10))
            }
            make.right.equalTo(clearButton.snp.left).offset(SCRXFrom(-8))
            make.top.bottom.equalToSuperview().inset(SCRYFrom(4))
        }
    }

    @objc private func textDidChange() {
        textChanged?(textField.text ?? "")
    }

    @objc private func clearAction() {
        textField.text = nil
        textChanged?("")
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class PJNGatewaySwitchRowView: UIView {

    var switchChanged: ((Bool) -> Void)?

    private let titleLabel = UILabel()
    private let toggle = UISwitch()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor(hex: 0x2F3555)
        toggle.onTintColor = UIColor(hex: 0x6366C8)
        toggle.addTarget(self, action: #selector(toggleAction), for: .valueChanged)

        addSubview(titleLabel)
        addSubview(toggle)
        titleLabel.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
        }
        toggle.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
        }
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(24))
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, isOn: Bool, enabled: Bool) {
        titleLabel.text = title
        toggle.isOn = isOn
        toggle.isEnabled = enabled
    }

    @objc private func toggleAction() {
        switchChanged?(toggle.isOn)
    }
}

final class PJNGatewayDisplayRowView: UIView, UITextFieldDelegate {

    var topActionTapped: (() -> Void)?
    var bottomActionTapped: (() -> Void)?
    var valueChanged: ((String) -> Void)?

    private let titleLabel = UILabel()
    private let valueLabel = UILabel()
    private let valueField = UITextField()
    private let valueContainer = UIView()
    private let valueTrailingButton = UIButton(type: .system)
    private let valueTrailingImageButton = UIButton(type: .system)
    private let topActionButton = UIButton(type: .system)
    private let bottomActionButton = UIButton(type: .system)
    private let trailingImageView = UIImageView()
    private let hintLabel = UILabel()
    private let bottomRow = UIStackView()
    private let bottomActionLoadingView = UIActivityIndicatorView(style: .medium)
    private var secureToggleEnabled = false
    private var secureHiddenImageName = "hide"
    private var secureVisibleImageName = "display"
    private var valueContainerWidthConstraint: Constraint?
    private var valueContainerHeightConstraint: Constraint?

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor(hex: 0x2F3555)
        valueLabel.font = .systemFont(ofSize: 14, weight: .regular)
        valueLabel.textColor = UIColor(hex: 0xA1A8B8)
        valueLabel.textAlignment = .left
        valueField.font = .systemFont(ofSize: 14, weight: .regular)
        valueField.textColor = UIColor(hex: 0x6B7280)
        valueField.textAlignment = .left
        valueField.returnKeyType = .done
        valueField.delegate = self
        valueField.addTarget(self, action: #selector(valueFieldChanged), for: .editingChanged)
        valueContainer.backgroundColor = UIColor(hex: 0xF6F7FB)
        valueContainer.layer.cornerRadius = SCRYFrom(8)
        valueTrailingButton.setTitleColor(UIColor(hex: 0x6366C8), for: .normal)
        valueTrailingButton.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        valueTrailingButton.addTarget(self, action: #selector(topActionButtonAction), for: .touchUpInside)
        valueTrailingButton.contentHorizontalAlignment = .right
        valueTrailingButton.isHidden = true
        valueTrailingImageButton.tintColor = UIColor(hex: 0x8B95A7)
        valueTrailingImageButton.contentHorizontalAlignment = .right
        valueTrailingImageButton.isHidden = true
        valueTrailingImageButton.addTarget(self, action: #selector(valueTrailingImageAction), for: .touchUpInside)
        [topActionButton, bottomActionButton].forEach {
            $0.setTitleColor(UIColor(hex: 0x6366C8), for: .normal)
            $0.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            $0.contentHorizontalAlignment = .right
            $0.isHidden = true
        }
        topActionButton.addTarget(self, action: #selector(topActionButtonAction), for: .touchUpInside)
        bottomActionButton.addTarget(self, action: #selector(bottomActionButtonAction), for: .touchUpInside)
        trailingImageView.contentMode = .scaleAspectFit
        trailingImageView.tintColor = UIColor(hex: 0x8B95A7)
        trailingImageView.isHidden = true
        hintLabel.font = .systemFont(ofSize: 12, weight: .regular)
        hintLabel.textColor = UIColor(hex: 0xC7CBD4)
        hintLabel.numberOfLines = 0
        hintLabel.isHidden = true
        bottomActionLoadingView.color = UIColor(hex: 0x8C88D8)
        bottomActionLoadingView.hidesWhenStopped = true
        bottomActionLoadingView.isHidden = true

        valueContainer.addSubview(valueLabel)
        valueContainer.addSubview(valueField)
        valueContainer.addSubview(valueTrailingButton)
        valueContainer.addSubview(valueTrailingImageButton)
        valueLabel.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(7), left: SCRXFrom(10), bottom: SCRYFrom(7), right: SCRXFrom(10)))
        }
        valueField.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview().inset(SCRYFrom(7))
            make.left.equalToSuperview().offset(SCRXFrom(10))
            make.right.equalToSuperview().offset(SCRXFrom(-10))
        }
        valueTrailingButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-10))
            make.centerY.equalToSuperview()
        }
        valueTrailingImageButton.snp.makeConstraints { make in
            make.right.equalToSuperview().offset(SCRXFrom(-10))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(16))
        }
        valueContainer.snp.makeConstraints { make in
            valueContainerHeightConstraint = make.height.equalTo(SCRYFrom(32)).constraint
            valueContainerWidthConstraint = make.width.equalTo(SCRXFrom(240)).constraint
        }

        addSubview(titleLabel)
        addSubview(valueContainer)
        addSubview(topActionButton)
        addSubview(trailingImageView)
        addSubview(bottomRow)

        bottomRow.axis = .horizontal
        bottomRow.alignment = .center
        bottomRow.spacing = SCRXFrom(8)
        bottomRow.addArrangedSubview(hintLabel)
        bottomRow.addArrangedSubview(UIView())
        bottomRow.addArrangedSubview(bottomActionButton)
        bottomRow.addArrangedSubview(bottomActionLoadingView)

        titleLabel.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.centerY.equalTo(valueContainer.snp.centerY)
        }
        topActionButton.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(valueContainer.snp.centerY)
        }
        trailingImageView.snp.makeConstraints { make in
            make.right.equalToSuperview()
            make.centerY.equalTo(valueContainer.snp.centerY)
            make.width.height.equalTo(SCRXFrom(16))
        }
        valueContainer.snp.makeConstraints { make in
            make.top.equalToSuperview()
            make.right.equalToSuperview()
        }
        bottomRow.snp.makeConstraints { make in
            make.top.equalTo(valueContainer.snp.bottom).offset(SCRYFrom(6))
            make.left.equalTo(valueContainer.snp.left)
            make.right.equalTo(valueContainer.snp.right)
            make.bottom.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, value: String, topActionText: String? = nil, bottomActionText: String? = nil, trailingImageName: String? = nil, actionInsideField: Bool = false, isEditable: Bool = false, isSecureEntry: Bool = false, keyboardType: UIKeyboardType = .default, valueWidth: CGFloat = SCRXFrom(240), valueHeight: CGFloat = SCRYFrom(32)) {
        titleLabel.text = title
        valueLabel.text = value.isEmpty ? "--" : value
        valueField.text = value
        valueField.keyboardType = keyboardType
        valueField.isEnabled = isEditable
        valueField.isSecureTextEntry = isSecureEntry
        valueField.isHidden = !isEditable
        valueLabel.isHidden = isEditable
        valueContainer.backgroundColor = UIColor(hex: 0xF6F7FB)
        valueContainer.layer.borderWidth = isEditable ? 0.5 : 0
        valueContainer.layer.borderColor = UIColor(hex: 0xDDE2EC).cgColor
        topActionButton.setTitle(topActionText, for: .normal)
        topActionButton.isHidden = topActionText == nil || actionInsideField
        bottomActionButton.setTitle(bottomActionText, for: .normal)
        bottomActionButton.isHidden = bottomActionText == nil
        trailingImageView.image = trailingImageName.flatMap { UIImage(named: $0) }
        if trailingImageView.image == nil, let trailingImageName {
            trailingImageView.image = UIImage(systemName: trailingImageName)
        }
        trailingImageView.isHidden = trailingImageName == nil || actionInsideField
        valueTrailingButton.setTitle(topActionText, for: .normal)
        valueTrailingButton.isHidden = topActionText == nil || !actionInsideField
        valueTrailingImageButton.setImage(trailingImageView.image, for: .normal)
        valueTrailingImageButton.isHidden = trailingImageName == nil || !actionInsideField
        secureToggleEnabled = isSecureEntry && actionInsideField && trailingImageName != nil
        if secureToggleEnabled {
            updateSecureToggleImage(isSecure: valueField.isSecureTextEntry)
        }
        valueContainerWidthConstraint?.update(offset: valueWidth)
        valueContainerHeightConstraint?.update(offset: valueHeight)
        let rightInset = actionInsideField && (topActionText != nil || trailingImageName != nil) ? SCRXFrom(52) : SCRXFrom(10)
        valueLabel.snp.updateConstraints { make in
            make.right.equalToSuperview().offset(-rightInset)
        }
        valueField.snp.updateConstraints { make in
            make.right.equalToSuperview().offset(-rightInset)
        }
        valueContainer.snp.updateConstraints { make in
            make.right.equalToSuperview().offset((actionInsideField || (topActionText == nil && trailingImageName == nil)) ? 0 : -SCRXFrom(26))
        }
    }

    func setHint(_ text: String?, actionText: String? = nil, actionLoading: Bool = false) {
        hintLabel.text = text
        hintLabel.isHidden = text == nil
        bottomActionButton.setTitle(actionText, for: .normal)
        bottomActionButton.isHidden = actionText == nil || actionLoading
        bottomActionLoadingView.isHidden = !actionLoading
        if actionLoading {
            bottomActionLoadingView.startAnimating()
        } else {
            bottomActionLoadingView.stopAnimating()
        }
        bottomRow.isHidden = text == nil && actionText == nil && !actionLoading
    }

    @objc private func topActionButtonAction() {
        topActionTapped?()
    }

    @objc private func bottomActionButtonAction() {
        bottomActionTapped?()
    }

    @objc private func valueFieldChanged() {
        valueChanged?(valueField.text ?? "")
    }

    @objc private func valueTrailingImageAction() {
        guard secureToggleEnabled else {
            topActionTapped?()
            return
        }
        valueField.isSecureTextEntry.toggle()
        updateSecureToggleImage(isSecure: valueField.isSecureTextEntry)
    }

    private func updateSecureToggleImage(isSecure: Bool) {
        let imageName = isSecure ? secureHiddenImageName : secureVisibleImageName
        let fallbackSystemName = isSecure ? "eye.slash" : "eye"
        let image = UIImage(named: imageName) ?? UIImage(systemName: fallbackSystemName)
        valueTrailingImageButton.setImage(image, for: .normal)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

final class PJNGatewayAdvancedHeaderView: UIControl {

    var tapped: (() -> Void)?

    private let titleLabel = UILabel()
    private let arrowView = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        titleLabel.text = "ngateway_advance_network_settings".localizedString
        titleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.textColor = UIColor(hex: 0x2F3555)
        arrowView.tintColor = UIColor(hex: 0x6B7280)

        addSubview(titleLabel)
        addSubview(arrowView)
        titleLabel.snp.makeConstraints { make in
            make.left.centerY.equalToSuperview()
        }
        arrowView.snp.makeConstraints { make in
            make.right.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(16))
        }
        snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(24))
        }
        addTarget(self, action: #selector(handleTap), for: .touchUpInside)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(expanded: Bool) {
        arrowView.image = UIImage(systemName: expanded ? "chevron.up" : "chevron.down")
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: SCRYFrom(24))
    }

    @objc private func handleTap() {
        tapped?()
    }
}

final class PJNGatewayIPModeView: UIView {

    var modeChanged: ((PJNGatewayModel.NetworkIPMode) -> Void)?

    private let dhcpButton = UIButton(type: .system)
    private let staticButton = UIButton(type: .system)
    private var currentMode: PJNGatewayModel.NetworkIPMode = .dhcp

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor(hex: 0xF6F7FB)
        layer.cornerRadius = SCRYFrom(18)
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(hex: 0xDDE2EC).cgColor

        [dhcpButton, staticButton].forEach {
            $0.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
            $0.layer.cornerRadius = SCRYFrom(16)
            $0.addTarget(self, action: #selector(modeButtonAction(_:)), for: .touchUpInside)
        }
        dhcpButton.setTitle("ngateway_dhcp".localizedString, for: .normal)
        staticButton.setTitle("ngateway_static_ip".localizedString, for: .normal)

        let row = UIStackView(arrangedSubviews: [dhcpButton, staticButton])
        row.axis = .horizontal
        row.spacing = SCRXFrom(8)
        row.distribution = .fillEqually
        addSubview(row)
        row.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(UIEdgeInsets(top: SCRYFrom(4), left: SCRXFrom(4), bottom: SCRYFrom(4), right: SCRXFrom(4)))
            make.height.equalTo(SCRYFrom(34))
        }
        updateButtons()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(mode: PJNGatewayModel.NetworkIPMode) {
        currentMode = mode
        updateButtons()
    }

    @objc private func modeButtonAction(_ sender: UIButton) {
        currentMode = sender == dhcpButton ? .dhcp : .staticIP
        updateButtons()
        modeChanged?(currentMode)
    }

    private func updateButtons() {
        configure(button: dhcpButton, selected: currentMode == .dhcp)
        configure(button: staticButton, selected: currentMode == .staticIP)
    }

    private func configure(button: UIButton, selected: Bool) {
        button.backgroundColor = selected ? UIColor(hex: 0x6366C8) : .clear
        button.setTitleColor(selected ? .white : UIColor(hex: 0xB5BCCB), for: .normal)
    }
}

final class PJNGatewayActionButton: UIView {

    var tapped: (() -> Void)?

    private let button = UIButton(type: .system)
    private let indicator = UIActivityIndicatorView(style: .medium)

    override init(frame: CGRect) {
        super.init(frame: frame)
        button.layer.cornerRadius = SCRYFrom(20)
        button.layer.borderWidth = 0.5
        button.layer.borderColor = UIColor(hex: 0xCDD3E1).cgColor
        button.setTitleColor(UIColor(hex: 0x6366C8), for: .normal)
        button.titleLabel?.font = .systemFont(ofSize: 14, weight: .medium)
        button.addTarget(self, action: #selector(buttonAction), for: .touchUpInside)

        addSubview(button)
        button.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        indicator.hidesWhenStopped = true
        button.addSubview(indicator)
        indicator.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(title: String, loading: Bool) {
        button.setTitle(loading ? nil : title, for: .normal)
        button.isEnabled = !loading
        if loading {
            indicator.startAnimating()
        } else {
            indicator.stopAnimating()
        }
    }

    @objc private func buttonAction() {
        tapped?()
    }
}
