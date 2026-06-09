//
//  PJEightKeySwitchEditorView.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchEditorView: UIView {

    let isCreateMode: Bool

    let scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    let contentView = UIView()

    let nameSectionLabel = UILabel(text: "name".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light)

    let nameContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    let nameTextField: UITextField = {
        let textField = UITextField()
        textField.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        textField.textColor = Title_Color
        textField.tintColor = Title_Done_Color
        textField.clearButtonMode = .never
        textField.returnKeyType = .done
        return textField
    }()

    let clearNameButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "clear"), for: .normal)
        return button
    }()

    let syncFailedButton: UIButton = {
        let button = UIButton(
            title: "devices_not_synced".localizedString,
            titleSize: 14,
            titleWeight: .light,
            titleColor: Red_Color,
            fit: false,
            normalImageName: "schedule_sync_failed"
        )
        button.isHidden = true
        button.setImagePosition(position: .left, spacing: SCRXFrom(4))
        return button
    }()

    let settingsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    let enableRowView = PJEightKeySwitchInfoRowView(
        title: "enable".localizedString,
        accessory: .toggle
    )

    let panelRowView = PJEightKeySwitchInfoRowView(
        title: "panel".localizedString,
        accessory: .valueWithArrow
    )

    let groupRowView = PJEightKeySwitchInfoRowView(
        title: "group".localizedString,
        accessory: .valueWithArrow
    )

    let sceneRowView = PJEightKeySwitchInfoRowView(
        title: "scene".localizedString,
        accessory: .valueWithArrow
    )

    let moreSettingsRowView = PJEightKeySwitchInfoRowView(
        title: "neightkeyswitches_more_settings".localizedString,
        accessory: .arrow
    )

    let panelPreviewView = PJEightKeySwitchPanelView()

    let linkActionButton: UIButton = {
        let button = UIButton(type: .custom)
        button.titleLabel?.font = UIFont.systemFont(ofSize: SCRYFrom(16), weight: .light)
        button.layer.cornerRadius = SCRYFrom(24)
        button.layer.borderWidth = 1
        return button
    }()

    let bottomActionView = DeviceBottomActionView(frame: .zero)

    init(isCreateMode: Bool) {
        self.isCreateMode = isCreateMode
        super.init(frame: .zero)
        setupUI()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func updatePanelPreviewHeight() {
        let targetHeight = panelPreviewView.preferredHeight(for: panelPreviewView.bounds.width)
        panelPreviewView.snp.updateConstraints { make in
            make.height.equalTo(targetHeight)
        }
    }

    func updateSceneRowVisibility(showsSceneRow: Bool) {
        sceneRowView.isHidden = !showsSceneRow
        sceneRowView.snp.remakeConstraints { make in
            make.top.equalTo(groupRowView.snp.bottom)
            make.left.right.equalToSuperview()
            make.height.equalTo(showsSceneRow ? SCRYFrom(48) : 0)
        }
        moreSettingsRowView.snp.remakeConstraints { make in
            make.top.equalTo(showsSceneRow ? sceneRowView.snp.bottom : groupRowView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(enableRowView)
        }
        layoutIfNeeded()
    }

    private func setupUI() {
        backgroundColor = Background_Color

        bottomActionView.setCreateMode(isCreateMode)
        addSubview(bottomActionView)
        bottomActionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(isCreateMode ? DeviceBottomActionView.preferredHeight : 0)
        }
        bottomActionView.isHidden = !isCreateMode

        addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            if isCreateMode {
                make.bottom.equalTo(bottomActionView.snp.top)
            } else {
                make.bottom.equalToSuperview()
            }
        }

        scrollView.addSubview(contentView)
        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView)
        }

        contentView.addSubview(nameSectionLabel)
        nameSectionLabel.snp.makeConstraints { make in
            make.top.equalTo(SCRYFrom(12))
            make.left.equalTo(SCRXFrom(16))
        }

        contentView.addSubview(syncFailedButton)
        syncFailedButton.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(nameSectionLabel)
        }

        contentView.addSubview(nameContainerView)
        nameContainerView.snp.makeConstraints { make in
            make.top.equalTo(nameSectionLabel.snp.bottom).offset(SCRYFrom(8))
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(48))
        }

        nameContainerView.addSubview(nameTextField)
        nameTextField.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.bottom.equalToSuperview()
            make.right.equalTo(SCRXFrom(-52))
        }

        nameContainerView.addSubview(clearNameButton)
        clearNameButton.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.right.equalTo(SCRXFrom(-16))
            make.width.height.equalTo(SCRXFrom(18))
        }

        contentView.addSubview(settingsContainerView)
        settingsContainerView.snp.makeConstraints { make in
            make.top.equalTo(nameContainerView.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalTo(nameContainerView)
        }

        [enableRowView, panelRowView, groupRowView, sceneRowView, moreSettingsRowView].forEach {
            settingsContainerView.addSubview($0)
        }

        enableRowView.snp.makeConstraints { make in
            make.top.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(48))
        }
        panelRowView.snp.makeConstraints { make in
            make.top.equalTo(enableRowView.snp.bottom)
            make.left.right.height.equalTo(enableRowView)
        }
        groupRowView.snp.makeConstraints { make in
            make.top.equalTo(panelRowView.snp.bottom)
            make.left.right.height.equalTo(enableRowView)
        }
        sceneRowView.snp.makeConstraints { make in
            make.top.equalTo(groupRowView.snp.bottom)
            make.left.right.height.equalTo(enableRowView)
        }
        moreSettingsRowView.snp.makeConstraints { make in
            make.top.equalTo(sceneRowView.snp.bottom)
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(enableRowView)
        }

        contentView.addSubview(panelPreviewView)
        panelPreviewView.snp.makeConstraints { make in
            make.top.equalTo(settingsContainerView.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalTo(nameContainerView)
            make.height.equalTo(SCRYFrom(320))
        }

        contentView.addSubview(linkActionButton)
        linkActionButton.snp.makeConstraints { make in
            make.top.equalTo(panelPreviewView.snp.bottom).offset(SCRYFrom(16))
            make.left.right.equalTo(nameContainerView)
            make.height.equalTo(SCRYFrom(48))
            make.bottom.equalTo(-SCRYFrom(24))
        }
    }
}
