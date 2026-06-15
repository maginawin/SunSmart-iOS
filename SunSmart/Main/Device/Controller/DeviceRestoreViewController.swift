//
//  DeviceRestoreViewController.swift
//  SunSmart
//
//  Created by 袁科鸿 on 2024/11/22.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON

class DeviceRestoreViewController: UIViewController {

    private var navigationBackBtn: UIButton!
    /// header
    private var scanAnimationView: UIImageView!
    private var headerView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: RangeSlider!
    private var farLabel: UILabel!
    private var addDeviceToLabel: UILabel!
    private var addDeviceTargetBtn: UIButton!
    private var scanBtn: UIButton!
    /// 设备列表
    private var tableView: UITableView!
    /// 添加设备结果
    private var addResultView: DeviceAddResultView!
    /// 底部全选
    private var footerView: DeviceAddBottomView!
    
        
    
    /// 搜索设备定时器
    private var scanTimer: Timer?
    /// 恢复数据sections
    private var sections: [DeviceRestoreSection] = []
    /// 找到的设备list
//    private var scanDevices: [Node] = []
    /// 展示的设备list（信号值筛选）
    private var showSections: [DeviceRestoreSection] = []
    /// 选择筛选的信号值
    private var selectRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 添加设备页面状态
    private var state: State = .none
    /// identify中的设备
    private var identifyDevice: ProvisioningDevice?
    /// 设备恢复完成回调
    var deviceRestoreCallback: (([Node], Bool)->Void)?
    /// 已恢复的设备
    private var restoreNodes: [Node] = []
    private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
    private var batteryPowerSwitchRestoreConfigurations: [Address: PJEightKeySwitchData] = [:]
    private var failedBatteryPowerSwitchRestoreAddresses: Set<Address> = []
    private var failedBatteryPowerSwitchRestoreReasons: [Address: String] = [:]
    private var pendingBatteryPowerSwitchRestoreLinkGroupAddresses: Set<Address> = []
    private var successfulBatteryPowerSwitchRestoreLinkGroupAddresses: Set<Address> = []
    private var successfulBatteryPowerSwitchTargetSubscriptions: Set<BatteryPowerSwitchTargetSubscriptionKey> = []
    private var deferredRestoreSyncDatasByAddress: [Address: [NodeSyncData]] = [:]
    private let deferredRestoreTaskMaxRetryCount = 1
    private let deferredRestoreTaskRetryDelay: TimeInterval = 1.5
    
    
    /// 展示的设备恢复数据list
    private var showRestoreData: [DeviceRestoreData] {
        var restoreDatas: [DeviceRestoreData] = []
        showSections.forEach { section in
            restoreDatas.append(contentsOf: section.restoreDatas)
        }
        return restoreDatas
    }
    
    /// 所有的设备list
    private var allDevices: [ProvisioningDevice] {
        var devices: [ProvisioningDevice] = []
        sections.forEach { section in
            devices.append(contentsOf: section.restoreDatas.compactMap({ $0.unprovisionedDevice }))
        }
        return devices
    }
    /// 展示的设备list
    private var showDevices: [ProvisioningDevice] {
        var devices: [ProvisioningDevice] = []
        showSections.forEach { section in
            devices.append(contentsOf: section.restoreDatas.compactMap({ $0.unprovisionedDevice }))
        }
        return devices
    }
    
    private var rssiSortTimer: Timer?
    
    let site: SiteData
    let space: SpaceData?
    
    /// 恢复数据模式
    let restoreMode: RestoreMode
    /// 恢复设备入口过滤
    private let restoreFilter: RestoreFilter
    /// 自动化恢复（设置以后自动扫描恢复设备）
    var automationRestore: Bool = false
    /// 自动重试次数
    var automationRetryCount: Int = 1
    /// 是否在分配设备地址
    private var applyDeviceAddress: Bool = false

    private struct BatteryPowerSwitchTargetSubscriptionKey: Hashable {
        let nodeAddress: Address
        let groupAddress: Address
        let elementAddress: Address
        let modelIdentifier: UInt16
        let companyIdentifier: UInt16?
    }

    private enum RestoreSyncEvaluationPhase {
        case deviceSuccess
        case batchFinish
    }

    private struct DeferredRestoreTask {
        let operationType: DeviceOperationType
        let messageHandles: [MeshMessageHandle]
        let filteredSceneRecallCount: Int
    }

    private struct DeferredRestoreResponseKey: Hashable, CustomStringConvertible {
        let targetAddress: Address
        let requestOpCode: UInt32
        let responseOpCode: UInt32
        let elementAddress: Address?
        let modelIdentifier: UInt16?
        let companyIdentifier: UInt16?
        let vendorCode: [UInt8]?

        var description: String {
            var parts = [
                "target=\(String(format: "%04X", Int(targetAddress)))",
                "request=\(String(format: "%06X", requestOpCode))",
                "response=\(String(format: "%06X", responseOpCode))"
            ]
            if let elementAddress {
                parts.append("element=\(String(format: "%04X", Int(elementAddress)))")
            }
            if let modelIdentifier {
                parts.append("model=\(String(format: "%04X", modelIdentifier))")
            }
            if let companyIdentifier {
                parts.append("company=\(String(format: "%04X", companyIdentifier))")
            }
            if let vendorCode {
                parts.append("vendor=\(vendorCode.map { String(format: "%02X", $0) }.joined())")
            }
            return parts.joined(separator: ",")
        }
    }

    private final class DeferredRestoreResponseTracker {
        private var successfulHandleIds: Set<ObjectIdentifier> = []
        private var successfulResponseKeys: Set<DeferredRestoreResponseKey> = []

        var hasSuccessfulResponse: Bool {
            !successfulHandleIds.isEmpty || !successfulResponseKeys.isEmpty
        }

        func markSuccessful(handle: MeshMessageHandle, statusMessage: StaticMeshMessage) {
            successfulHandleIds.insert(ObjectIdentifier(handle))
            if let key = Self.responseKey(for: handle, statusMessage: statusMessage) {
                successfulResponseKeys.insert(key)
            }
        }

        func hasSuccessfulResponse(for handle: MeshMessageHandle) -> Bool {
            if successfulHandleIds.contains(ObjectIdentifier(handle)) {
                return true
            }
            guard let key = Self.requestKey(for: handle) else {
                return false
            }
            return successfulResponseKeys.contains(key)
        }

        func responseKeysDescription() -> String {
            successfulResponseKeys.map(\.description).sorted().joined(separator: ";")
        }

        private static func requestKey(for handle: MeshMessageHandle) -> DeferredRestoreResponseKey? {
            guard let responseOpCode = (handle.message as? AcknowledgedMeshMessage)?.responseOpCode else {
                return nil
            }
            return responseKey(
                targetAddress: handle.targetAddress,
                requestMessage: handle.message,
                responseOpCode: responseOpCode,
                statusMessage: nil
            )
        }

        private static func responseKey(
            for handle: MeshMessageHandle,
            statusMessage: StaticMeshMessage
        ) -> DeferredRestoreResponseKey? {
            responseKey(
                targetAddress: handle.targetAddress,
                requestMessage: handle.message,
                responseOpCode: statusMessage.opCode,
                statusMessage: statusMessage
            )
        }

        private static func responseKey(
            targetAddress: Address,
            requestMessage: MeshMessage,
            responseOpCode: UInt32,
            statusMessage: StaticMeshMessage?
        ) -> DeferredRestoreResponseKey? {
            var elementAddress: Address?
            var modelIdentifier: UInt16?
            var companyIdentifier: UInt16?
            var vendorCode: [UInt8]?

            if let publicationStatus = statusMessage as? ConfigModelPublicationStatus {
                elementAddress = publicationStatus.elementAddress
                modelIdentifier = publicationStatus.modelIdentifier
                companyIdentifier = publicationStatus.companyIdentifier
            } else if let request = requestMessage as? ConfigAnyModelMessage {
                elementAddress = request.elementAddress
                modelIdentifier = request.modelIdentifier
                companyIdentifier = request.companyIdentifier
            }

            if let vendorStatus = statusMessage as? SunricherVendorStatus {
                vendorCode = vendorStatus.status.code.code
            } else if requestMessage is SunricherVendorSet || requestMessage is SunricherVendorGet {
                vendorCode = vendorResponseCode(from: requestMessage.parameters)
            }

            return DeferredRestoreResponseKey(
                targetAddress: targetAddress,
                requestOpCode: requestMessage.opCode,
                responseOpCode: responseOpCode,
                elementAddress: elementAddress,
                modelIdentifier: modelIdentifier,
                companyIdentifier: companyIdentifier,
                vendorCode: vendorCode
            )
        }

        private static func vendorResponseCode(from parameters: Data?) -> [UInt8]? {
            guard let parameters,
                  let opCode = parameters.first else {
                return nil
            }

            let subcodedOpCodes: Set<UInt8> = [
                0x31, 0x36, 0x37, 0x39, 0x41, 0x42, 0x43, 0x44,
                0x46, 0x47, 0x48, 0x49, 0x4A, 0x4C, 0x4D
            ]
            if subcodedOpCodes.contains(opCode), parameters.count > 1 {
                return [opCode, parameters[1]]
            }
            return [opCode]
        }
    }

    init(site: SiteData, space: SpaceData?, restoreMode: RestoreMode, restoreFilter: RestoreFilter = .all) {
        self.site = site
        self.space = space
        self.restoreMode = restoreMode
        self.restoreFilter = restoreFilter
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = "Restore_Device_Data".localizedString
        
        view.backgroundColor = Background_Color
        self.isModalInPresentation = true
        
        
        navigationBackBtn = UIButton(normalImageName: "navigation_back", target: self, action: #selector(backClick))
        navigationItem.leftBarButtonItem = UIBarButtonItem(customView: navigationBackBtn)
        
        scanAnimationView = UIImageView(image: UIImage(named: "loading"))
        scanAnimationView.isHidden = true
        navigationItem.rightBarButtonItem = UIBarButtonItem(customView: scanAnimationView)
        
        setupUI()
        scanBtn.isSelected = true
        startScan()
        
        if space == nil, MeshNetworkManager.instance.meshNetwork?.uuid.uuidString != self.site.meshUUID || !MeshNetworkManager.instance.currentNetworkKey.isPrimary {
            DispatchQueue.global().async {[weak self] in
                guard let self = self else { return }
                MeshLibManager.manager.setMeshNetworkConnected(meshUUID: self.site.meshUUID, subNetworkId: self.site.meshNetworkId, connected: false)
            }
        }
        
        if automationRestore {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: {[weak self] in
                guard let self = self else { return }
                self.navigationController?.showAutomaticHud(messsage: "device_automatic_restore_message".localizedString) {[weak self] in
                    guard let self = self else { return }
                    self.navigationController?.hideAutomaticHud()
                    self.automationRestore = false
                    DispatchQueue.main.async {
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automationRestoreScanTimeout), object: nil)
                    }
                }
            })
        }
        
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if state == .scanning { // 退出页面/切换停止扫描
            stopScan()
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
    }

    
    deinit {
//        if state == .scanning {
//            stopScan()
//        }else {
            if state == .adding {
                MeshAPI.stopFastAddDevice(finishBack: nil)
            }
//            if self.restoreNodes.count > 0 {
        self.deviceRestoreCallback?(self.restoreNodes, self.automationRestore)
//            }
        self.restoreNodes.forEach {
            $0.batteryPowerSwitchRestoreTargetSubscriptionSnapshots = nil
        }
        // 关闭设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = false
//        }
    }
    
    @objc private func backClick() {
        if allDevices.contains(where: { $0.addState == .syncFailed }) {
            SRAlertView(title: "notification".localizedString, message: "devices_unrestored_message".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                self?.dismiss()
            })]).show()
        }else {
//            navigationController?.popViewController(animated: true)
            dismiss()
        }
    }
    
    private func dismiss() {
        if automationRestore {
            navigationController?.hideAutomaticHud()
        }
        if navigationController?.viewControllers.count ?? 0 > 1 {
            navigationController?.popViewController(animated: true)
        }else {
            dismiss(animated: true)
        }
    }
    
    
