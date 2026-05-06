//
//  PJPreAddEightKeySwitchesVC.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

final class PJPreAddEightKeySwitchesVC: UIViewController {

    private enum ActivationDemoOutcome {
        case detected
        case timeout
    }

    private struct Snapshot: Equatable {
        let deviceName: String
        let isEnabled: Bool
        let selectedPanelType: PJEightKeySwitchPanelDefinition.PanelType
        let selectedGroupAddresses: [Address]
        let sceneNumbers: [SceneNumber?]
        let periodicReporting: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption
        let ledIndicatorEnabled: Bool
    }
    
    var deleteSwitchAction: ((DeviceSwitchData) -> Void)?
    
    private var viewModel: PJPreAddEightKeySwitchesViewModel
    private var initialSnapshot: Snapshot?
    private weak var activationAlertController: PJEightKeySwitchActivationAlertController?
    private var nextActivationDemoOutcome: ActivationDemoOutcome = .detected
    private lazy var saveBarButtonItem = UIBarButtonItem(
        title: "save".localizedString,
        color: RGB(0, 0, 0, 0.85),
        font: UIFont.systemFont(ofSize: 16, weight: .light),
        target: self,
        sel: #selector(saveBarButtonAction)
    )
    private lazy var editorView = PJEightKeySwitchEditorView(isCreateMode: viewModel.sourceSwitchData == nil)
    
    init(space: SpaceData) {
        self.viewModel = PJPreAddEightKeySwitchesViewModel(space: space)
        super.init(nibName: nil, bundle: nil)
    }
    
    init(space: SpaceData, switchData: PJEightKeySwitchData) {
        self.viewModel = PJPreAddEightKeySwitchesViewModel(space: space, switchData: switchData)
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        isModalInPresentation = true
        setupUI()
        setupNavigation()
        bindViewModel()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.isModalInPresentation = true
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelPreviewHeight()
    }
    
