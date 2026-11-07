//
//  DeviceInformationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/29.
//

import Foundation

enum DeviceInformationSection: Hashable {
    case deviceInfo, group, scene
}

struct DeviceInformationSceneRow: Equatable {
    let name: String
    let content: String?
}

/// Keep count, header and cell reads on one presentation even when the SDK
/// changes Scene membership between UITableView data-source calls.
struct DeviceInformationSnapshot<DeviceRow> {
    let sections: [DeviceInformationSection]
    let expandedSections: Set<DeviceInformationSection>
    let deviceRows: [DeviceRow]
    let groupText: String
    let sceneRows: [DeviceInformationSceneRow]
    let sceneTextOverride: String?

    func section(at index: Int) -> DeviceInformationSection? {
        sections.indices.contains(index) ? sections[index] : nil
    }

    func rowCount(in section: Int) -> Int {
        guard let kind = self.section(at: section), expandedSections.contains(kind) else { return 0 }
        switch kind {
        case .deviceInfo: return deviceRows.count
        case .group: return 0
        case .scene: return sceneTextOverride == nil ? sceneRows.count : 0
        }
    }
}

/// A cancelled pop may resume pending firmware/TTL work, but must not revive
/// the RSSI callbacks belonging to the previous appearance.
final class DeviceInformationPageSession {
    private(set) var appearanceID: UUID?
    private(set) var isFinished = false
    var isVisible: Bool { appearanceID != nil && !isFinished }

    func appear() {
        guard !isFinished, appearanceID == nil else { return }
        appearanceID = UUID()
    }

    func disappear() { appearanceID = nil }

    func finish() {
        disappear()
        isFinished = true
    }

    func accepts(_ id: UUID) -> Bool { isVisible && appearanceID == id }
}

#if canImport(UIKit)
import UIKit
import NordicSigMeshSDK

class DeviceInformationViewController: UIViewController {

    private struct DeviceInfoRow {
        enum ID {
            case name, mac, pid, address, versionIdentifier
            case model, deviceType, firmware, signalStrength
            case ttl
            case dateTime, timeZone
        }

        let id: ID
        let model: CustomCellModel
    }

    private enum DeviceInfoDisplayMode {
        case standard
        case full
    }

    private var tableView: UITableView!
    
    private var sections: [SectionType] = [.deviceInfo, .group, .scene]
    private var expandedSections: Set<SectionType> = [.deviceInfo, .scene]
    private var snapshot = DeviceInformationSnapshot<DeviceInfoRow>(
        sections: [], expandedSections: [], deviceRows: [], groupText: "",
        sceneRows: [], sceneTextOverride: nil
    )
    private let pageSession = DeviceInformationPageSession()
    
    let node: Node
    private let emptyGroupText: String
    private let groupTextOverride: String?
    private let sceneTextOverride: String?
    private let nameOverride: String?
    private let deviceInfoDisplayMode: DeviceInfoDisplayMode
    private let gatewayContext: GatewayInformationContext?
    private var gatewayTimeCoordinator: GatewayTimeInformationCoordinator?
    private var gatewayTimeSnapshot: GatewayTimeInformationSnapshot?
    private var gatewayIsDisconnected = false
    private let lightTimeContext: LightTimeInformationContext?
    private var lightTimeCoordinator: LightTimeInformationCoordinator?
    private var lightTimeSnapshot: GatewayTimeInformationSnapshot?
    private let ttlContext: InformationTTLContext?
    private var ttlService: InformationTTLMeshService?
    private var ttlCoordinator: InformationTTLCoordinator?
    private var ttlAlert: SRAlertView?
    private var ttlProgressAlert: SRAlertView?
    private var ttlInteractive = false
    private var ttlEditAfterRead = false
    private var ttlInitialReadPending = true
    private var informationTimeReading = false
    private var informationFirmwareReading = false
    private var informationRequestsStarted = false
    
