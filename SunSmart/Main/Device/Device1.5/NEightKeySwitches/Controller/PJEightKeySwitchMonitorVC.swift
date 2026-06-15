//
//  PJEightKeySwitchMonitorVC.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class PJEightKeySwitchMonitorVC: UIViewController {

    var deleteSwitchAction: ((DeviceSwitchData, UIViewController) -> Void)?

    private let viewModel: PJEightKeySwitchMonitorViewModel

    private let headerView = PJEightKeySwitchMonitorHeaderView()
    private let panelScrollView = UIScrollView()
    private let panelView = PJEightKeySwitchMonitorPanelView()
    private let bottomView = PJEightKeySwitchMonitorStatusSetView()
    private var isRefreshing = false
    private var activationFlow: PJEightKeySwitchActivationFlow?
    private var batteryRefreshFlow: PJEightKeySwitchBatteryRefreshFlow?
    private var txEnableFlow: PJEightKeySwitchTxEnableFlow?
    private var identifyFlow: PJEightKeySwitchIdentifyFlow?
    private var pendingEnabledValue: Bool?
    private let virtualGroupControlSender = PJEightKeySwitchVirtualGroupControlSender()
    private var lastKeyTapTimes: [Int: Date] = [:]
    private let keyTapThrottleInterval: TimeInterval = 0.2

    init(space: SpaceData, switchData: PJEightKeySwitchData) {
        viewModel = PJEightKeySwitchMonitorViewModel(space: space, switchData: switchData)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.title
        view.backgroundColor = Background_Color
        setupNavigation()
        setupUI()
        bindActions()
        updateUI()
    }

    @objc private func backAction() {
        dismissLikeSystem()
    }

    @objc private func moreAction() {
        var items: [MenuPopView.MenuItem] = []

        if viewModel.isEffectiveVisitor {
            guard viewModel.isRealBatteryPowerSwitch else {
                return
            }
            items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
                self?.pushInformation()
            }))
        } else {
            if viewModel.space.deviceOperates.contains(.edit) {
                items.append(.init(icon: UIImage(named: "menu_edit"), title: "edit".localizedString, tapItemBack: { [weak self] _ in
                    self?.pushEditor()
                }))
            }
            if viewModel.space.deviceOperates.contains(.delete) {
                items.append(.init(icon: UIImage(named: "menu_delete"), title: "delete".localizedString, tapItemBack: { [weak self] _ in
                    self?.deleteCurrentSwitch()
                }))
            }
            if !viewModel.isUnlinkedVirtualBatteryPowerSwitch {
                if viewModel.isRealBatteryPowerSwitch {
                    items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
                        self?.pushInformation()
                    }))
                }
                items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: { [weak self] _ in
                    self?.identifyAction()
                }))
            }
        }

        guard !items.isEmpty else {
            return
        }

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
    }

    private func showNoPermissionTip() {
        XWHUDManager.showTipHUD("No permission!", isLineFeed: true)
    }

    private func identifyAction() {
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            return
        }
        guard viewModel.informationNode != nil else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }

        let flow = PJEightKeySwitchIdentifyFlow(
            presenter: self,
            switchData: viewModel.switchData,
            onFinished: { [weak self] in
                self?.identifyFlow = nil
            }
        )
        identifyFlow = flow
        flow.start()
    }

    private func setupNavigation() {
        navigationItem.leftBarButtonItem = UIBarButtonItem(image: UIImage(named: "navigation_back")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(backAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(image: UIImage(named: "more_vertical")?.withRenderingMode(.alwaysOriginal), style: .done, target: self, action: #selector(moreAction))
    }

    private func setupUI() {
        view.addSubview(headerView)
        if isIPad {
            view.addSubview(panelView)
        } else {
            panelScrollView.showsVerticalScrollIndicator = false
            panelScrollView.alwaysBounceVertical = false
            panelScrollView.contentInsetAdjustmentBehavior = .never
            view.addSubview(panelScrollView)
            panelScrollView.addSubview(panelView)
        }
        view.addSubview(bottomView)

        headerView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide).offset(SCRYFrom(14))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(24))
        }

        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
        }

        if isIPad {
            setupCenteredPanelConstraints()
        } else {
            setupScrollablePanelConstraints()
        }
    }

    private func setupCenteredPanelConstraints() {
        let panelAreaGuide = UILayoutGuide()
        view.addLayoutGuide(panelAreaGuide)
        panelAreaGuide.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }

        panelView.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.centerY.equalTo(panelAreaGuide.snp.centerY)
            make.top.greaterThanOrEqualTo(headerView.snp.bottom).offset(SCRYFrom(18))
            make.bottom.lessThanOrEqualTo(bottomView.snp.top).offset(-SCRYFrom(12))
            make.left.greaterThanOrEqualToSuperview().offset(SCRXFrom(24))
            make.right.lessThanOrEqualToSuperview().offset(-SCRXFrom(24))
            make.width.equalTo(PJEightKeySwitchMonitorPanelView.preferredWidth)
            make.height.equalTo(SCRYFrom(502))
        }
    }

    private func setupScrollablePanelConstraints() {
        panelScrollView.snp.makeConstraints { make in
            make.top.equalTo(headerView.snp.bottom)
            make.left.right.equalToSuperview()
            make.bottom.equalTo(bottomView.snp.top)
        }
        panelScrollView.contentLayoutGuide.snp.makeConstraints { make in
            make.width.equalTo(panelScrollView.frameLayoutGuide.snp.width)
        }

        panelView.snp.makeConstraints { make in
            make.top.equalTo(panelScrollView.contentLayoutGuide.snp.top).offset(SCRYFrom(18))
            make.bottom.equalTo(panelScrollView.contentLayoutGuide.snp.bottom).offset(-SCRYFrom(12))
            make.centerX.equalTo(panelScrollView.frameLayoutGuide.snp.centerX)
            make.left.greaterThanOrEqualTo(panelScrollView.frameLayoutGuide.snp.left).offset(SCRXFrom(24))
            make.right.lessThanOrEqualTo(panelScrollView.frameLayoutGuide.snp.right).offset(-SCRXFrom(24))
            make.width.equalTo(PJEightKeySwitchMonitorPanelView.preferredWidth)
            make.height.equalTo(SCRYFrom(502))
        }
    }

    private func bindActions() {
        headerView.refreshAction = { [weak self] in
            self?.refreshMonitor()
        }

        panelView.keyTapAction = { [weak self] index in
            self?.handlePanelKeyTap(index: index)
        }
        panelView.dimmingLongPressAction = { [weak self] _ in
            self?.presentDimmingPopup()
        }
        panelView.autoLongPressAction = { [weak self] in
            self?.presentForcedAutoPopup()
        }
        panelView.disabledTapAction = { [weak self] in
            guard self?.viewModel.isUnlinkedVirtualBatteryPowerSwitch != true else {
                return
            }
            XWHUDManager.showTipHUD("neightkeyswitches_disabled_tip".localizedString, isLineFeed: true)
        }

        bottomView.enableChanged = { [weak self] isOn in
            self?.startTxEnableUpdate(isOn)
        }

        bottomView.groupLinkAction = {
            XWHUDManager.showTipHUD("group", isLineFeed: false)
        }
    }

    private func updateUI() {
        let header = viewModel.headerState
        headerView.configure(state: .init(
            batteryText: header.batteryText,
            batteryIconSystemName: header.batteryIconSystemName,
            statusPrefixText: header.statusPrefixText,
            statusText: header.statusText,
            statusColor: header.statusColor,
            updatedText: header.updatedText,
            showsRefreshButton: header.showsRefreshButton,
            layout: header.layout == .battery ? .battery : .centeredStatus
        ))

        let isTxEnablePending = pendingEnabledValue != nil
        panelView.configure(items: viewModel.keyItems, enabled: viewModel.settingsState.isEnabled && !isTxEnablePending)
        bottomView.configure(state: .init(
            groupNames: viewModel.settingsState.groupNames,
            isGroupLinked: viewModel.settingsState.isGroupLinked,
            isEnabled: viewModel.settingsState.isEnabled,
            isPending: isTxEnablePending
        ))
    }

    private func refreshMonitor() {
        guard !isRefreshing else { return }
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            updateUI()
            return
        }
        guard viewModel.switchData.powerSwitchKind == .battery else {
            return
        }
        guard let node = viewModel.informationNode else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }
        isRefreshing = true
        headerView.setRefreshing(true)

        let flow = PJEightKeySwitchBatteryRefreshFlow(
            presenter: self,
            node: node,
            onBatteryLevel: { [weak self] level in
                guard let self else { return false }
                guard self.viewModel.saveBatteryLevel(level) else {
                    return false
                }
                self.updateUI()
                return true
            },
            onFinished: { [weak self] in
                self?.finishBatteryRefresh()
            }
        )
        batteryRefreshFlow = flow
        flow.start()
    }

    private func finishBatteryRefresh() {
        isRefreshing = false
        headerView.setRefreshing(false)
        batteryRefreshFlow = nil
    }

    private func handlePanelKeyTap(index: Int) {
        guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
            return
        }
        guard shouldAcceptKeyTap(index: index) else {
            return
        }
        virtualGroupControlSender.sendKeyTap(index: index, switchData: viewModel.switchData)
    }

    private func shouldAcceptKeyTap(index: Int, now: Date = Date()) -> Bool {
        if let lastTapTime = lastKeyTapTimes[index],
           now.timeIntervalSince(lastTapTime) < keyTapThrottleInterval {
            return false
        }
        lastKeyTapTimes[index] = now
        return true
    }

    deinit {
        batteryRefreshFlow?.cancel()
        txEnableFlow?.cancel()
        identifyFlow?.cancel()
        activationFlow = nil
    }

    private func updateUnlinkedVirtualEnable(_ isEnabled: Bool) {
        viewModel.updateEnabled(isEnabled)
        _ = viewModel.persist()
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        updateUI()
    }

    private func startTxEnableUpdate(_ isEnabled: Bool) {
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            updateUI()
            return
        }
        guard pendingEnabledValue == nil else {
            updateUI()
            return
        }
        guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
            updateUnlinkedVirtualEnable(isEnabled)
            return
        }
        guard viewModel.informationNode != nil else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            updateUI()
            return
        }

        pendingEnabledValue = isEnabled
        updateUI()

        if viewModel.switchData.powerSwitchKind == .ac {
            sendACTxEnable(isEnabled)
            return
        }

        let flow = PJEightKeySwitchTxEnableFlow(
            presenter: self,
            switchData: viewModel.switchData,
            enabled: isEnabled,
            onSucceeded: { [weak self] enabled in
                guard let self else { return }
                self.viewModel.applyTxEnableSucceeded(enabled)
                self.viewModel.persist()
                NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
                self.updateUI()
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.pendingEnabledValue = nil
                self.txEnableFlow = nil
                self.updateUI()
            }
        )
        txEnableFlow = flow
        flow.start()
    }

    private func sendACTxEnable(_ isEnabled: Bool) {
        guard let node = viewModel.informationNode else {
            pendingEnabledValue = nil
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            updateUI()
            return
        }

        MeshBatteryPowerSwitchTxEnableSender().sendTxEnable(isEnabled, to: node) { [weak self] succeeded in
            DispatchQueue.main.async {
                guard let self else { return }
                if succeeded {
                    self.viewModel.applyTxEnableSucceeded(isEnabled)
                    self.viewModel.persist()
                    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
                } else {
                    XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                }
                self.pendingEnabledValue = nil
                self.updateUI()
            }
        }
    }

    private func presentDimmingPopup() {
        guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
            return
        }
        let vc = PJEightKeySwitchDimmingPopupController()
        vc.brightnessEndedAction = { [weak self] value in
            guard let self else { return }
            self.virtualGroupControlSender.sendBrightness(value, switchData: self.viewModel.switchData)
        }
        present(vc, animated: true)
    }

    private func presentForcedAutoPopup() {
        guard !viewModel.isUnlinkedVirtualBatteryPowerSwitch else {
            return
        }
        let vc = PJEightKeySwitchForcedAutoPopupController()
        vc.autoAction = { [weak self] in
            guard let self else { return }
            self.virtualGroupControlSender.sendAuto(switchData: self.viewModel.switchData)
        }
        present(vc, animated: true)
    }

    private func pushInformation() {
        guard let node = viewModel.informationNode else {
            XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
            return
        }

        let groupText = viewModel.informationGroupText ?? "Not yet linked to a group".localizedString
        let sceneText = viewModel.informationSceneText ?? "Not yet linked to a scene".localizedString
        let vc = DeviceInformationViewController(
            node: node,
            emptyGroupText: "Not yet linked to a group".localizedString,
            showsSceneSection: viewModel.showsInformationSceneSection,
            groupTextOverride: groupText,
            sceneTextOverride: sceneText,
            nameOverride: viewModel.title,
            showsFullDeviceInfo: true
        )
        navigationController?.pushViewController(vc, animated: true)
    }

    private func pushBatteryPowerSwitchSync() {
        guard viewModel.prepareBatteryPowerSwitchDesiredConfigIfNeeded() else {
            XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
            return
        }
        let needsConfigurationSync = viewModel.switchData.needsBatteryPowerSwitchConfigurationSync
        viewModel.persist()
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        if needsConfigurationSync && viewModel.switchData.requiresActivationBeforeOwnConfiguration {
            presentBatteryPowerSwitchActivation()
        } else {
            pushBatteryPowerSwitchSyncController()
        }
    }

    private func presentBatteryPowerSwitchActivation() {
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: viewModel.switchData
        ) { [weak self] in
            guard let self else { return }
            self.activationFlow = nil
            self.pushBatteryPowerSwitchSyncController()
        }
        activationFlow = flow
        flow.start()
    }

    private func pushBatteryPowerSwitchSyncController() {
        let vc = SyncDevicesViewController(type: .batteryPowerSwitch(viewModel.switchData))
        vc.syncSuccessCallback = { [weak self] _ in
            guard let self else { return }
            self.viewModel.switchData.markBatteryPowerSwitchSyncSucceeded()
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        vc.backActionCallback = { [weak self] result in
            guard let self else { return }
            let failedOperationTypes = result.flatMap(\.failedOperationTypes)
            let successOperationTypes = result.flatMap(\.successOperationTypes)
            if self.containsPowerSwitchSyncOperation(failedOperationTypes) {
                self.viewModel.switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
            } else if self.containsBatteryPowerSwitchOwnConfiguration(successOperationTypes) {
                self.viewModel.switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
            }
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
            self.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func containsBatteryPowerSwitchOwnConfiguration(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchOwnConfigurationOperation }
    }
    
    private func containsPowerSwitchSyncOperation(_ operationTypes: [DeviceOperationType]) -> Bool {
        operationTypes.contains { $0.isPowerSwitchSyncOperation }
    }

    private func pushEditor() {
        guard viewModel.canEditPowerSwitch else {
            showNoPermissionTip()
            return
        }
        let vc = PJPreAddEightKeySwitchesVC(space: viewModel.space, switchData: viewModel.switchData)
        vc.deleteSwitchAction = deleteSwitchAction
        vc.switchSavedAction = { [weak self] switchData in
            guard let self else { return }
            self.viewModel.updateSwitchData(switchData)
            self.title = self.viewModel.title
            self.updateUI()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func deleteUnlinkedVirtualSwitch() {
        MeshNetworkManager.instance.deleteSwitch(switchData: viewModel.switchData)
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
            self?.dismissLikeSystem()
        }
    }

    private func deleteCurrentSwitch() {
        guard viewModel.space.deviceOperates.contains(.delete) else {
            showNoPermissionTip()
            return
        }

        SRAlertView(
            title: "notification".localizedString,
            message: viewModel.switchData.powerSwitchKind.deleteConfirmationMessage,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    guard let self else { return }
                    if self.viewModel.isUnlinkedVirtualBatteryPowerSwitch {
                        self.deleteUnlinkedVirtualSwitch()
                    } else {
                        self.deleteSwitchAction?(self.viewModel.switchData, self)
                    }
                })
            ]
        ).show()
    }
}