//    override func viewWillDisappear(_ animated: Bool) {
//        super.viewWillDisappear(animated)
//        
//        MeshAPI.stopScanRecoverDevices()
//    }

    private func shouldIncludeRestoreNode(_ node: Node) -> Bool {
        switch restoreFilter {
        case .all:
            return true
        case .gatewaysOnly:
            return node.deviceType == .gateway
        case .currentSpaceNonGateways:
            guard let space else {
                return false
            }
            return node.deviceType != .gateway && node.subNetworkId == space.meshNetworkId
        }
    }

    private func isNodeRestored(_ node: Node) -> Bool {
        restoreNodes.contains {
            $0.macAddress == node.macAddress || $0.macAddress?.toOldMacAddress() == node.macAddress
        }
    }

    private func pendingRestoreNodes(from nodes: [Node]) -> [Node] {
        nodes.filter { node in
            shouldIncludeRestoreNode(node) && !isNodeRestored(node)
        }
    }
    
    private func setupDataSource() {
        
        switch self.restoreMode {
        case .default:
            sections.removeAll()
            showSections.removeAll()
        case .specified(let nodes):
            sections.removeAll()
            /// 需要继续恢复的设备，如已恢复的设备将不展示
            let nextRestoreNodes = pendingRestoreNodes(from: nodes)
            nextRestoreNodes.forEach { node in
                let data = DeviceRestoreData(node: node)
                if let section = sections.first(where: { $0.group == node.group }) {
                    section.restoreDatas.append(data)
                }else {
                    let section = DeviceRestoreSection(group: node.group, restoreDatas: [data])
                    if node.group == nil {
                        sections.insert(section, at: 0)
                    }else {
                        sections.append(section)
                    }
                }
            }
            showSections = sections
        }
    }

    // MARK: - Scan
    private func startScan() {
        
        state = .scanning
        
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanAnimationView.isHidden = false
        scanAnimationView.layer.addRotationAnimation(duration: 1.5, repeatCount: .max, animationKey: "scan")
        startScanTimer()

//        scanDevices.removeAll()
//        showSections.removeAll()
        setupDataSource()
        tableView.reloadData()
        
        updateUIState()
        // 扫描中设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        if automationRestore { // 自动化恢复，开启30秒定时器
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automationRestoreScanTimeout), object: nil)
                self.perform(#selector(self.automationRestoreScanTimeout), with: nil, afterDelay: 30)
            }
        }
        
        MeshAPI.startScanRecoverDevices(duration: .max, scanDevice: {[weak self] unprovisionedDevice, node in
            guard let self = self, unprovisionedDevice.rssi.intValue >= self.filterRSSIRange.lowerBound else { return }

            guard self.shouldIncludeRestoreNode(node) else {
                return
            }
            
            if self.automationRestore {
                DispatchQueue.main.async {
                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.automationRestoreScanTimeout), object: nil)
                }
            }
            
            if unprovisionedDevice.rssi.intValue > self.filterRSSIRange.upperBound {
                unprovisionedDevice.rssi = NSNumber(value: self.filterRSSIRange.upperBound)
            }
            
            self.stopScanTimer()
            // 只有指定设备才显示
            if case .specified(let nodes) = self.restoreMode {
                let nextRestoreNodes = self.pendingRestoreNodes(from: nodes)
                if !nextRestoreNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    return
                }
            }
            
            unprovisionedDevice.selectedState = .selected
            unprovisionedDevice.addState = .scaning
            unprovisionedDevice.deviceName = node.name
            unprovisionedDevice.elementCount = Int(node.elementsCount)
            unprovisionedDevice.icon = node.iconName
            unprovisionedDevice.deviceType = node.deviceType
            
            var setSection: DeviceRestoreSection!
            // 是否刷新设备数据（找到同一个设备beacon包）