    init(
        node: Node,
        emptyGroupText: String? = nil,
        showsGroupSection: Bool = true,
        showsSceneSection: Bool = true,
        groupTextOverride: String? = nil,
        sceneTextOverride: String? = nil,
        nameOverride: String? = nil,
        showsFullDeviceInfo: Bool = false,
        gatewayContext: GatewayInformationContext? = nil,
        lightTimeContext: LightTimeInformationContext? = nil,
        ttlContext: InformationTTLContext? = nil
    ) {
        self.node = node
        self.emptyGroupText = emptyGroupText ?? "device_not_added_group".localizedString
        self.groupTextOverride = groupTextOverride
        self.sceneTextOverride = sceneTextOverride
        self.nameOverride = nameOverride
        self.deviceInfoDisplayMode = showsFullDeviceInfo ? .full : .standard
        self.gatewayContext = gatewayContext
        self.lightTimeContext = lightTimeContext
        self.ttlContext = ttlContext ?? gatewayContext.map(InformationTTLContext.gateway)
        self.sections = [.deviceInfo]
        if showsGroupSection {
            self.sections.append(.group)
        }
        if showsSceneSection {
            self.sections.append(.scene)
        }
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "information".localizedString
        view.backgroundColor = Background_Color
        
        setupTableView()
        setupTTL()
        setupGatewayTimeCoordinator()
        setupLightTimeCoordinator()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        pageSession.appear()
        reloadInformation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard pageSession.isVisible else { return }
        if !informationRequestsStarted {
            requestGatewayTime()
            requestLightTime()
            getData()
            informationRequestsStarted = true
        }
        refreshRSSI()
        requestInitialTTL()
        updateTTLPresentation()
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        // Invalidate before any dismissal/completion can reenter this page.
        pageSession.disappear()
        dismissTTLAlerts()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let isNoLongerInNavigationStack = !(navigationController?.viewControllers.contains(where: { $0 === self }) ?? false)
        if isMovingFromParent || isBeingDismissed || isNoLongerInNavigationStack
            || navigationController?.isBeingDismissed == true {
            pageSession.finish()
            gatewayTimeCoordinator?.finishPage()
            lightTimeCoordinator?.finishPage()
            ttlCoordinator?.detach()
            dismissTTLAlerts()
        }
    }

    private func dismissTTLAlerts() {
        ttlAlert?.dismiss(animation: false)
        ttlAlert = nil
        ttlProgressAlert?.dismiss(animation: false)
        ttlProgressAlert = nil
    }

    private func setupTTL() {
        guard let ttlContext, let service = InformationTTLMeshService(node: node, context: ttlContext) else { return }
        ttlService = service
        let coordinator = InformationTTLCoordinator(service: service)
        ttlCoordinator = coordinator
        coordinator.onChange = { [weak self] in self?.updateTTLPresentation() }
        coordinator.onResult = { [weak self] result in self?.handleTTLResult(result) }
    }

    private func requestInitialTTL() {
        guard pageSession.isVisible, informationRequestsStarted, ttlInitialReadPending, !informationTimeReading, !informationFirmwareReading,
              ttlContext?.isVisible == true else { return }
        ttlInitialReadPending = false
        ttlCoordinator?.read()
    }

