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
        let action: (() -> Bool)?
    }

    private enum Layout {
        static let buttonSize = SCRXFrom(40)
        static let mockButtonSpacing = SCRXFrom(24)
        static let rowSpacing = SCRYFrom(28)
        static let actionCount = 4
    }

    private final class ActionButton: UIButton {
        override var isHighlighted: Bool {
            didSet {
                imageView?.alpha = isHighlighted ? 0.5 : 1.0
            }
        }
    }

    private var actionItems: [ActionItem] = []
    private var progressIndexes: Set<Int> = []
    private lazy var buttons: [ActionButton] = (0..<Layout.actionCount).map { index in
        let button = ActionButton(type: .custom)
        button.backgroundColor = .clear
        button.layer.borderWidth = 0
        button.imageView?.contentMode = .scaleAspectFit
        button.tag = index
        button.addTarget(self, action: #selector(handleButtonTap(_:)), for: .touchUpInside)
        button.snp.makeConstraints { make in
            make.width.height.equalTo(Layout.buttonSize)
        }
        return button
    }

    private lazy var primaryStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [buttons[0]])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.distribution = .equalCentering
        return stackView
    }()

    private lazy var mockStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: Array(buttons[1...3]))
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.mockButtonSpacing
        return stackView
    }()

    private lazy var stackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [primaryStackView, mockStackView])
        stackView.axis = .vertical
        stackView.alignment = .center
        stackView.spacing = Layout.rowSpacing
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
        progressIndexes.removeAll()
        actionItems = Array(actions.prefix(buttons.count))

        for (index, button) in buttons.enumerated() {
            guard index < actionItems.count else {
                button.isHidden = true
                button.layer.borderWidth = 0
                button.layer.removeAnimation(forKey: "loading")
                continue
            }

            let item = actionItems[index]
            button.isHidden = false
            button.setImage(item.image?.withRenderingMode(.alwaysOriginal), for: .normal)
            button.layer.borderWidth = 0
            updateButton(button, at: index)
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
        guard !progressIndexes.contains(sender.tag) else {
            return
        }
        guard actionItems[sender.tag].action?() == true else {
            return
        }
        setProgress(true, at: sender.tag)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.setProgress(false, at: sender.tag)
        }
    }

    private func setProgress(_ progress: Bool, at index: Int) {
        guard index < buttons.count else { return }
        if progress {
            progressIndexes.insert(index)
        } else {
            progressIndexes.remove(index)
        }
        updateButton(buttons[index], at: index)
    }

    private func updateButton(_ button: ActionButton, at index: Int) {
        let isProgress = progressIndexes.contains(index)
        if isProgress {
            button.layer.borderWidth = 0
            button.setImage(UIImage(named: isIPad ? "group_auto_progress_big" : "group_auto_progress")?.withTintColor(Bar_Color, renderingMode: .alwaysOriginal), for: .normal)
            button.layer.addRotationAnimation(duration: 1, repeatCount: 10, animationKey: "loading")
        } else {
            button.layer.borderWidth = 0
            button.layer.removeAnimation(forKey: "loading")
            if index < actionItems.count {
                button.setImage(actionItems[index].image?.withRenderingMode(.alwaysOriginal), for: .normal)
            }
        }
    }
}