private final class PJEightKeySwitchVirtualGroupControlSender {

    private static let dimmingStepLevel: Int32 = 13107

    func sendKeyTap(index: Int, switchData: PJEightKeySwitchData) {
        guard let address = switchData.linkGroupAddress,
              let message = keyTapMessage(index: index, switchData: switchData) else {
            return
        }
        MeshAPI.sendMessage(message: message, address: address)
    }

    func sendBrightness(_ value: Int, switchData: PJEightKeySwitchData) {
        guard let address = switchData.linkGroupAddress else {
            return
        }
        let lightness = Node.getLightness(lightness100: value)
        MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: address)
    }

    func sendAuto(switchData: PJEightKeySwitchData) {
        guard let address = switchData.linkGroupAddress else {
            return
        }
        let message = LightLCLightOnOffSetUnacknowledged(true, transitionTime: .default, delay: 0)
        MeshAPI.sendMessage(message: message, address: address)
    }

    private func keyTapMessage(index: Int, switchData: PJEightKeySwitchData) -> MeshMessage? {
        switch index {
        case 0...3:
            return topKeyMessage(index: index, switchData: switchData)
        case 4:
            return dimmingDeltaMessage(delta: Self.dimmingStepLevel)
        case 5:
            return dimmingDeltaMessage(delta: -Self.dimmingStepLevel)
        case 6:
            return GenericOnOffSetUnacknowledged(true)
        case 7:
            return GenericOnOffSetUnacknowledged(false)
        default:
            return nil
        }
    }

    private func dimmingDeltaMessage(delta: Int32) -> GenericDeltaSetUnacknowledged {
        var message = GenericDeltaSetUnacknowledged(delta: delta)
        message.continueTransaction = false
        return message
    }

    private func topKeyMessage(index: Int, switchData: PJEightKeySwitchData) -> MeshMessage? {
        switch switchData.eightKeyPanelType {
        case .scene8Key:
            let sceneNumbers = [
                switchData.sceneANumber,
                switchData.sceneBNumber,
                switchData.sceneCNumber,
                switchData.sceneDNumber
            ]
            guard sceneNumbers.indices.contains(index),
                  let sceneNumber = sceneNumbers[index] else {
                return nil
            }
            return SceneRecallUnacknowledged(sceneNumber)
        case .brightness8Key:
            let brightnessValues = [100, 75, 50, 25]
            guard brightnessValues.indices.contains(index) else {
                return nil
            }
            let lightness = Node.getLightness(lightness100: brightnessValues[index])
            return LightLightnessSetUnacknowledged(lightness: lightness)
        }
    }
}