    private func updateTTLPresentation() {
        guard pageSession.isVisible else { return }
        reloadInformation()
        guard let coordinator = ttlCoordinator else { return }
        navigationItem.rightBarButtonItem = coordinator.needsRetry && coordinator.phase == .idle
            && ttlService?.context.canEdit == true
            ? UIBarButtonItem(title: (coordinator.retryFailure == .localSave
                                ? "information_ttl_retry" : "information_ttl_retry_sync").localizedString,
                              style: .plain, target: self, action: #selector(retryTTL)).withoutSharedBackground() : nil
        guard ttlInteractive, coordinator.phase != .idle else {
            ttlProgressAlert?.dismiss(animation: false)
            ttlProgressAlert = nil
            return
        }
        let key: String
        switch coordinator.phase {
        case .reading: key = "information_ttl_reading"
        case .writing: key = "information_ttl_updating"
        case .verifying: key = "information_ttl_verifying"
        case .synchronizing: key = "information_ttl_syncing"
        case .idle: return
        }
        if let alert = ttlProgressAlert {
            alert.messageLabel.text = key.localizedString
        } else {
            let alert = SRAlertView(title: "information_ttl_title".localizedString,
                                    message: key.localizedString,
                                    stateImage: UIImage(named: "site_entry_sync_loading"),
                                    loadingState: true, tapBackgroundHide: false)
            ttlProgressAlert = alert
            alert.show()
        }
    }

    private func selectTTL() {
        guard pageSession.isVisible, let service = ttlService, let coordinator = ttlCoordinator,
              service.context.isVisible, coordinator.phase == .idle,
              !informationTimeReading, !informationFirmwareReading else { return }
        if let blocker = service.writeBlocker {
            showTTLFailure(blocker)
            return
        }
        if coordinator.value == nil {
            ttlInteractive = true
            ttlEditAfterRead = true
            coordinator.read()
        } else {
            showTTLEditor()
        }
    }

    @objc private func retryTTL() {
        guard pageSession.isVisible, let coordinator = ttlCoordinator, coordinator.phase == .idle else { return }
        showTTLFailure(coordinator.retryFailure)
    }

    private func showTTLEditor() {
        guard let appearanceID = pageSession.appearanceID,
              let value = ttlCoordinator?.value, ttlService?.writeBlocker == nil else { return }
        // Keep validation in this alert. SRAlertView's generic input callback
        // dismisses first, so use an explicit non-closing Confirm action instead.
        let confirm = SRAlertAction(title: "COMFIRM".localizedString, closeAlert: false) { [weak self] _ in
            guard let self, self.pageSession.accepts(appearanceID), let alert = self.ttlAlert else { return }
            guard let target = InformationTTLValue.parse(alert.textField.text ?? "") else {
                alert.messageLabel.text = "information_ttl_invalid".localizedString
                alert.messageLabel.textColor = Red_Color
                return
            }
            alert.dismiss { [weak self] in
                guard let self, self.pageSession.accepts(appearanceID) else { return }
                self.ttlAlert = nil
                self.ttlInteractive = true
                self.ttlCoordinator?.update(target)
            }
        }
        let alert = SRAlertView(
            title: "information_ttl_title".localizedString,
            message: "information_ttl_hint".localizedString,
            inputText: String(value),
            inputFieldStyle: .init(keyboardType: .numberPad, maxInputLength: Int.max, textAlignment: .center, showClear: true),
            showPrompt: false, actions: [.cancelAction, confirm],
            textValueChangedBack: { text, _ in
                InformationTTLValue.parse(text) == nil ? "information_ttl_invalid".localizedString : nil
            }, inputDoneBack: nil
        )
        ttlAlert = alert
        alert.show()
    }

    private func handleTTLResult(_ result: InformationTTLResult) {
        let interactive = ttlInteractive
        let editAfterRead = ttlEditAfterRead
        ttlInteractive = false
        ttlEditAfterRead = false
        guard pageSession.isVisible, interactive else { return }
        switch result {
        case .read:
            if editAfterRead { showTTLEditor() }
        case .updated:
            XWHUDManager.showSuccessTipHUD("information_ttl_success".localizedString)
        case .unchanged:
            break
        case .failed(let failure):
            showTTLFailure(failure)
        }
    }

    private func showTTLFailure(_ failure: InformationTTLFailure) {
        guard let appearanceID = pageSession.appearanceID else { return }
        let key: String
        switch failure {
        case .permission: key = "no_permission"
        case .disconnected: key = "information_ttl_disconnected"
        case .unavailable: key = "information_ttl_unavailable"
        case .readFailed: key = "information_ttl_read_failed"
        case .unconfirmed: key = "information_ttl_unconfirmed"
        case .mismatch: key = "information_ttl_mismatch"
        case .localSave: key = "information_ttl_local_failed"
        case .cloudSync: key = "information_ttl_cloud_failed"
        }
        guard ttlCoordinator?.needsRetry == true, ttlCoordinator?.value != nil,
              failure == .localSave || failure == .cloudSync else {
            XWHUDManager.showTipHUD(key.localizedString, isLineFeed: true)
            return
        }
        let retry = SRAlertAction(title: "information_ttl_retry".localizedString, performsActionAfterDismiss: true) { [weak self] _ in
            guard let self, self.pageSession.accepts(appearanceID) else { return }
            self.ttlAlert = nil
            self.ttlInteractive = true
            self.ttlCoordinator?.retry()
        }
        let alert = SRAlertView(title: "information_ttl_title".localizedString,
                                message: key.localizedString, actions: [.cancelAction, retry])
        ttlAlert = alert
        alert.show()
    }

    private func setupGatewayTimeCoordinator() {
        guard let gatewayContext else { return }
        let coordinator = GatewayTimeInformationCoordinator(context: gatewayContext)
        coordinator.onReadState = { [weak self] state in
            guard let self, !self.pageSession.isFinished else { return }
            switch state {
            case .disconnected:
                gatewayIsDisconnected = true
                reloadInformation()
            case .reading:
                gatewayIsDisconnected = false
                reloadInformation()
            case .succeeded(let snapshot):
                gatewayIsDisconnected = false
                gatewayTimeSnapshot = snapshot
                reloadInformation()
            case .failed:
                gatewayIsDisconnected = false
                reloadInformation()
            }
            if case .reading = state { informationTimeReading = true } else { informationTimeReading = false }
            requestInitialTTL()
        }
        gatewayTimeCoordinator = coordinator
    }

    private func requestGatewayTime() {
        guard pageSession.isVisible,
              ttlCoordinator?.phase == .idle || ttlCoordinator == nil else { return }
        _ = gatewayTimeCoordinator?.read()
    }

    private func setupLightTimeCoordinator() {
        guard let lightTimeContext, node.timeModel != nil else { return }
        let coordinator = LightTimeInformationCoordinator(
            node: node,
            context: lightTimeContext
        )
        coordinator.onReadState = { [weak self] state in
            guard let self, !self.pageSession.isFinished else { return }
            switch state {
            case .disconnected:
                lightTimeSnapshot = nil
                reloadInformation()
            case .reading:
                reloadInformation()
            case .succeeded(let snapshot):
                lightTimeSnapshot = snapshot
                reloadInformation()
            case .failed:
                reloadInformation()
            }
            if case .reading = state { informationTimeReading = true } else { informationTimeReading = false }
            requestInitialTTL()
        }
        lightTimeCoordinator = coordinator
    }

    private func requestLightTime() {
        guard pageSession.isVisible,
              ttlCoordinator?.phase == .idle || ttlCoordinator == nil else { return }
        _ = lightTimeCoordinator?.read()
    }
    
    private func getData() {
        guard pageSession.isVisible else { return }
        if let model = node.firmwareUpdateServerModel {
            informationFirmwareReading = true
            let cacheVersion = node.firmwareVersion
            MeshAPI.sendMessage(message: FirmwareUpdateInformationGet(firstIndex: 0, entriesLimit: 1), model: model) { [weak self] _ in
                guard let self, !self.pageSession.isFinished, self.informationFirmwareReading else { return }
                // Complete bookkeeping even while temporarily hidden. A cancelled
                // pop resumes this same request instead of sending a duplicate.
                self.informationFirmwareReading = false
                if self.node.firmwareVersion != cacheVersion {
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                }
                self.reloadInformation()
                self.requestInitialTTL()
            }
        }
    }

    private func refreshRSSI() {
        guard let appearanceID = pageSession.appearanceID else { return }
        var didRefreshCurrentNodeRSSI = false
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5, nodeScan: { [weak self] data in
            guard let self, self.pageSession.accepts(appearanceID), data.node === self.node else { return }
            didRefreshCurrentNodeRSSI = true
            self.node.rssi = data.rssi.intValue
            // stop invokes finished synchronously. Mark the sample accepted first.
            MeshLibManager.manager.stopRefreshNodesRSSI()
            self.reloadInformation()
        }, finished: { [weak self] nodes in
            guard let self, self.pageSession.accepts(appearanceID), !didRefreshCurrentNodeRSSI else { return }
            if !nodes.contains(where: { $0.node === self.node }) {
                self.node.rssi = nil
                self.reloadInformation()
            }
        })
    }

