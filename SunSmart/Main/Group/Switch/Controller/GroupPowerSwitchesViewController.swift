//
//  GroupPowerSwitchesViewController.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import UIKit
import NordicSigMeshSDK

final class GroupPowerSwitchesViewController: UIViewController {

    private let viewModel: GroupPowerSwitchesViewModel
    private let editable: Bool
    private var expandedSwitchIDs: Set<String> = []
    private var pendingEnableSwitchIDs: Set<String> = []
    private var activationFlow: PJEightKeySwitchActivationFlow?
    private var txEnableFlows: [String: PJEightKeySwitchTxEnableFlow] = [:]

    private enum Row: Equatable {
        case panel
        case group
        case scene
        case moreSettings
        case panelPreview
    }

    private let tableView: UITableView = {
        let tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.rowHeight = UITableView.automaticDimension
        tableView.estimatedRowHeight = SCRYFrom(80)
        tableView.register(CustomTableViewCell.self, forCellReuseIdentifier: "info")
        tableView.register(GroupPowerSwitchPanelCell.self, forCellReuseIdentifier: "panel")
        tableView.register(GroupPowerSwitchHeaderView.self, forHeaderFooterViewReuseIdentifier: "header")
        return tableView
    }()

    private let bottomView: UIView = {
        let view = UIView()
        view.backgroundColor = .white
        return view
    }()

    private lazy var addSwitchButton = UIButton(
        title: "add_virtual_switch".localizedString,
        titleSize: 15,
        titleWeight: .light,
        titleColor: Title_Color,
        target: self,
        action: #selector(addSwitchButtonAction)
    )

    init(group: Group, kind: GroupPowerSwitchesViewModel.Kind, editable: Bool) {
        self.viewModel = GroupPowerSwitchesViewModel(group: group, kind: kind)
        self.editable = editable
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        txEnableFlows.values.forEach { $0.cancel() }
        activationFlow = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = viewModel.kind.title
        view.backgroundColor = Background_Color
        isModalInPresentation = true
        navigationController?.setNavigationBarBackgroundColor(color: Background_Color)
        setupUI()
        updateEmptyUI()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        (navigationController as? NavigationViewController)?.navigationDelegate = self
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if tableView.firstShowFlashScrollIndicators {
            tableView.flashScrollIndicatorsIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        (navigationController as? NavigationViewController)?.navigationDelegate = nil
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateEmptyUI()
    }

    private var hasUnsavedChanges: Bool {
        viewModel.switchDatas.contains { viewModel.hasSaveChanges($0) }
    }

    private func setupUI() {
        bottomView.isHidden = !editable
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(56) + (isIPad ? 0 : kSafeAreaBottomHeight))
        }