//            var refreshDevice: Bool = false
            
            if let sectionIndex = self.sections.firstIndex(where: { $0.group == node.group }) {
                let section = self.sections[sectionIndex]
                if let data = section.restoreDatas.first(where: { $0.node.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    data.unprovisionedDevice = unprovisionedDevice
//                    refreshDevice = true
                }else {
                    section.restoreDatas.append(DeviceRestoreData(node: node, unprovisionedDevice: unprovisionedDevice))
                }
                setSection = section
            }else {
                let data = DeviceRestoreData(node: node, unprovisionedDevice: unprovisionedDevice)
                let section = DeviceRestoreSection(group: node.group, restoreDatas: [data])
                if node.group == nil {
                    self.sections.insert(section, at: 0)
                }else {
                    self.sections.append(section)
                }
                setSection = section
            }
    
            
            // 当前设备信号值在筛选范围内可展示
            if self.selectRSSIRange.contains(unprovisionedDevice.rssi.intValue) {
                if !self.showSections.contains(where: { $0.group == setSection.group }) {
                    if setSection.group == nil {
                        self.showSections.insert(setSection, at: 0)
//                        self.tableView.insertSections(IndexSet(integer: 0), with: .none)
                    }else {
                        self.showSections.append(setSection)
//                        self.tableView.insertSections(IndexSet(integer: self.showSections.count - 1), with: .none)
                    }
                                                          
                }
            }
            devicesRssiSort()
            
            switch self.restoreMode {
            case .default:
                self.footerView.selectCountLabel.text = "\(self.showDevices.count)"
            case .specified(let nodes):
                let restoreTargetCount = self.pendingRestoreNodes(from: nodes).count
                self.footerView.selectCountLabel.text = "\(self.showDevices.count)/\(restoreTargetCount)"
                // 已找到全部设备
                if self.allDevices.count >= restoreTargetCount {
                    stopScan()
                    if self.automationRestore { // 自动恢复设备流程
                        addSelectedBtnClick()
                    }
                    DispatchQueue.main.async {
                        NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
                    }
                    return
                }
            }
            
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
                self.perform(#selector(self.scanTimeout), with: nil, afterDelay: self.automationRestore ? 20 : 10)
            }

        }, scanFinish: nil)
                    
    }
    
    /// 扫描超时（未找到新设备）
    @objc private func scanTimeout() {
        stopScan()
        if self.automationRestore { // 自动恢复设备流程
            addSelectedBtnClick()
        }
    }
    
    @objc private func stopScan() {
        
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.scanTimeout), object: nil)
        }
        
        scanAnimationView.isHidden = true
        scanAnimationView.layer.removeAnimation(forKey: "scan")
        scanBtn.isSelected = false
        MeshAPI.stopScan()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        // 停止扫描设备状态设置为空状态
        self.sections.forEach { section in
            section.restoreDatas.forEach({
                $0.unprovisionedDevice?.addState = .none
            })
        }
        self.tableView.reloadData()
        
        updateUIState()
        
        stopScanTimer()
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 0.5, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        guard sections.count > 0 else {
            return
        }
        // 筛选展示的设备
        var currentShowSections: [DeviceRestoreSection] = []
        sections.forEach { section in
            let devices = section.restoreDatas.filter({ $0.unprovisionedDevice == nil || selectRSSIRange.contains($0.unprovisionedDevice!.rssi.intValue) })
            if devices.count > 0 {
                currentShowSections.append(DeviceRestoreSection(group: section.group, restoreDatas: devices))
            }
        }
        showSections = currentShowSections
        tableView.reloadData()
        
    }
    
    /// 自动恢复扫描设备超时
    @objc private func automationRestoreScanTimeout() {
        stopScan()
        // 回调超时状态到外部
        if automationRestore {
            dismiss()
        }
    }
    
    // MARK: - Mesh API
    
    /// 设备identify
    private func identify(_ device: ProvisioningDevice) {
        
        // 判断连接量是否达到上限
        let bleConnectCount = max(showDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        guard bleConnectCount < 5 else {
            device.addState = .identifyWait
            reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {[weak self] in
                if device.addState == .identifyWait {
                    device.addState = .none
                    self?.reloadDeviceState(device)
                }
            }
            return
        }
        
        if identifyDevice != nil {
            identifyDevice?.addState = .none
            reloadDeviceState(identifyDevice!)
            identifyDevice = nil
            MeshAPI.stopUnprovisionedDeviceIdentify()
        }
        
        device.addState = .identifyConnecting
        reloadDeviceState(device)
        if state == .none || state == .addFineshed {
            state = .identifying
            updateUIState()
        }
        identifyDevice = device
        MeshAPI.unprovisionedDeviceIdentify(device: device, attentionTimer: 6) {[weak self] _, _ in
            device.addState = .identifying
            self?.reloadDeviceState(device)
        } identifyFinished: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .none
            self.identifyDevice = nil
            self.reloadDeviceState(device)
            if self.state == .identifying {
                self.updateUIState()
            }
        } identifyFail: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .identifyFail
            self.reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                guard let self = self else { return }
                if device.addState == .identifyFail {
                    device.addState = .none
                    self.reloadDeviceState(device)
                }
                if self.state == .identifying {
                    self.updateUIState()
                }
            }
        }
    }
    
    private func finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(fallbackDisconnectNodes: [Node]) {
        let requests = pendingBatteryPowerSwitchInitialBatteryReads
        pendingBatteryPowerSwitchInitialBatteryReads.removeAll()
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelsAndDisconnect(
            requests,
            fallbackDisconnectNodes: fallbackDisconnectNodes
        )
    }

    private func batteryPowerSwitchData(boundTo oldNode: Node) -> PJEightKeySwitchData? {
        guard let switchData = MeshNetworkManager.instance.switchs.first(where: {
            $0.proxyNodeAddress == oldNode.primaryUnicastAddress
        }) else {
            return nil
        }
        if let batteryPowerSwitchData = switchData as? PJEightKeySwitchData {
            return batteryPowerSwitchData
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: switchData)
    }

    private func isBatteryPowerSwitchRestore(oldNode: Node, newNode: Node) -> Bool {
        guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(newNode),
              let switchData = batteryPowerSwitchData(boundTo: oldNode) else {
            return false
        }
        return switchData.powerSwitchKind == newNode.powerSwitchKind
    }

    private func prepareBatteryPowerSwitchRestoreConfiguration(
        oldNode: Node,
        newNode: Node,
        appendMessages: inout [MeshMessageHandle]
    ) {
        guard let sourceSwitchData = batteryPowerSwitchData(boundTo: oldNode) else {
            return
        }

        switch BatteryPowerSwitchAddConfiguration.prepareRestoreSwitchData(
            sourceSwitchData: sourceSwitchData,
            node: newNode
        ) {
        case .success(let switchData):
            batteryPowerSwitchRestoreConfigurations[newNode.primaryUnicastAddress] = switchData
            let handles = BatteryPowerSwitchAddConfiguration.restoreConfigurationMessageHandles(
                for: switchData,
                node: newNode
            )
            if handles.isEmpty {
                failedBatteryPowerSwitchRestoreAddresses.insert(newNode.primaryUnicastAddress)
                failedBatteryPowerSwitchRestoreReasons[newNode.primaryUnicastAddress] = "sync_failed".localizedString
            } else {
                appendMessages.append(contentsOf: handles)
            }
        case .failure(let error):
            failedBatteryPowerSwitchRestoreAddresses.insert(newNode.primaryUnicastAddress)
            failedBatteryPowerSwitchRestoreReasons[newNode.primaryUnicastAddress] = error.message
        }
    }

    private func isBatteryPowerSwitchRestoreConfigurationMessage(_ message: MeshMessage) -> Bool {
        guard let message = message as? SunricherVendorSet else {
            return false
        }
        switch message.function {
        case .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnabled, .batteryPowerSwitchLEDEnabled:
            return true
        default:
            return false
        }
    }

    private func markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(_ messageHandle: MeshMessageHandle) {
        guard isBatteryPowerSwitchRestoreConfigurationMessage(messageHandle.message) else {
            return
        }
        guard let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address else {
            return
        }
        guard batteryPowerSwitchRestoreConfigurations[address] != nil else {
            return
        }
        failedBatteryPowerSwitchRestoreAddresses.insert(address)
        failedBatteryPowerSwitchRestoreReasons[address] = "sync_failed".localizedString
    }

    private func finalizeBatteryPowerSwitchRestoreConfiguration(
        for node: Node
    ) -> BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest? {
        guard let switchData = batteryPowerSwitchRestoreConfigurations[node.primaryUnicastAddress] else {
            failedBatteryPowerSwitchRestoreAddresses.remove(node.primaryUnicastAddress)
            failedBatteryPowerSwitchRestoreReasons.removeValue(forKey: node.primaryUnicastAddress)
            return nil
        }

        let failed = failedBatteryPowerSwitchRestoreAddresses.contains(node.primaryUnicastAddress)
        let linkGroupAddress = switchData.linkGroupAddress
        if failed {
            BatteryPowerSwitchAddConfiguration.markFailed(
                switchData,
                reason: failedBatteryPowerSwitchRestoreReasons[node.primaryUnicastAddress]
                    ?? switchData.lastSyncFailedReason
                    ?? "sync_failed".localizedString
            )
        } else {
            BatteryPowerSwitchAddConfiguration.markSucceeded(switchData, clearRemovedGroups: false)
            if let linkGroupAddress {
                successfulBatteryPowerSwitchRestoreLinkGroupAddresses.insert(linkGroupAddress)
            }
        }
        if let linkGroupAddress {
            pendingBatteryPowerSwitchRestoreLinkGroupAddresses.remove(linkGroupAddress)
        }

        let request = BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
            for: switchData,
            node: node
        )

        batteryPowerSwitchRestoreConfigurations.removeValue(forKey: node.primaryUnicastAddress)
        failedBatteryPowerSwitchRestoreAddresses.remove(node.primaryUnicastAddress)
        failedBatteryPowerSwitchRestoreReasons.removeValue(forKey: node.primaryUnicastAddress)
        return request
    }

    private func recordPendingBatteryPowerSwitchRestoreLinkGroups(for restoreDatas: [DeviceRestoreData]) {
        restoreDatas.forEach { data in
            guard let linkGroupAddress = batteryPowerSwitchData(boundTo: data.node)?.linkGroupAddress else {
                return
            }
            pendingBatteryPowerSwitchRestoreLinkGroupAddresses.insert(linkGroupAddress)
        }
    }

    private func recordBatteryPowerSwitchTargetSubscriptionSuccessIfNeeded(
        _ messageHandle: MeshMessageHandle,
        node: Node
    ) {
        guard let target = batteryPowerSwitchTargetSubscription(from: messageHandle.message),
              isPendingOrSuccessfulBatteryPowerSwitchRestoreLinkGroup(target.groupAddress) else {
            return
        }
        let key = BatteryPowerSwitchTargetSubscriptionKey(
            nodeAddress: node.primaryUnicastAddress,
            groupAddress: target.groupAddress,
            elementAddress: target.elementAddress,
            modelIdentifier: target.modelIdentifier,
            companyIdentifier: target.companyIdentifier
        )
        successfulBatteryPowerSwitchTargetSubscriptions.insert(key)
    }

    private func batteryPowerSwitchTargetSubscription(from message: MeshMessage) -> (groupAddress: Address, elementAddress: Address, modelIdentifier: UInt16, companyIdentifier: UInt16?)? {
        if let message = message as? ConfigModelSubscriptionAdd {
            return (message.address, message.elementAddress, message.modelIdentifier, message.companyIdentifier)
        }
        if let message = message as? ConfigModelSubscriptionVirtualAddressAdd {
            return (MeshAddress(message.virtualLabel).address, message.elementAddress, message.modelIdentifier, message.companyIdentifier)
        }
        return nil
    }

    private func isPendingOrSuccessfulBatteryPowerSwitchRestoreLinkGroup(_ groupAddress: Address) -> Bool {
        pendingBatteryPowerSwitchRestoreLinkGroupAddresses.contains(groupAddress)
            || successfulBatteryPowerSwitchRestoreLinkGroupAddresses.contains(groupAddress)
            || batteryPowerSwitchRestoreConfigurations.values.contains(where: { $0.linkGroupAddress == groupAddress })
    }

    private func shouldMarkRestoredNodeSyncFailed(
        _ node: Node,
        phase: RestoreSyncEvaluationPhase
    ) -> Bool {
        guard !node.isPowerSwitch else {
            return false
        }
        // 恢复数据不包括邻近照明邻居关系，涉及其它节点，仍保持外部同步流程。
        guard node.getNodeSyncProximityLighting() == nil else {
            return false
        }

        let syncDatas = node.getSyncData(type: .all)
        guard !syncDatas.isEmpty else {
            return false
        }

        let unresolvedSyncDescriptions = syncDatas.flatMap {
            unresolvedRestoreSyncDescriptions(for: $0, node: node, phase: phase)
        }
        guard !unresolvedSyncDescriptions.isEmpty else {
            print("[DeviceRestore] Skip sync failed for node=\(node.primaryUnicastAddress.hex), recovered BPS target subscription only")
            return false
        }

        print("[DeviceRestore] Mark sync failed for node=\(node.primaryUnicastAddress.hex), sync=\(unresolvedSyncDescriptions.joined(separator: ","))")
        return true
    }

    private func unresolvedRestoreSyncDescriptions(
        for syncData: NodeSyncData,
        node: Node,
        phase: RestoreSyncEvaluationPhase
    ) -> [String] {
        switch syncData {
        case .syncSwitchs(let switchDatas):
            return switchDatas.compactMap { switchData in
                if shouldIgnoreRestoredBatteryPowerSwitchTargetSync(
                    switchData: switchData,
                    node: node,
                    phase: phase
                ) {
                    return nil
                }
                return restoreSyncSwitchDescription(switchData)
            }
        default:
            return [restoreSyncDescription(syncData)]
        }
    }

    private func shouldIgnoreRestoredBatteryPowerSwitchTargetSync(
        switchData: DeviceSwitchData,
        node: Node,
        phase: RestoreSyncEvaluationPhase
    ) -> Bool {
        guard switchData.batteryPowerSwitchData != nil,
              let linkGroupAddress = switchData.linkGroupAddress else {
            return false
        }

        switch phase {
        case .deviceSuccess:
            return pendingBatteryPowerSwitchRestoreLinkGroupAddresses.contains(linkGroupAddress)
                || successfulBatteryPowerSwitchRestoreLinkGroupAddresses.contains(linkGroupAddress)
        case .batchFinish:
            guard successfulBatteryPowerSwitchRestoreLinkGroupAddresses.contains(linkGroupAddress) else {
                return false
            }
            let keys = batteryPowerSwitchExpectedTargetSubscriptionKeys(
                switchData: switchData,
                node: node
            )
            guard !keys.isEmpty else {
                return false
            }
            return keys.allSatisfy { successfulBatteryPowerSwitchTargetSubscriptions.contains($0) }
        }
    }

    private func batteryPowerSwitchExpectedTargetSubscriptionKeys(
        switchData: DeviceSwitchData,
        node: Node
    ) -> [BatteryPowerSwitchTargetSubscriptionKey] {
        let handles: [MeshMessageHandle]
        if node.batteryPowerSwitchRestoreTargetSubscriptionSnapshots != nil {
            handles = node.getBatteryPowerSwitchRestoreTargetSubscriptionMessageHandles(
                switchData: switchData,
                includeExisting: true
            )
        } else {
            handles = node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(
                switchData: switchData,
                unsubscribe: false,
                includeExisting: true
            )
        }
        return handles.compactMap { handle in
            guard let target = batteryPowerSwitchTargetSubscription(from: handle.message) else {
                return nil
            }
            return BatteryPowerSwitchTargetSubscriptionKey(
                nodeAddress: node.primaryUnicastAddress,
                groupAddress: target.groupAddress,
                elementAddress: target.elementAddress,
                modelIdentifier: target.modelIdentifier,
                companyIdentifier: target.companyIdentifier
            )
        }
    }

    private func restoreSyncSwitchDescription(_ switchData: DeviceSwitchData) -> String {
        if switchData.batteryPowerSwitchData != nil {
            return "batteryPowerSwitchTarget(\(switchData.linkGroupAddress?.hex ?? "nil"))"
        }
        return "switch(\(switchData.id))"
    }

    private func restoreSyncDescription(_ syncData: NodeSyncData) -> String {
        switch syncData {
        case .subscribeGroup(let group):
            return "subscribeGroup(\(group.address.address.hex))"
        case .unsubscribeGroup(let group):
            return "unsubscribeGroup(\(group.address.address.hex))"
        case .profile(let types):
            return "profile(\(types.count))"
        case .syncScenes(let datas):
            return "syncScenes(\(datas.count))"
        case .deleteScenes(let scenes):
            return "deleteScenes(\(scenes.count))"
        case .syncSchedules(let schedules):
            return "syncSchedules(\(schedules.count))"
        case .deleteSchedules(let schedules):
            return "deleteSchedules(\(schedules.count))"
        case .syncSwitchProxy:
            return "syncSwitchProxy"
        case .deleteSwitchProxy:
            return "deleteSwitchProxy"
        case .syncSwitchs(let switchDatas):
            return "syncSwitchs(\(switchDatas.count))"
        case .deleteSwitchs(let switchDatas):
            return "deleteSwitchs(\(switchDatas.count))"
        case .deviceInitialize:
            return "deviceInitialize"
        case .deviceParameterTypes(let types):
            return "deviceParameterTypes(\(types.count))"
        case .syncCollectionSchedules(let schedules):
            return "syncCollectionSchedules(\(schedules.count))"
        case .deleteCollectionSchedules(let scheduleIds):
            return "deleteCollectionSchedules(\(scheduleIds.count))"
        case .syncGatewaySubnetAppkeyIndexs(let appkeyIndexs):
            return "syncGatewaySubnetAppkeyIndexs(\(appkeyIndexs.count))"
        case .gatewayAssociatedSpaces(let datas, let activate):
            return "gatewayAssociatedSpaces(\(datas.count),activate:\(activate))"
        case .gatewayUnbindAssociatedSpaces(let datas, let activate):
            return "gatewayUnbindAssociatedSpaces(\(datas.count),activate:\(activate))"
        case .pirEnabled(let enabled):
            return "pirEnabled(\(enabled))"
        default:
            return "otherSync"
        }
    }

    private func deferredRestoreOperationDescription(_ operationType: DeviceOperationType) -> String {
        switch operationType {
        case .configuration(_, let actionType):
            return "configuration(\(deferredRestoreActionDescription(actionType)))"
        case .delete(_, let actionType):
            return "delete(\(deferredRestoreActionDescription(actionType)))"
        case .read(_, let actionType):
            return "read(\(deferredRestoreActionDescription(actionType)))"
        }
    }

    private func deferredRestoreActionDescription(_ actionType: ActionType) -> String {
        switch actionType {
        case .scene(let sceneId, _):
            return "scene(\(sceneId))"
        case .schedule:
            return "schedule"
        case .profile(let type):
            return "profile(\(type))"
        case .enOceanSwitch:
            return "enOceanSwitch"
        case .enOceanProxy:
            return "enOceanProxy"
        case .collectionSchedule(let index, _):
            return "collectionSchedule(\(index))"
        default:
            return String(describing: actionType)
        }
    }

    private func appendRestoreSyncMessages(
        syncDatas: [NodeSyncData],
        node: Node,
        appendMessages: inout [MeshMessageHandle]
    ) {
        var batteryPowerSwitchMessages: [MeshMessageHandle] = []
        var deferredSyncDatas: [NodeSyncData] = []

        syncDatas.forEach { syncData in
            switch syncData {
            case .syncSwitchs(let switchDatas):
                var otherSwitchDatas: [DeviceSwitchData] = []
                switchDatas.forEach { switchData in
                    if switchData.batteryPowerSwitchData != nil {
                        batteryPowerSwitchMessages.append(
                            contentsOf: node.getBatteryPowerSwitchRestoreTargetSubscriptionMessageHandles(
                                switchData: switchData
                            )
                        )
                    } else {
                        otherSwitchDatas.append(switchData)
                    }
                }
                if !otherSwitchDatas.isEmpty {
                    deferredSyncDatas.append(.syncSwitchs(switchDatas: otherSwitchDatas))
                }
            case .profile(_),
                    .syncScenes(_),
                    .deleteScenes(_),
                    .syncSchedules(_),
                    .deleteSchedules(_),
                    .syncCollectionSchedules(_),
                    .deleteCollectionSchedules(_),
                    .syncSwitchProxy(_),
                    .deleteSwitchProxy(_),
                    .deleteSwitchs(_):
                deferredSyncDatas.append(syncData)
            default:
                appendMessages.append(contentsOf: syncData.getMessageHandles(node: node))
            }
        }

        appendMessages.append(contentsOf: batteryPowerSwitchMessages)
        storeDeferredRestoreSyncDatas(syncDatas: deferredSyncDatas, node: node)
    }

    private func storeDeferredRestoreSyncDatas(
        syncDatas: [NodeSyncData],
        node: Node
    ) {
        let tasks = deferredRestoreTasks(syncDatas: syncDatas, node: node)
        guard !tasks.isEmpty else {
            deferredRestoreSyncDatasByAddress.removeValue(forKey: node.primaryUnicastAddress)
            return
        }
        deferredRestoreSyncDatasByAddress[node.primaryUnicastAddress] = syncDatas

        #if DEBUG
        let filteredSceneRecallCount = tasks.reduce(0) { $0 + $1.filteredSceneRecallCount }
        let descriptions = syncDatas.map { restoreSyncDescription($0) }.joined(separator: ",")
        print("[DeviceRestore] Defer restore sync node=\(node.primaryUnicastAddress.hex), tasks=\(tasks.count), filteredSceneRecalls=\(filteredSceneRecallCount), sync=\(descriptions)")
        #endif
    }

    private func hasDeferredRestoreSyncData(for node: Node) -> Bool {
        !(deferredRestoreSyncDatasByAddress[node.primaryUnicastAddress]?.isEmpty ?? true)
    }

    private func deferredRestoreTasks(
        syncDatas: [NodeSyncData],
        node: Node
    ) -> [DeferredRestoreTask] {
        var tasks: [DeferredRestoreTask] = []

        func appendTask(_ operationType: DeviceOperationType) {
            let messageHandles = operationType.messageHandles
            let filteredMessageHandles = messageHandles.filter { !($0.message is SceneRecall) }
            let filteredSceneRecallCount = messageHandles.count - filteredMessageHandles.count
            guard !filteredMessageHandles.isEmpty else {
                #if DEBUG
                if filteredSceneRecallCount > 0 {
                    print("[DeviceRestore] Skip restore SceneRecall-only task node=\(node.primaryUnicastAddress.hex), count=\(filteredSceneRecallCount)")
                }
                #endif
                return
            }
            #if DEBUG
            if filteredSceneRecallCount > 0 {
                print("[DeviceRestore] Filter restore SceneRecall node=\(node.primaryUnicastAddress.hex), count=\(filteredSceneRecallCount)")
            }
            #endif
            let task = DeferredRestoreTask(
                operationType: operationType,
                messageHandles: filteredMessageHandles,
                filteredSceneRecallCount: filteredSceneRecallCount
            )
            tasks.append(task)
        }

        syncDatas.forEach { syncData in
            switch syncData {
            case .profile(let types):
                types.forEach { profileType in
                    appendTask(.configuration(node: node, type: .profile(type: profileType)))
                }
            case .syncScenes(let datas):
                datas.forEach { scene, data in
                    appendTask(.configuration(node: node, type: .scene(sceneId: scene.number, executeData: data)))
                }
            case .deleteScenes(let scenes):
                scenes.forEach { scene in
                    appendTask(.delete(node: node, type: .scene(sceneId: scene.number, executeData: nil)))
                }
            case .syncSchedules(let schedules):
                schedules.forEach { schedule in
                    appendTask(.configuration(node: node, type: .schedule(schedule: schedule)))
                }
            case .deleteSchedules(let schedules):
                schedules.forEach { schedule in
                    appendTask(.delete(node: node, type: .schedule(schedule: schedule)))
                }
            case .syncCollectionSchedules(let schedules):
                schedules.forEach { index, entry in
                    appendTask(.configuration(node: node, type: .collectionSchedule(index: index, entry: entry)))
                }
            case .deleteCollectionSchedules(let scheduleIds):
                scheduleIds.forEach { index in
                    appendTask(.delete(node: node, type: .collectionSchedule(index: index, entry: SchedulerRegistryEntry())))
                }
            case .syncSwitchProxy(let switchData):
                appendTask(.configuration(node: node, type: .enOceanProxy(switchData: switchData)))
            case .deleteSwitchProxy(let switchData):
                appendTask(.delete(node: node, type: .enOceanProxy(switchData: switchData)))
            case .syncSwitchs(let switchDatas):
                switchDatas.forEach { switchData in
                    guard switchData.batteryPowerSwitchData == nil else {
                        return
                    }
                    appendTask(.configuration(node: node, type: .enOceanSwitch(switchData: switchData)))
                }
            case .deleteSwitchs(let switchDatas):
                switchDatas.forEach { switchData in
                    guard switchData.batteryPowerSwitchData == nil else {
                        return
                    }
                    appendTask(.delete(node: node, type: .enOceanSwitch(switchData: switchData)))
                }
            default:
                break
            }
        }

        return tasks
    }

    private func runDeferredRestoreIfNeeded(
        successList: [ProvisioningDevice],
        completion: @escaping () -> Void
    ) {
        let deferredDevices = successList.filter {
            !(deferredRestoreSyncDatasByAddress[$0.address]?.isEmpty ?? true)
        }
        guard !deferredDevices.isEmpty else {
            completion()
            return
        }
        runDeferredRestoreDevices(
            deferredDevices,
            index: 0,
            completion: completion
        )
    }

    private func runDeferredRestoreDevices(
        _ devices: [ProvisioningDevice],
        index: Int,
        completion: @escaping () -> Void
    ) {
        guard index < devices.count else {
            completion()
            return
        }

        let device = devices[index]
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: device.address) else {
            device.addState = .syncFailed
            reloadDeviceState(device)
            updateUIState()
            runDeferredRestoreDevices(devices, index: index + 1, completion: completion)
            return
        }

        let syncDatas = deferredRestoreSyncDatasByAddress[node.primaryUnicastAddress] ?? []
        let tasks = deferredRestoreTasks(syncDatas: syncDatas, node: node)
        guard !tasks.isEmpty else {
            deferredRestoreSyncDatasByAddress.removeValue(forKey: node.primaryUnicastAddress)
            finishDeferredRestore(for: node, device: device, hadFailedTask: false)
            runDeferredRestoreDevices(devices, index: index + 1, completion: completion)
            return
        }

        device.addState = .adding
        reloadDeviceState(device)
        updateUIState()

        runDeferredRestoreTasks(tasks, index: 0, node: node, hadFailedTask: false) { [weak self] hadFailedTask in
            guard let self = self else { return }
            self.deferredRestoreSyncDatasByAddress.removeValue(forKey: node.primaryUnicastAddress)
            self.finishDeferredRestore(for: node, device: device, hadFailedTask: hadFailedTask)
            self.runDeferredRestoreDevices(devices, index: index + 1, completion: completion)
        }
    }

    private func runDeferredRestoreTasks(
        _ tasks: [DeferredRestoreTask],
        index: Int,
        node: Node,
        hadFailedTask: Bool,
        retryCount: Int = 0,
        completion: @escaping (Bool) -> Void
    ) {
        guard index < tasks.count else {
            completion(hadFailedTask)
            return
        }

        let task = tasks[index]
        let messageHandles = task.messageHandles
        let responseTracker = DeferredRestoreResponseTracker()
        guard !messageHandles.isEmpty else {
            runDeferredRestoreTasks(
                tasks,
                index: index + 1,
                node: node,
                hadFailedTask: hadFailedTask,
                retryCount: 0,
                completion: completion
            )
            return
        }

        runDeferredRestoreMessageHandles(
            messageHandles,
            task: task,
            node: node,
            responseTracker: responseTracker
        ) { [weak self] in
            self?.handleDeferredRestoreTaskCompletion(
                tasks: tasks,
                index: index,
                task: task,
                node: node,
                hadFailedTask: hadFailedTask,
                retryCount: retryCount,
                responseTracker: responseTracker,
                completion: completion
            )
        }
    }

    private func runDeferredRestoreMessageHandles(
        _ messageHandles: [MeshMessageHandle],
        task: DeferredRestoreTask,
        node: Node,
        responseTracker: DeferredRestoreResponseTracker,
        completion: @escaping () -> Void
    ) {
        MeshProxyMessageCommand.shared.addMessage(
            messageHandles: messageHandles,
            ackMessageTimeout: 7,
            progressBack: nil,
            successfulBack: { [weak self] handle, statusMessage in
                if self?.isSuccessfulDeferredRestoreResponse(statusMessage) == true {
                    responseTracker.markSuccessful(handle: handle, statusMessage: statusMessage)
                }
                self?.handleDeferredRestoreSuccessfulResponse(
                    handle: handle,
                    statusMessage: statusMessage,
                    node: node,
                    messageHandles: task.messageHandles
                )
            },
            failedBack: nil
        ) { _ in
            completion()
        }
    }

    private func handleDeferredRestoreTaskCompletion(
        tasks: [DeferredRestoreTask],
        index: Int,
        task: DeferredRestoreTask,
        node: Node,
        hadFailedTask: Bool,
        retryCount: Int,
        responseTracker: DeferredRestoreResponseTracker,
        completion: @escaping (Bool) -> Void
    ) {
        let messageHandles = task.messageHandles
        let resultSuccessful = !messageHandles.contains(where: { !$0.isSuccessful })
        let operationSuccessful = task.operationType.isSuccessful
        let failedHandles = messageHandles.filter { !$0.isSuccessful }
        let failedHandlesRecoveredBySuccessfulResponses = !failedHandles.isEmpty
            && failedHandles.allSatisfy { responseTracker.hasSuccessfulResponse(for: $0) }
        let recoveredByReliableOperationState = !failedHandles.isEmpty
            && operationSuccessful
            && hasReliableDeferredOperationStateCheck(task.operationType)
        let taskSuccessful = isDeferredRestoreTaskSuccessful(
            resultSuccessful: resultSuccessful,
            operationSuccessful: operationSuccessful,
            failedHandlesRecoveredBySuccessfulResponses: failedHandlesRecoveredBySuccessfulResponses,
            recoveredByReliableOperationState: recoveredByReliableOperationState
        )
        let taskFailed = !taskSuccessful

        let retryHandles = retryableDeferredRestoreHandles(
            failedHandles: failedHandles,
            responseTracker: responseTracker,
            retryCount: retryCount
        )

        if taskFailed, !retryHandles.isEmpty {
            #if DEBUG
            let failedDescription = deferredRestoreFailedHandleDescription(retryHandles)
            let operationDescription = deferredRestoreOperationDescription(task.operationType)
            print("[DeviceRestore] Retry deferred restore task node=\(node.primaryUnicastAddress.hex), retry=\(retryCount + 1), operation=\(operationDescription), failed=\(failedDescription)")
            #endif
            resetDeferredRestoreMessageHandles(retryHandles)
            DispatchQueue.main.asyncAfter(deadline: .now() + deferredRestoreTaskRetryDelay) { [weak self] in
                guard let self = self else { return }
                self.runDeferredRestoreMessageHandles(
                    retryHandles,
                    task: task,
                    node: node,
                    responseTracker: responseTracker
                ) { [weak self] in
                    self?.handleDeferredRestoreTaskCompletion(
                        tasks: tasks,
                        index: index,
                        task: task,
                        node: node,
                        hadFailedTask: hadFailedTask,
                        retryCount: retryCount + 1,
                        responseTracker: responseTracker,
                        completion: completion
                    )
                }
            }
            return
        }

        updateDeferredRestoreNodeData(
            resultMessageHandles: messageHandles,
            responseTracker: responseTracker,
            recoveredByReliableOperationState: recoveredByReliableOperationState,
            fallbackNode: node
        )

        #if DEBUG
        if taskFailed {
            let failedDescription = deferredRestoreFailedHandleDescription(failedHandles)
            let responseKeys = responseTracker.responseKeysDescription()
            print("[DeviceRestore] Deferred restore task failed node=\(node.primaryUnicastAddress.hex), result=\(resultSuccessful), operation=\(operationSuccessful), response=\(responseTracker.hasSuccessfulResponse), reliableOperation=\(recoveredByReliableOperationState), keys=\(responseKeys), failed=\(failedDescription)")
        } else if !resultSuccessful && operationSuccessful && (failedHandlesRecoveredBySuccessfulResponses || recoveredByReliableOperationState) {
            let failedDescription = deferredRestoreFailedHandleDescription(failedHandles)
            let responseKeys = responseTracker.responseKeysDescription()
            print("[DeviceRestore] Ignore deferred handle false node=\(node.primaryUnicastAddress.hex), operation=true, response=\(failedHandlesRecoveredBySuccessfulResponses), reliableOperation=\(recoveredByReliableOperationState), keys=\(responseKeys), failed=\(failedDescription)")
        }
        #endif

        runDeferredRestoreTasks(
            tasks,
            index: index + 1,
            node: node,
            hadFailedTask: hadFailedTask || taskFailed,
            retryCount: 0,
            completion: completion
        )
    }

    private func retryableDeferredRestoreHandles(
        failedHandles: [MeshMessageHandle],
        responseTracker: DeferredRestoreResponseTracker,
        retryCount: Int
    ) -> [MeshMessageHandle] {
        guard retryCount < deferredRestoreTaskMaxRetryCount, !failedHandles.isEmpty else {
            return []
        }

        let unrecoveredFailedHandles = failedHandles.filter {
            !responseTracker.hasSuccessfulResponse(for: $0)
        }
        guard !unrecoveredFailedHandles.isEmpty,
              unrecoveredFailedHandles.allSatisfy({ isRetryableDeferredRestoreHandle($0) }) else {
            return []
        }

        return unrecoveredFailedHandles
    }

    private func isRetryableDeferredRestoreHandle(_ messageHandle: MeshMessageHandle) -> Bool {
        guard messageHandle.message is AcknowledgedMeshMessage,
              !(messageHandle.message is SceneRecall),
              !isBatteryPowerSwitchRestoreConfigurationMessage(messageHandle.message),
              !messageHandle.notRespondAddresss.isEmpty else {
            return false
        }
        return true
    }

    private func resetDeferredRestoreMessageHandles(_ messageHandles: [MeshMessageHandle]) {
        messageHandles.forEach {
            $0.respondAddresss = []
            $0.notRespondAddresss = []
        }
    }

    private func isDeferredRestoreTaskSuccessful(
        resultSuccessful: Bool,
        operationSuccessful: Bool,
        failedHandlesRecoveredBySuccessfulResponses: Bool,
        recoveredByReliableOperationState: Bool
    ) -> Bool {
        if resultSuccessful && operationSuccessful {
            return true
        }
        guard operationSuccessful else {
            return false
        }
        return failedHandlesRecoveredBySuccessfulResponses || recoveredByReliableOperationState
    }

    private func isSuccessfulDeferredRestoreResponse(_ statusMessage: StaticMeshMessage) -> Bool {
        if let configStatus = statusMessage as? ConfigStatusMessage {
            return configStatus.isSuccess
        }
        if let vendorStatus = statusMessage as? SunricherVendorStatus {
            return vendorStatus.status.isSuccessful
        }
        return true
    }

    private func hasReliableDeferredOperationStateCheck(_ operationType: DeviceOperationType) -> Bool {
        switch operationType {
        case .configuration(_, let actionType):
            return hasReliableDeferredActionStateCheck(actionType)
        case .delete(_, let actionType):
            switch actionType {
            case .scene, .schedule, .collectionSchedule, .enOceanSwitch, .enOceanProxy:
                return true
            case .profile(let type):
                return hasReliableDeferredProfileStateCheck(type)
            default:
                return false
            }
        case .read:
            return false
        }
    }

    private func hasReliableDeferredActionStateCheck(_ actionType: ActionType) -> Bool {
        switch actionType {
        case .scene, .schedule, .collectionSchedule, .enOceanSwitch, .enOceanProxy:
            return true
        case .profile(let type):
            return hasReliableDeferredProfileStateCheck(type)
        default:
            return false
        }
    }

    private func hasReliableDeferredProfileStateCheck(_ type: ProfileType) -> Bool {
        switch type {
        case .daylightCalibrateRate,
                .daylightCalibrateInflectionPoint,
                .lightControlSwitch,
                .daylightSensorConditionRecall,
                .lightControlRestore,
                .profileToggleTriggerConditionLuxLock,
                .profileToggleTriggerConditionLuxUnLock:
            return false
        default:
            return true
        }
    }

    private func deferredRestoreFailedHandleDescription(_ failedHandles: [MeshMessageHandle]) -> String {
        guard !failedHandles.isEmpty else {
            return "none"
        }
        return failedHandles.map { handle in
            let message = String(describing: type(of: handle.message))
            let target = formatDeferredRestoreAddress(handle.targetAddress)
            let responded = handle.respondAddresss.map { formatDeferredRestoreAddress($0) }.joined(separator: ",")
            let missing = handle.notRespondAddresss.map { formatDeferredRestoreAddress($0) }.joined(separator: ",")
            return "\(message)@\(target)[responded=\(responded),missing=\(missing)]"
        }.joined(separator: ";")
    }

    private func formatDeferredRestoreAddress(_ address: Address) -> String {
        String(format: "%04X", Int(address))
    }

    private func handleDeferredRestoreSuccessfulResponse(
        handle: MeshMessageHandle,
        statusMessage: StaticMeshMessage,
        node: Node,
        messageHandles: [MeshMessageHandle]
    ) {
        if statusMessage is GenericOnOffStatus
            || statusMessage is LightLightnessStatus
            || statusMessage is LightCTLTemperatureStatus
            || statusMessage is LightCTLStatus
            || statusMessage is LightHSLStatus,
           messageHandles.contains(where: { $0.message is SceneStore }) {
            let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
            let targetNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? node
            targetNode.updateNodeStatus(message: statusMessage, source: address)
            if let onOffStatus = statusMessage as? GenericOnOffStatus,
               !(onOffStatus.targetState ?? onOffStatus.isOn) {
                targetNode.lightness = 0
            }
        }
    }

    private func updateDeferredRestoreNodeData(
        resultMessageHandles: [MeshMessageHandle],
        responseTracker: DeferredRestoreResponseTracker,
        recoveredByReliableOperationState: Bool,
        fallbackNode: Node
    ) {
        resultMessageHandles.forEach { handle in
            let address = handle.address ?? handle.model?.parentElement?.unicastAddress ?? fallbackNode.primaryUnicastAddress
            let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) ?? fallbackNode
            let effectiveSuccess = handle.isSuccessful
                || responseTracker.hasSuccessfulResponse(for: handle)
                || recoveredByReliableOperationState
            node.updateData(message: handle.message, isSuccess: effectiveSuccess)
            node.clearSyncStateCache()
        }
    }

    private func finishDeferredRestore(
        for node: Node,
        device: ProvisioningDevice,
        hadFailedTask: Bool
    ) {
        if hadFailedTask || shouldMarkRestoredNodeSyncFailed(node, phase: .batchFinish) {
            if hadFailedTask {
                print("[DeviceRestore] Mark sync failed for node=\(node.primaryUnicastAddress.hex), deferred task failed")
            }
            device.addState = .syncFailed
        } else {
            device.addState = .success
        }
        reloadDeviceState(device)
        updateUIState()
    }

    // MARK: - Device Restore
    /// 添加设备
    private func addDevice(_ deviceData: DeviceRestoreData) {
        
        guard let unprovisionedDevice = deviceData.unprovisionedDevice else {
            return
        }
        
        // 设备identify中添加不需要再闪烁
//        if unprovisionedDevice.addState == .identifyConnecting || unprovisionedDevice.addState == .identifyWait || unprovisionedDevice.addState == .failed || unprovisionedDevice.addState == .identifying {
            //            if device.addState == .identifying {
            //                device.identifyAttentionTimer = 0
            //            }
        if deviceData.unprovisionedDevice?.peripheral.identifier.uuidString == identifyDevice?.peripheral.identifier.uuidString {
                //                if let bearer = identifyBearer { // 将identify连接的设备数据传入添加设备操作，避免二次连接
                //                    device.gattBearer = PBGattBearer(bearer: bearer)
                //                    stopDeviceIdentify(close: false)
                //                }else {
            MeshAPI.stopUnprovisionedDeviceIdentify()
                //                }
            }
//        }
        // 添加设备不需要闪烁
        unprovisionedDevice.identifyAttentionTimer = 0
        if unprovisionedDevice.addState == .none {
            unprovisionedDevice.addState = .wait
            unprovisionedDevice.selectedState = .disabled
            reloadDeviceState(unprovisionedDevice)
        }
        updateUIState()
        
        MeshAPI.startFastAddDevices(devices: [unprovisionedDevice]) { [weak self] addDevice in
            addDevice.addState = .addConnecting
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } connectingBack: {[weak self] addDevice in
            addDevice.addState = .adding
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } provisionCompleteCallback: {[weak self] addDevice, node in
            guard let self = self else { return }
            
            var oldNode = deviceData.node
            var addToGroup = oldNode.group
            if oldNode.groupState == .exitFailure {
                addToGroup = nil
            }
            
            if let section = self.showSections.first(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == addDevice }) }), let data = section.restoreDatas.first(where: { $0.unprovisionedDevice == addDevice }) {
                oldNode = data.node
                if oldNode.groupState == .exitFailure {
                    addToGroup = nil
                }else {
                    addToGroup = section.group
                }
            }
            
            if addDevice.deviceType == .gateway, let mac = node.macAddress { // 网关设备，创建一个网关model数据映射
                
                let gatewayModel = GatewayModel.load(node: oldNode) ?? GatewayModel(siteId: site.id, name: node.name ?? "", address: node.primaryUnicastAddress, mac: mac, activate: true)
                gatewayModel.address = node.primaryUnicastAddress
                gatewayModel.save()
            }
            // 新添加的设备支持最新功能绑定要求
            node.requiredFunctionTypes = [.lightLCScene, .lightLCScheduler]
            
            // 恢复数据
            node.updateResoreData(oldNode: oldNode, resoreGroup: addToGroup)
            node.batteryPowerSwitchRestoreTargetSubscriptionSnapshots = oldNode.makeBatteryPowerSwitchRestoreTargetSubscriptionSnapshots(
                group: addToGroup
            )
            
        } appendMessagesBack: {[weak self] addDevice, appendCompletion in
            guard let self = self, let newNode = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) else {
                appendCompletion([])
                return
            }
            
            var oldNode = deviceData.node
            var addToGroup = oldNode.group