    private func reloadInformation() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard pageSession.isVisible, let tableView else { return }
        let sceneRows: [DeviceInformationSceneRow] = sceneTextOverride == nil && sections.contains(.scene)
            ? node.scenes.map { scene in
                var content: String?
                if let data = node.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                    if data.lightness == 0 {
                        content = "off".localizedString
                    } else {
                        var text = "\("brightness".localizedString)-\(Node.getLightness100(lightness: data.lightness))%."
                        if node.singleDeviceDisplaySupportCct {
                            let cct = node.getEffectiveTemperature100(temperature: UInt16(data.cct))
                            text += "\("cct".localizedString)-\(cct)%"
                        }
                        content = text
                    }
                }
                return DeviceInformationSceneRow(name: scene.name, content: content)
            } : []
        snapshot = DeviceInformationSnapshot(
            sections: sections, expandedSections: expandedSections,
            deviceRows: makeDeviceInfoRows(),
            groupText: groupTextOverride ?? node.group?.name ?? emptyGroupText,
            sceneRows: sceneRows, sceneTextOverride: sceneTextOverride
        )
        // Every section now comes from the same snapshot. A partial section
        // reload cannot account for concurrent changes to the Scene register.
        let offset = tableView.contentOffset
        UIView.performWithoutAnimation {
            tableView.reloadData()
            tableView.layoutIfNeeded()
            let minimumY = -tableView.adjustedContentInset.top
            let maximumY = max(minimumY, tableView.contentSize.height - tableView.bounds.height
                               + tableView.adjustedContentInset.bottom)
            tableView.setContentOffset(CGPoint(x: offset.x, y: min(max(offset.y, minimumY), maximumY)), animated: false)
        }
    }

    /// 设备数据
    private func makeDeviceInfoRows() -> [DeviceInfoRow] {
        var name = nameOverride ?? node.name ?? ""
        if nameOverride == nil,
           let group = node.group,
           SpaceViewController.currentSpace()?.displayDeviceNamePrefix ?? false {
            name = "\(group.name)-\(name)"
        }
        let nameModel = CustomCellModel(title: "name".localizedString, content: name, style: .none)
        
        let macModel = CustomCellModel(icon: UIImage(named: "copy"), title: "MAC", content: node.macAddressResult, style: .icon)
        
        let pidContent = node.productIdentifier.map { "0x\($0.hex)" } ?? "--"
        let pidModel = CustomCellModel(title: "PID".localizedString, content: pidContent, style: .none)
        
        let addressModel = CustomCellModel(title: "address".localizedString, content: "\(node.primaryUnicastAddress)", style: .none)
        
        let vidModel = CustomCellModel(title: "version_identifier".localizedString, content: node.versionIdentifier != nil ? "\(node.versionIdentifier!)" : "--", style: .none)
        
        let devModel = CustomCellModel(title: "model".localizedString, content: node.modelName ?? "--", style: .none)
        
        let typeName = node.categoryName
        let deviceTypeModel = CustomCellModel(title: "device_type".localizedString, content: typeName ?? "--", style: .none)
        
        let firmwareModel = CustomCellModel(title: "firmware".localizedString, content: node.firmwareVersion ?? "--", style: .none)
        
        let singleStrengthModel = CustomCellModel(title: "signal_strength".localizedString, content: node.rssi != nil ? "\(node.rssi!)dB" : "--", style: .none)
        
        var rows: [DeviceInfoRow]
        switch deviceInfoDisplayMode {
        case .full:
            rows = [
                DeviceInfoRow(id: .name, model: nameModel),
                DeviceInfoRow(id: .mac, model: macModel),
                DeviceInfoRow(id: .pid, model: pidModel),
                DeviceInfoRow(id: .address, model: addressModel),
                DeviceInfoRow(id: .versionIdentifier, model: vidModel),
                DeviceInfoRow(id: .model, model: devModel),
                DeviceInfoRow(id: .deviceType, model: deviceTypeModel),
                DeviceInfoRow(id: .firmware, model: firmwareModel),
                DeviceInfoRow(id: .signalStrength, model: singleStrengthModel)
            ]
        case .standard:
            rows = [
                DeviceInfoRow(id: .name, model: nameModel),
                DeviceInfoRow(id: .mac, model: macModel),
                DeviceInfoRow(id: .pid, model: pidModel),
                DeviceInfoRow(id: .address, model: addressModel),
                DeviceInfoRow(id: .versionIdentifier, model: vidModel),
                DeviceInfoRow(id: .model, model: devModel),
                DeviceInfoRow(id: .deviceType, model: deviceTypeModel),
                DeviceInfoRow(id: .firmware, model: firmwareModel),
                DeviceInfoRow(id: .signalStrength, model: singleStrengthModel)
            ]
        }

        if let service = ttlService, service.context.isVisible {
            let content = ttlInitialReadPending || ttlCoordinator?.phase == .reading
                ? "information_ttl_reading".localizedString
                : ttlCoordinator?.value.map(String.init) ?? "--"
            rows.append(DeviceInfoRow(id: .ttl, model: CustomCellModel(
                title: "information_ttl_title".localizedString, content: content,
                contentColor: service.context.canEdit ? TextBlack_Color : TextBlack_Color.withAlphaComponent(0.5),
                style: .arrow
            )))
        }

        if gatewayContext != nil {
            let dateTimeContent = gatewayIsDisconnected
                ? "gateway_not_connected".localizedString
                : gatewayTimeSnapshot?.dateTimeText ?? "--"
            let timeZoneContent = gatewayIsDisconnected
                ? "--"
                : gatewayTimeSnapshot?.timeZoneText ?? "--"
            rows.append(
                DeviceInfoRow(
                    id: .dateTime,
                    model: CustomCellModel(
                        title: "gateway_date_time".localizedString,
                        content: dateTimeContent,
                        style: .none
                    )
                )
            )
            rows.append(
                DeviceInfoRow(
                    id: .timeZone,
                    model: CustomCellModel(
                        title: "site_time_zone_row_title".localizedString,
                        content: timeZoneContent,
                        style: .none
                    )
                )
            )
        } else if lightTimeContext != nil {
            let dateTimeContent = node.timeModel == nil
                ? "not_supported".localizedString
                : lightTimeSnapshot?.dateTimeText ?? "--"
            let timeZoneContent = node.timeModel == nil
                ? "not_supported".localizedString
                : lightTimeSnapshot?.timeZoneText ?? "--"
            rows.append(
                DeviceInfoRow(
                    id: .dateTime,
                    model: CustomCellModel(
                        title: "gateway_date_time".localizedString,
                        content: dateTimeContent,
                        style: .none
                    )
                )
            )
            rows.append(
                DeviceInfoRow(
                    id: .timeZone,
                    model: CustomCellModel(
                        title: "site_time_zone_row_title".localizedString,
                        content: timeZoneContent,
                        style: .none
                    )
                )
            )
        }
        return rows
    }
    
    private func setupTableView() {
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = Background_Color
        tableView.register(CustomTableViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceLightInfoSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
//        tableView.showsVerticalScrollIndicator = false
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
    }
    


}

