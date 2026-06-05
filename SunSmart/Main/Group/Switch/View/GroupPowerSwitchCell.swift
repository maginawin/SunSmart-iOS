//
//  GroupPowerSwitchCell.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class GroupPowerSwitchCell: UITableViewCell {

    struct State {
        let name: String
        let detailText: String
        let isEnabled: Bool
        let isExpanded: Bool
        let isEditable: Bool
        let isEnablePending: Bool
        let panelTitle: String
        let groupTitle: String
        let sceneTitle: String
        let moreSettingsTitle: String
        let showsSceneRow: Bool
        let panelDefinition: PJEightKeySwitchPanelDefinition
        let isSaveEnabled: Bool
    }

    var expandAction: (() -> Void)?
    var enableAction: ((Bool) -> Void)?
    var panelAction: (() -> Void)?
    var groupAction: (() -> Void)?
    var sceneAction: (() -> Void)?
    var moreSettingsAction: (() -> Void)?
    var deleteAction: (() -> Void)?
    var saveAction: (() -> Void)?

    private let cardView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 8
        return view
    }()

    private let headerView = UIView()
    private let headerTapButton = UIButton()

    private let nameLabel: UILabel = {
        let label = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)
        label.numberOfLines = 1
        return label
    }()

    private let detailLabel: UILabel = {
        let label = UILabel(text: nil, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        label.numberOfLines = 1
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private let statusLabel: UILabel = {
        let label = UILabel(text: nil, textColor: SubText_Color, fontSize: 12, fontWeight: .light)
        label.textAlignment = .right
        return label
    }()

    private let enableSwitch: UISwitch = {
        let control = UISwitch()
        control.onTintColor = Bar_Color
        control.tintColor = RGB(207, 207, 207)
        control.isUserInteractionEnabled = false
        return control
    }()

    private let enableButton = UIButton()

    private let arrowImageView: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "arrow_down"))
        imageView.contentMode = .scaleAspectFit
        return imageView
    }()

    private let detailsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 0
        return stackView
    }()

    private let panelRowView = PJEightKeySwitchInfoRowView(title: "panel".localizedString, accessory: .valueWithArrow)
    private let groupRowView = PJEightKeySwitchInfoRowView(title: "group".localizedString, accessory: .valueWithArrow)
    private let sceneRowView = PJEightKeySwitchInfoRowView(title: "scene".localizedString, accessory: .valueWithArrow)
    private let moreSettingsRowView = PJEightKeySwitchInfoRowView(title: "neightkeyswitches_more_settings".localizedString, accessory: .valueWithArrow)
    private let panelPreviewView = PJEightKeySwitchPanelView()

    private let actionView = UIView()
    private let deleteButton = UIButton(normalImageName: "switch_delete")
    private let saveButton = UIButton(normalImageName: "switch_save")

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupUI()
        bindActions()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        expandAction = nil
        enableAction = nil
        panelAction = nil
        groupAction = nil
        sceneAction = nil
        moreSettingsAction = nil
        deleteAction = nil
        saveAction = nil
    }

    func configure(state: State) {
        nameLabel.text = state.name
        detailLabel.text = state.detailText
        statusLabel.text = state.isEnabled ? "enable".localizedString : "disable".localizedString
        statusLabel.textColor = state.isEnabled ? Bar_Color : SubText_Color
        enableSwitch.isOn = state.isEnabled
        enableButton.isEnabled = state.isEditable && !state.isEnablePending
        enableSwitch.alpha = state.isEnablePending ? 0.45 : 1
        arrowImageView.image = UIImage(named: state.isExpanded ? "arrow_up" : "arrow_down")
        detailsStackView.isHidden = !state.isExpanded

        panelRowView.setValue(state.panelTitle)
        groupRowView.setValue(state.groupTitle)
        sceneRowView.setValue(state.sceneTitle)
        sceneRowView.isHidden = !state.showsSceneRow
        moreSettingsRowView.setValue(state.moreSettingsTitle)
        panelPreviewView.configure(definition: state.panelDefinition, mode: .preview)

        saveButton.isEnabled = state.isEditable && state.isSaveEnabled
        saveButton.setImage(UIImage(named: state.isSaveEnabled ? "switch_save" : "switch_save_un"), for: .normal)
        deleteButton.isEnabled = state.isEditable
        deleteButton.alpha = state.isEditable ? 1 : 0.35
        panelRowView.isUserInteractionEnabled = state.isEditable
        sceneRowView.isUserInteractionEnabled = state.isEditable && state.showsSceneRow
        moreSettingsRowView.isUserInteractionEnabled = state.isEditable
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = Background_Color
        contentView.backgroundColor = Background_Color

        contentView.addSubview(cardView)
        cardView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(8))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-8))
        }

        cardView.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(64))
        }

        headerView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
            make.width.height.equalTo(SCRXFrom(16))
        }

        headerView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }

        headerView.addSubview(enableButton)
        enableButton.snp.makeConstraints { make in
            make.edges.equalTo(enableSwitch)
        }

        headerView.addSubview(statusLabel)
        statusLabel.snp.makeConstraints { make in
            make.right.equalTo(enableSwitch.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalToSuperview()
            make.width.greaterThanOrEqualTo(SCRXFrom(48))
        }

        headerView.addSubview(nameLabel)
        nameLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(12))
            make.right.lessThanOrEqualTo(statusLabel.snp.left).offset(SCRXFrom(-8))
        }

        headerView.addSubview(detailLabel)
        detailLabel.snp.makeConstraints { make in
            make.left.equalTo(nameLabel)
            make.top.equalTo(nameLabel.snp.bottom).offset(SCRYFrom(5))
            make.right.lessThanOrEqualTo(statusLabel.snp.left).offset(SCRXFrom(-8))
        }

        headerView.addSubview(headerTapButton)
        headerTapButton.snp.makeConstraints { make in
            make.top.bottom.left.equalToSuperview()
            make.right.equalTo(statusLabel.snp.left).offset(SCRXFrom(-4))
        }

        cardView.addSubview(detailsStackView)
        detailsStackView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
        }

        [panelRowView, groupRowView, sceneRowView, moreSettingsRowView].forEach { rowView in
            detailsStackView.addArrangedSubview(rowView)
            rowView.snp.makeConstraints { make in
                make.height.equalTo(SCRYFrom(44))
            }
        }

        let panelContainerView = UIView()
        detailsStackView.addArrangedSubview(panelContainerView)
        panelContainerView.addSubview(panelPreviewView)
        panelContainerView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(264))
        }
        panelPreviewView.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(12))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.bottom.equalTo(SCRYFrom(-12))
        }

        detailsStackView.addArrangedSubview(actionView)
        actionView.snp.makeConstraints { make in
            make.height.equalTo(SCRYFrom(64))
        }

        actionView.addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(40))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }

        saveButton.setImage(UIImage(named: "switch_save_un"), for: .disabled)
        actionView.addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-40))
            make.centerY.height.equalTo(deleteButton)
        }
    }

    private func bindActions() {
        headerTapButton.addTarget(self, action: #selector(expandButtonAction), for: .touchUpInside)
        enableButton.addTarget(self, action: #selector(enableButtonAction), for: .touchUpInside)
        panelRowView.tapAction = { [weak self] in self?.panelAction?() }
        groupRowView.tapAction = { [weak self] in self?.groupAction?() }
        sceneRowView.tapAction = { [weak self] in self?.sceneAction?() }
        moreSettingsRowView.tapAction = { [weak self] in self?.moreSettingsAction?() }
        deleteButton.addTarget(self, action: #selector(deleteButtonAction), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveButtonAction), for: .touchUpInside)
    }

    @objc private func expandButtonAction() {
        expandAction?()
    }

    @objc private func enableButtonAction() {
        enableAction?(!enableSwitch.isOn)
    }

    @objc private func deleteButtonAction() {
        deleteAction?()
    }

    @objc private func saveButtonAction() {
        saveAction?()
    }
}