//            if oldNode.groupState == .exitFailure {
//                addToGroup = nil
//            }
//            
            if let section = self.showSections.first(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == addDevice }) }), let data = section.restoreDatas.first(where: { $0.unprovisionedDevice == addDevice }) {
                oldNode = data.node
                if oldNode.groupState == .exitFailure {
                    addToGroup = nil
                }else {
                    addToGroup = section.group
                }
            }
//            
//            // 恢复数据
//            newNode.updateResoreData(oldNode: oldNode, resoreGroup: addToGroup)

            let restoringBatteryPowerSwitch = isBatteryPowerSwitchRestore(
                oldNode: oldNode,
                newNode: newNode
            )
            
            var appendMessages: [MeshMessageHandle] = []

            if restoringBatteryPowerSwitch {
                prepareBatteryPowerSwitchRestoreConfiguration(
                    oldNode: oldNode,
                    newNode: newNode,
                    appendMessages: &appendMessages
                )
                if let healthModel = newNode.healthModel {
                    appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
                }
                appendCompletion(appendMessages)
                return
            }
            newNode.batteryPowerSwitchRestoreTargetSubscriptionSnapshots = oldNode.makeBatteryPowerSwitchRestoreTargetSubscriptionSnapshots(
                group: addToGroup
            )

            // 入网后默认调为最大亮度
            if let model = newNode.lightnessModel {
                appendMessages.append(MeshMessageHandle(message: LightLightnessSetUnacknowledged(lightness: .max), model: model))
            }
            let syncDatas = newNode.getSyncData(type: .all)
            self.appendRestoreSyncMessages(syncDatas: syncDatas, node: newNode, appendMessages: &appendMessages)
