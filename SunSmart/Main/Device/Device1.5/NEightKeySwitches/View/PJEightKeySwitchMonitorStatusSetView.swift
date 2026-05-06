//
//  PJEightKeySwitchMonitorStatusSetView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import SnapKit

final class PJEightKeySwitchMonitorStatusSetView: UIView {

    struct State {
        let groupNames: [String]
        let isGroupLinked: Bool
        let isEnabled: Bool
    }

    private enum Layout {
        static let collapsedHeight = SCRYFrom(40) + kSafeAreaBottomHeight
        static let expandedHeight = SCRYFrom(272) + kSafeAreaBottomHeight
        static let headerHeight = SCRYFrom(40)
        static let cardHeight = SCRYFrom(36)
    }

    var isExpanded = false {
        didSet { updateExpandedState(animated: true) }
    }

    var expandAction: ((Bool) -> Void)?
    var enableChanged: ((Bool) -> Void)?
    var groupLinkAction: (() -> Void)?

    private var heightConstraint: Constraint?
    private let contentView = UIView()
    private let headerButton = UIButton(type: .custom)
    private let arrowImageView = UIImageView(image: UIImage(named: "arrow_up"))
    private let titleLabel = UILabel(text: "settings".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
    private let groupLinkTitleLabel = UILabel(text: "neightkeyswitches_group_link".localizedString, textColor: Title_Color, fontSize: 13, fontWeight: .light, fit: false)
    private let groupLinkButton = UIButton(type: .custom)
    private let enableTitleLabel = UILabel(text: "enable".localizedString, textColor: Title_Color, fontSize: 13, fontWeight: .light, fit: false)
    let enableSwitch = UISwitch()

    private let expandedContainerView = UIView()
    private let statusCardView = UIView()
    private let linkedIconView = UIImageView()
    private let linkedLabel = UILabel(text: "neightkeyswitches_linked".localizedString, textColor: RGB(90, 102, 134), fontSize: 13, fontWeight: .light, fit: false)
    private let unlinkedIconView = UIImageView()
    private let unlinkedLabel = UILabel(text: "neightkeyswitches_unlinked".localizedString, textColor: RGB(144, 150, 170), fontSize: 13, fontWeight: .light, fit: false)
    private let innerEnableSwitch = UISwitch()
    private let innerEnableLabel = UILabel(text: nil, textColor: RGB(90, 102, 134), fontSize: 13, fontWeight: .light, fit: false)
    private let groupsTitleLabel = UILabel(text: "neightkeyswitches_groups_it_controls".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
    private let emptyLabel = UILabel(text: "neightkeyswitches_group_empty_tip".localizedString, textColor: RGB(120, 126, 148), fontSize: 14, fontWeight: .light)
    private let groupsStackView = UIStackView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupUI()
        updateExpandedState(animated: false)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(state: State) {
        enableSwitch.isOn = state.isEnabled
        innerEnableSwitch.isOn = state.isEnabled
        innerEnableLabel.text = state.isEnabled ? "enable".localizedString : "disabled".localizedString
        innerEnableLabel.textColor = state.isEnabled ? RGB(90, 102, 134) : RGB(144, 150, 170)

        let linkedTint = state.isGroupLinked ? RGB(90, 102, 134) : RGB(188, 193, 209)
        let unlinkedTint = state.isGroupLinked ? RGB(188, 193, 209) : RGB(90, 102, 134)
        linkedIconView.image = (UIImage(named: "link") ?? UIImage(systemName: "link"))?.withTintColor(linkedTint, renderingMode: .alwaysOriginal)
        unlinkedIconView.image = (UIImage(named: "unlink") ?? UIImage(systemName: "link.badge.minus"))?.withTintColor(unlinkedTint, renderingMode: .alwaysOriginal)
        linkedLabel.textColor = linkedTint
        unlinkedLabel.textColor = unlinkedTint

        groupsStackView.arrangedSubviews.forEach {
            groupsStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if state.groupNames.isEmpty {
            emptyLabel.isHidden = false
            groupsStackView.isHidden = true
        } else {
            emptyLabel.isHidden = true
            groupsStackView.isHidden = false
            state.groupNames.forEach { name in
                let label = UILabel(text: name, textColor: RGB(104, 120, 162), fontSize: 14, fontWeight: .light)
                label.numberOfLines = 1
                groupsStackView.addArrangedSubview(label)
            }
        }
    }

    @objc private func toggleExpanded() {
        isExpanded.toggle()
        expandAction?(isExpanded)
    }

    @objc private func groupLinkButtonAction() {
        groupLinkAction?()
    }

    @objc private func enableValueChanged(_ sender: UISwitch) {
        enableSwitch.setOn(sender.isOn, animated: true)
        innerEnableSwitch.setOn(sender.isOn, animated: true)
        enableChanged?(sender.isOn)
    }

    private func setupUI() {
        backgroundColor = .clear

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(20)
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            heightConstraint = make.height.equalTo(Layout.collapsedHeight).constraint
        }

        headerButton.addTarget(self, action: #selector(toggleExpanded), for: .touchUpInside)
        contentView.addSubview(headerButton)
        headerButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(Layout.headerHeight)
        }

        arrowImageView.contentMode = .scaleAspectFit
        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.width.height.equalTo(SCRXFrom(16))
        }

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(8))
        }