    @objc private func closeAction() {
        view.endEditing(true)
        guard hasUnsavedChanges else {
            dismiss(animated: true)
            return
        }
        SRAlertView(
            title: "notification".localizedString,
            message: "profile_exiting_message".localizedString,
            actions: [
                SRAlertAction(title: "keep_edit".localizedString, style: .cancel),
                SRAlertAction(title: "EXIT".localizedString, actionHandler: { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.dismiss(animated: true)
                    }
                })
            ]
        ).show()
    }
    
    @objc private func backAction() {
        closeAction()
    }
    
    @objc private func nameDidChange(_ textField: UITextField) {
        viewModel.deviceName = textField.text ?? ""
        updateNameClearButtonState()
        updateSaveBarButtonState()
    }
    
    @objc private func clearNameAction() {
        editorView.nameTextField.text = nil
        viewModel.deviceName = ""
        updateNameClearButtonState()
        updateSaveBarButtonState()
    }
    
    @objc private func enableValueChanged(_ sender: UISwitch) {
        viewModel.isEnabled = sender.isOn
        updateSaveBarButtonState()
    }
    
    @objc private func saveBarButtonAction() {
        submitAction()
    }
    
    @objc private func linkAction() {
        XWHUDManager.showTipHUD("link", isLineFeed: false)
    }
    
    @objc private func moreSettingsAction() {
        let vc = PJEightKeySwitchMoreSettingsController(state: viewModel.moreSettings)
        vc.settingsChanged = { [weak self] state in
            self?.viewModel.moreSettings = state
            self?.updateSaveBarButtonState()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func selectPanelAction() {
        let vc = PJEightKeySwitchSelectPanelController(selectedPanelType: viewModel.selectedPanelType)
        vc.selectPanelTypeCallback = { [weak self] (type: PJEightKeySwitchPanelDefinition.PanelType) in
            guard let self else { return }
            self.viewModel.selectedPanelType = type
            if !self.viewModel.showsSceneRow {
                self.viewModel.clearSceneDatas()
            }
            self.editorView.panelRowView.setValue(type.title)
            self.editorView.sceneRowView.setValue(self.viewModel.sceneTitle)
            self.editorView.panelPreviewView.configure(definition: self.viewModel.selectedPanelDefinition, mode: PJEightKeySwitchPanelView.Mode.preview)
            self.updateSceneRowVisibility()
            self.updatePanelPreviewHeight()
            self.updateSaveBarButtonState()
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
            self.editorView.groupRowView.setValue(self.viewModel.groupTitle)
            self.updateSaveBarButtonState()
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
            self.editorView.sceneRowView.setValue(self.viewModel.sceneTitle)
            self.updateSaveBarButtonState()
        }
        navigationController?.pushViewController(vc, animated: true)
    }
    
    private func submitAction() {
        view.endEditing(true)
        //模拟保存激活切换
        if viewModel.sourceSwitchData == nil, MeshNetworkManager.instance.switchs.count >= 16 {
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
        
        guard !(MeshNetworkManager.instance.isSwitchTautonym(name: viewModel.deviceName) && viewModel.deviceName != viewModel.sourceSwitchData?.name) else {
            XWHUDManager.showTipHUD("name_already_exists".localizedString, isLineFeed: true)
            return
        }
        
        let switchData = viewModel.buildSwitchData()
        persistSwitchData(switchData)
        
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        
        initialSnapshot = makeSnapshot()
        
        guard !hasRealDeviceLink(switchData) else {
            presentActivationAlert(for: switchData)
            return
        }
        
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.dismiss(animated: true)
        }
    }
    
    private func deleteAction() {
        guard let switchData = viewModel.sourceSwitchData else { return }
        SRAlertView(
            title: "notification".localizedString,
            message: "switchs_delete_message".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    self?.dismiss(animated: true) {
                        self?.deleteSwitchAction?(switchData)
                    }
                })
            ]
        ).show()
    }
    
    private func setupNavigation() {
        title = "switch".localizedString
        let closeBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "close")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(closeAction)
        )
        let backBarButtonItem = UIBarButtonItem(
            image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal),
            style: .done,
            target: self,
            action: #selector(backAction)
        )
        if viewModel.sourceSwitchData == nil {
            navigationItem.rightBarButtonItem = closeBarButtonItem
            navigationItem.leftBarButtonItem = nil
        } else {
            navigationItem.leftBarButtonItem = backBarButtonItem
            navigationItem.rightBarButtonItem = saveBarButtonItem
        }
    }
    
    private func setupUI() {
        view.backgroundColor = Background_Color
        view.addSubview(editorView)
        editorView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        
        editorView.nameTextField.delegate = self
        editorView.nameTextField.addTarget(self, action: #selector(nameDidChange(_:)), for: .editingChanged)
        editorView.clearNameButton.addTarget(self, action: #selector(clearNameAction), for: .touchUpInside)
        editorView.linkActionButton.addTarget(self, action: #selector(linkAction), for: .touchUpInside)
        
        editorView.bottomActionView.createAction = { [weak self] in
            self?.submitAction()
        }
        editorView.bottomActionView.saveAction = { [weak self] in
            self?.submitAction()
        }
        editorView.bottomActionView.deleteAction = { [weak self] in
            self?.deleteAction()
        }
        
        editorView.enableRowView.switchControl.addTarget(self, action: #selector(enableValueChanged(_:)), for: .valueChanged)
        editorView.panelRowView.tapAction = { [weak self] in
            self?.selectPanelAction()
        }
        editorView.groupRowView.tapAction = { [weak self] in
            self?.selectGroupsAction()
        }
        editorView.sceneRowView.tapAction = { [weak self] in
            self?.selectScenesAction()
        }
        editorView.moreSettingsRowView.tapAction = { [weak self] in
            self?.moreSettingsAction()
        }
    }
    
    private func bindViewModel() {
        editorView.nameTextField.text = viewModel.deviceName
        editorView.enableRowView.switchControl.isOn = viewModel.isEnabled
        editorView.panelRowView.setValue(viewModel.panelTitle)
        editorView.groupRowView.setValue(viewModel.groupTitle)
        editorView.sceneRowView.setValue(viewModel.sceneTitle)
        editorView.moreSettingsRowView.setValue(nil)
        editorView.panelPreviewView.configure(definition: viewModel.selectedPanelDefinition, mode: PJEightKeySwitchPanelView.Mode.preview)
        updateNameClearButtonState()
        updateLinkActionButtonState()
        updateSceneRowVisibility()
        initialSnapshot = makeSnapshot()
        updateSaveBarButtonState()
    }
    
    private func updateNameClearButtonState() {
        editorView.clearNameButton.isHidden = viewModel.deviceName.isEmpty
    }
    
    private func updateSaveBarButtonState() {
        guard viewModel.sourceSwitchData != nil else { return }
        let nameValid = !(viewModel.deviceName.isAllInputTextEmpty()
            || MeshNetworkManager.instance.isSwitchTautonym(name: viewModel.deviceName) && viewModel.deviceName != viewModel.sourceSwitchData?.name)
        saveBarButtonItem.isEnabled = nameValid
    }
    
    private func updatePanelPreviewHeight() {
        editorView.updatePanelPreviewHeight()
    }
    
    private func updateSceneRowVisibility() {
        editorView.updateSceneRowVisibility(showsSceneRow: viewModel.showsSceneRow)
    }
    
    private var hasUnsavedChanges: Bool {
        guard let initialSnapshot else { return false }
        return initialSnapshot != makeSnapshot()
    }
    
    private func makeSnapshot() -> Snapshot {
        Snapshot(
            deviceName: viewModel.deviceName,
            isEnabled: viewModel.isEnabled,
            selectedPanelType: viewModel.selectedPanelType,
            selectedGroupAddresses: viewModel.selectedGroups.map(\.address.address),
            sceneNumbers: viewModel.sceneDatas.map(\.scene?.number),
            periodicReporting: viewModel.moreSettings.periodicReporting,
            ledIndicatorEnabled: viewModel.moreSettings.ledIndicatorEnabled
        )
    }
    
    private var isRealDeviceLinked: Bool {
        guard let switchData = currentEightKeySwitchData else { return false }
        return hasRealDeviceLink(switchData)
    }
    
    private var currentEightKeySwitchData: PJEightKeySwitchData? {
        guard let switchId = viewModel.sourceSwitchData?.id else { return nil }
        guard let currentSwitch = MeshNetworkManager.instance.switchs.first(where: { $0.id == switchId }) else {
            return viewModel.sourceSwitchData
        }
        if let eightKeySwitch = currentSwitch as? PJEightKeySwitchData {
            return eightKeySwitch
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: currentSwitch)
    }
    
    private func updateLinkActionButtonState() {
        let isEditing = viewModel.sourceSwitchData != nil
        editorView.linkActionButton.isHidden = !isEditing
        
        if isRealDeviceLinked {
            editorView.linkActionButton.setTitle("LINKED", for: .normal)
            editorView.linkActionButton.setTitleColor(RGB(98, 193, 96), for: .normal)
            editorView.linkActionButton.backgroundColor = RGB(234, 248, 234)
            editorView.linkActionButton.layer.borderColor = UIColor.clear.cgColor
            editorView.linkActionButton.isEnabled = false
        } else {
            editorView.linkActionButton.setTitle("LINK", for: .normal)
            editorView.linkActionButton.setTitleColor(Title_Done_Color, for: .normal)
            editorView.linkActionButton.backgroundColor = .white
            editorView.linkActionButton.layer.borderColor = RGB(174, 186, 226).cgColor
            editorView.linkActionButton.isEnabled = true
        }
    }
    
    private func hasRealDeviceLink(_ switchData: DeviceSwitchData) -> Bool {
        switchData.proxyNodeAddress != nil && !(switchData.enOceanMacAddress?.isEmpty ?? true)
    }
    
    private func presentActivationAlert(for switchData: PJEightKeySwitchData) {
        let demoOutcome = nextActivationDemoOutcome
        nextActivationDemoOutcome = demoOutcome == .detected ? .timeout : .detected
        let controller = PJEightKeySwitchActivationAlertController(panelType: switchData.eightKeyPanelType)
        controller.cancelAction = { [weak self] in
            self?.refreshEditingStateFromCurrentSwitchData()
        }
        controller.retryAction = { [weak self, weak controller] in
            self?.refreshEditingStateFromCurrentSwitchData()
            self?.scheduleActivationDemoResult(on: controller, outcome: .detected)
        }
        activationAlertController = controller
        present(controller, animated: true) { [weak controller] in
            controller?.startWaiting()
            self.scheduleActivationDemoResult(on: controller, outcome: demoOutcome)
        }
    }

    private func scheduleActivationDemoResult(on controller: PJEightKeySwitchActivationAlertController?, outcome: ActivationDemoOutcome) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak controller] in
            guard let controller, controller.presentingViewController != nil else { return }
            switch outcome {
            case .detected:
                controller.showDetected()
            case .timeout:
                controller.showTimeout()
            }
        }
    }
    
    private func persistSwitchData(_ switchData: PJEightKeySwitchData) {
        if let sourceSwitchData = viewModel.sourceSwitchData,
           let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == sourceSwitchData.id }) {
            MeshNetworkManager.instance.switchs[index] = switchData
        } else {
            MeshNetworkManager.instance.switchs.append(switchData)
        }
        switchData.save()
        PJEightKeySwitchRepository.shared.save(switchData)
    }
    
    private func refreshEditingStateFromCurrentSwitchData() {
        guard let switchData = currentEightKeySwitchData else { return }
        viewModel = PJPreAddEightKeySwitchesViewModel(space: viewModel.space, switchData: switchData)
        bindViewModel()
    }
    
}
extension PJPreAddEightKeySwitchesVC: UITextFieldDelegate {

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
