//
//  PJEightKeySwitchMonitorVC.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit

final class PJEightKeySwitchMonitorVC: UIViewController {

    var deleteSwitchAction: ((DeviceSwitchData) -> Void)?

    private let viewModel: PJEightKeySwitchMonitorViewModel

    private let headerView = PJEightKeySwitchMonitorHeaderView()
    private let panelScrollView = UIScrollView()
    private let panelView = PJEightKeySwitchMonitorPanelView()
    private let bottomView = PJEightKeySwitchMonitorStatusSetView()
    private var isRefreshing = false
    private var nextRefreshSimulationWillSucceed = true
    private var activationFlow: PJEightKeySwitchActivationFlow?

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
        if viewModel.isRealBatteryPowerSwitch {
            items.append(.init(icon: UIImage(named: "menu_information"), title: "information".localizedString, tapItemBack: { [weak self] _ in
                self?.pushInformation()
            }))
        }
        items.append(.init(icon: UIImage(named: "Identify_gateway"), title: "Identify", tapItemBack: {  _ in
           //Identify
        }))
        

        let touchCenterX = view.width - navigationRightItemMargin - 15
        let touchCenterY = view.safeAreaInsets.top - 10
        let windowPoint = view.convert(CGPoint(x: touchCenterX, y: touchCenterY), to: UIApplication.shared.keyWindow())
        MenuPopView.show(items: items, anchorPoint: windowPoint, menuWidth: SCRXFrom(114))
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

        panelView.dimmingLongPressAction = { [weak self] _ in
            self?.presentDimmingPopup()
        }
        panelView.autoLongPressAction = { [weak self] in
            self?.presentForcedAutoPopup()
        }
        panelView.disabledTapAction = {
            XWHUDManager.showTipHUD("neightkeyswitches_disabled_tip".localizedString, isLineFeed: true)
        }

        bottomView.enableChanged = { [weak self] isOn in
            guard let self else { return }
            self.viewModel.updateEnabled(isOn)
            guard self.viewModel.prepareBatteryPowerSwitchDesiredConfigIfNeeded() else {
                self.viewModel.updateEnabled(!isOn)
                self.updateUI()
                XWHUDManager.showErrorTipHUD("group_address_insufficient_message".localizedString, timer: 2)
                return
            }
            self.viewModel.persist()
            NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            self.updateUI()
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
            updatedText: header.updatedText
        ))

        panelView.configure(items: viewModel.keyItems, enabled: viewModel.settingsState.isEnabled)
        bottomView.configure(state: .init(
            groupNames: viewModel.settingsState.groupNames,
            isGroupLinked: viewModel.settingsState.isGroupLinked,
            isEnabled: viewModel.settingsState.isEnabled
        ))
    }

    private func refreshMonitor() {
        guard !isRefreshing else { return }
        guard !viewModel.needsBatteryPowerSwitchSync else {
            pushBatteryPowerSwitchSync()
            return
        }
        isRefreshing = true

        let willSucceed = nextRefreshSimulationWillSucceed
        nextRefreshSimulationWillSucceed.toggle()

        let vc = PJEightKeySwitchRefreshAlertController()
        vc.cancelAction = { [weak self] in
            self?.isRefreshing = false
        }
        vc.retryAction = { [weak self, weak vc] in
            self?.scheduleRefreshSimulation(for: vc, willSucceed: true)
        }
        present(vc, animated: true) { [weak self, weak vc] in
            vc?.startWaiting()
            self?.scheduleRefreshSimulation(for: vc, willSucceed: willSucceed)
        }
    }

    private func scheduleRefreshSimulation(for controller: PJEightKeySwitchRefreshAlertController?, willSucceed: Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self, weak controller] in
            guard let self, let controller, controller.presentingViewController != nil else { return }
            self.updateUI()
            self.isRefreshing = false
            if willSucceed {
                controller.showUpdated()
            } else {
                controller.showTimeout()
            }
        }
    }

    private func presentDimmingPopup() {
        let vc = PJEightKeySwitchDimmingPopupController()
        present(vc, animated: true)
    }

    private func presentForcedAutoPopup() {
        let vc = PJEightKeySwitchForcedAutoPopupController()
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
        if needsConfigurationSync {
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
            if self.containsBatteryPowerSwitchOwnConfiguration(failedOperationTypes) {
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
        operationTypes.contains { operationType in
            guard case .configuration(_, let syncData) = operationType else {
                return false
            }
            switch syncData {
            case .batteryPowerSwitchReset, .batteryPowerSwitchKeyConfig, .batteryPowerSwitchModelPublication:
                return true
            default:
                return false
            }
        }
    }

    private func pushEditor() {
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

    private func deleteCurrentSwitch() {
        SRAlertView(
            title: "notification".localizedString,
            message: "switchs_delete_message".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self] _ in
                    guard let self else { return }
                    self.dismiss(animated: true) {
                        self.deleteSwitchAction?(self.viewModel.switchData)
                    }
                })
            ]
        ).show()
    }
}