extension DeviceInformationViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        snapshot.sections.count
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        snapshot.rowCount(in: section)
    }

    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard let sectionType = snapshot.section(at: section) else { return nil }
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceLightInfoSectionView
        headerView.contentLabel.isHidden = true
        headerView.showImageView.isHidden = true
        switch sectionType {
        case .deviceInfo:
            headerView.titleLabel.text = "device".localizedString
            headerView.showImageView.isHidden = false
            let isShow = snapshot.expandedSections.contains(sectionType)
            headerView.showImageView.image = UIImage(named: isShow ? "arrow_up" : "arrow_down")
        case .group:
            headerView.titleLabel.text = "group".localizedString
            headerView.contentLabel.isHidden = false
            headerView.contentLabel.text = snapshot.groupText
        case .scene:
            headerView.titleLabel.text = "scene".localizedString
            if let text = snapshot.sceneTextOverride {
                headerView.contentLabel.isHidden = false
                headerView.contentLabel.text = text
            } else if !snapshot.sceneRows.isEmpty {
                headerView.showImageView.isHidden = false
                let isShow = snapshot.expandedSections.contains(sectionType)
                headerView.showImageView.image = UIImage(named: isShow ? "arrow_up" : "arrow_down")
            } else {
                headerView.contentLabel.isHidden = false
                headerView.contentLabel.text = "device_not_added_scene".localizedString
            }
        }
        let appearanceID = pageSession.appearanceID
        headerView.sectionViewClickCallback = { [weak self] in
            guard let self, let appearanceID, self.pageSession.accepts(appearanceID) else { return }
            if sectionType == .deviceInfo || sectionType == .scene {
                if !self.expandedSections.insert(sectionType).inserted {
                    self.expandedSections.remove(sectionType)
                }
                self.reloadInformation()
            }
        }
        return headerView
    }

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        
//        if sectionType == .deviceInfo && indexPath.row == 3 {
//            return SCRYFrom(60)
//        }
        return SCRYFrom(44)
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.selectionStyle = .none
        cell.titleLabel.text = nil
        cell.contentLabel.text = nil
        guard let sectionType = snapshot.section(at: indexPath.section),
              indexPath.row >= 0, indexPath.row < snapshot.rowCount(in: indexPath.section) else { return cell }
        if sectionType == .deviceInfo {
            let model = snapshot.deviceRows[indexPath.row].model
            cell.cellStyle = model.style
            cell.titleLabel.text = model.title
            cell.titleLabel.textColor = model.titleColor
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(15), weight: .light)
            cell.contentLabel.text = model.content
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            cell.contentLabel.textColor = model.contentColor
            cell.contentLabel.numberOfLines = 2
            
            if model.style == .icon {
                cell.iconImageView.image = model.icon
                cell.iconX = tableView.width - 30 - SCRXFrom(8)
                cell.arrowImageView.isHidden = true
            }
        } else if sectionType == .scene {
            let scene = snapshot.sceneRows[indexPath.row]
            cell.cellStyle = .none
            cell.titleLabel.text = scene.name
            cell.titleLabel.textColor = TextBlack_Color
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            cell.contentLabel.text = scene.content
            cell.contentLabel.textColor = RGB(13, 14, 28, 0.5)
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
        }
        cell.titleX = SCRXFrom(32)
        cell.lineView.backgroundColor = Line_Color
        //            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        guard pageSession.isVisible, snapshot.section(at: indexPath.section) == .deviceInfo,
              indexPath.row >= 0, indexPath.row < snapshot.rowCount(in: indexPath.section) else {
            return
        }
        let row = snapshot.deviceRows[indexPath.row]
        switch row.id {
        case .ttl:
            selectTTL()
        case .mac:
            if let content = row.model.content {
                let pasteboard = UIPasteboard.general
                pasteboard.string = content
                XWHUDManager.showTipHUD(inView: "copy_success".localizedString, isLineFeed: false)
            }
        case .dateTime, .timeZone:
            requestGatewayTime()
            requestLightTime()
        default:
            break
        }
    }
    
}

extension DeviceInformationViewController {
    typealias SectionType = DeviceInformationSection
}
#endif
