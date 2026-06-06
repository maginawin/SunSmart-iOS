//
//  GroupPowerSwitchCell.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class GroupPowerSwitchHeaderView: UITableViewHeaderFooterView {

    struct State {
        let name: String
        let detailText: String
        let isEnabled: Bool
        let isExpanded: Bool
        let isEditable: Bool
        let isEnablePending: Bool
    }

    var expandAction: (() -> Void)?
    var enableAction: ((Bool) -> Void)?

    private let titleLabel = UILabel(text: nil, textColor: TextBlack_Color, fontSize: 14)

    private let detailLabel: UILabel = {
        let label = UILabel(text: nil, textColor: SubText_Color, fontSize: 14, fontWeight: .light)
        label.lineBreakMode = .byTruncatingMiddle
        return label
    }()

    private let arrowImageView = UIImageView(image: UIImage(named: "arrow_down"))
    private let enableSwitch = UISwitch()
    private let enableButton = UIButton()

    private let lineView: UIView = {
        let view = UIView()
        view.backgroundColor = RGB(243, 243, 243, 0.7)
        return view
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
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
    }

    func configure(state: State) {
        titleLabel.text = state.name
        detailLabel.text = state.detailText
        enableSwitch.isOn = state.isEnabled
        enableSwitch.alpha = state.isEnablePending ? 0.45 : 1
        enableButton.isEnabled = state.isEditable && !state.isEnablePending
        arrowImageView.image = UIImage(named: state.isExpanded ? "arrow_up" : "arrow_down")
    }

    private func setupUI() {
        contentView.backgroundColor = .white

        contentView.addSubview(titleLabel)
        titleLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(13))
        }

        contentView.addSubview(arrowImageView)
        arrowImageView.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-8))
            make.centerY.equalToSuperview()
        }

        enableSwitch.onTintColor = Bar_Color
        enableSwitch.tintColor = RGB(207, 207, 207)
        contentView.addSubview(enableSwitch)
        enableSwitch.snp.makeConstraints { make in
            make.right.equalTo(arrowImageView.snp.left).offset(SCRXFrom(-12))
            make.centerY.equalToSuperview()
        }

        enableSwitch.addSubview(enableButton)
        enableButton.snp.makeConstraints { make in
            make.edges.equalTo(enableSwitch)
        }

        contentView.addSubview(detailLabel)
        detailLabel.snp.makeConstraints { make in
            make.left.equalTo(titleLabel)
            make.top.equalTo(titleLabel.snp.bottom).offset(SCRYFrom(5))
            make.right.lessThanOrEqualTo(enableSwitch.snp.left).offset(SCRXFrom(-12))
        }

        contentView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.bottom.right.equalToSuperview()
            make.height.equalTo(1)
        }
    }

    private func bindActions() {
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(expandButtonAction)))
        enableButton.addTarget(self, action: #selector(enableButtonAction), for: .touchUpInside)
    }

    @objc private func expandButtonAction() {
        expandAction?()
    }

    @objc private func enableButtonAction() {
        enableAction?(!enableSwitch.isOn)
    }
}

final class GroupPowerSwitchPanelCell: UITableViewCell {

    var deleteAction: (() -> Void)?
    var saveAction: (() -> Void)?

    private let panelContainerView: UIView = {
        let view = UIView()
        view.layer.borderColor = RGB(220, 220, 220).cgColor
        view.layer.borderWidth = 0.6
        view.layer.cornerRadius = 15
        view.backgroundColor = .white
        return view
    }()

    private let panelPreviewView = PJEightKeySwitchPanelView()
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
        deleteAction = nil
        saveAction = nil
    }

    func configure(definition: PJEightKeySwitchPanelDefinition, isEditable: Bool, isSaveEnabled: Bool) {
        panelPreviewView.configure(definition: definition, mode: .preview)
        deleteButton.isEnabled = isEditable
        deleteButton.alpha = isEditable ? 1 : 0.35
        saveButton.isEnabled = isEditable && isSaveEnabled
        saveButton.setImage(UIImage(named: isSaveEnabled ? "switch_save" : "switch_save_un"), for: .normal)
    }

    private func setupUI() {
        selectionStyle = .none
        backgroundColor = Background_Color
        contentView.backgroundColor = Background_Color

        contentView.addSubview(panelContainerView)
        panelContainerView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(8))
            make.height.equalTo(SCRYFrom(288))
        }

        panelContainerView.addSubview(panelPreviewView)
        panelPreviewView.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(
                UIEdgeInsets(
                    top: SCRYFrom(8),
                    left: SCRXFrom(8),
                    bottom: SCRYFrom(8),
                    right: SCRXFrom(8)
                )
            )
        }

        contentView.addSubview(deleteButton)
        deleteButton.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(56))
            make.top.equalTo(panelContainerView.snp.bottom).offset(SCRYFrom(16))
            make.height.equalTo(40)
        }

        saveButton.setImage(UIImage(named: "switch_save_un"), for: .disabled)
        contentView.addSubview(saveButton)
        saveButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-56))
            make.centerY.height.equalTo(deleteButton)
        }
    }

    private func bindActions() {
        deleteButton.addTarget(self, action: #selector(deleteButtonAction), for: .touchUpInside)
        saveButton.addTarget(self, action: #selector(saveButtonAction), for: .touchUpInside)
    }

    @objc private func deleteButtonAction() {
        deleteAction?()
    }

    @objc private func saveButtonAction() {
        saveAction?()
    }
}
