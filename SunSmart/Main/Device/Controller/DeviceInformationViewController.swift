//
//  DeviceInformationViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/3/29.
//

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
    private var sectionShowMap: [SectionType: Bool] = [:]
    private var deviceInfoModels: [DeviceInfoRow] = []
    
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
        
        setupDeviceInfoDataSource()
        
        sectionShowMap = [.deviceInfo: true, .group: true, .scene: true]
        
        setupTableView()
        setupTTL()
        setupGatewayTimeCoordinator()
        setupLightTimeCoordinator()
        requestGatewayTime()
        requestLightTime()
        getData()
        refreshRSSI()
        informationRequestsStarted = true
        requestInitialTTL()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        reloadDeviceInfoSection()
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let isNoLongerInNavigationStack = navigationController?.viewControllers.contains(where: { $0 === self }) == false
        if isMovingFromParent || isBeingDismissed || isNoLongerInNavigationStack
            || navigationController?.isBeingDismissed == true {
            gatewayTimeCoordinator?.finishPage()
            lightTimeCoordinator?.finishPage()
            ttlCoordinator?.detach()
            ttlAlert?.dismiss(animation: false)
            ttlProgressAlert?.dismiss(animation: false)
        }
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
        guard informationRequestsStarted, ttlInitialReadPending, !informationTimeReading, !informationFirmwareReading,
              ttlContext?.isVisible == true else { return }
        ttlInitialReadPending = false
        ttlCoordinator?.read()
    }

    private func updateTTLPresentation() {
        reloadDeviceInfoSection()
        guard let coordinator = ttlCoordinator else { return }
        navigationItem.rightBarButtonItem = coordinator.needsRetry && coordinator.phase == .idle
            && ttlService?.context.canEdit == true
            ? UIBarButtonItem(title: (coordinator.retryFailure == .localSave
                                ? "information_ttl_retry" : "information_ttl_retry_sync").localizedString,
                              style: .plain, target: self, action: #selector(retryTTL)) : nil
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
        guard let service = ttlService, let coordinator = ttlCoordinator,
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
        guard let coordinator = ttlCoordinator, coordinator.phase == .idle else { return }
        showTTLFailure(coordinator.retryFailure)
    }

    private func showTTLEditor() {
        guard let value = ttlCoordinator?.value, ttlService?.writeBlocker == nil else { return }
        // Keep validation in this alert. SRAlertView's generic input callback
        // dismisses first, so use an explicit non-closing Confirm action instead.
        let confirm = SRAlertAction(title: "COMFIRM".localizedString, closeAlert: false) { [weak self] _ in
            guard let self, let alert = self.ttlAlert else { return }
            guard let target = InformationTTLValue.parse(alert.textField.text ?? "") else {
                alert.messageLabel.text = "information_ttl_invalid".localizedString
                alert.messageLabel.textColor = Red_Color
                return
            }
            alert.dismiss { [weak self] in
                guard let self else { return }
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
        guard interactive else { return }
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
            self?.ttlAlert = nil
            self?.ttlInteractive = true
            self?.ttlCoordinator?.retry()
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
            guard let self else { return }
            switch state {
            case .disconnected:
                gatewayIsDisconnected = true
                reloadDeviceInfoSection()
            case .reading:
                gatewayIsDisconnected = false
                reloadDeviceInfoSection()
            case .succeeded(let snapshot):
                gatewayIsDisconnected = false
                gatewayTimeSnapshot = snapshot
                reloadDeviceInfoSection()
            case .failed:
                gatewayIsDisconnected = false
                reloadDeviceInfoSection()
            }
            if case .reading = state { informationTimeReading = true } else { informationTimeReading = false }
            requestInitialTTL()
        }
        gatewayTimeCoordinator = coordinator
    }

    private func requestGatewayTime() {
        guard ttlCoordinator?.phase == .idle || ttlCoordinator == nil else { return }
        _ = gatewayTimeCoordinator?.read()
    }

    private func setupLightTimeCoordinator() {
        guard let lightTimeContext, node.timeModel != nil else { return }
        let coordinator = LightTimeInformationCoordinator(
            node: node,
            context: lightTimeContext
        )
        coordinator.onReadState = { [weak self] state in
            guard let self else { return }
            switch state {
            case .disconnected:
                lightTimeSnapshot = nil
                reloadDeviceInfoSection()
            case .reading:
                reloadDeviceInfoSection()
            case .succeeded(let snapshot):
                lightTimeSnapshot = snapshot
                reloadDeviceInfoSection()
            case .failed:
                reloadDeviceInfoSection()
            }
            if case .reading = state { informationTimeReading = true } else { informationTimeReading = false }
            requestInitialTTL()
        }
        lightTimeCoordinator = coordinator
    }

    private func requestLightTime() {
        guard ttlCoordinator?.phase == .idle || ttlCoordinator == nil else { return }
        _ = lightTimeCoordinator?.read()
    }
    
    private func getData() {
        
        if let model = node.firmwareUpdateServerModel {
            informationFirmwareReading = true
            let cacheVersion = node.firmwareVersion
            MeshAPI.sendMessage(message: FirmwareUpdateInformationGet(firstIndex: 0, entriesLimit: 1), model: model) {[weak self] response in
                guard let self = self else { return }
                if self.node.firmwareVersion != cacheVersion {
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                }
                self.setupDeviceInfoDataSource()
                self.tableView.reloadSections(IndexSet(integer: 0), with: .none)
                self.informationFirmwareReading = false
                self.requestInitialTTL()
            }
        }
    }
    
    private func refreshRSSI() {
        var didRefreshCurrentNodeRSSI = false
        MeshLibManager.manager.refreshNodesRSSI(withWaitFor: 5, nodeScan: {[weak self] data in
            guard let self = self else { return }
            guard data.node.primaryUnicastAddress == self.node.primaryUnicastAddress else {
                return
            }
            didRefreshCurrentNodeRSSI = true
            self.node.rssi = data.rssi.intValue
            MeshLibManager.manager.stopRefreshNodesRSSI()
            self.reloadDeviceInfoSection()
        }, finished: {[weak self] nodes in
            guard let self = self else { return }
            guard !didRefreshCurrentNodeRSSI else {
                return
            }
            if !nodes.contains(where: { $0.node.primaryUnicastAddress == self.node.primaryUnicastAddress }) {
                self.node.rssi = nil
                self.reloadDeviceInfoSection()
            }
        })
    }
    
    private func reloadDeviceInfoSection() {
        setupDeviceInfoDataSource()
        if let section = sections.firstIndex(of: .deviceInfo) {
            CATransaction.setDisableActions(true)
            tableView.reloadSections(IndexSet(integer: section), with: .none)
            CATransaction.commit()
        }
    }
    
    /// 设备数据
    private func setupDeviceInfoDataSource() {
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
        deviceInfoModels = rows
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
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionType = sections[section]
        switch sectionType {
        case .deviceInfo:
            let isShow = sectionShowMap[sectionType] ?? false
            return isShow ? deviceInfoModels.count : 0
        case .scene:
            guard sceneTextOverride == nil else {
                return 0
            }
            let sceneCount = node.scenes.count
            let isShow = sectionShowMap[sectionType] ?? false
            return (isShow && sceneCount > 0) ? sceneCount : 0
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let sectionType = sections[section]
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceLightInfoSectionView
        headerView.contentLabel.isHidden = true
        headerView.showImageView.isHidden = true
        switch sectionType {
        case .deviceInfo:
            headerView.titleLabel.text = "device".localizedString
            headerView.showImageView.isHidden = false
            let isShow = sectionShowMap[sectionType] ?? false
            headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
        case .group:
            headerView.titleLabel.text = "group".localizedString
            headerView.contentLabel.isHidden = false
            headerView.contentLabel.text = groupTextOverride ?? node.group?.name ?? emptyGroupText
        case .scene:
            headerView.titleLabel.text = "scene".localizedString
            if let sceneTextOverride {
                headerView.contentLabel.isHidden = false
                headerView.contentLabel.text = sceneTextOverride
            } else if node.scenes.count > 0 {
                headerView.showImageView.isHidden = false
                let isShow = sectionShowMap[sectionType] ?? false
                headerView.showImageView.image = UIImage(named: isShow ? "arrow_up": "arrow_down")
            }else {
                headerView.contentLabel.isHidden = false
                headerView.contentLabel.text = "device_not_added_scene".localizedString
            }
        }
        headerView.sectionViewClickCallback = {[weak self] in
            if sectionType == .deviceInfo || sectionType == .scene {
                let isShow = self?.sectionShowMap[sectionType] ?? false
                self?.sectionShowMap[sectionType] = !isShow
                self?.tableView.reloadSections(IndexSet(integer: section), with: .automatic)
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
        
        let sectionType = sections[indexPath.section]
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! CustomTableViewCell
        cell.selectionStyle = .none
        if sectionType == .deviceInfo {
            let model = deviceInfoModels[indexPath.row].model
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
//            cell.lineView.isHidden = indexPath.row != deviceInfoModels.count - 1
            //                tableView.numberOfRows(inSection: indexPath.section) - 1 != indexPath.row
        }else {
            guard sceneTextOverride == nil else {
                return cell
            }
            let scene = node.scenes[indexPath.row]
            cell.cellStyle = .none
            cell.titleLabel.text = scene.name
            cell.titleLabel.textColor = TextBlack_Color
            cell.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
            //                Font_Medium_Size(SCRYFrom(14))
            if let sceneData = node.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number }) {
                if sceneData.lightness == 0 {
                    cell.contentLabel.text = "off".localizedString
                }else {
                    if node.singleDeviceDisplaySupportCct {
                        let cct100 = node.getEffectiveTemperature100(temperature: UInt16(sceneData.cct))
                        cell.contentLabel.text = "\("brightness".localizedString)-\(Node.getLightness100(lightness: sceneData.lightness))%.\("cct".localizedString)-\(cct100)%"
                    }else {
                        cell.contentLabel.text = "\("brightness".localizedString)-\(Node.getLightness100(lightness: sceneData.lightness))%."
                    }
                }
            }
            //                "Brightness-20%."
            cell.contentLabel.textColor = RGB(13, 14, 28, 0.5)
            cell.contentLabel.font = UIFont.systemFont(ofSize: SCRYFrom(14), weight: .light)
//            cell.lineView.isHidden = false
        }
        cell.titleX = SCRXFrom(32)
        cell.lineView.backgroundColor = Line_Color
        //            cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let sectionType = sections[indexPath.section]
        guard sectionType == .deviceInfo,
              deviceInfoModels.indices.contains(indexPath.row) else {
            return
        }
        let row = deviceInfoModels[indexPath.row]
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
    
    /// 组类型
    enum SectionType {
        /// 设备信息
        case deviceInfo
        /// 组
        case group
        /// 场景
        case scene
    }
    
}
