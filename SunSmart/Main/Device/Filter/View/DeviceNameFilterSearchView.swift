//
//  DeviceNameFilterSearchView.swift
//  SunSmart
//
//  Created by One on 2026/7/22.
//

import UIKit

final class DeviceNameFilterSearchView: UIControl, UITextFieldDelegate {
    private let cardView = UIView()
    private let searchBackgroundView = UIView()
    private let textField = UITextField()
    private var onSubmit: ((String) -> Void)?

    static func show(initialText: String, onSubmit: @escaping (String) -> Void) {
        let window = UIApplication.shared.keyWindow()
        window.subviews.compactMap { $0 as? DeviceNameFilterSearchView }
            .forEach { $0.removeFromSuperview() }
        window.subviews.compactMap { $0 as? DeviceNameFilterMenuView }
            .forEach { $0.removeFromSuperview() }

        let searchView = DeviceNameFilterSearchView(frame: window.bounds)
        searchView.onSubmit = onSubmit
        searchView.setupUI(initialText: initialText)
        window.addSubview(searchView)

        DispatchQueue.main.async {
            searchView.textField.becomeFirstResponder()
        }
    }

    private func setupUI(initialText: String) {
        backgroundColor = UIColor.black.withAlphaComponent(0.2)
        accessibilityViewIsModal = true
        addTarget(self, action: #selector(cancel), for: .touchUpInside)

        cardView.backgroundColor = .white
        cardView.layer.cornerRadius = SCRYFrom(16)
        cardView.layer.shadowColor = UIColor.black.cgColor
        cardView.layer.shadowOpacity = 0.15
        cardView.layer.shadowRadius = SCRYFrom(5)
        cardView.layer.shadowOffset = CGSize(width: 0, height: SCRYFrom(-4))
        addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.top).offset(SCRYFrom(96))
            make.centerX.equalToSuperview()
            make.left.greaterThanOrEqualTo(SCRXFrom(16))
            make.right.lessThanOrEqualTo(SCRXFrom(-16))
            make.width.equalTo(SCRXFrom(340)).priority(.high)
            make.height.equalTo(SCRYFrom(65))
        }

        searchBackgroundView.backgroundColor = RGB(248, 250, 252)
        searchBackgroundView.layer.borderColor = RGB(193, 207, 226).cgColor
        searchBackgroundView.layer.borderWidth = 2.0 / 3.0
        searchBackgroundView.layer.cornerRadius = SCRYFrom(10)
        searchBackgroundView.clipsToBounds = true
        cardView.addSubview(searchBackgroundView)
        searchBackgroundView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(12))
            make.bottom.equalTo(SCRYFrom(-12))
        }

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel".localizedString, for: .normal)
        cancelButton.setTitleColor(Bar_Color, for: .normal)
        cancelButton.titleLabel?.font = FONTS(14)
        cancelButton.setContentHuggingPriority(.required, for: .horizontal)
        cancelButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        searchBackgroundView.addSubview(cancelButton)
        cancelButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-12))
            make.centerY.equalToSuperview()
            make.height.equalToSuperview()
        }

        textField.text = initialText
        textField.placeholder = "device_filter_search_by_name".localizedString
        textField.font = FONTS(14)
        textField.textColor = TextBlack_Color
        textField.tintColor = Bar_Color
        textField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        textField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.clearButtonMode = .whileEditing
        textField.returnKeyType = .search
        textField.autocorrectionType = .no
        textField.autocapitalizationType = .none
        textField.delegate = self
        textField.leftViewMode = .always
        textField.leftView = makeSearchIconView()
        searchBackgroundView.addSubview(textField)
        textField.snp.makeConstraints { make in
            make.left.top.bottom.equalToSuperview()
            make.right.equalTo(cancelButton.snp.left).offset(SCRXFrom(-12))
        }
    }

    private func makeSearchIconView() -> UIView {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: SCRXFrom(40), height: SCRYFrom(41)))
        let imageView = UIImageView(image: UIImage(named: "search_icon"))
        imageView.contentMode = .scaleAspectFit
        imageView.frame = CGRect(
            x: SCRXFrom(12),
            y: (SCRYFrom(41) - SCRYFrom(20)) / 2,
            width: SCRXFrom(20),
            height: SCRYFrom(20)
        )
        container.addSubview(imageView)
        return container
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let submittedText = textField.text ?? ""
        let completion = onSubmit
        textField.resignFirstResponder()
        removeFromSuperview()
        completion?(submittedText)
        return true
    }

    @objc private func cancel() {
        textField.resignFirstResponder()
        removeFromSuperview()
    }
}