//            appendMessages.append(contentsOf: newNode.getResoreMessageHandles(oldNode: oldNode))
            
            if addToGroup == nil {
                if let vendorModel = newNode.sunricherVendorModel { // 未加入组的设备默认设置一个手动控制延迟时间，避免默认30s后状态被LC修改
                    appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max)), model: vendorModel))
                }
                if let powerOnOffSetupModel = newNode.powerOnOffSetupModel, newNode.lightLCModel != nil { // 设置默认上电状态为上一次亮度
                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .restore), model: powerOnOffSetupModel))
                    //                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .default), model: powerOnOffSetupModel))
                    //                    appendMessages.append(MeshMessageHandle(message: LightLightnessDefaultSet(lightness: .max), model: lightnessSetupModel))
                }
            }
            // 需要追加发送的消息
            if let ctlModel = newNode.ctlModel, newNode.temperatureModel != nil {
                appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
                newNode.lightCTLTemperatureRange = oldNode.lightCTLTemperatureRange
                newNode.changeControlPage = oldNode.changeControlPage
                newNode.absoluteCctRange = oldNode.absoluteCctRange
            }
            // 节点数据hash
//            if let vendorModel = newNode.sunricherVendorModel {
//                appendMessages.append(MeshMessageHandle(message: SunricherVendorGet(function: .compositionHash), model: vendorModel))
//                newNode.compositionHash = oldNode.compositionHash
//            }
            // 添加成功后闪烁
            if let healthModel = newNode.healthModel {
                appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
            }
            appendMessages = newNode.filterSunSmartBatteryPowerSwitchSubscriptionMessageHandles(appendMessages)
            appendCompletion(appendMessages)
