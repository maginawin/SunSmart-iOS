//
//  EmerFireAlarmMoniView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmMoniView: UIView {

    struct ActionItem {
        let image: UIImage?
        let borderColor: UIColor?
        let action: (() -> Void)?
    }

    private enum Layout {
        static let buttonSize = SCRXFrom(40)
        static let buttonSpacing = SCRXFrom(24)
    }

    private final class ActionButton: UIButton {
        override var isHighlighted: Bool {
            didSet {
                imageView?.alpha = isHighlighted ? 0.5 : 1.0
            }
        }
    }

    private var actionItems: [ActionItem] = []
    private lazy var buttons: [ActionButton] = (0..<3).map { index in
        let button = ActionButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = Layout.buttonSize / 2
        button.layer.borderWidth = 0
        button.layer.borderColor = RGB(216, 227, 255).cgColor
        button.imageView?.contentMode = .scaleAspectFit
        button.tag = index
        button.addTarget(self, action: #selector(handleButtonTap(_:)), for: .touchUpInside)
        button.snp.makeConstraints { make in
            make.width.height.equalTo(Layout.buttonSize)
        }
        return button
    }

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: buttons)
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.buttonSpacing
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(actions: [ActionItem]) {
        actionItems = Array(actions.prefix(buttons.count))

        for (index, button) in buttons.enumerated() {
            guard index < actionItems.count else {
                button.isHidden = true
                continue
            }

            let item = actionItems[index]
            button.isHidden = false
            button.setImage(item.image?.withRenderingMode(.alwaysOriginal), for: .normal)
            //button.layer.borderColor = item.borderColor.cgColor
        }
    }

    private func setupUI() {
        backgroundColor = .clear

        addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
            make.top.bottom.equalToSuperview()
        }
    }

    @objc private func handleButtonTap(_ sender: UIButton) {
        guard sender.tag < actionItems.count else {
            return
        }
        actionItems[sender.tag].action?()
    }
}
