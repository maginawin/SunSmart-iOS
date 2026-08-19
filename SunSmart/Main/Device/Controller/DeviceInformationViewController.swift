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
        lightTimeContext: LightTimeInformationContext? = nil
    ) {
        self.node = node
        self.emptyGroupText = emptyGroupText ?? "device_not_added_group".localizedString
        self.groupTextOverride = groupTextOverride
        self.sceneTextOverride = sceneTextOverride
        self.nameOverride = nameOverride
        self.deviceInfoDisplayMode = showsFullDeviceInfo ? .full : .standard
        self.gatewayContext = gatewayContext
        self.lightTimeContext = lightTimeContext
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
        setupGatewayTimeCoordinator()
        setupLightTimeCoordinator()
        requestGatewayTime()
        requestLightTime()
        getData()
        refreshRSSI()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if self.tableView.firstShowFlashScrollIndicators {
            self.tableView.flashScrollIndicatorsIfNeeded()
        }
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        let isNoLongerInNavigationStack = navigationController?.viewControllers.contains(where: { $0 === self }) == false
        if isMovingFromParent || isBeingDismissed || isNoLongerInNavigationStack {
            gatewayTimeCoordinator?.finishPage()
            lightTimeCoordinator?.finishPage()
        }
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
                XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
            }
        }
        coordinator.onCloudFailure = {
            XWHUDManager.showErrorTipHUD("site_entry_sync_failed_to_update_server".localizedString)
        }
        gatewayTimeCoordinator = coordinator
    }

    private func requestGatewayTime() {
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
                XWHUDManager.showErrorTipHUD("device_offline_message".localizedString)
            case .reading:
                reloadDeviceInfoSection()
            case .succeeded(let snapshot):
                lightTimeSnapshot = snapshot
                reloadDeviceInfoSection()
            case .failed:
                reloadDeviceInfoSection()
                XWHUDManager.showErrorTipHUD("failed_to_retrieve_data".localizedString)
            }
        }
        lightTimeCoordinator = coordinator
    }

    private func requestLightTime() {
        _ = lightTimeCoordinator?.read()
    }
    
    private func getData() {
        
        if let model = node.firmwareUpdateServerModel {
            let cacheVersion = node.firmwareVersion
            MeshAPI.sendMessage(message: FirmwareUpdateInformationGet(firstIndex: 0, entriesLimit: 1), model: model) {[weak self] response in
                guard let self = self else { return }
                if self.node.firmwareVersion != cacheVersion {
                    NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                }
                self.setupDeviceInfoDataSource()
                self.tableView.reloadSections(IndexSet(integer: 0), with: .none)
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
        
        let sectionType = sections[indexPath.section]
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
