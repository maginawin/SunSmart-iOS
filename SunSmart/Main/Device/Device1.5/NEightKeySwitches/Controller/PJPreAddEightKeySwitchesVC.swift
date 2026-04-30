//
//  PJPreAddEightKeySwitchesVC.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class PJPreAddEightKeySwitchesVC: UIViewController {

    private var viewModel: PJPreAddEightKeySwitchesViewModel

    private lazy var scrollView: UIScrollView = {
        let scrollView = UIScrollView()
        scrollView.backgroundColor = .clear
        scrollView.showsVerticalScrollIndicator = false
        scrollView.keyboardDismissMode = .onDrag
        return scrollView
    }()

    private lazy var contentView = UIView()

    private lazy var nameSectionLabel: UILabel = {
        let label = UILabel(text: "name".localizedString, textColor: Title_Color, fontSize: 14, fontWeight: .light)
        return label
    }()

    private lazy var nameContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var nameTextField: UITextField = {
        let textField = UITextField()
        textField.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        textField.textColor = Title_Color
        textField.tintColor = Title_Done_Color
        textField.clearButtonMode = .never
        textField.returnKeyType = .done
        textField.delegate = self
        textField.addTarget(self, action: #selector(nameDidChange(_:)), for: .editingChanged)
        return textField
    }()

    private lazy var clearNameButton: UIButton = {
        let button = UIButton(type: .custom)
        button.setImage(UIImage(named: "clear"), for: .normal)
        button.addTarget(self, action: #selector(clearNameAction), for: .touchUpInside)
        return button
    }()

    private lazy var settingsContainerView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        view.layer.cornerRadius = 12
        return view
    }()

    private lazy var enableRowView = PJEightKeySwitchInfoRowView(
        title: "enable".localizedString,
        accessory: .toggle
    )

    private lazy var panelRowView = PJEightKeySwitchInfoRowView(
        title: "panel".localizedString,
        accessory: .valueWithArrow
    )

    private lazy var groupRowView = PJEightKeySwitchInfoRowView(
        title: "group".localizedString,
        accessory: .valueWithArrow
    )

    private lazy var sceneRowView = PJEightKeySwitchInfoRowView(
        title: "scene".localizedString,
        accessory: .valueWithArrow
    )

    private lazy var moreSettingsRowView = PJEightKeySwitchInfoRowView(
        title: "neightkeyswitches_more_settings".localizedString,
        accessory: .arrow
    )

    private lazy var panelPreviewView = PJEightKeySwitchPanelView()

    private lazy var bottomActionView = DeviceBottomActionView(frame: .zero)

    init(space: SpaceData) {
        self.viewModel = PJPreAddEightKeySwitchesViewModel(space: space)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        setupNavigation()
        bindViewModel()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelPreviewHeight()
    }

    @objc private func closeAction() {
        view.endEditing(true)
        dismiss(animated: true)
    }

    @objc private func nameDidChange(_ textField: UITextField) {
        viewModel.deviceName = textField.text ?? ""
        updateNameClearButtonState()
    }

    @objc private func clearNameAction() {
        nameTextField.text = nil
        viewModel.deviceName = ""
        updateNameClearButtonState()
    }

    @objc private func enableValueChanged(_ sender: UISwitch) {
        viewModel.isEnabled = sender.isOn
    }

    @objc private func moreSettingsAction() {
        let vc = PJEightKeySwitchMoreSettingsController(state: viewModel.moreSettings)
        vc.settingsChanged = { [weak self] state in
            self?.viewModel.moreSettings = state
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func selectPanelAction() {
        let vc = PJEightKeySwitchSelectPanelController(selectedPanelType: viewModel.selectedPanelType)
        vc.selectPanelTypeCallback = { [weak self] (type: PJEightKeySwitchPanelDefinition.PanelType) in
            guard let self else { return }
            self.viewModel.selectedPanelType = type
            self.panelRowView.setValue(type.title)
            self.panelPreviewView.configure(definition: self.viewModel.selectedPanelDefinition, mode: PJEightKeySwitchPanelView.Mode.preview)
            self.updatePanelPreviewHeight()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func selectGroupsAction() {
        let vc = SwitchSelectGroupsViewController(
            groups: MeshNetworkManager.instance.groups,
            selectGroups: viewModel.selectedGroups
        )
        vc.selectGroupsCallback = { [weak self] groups in
            guard let self else { return }
            self.viewModel.selectedGroups = groups
            self.groupRowView.setValue(self.viewModel.groupTitle)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func selectScenesAction() {
        if SRAlertView.isVisible() {
            return
        }

        let vc = SwitchSelectScenePageController(
            scenes: MeshNetworkManager.instance.scenes,
            sceneDatas: viewModel.sceneDatas
        )
        vc.scenesSelectCallback = { [weak self] sceneDatas in
            guard let self else { return }
            self.viewModel.sceneDatas = sceneDatas
            self.sceneRowView.setValue(self.viewModel.sceneTitle)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func createAction() {
        view.endEditing(true)
        guard MeshNetworkManager.instance.switchs.count < 16 else {
            SRAlertView(
                title: "notification".localizedString,
                message: "switchs_overrun_message".localizedString,
                actions: [SRAlertAction(title: "GOT_IT".localizedString)]
            ).show()
            return
        }

        guard !viewModel.deviceName.isAllInputTextEmpty() else {
            XWHUDManager.showTipHUD("name_empty".localizedString, isLineFeed: true)
            return
        }

        guard !MeshNetworkManager.instance.isSwitchTautonym(name: viewModel.deviceName) else {
            XWHUDManager.showTipHUD("name_already_exists".localizedString, isLineFeed: true)
            return
        }

        let switchData = viewModel.buildSwitchData()
        MeshNetworkManager.instance.switchs.append(switchData)
        switchData.save()
        PJEightKeySwitchRepository.shared.save(switchData)

        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)

        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }

    private func setupNavigation() {
        title = "switch".localizedString
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(closeAction)
        )
        navigationItem.leftBarButtonItem = nil
    }

    private func setupUI() {
        view.backgroundColor = Background_Color

        bottomActionView.setCreateMode(true)
        bottomActionView.createAction = { [weak self] in
            self?.createAction()
        }
        view.addSubview(bottomActionView)
        bottomActionView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(DeviceBottomActionView.preferredHeight)
        }

        view.addSubview(scrollView)
        scrollView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomActionView.snp.top)
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

        let rowViews = [enableRowView, panelRowView, groupRowView, sceneRowView, moreSettingsRowView]
        for rowView in rowViews {
            settingsContainerView.addSubview(rowView)
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
            make.bottom.equalTo(SCRYFrom(-SCRYFrom(24)))
        }

        enableRowView.switchControl.addTarget(self, action: #selector(enableValueChanged(_:)), for: .valueChanged)
        panelRowView.tapAction = { [weak self] in
            self?.selectPanelAction()
        }
        groupRowView.tapAction = { [weak self] in
            self?.selectGroupsAction()
        }
        sceneRowView.tapAction = { [weak self] in
            self?.selectScenesAction()
        }
        moreSettingsRowView.tapAction = { [weak self] in
            self?.moreSettingsAction()
        }
    }

    private func bindViewModel() {
        nameTextField.text = viewModel.deviceName
        enableRowView.switchControl.isOn = viewModel.isEnabled
        panelRowView.setValue(viewModel.panelTitle)
        groupRowView.setValue(viewModel.groupTitle)
        sceneRowView.setValue(viewModel.sceneTitle)
        moreSettingsRowView.setValue(nil)
        panelPreviewView.configure(definition: viewModel.selectedPanelDefinition, mode: PJEightKeySwitchPanelView.Mode.preview)
        updateNameClearButtonState()
    }

    private func updateNameClearButtonState() {
        clearNameButton.isHidden = viewModel.deviceName.isEmpty
    }

    private func updatePanelPreviewHeight() {
        let targetHeight = panelPreviewView.preferredHeight(for: panelPreviewView.bounds.width)
        panelPreviewView.snp.updateConstraints { make in
            make.height.equalTo(targetHeight)
        }
    }
}

extension PJPreAddEightKeySwitchesVC: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