        enableSwitch.addTarget(self, action: #selector(enableValueChanged(_:)), for: .valueChanged)
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalToSuperview().offset(-SCRXFrom(24))
        }

        contentView.addSubview(enableTitleLabel)
        enableTitleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalTo(enableSwitch.snp.left).offset(-SCRXFrom(8))
        }

        groupLinkButton.addTarget(self, action: #selector(groupLinkButtonAction), for: .touchUpInside)
        groupLinkButton.setImage((UIImage(named: "link") ?? UIImage(systemName: "link"))?.withTintColor(RGB(129, 118, 226), renderingMode: .alwaysOriginal), for: .normal)
        contentView.addSubview(groupLinkButton)
        groupLinkButton.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalTo(enableTitleLabel.snp.left).offset(-SCRXFrom(20))
            make.width.height.equalTo(SCRXFrom(18))
        }

        contentView.addSubview(groupLinkTitleLabel)
        groupLinkTitleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalTo(groupLinkButton.snp.left).offset(-SCRXFrom(6))
        }

        contentView.addSubview(expandedContainerView)
        expandedContainerView.snp.makeConstraints { make in
            make.top.equalTo(headerButton.snp.bottom)
            make.left.right.equalToSuperview()
            make.bottom.equalToSuperview().offset(-kSafeAreaBottomHeight)
        }

        statusCardView.backgroundColor = RGB(247, 248, 252)
        statusCardView.layer.cornerRadius = SCRYFrom(10)
        expandedContainerView.addSubview(statusCardView)
        statusCardView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(8))
            make.left.equalToSuperview().offset(SCRXFrom(24))
            make.right.equalToSuperview().offset(-SCRXFrom(24))
            make.height.equalTo(Layout.cardHeight)
        }

        [linkedIconView, linkedLabel, unlinkedIconView, unlinkedLabel, innerEnableSwitch, innerEnableLabel].forEach {
            statusCardView.addSubview($0)
        }

        linkedIconView.contentMode = .scaleAspectFit
        linkedIconView.snp.makeConstraints { make in
            make.left.equalToSuperview().offset(SCRXFrom(12))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(14))
        }

        linkedLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(linkedIconView.snp.right).offset(SCRXFrom(6))
        }

        unlinkedIconView.contentMode = .scaleAspectFit
        unlinkedIconView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(linkedLabel.snp.right).offset(SCRXFrom(18))
            make.width.height.equalTo(SCRXFrom(14))
        }

        unlinkedLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(unlinkedIconView.snp.right).offset(SCRXFrom(6))
        }

        innerEnableSwitch.addTarget(self, action: #selector(enableValueChanged(_:)), for: .valueChanged)
        statusCardView.addSubview(innerEnableSwitch)
        innerEnableSwitch.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(innerEnableLabel.snp.left).offset(-SCRXFrom(8))
            make.width.equalTo(SCRXFrom(44))
        }

        innerEnableLabel.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalToSuperview().offset(-SCRXFrom(12))
        }

        expandedContainerView.addSubview(groupsTitleLabel)
        groupsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(statusCardView.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(statusCardView)
            make.right.equalTo(statusCardView)
        }

        emptyLabel.numberOfLines = 0
        expandedContainerView.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.top.equalTo(groupsTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(statusCardView)
            make.right.equalTo(statusCardView)
        }

        groupsStackView.axis = .vertical
        groupsStackView.alignment = .fill
        groupsStackView.spacing = SCRYFrom(10)
        expandedContainerView.addSubview(groupsStackView)
        groupsStackView.snp.makeConstraints { make in
            make.top.equalTo(groupsTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(statusCardView)
            make.right.equalTo(statusCardView)
            make.bottom.lessThanOrEqualToSuperview()
        }
    }

    private func updateExpandedState(animated: Bool) {
        let targetHeight = isExpanded ? Layout.expandedHeight : Layout.collapsedHeight
        heightConstraint?.update(offset: targetHeight)
        expandedContainerView.isHidden = !isExpanded
        arrowImageView.image = UIImage(named: isExpanded ? "arrow_down" : "arrow_up")

        let animations = { [weak self] in
            self?.superview?.layoutIfNeeded()
            return
        }

        if animated {
            UIView.animate(withDuration: 0.25, animations: animations)
        } else {
            animations()
        }
    }
}