//            return appendMessages
        } appendMessageSuccessBack: { [weak self] messageHandle in
            // 发送扩展消息成功更新缓存数据
            if let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                self?.recordBatteryPowerSwitchTargetSubscriptionSuccessIfNeeded(messageHandle, node: node)
                DispatchQueue.global().async {
                    node.updateData(message: messageHandle.message)
                }
            }
        } appendMessageFailedBack: { [weak self] messageHandle in
            self?.markBatteryPowerSwitchRestoreConfigurationFailedIfNeeded(messageHandle)
        } addSuccess: {[weak self] addDevice in
            guard let self = self else { return }
            addDevice.addState = .success
            if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) {
//                if let repalceNode = addDevice.repalceNode { // 删除被替换节点的缓存数据
//                    repalceNode.deleteExtension()
//                }
                node.rssi = addDevice.rssi.intValue
                node.macAddress = addDevice.macAddress
                node.name = deviceData.node.name
                if let section = self.showSections.first(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == addDevice }) }), let data = section.restoreDatas.first(where: { $0.unprovisionedDevice == addDevice }) {
                    node.name = data.node.name
                }
                node.save()
                if let request = finalizeBatteryPowerSwitchRestoreConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
                if self.hasDeferredRestoreSyncData(for: node) {
                    addDevice.addState = .adding
                } else if shouldMarkRestoredNodeSyncFailed(node, phase: .deviceSuccess) {
                    addDevice.addState = .syncFailed
                }
                self.restoreNodes.append(node)
            }
            self.reloadDeviceState(addDevice)
            self.updateUIState()
            
        } addFail: {[weak self] addDevice, error in
            guard let self = self else { return }
            addDevice.addState = .failed
            addDevice.selectedState = .selected
            self.reloadDeviceState(addDevice)
            self.updateUIState()
            if case .noAddressAvailable = error, !self.applyDeviceAddress {
                let applyAddressCount = 200
                guard NetworkRequest.shared.networkable else {
                    if SRAlertView.getCurrentAlertView() == nil {
                        SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                            if NetworkRequest.shared.networkable {
                                self?.space?.applyDeviceAddressCount = nil
                                self?.space?.save()
                                self?.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
                            }
                        })]).show()
                    }
                    self.space?.applyDeviceAddressCount = applyAddressCount
                    self.space?.save()
                    return
                }
                self.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
            }
            
        } addFinish: {[weak self] successList, failList in
            guard let self = self else { return }
            self.runDeferredRestoreIfNeeded(successList: successList) { [weak self] in
                guard let self = self else { return }
                UpDownLightDefaultCctStepsReader.readAfterProvisioning(nodes: self.restoreNodes) { [weak self] in
                    self?.finishDeviceRestoreAdd(successList: successList, failList: failList)
                }
            }
        }
    }

    private func finishDeviceRestoreAdd(
        successList: [ProvisioningDevice],
        failList: [ProvisioningDevice]
    ) {
        // 添加完成后检查是否有设备需要同步
        let needSyncNodes = restoreNodes.filter({
            shouldMarkRestoredNodeSyncFailed($0, phase: .batchFinish)
        })
        if needSyncNodes.count > 0 {
            needSyncNodes.forEach({ node in
                if let device = successList.first(where: { $0.address == node.primaryUnicastAddress }) {
                    device.addState = .syncFailed
                }
            })
            tableView.reloadData()
            updateUIState()
        }

        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))

        let addedBatteryPowerSwitchNodes = restoreNodes.filter { $0.isBatteryPowerSwitch }
        finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect(
            fallbackDisconnectNodes: addedBatteryPowerSwitchNodes
        )

        // 是否自动化恢复流程
        if automationRestore {
            if failList.count > 0 && automationRetryCount > 0 {
                automationRetryCount -= 1
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                    guard let self = self, self.automationRestore else { return }
                    self.addSelectedBtnClick()
//                    failList.compactMap({ device in self.showRestoreData.first(where: { $0.unprovisionedDevice?.peripheral.identifier == device.peripheral.identifier }) }).forEach({
//                        self.addDevice($0)
//                    })
                }
            } else {
                // TODO: 等几秒钟进入同步页面，添加设备完成后代理可能还在连接中
                // 恢复设备后是否有同步失败的设备
                if allDevices.contains(where: { $0.addState == .syncFailed }) {
                    syncBtnAction()
                } else {
                    dismiss()
                }
            }
        }
    }
    
    /// 检查设备地址是否足够
    private func checkDeviceAddressesAreSufficient(devices: [DeviceRestoreData]) {
        
        let bleConnectCount = max(showDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        for (index, device) in devices.enumerated() {
            if index < (5 - bleConnectCount) {
                device.unprovisionedDevice?.addState = .addConnecting
            }else {
                device.unprovisionedDevice?.addState = .wait
            }
            device.unprovisionedDevice?.selectedState = .disabled
            if let unprovisionedDevice = device.unprovisionedDevice {
                reloadDeviceState(unprovisionedDevice)
            }
        }
        self.updateUIState()
        
        DispatchQueue.global().async {
            // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
            let estimatedAddressCount = devices.reduce(0, { (result, device) in result + (device.unprovisionedDevice?.elementCount ?? 0) })
            // 可用地址数量
            let availableUnicastCount = MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.site.meshUUID)
            
            // 检查剩余地址是否足够添加设备
            guard availableUnicastCount >= estimatedAddressCount else {
                
                // 获取网络内已存在的设备地址数量
                let existingAddressCount = Node.loadAddresses(meshUUID: self.site.meshUUID).count
                // 申请的地址数量
                let applyAddressCount = estimatedAddressCount - availableUnicastCount + Int(Float(existingAddressCount) * 0.2)
                
                // 地址不够
                // 手机是否联网
                guard NetworkRequest.shared.networkable else {
                    // 未联网提示联网以获取地址
                    self.space?.applyDeviceAddressCount = applyAddressCount
                    self.space?.save()
                    
                    DispatchQueue.main.async {
//                        XWHUDManager.hide()
                        devices.forEach({
                            if let unprovisionedDevice = $0.unprovisionedDevice {
                                unprovisionedDevice.addState = .none
                                unprovisionedDevice.selectedState = .selected
                                self.reloadDeviceState(unprovisionedDevice)
                            }
                        })
                        self.updateUIState()
                        SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                            if NetworkRequest.shared.networkable {
                                self?.space?.applyDeviceAddressCount = nil
                                self?.space?.save()
                                self?.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
                            }
                        })]).show()
                    }
                    return
                }
                // 向服务器申请地址
                DispatchQueue.main.async {
//                    XWHUDManager.hide()
                    self.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount, devices: devices)
                }
                return
            }
            DispatchQueue.main.async {
                XWHUDManager.hide()
                devices.forEach({
                    self.addDevice($0)
                })
            }
        }
    }
    
    /// 申请设备地址请求
    /// - Parameters:
    ///   - applyAddressCount: 申请地址数量
    ///   - devices: 需要添加的设备
    private func applyDeviceAddressesRequest(applyAddressCount: Int, devices: [DeviceRestoreData] = []) {

        self.applyDeviceAddress = true
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.applyAddress(siteId: self.site.id, type: .device, number: applyAddressCount)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            self.applyDeviceAddress = false
            switch result {
            case .success(let repsonsed):
                // 新增地址
                if let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                    self.site.setProvisioner(provisionerData: provisionerData)
                    // 继续添加设备
                    devices.forEach({
                        self.addDevice($0)
                    })
                }else {
                    devices.forEach({
                        if let unprovisionedDevice = $0.unprovisionedDevice {
                            unprovisionedDevice.addState = .none
                            unprovisionedDevice.selectedState = .selected
                            self.reloadDeviceState(unprovisionedDevice)
                        }
                    })
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
                devices.forEach({
                    if let unprovisionedDevice = $0.unprovisionedDevice {
                        unprovisionedDevice.addState = .none
                        unprovisionedDevice.selectedState = .selected
                        self.reloadDeviceState(unprovisionedDevice)
                    }
                })
                self.updateUIState()
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
       
    }
    
    
    // MARK: - Action
    /// 扫描
    @objc private func scanBtnClick(sender: UIButton) {
        
        if self.state == .adding || self.state == .identifying {
            // 提示设备正在操作中，不能扫描
//            XWHUDManager.showTipHUD(inView: "scan_disable_adding".localizedString, isLineFeed: true)
            return
        }
//        if self.state == .identifying {
//            // 提示设备正在操作中，不能扫描
//            XWHUDManager.showTipHUD(inView: "scan_disable_identify".localizedString, isLineFeed: true)
//            return
//        }
        
        sender.isSelected = !sender.isSelected
        if sender.isSelected {
//            sender.setTitle("stop".localizedString, for: .normal)
            startScan()
        }else {
//            sender.setTitle("scan".localizedString, for: .normal)
            stopScan()
            DispatchQueue.main.async {
                NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
            }
        }
    }
    
    /// 全选/取消全选
    @objc private func selectAllBtnClick(sender: UIButton) {

        sender.isSelected = !sender.isSelected
        
        let canAddDevices = showDevices.filter({ $0.selectedState != .disabled && !($0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting) })

        if sender.isSelected {
            canAddDevices.forEach({ $0.selectedState = .selected })
//            selectCountLabel.text = "\(devices.count)/\(devices.count)"
        }else {
            canAddDevices.forEach({ $0.selectedState = .unselected })
            
//            selectCountLabel.text = "0/\(devices.count)"
        }
        updateFooterViewState()
        tableView.reloadData()
    }
    
    /// 批量添加
    @objc private func addSelectedBtnClick() {
        
        var selectDeviceDatas: [DeviceRestoreData] = []
        showSections.forEach { section in
            selectDeviceDatas.append(contentsOf: section.restoreDatas.filter({ $0.unprovisionedDevice != nil && $0.unprovisionedDevice?.selectedState == .selected }))
        }
        recordPendingBatteryPowerSwitchRestoreLinkGroups(for: selectDeviceDatas)
        checkDeviceAddressesAreSufficient(devices: selectDeviceDatas)
//        selectDeviceDatas.forEach { device in
//            addDevice(device)
//        }
    }
    
    /// 隐藏添加结果view
    @objc private func closeBtnClick() {
        addResultView.isHidden = true
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
    }
    
    /// 停止添加（取消正在排队的设备）
    @objc private func stopAddBtnClick() {
        guard state == .adding else {
            return
        }
        
        MeshAPI.cancelFastAddAwaitOperations()

        let waitDevices = showDevices.filter({ $0.addState == .wait })
        waitDevices.forEach({
            $0.addState = .none
            $0.selectedState = .selected
        })
        tableView.reloadData()
        updateUIState()
    }
    
    /// 点击同步设备
    @objc private func syncBtnAction() {
        
        let syncFailedDevices = allDevices.filter({ $0.addState == .syncFailed })
        let syncFailedNodes = syncFailedDevices.compactMap({ MeshNetworkManager.instance.meshNetwork?.node(withAddress: $0.address) })
//        restoreNodes.filter({ $0.needSync })
        guard syncFailedNodes.count > 0 else {
            return
        }
        let vc = SyncDevicesViewController(type: .devices(syncFailedNodes))
        vc.automationRestore = automationRestore
        vc.syncSuccessCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.hideAutomaticHud()
            if self.automationRestore, case .specified = restoreMode {
                self.deviceRestoreCallback?(self.restoreNodes, self.automationRestore)
                self.navigationController?.popToViewController(vcClass: BleFirmwareUpdateViewController.classForCoder())
            }else {
                self.navigationController?.popViewController(animated: true)
                syncFailedDevices.forEach { device in
                    if let node = syncFailedNodes.first(where: { $0.primaryUnicastAddress == device.address }), !node.needSync {
                        device.addState = .success
                    }
                }
                self.tableView.reloadData()
                self.updateUIState()
            }
        }
        vc.backActionCallback = {[weak self] _ in
            guard let self = self else { return }
            self.navigationController?.popViewController(animated: true)
            syncFailedDevices.forEach { device in
                if let node = syncFailedNodes.first(where: { $0.primaryUnicastAddress == device.address }), !node.needSync {
                    device.addState = .success
                }
            }
            self.tableView.reloadData()
            self.updateUIState()
        }
        navigationController?.pushViewController(vc, animated: true)
    }

    // MARK: - Scan Timer
    private func startScanTimer() {
        scanTimer = LCWeakTimer.scheduledTimer(timeInterval: 10, aTarget: self, selector: #selector(showDeviceNotFound), userInfo: nil, repeats: true)
        RunLoop.current.add(scanTimer!, forMode: .common)
    }
    
    private func stopScanTimer() {
        scanTimer?.invalidate()
        scanTimer = nil
        hideDeviceNotFound()
    }
    
    /// 显示找不到设备提示
    @objc private func showDeviceNotFound() {
        
        view.showEmptyDataView(imageName: "device_found_empty", title: "device_scan_notfound_title".localizedString, tipText: "device_scan_notfound_message".localizedString)
        
        if let emptyView = view.emptyView {
            emptyView.contentView.snp.remakeConstraints { make in
                make.centerY.equalToSuperview()
                make.left.equalTo(SCRXFrom(16))
                make.right.equalTo(SCRXFrom(-16))
            }
            emptyView.contentView.layer.cornerRadius = SCRYFrom(20)
            emptyView.contentView.backgroundColor = .white
            emptyView.tipLabel.textAlignment = .left
//            emptyView.tipLabel.lineBreakMode = .byClipping
            emptyView.tipLabel.textColor = RGB(148, 163, 184)
            emptyView.tipLabel.snp.remakeConstraints { make in
                make.left.equalTo(SCRXFrom(20))
                make.right.equalTo(SCRXFrom(-20))
                make.top.equalTo(emptyView.titleLabel.snp.bottom).offset(SCRYFrom(16))
                make.bottom.equalTo(SCRYFrom(-28))
            }
//            if !automationRestore {
                let shadeView = UIView(frame: view.bounds)
                shadeView.backgroundColor = RGB(0, 0, 0, 0.4)
                emptyView.insertSubview(shadeView, belowSubview: emptyView.contentView)
//            }
            if isIPad && self.automationRestore {
                shadeView.layer.cornerRadius = 20
            }
        }
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
            self.perform(#selector(self.hideDeviceNotFound), with: nil, afterDelay: 5)
        }
        
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice) {
        
        if let sectionIndex = showSections.firstIndex(where: { $0.restoreDatas.contains(where: { $0.unprovisionedDevice == device }) }), let row = showSections[sectionIndex].restoreDatas.firstIndex(where: { $0.unprovisionedDevice == device }) {
            if let cell = tableView.cellForRow(at: IndexPath(row: row, section: sectionIndex)) as? DeviceAddViewCell {
                cell.device = device
                if device.addState == .addConnecting || device.addState == .adding {
                    cell.addStateLabel.isHidden = true
                    cell.stateImageView.snp.updateConstraints { make in
                        make.width.height.equalTo(30)
                    }
                }
                cell.selectImageView.isHidden = false
            }else {
                tableView.reloadRows(at: [IndexPath(row: row, section: sectionIndex)], with: .none)
            }
        }else {
            tableView.reloadData()
        }
    }
    
    /// 隐藏找不到设备提示
    @objc private func hideDeviceNotFound() {
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
        }
        view.hideEmptyDataView()
    }
    
    /// 更新底部view数量状态
    private func updateFooterViewState() {
        let selectDevices = showDevices.filter({ $0.selectedState == .selected })
        let enableDevices = showDevices.filter({ $0.selectedState != .disabled })
        footerView.selectCountLabel.text = "\(selectDevices.count)/\(enableDevices.count)"
        if !enableDevices.isEmpty && selectDevices.count >= enableDevices.count {
            footerView.selectAllBtn.isSelected = true
        }else {
            footerView.selectAllBtn.isSelected = false
        }
        footerView.addSelectedBtn.isEnabled = selectDevices.count > 0
    }
    
    /// 更新UI
    private func updateUIState() {
        navigationBackBtn.isHidden = false
        self.navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        // 添加设备中

        if showDevices.contains(where: { $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }) {
            state = .adding
            navigationBackBtn.isHidden = true
            self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
        }else if showDevices.contains(where: { $0.addState == .identifyConnecting || $0.addState == .identifying }) { // identify中
            state = .identifying
        }else if showDevices.contains(where: { $0.addState == .success || $0.addState == .failed || $0.addState == .syncFailed }) { // 操作完成（add）
            state = .addFineshed
        }else if state != .scanning {
            state = .none
        }
        // 未操作、操作成功可以筛选信号
        rssiSlider.isEnabled = state == .none || state == .addFineshed
        scanBtn.isEnabled = state == .none || state == .scanning || state == .addFineshed
        
//        if rssiSlider.isEnabled {
//            rssiSlider.setThumbImage(UIImage(named: "slider_point"), for: .normal)
//            rssiSlider.minimumTrackTintColor = Slider_Color
//        }else {
//            rssiSlider.setThumbImage(UIImage(named: "slider_point_disable"), for: .normal)
//            rssiSlider.minimumTrackTintColor = Slider_Color.withAlphaComponent(0.5)
//        }
        
        UIApplication.shared.isIdleTimerDisabled = false
        
        footerView.selectAllBtn.isHidden = false
        footerView.selectAllLabel.text = "select_all".localizedString
        footerView.addSelectedBtn.isHidden = false
        footerView.syncBtn.isHidden = true
        if footerView.frame == .zero {
            footerView.layoutIfNeeded()
        }
        
        switch state {
        case .none:
            footerView.isHidden = false
            addResultView.isHidden = true
            updateFooterViewState()
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
        case .scanning:
            footerView.isHidden = false
            footerView.selectAllBtn.isHidden = true
            footerView.selectAllLabel.text = "devices_found".localizedString
            footerView.addSelectedBtn.isHidden = true
            switch self.restoreMode {
            case .default:
                footerView.selectCountLabel.text = "\(showDevices.count)"
            case .specified(let nodes):
                footerView.selectCountLabel.text = "\(showDevices.count)/\(pendingRestoreNodes(from: nodes).count)"
            }
            
            tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: footerView.height + SCRYFrom(8), right: 0)
            addResultView.isHidden = true
        case .identifying:
            break
        case .adding, .addFineshed:
            footerView.isHidden = false
            updateFooterViewState()
            if state == .adding {
                addResultView.isHidden = false
                tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: addResultView.height + footerView.height + SCRYFrom(8), right: 0)
                addResultView.closeBtn.isHidden = true
                addResultView.stopAddBtn.isHidden = !showDevices.contains(where: { $0.addState == .wait})
                // 添加中设置屏幕常亮
                UIApplication.shared.isIdleTimerDisabled = true
            }else {
                addResultView.closeBtn.isHidden = false
                addResultView.stopAddBtn.isHidden = true
            }
            
            let successCount = allDevices.filter({ $0.addState == .success }).count
            let failedCount = allDevices.filter({ $0.addState == .failed }).count
            let syncFailedCount = allDevices.filter({ $0.addState == .syncFailed }).count
            addResultView.successCountLabel.text = "\("successfully".localizedString) : \(successCount)"
            addResultView.failedCountLabel.text = "\(failedCount)"
            if syncFailedCount > 0 {
                addResultView.syncFailedLabel.isHidden = false
                addResultView.syncFailedCountLabel.isHidden = false
                addResultView.syncFailedCountLabel.text = "\(syncFailedCount)"
                self.navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            }else {
                addResultView.syncFailedLabel.isHidden = true
                addResultView.syncFailedCountLabel.isHidden = true
            }
            
            if syncFailedCount > 0 && state == .addFineshed {
                footerView.syncBtn.isHidden = false
            }else {
                footerView.syncBtn.isHidden = true
            }
        }
        
    }
    
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        print(changeRSSIRange)
        selectRSSIRange = changeRSSIRange
        // 筛选展示的设备
