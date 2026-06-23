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
        let isPending: Bool
    }

    private enum Layout {
        static let collapsedHeight = SCRYFrom(40) + kSafeAreaBottomHeight
        static let expandedHeight = SCRYFrom(330) + kSafeAreaBottomHeight
        static let headerHeight = SCRYFrom(40)
        static let legendHeight = SCRYFrom(32)
        static let miniSwitchSize = CGSize(width: SCRXFrom(30), height: SCRYFrom(20))
    }

    fileprivate enum Palette {
        static let primaryText = RGB(30, 35, 41)
        static let titleText = RGB(39, 37, 54)
        static let legendText = RGB(64, 79, 102)
        static let secondaryText = RGB(100, 116, 139)
        static let auxiliary = RGB(148, 163, 184)
        static let iconDark = RGB(20, 46, 79)
        static let tagBackground = RGB(250, 250, 250)
        static let switchDisabledTrack = RGB(238, 238, 238)
        static let switchDisabledKnob = UIColor.white
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
    private let arrowImageView = UIImageView(image: UIImage(named: "arrow_up_black"))
    private let titleLabel = UILabel(text: "settings".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light, fit: false)
    private let groupLinkTitleLabel = UILabel(text: "neightkeyswitches_group_link".localizedString, textColor: Title_Color, fontSize: 13, fontWeight: .light, fit: false)
    private let groupLinkButton = UIButton(type: .custom)
    private let enableTitleLabel = UILabel(text: "enable".localizedString, textColor: Title_Color, fontSize: 13, fontWeight: .light, fit: false)
    let enableSwitch = UISwitch()
    private let enableSwitchTouchShield = UIControl()

    private let expandedContainerView = UIView()
    private let statusCardView = UIView()
    private let linkedIconView = UIImageView()
    private let linkedLabel = UILabel(text: "neightkeyswitches_linked".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
    private let unlinkedIconView = UIImageView()
    private let unlinkedLabel = UILabel(text: "neightkeyswitches_unlinked".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
    private let enableLegendSwitch = PJEightKeySwitchMiniSwitchLegendView()
    private let enableLegendLabel = UILabel(text: "enable".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
    private let disabledLegendSwitch = PJEightKeySwitchMiniSwitchLegendView()
    private let disabledLegendLabel = UILabel(text: "disable".localizedString, textColor: Palette.legendText, fontSize: 12, fontWeight: .light, fit: false)
    private let groupsTitleLabel = UILabel(text: "neightkeyswitches_groups_it_controls".localizedString, textColor: Palette.primaryText, fontSize: 15, fontWeight: .light, fit: false)
    private let emptyLabel = UILabel(text: "neightkeyswitches_group_empty_tip".localizedString, textColor: Palette.secondaryText, fontSize: 13, fontWeight: .light)
    private let groupsScrollView = UIScrollView()
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
        enableSwitch.setOn(state.isEnabled, animated: false)
        enableSwitch.isEnabled = true
        enableSwitchTouchShield.isHidden = false

        groupLinkButton.setImage(UIImage(named: state.isGroupLinked ? "group_linked" : "group_unlinked"), for: .normal)

        linkedIconView.image = UIImage(named: "group_linked")
        unlinkedIconView.image = UIImage(named: "group_unlinked")
        enableLegendSwitch.isOn = true
        disabledLegendSwitch.isOn = false

        renderGroupNames(state.groupNames)
    }

    private func renderGroupNames(_ names: [String]) {
        groupsStackView.arrangedSubviews.forEach {
            groupsStackView.removeArrangedSubview($0)
            $0.removeFromSuperview()
        }

        if names.isEmpty {
            emptyLabel.isHidden = false
            groupsScrollView.isHidden = true
            return
        }

        emptyLabel.isHidden = true
        groupsScrollView.isHidden = false
        names.forEach { name in
            let label = UILabel(text: name, textColor: Palette.secondaryText, fontSize: 13, fontWeight: .light, fit: false)
            label.numberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            groupsStackView.addArrangedSubview(label)
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
        enableChanged?(sender.isOn)
    }

    private func setupUI() {
        backgroundColor = .clear

        contentView.backgroundColor = .white
        contentView.layer.cornerRadius = SCRYFrom(20)
        contentView.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner]
        contentView.layer.shadowColor = UIColor.black.cgColor
        contentView.layer.shadowOpacity = 0.07
        contentView.layer.shadowRadius = SCRYFrom(6)
        contentView.layer.shadowOffset = CGSize(width: 0, height: -SCRYFrom(2))
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
            make.width.height.equalTo(SCRXFrom(30))
        }

        contentView.addSubview(titleLabel)
        titleLabel.textColor = Palette.titleText
        titleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.left.equalTo(arrowImageView.snp.right).offset(SCRXFrom(2))
        }

        enableSwitch.addTarget(self, action: #selector(enableValueChanged(_:)), for: .valueChanged)
        enableSwitch.onTintColor = Bar_Color
        enableSwitch.tintColor = RGB(207, 207, 207)
        enableSwitch.thumbTintColor = .white
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalToSuperview().offset(-SCRXFrom(24))
        }

        enableSwitchTouchShield.backgroundColor = .clear
        contentView.addSubview(enableSwitchTouchShield)
        enableSwitchTouchShield.snp.makeConstraints { make in
            make.edges.equalTo(enableSwitch)
        }

        contentView.addSubview(enableTitleLabel)
        enableTitleLabel.textColor = Palette.primaryText
        enableTitleLabel.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalTo(enableSwitch.snp.left).offset(-SCRXFrom(8))
        }

        groupLinkButton.addTarget(self, action: #selector(groupLinkButtonAction), for: .touchUpInside)
        groupLinkButton.imageView?.contentMode = .scaleAspectFit
        groupLinkButton.setImage(UIImage(named: "group_linked"), for: .normal)
        contentView.addSubview(groupLinkButton)
        groupLinkButton.snp.makeConstraints { make in
            make.centerY.equalTo(headerButton)
            make.right.equalTo(enableTitleLabel.snp.left).offset(-SCRXFrom(16))
            make.width.height.equalTo(SCRXFrom(20))
        }

        contentView.addSubview(groupLinkTitleLabel)
        groupLinkTitleLabel.textColor = Palette.primaryText
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

        statusCardView.backgroundColor = Palette.tagBackground
        statusCardView.layer.cornerRadius = SCRYFrom(10)
        expandedContainerView.addSubview(statusCardView)
        statusCardView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(SCRYFrom(4))
            make.left.equalToSuperview().offset(SCRXFrom(20))
            make.right.equalToSuperview().offset(-SCRXFrom(20))
            make.height.equalTo(Layout.legendHeight)
        }

        enableLegendSwitch.isOn = true
        disabledLegendSwitch.isOn = false
        let legendStackView = UIStackView(arrangedSubviews: [
            makeLegendItem(iconView: linkedIconView, label: linkedLabel),
            makeLegendItem(iconView: unlinkedIconView, label: unlinkedLabel),
            makeSwitchLegendItem(switchView: enableLegendSwitch, label: enableLegendLabel),
            makeSwitchLegendItem(switchView: disabledLegendSwitch, label: disabledLegendLabel)
        ])
        legendStackView.axis = .horizontal
        legendStackView.alignment = .center
        legendStackView.spacing = SCRXFrom(16)
        statusCardView.addSubview(legendStackView)
        legendStackView.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }

        expandedContainerView.addSubview(groupsTitleLabel)
        groupsTitleLabel.snp.makeConstraints { make in
            make.top.equalTo(statusCardView.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(statusCardView).offset(SCRXFrom(8))
            make.right.equalTo(statusCardView).offset(-SCRXFrom(8))
        }

        emptyLabel.numberOfLines = 0
        expandedContainerView.addSubview(emptyLabel)
        emptyLabel.snp.makeConstraints { make in
            make.top.equalTo(groupsTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(groupsTitleLabel)
            make.right.equalTo(groupsTitleLabel)
        }

        groupsScrollView.showsVerticalScrollIndicator = false
        groupsScrollView.alwaysBounceVertical = false
        expandedContainerView.addSubview(groupsScrollView)
        groupsScrollView.snp.makeConstraints { make in
            make.top.equalTo(groupsTitleLabel.snp.bottom).offset(SCRYFrom(16))
            make.left.equalTo(groupsTitleLabel)
            make.right.equalTo(groupsTitleLabel)
            make.bottom.equalToSuperview().offset(-SCRYFrom(8))
        }

        groupsStackView.axis = .vertical
        groupsStackView.alignment = .fill
        groupsStackView.spacing = SCRYFrom(10)
        groupsScrollView.addSubview(groupsStackView)
        groupsStackView.snp.makeConstraints { make in
            make.edges.equalTo(groupsScrollView.contentLayoutGuide)
            make.width.equalTo(groupsScrollView.frameLayoutGuide)
        }
    }

    private func makeLegendItem(iconView: UIImageView, label: UILabel) -> UIStackView {
        iconView.contentMode = .scaleAspectFit
        iconView.snp.makeConstraints { make in
            make.width.height.equalTo(SCRXFrom(20))
        }
        let stackView = UIStackView(arrangedSubviews: [iconView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = SCRXFrom(4)
        return stackView
    }

    private func makeSwitchLegendItem(switchView: PJEightKeySwitchMiniSwitchLegendView, label: UILabel) -> UIStackView {
        switchView.snp.makeConstraints { make in
            make.width.equalTo(Layout.miniSwitchSize.width)
            make.height.equalTo(Layout.miniSwitchSize.height)
        }
        let stackView = UIStackView(arrangedSubviews: [switchView, label])
        stackView.axis = .horizontal
        stackView.alignment = .center
        stackView.spacing = SCRXFrom(0)
        return stackView
    }

    private func updateExpandedState(animated: Bool) {
        let targetHeight = isExpanded ? Layout.expandedHeight : Layout.collapsedHeight
        heightConstraint?.update(offset: targetHeight)
        expandedContainerView.isHidden = !isExpanded
        arrowImageView.image = UIImage(named: isExpanded ? "arrow_down_black" : "arrow_up_black")

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

private final class PJEightKeySwitchMiniSwitchLegendView: UIView {

    var isOn = true {
        didSet { setNeedsLayout() }
    }

    private let trackView = UIView()
    private let knobView = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        addSubview(trackView)
        addSubview(knobView)
        trackView.layer.masksToBounds = true
        knobView.backgroundColor = .white
        knobView.layer.shadowColor = UIColor.black.cgColor
        knobView.layer.shadowOpacity = 0.12
        knobView.layer.shadowRadius = 2
        knobView.layer.shadowOffset = CGSize(width: 0, height: 1)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        trackView.frame = bounds.insetBy(dx: SCRXFrom(2.5), dy: SCRYFrom(2.5))
        trackView.layer.cornerRadius = trackView.bounds.height / 2
        trackView.backgroundColor = isOn ? Bar_Color : PJEightKeySwitchMonitorStatusSetView.Palette.switchDisabledTrack

        let knobSide = SCRXFrom(16)
        let knobX = isOn ? bounds.width - SCRXFrom(2.5) - knobSide : SCRXFrom(2.5)
        knobView.frame = CGRect(x: knobX, y: (bounds.height - knobSide) / 2, width: knobSide, height: knobSide)
        knobView.layer.cornerRadius = knobSide / 2
        knobView.backgroundColor = isOn ? .white : PJEightKeySwitchMonitorStatusSetView.Palette.switchDisabledKnob
    }
}
