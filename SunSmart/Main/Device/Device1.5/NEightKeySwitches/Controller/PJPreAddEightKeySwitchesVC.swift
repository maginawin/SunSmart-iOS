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

    private struct Snapshot: Equatable {
        let deviceName: String
        let isEnabled: Bool
        let selectedPanelType: PJEightKeySwitchPanelDefinition.PanelType
        let selectedGroupAddresses: [Address]
        let sceneNumbers: [SceneNumber?]
        let periodicReporting: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption
        let ledIndicatorEnabled: Bool
    }

    private struct BatteryPowerSwitchOwnStateSnapshot {
        let enabled: Bool
        let moreSettings: PJEightKeySwitchMoreSettingsViewModel.State
    }
    
    var deleteSwitchAction: ((DeviceSwitchData) -> Void)?
    var switchSavedAction: ((PJEightKeySwitchData) -> Void)?
    
    private var viewModel: PJPreAddEightKeySwitchesViewModel
    private var initialSnapshot: Snapshot?
    private weak var previousPopGestureDelegate: UIGestureRecognizerDelegate?
    private var activationFlow: PJEightKeySwitchActivationFlow?
    private var pendingBatteryPowerSwitchOwnStateSnapshot: BatteryPowerSwitchOwnStateSnapshot?
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard isEditMode, let popGesture = navigationController?.interactivePopGestureRecognizer else { return }
        previousPopGestureDelegate = popGesture.delegate
        popGesture.delegate = self
        popGesture.isEnabled = true
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        guard let popGesture = navigationController?.interactivePopGestureRecognizer,
              popGesture.delegate === self else {
            return
        }
        popGesture.delegate = previousPopGestureDelegate
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updatePanelPreviewHeight()
    }
    
    @objc private func closeAction() {
        view.endEditing(true)
        guard hasUnsavedChanges else {
            closeEditor(animated: true)
            return
        }
        SRAlertView(
            title: "notification".localizedString,
            message: "profile_exiting_message".localizedString,
            actions: [
                SRAlertAction(title: "keep_edit".localizedString, style: .cancel),
                SRAlertAction(title: "EXIT".localizedString, actionHandler: { [weak self] _ in
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self?.closeEditor(animated: true)
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
        let context = PJDevicesAddEntryContext(
            source: .eightKeySwitch,
            space: viewModel.space,
            title: "add_device".localizedString,
            appointGroup: nil,
            addBehavior: .init(
                allowsTargetSelection: false,
                allowsCategorySelection: false,
                allowedTypes: [.switches],
                blockedDeviceTypes: [],
                selectionMode: .single,
                forbiddenSelectionTip: "You can't choose other devices.",
                forbiddenDeviceTypeTip: "Cannot add, type mismatch"
            )
        )
        let controller = PJDevicesAddFlowFactory.make(context: context)
        navigationController?.pushViewController(controller, animated: true)
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
        let vc = PJDeviceGroupSelectionViewController(
            context: .init(
                title: "select_group(s)".localizedString,
                groups: MeshNetworkManager.instance.groups,
                selectedGroupAddresses: viewModel.selectedGroups.map(\.address.address),
                disabledGroupAddresses: [],
                disabledSelectionTip: ""
            )
        ) { [weak self] addresses in
            guard let self else { return }
            self.viewModel.selectedGroups = MeshNetworkManager.instance.groups.filter { addresses.contains($0.address.address) }
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
        if isBatteryPowerSwitchLinked(switchData) {
            submitBatteryPowerSwitch(switchData)
            return
        }

        persistSwitchData(switchData)
        switchSavedAction?(switchData)
        
        postSwitchDataChangedNotifications()
        
        initialSnapshot = makeSnapshot()

        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.closeEditor(animated: true)
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

    private var isEditMode: Bool {
        viewModel.sourceSwitchData != nil
    }

    private var isPushedInNavigationStack: Bool {
        guard let navigationController else { return false }
        return navigationController.viewControllers.first !== self
    }

    private func closeEditor(animated: Bool) {
        if isEditMode, isPushedInNavigationStack {
            navigationController?.popViewController(animated: animated)
        } else {
            dismiss(animated: animated)
        }
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
        if isBatteryPowerSwitchLinked(switchData) {
            return true
        }
        return switchData.proxyNodeAddress != nil && !(switchData.enOceanMacAddress?.isEmpty ?? true)
    }

    private func isBatteryPowerSwitchLinked(_ switchData: DeviceSwitchData) -> Bool {
        switchData.proxyNode?.isBatteryPowerSwitch == true
    }

    private func submitBatteryPowerSwitch(_ switchData: PJEightKeySwitchData) {
        updateBatteryPowerSwitchRemovedGroups(switchData)
        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
            return
        }

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        let desiredHash = switchData.batteryPowerSwitchDesiredConfigHash(appKeyIndex: appKeyIndex)
        let needsConfigurationSync = needsBatteryPowerSwitchConfigurationSync(switchData, desiredHash: desiredHash)
        let needsTxEnableSync = needsBatteryPowerSwitchTxEnableSync(switchData)
        let needsLEDIndicatorSync = needsBatteryPowerSwitchLEDIndicatorSync(switchData)
        let needsTargetSync = switchData.needSyncData
        let needsOwnConfigurationSync = needsConfigurationSync || needsTxEnableSync || needsLEDIndicatorSync
        if needsConfigurationSync {
            switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        } else {
            switchData.desiredConfigHash = desiredHash
            if switchData.desiredConfigVersion == 0 {
                switchData.desiredConfigVersion = 1
            }
        }

        if !needsOwnConfigurationSync {
            persistSwitchData(switchData)
            switchSavedAction?(switchData)
            postSwitchDataChangedNotifications()
            initialSnapshot = makeSnapshot()
        }

        guard needsOwnConfigurationSync || needsTargetSync else {
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.closeEditor(animated: true)
            }
            return
        }

        if needsOwnConfigurationSync {
            if let sourceSwitchData = viewModel.sourceSwitchData {
                pendingBatteryPowerSwitchOwnStateSnapshot = BatteryPowerSwitchOwnStateSnapshot(
                    enabled: sourceSwitchData.enabled,
                    moreSettings: sourceSwitchData.moreSettingsState
                )
            }
            presentBatteryPowerSwitchActivation(for: switchData)
        } else {
            pushBatteryPowerSwitchSync(switchData)
        }
    }

    private func updateBatteryPowerSwitchRemovedGroups(_ switchData: PJEightKeySwitchData) {
        let previousAddresses = Set(viewModel.sourceSwitchData?.bindGroupAddresses ?? [])
        let currentAddresses = Set(switchData.bindGroupAddresses)
        let removedAddresses = previousAddresses.subtracting(currentAddresses)
        let pendingRemovedAddresses = Set(switchData.unbindGroupAddresses).union(removedAddresses)
        switchData.unbindGroupAddresses = pendingRemovedAddresses
            .filter { !currentAddresses.contains($0) }
            .sorted()
    }

    private func pushBatteryPowerSwitchSync(_ switchData: PJEightKeySwitchData) {
        let vc = SyncDevicesViewController(type: .batteryPowerSwitch(switchData))
        vc.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            switchData.markBatteryPowerSwitchSyncSucceeded()
            self.pendingBatteryPowerSwitchOwnStateSnapshot = nil
            self.persistSwitchData(switchData)
            self.switchSavedAction?(switchData)
            self.postSwitchDataChangedNotifications()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.popBackAfterBatteryPowerSwitchSync(animated: true)
            }
        }
        vc.backActionCallback = { [weak self] result in
            guard let self else { return }
            let failedOperationTypes = result.flatMap(\.failedOperationTypes)
            let successOperationTypes = result.flatMap(\.successOperationTypes)
            if self.containsBatteryPowerSwitchOwnConfiguration(failedOperationTypes) {
                switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
                if let snapshot = self.pendingBatteryPowerSwitchOwnStateSnapshot {
                    switchData.enabled = snapshot.enabled
                    switchData.moreSettingsState = snapshot.moreSettings
                }
            } else if self.containsBatteryPowerSwitchOwnConfiguration(successOperationTypes) {
                switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
            }
            self.pendingBatteryPowerSwitchOwnStateSnapshot = nil
            self.persistSwitchData(switchData)
            self.switchSavedAction?(switchData)
            self.postSwitchDataChangedNotifications()
            self.popBackAfterBatteryPowerSwitchSync(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func containsBatteryPowerSwitchOwnConfiguration(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { operationType in
            guard case .configuration(_, let syncData) = operationType else {
                return false
            }
            switch syncData {
            case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
                return true
            default:
                return false
            }
        }
    }

    private func needsBatteryPowerSwitchConfigurationSync(_ switchData: PJEightKeySwitchData, desiredHash: String) -> Bool {
        guard let sourceSwitchData = viewModel.sourceSwitchData else {
            return switchData.needsBatteryPowerSwitchConfigurationSync
        }

        if sourceSwitchData.linkGroupAddress != switchData.linkGroupAddress ||
            sourceSwitchData.eightKeyPanelType != switchData.eightKeyPanelType {
            return true
        }

        if switchData.eightKeyPanelType == .scene8Key,
           sourceSwitchData.sceneANumber != switchData.sceneANumber ||
            sourceSwitchData.sceneBNumber != switchData.sceneBNumber ||
            sourceSwitchData.sceneCNumber != switchData.sceneCNumber ||
            sourceSwitchData.sceneDNumber != switchData.sceneDNumber {
            return true
        }

        return switchData.syncState != .synced && switchData.appliedConfigHash != desiredHash
    }

    private func needsBatteryPowerSwitchTxEnableSync(_ switchData: PJEightKeySwitchData) -> Bool {
        guard isBatteryPowerSwitchLinked(switchData) else {
            return false
        }
        guard let sourceSwitchData = viewModel.sourceSwitchData else {
            return switchData.needsBatteryPowerSwitchTxEnableSync
        }
        return sourceSwitchData.enabled != switchData.enabled || switchData.needsBatteryPowerSwitchTxEnableSync
    }

    private func needsBatteryPowerSwitchLEDIndicatorSync(_ switchData: PJEightKeySwitchData) -> Bool {
        guard isBatteryPowerSwitchLinked(switchData) else {
            return false
        }
        guard let sourceSwitchData = viewModel.sourceSwitchData else {
            return switchData.needsBatteryPowerSwitchLEDIndicatorSync
        }
        return sourceSwitchData.moreSettingsState.ledIndicatorEnabled != switchData.moreSettingsState.ledIndicatorEnabled
            || switchData.needsBatteryPowerSwitchLEDIndicatorSync
    }

    private func presentBatteryPowerSwitchActivation(for switchData: PJEightKeySwitchData) {
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: switchData
        ) { [weak self, weak switchData] in
            guard let self, let switchData else { return }
            self.activationFlow = nil
            self.pushBatteryPowerSwitchSync(switchData)
        }
        activationFlow = flow
        flow.start()
    }

    private func popBackAfterBatteryPowerSwitchSync(animated: Bool) {
        guard let navigationController else {
            closeEditor(animated: animated)
            return
        }
        if let editorIndex = navigationController.viewControllers.firstIndex(of: self), editorIndex > 0 {
            navigationController.popToViewController(navigationController.viewControllers[editorIndex - 1], animated: animated)
        } else {
            closeEditor(animated: animated)
        }
    }

    private func postSwitchDataChangedNotifications() {
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
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

extension PJPreAddEightKeySwitchesVC: UIGestureRecognizerDelegate {

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === navigationController?.interactivePopGestureRecognizer else {
            return true
        }
        guard hasUnsavedChanges else {
            return true
        }
        guard !SRAlertView.isVisible() else {
            return false
        }
        closeAction()
        return false
    }
}