//        showDevices = scanDevices.filter({ showDeviceTypes.contains($0.deviceType) && selectRSSIRange.contains($0.rssi.intValue) })

        farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
        nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
        
        // 筛选展示的设备
        var currentShowSections: [DeviceRestoreSection] = []
        sections.forEach { section in
            let devices = section.restoreDatas.filter({ $0.unprovisionedDevice == nil || selectRSSIRange.contains($0.unprovisionedDevice!.rssi.intValue) })
            if devices.count > 0 {
                currentShowSections.append(DeviceRestoreSection(group: section.group, restoreDatas: devices))
            }
        }
        showSections = currentShowSections
        
        updateFooterViewState()
        tableView.reloadData()
    }
    
    
    // MARK: - UI
    
    private func setupUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
//        let navigationHeight = (navigationController?.navigationBar.frame.maxY ?? kNavigationHeight)
        headerView.snp.makeConstraints { make in
            make.left.right.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide)
//            make.top.equalTo(kNavigationHeight)
            make.height.equalTo(SCRYFrom(64))
        }
        
        scanBtn = UIButton(title: "scan".localizedString, titleSize: 13, titleColor: Bottom_Done_Color, normalImageName: "device_scan", target: self, action: #selector(scanBtnClick))
        scanBtn.setTitle("stop".localizedString, for: .selected)
        scanBtn.setTitleColor(Bar_Color.withAlphaComponent(0.5), for: .disabled)
        scanBtn.layer.cornerRadius = SCRYFrom(5)
        scanBtn.layer.borderWidth = 1
        scanBtn.layer.borderColor = RGB(220, 220, 220).cgColor
        scanBtn.backgroundColor = .white
        scanBtn.contentHorizontalAlignment = .left
        scanBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
        scanBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: 0)
        headerView.addSubview(scanBtn)
        scanBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(SCRYFrom(16))
            make.width.equalTo(SCRXFrom(80))
            make.height.equalTo(SCRYFrom(32))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        nearLabel.sizeToFit()
        headerView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalTo(scanBtn)
            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
        farLabel.sizeToFit()
        headerView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(scanBtn.snp.left).offset(SCRXFrom(-12))
            make.top.equalTo(nearLabel)
            make.width.equalTo(farLabel.width)
        }
        
        rssiSlider = RangeSlider()
        rssiSlider.trackHighlightTintColor = Slider_Color
        rssiSlider.trackHighlightDisableTintColor = Slider_Color.withAlphaComponent(0.5)
        rssiSlider.trackTintColor = RGB(229, 229, 229)
        rssiSlider.thumbDisableTintColor = Background_Color
        rssiSlider.minimumValue = Double(abs(filterRSSIRange.upperBound))
        rssiSlider.maximumValue = Double(abs(filterRSSIRange.lowerBound))
        rssiSlider.lowerValue = Double(abs(selectRSSIRange.upperBound))
        rssiSlider.upperValue = Double(abs(selectRSSIRange.lowerBound))
        rssiSlider.addTarget(self, action: #selector(rssiSliderValueChanged), for: .valueChanged)
        headerView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(nearLabel.snp.right).offset(SCRXFrom(-3))
            make.right.equalTo(farLabel.snp.left).offset(SCRXFrom(3))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        
        tableView = UITableView()
        tableView.separatorStyle = .none
        tableView.rowHeight = SCRYFrom(70)
        tableView.backgroundColor = .clear
        tableView.contentInsetAdjustmentBehavior = .never
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceLightInfoSectionView.classForCoder(), forHeaderFooterViewReuseIdentifier: "header")
//        tableView.register(DeviceRestoreEmptyViewCell.classForCoder(), forCellReuseIdentifier: "emptyCell")
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(8), right: 0)
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.top.equalTo(headerView.snp.bottom)
        }
        
        footerView = DeviceAddBottomView()
        footerView.isHidden = true
        footerView.addSelectedBtn.layer.cornerRadius = SCRYFrom(20)
        footerView.addSelectedBtn.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: .light)
        footerView.addSelectedBtn.setTitle("restore_selected".localizedString, for: .normal)
        view.addSubview(footerView)
        footerView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60) + kSafeAreaBottomHeight)
        }
        footerView.selectAllBtn.addTarget(self, action: #selector(selectAllBtnClick), for: .touchUpInside)
        footerView.addSelectedBtn.addTarget(self, action: #selector(addSelectedBtnClick), for: .touchUpInside)
        let btnSize = CGSize(width: SCRXFrom(140), height: SCRYFrom(40))
        footerView.addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color), for: .normal)
        footerView.addSelectedBtn.setBackgroundImage(UIImage.image(size: btnSize, color: Bar_Color.withAlphaComponent(0.5)), for: .disabled)
        footerView.addSelectedBtn.snp.updateConstraints { make in
            make.size.equalTo(btnSize)
        }
        footerView.syncBtn.addTarget(self, action: #selector(syncBtnAction), for: .touchUpInside)
        
        addResultView = DeviceAddResultView()
        addResultView.addResultLabel.text = "restore_result".localizedString
        addResultView.isHidden = true
        view.addSubview(addResultView)
        addResultView.snp.makeConstraints { make in
            make.bottom.equalTo(footerView.snp.top).offset(SCRYFrom(-1))
            make.left.right.equalToSuperview()
            make.height.equalTo(SCRYFrom(72))
        }
        addResultView.closeBtn.addTarget(self, action: #selector(closeBtnClick), for: .touchUpInside)
        addResultView.stopAddBtn.addTarget(self, action: #selector(stopAddBtnClick), for: .touchUpInside)
        addResultView.stopAddBtn.snp.remakeConstraints { make in
            make.right.equalTo(SCRXFrom(-18))
            make.top.equalTo(SCRYFrom(7))
            make.height.equalTo(SCRYFrom(32))
        }
    }

}

extension DeviceRestoreViewController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return showSections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let sectionData = showSections[section]
        return sectionData.isShow ?sectionData.restoreDatas.count : 0
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let sectionData = showSections[indexPath.section]
//        if sectionData.restoreDatas.isEmpty {
//            let emptyCell = tableView.dequeueReusableCell(withIdentifier: "emptyCell", for: indexPath) as! DeviceRestoreEmptyViewCell
//            return emptyCell
//        }else {
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
            cell.selectionStyle = .none
            let deviceData = sectionData.restoreDatas[indexPath.row]
            //        let device = showDevices[indexPath.row]
            if let device = deviceData.unprovisionedDevice {
                cell.device = device
                if device.addState == .addConnecting || device.addState == .adding {
                    cell.addStateLabel.isHidden = true
                    cell.stateImageView.snp.updateConstraints { make in
                        make.width.height.equalTo(30)
                    }
                }
                cell.selectImageView.isHidden = false
            }else {
                cell.deviceImageView.image = UIImage(named: deviceData.node.iconName)?.withTintColor(RGB(166, 166, 166))
                cell.identifyAnimationView.isHidden = true
                cell.nameLabel.text = deviceData.node.name
                cell.macAddressLabel.text = deviceData.node.macAddress?.getMacAddressSegmentString()
                cell.identifyBtn.isEnabled = false
                cell.addBtn.isEnabled = false
                cell.identifyBtn.isHidden = false
                cell.addBtn.isHidden = false
                cell.identifyBtn.layer.borderColor = RGB(156, 163, 175, 0.5).cgColor
                cell.selectImageView.isHidden = true
                cell.stateImageView.isHidden = true
                cell.signalStrengthView.setSignalStrength(rssi: -999)
                cell.signalLabel.text = nil
            }
            cell.addBtn.setImage(UIImage(named: "device_restore"), for: .normal)
            cell.addBtn.setImage(UIImage(named: "device_restore_disable"), for: .disabled)
            cell.delegate = self
            return cell
//        }
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        guard space != nil else {
            return UIView()
        }
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "header") as! DeviceLightInfoSectionView
        let sectionData = showSections[section]
        if let group = sectionData.group {
            headerView.titleLabel.text = group.name
        }else {
            headerView.titleLabel.text = "not_in_the_group".localizedString
        }
        headerView.showImageView.isHidden = false
        headerView.showImageView.image = UIImage(named: sectionData.isShow ? "arrow_up": "arrow_down")
        headerView.sectionViewClickCallback = {
            sectionData.isShow = !sectionData.isShow
            tableView.reloadSections(IndexSet(integer: section), with: .automatic)
        }
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        if space != nil {
            return SCRYFrom(44)
        }
        return 0.01
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        
        let sectionData = showSections[indexPath.section]
        guard indexPath.row < sectionData.restoreDatas.count else {
            return
        }
        let deviceData = sectionData.restoreDatas[indexPath.row]
        guard let device = deviceData.unprovisionedDevice, device.selectedState == .unselected || device.selectedState == .selected else {
            return
        }
    
        if device.selectedState == .unselected {
            device.selectedState = .selected
        }else {
            device.selectedState = .unselected
        }
        if device.addState == .failed {
            device.addState = .none
            device.selectedState = .selected
            tableView.reloadRows(at: [indexPath], with: .none)
            updateUIState()
            
        }else {
            if let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
                switch device.selectedState {
                case .unselected:
                    cell.selectImageView.image = UIImage(named: "device_select_un")
                case .selected:
                    cell.selectImageView.image = UIImage(named: "device_select")
                case .disabled:
                    cell.selectImageView.image = UIImage(named: "device_select_disable")
                }
            }else {
                tableView.reloadRows(at: [indexPath], with: .none)
            }
        }
        
        updateFooterViewState()
    }
    
}

