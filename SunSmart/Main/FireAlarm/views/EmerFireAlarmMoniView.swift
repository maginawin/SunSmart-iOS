//
//  EmerFireAlarmMoniView.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import UIKit
import SnapKit

final class EmerFireAlarmMoniView: UIView {

    enum ActionPosition: CaseIterable {
        case top
        case bottomLeft
        case bottomCenterLeft
        case bottomCenterRight
        case bottomRight
    }

    private enum Layout {
        static let buttonSize = SCRXFrom(40)
        static let topBottomSpacing = SCRYFrom(34)
        static let bottomButtonSpacing = SCRXFrom(22)
        static let dividerHeight = SCRYFrom(24)
        static let dividerWidth = 1
    }

    private final class ActionButton: UIButton {
        override var isHighlighted: Bool {
            didSet {
                imageView?.alpha = isHighlighted ? 0.5 : 1.0
            }
        }
    }

    var actionHandler: ((ActionPosition) -> Void)?

    private lazy var topButton = makeButton(for: .top)
    private lazy var bottomLeftButton = makeButton(for: .bottomLeft)
    private lazy var bottomCenterLeftButton = makeButton(for: .bottomCenterLeft)
    private lazy var bottomCenterRightButton = makeButton(for: .bottomCenterRight)
    private lazy var bottomRightButton = makeButton(for: .bottomRight)

    private lazy var dividerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor(red: 0.58, green: 0.639, blue: 0.722, alpha: 1)
        return view
    }()

    private lazy var leftStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [bottomLeftButton, bottomCenterLeftButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.bottomButtonSpacing
        return stackView
    }()

    private lazy var rightStackView: UIStackView = {
        let stackView = UIStackView(arrangedSubviews: [bottomCenterRightButton, bottomRightButton])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = Layout.bottomButtonSpacing
        return stackView
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setImage(_ image: UIImage?, for position: ActionPosition) {
        button(for: position).setImage(image?.withRenderingMode(.alwaysOriginal), for: .normal)
    }

    func setHidden(_ isHidden: Bool, for position: ActionPosition) {
        button(for: position).isHidden = isHidden
    }

    private func setupUI() {
        backgroundColor = .clear

        topButton.setImage(UIImage(named: "Identify"), for: .normal)
        bottomLeftButton.setImage(UIImage(named: "Frame 250"), for: .normal)
        bottomCenterLeftButton.setImage(UIImage(named: "Logout-2 Streamline Sharp1"), for: .normal)
        bottomCenterRightButton.setImage(UIImage(named: "space_light_401"), for: .normal)
        bottomRightButton.setImage(UIImage(named: "Logout-2 Streamline Sharp"), for: .normal)
        
        bottomLeftButton.layer.borderWidth = 0.8
        bottomLeftButton.layer.borderColor = UIColor(red: 0, green: 0.383, blue: 1, alpha: 1).cgColor
        bottomCenterLeftButton.layer.borderWidth = 0.8
        bottomCenterLeftButton.layer.borderColor = UIColor(red: 0, green: 0.383, blue: 1, alpha: 1).cgColor
        
        bottomCenterRightButton.layer.borderWidth = 0.8
        bottomCenterRightButton.layer.borderColor = UIColor(red: 1, green: 0.281, blue: 0.194, alpha: 1).cgColor
        bottomRightButton.layer.borderWidth = 0.8
        bottomRightButton.layer.borderColor = UIColor(red: 1, green: 0.281, blue: 0.194, alpha: 1).cgColor

        
        addSubview(topButton)
        topButton.snp.makeConstraints { make in
            make.top.centerX.equalToSuperview()
            make.width.height.equalTo(Layout.buttonSize)
        }

        addSubview(leftStackView)
        
        leftStackView.snp.makeConstraints { make in
            make.top.equalTo(topButton.snp.bottom).offset(Layout.topBottomSpacing)
            make.left.equalToSuperview()
            make.bottom.equalToSuperview()
        }

        addSubview(dividerView)
        dividerView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(leftStackView)
            make.width.equalTo(Layout.dividerWidth)
            make.height.equalTo(Layout.dividerHeight)
        }

        addSubview(rightStackView)
        rightStackView.snp.makeConstraints { make in
            make.centerY.equalTo(leftStackView)
            make.right.equalToSuperview()
        }
    }

    private func makeButton(for position: ActionPosition) -> UIButton {
        let button = ActionButton(type: .custom)
        button.backgroundColor = .white
        button.layer.cornerRadius = Layout.buttonSize / 2
        button.layer.borderWidth = 1
        button.layer.borderColor = RGB(216, 227, 255).cgColor
        button.imageView?.contentMode = .scaleAspectFit
        button.tag = tagValue(for: position)
        button.addTarget(self, action: #selector(handleButtonTap(_:)), for: .touchUpInside)
        button.snp.makeConstraints { make in
            make.width.height.equalTo(Layout.buttonSize)
        }
        return button
    }

    @objc private func handleButtonTap(_ sender: UIButton) {
        guard let position = position(for: sender.tag) else { return }
        actionHandler?(position)
    }

    private func button(for position: ActionPosition) -> UIButton {
        switch position {
        case .top:
            return topButton
        case .bottomLeft:
            return bottomLeftButton
        case .bottomCenterLeft:
            return bottomCenterLeftButton
        case .bottomCenterRight:
            return bottomCenterRightButton
        case .bottomRight:
            return bottomRightButton
        }
    }

    private func tagValue(for position: ActionPosition) -> Int {
        switch position {
        case .top:
            return 100
        case .bottomLeft:
            return 101
        case .bottomCenterLeft:
            return 102
        case .bottomCenterRight:
            return 103
        case .bottomRight:
            return 104
        }
    }

    private func position(for tag: Int) -> ActionPosition? {
        switch tag {
        case 100:
            return .top
        case 101:
            return .bottomLeft
        case 102:
            return .bottomCenterLeft
        case 103:
            return .bottomCenterRight
        case 104:
            return .bottomRight
        default:
            return nil
        }
    }
}