        bottomView.addSubview(addSwitchButton)
        addSwitchButton.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(56))
        }

        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.top.equalTo(view.safeAreaLayoutGuide)
            make.left.right.equalToSuperview()
            if editable {
                make.bottom.equalTo(bottomView.snp.top)
            } else {
                make.bottom.equalToSuperview()
            }
        }
    }

    private func updateEmptyUI() {
        if viewModel.switchDatas.isEmpty {
            tableView.showEmptyDataView(
                frame: tableView.frame,
                title: "switch_empty_title".localizedString,
                tipText: "switch_empty_message".localizedString,
                position: .center,
                bottomMargin: SCRYFit(100)
            )
            tableView.emptyView?.backgroundColor = .clear
        } else {
            tableView.hideEmptyDataView()
        }
    }

    private func exitAction() {
        guard hasUnsavedChanges else {
            navigationController?.popViewController(animated: true)
            return
        }

        SRAlertView(
            title: "notification".localizedString,
            message: "profile_exiting_message".localizedString,
            actions: [
                SRAlertAction(title: "keep_edit".localizedString, style: .cancel),
                SRAlertAction(title: "EXIT".localizedString, actionHandler: { [weak self] _ in
                    self?.navigationController?.popViewController(animated: true)
                })
            ]
        ).show()
    }

    @objc private func addSwitchButtonAction() {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = viewModel.makeVirtualSwitch() else {
            SRAlertView(
                title: "notification".localizedString,
                message: "switchs_overrun_message".localizedString,
                actions: [SRAlertAction(title: "GOT_IT".localizedString)]
            ).show()
            return
        }
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }

        expandedSwitchIDs.insert(switchData.id)
        let index = max(viewModel.switchDatas.count - 1, 0)
        tableView.insertSections(IndexSet(integer: index), with: .top)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.tableView.scrollToRow(at: IndexPath(row: 0, section: index), at: .top, animated: true)
        }
        postSwitchDataChangedNotifications()
        updateEmptyUI()
    }

    private func toggleExpanded(id: String) {
        if expandedSwitchIDs.contains(id) {
            expandedSwitchIDs.remove(id)
        } else {
            expandedSwitchIDs.insert(id)
        }
        reloadSwitch(id: id, animation: .automatic)
    }

    private func startEnableUpdate(id: String, enabled: Bool) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard !pendingEnableSwitchIDs.contains(id),
              let switchData = switchData(id: id) else {
            reloadSwitch(id: id)
            return
        }

        guard viewModel.isRealSwitch(switchData) else {
            updateVirtualEnable(switchData, enabled: enabled)
            return
        }

        pendingEnableSwitchIDs.insert(id)
        reloadSwitch(id: id)

        if switchData.powerSwitchKind == .ac {
            sendACEnable(switchData, enabled: enabled)
        } else {
            startBatteryEnableFlow(switchData, enabled: enabled)
        }
    }

    private func updateVirtualEnable(_ switchData: PJEightKeySwitchData, enabled: Bool) {
        let oldValue = switchData.enabled
        viewModel.applyEnabled(enabled, to: switchData, markTxEnableSucceeded: false)
        guard viewModel.persist(switchData) else {
            viewModel.applyEnabled(oldValue, to: switchData, markTxEnableSucceeded: false)
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            reloadSwitch(id: switchData.id)
            return
        }
        postSwitchDataChangedNotifications()
        reloadSwitch(id: switchData.id)
    }

    private func startBatteryEnableFlow(_ switchData: PJEightKeySwitchData, enabled: Bool) {
        let flow = PJEightKeySwitchTxEnableFlow(
            presenter: self,
            switchData: switchData,
            enabled: enabled,
            onSucceeded: { [weak self, weak switchData] enabled in
                guard let self, let switchData else { return }
                self.viewModel.applyEnabled(enabled, to: switchData, markTxEnableSucceeded: true)
                guard self.viewModel.persist(switchData) else {
                    XWHUDManager.showErrorTipHUD("failed".localizedString)
                    return
                }
                self.postSwitchDataChangedNotifications()
                self.reloadSwitch(id: switchData.id)
            },
            onFinished: { [weak self] in
                guard let self else { return }
                self.pendingEnableSwitchIDs.remove(switchData.id)
                self.txEnableFlows.removeValue(forKey: switchData.id)
                self.reloadSwitch(id: switchData.id)
            }
        )
        txEnableFlows[switchData.id] = flow
        flow.start()
    }

    private func sendACEnable(_ switchData: PJEightKeySwitchData, enabled: Bool) {
        guard let node = switchData.proxyNode, node.isPowerSwitch else {
            finishACEnable(id: switchData.id, succeeded: false)
            return
        }

        MeshBatteryPowerSwitchTxEnableSender().sendTxEnable(enabled, to: node) { [weak self, weak switchData] succeeded in
            DispatchQueue.main.async {
                guard let self, let switchData else { return }
                if succeeded {
                    self.viewModel.applyEnabled(enabled, to: switchData, markTxEnableSucceeded: true)
                    if self.viewModel.persist(switchData) {
                        self.postSwitchDataChangedNotifications()
                    } else {
                        XWHUDManager.showErrorTipHUD("failed".localizedString)
                    }
                } else {
                    XWHUDManager.showTipHUD("failed".localizedString, isLineFeed: false)
                }
                self.finishACEnable(id: switchData.id, succeeded: succeeded)
            }
        }
    }

    private func finishACEnable(id: String, succeeded: Bool) {
        pendingEnableSwitchIDs.remove(id)
        reloadSwitch(id: id)
    }

    private func selectPanel(id: String) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = switchData(id: id) else { return }
        let vc = PJEightKeySwitchSelectPanelController(selectedPanelType: switchData.eightKeyPanelType)
        vc.selectPanelTypeCallback = { [weak self, weak switchData] type in
            guard let self, let switchData else { return }
            self.viewModel.updatePanelType(type, for: switchData)
            self.reloadSwitch(id: switchData.id)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func showGroups(id: String) {
        guard let switchData = switchData(id: id) else { return }
        let vc = SwitchSelectGroupsViewController(groups: switchData.bindGroups, selectGroups: switchData.bindGroups)
        vc.editable = false
        navigationController?.pushViewController(vc, animated: true)
    }

    private func selectScenes(id: String) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = switchData(id: id),
              switchData.eightKeyPanelType == .scene8Key else {
            return
        }
        if SRAlertView.isVisible() {
            return
        }
        let sceneDatas: [SwitchSceneData] = [
            .init(type: .sceneA, scene: switchData.sceneA),
            .init(type: .sceneB, scene: switchData.sceneB),
            .init(type: .sceneC, scene: switchData.sceneC),
            .init(type: .sceneD, scene: switchData.sceneD)
        ]
        let scenes = MeshNetworkManager.instance.scenes.filter { !DeviceEmerFireData.reservedSceneNumbers.contains($0.number) }
        let vc = SwitchSelectScenePageController(scenes: scenes, sceneDatas: sceneDatas)
        vc.scenesSelectCallback = { [weak self, weak switchData] sceneDatas in
            guard let self, let switchData else { return }
            self.viewModel.updateScenes(sceneDatas, for: switchData)
            self.reloadSwitch(id: switchData.id)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func moreSettings(id: String) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = switchData(id: id) else { return }
        let vc = PJEightKeySwitchMoreSettingsController(state: switchData.moreSettingsState)
        vc.settingsChanged = { [weak self, weak switchData] state in
            guard let self, let switchData else { return }
            self.viewModel.updateMoreSettings(state, for: switchData)
            self.reloadSwitch(id: switchData.id)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func deleteSwitch(id: String) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = switchData(id: id) else { return }
        guard viewModel.isRealSwitch(switchData) else {
            detachVirtualSwitch(switchData)
            return
        }

        SRAlertView(
            title: "notification".localizedString,
            message: "alert_delete_message".localizedString,
            actions: [
                .cancelAction,
                SRAlertAction(title: "confirm".localizedString, style: .destructive, actionHandler: { [weak self, weak switchData] _ in
                    guard let self, let switchData else { return }
                    self.detachRealSwitch(switchData)
                })
            ]
        ).show()
    }

    private func detachVirtualSwitch(_ switchData: PJEightKeySwitchData) {
        viewModel.detachCurrentGroup(from: switchData, requiresCleanupSync: false)
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        removeSwitchRow(id: switchData.id)
        postSwitchDataChangedNotifications()
        updateEmptyUI()
    }

    private func detachRealSwitch(_ switchData: PJEightKeySwitchData) {
        viewModel.detachCurrentGroup(from: switchData, requiresCleanupSync: true)
        pushPowerSwitchSync(switchData, mode: .deleteGroup)
    }

    private func saveSwitch(id: String) {
        guard editable else {
            XWHUDManager.showTipHUD("no_permission".localizedString + "！")
            return
        }
        guard let switchData = switchData(id: id),
              viewModel.hasSaveChanges(switchData) else {
            reloadSwitch(id: id)
            return
        }

        guard viewModel.isRealSwitch(switchData) else {
            saveVirtualSwitch(switchData)
            return
        }
        saveRealSwitch(switchData)
    }

    private func saveVirtualSwitch(_ switchData: PJEightKeySwitchData) {
        guard viewModel.persist(switchData) else {
            XWHUDManager.showErrorTipHUD("failed".localizedString)
            return
        }
        postSwitchDataChangedNotifications()
        reloadSwitch(id: switchData.id)
        XWHUDManager.showSuccessTipHUD("done!".localizedString)
    }

    private func saveRealSwitch(_ switchData: PJEightKeySwitchData) {
        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        let desiredHash = switchData.batteryPowerSwitchDesiredConfigHash(appKeyIndex: appKeyIndex)
        let needsConfigurationSync = needsBatteryPowerSwitchConfigurationSync(switchData, desiredHash: desiredHash)
        let needsLEDIndicatorSync = needsBatteryPowerSwitchLEDIndicatorSync(switchData)
        let needsTargetSync = switchData.needSyncData
        let needsOwnConfigurationSync = needsConfigurationSync || needsLEDIndicatorSync

        if needsConfigurationSync {
            switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        } else {
            switchData.desiredConfigHash = desiredHash
            if switchData.desiredConfigVersion == 0 {
                switchData.desiredConfigVersion = 1
            }
        }

        guard needsOwnConfigurationSync || needsTargetSync else {
            saveVirtualSwitch(switchData)
            return
        }

        if needsOwnConfigurationSync, switchData.requiresActivationBeforeOwnConfiguration {
            presentActivationBeforeSave(switchData)
        } else {
            pushPowerSwitchSync(switchData, mode: .save)
        }
    }

    private func presentActivationBeforeSave(_ switchData: PJEightKeySwitchData) {
        let flow = PJEightKeySwitchActivationFlow(
            presenter: self,
            switchData: switchData
        ) { [weak self, weak switchData] in
            guard let self, let switchData else { return }
            self.activationFlow = nil
            self.pushPowerSwitchSync(switchData, mode: .save)
        }
        activationFlow = flow
        flow.start()
    }

    private enum SyncMode {
        case save
        case deleteGroup
    }

    private func pushPowerSwitchSync(_ switchData: PJEightKeySwitchData, mode: SyncMode) {
        let vc = SyncDevicesViewController(type: .batteryPowerSwitch(switchData))
        vc.syncSuccessCallback = { [weak self, weak switchData] _ in
            guard let self, let switchData else { return }
            switchData.markBatteryPowerSwitchSyncSucceeded()
            guard self.viewModel.persist(switchData) else {
                XWHUDManager.showErrorTipHUD("failed".localizedString)
                return
            }
            self.handlePowerSwitchSyncFinished(id: switchData.id, mode: mode)
            XWHUDManager.showSuccessTipHUD("done!".localizedString)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                self?.navigationController?.popViewController(animated: true)
            }
        }
        vc.backActionCallback = { [weak self, weak switchData] result in
            guard let self, let switchData else { return }
            if mode == .deleteGroup {
                if let sourceSwitchData = self.viewModel.sourceSwitchData(id: switchData.id) {
                    self.viewModel.replaceLocalSwitchData(sourceSwitchData.copy())
                    self.reloadSwitch(id: sourceSwitchData.id)
                } else {
                    self.tableView.reloadData()
                }
                self.navigationController?.popViewController(animated: true)
                return
            }
            let failedOperationTypes = result.flatMap(\.failedOperationTypes)
            let successOperationTypes = result.flatMap(\.successOperationTypes)
            if self.containsBatteryPowerSwitchOwnConfiguration(failedOperationTypes) {
                switchData.markBatteryPowerSwitchSyncFailed(reason: "sync_failed".localizedString)
            } else if self.containsBatteryPowerSwitchOwnConfiguration(successOperationTypes) {
                switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: false)
            }
            if self.viewModel.persist(switchData) {
                self.handlePowerSwitchSyncFinished(id: switchData.id, mode: mode)
            } else {
                XWHUDManager.showErrorTipHUD("failed".localizedString)
            }
            self.navigationController?.popViewController(animated: true)
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    private func handlePowerSwitchSyncFinished(id: String, mode: SyncMode) {
        postSwitchDataChangedNotifications()
        switch mode {
        case .save:
            reloadSwitch(id: id)
        case .deleteGroup:
            removeSwitchRow(id: id)
            updateEmptyUI()
        }
    }

    private func needsBatteryPowerSwitchConfigurationSync(_ switchData: PJEightKeySwitchData, desiredHash: String) -> Bool {
        guard let sourceSwitchData = viewModel.sourceSwitchData(id: switchData.id) else {
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

    private func needsBatteryPowerSwitchLEDIndicatorSync(_ switchData: PJEightKeySwitchData) -> Bool {
        guard viewModel.isRealSwitch(switchData) else {
            return false
        }
        guard let sourceSwitchData = viewModel.sourceSwitchData(id: switchData.id) else {
            return switchData.needsBatteryPowerSwitchLEDIndicatorSync
        }
        return sourceSwitchData.moreSettingsState.ledIndicatorEnabled != switchData.moreSettingsState.ledIndicatorEnabled ||
            switchData.needsBatteryPowerSwitchLEDIndicatorSync
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

    private func postSwitchDataChangedNotifications() {
        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
    }

    private func switchData(id: String) -> PJEightKeySwitchData? {
        viewModel.switchDatas.first(where: { $0.id == id })
    }

    private func switchData(section: Int) -> PJEightKeySwitchData {
        viewModel.switchData(at: section)
    }

    private func rows(for switchData: PJEightKeySwitchData) -> [Row] {
        var rows: [Row] = [.panel, .group]
        if viewModel.showsSceneRow(for: switchData) {
            rows.append(.scene)
        }
        rows.append(contentsOf: [.moreSettings, .panelPreview])
        return rows
    }

    private func configureInfoCell(_ cell: CustomTableViewCell, row: Row, switchData: PJEightKeySwitchData) {
        cell.selectionStyle = .none
        cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        cell.lineView.backgroundColor = RGB(243, 243, 243, 0.7)
        cell.lineView.isHidden = false
        cell.cellStyle = .arrow
        cell.titleX = SCRXFrom(32)

        switch row {
        case .panel:
            cell.titleLabel.text = "panel".localizedString
            cell.contentLabel.text = switchData.eightKeyPanelType.title
        case .group:
            cell.titleLabel.text = "group".localizedString
            cell.contentLabel.text = viewModel.groupTitle(for: switchData)
        case .scene:
            cell.titleLabel.text = "scene".localizedString
            cell.contentLabel.text = viewModel.sceneTitle(for: switchData)
        case .moreSettings:
            cell.titleLabel.text = "neightkeyswitches_more_settings".localizedString
            cell.contentLabel.text = nil
        case .panelPreview:
            break
        }
    }

    private func reloadSwitch(id: String, animation: UITableView.RowAnimation = .none) {
        guard let index = viewModel.switchDatas.firstIndex(where: { $0.id == id }) else {
            tableView.reloadData()
            return
        }
        tableView.reloadSections(IndexSet(integer: index), with: animation)
    }

    private func removeSwitchRow(id: String) {
        guard let index = viewModel.switchDatas.firstIndex(where: { $0.id == id }) else {
            viewModel.removeLocalSwitchData(id: id)
            tableView.reloadData()
            return
        }
        expandedSwitchIDs.remove(id)
        pendingEnableSwitchIDs.remove(id)
        viewModel.removeLocalSwitchData(id: id)
        tableView.deleteSections(IndexSet(integer: index), with: .fade)
    }
}

extension GroupPowerSwitchesViewController: NavigationViewControllerDelegate {

    func navigationController(_ navigationController: NavigationViewController, backItemAction showViewController: UIViewController) {
        exitAction()
    }

    func navigationController(_ navigationController: NavigationViewController, gestureRecognizerShould gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard hasUnsavedChanges else {
            return true
        }
        exitAction()
        return false
    }
}

extension GroupPowerSwitchesViewController: UITableViewDataSource, UITableViewDelegate {

    func numberOfSections(in tableView: UITableView) -> Int {
        viewModel.switchDatas.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let switchData = switchData(section: section)
        return expandedSwitchIDs.contains(switchData.id) ? rows(for: switchData).count : 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let switchData = switchData(section: indexPath.section)
        let row = rows(for: switchData)[indexPath.row]

        switch row {
        case .panel, .group, .scene, .moreSettings:
            let cell = tableView.dequeueReusableCell(withIdentifier: "info", for: indexPath) as! CustomTableViewCell
            configureInfoCell(cell, row: row, switchData: switchData)
            return cell
        case .panelPreview:
            let cell = tableView.dequeueReusableCell(withIdentifier: "panel", for: indexPath) as! GroupPowerSwitchPanelCell
            let switchID = switchData.id
            cell.configure(
                definition: PJEightKeySwitchPanelDefinition.make(type: switchData.eightKeyPanelType),
                isEditable: editable,
                isSaveEnabled: viewModel.hasSaveChanges(switchData)
            )
            cell.deleteAction = { [weak self] in self?.deleteSwitch(id: switchID) }
            cell.saveAction = { [weak self] in self?.saveSwitch(id: switchID) }
            return cell
        }
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! GroupPowerSwitchHeaderView
        let switchData = switchData(section: section)
        let switchID = switchData.id
        headerView.configure(state: .init(
            name: switchData.name,
            detailText: viewModel.detailText(for: switchData),
            isEnabled: switchData.enabled,
            isExpanded: expandedSwitchIDs.contains(switchID),
            isEditable: editable,
            isEnablePending: pendingEnableSwitchIDs.contains(switchID)
        ))
        headerView.expandAction = { [weak self] in
            self?.toggleExpanded(id: switchID)
        }
        headerView.enableAction = { [weak self] enabled in
            self?.startEnableUpdate(id: switchID, enabled: enabled)
        }
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        SCRYFrom(64)
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let switchData = switchData(section: indexPath.section)
        let row = rows(for: switchData)[indexPath.row]
        switch row {
        case .panelPreview:
            return SCRYFrom(84) + SCRXFrom(288)
        case .panel, .group, .scene, .moreSettings:
            return SCRYFrom(44)
        }
    }

    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        0.01
    }

    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        UIView()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let switchData = switchData(section: indexPath.section)
        let row = rows(for: switchData)[indexPath.row]

        switch row {
        case .panel:
            selectPanel(id: switchData.id)
        case .group:
            showGroups(id: switchData.id)
        case .scene:
            selectScenes(id: switchData.id)
        case .moreSettings:
            moreSettings(id: switchData.id)
        case .panelPreview:
            break
        }
    }
}