extension DeviceRestoreViewController: DeviceAddViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        if device.addState == .identifying {
            return
        }
        if state == .scanning {
            
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_identify".localizedString)
            return
        }
        if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: device.address), node.healthModel != nil, node.healthModel!.boundApplicationKeys.count > 0 { // 已加入网络的设备identity用mesh方式
            MeshAPI.identify(address: node.primaryUnicastAddress)
          
            cell.identifyStateLabel.text = "identifying".localizedString
            cell.identifyAnimationView.isHidden = false
//                    deviceImageView.layer.addOpacityAnimation(fromOpacity: 1, toOpacity: 0, duration: 0.5, repeatCount: 10, animationKey: "identify")
            cell.identifyAnimationView.layer.addScaleAnimation(fromScale: 0, toScale: 1, duration: 1, repeatCount: .max, timingName: .easeInEaseOut, animationKey: "identify")
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 5) {[weak self] in
                self?.reloadDeviceState(device)
            }
        }else {
            identify(device)
        }
    }
    
    /// 设备添加点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        if state == .scanning {
            XWHUDManager.showTipHUD(inView: "device_scaning_disable_add".localizedString)
            return
        }
        if let deviceData = showSections.compactMap({ $0.restoreDatas.first(where: { $0.unprovisionedDevice == device }) }).first {
//            addDevice(deviceData)
            checkDeviceAddressesAreSufficient(devices: [deviceData])
        }
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
        guard device.addState == .wait || device.addState == .failed else {
            return
        }
        if device.addState == .wait { // 等待添加
            MeshAPI.cancelFastAddAwaitOperations(devices: [device])
        }
        
        // 设备状态回归为默认状态
        device.addState = .none
        device.selectedState = .selected
        reloadDeviceState(device)
        
        updateUIState()
    }
}

extension DeviceRestoreViewController {
    /// 设备添加页面状态
    enum State {
        /// 无状态
        case none
        /// 扫描设备中
        case scanning
        /// identify中
        case identifying
        /// 添加设备中
        case adding
        /// 设备添加完成
        case addFineshed
    }
    
    /// 恢复设备模式
    enum RestoreMode {
        /// 默认（无限制）
        case `default`
        /// 指定恢复部分设备，不在内的设备不显示
        case specified(nodes: [Node])
    }

    /// 恢复设备入口过滤
    enum RestoreFilter {
        /// 不限制设备类型或归属
        case all
        /// 仅恢复 gateway 设备
        case gatewaysOnly
        /// 仅恢复当前 space 内的非 gateway 设备
        case currentSpaceNonGateways
    }
    
    /// 设备恢复数据组
    class DeviceRestoreSection {
        /// 对应组
        let group: Group?
        /// 恢复数据list
        var restoreDatas: [DeviceRestoreData]
        /// 是否展开
        var isShow: Bool = true
        
        init(group: Group?, restoreDatas: [DeviceRestoreData]) {
            self.group = group
            self.restoreDatas = restoreDatas
        }
        
    }
    
    /// 设备恢复数据
    class DeviceRestoreData {
        /// 对应节点
        let node: Node
        /// 未配网的设备
        var unprovisionedDevice: ProvisioningDevice?
        
        init(node: Node, unprovisionedDevice: ProvisioningDevice? = nil) {
            self.node = node
            self.unprovisionedDevice = unprovisionedDevice
        }
    }
    
    
}
