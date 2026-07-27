//
//  DeviceAddProfessionalModeController.swift
//  SunSmart
//
//  Created by yuankehong on 2025/6/19.
//

import UIKit
import NordicSigMeshSDK
import SwiftyJSON
import AVFAudio

class DeviceAddProfessionalModeController: UIViewController {

    /// 添加模式
    enum AddMode {
        
        var title: String {
            switch self {
            case .motionSensing:
                return "device_add_mode_motionSensing".localizedString
            case .lightSening:
                return "device_add_light_sensing".localizedString
            case .manual:
                return "device_add_mode_manual".localizedString
            case .rssiRange:
                return "device_add_mode_rssiRange".localizedString
            }
        }
        
        /// 移动感应
        case motionSensing
        /// 光照感应
        case lightSening
        /// 手动添加
        case manual
        /// 信号范围
        case rssiRange
    }
    
    /// 组类型
    enum SectionType {
        /// rssi内
        case inRSSI
        /// 不在rssi内
        case remainingRSSI
    }
    
    
    /// header
    private var headerView: UIView!
    private var nearLabel: UILabel!
    private var rssiSlider: RangeSlider!
    private var farLabel: UILabel!
    
    /// 搜索的设备list view（iPad）
    private var devicesFoundView: UIView?
    private var devicesFoundLabel: UILabel?
    private var rssiRangeLabel: UILabel?
    
    private var addModeBtn: UIButton!
    private var pauseBtn: UIButton!
    private var settingsBtn: UIButton!
    private var settingsTipView: UIView!
    private var scanBtn: UIButton!
    
    private var addModeBtnMaxWidth: CGFloat = SCRXFrom(192)
    
    private var messageLabel: UILabel?
    /// 设备列表
    private var tableView: UITableView!
    
    
    private var bottomView: UIView!
    private var lineView: UIView!
    private var candidateCountLabel: UILabel?
    private var showDeviceListBtn: UIButton?
    
    private var selectRSSIRange: ClosedRange<Int> = -65 ... -25
    /// 筛选信号值范围
    private let filterRSSIRange: ClosedRange<Int> = -100 ... -25
    /// 添加模式
    private var addMode: AddMode = .manual
    /// 扫描设备定时器
    private var scanTimer: Timer?
    /// 刷新信号定时器
    private var rssiSortTimer: Timer?
    
    /// 添加设备页面状态
    private var state: DeviceAddState = .none
    
    /// 找到的设备list
    private var scanDevices: [ProvisioningDevice] = []
    /// rssi信号范围内的设备
    private var inRSSIDevices: [ProvisioningDevice] = []
    /// 不在rssi信号范围内的设备
    private var remainingRSSIDevices: [ProvisioningDevice] = []
    /// 候选的设备list
    private var candidateDevices: [ProvisioningDevice] = []
    
    private var sectionTypes: [SectionType] = [.inRSSI, .remainingRSSI]
    
    /// identify中的设备
    private var identifyDevice: ProvisioningDevice?
    /// 是否刷新
    private var isRefresh: Bool = true
    /// 刷新数据中
    private var reloadDataing: Bool = false
    /// 预选view
    private var candidateView: DeviceAddCandidateDeviceListView!
    /// 参数设置view
    private var parameterSettingsView :DeviceAddParameterSettingsView?
    /// 无定向广播
    private let broadcaster = BluetoothBroadcaster()
    /// 广播时设备配置持续时长
    private let broadcasterDuration: UInt8 = 2
    /// 添加目标
    private var addTarget: AddDeviceToTarget!
    /// 添加成功的节点
    private var addSuccessNodes: [Node] = []
    private var pendingBatteryPowerSwitchInitialBatteryReads: [BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest] = []
    private var fastAddGroupSyncPlans: [Address: DeviceGroupFastAddSyncPlan] = [:]
    private var failedFastAddGroupSyncNodeAddresses: Set<Address> = []
    private var emergencyFireDefaultConfigurationMessageHandles: [Address: [MeshMessageHandle]] = [:]
    private var failedEmergencyFireDefaultConfigurationNodeAddresses: Set<Address> = []
    private var emergencyFireGroupMutationMessageHandles: [Address: [MeshMessageHandle]] = [:]
    private var failedEmergencyFireGroupMutationNodeAddresses: Set<Address> = []
    private var fastAddGroupEffectiveMemberCount: Int?
    private var groupMemberAddedProfileSyncContext: GroupProfileSyncContext {
        GroupProfileSyncContext(reason: .memberAdded)
    }
    private var batteryPowerSwitchAddConfigurations: [Address: PJEightKeySwitchData] = [:]
    private var failedBatteryPowerSwitchAddConfigurationAddresses: Set<Address> = []
    private var failedBatteryPowerSwitchAddConfigurationReasons: [Address: String] = [:]
    /// 系统音量监听者
    private var systemVolumeObservation: NSKeyValueObservation?
    
    /// 其它网关数据
    private var otherGateways: [GatewayModel] = []
    
    let space: SpaceData
    
    /// 外部传入指定添加该到group
    var appointGroup: Group?
    
    /// 外部传入指定dognle设备绑定该到dognle数据
    var forceBindToDongle: DeviceDongleData?
    /// 添加完成后绑定到外部业务对象。默认 nil，不改变老设备添加流程。
    var bindTarget: AddDeviceBindTarget?
    /// Device1.5 注入的通用添加限制策略，不改变默认老业务流程。
    var addBehavior: PJDevicesAddBehavior?
    
    /// 已存在的dognle数据list
    private var dongles: [DeviceDongleData] = []
    /// 添加状态回调 是否添加中
    var deviceStateCallback: ((Bool)->Void)?
    var deviceAddCallback: (([Node])->Void)?
    
    /// 是否在分配设备地址
    private var applyDeviceAddress: Bool = false

    private var bindToEmerFire: DeviceEmerFireData? {
        if case .emergencyFire(let device) = bindTarget {
            return device
        }
        return nil
    }

    private var bindToBatteryPowerSwitch: PJEightKeySwitchData? {
        if case .batteryPowerSwitch(let switchData) = bindTarget {
            return switchData
        }
        return nil
    }

    private var isVirtualAddTarget: Bool {
        if bindTarget != nil {
            return true
        }
        if case .dongle = addTarget {
            return true
        }
        return false
    }

    private var hidesBatchSelectionControls: Bool {
        isVirtualAddTarget
    }

    private var virtualTargetAddLocked: Bool {
        guard isVirtualAddTarget else {
            return false
        }
        return (scanDevices + candidateDevices).contains {
            $0.addState.blocksVirtualTargetSingleAdd
        }
    }

    private func canStartVirtualTargetAdd() -> Bool {
        guard isVirtualAddTarget else {
            return true
        }
        return !virtualTargetAddLocked
    }

    private var lockedCategoryIndexForCurrentTarget: Int? {
        if bindToBatteryPowerSwitch != nil {
            return 1
        }
        if bindToEmerFire != nil {
            return 3
        }
        if case .dongle = addTarget {
            return 3
        }
        return nil
    }

    private var unboundBatteryPowerSwitches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs
            .unboundVirtualPowerSwitchAddTargets(kind: .battery)
    }

    private var unboundACPowerSwitches: [PJEightKeySwitchData] {
        MeshNetworkManager.instance.switchs
            .unboundVirtualPowerSwitchAddTargets(kind: .ac)
    }

    private var unboundEmergencyFireDevices: [DeviceEmerFireData] {
        DeviceEmerFireStore.shared.devices(in: space).filter { $0.bindNodeAddress == nil }
    }

    private var unboundDongles: [DeviceDongleData] {
        MeshNetworkManager.instance.dongles.filter { $0.bindNodeAddress == nil }
    }

    private var addTargetNameOverride: String? {
        bindTarget?.name
    }

    private var currentAddGroup: Group? {
        if case .group(let group) = addTarget {
            return group
        }
        return nil
    }

    private var currentTargetSelection: DeviceAddTargetSelection {
        if let bindToBatteryPowerSwitch {
            return bindToBatteryPowerSwitch.powerSwitchKind == .ac
                ? .acPowerSwitch(bindToBatteryPowerSwitch)
                : .batteryPowerSwitch(bindToBatteryPowerSwitch)
        }
        if let bindToEmerFire {
            return .emergencyFire(bindToEmerFire)
        }
        switch addTarget {
        case .group(let group):
            return .group(group)
        case .dongle(let dongle):
            return .dongle(dongle)
        default:
            return .space
        }
    }

    private var isSingleSelectionMode: Bool {
        bindTarget != nil || addBehavior?.selectionMode == .single
    }

    private var displayedCandidateDevices: [ProvisioningDevice] {
        candidateDevices.filter { isVisibleDeviceInCurrentAddMode($0) }
    }

    private var displayedCandidateCount: Int {
        displayedCandidateDevices.filter { $0.addState != .success }.count
    }

    private func isVisibleDeviceInCurrentAddMode(_ device: ProvisioningDevice) -> Bool {
        let isEmergencySignController = Node.isEmergencySignController(
            companyIdentifier: device.cid,
            productIdentifier: device.pid
        )

        switch addMode {
        case .manual, .rssiRange:
            return true
        case .motionSensing, .lightSening:
            return !isEmergencySignController && (device.deviceType == .light || device.deviceType == .sensor)
        }
    }

    private func syncCandidateDevicesForCurrentAddMode() {
        guard candidateView != nil else {
            return
        }
        candidateView.candidateDevices = displayedCandidateDevices
        candidateCountLabel?.text = "\(displayedCandidateCount)"
    }

    private func canSelectEmergencyFireVirtualTarget(for deviceTypes: [Node.DeviceType]) -> Bool {
        addBehavior?.allowsEmergencyFireVirtualTargetSelection == true && deviceTypes.contains(.emergencyController)
    }

    private var shouldBlockEmergencyControllerForCurrentTarget: Bool {
        guard addBehavior?.allowsEmergencyFireVirtualTargetSelection == true else {
            return false
        }
        if bindTarget != nil {
            return false
        }
        switch addTarget {
        case .group, .dongle:
            return true
        default:
            return false
        }
    }

    private var isAddingToGroupTarget: Bool {
        if case .group = addTarget {
            return true
        }
        return false
    }

    private func shouldBlockDeviceTypeForGroupTarget(_ deviceType: Node.DeviceType) -> Bool {
        guard isAddingToGroupTarget else {
            return false
        }
        switch deviceType {
        case .switches, .dongle, .gateway, .emergencyController, .unknown:
            return true
        default:
            return false
        }
    }

    private func shouldRestoreDeviceTypeAfterLeavingGroupTarget(_ deviceType: Node.DeviceType) -> Bool {
        guard !isAddingToGroupTarget else {
            return false
        }
        switch deviceType {
        case .switches, .dongle, .gateway, .emergencyController:
            return true
        default:
            return false
        }
    }
    
    init(space: SpaceData) {
        self.space = space
        super.init(nibName: nil, bundle: nil)
        
        addTarget = .space(space)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Background_Color
        
        if let group = self.appointGroup {
            addTarget = .group(group)
        }else if let dongle = self.forceBindToDongle {
            addTarget = .dongle(dongle)
        }
        dongles = MeshNetworkManager.instance.dongles
        
        if isIPad {
            if self.presentingViewController != nil {
                addModeBtnMaxWidth = SCRXFrom(160)
            }else {
                addModeBtnMaxWidth = SCRXFrom(200)
            }
        }
        setupUI()
        syncCandidateTargetState()
        
        addObserver()
    }

    private func showAddBehaviorTip() {
        XWHUDManager.showTipHUD(forbiddenSelectionTip, isLineFeed: true)
    }

    private var forbiddenSelectionTip: String {
        let tip = addBehavior?.forbiddenSelectionTip ?? ""
        return tip.isEmpty ? "You can't choose other devices." : tip
    }

    private func showInvalidDeviceTypeTip() {
        guard let tip = addBehavior?.forbiddenDeviceTypeTip, !tip.isEmpty else {
            return
        }
        XWHUDManager.showTipHUD(tip, isLineFeed: true)
    }

    private func isAllowedDeviceType(_ deviceType: Node.DeviceType) -> Bool {
        if let bindTarget {
            return bindTarget.allowedDeviceTypes.contains(deviceType)
        }
        if case .dongle = addTarget {
            return deviceType == .dongle
        }
        guard let addBehavior else {
            return true
        }
        guard !addBehavior.allowedTypes.isEmpty else {
            return true
        }
        return addBehavior.allowedTypes.contains {
            switch ($0, deviceType) {
            case (.lights, .light), (.switches, .switches), (.sensors, .sensor):
                return true
            case (.others, .dongle), (.others, .gateway), (.others, .emergencyController), (.others, .unknown):
                return true
            default:
                return false
            }
        }
    }

    private func isBlockedDeviceType(_ deviceType: Node.DeviceType) -> Bool {
        if let bindTarget {
            return !bindTarget.allowedDeviceTypes.contains(deviceType)
        }
        if case .dongle = addTarget {
            return deviceType != .dongle
        }
        if shouldBlockDeviceTypeForGroupTarget(deviceType) {
            return true
        }
        if shouldBlockEmergencyControllerForCurrentTarget, deviceType == .emergencyController {
            return true
        }
        return addBehavior?.blockedDeviceTypes.contains(deviceType) == true
    }

    private func isSelectableDeviceType(_ deviceType: Node.DeviceType) -> Bool {
        isAllowedDeviceType(deviceType) && !isBlockedDeviceType(deviceType)
    }

    private func isAllowedDevice(_ device: ProvisioningDevice) -> Bool {
        if let bindTarget {
            return bindTarget.allows(device)
        }
        if case .dongle = addTarget {
            return device.deviceType == .dongle
        }
        let deviceType = device.deviceType
        return isAllowedDeviceType(deviceType)
    }

    private func isBlockedDevice(_ device: ProvisioningDevice) -> Bool {
        if let bindTarget {
            return !bindTarget.allows(device)
        }
        if case .dongle = addTarget {
            return device.deviceType != .dongle
        }
        let deviceType = device.deviceType
        return isBlockedDeviceType(deviceType)
    }

    private func isSelectableDevice(_ device: ProvisioningDevice) -> Bool {
        isAllowedDevice(device) && !isBlockedDevice(device)
    }

    private func applySelectableState(to device: ProvisioningDevice) {
        if bindToBatteryPowerSwitch == nil,
           device.isPowerSwitch,
           MeshNetworkManager.instance.switchs.count >= 16 {
            device.selectedState = .disabled
            return
        }
        if addBehavior == nil,
           bindTarget == nil,
           !isVirtualAddTarget,
           device.selectedState == .disabled,
           shouldRestoreDeviceTypeAfterLeavingGroupTarget(device.deviceType) {
            device.selectedState = .unselected
            return
        }
        guard addBehavior != nil || bindTarget != nil || isVirtualAddTarget || isAddingToGroupTarget else {
            return
        }
        if device.addState == .wait || device.addState == .adding || device.addState == .addConnecting || device.addState == .success {
            return
        }
        // 这里仅收敛外部注入的禁选设备类型，不改变默认展示与 identify 行为。
        if isSelectableDevice(device) {
            if device.selectedState == .disabled {
                device.selectedState = .unselected
            }
            if hidesBatchSelectionControls, device.selectedState == .selected {
                device.selectedState = .unselected
            }
        } else {
            device.selectedState = .disabled
        }
        if isSingleSelectionMode, device.selectedState == .selected {
            applySingleSelectionIfNeeded(for: device)
        }
    }

    private func showDisabledDeviceTip(_ device: ProvisioningDevice) {
        if bindToBatteryPowerSwitch == nil,
           device.isPowerSwitch,
           MeshNetworkManager.instance.switchs.count >= 16 {
            showBatteryPowerSwitchLimitTip()
        } else {
            showInvalidDeviceTypeTip()
        }
    }

    private func showBatteryPowerSwitchLimitTip() {
        SRAlertView(
            title: "notification".localizedString,
            message: "switchs_overrun_message".localizedString,
            actions: [SRAlertAction(title: "GOT_IT".localizedString)]
        ).show()
    }

    private func isBatteryPowerSwitchLimitExceeded(for devices: [ProvisioningDevice]) -> Bool {
        guard bindToBatteryPowerSwitch == nil else {
            return false
        }
        let powerSwitchCount = devices.filter { $0.isPowerSwitch }.count
        return powerSwitchCount > 0 && MeshNetworkManager.instance.switchs.count + powerSwitchCount > 16
    }

    private func validateBatteryPowerSwitchLimit(for devices: [ProvisioningDevice]) -> Bool {
        guard !isBatteryPowerSwitchLimitExceeded(for: devices) else {
            showBatteryPowerSwitchLimitTip()
            return false
        }
        return true
    }

    private func restoreDevicesForAddRetry(_ devices: [ProvisioningDevice]) {
        resetFastAddGroupSyncBatch()
        devices.forEach {
            $0.addState = .none
            $0.selectedState = .selected
            reloadDeviceState($0)
        }
        updateUIState()
    }

    private func finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect() {
        let requests = pendingBatteryPowerSwitchInitialBatteryReads
        pendingBatteryPowerSwitchInitialBatteryReads.removeAll()
        BatteryPowerSwitchAddConfiguration.readInitialBatteryLevelsAndDisconnect(
            requests,
            fallbackDisconnectNodes: addSuccessNodes
        )
    }

    private func prepareFastAddGroupSyncBatch(devices: [ProvisioningDevice]) {
        resetFastAddGroupSyncBatch()
        guard let group = currentAddGroup else {
            return
        }
        fastAddGroupEffectiveMemberCount = group.nodes.count + devices.count
    }

    private func resetFastAddGroupSyncBatch() {
        fastAddGroupSyncPlans.removeAll()
        failedFastAddGroupSyncNodeAddresses.removeAll()
        emergencyFireDefaultConfigurationMessageHandles.removeAll()
        failedEmergencyFireDefaultConfigurationNodeAddresses.removeAll()
        emergencyFireGroupMutationMessageHandles.removeAll()
        failedEmergencyFireGroupMutationNodeAddresses.removeAll()
        fastAddGroupEffectiveMemberCount = nil
    }

    private func registerFastAddGroupSyncPlan(_ plan: DeviceGroupFastAddSyncPlan) {
        fastAddGroupSyncPlans[plan.nodeAddress] = plan
        failedFastAddGroupSyncNodeAddresses.remove(plan.nodeAddress)
    }

    private func fastAddGroupSyncPlan(containing messageHandle: MeshMessageHandle) -> DeviceGroupFastAddSyncPlan? {
        fastAddGroupSyncPlans.values.first { $0.contains(messageHandle) }
    }

    private func recordFastAddGroupSyncFailure(_ plan: DeviceGroupFastAddSyncPlan) {
        failedFastAddGroupSyncNodeAddresses.insert(plan.nodeAddress)
        if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: plan.nodeAddress) {
            node.clearSyncStateCache()
        }
        plan.group.updateGroupSyncState()
    }

    private func resolveFastAddGroupSyncFailed(for node: Node) -> Bool {
        guard let plan = fastAddGroupSyncPlans.removeValue(forKey: node.primaryUnicastAddress) else {
            return resolveEmergencyFireGroupMutationFailed(for: node)
        }

        let failed = failedFastAddGroupSyncNodeAddresses.contains(node.primaryUnicastAddress)
            || plan.hasVerificationFailure
            || resolveEmergencyFireGroupMutationFailed(for: node)
        if failed {
            recordFastAddGroupSyncFailure(plan)
        }
        failedFastAddGroupSyncNodeAddresses.remove(node.primaryUnicastAddress)
        return failed
    }

    private func appendEmergencyFireControllerGroupMutationMessages(
        node: Node,
        group: Group,
        appendMessages: inout [MeshMessageHandle]
    ) {
        let items = EmergencyFireControllerSyncPlanner.makeGroupMutationItems(
            group: group,
            addNodes: [node],
            exitNodes: [],
            space: space
        )
        let handles = items.flatMap { $0.tasks.flatMap { $0.messageHandles } }
        guard !handles.isEmpty else {
            return
        }
        appendMessages.append(contentsOf: handles)
        emergencyFireGroupMutationMessageHandles[node.primaryUnicastAddress, default: []].append(contentsOf: handles)
        failedEmergencyFireGroupMutationNodeAddresses.remove(node.primaryUnicastAddress)
    }

    private func appendEmergencyFireControllerDefaultConfigurationMessages(
        controller: DeviceEmerFireData,
        appendMessages: inout [MeshMessageHandle]
    ) {
        guard let nodeAddress = controller.bindNodeAddress else {
            return
        }
        do {
            let handles = try controller.getControllerDefaultConfigurationMessageHandles(
                meshUUID: space.meshUUID,
                subnetworkId: space.meshNetworkId
            )
            guard !handles.isEmpty else {
                return
            }
            appendMessages.append(contentsOf: handles)
            emergencyFireDefaultConfigurationMessageHandles[nodeAddress, default: []].append(contentsOf: handles)
            failedEmergencyFireDefaultConfigurationNodeAddresses.remove(nodeAddress)
        } catch {
            print(error.localizedDescription)
        }
    }

    private func emergencyFireDefaultConfigurationNodeAddress(containing messageHandle: MeshMessageHandle) -> Address? {
        emergencyFireDefaultConfigurationMessageHandles.first { _, handles in
            handles.contains { $0 === messageHandle }
        }?.key
    }

    private func finishLinkedEmergencyFireControllerConfiguration(for node: Node) {
        let hadDefaultConfiguration = emergencyFireDefaultConfigurationMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil
        guard hadDefaultConfiguration,
              let controller = DeviceEmerFireStore.shared.devices(in: space).first(where: { $0.bindNodeAddress == node.primaryUnicastAddress }) else {
            return
        }
        let defaultConfigurationFailed = failedEmergencyFireDefaultConfigurationNodeAddresses.contains(node.primaryUnicastAddress)
        failedEmergencyFireDefaultConfigurationNodeAddresses.remove(node.primaryUnicastAddress)

        controller.isSynced = !defaultConfigurationFailed
        DeviceEmerFireStore.shared.save(controller)
    }

    private func emergencyFireGroupMutationNodeAddress(containing messageHandle: MeshMessageHandle) -> Address? {
        emergencyFireGroupMutationMessageHandles.first { _, handles in
            handles.contains { $0 === messageHandle }
        }?.key
    }

    private func resolveEmergencyFireGroupMutationFailed(for node: Node) -> Bool {
        guard emergencyFireGroupMutationMessageHandles.removeValue(forKey: node.primaryUnicastAddress) != nil else {
            return false
        }
        let failed = failedEmergencyFireGroupMutationNodeAddresses.contains(node.primaryUnicastAddress)
        failedEmergencyFireGroupMutationNodeAddresses.remove(node.primaryUnicastAddress)
        return failed
    }

    private func finalizeBatteryPowerSwitchAddConfiguration(
        for node: Node
    ) -> BatteryPowerSwitchAddConfiguration.InitialBatteryReadRequest? {
        guard BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) else {
            return nil
        }

        guard let switchData = batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] else {
            if bindToBatteryPowerSwitch != nil {
                failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
                failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
                return nil
            }

            if let fallbackSwitchData = MeshNetworkManager.instance
                .createDefaultSwitch(forBatteryPowerSwitch: node)?
                .batteryPowerSwitchData {
                BatteryPowerSwitchAddConfiguration.markFailed(
                    fallbackSwitchData,
                    reason: "sync_failed".localizedString
                )
                return BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
                    for: fallbackSwitchData,
                    node: node
                )
            }
            return nil
        }

        if failedBatteryPowerSwitchAddConfigurationAddresses.contains(node.primaryUnicastAddress) {
            BatteryPowerSwitchAddConfiguration.markFailed(
                switchData,
                reason: failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress]
                    ?? switchData.lastSyncFailedReason
                    ?? "sync_failed".localizedString
            )
        } else {
            BatteryPowerSwitchAddConfiguration.markSucceeded(switchData)
        }

        let request = BatteryPowerSwitchAddConfiguration.makeInitialBatteryReadRequest(
            for: switchData,
            node: node
        )

        batteryPowerSwitchAddConfigurations.removeValue(forKey: node.primaryUnicastAddress)
        failedBatteryPowerSwitchAddConfigurationAddresses.remove(node.primaryUnicastAddress)
        failedBatteryPowerSwitchAddConfigurationReasons.removeValue(forKey: node.primaryUnicastAddress)
        return request
    }

    private func shouldAllowTargetSelection() -> Bool {
        guard addBehavior?.allowsTargetSelection == false else {
            return true
        }
        return false
    }

    private func clearSelectedDevicesForVirtualTargetIfNeeded(previousWasVirtual: Bool) {
        guard isVirtualAddTarget, !previousWasVirtual else {
            return
        }
        scanDevices.forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        inRSSIDevices.forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        remainingRSSIDevices.forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        candidateDevices.forEach {
            if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
    }

    private func applyTargetSelection(_ selection: DeviceAddTargetSelection) {
        let previousWasVirtual = isVirtualAddTarget

        switch selection {
        case .space:
            addTarget = .space(space)
            bindTarget = nil
        case .group(let group):
            addTarget = .group(group)
            bindTarget = nil
        case .batteryPowerSwitch(let switchData), .acPowerSwitch(let switchData):
            addTarget = .space(space)
            bindTarget = .batteryPowerSwitch(switchData)
        case .emergencyFire(let device):
            addTarget = .space(space)
            bindTarget = .emergencyFire(device)
        case .dongle(let dongle):
            addTarget = .dongle(dongle)
            bindTarget = nil
        }

        clearSelectedDevicesForVirtualTargetIfNeeded(previousWasVirtual: previousWasVirtual)
        normalizeSelectionForCurrentTarget()
        syncCandidateTargetState()
    }

    private func resetSelectableVirtualTargetForScanIfNeeded() {
        guard shouldAllowTargetSelection(), bindTarget != nil else {
            return
        }
        addTarget = .space(space)
        bindTarget = nil
        normalizeSelectionForCurrentTarget()
        syncCandidateTargetState()
    }

    private func syncCandidateTargetState() {
        guard candidateView != nil else {
            return
        }
        candidateView.addTarget = addTarget
        candidateView.addTargetNameOverride = addTargetNameOverride
        candidateView.hidesSelectionControls = hidesBatchSelectionControls
        candidateView.virtualTargetAddLocked = virtualTargetAddLocked
        candidateView.lockedCategorySelectionTip = forbiddenSelectionTip
        candidateView.lockedCategoryIndex = lockedCategoryIndexForCurrentTarget
        candidateView.candidateDevices = displayedCandidateDevices
        candidateView.state = state
        candidateView.isRefresh = isRefresh
    }

    private func applySingleSelectionIfNeeded(for selectedDevice: ProvisioningDevice) {
        guard isSingleSelectionMode else {
            return
        }
        // 单选模式下仅保留当前设备，避免修改默认多选业务流程。
        scanDevices.forEach {
            if $0.peripheral.identifier == selectedDevice.peripheral.identifier {
                $0.selectedState = .selected
            } else if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        inRSSIDevices.forEach {
            if $0.peripheral.identifier == selectedDevice.peripheral.identifier {
                $0.selectedState = .selected
            } else if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        remainingRSSIDevices.forEach {
            if $0.peripheral.identifier == selectedDevice.peripheral.identifier {
                $0.selectedState = .selected
            } else if $0.selectedState == .selected {
                $0.selectedState = .unselected
            }
        }
        candidateDevices = candidateDevices.filter { $0.peripheral.identifier == selectedDevice.peripheral.identifier }
    }

    private func normalizeSelectionForCurrentTarget() {
        scanDevices.forEach { applySelectableState(to: $0) }
        inRSSIDevices.forEach { applySelectableState(to: $0) }
        remainingRSSIDevices.forEach { applySelectableState(to: $0) }
        candidateDevices.forEach { applySelectableState(to: $0) }
        guard isSingleSelectionMode else {
            return
        }
        let selectedDevices = (scanDevices + candidateDevices).filter { $0.selectedState == .selected }
        guard let firstSelectedDevice = selectedDevices.first else {
            return
        }
        applySingleSelectionIfNeeded(for: firstSelectedDevice)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        SystemVolumeManager.shared.startObserveVolume()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        SystemVolumeManager.shared.stopObserveVolume()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        scanDevices.removeAll()
        if state == .scanning { // 退出页面/切换停止扫描
            stopScan()
        }
        candidateDevices.removeAll()
        inRSSIDevices.removeAll()
        remainingRSSIDevices.removeAll()
//        sectionTypes.removeAll()
        syncCandidateDevicesForCurrentAddMode()
        candidateView.state = state
        tableView.reloadData()
    }
    
    deinit {
        systemVolumeObservation = nil
    }
    
    private func addObserver() {
        
        // 激活 AVAudioSession（否则监听可能无效）
//        try? AVAudioSession.sharedInstance().setActive(true, options: [])

        
        systemVolumeObservation = SystemVolumeManager.shared.observe(\.currentVolume, options: [.new], changeHandler: {[weak self] _, value in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.settingsTipView.isHidden = (value.newValue ?? 0) >= DeviceSettingsParameterData.systemMinimumVolumeRequire
            }
        })
        
    }
    
    // MARK: - Scan
    
    private func startScan() {
        
        (wm_pageController as? DeviceAddViewController)?.startScan()
        
        resetSelectableVirtualTargetForScanIfNeeded()
        state = .scanning
        scanBtn.isSelected = true
        startScanTimer()

        scanDevices.removeAll()
        candidateDevices.removeAll()
        candidateCountLabel?.text = "\(displayedCandidateCount)"
        syncCandidateDevicesForCurrentAddMode()
        candidateView.state = state
        inRSSIDevices.removeAll()
        remainingRSSIDevices.removeAll()
//        if !isIPad {
//            sectionTypes.removeAll()
//        }
        tableView.isHidden = false
        tableView.reloadData()
        isRefresh = true
        candidateView.isRefresh = isRefresh
        pauseBtn.isSelected = false
        messageLabel?.isHidden = true
        pauseBtn.isHidden = false
        bottomView.isHidden = false
        
        startBroadcasting()
        
        // 扫描中设置屏幕常亮
        UIApplication.shared.isIdleTimerDisabled = true
        
        MeshAPI.startScanDevice(.max, deviceScan: {[weak self] device in
            guard let self = self else { return }
            // 新发现设备
            if device.macAddress != nil, device.rssi.intValue >= self.filterRSSIRange.lowerBound {
                
                if let info = MeshLibManager.manager.supportDeviceInfos.first(where: { $0.companyId == device.cid && $0.productId == device.pid }) {
                    device.deviceName = info.categoryName
                    device.elementCount = info.elementCount
                    device.deviceType = Node.DeviceType(deviceCategory: info.deviceCategory)
                    device.icon = EmergencyFireControllerIconName.addListIconName(for: device.deviceType, fallback: info.iconName)
                    device.selectedState = .selected
                }else {
                    device.deviceType = .unknown
                    device.icon = "device_unknown"
                    device.selectedState = .disabled
                }
                if device.deviceType == .gateway { // 禁止space添加网关
                    return
                }
                
                self.stopScanTimer()
                
                if device.rssi.intValue > self.filterRSSIRange.upperBound {
                    device.rssi = NSNumber(value: self.filterRSSIRange.upperBound)
                }
//                if device.macAddress == "EA2CCBC2B7A0" {
//                    print("收到广播包, activity:\(device.triggerActionTypes.count > 0 ? true : false)")
//                }
                
                if (self.addMode == .lightSening || self.addMode == .motionSensing) && device.triggerActionTypes.count > 0 {
                    device.activityDate = Date()
                    print("触发了: \(device.macAddress!)")
                }
                
               
                
                var newDevice = device
                
                if let index = self.scanDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
                    let cacheDevice = self.scanDevices[index]
                    cacheDevice.updateData(device: device)
                    self.applySelectableState(to: cacheDevice)
                    newDevice = cacheDevice

                    if let index = self.candidateDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) {
                        let cacheDevice = self.candidateDevices[index]
                        cacheDevice.updateData(device: device)
                        if !self.isRefresh {
                            self.candidateView?.updateDeviceData(device: cacheDevice)
                        }
                    }
                    
                }else {
                    self.applySelectableState(to: device)
                    self.scanDevices.append(device)
                }
                
                if self.isRefresh {
                    if newDevice.selectedState != .disabled,
                       self.isSelectableDevice(newDevice),
                       self.isVisibleDeviceInCurrentAddMode(newDevice),
                       !self.candidateDevices.contains(where: { $0.peripheral.identifier.uuidString == newDevice.peripheral.identifier.uuidString }),
                       self.selectRSSIRange.contains(newDevice.rssi.intValue) {
                        switch addMode {
                        case .motionSensing:
                            if newDevice.triggerActionTypes.contains(.motionSensing) {
                                self.candidateDevices.append(newDevice)
                                self.playerNotificationAudio()
                            }
                        case .lightSening:
                            if newDevice.triggerActionTypes.contains(.lightSensing) {
                                self.candidateDevices.append(newDevice)
                                self.playerNotificationAudio()
                            }
                        case .manual:
                            break
                        case .rssiRange:
                            self.candidateDevices.append(newDevice)
                            self.playerNotificationAudio()
                        }
                    }
                    self.startRssiSortTimer()
                }else {
                    var reloadDevice = device
                    if let index = self.inRSSIDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == newDevice.peripheral.identifier.uuidString }) {
                        let cacheDevice = self.inRSSIDevices[index]
                        cacheDevice.updateData(device: newDevice)
                        reloadDevice = cacheDevice
//                        device.selectedState = cacheDevice.selectedState
//                        device.addState = cacheDevice.addState
//                        self.inRSSIDevices.replaceSubrange(index...index, with: [device])
                    }
                    
                    if let index = self.remainingRSSIDevices.firstIndex(where: { $0.peripheral.identifier.uuidString == newDevice.peripheral.identifier.uuidString }) {
                        let cacheDevice = self.remainingRSSIDevices[index]
                        cacheDevice.updateData(device: newDevice)
                        reloadDevice = cacheDevice
//                        device.selectedState = cacheDevice.selectedState
//                        device.addState = cacheDevice.addState
//                        self.remainingRSSIDevices.replaceSubrange(index...index, with: [device])
                    }
                    reloadDeviceState(reloadDevice, force: false)
                }
                
//                DispatchQueue.main.async {
//                    NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.stopScan), object: nil)
//                    self.perform(#selector(self.stopScan), with: nil, afterDelay: 8)
//                }
            }
            
        }, deviceScanFinish: nil)
    }
    
    @objc private func stopScan() {

        (wm_pageController as? DeviceAddViewController)?.stopScan()
        
        scanBtn.isSelected = false
        MeshAPI.stopScan()
        UIApplication.shared.isIdleTimerDisabled = false
        state = .none
        
        stopBroadcasting()
        // 停止扫描设备状态设置为空状态
//        scanDevices.forEach({
//            $0.addState = .none
////            reloadDeviceState($0)
//        })
        if scanDevices.count > 0 {
            messageLabel?.isHidden = true
            bottomView.isHidden = false
            tableView.isHidden = false
        }else {
            messageLabel?.isHidden = false
            bottomView.isHidden = true
            if isIPhone {
                tableView.isHidden = true
            }
        }
        pauseBtn.isHidden = true
        if isIPad {
            bottomView.isHidden = true
        }
        updateUIState()
        stopScanTimer()
        if rssiSortTimer != nil {
            devicesRssiSort()
        }else {
            tableView.reloadData()
        }
    }
    
    /// 开始无定向广播（添加模式：移动感应、光照感应）
    private func startBroadcasting() {
        
        switch self.addMode {
        case .motionSensing:
            broadcaster.startBroadcasting(type: .pirDiscoverAdd(timeout: broadcasterDuration, lightness: max(deviceSettingsParameterData.brightness.value8, 1)), interval: 0.5)
        case .lightSening:
            broadcaster.startBroadcasting(type: .ambientLightDiscoverAdd(timeout: broadcasterDuration, lightness: max(deviceSettingsParameterData.brightness.value8, 1), delta: deviceSettingsParameterData.illuminationDelta), interval: 0.5)
        default:
            break
        }
    }
    
    /// 停止无定向广播
    private func stopBroadcasting() {
        broadcaster.stopBroadcasting()
    }
    
    /// 播放添加设备通知
    private func playerNotificationAudio() {
        
        if deviceSettingsParameterData.notificationEnable {
            try? DeviceAudioManager.manager.startAudio(type: .deviceAdd, volume: deviceSettingsParameterData.volume)
        }
        if deviceSettingsParameterData.vibrationEnable {
            DeviceAudioManager.manager.vibration()
        }
    }
    
    /// 更新UI
    private func updateUIState() {
        
        if state != .scanning {
            // 添加设备中
//            if scanDevices.contains(where: { $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting }) {
//                state = .adding
//            }else if scanDevices.contains(where: { $0.addState == .success || $0.addState == .failed }) { // 操作完成（add）
//                state = .addFineshed
//            }else if state != .scanning {
//                state = .none
//            }
            
            scanBtn.isEnabled = !scanDevices.contains(where: { $0.addState == .wait || $0.addState == .adding || $0.addState == .addConnecting })
        }
        
        candidateView.state = state
        candidateView.virtualTargetAddLocked = virtualTargetAddLocked
        
        candidateCountLabel?.text = "\(displayedCandidateCount)"
        refreshVisibleDeviceAddRows()
        
       
    }

    private func refreshVisibleDeviceAddRows() {
        tableView.visibleCells.forEach { cell in
            guard let cell = cell as? DeviceAddViewCell,
                  let indexPath = tableView.indexPath(for: cell),
                  indexPath.row > 0,
                  let type = sectionTypes[safe: indexPath.section] else {
                return
            }
            let device: ProvisioningDevice?
            switch type {
            case .inRSSI:
                device = inRSSIDevices[safe: indexPath.row - 1]
            case .remainingRSSI:
                device = remainingRSSIDevices[safe: indexPath.row - 1]
            }
            guard let device else {
                return
            }
            cell.hidesSelectionControl = hidesBatchSelectionControls
            cell.device = device
            cell.addBtn.setImage(UIImage(named: "device_add_candidate"), for: .normal)
            cell.addBtn.setImage(nil, for: .disabled)
            if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
                cell.addBtn.isEnabled = false
            }
        }
    }
    
    /// 设备identify
    private func identify(_ device: ProvisioningDevice) {
        
        // 判断连接量是否达到上限
        let bleConnectCount = max(scanDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
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
        
        if let identifyDevice = self.identifyDevice {
            
            identifyDevice.addState = .none
            
            let cacheDevice = scanDevices.first(where: { $0.peripheral.identifier == identifyDevice.peripheral.identifier })
            cacheDevice?.addState = .none
            reloadDeviceState(identifyDevice)
            
            MeshAPI.stopUnprovisionedDeviceIdentify()
        }
        
        device.addState = .identifyConnecting
        let cacheDevice = self.scanDevices.first(where: { $0.peripheral.identifier == device.peripheral.identifier })
        cacheDevice?.addState = .identifyConnecting
        reloadDeviceState(device)
//        if state == .none || state == .scanning || state == .addFineshed {
//            state = .identifying
//            candidateView?.state = state
//        }
        
        
        identifyDevice = cacheDevice ?? device
        MeshAPI.unprovisionedDeviceIdentify(device: cacheDevice ?? device, attentionTimer: 6) {[weak self] _, _ in
            guard let self = self else { return }
            
            device.addState = .identifying
            let cacheDevice = self.scanDevices.first(where: { $0.peripheral.identifier == device.peripheral.identifier })
            cacheDevice?.addState = .identifying
            self.reloadDeviceState(device)
        } identifyFinished: {[weak self] _ in
            guard let self = self else { return }
            
            device.addState = .none
            
            let cacheDevice = self.scanDevices.first(where: { $0.peripheral.identifier == device.peripheral.identifier })
            cacheDevice?.addState = .none
            self.identifyDevice = nil
            self.reloadDeviceState(device)
        } identifyFail: {[weak self] _ in
            guard let self = self else { return }
            device.addState = .identifyFail
            
            let cacheDevice = self.scanDevices.first(where: { $0.peripheral.identifier == device.peripheral.identifier })
            cacheDevice?.addState = .identifyFail
            self.reloadDeviceState(device)
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 1) {[weak self] in
                if device.addState == .identifyFail {
                    device.addState = .none
                    cacheDevice?.addState = .none
                    self?.identifyDevice = nil
                    self?.reloadDeviceState(device)
                }
//                self?.candidateView?.updateDeviceData(device: device)
            }
        }
    }
    
    /// 添加设备
    private func addDevice(_ device: ProvisioningDevice) {
        
        // 设备identify中添加不需要再闪烁
//        if device.addState == .identifyConnecting || device.addState == .identifyWait || device.addState == .failed || device.addState == .identifying {
//            if device.addState == .identifying {
//                device.identifyAttentionTimer = 0
//            }
        if device.peripheral.identifier.uuidString == identifyDevice?.peripheral.identifier.uuidString {
            identifyDevice = nil
            MeshAPI.stopUnprovisionedDeviceIdentify()
        }
//        }
        // 添加设备不需要闪烁
        device.identifyAttentionTimer = 0
        if device.addState == .none {
            device.addState = .wait
            device.selectedState = .disabled
            reloadDeviceState(device)
        }
        updateUIState()
        
        deviceStateCallback?(true)
        
        MeshAPI.startFastAddDevices(devices: [device]) { [weak self] addDevice in
            addDevice.addState = .addConnecting
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } connectingBack: {[weak self] addDevice in
            addDevice.addState = .adding
            self?.reloadDeviceState(addDevice)
            self?.updateUIState()
        } provisionCompleteCallback: {[weak self] addDevice, node in
            guard let self = self else { return }
            // 配网完成
            
            node.rssi = addDevice.rssi.intValue
            if let macAddress = addDevice.macAddress {
                node.macAddress = macAddress
            }else {
                // 没有MAC，自动生成一个随机数
                let mac = MeshNetworkManager.instance.getRandomMacAddress()
                node.macAddress = mac
            }
//            if device.deviceType == .gateway {
//                node.name = MeshNetworkManager.instance.getNextNodeName("gateway".localizedString, length: 1)
//            }else {
//                node.name = MeshNetworkManager.instance.getNextNodeName()
//            }
            node.name = MeshNetworkManager.instance.getNextNodeName(node.defaultNameCategory)
            // 新添加的设备支持最新功能绑定要求
            if addDevice.deviceType != .emergencyController {
                node.requiredFunctionTypes = [.lightLCScene, .lightLCScheduler]
            }
            node.save()
            
            if addDevice.deviceType == .dongle { // dongle设备，需要一个dongle虚拟数据与之绑定
            
                if case .dongle(let selectDongle) = self.addTarget { // 已选择dognle
                    if selectDongle.bindNode != nil { // 已绑定设备则创建新的dongle并绑定设备
                        let newDongle = DeviceDongleData(id: UUID().uuidString, name: MeshNetworkManager.instance.getNextDongleName(), bindNodeAddress: node.primaryUnicastAddress, timeAuthority: selectDongle.timeAuthority, collectionEnable: selectDongle.collectionEnable, schedules: selectDongle.schedules)
                        MeshNetworkManager.instance.dongles.append(newDongle)
                        newDongle.save()
                    }else { // 未绑定设备则设备绑定到dongle
                        selectDongle.bindNodeAddress = node.primaryUnicastAddress
                        selectDongle.save()
                    }
                }else { // 添加到space
                    // 创建一个空的dongle数据做为dongle设备的绑定
                    let newDongle = DeviceDongleData.default()
                    MeshNetworkManager.instance.dongles.append(newDongle)
                    newDongle.save()
                }
            } else if addDevice.deviceType == .emergencyController {
                if let bindToEmerFire = self.bindToEmerFire {
                    DeviceEmerFireStore.shared.bind(bindToEmerFire, to: node, in: self.space)
                } else {
                    DeviceEmerFireStore.shared.ensureDevice(for: node, in: self.space)
                }
            }
            
        } appendMessagesBack: {[weak self] addDevice, appendCompletion in
            guard let self = self, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) else {
                appendCompletion([])
                return
            }
            var appendMessages: [MeshMessageHandle] = []
            if addDevice.deviceType == .emergencyController {
                let controller: DeviceEmerFireData
                if let bindToEmerFire = self.bindToEmerFire {
                    controller = DeviceEmerFireStore.shared.bind(bindToEmerFire, to: node, in: self.space)
                } else {
                    controller = DeviceEmerFireStore.shared.ensureDevice(for: node, in: self.space)
                }
                appendEmergencyFireControllerDefaultConfigurationMessages(controller: controller, appendMessages: &appendMessages)
            }
            // 入网后默认调为最大亮度
            let shouldApplyLightingDefaults = addDevice.deviceType == .light
            if shouldApplyLightingDefaults, let model = node.lightnessModel {
                appendMessages.append(MeshMessageHandle(message: LightLightnessSetUnacknowledged(lightness: .max), model: model))
            }
            if case .group(let group) = self.addTarget {
                // 判断组是否有关联动能开关，如果动能开关还未分配地址则提前分配地址以订阅设备
                if shouldApplyLightingDefaults {
                    let emptySwitchs = group.info.switchs.filter({ $0.linkGroup == nil })
                    emptySwitchs.forEach { switchData in

                        // 判断组地址是否足够分配
                        if MeshAPI.getAvailableGroupAddresses(meshUUID: self.space.meshUUID, subnetworkId: self.space.meshNetworkId).count >= switchData.panelType.usedAddressesNumber, switchData.linkGroupAddress == nil {

                            let linkGroup = try? MeshAPI.createGroup(name: switchData.name + "-Group", isVirtual: true)
                            let subLinkGroup = try? MeshAPI.createGroup(name: switchData.name + "-Group_1", isVirtual: true)

                            switchData.linkGroupAddress = linkGroup?.address.address
                            switchData.subLinkGroupAddress = subLinkGroup?.address.address
                            switchData.save()
                            //                        print("创建动能开关组")
                        }
                    }
                }
                let profileSyncContext = node.deviceType == .light ? groupMemberAddedProfileSyncContext : nil
                if let plan = DeviceGroupFastAddSyncPlanner.makePlan(
                    node: node,
                    group: group,
                    effectiveMemberCount: fastAddGroupEffectiveMemberCount,
                    profileSyncContext: profileSyncContext
                ) {
                    appendMessages.append(contentsOf: plan.appendMessageHandles)
                    self.registerFastAddGroupSyncPlan(plan)
                }
                appendEmergencyFireControllerGroupMutationMessages(node: node, group: group, appendMessages: &appendMessages)
                //                appendMessages.append(contentsOf: group.getNodeAddMessageHandles(node: node))
            }else {
                if shouldApplyLightingDefaults {
                    if let vendorModel = node.sunricherVendorModel, node.lightLCModel != nil { // 未加入组的设备默认设置一个手动控制延迟时间，避免默认30s后状态被LC修改
                        appendMessages.append(MeshMessageHandle(message: SunricherVendorSet(function: .manualOverrideTimeout(enabled: true, state: .standby, interval: .max)), model: vendorModel))
                    }
                    if let powerOnOffSetupModel = node.powerOnOffSetupModel { // 设置默认上电状态为上一次亮度
                        appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .restore), model: powerOnOffSetupModel))
                        //                    appendMessages.append(MeshMessageHandle(message: GenericOnPowerUpSet(state: .default), model: powerOnOffSetupModel))
                        //                    appendMessages.append(MeshMessageHandle(message: LightLightnessDefaultSet(lightness: .max), model: lightnessSetupModel))
                    }
                    if let lightLCSetupModel = node.lightLCSetupModel {
                        appendMessages.append(MeshMessageHandle(message: LightLCModeSet(false), model: lightLCSetupModel))
                    }
                }
            }
            // 需要追加发送的消息
            if let ctlModel = node.ctlModel, node.temperatureModel != nil {
                appendMessages.insert(MeshMessageHandle(message: LightCTLTemperatureRangeGet(), model: ctlModel), at: 0)
            }

            if BatteryPowerSwitchAddConfiguration.isSupportedAddNode(node) {
                if let bindToBatteryPowerSwitch {
                    switch BatteryPowerSwitchAddConfiguration.prepareLinkedSwitchData(
                        sourceSwitchData: bindToBatteryPowerSwitch,
                        node: node
                    ) {
                    case .success(let switchData):
                        batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] = switchData
                        let handles = BatteryPowerSwitchAddConfiguration.linkedConfigurationMessageHandles(
                            for: switchData,
                            node: node
                        )
                        if handles.isEmpty {
                            failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
                            failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress] = "sync_failed".localizedString
                        } else {
                            appendMessages.append(contentsOf: handles)
                        }
                    case .failure(let error):
                        failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
                        failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress] = error.message
                    }
                } else if let switchData = BatteryPowerSwitchAddConfiguration.prepareSwitchData(for: node) {
                    batteryPowerSwitchAddConfigurations[node.primaryUnicastAddress] = switchData
                    let handles = BatteryPowerSwitchAddConfiguration.defaultConfigurationMessageHandles(
                        for: switchData,
                        node: node
                    )
                    if handles.isEmpty {
                        failedBatteryPowerSwitchAddConfigurationAddresses.insert(node.primaryUnicastAddress)
                        failedBatteryPowerSwitchAddConfigurationReasons[node.primaryUnicastAddress] = "sync_failed".localizedString
                    } else {
                        appendMessages.append(contentsOf: handles)
                    }
                }
            }

            // 设置默认过渡时间
            //            if let defaultTransitionTimeModel = node.defaultTransitionTimeModel {
            //                appendMessages.append(MeshMessageHandle(message: GenericDefaultTransitionTimeSet(transitionTime: .default), model: defaultTransitionTimeModel))
            //            }
            // 节点数据hash
            //            if let vendorModel = node.sunricherVendorModel {
            //                appendMessages.append(MeshMessageHandle(message: SunricherVendorGet(function: .compositionHash), model: vendorModel))
            //            }
            
            // 添加成功后闪烁
            if let healthModel = node.healthModel {
                appendMessages.append(MeshMessageHandle(message: AttentionSet(attentionTimer: 6), model: healthModel))
            }
            appendCompletion(appendMessages)
            
            
            //            appendMessages.insert(MeshMessageHandle(message: ConfigRelaySet(), address: node.primaryUnicastAddress), at: 0)
            
            // 获取对应传感器model，识别传感器类型
            //            node.sensorModels.forEach { sensorModel in
            //                appendMessages.append(MeshMessageHandle(message: SensorGet(), model: sensorModel))
            //            }
            //            return appendMessages
        } appendMessageSuccessBack: { [weak self] messageHandle in
            // 发送扩展消息成功更新缓存数据
            if let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                if let plan = self?.fastAddGroupSyncPlan(containing: messageHandle) {
                    node.updateData(
                        message: messageHandle.message,
                        model: messageHandle.model
                    )
                    plan.recordSuccessfulMessageHandle(messageHandle)
                } else {
                    DispatchQueue.global().async {
                        node.updateData(
                            message: messageHandle.message,
                            model: messageHandle.model
                        )
                    }
                }
            }
        } appendMessageFailedBack: { [weak self] messageHandle in
            guard let self = self else { return }
            if let plan = self.fastAddGroupSyncPlan(containing: messageHandle) {
                self.recordFastAddGroupSyncFailure(plan)
            }
            if let nodeAddress = self.emergencyFireGroupMutationNodeAddress(containing: messageHandle) {
                self.failedEmergencyFireGroupMutationNodeAddresses.insert(nodeAddress)
            }
            if let nodeAddress = self.emergencyFireDefaultConfigurationNodeAddress(containing: messageHandle) {
                self.failedEmergencyFireDefaultConfigurationNodeAddresses.insert(nodeAddress)
            }
            guard let address = messageHandle.model?.parentElement?.unicastAddress ?? messageHandle.address else {
                return
            }
            if self.batteryPowerSwitchAddConfigurations[address] != nil {
                self.failedBatteryPowerSwitchAddConfigurationAddresses.insert(address)
                self.failedBatteryPowerSwitchAddConfigurationReasons[address] = "sync_failed".localizedString
            }
        } addSuccess: {[weak self] addDevice in
            guard let self = self else { return }
            var groupSyncFailed = false
            if let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: addDevice.address) {
                if let repalceNode = addDevice.repalceNode { // 删除被替换节点的缓存数据
                    repalceNode.deleteExtension()
                }
//                if device.deviceType == .gateway {
//                    node.name = MeshNetworkManager.instance.getNextNodeName("gateway".localizedString, length: 1)
//                }else {
//                    node.name = MeshNetworkManager.instance.getNextNodeName()
//                }
                // 需添加到组里
                if case .group(let group) = self.addTarget {
                    if node.group == nil { // 未添加组成功，需要记录组数据下次同步恢复到组里
                        node.restoreData = NodeRestoreData(addGroupAddress: group.address.address)
                        node.save()
                    }
                }
                if case .group = self.addTarget {
                    groupSyncFailed = self.resolveFastAddGroupSyncFailed(for: node)
                }
                if node.deviceType == .emergencyController {
                    self.finishLinkedEmergencyFireControllerConfiguration(for: node)
                }
                if node.isPowerSwitch,
                   let request = finalizeBatteryPowerSwitchAddConfiguration(for: node) {
                    pendingBatteryPowerSwitchInitialBatteryReads.append(request)
                }
//                node.state = true
                
//                node.saveNodeInfo(meshUUID: self.space.meshUUID, networkKey: self.space.meshNetworkKey)
//                self?.space.getNextNodeName(resultCallback: { name in
//                    node.name = name
//                    print("address:\(node.primaryUnicastAddress), name:\(name)")
//                })
//                if let name = self?.space.getNextNodeName() {
//                    node.name = name
//                }
                if !self.addSuccessNodes.contains(where: { $0.primaryUnicastAddress == node.primaryUnicastAddress }) {
                    self.addSuccessNodes.append(node)
                }
            }
            addDevice.addState = groupSyncFailed ? .syncFailed : .success
            self.reloadDeviceState(addDevice)
            self.updateUIState()
        } addFail: {[weak self] addDevice, error in
            guard let self = self else { return }
            addDevice.addState = .failed
            addDevice.selectedState = .selected
            self.reloadDeviceState(addDevice)
            self.updateUIState()
            // 设备地址已分配完
            if case .noAddressAvailable = error, !self.applyDeviceAddress {
                let applyAddressCount = 100
                guard NetworkRequest.shared.networkable else {
                    if SRAlertView.getCurrentAlertView() == nil {
                        SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                            if NetworkRequest.shared.networkable {
                                self?.space.applyDeviceAddressCount = nil
                                self?.space.save()
                                self?.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
                            }
                        })]).show()
                    }
                    self.space.applyDeviceAddressCount = applyAddressCount
                    self.space.save()
                    return
                }
                self.applyDeviceAddressesRequest(applyAddressCount: applyAddressCount)
            }
            
        } addFinish: {[weak self] successList, failList in
            guard let self = self else { return }

            UpDownLightDefaultCctStepsReader.readAfterProvisioning(devices: successList) { [weak self] in
                guard let self = self else { return }
                self.deviceAddCallback?(self.addSuccessNodes)
                self.deviceStateCallback?(false)

                self.space.deviceCount = MeshNetworkManager.instance.realNodes.count
                self.space.luminairesCount = MeshNetworkManager.instance.realNodes.filter({ $0.deviceType == .light }).count //MeshNetworkManager.instance.lightNodes.count
                self.space.switchesCount = MeshNetworkManager.instance.switchs.count
                self.space.save()
                // 通知space数据修改
                //                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.network(type: .address))
                NotificationCenter.default.post(name: .init(devicesAddNotificationName), object: nil)
                if self.addSuccessNodes.contains(where: { [.dongle, .gateway, .emergencyController, .unknown].contains($0.deviceType) }) {
                    NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
                }
                if self.addSuccessNodes.contains(where: { $0.deviceType == .emergencyController }) {
                    NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
                }
                if self.addSuccessNodes.contains(where: { $0.isPowerSwitch }) {
                    NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
                }
                self.resetFastAddGroupSyncBatch()
                self.finishBatteryPowerSwitchInitialBatteryReadsAndDisconnect()
            }
        }
        
    }
    
    /// 检查设备地址是否足够
    private func checkDeviceAddressesAreSufficient(devices: [ProvisioningDevice]) {

        guard validateBatteryPowerSwitchLimit(for: devices) else {
            return
        }

        prepareFastAddGroupSyncBatch(devices: devices)
        
        let bleConnectCount = max(candidateDevices.filter({ $0.addState == .adding || $0.addState == .addConnecting }).count, MeshLibManager.manager.getConnectedPeripherals().count)
        for (index, device) in devices.enumerated() {
            if index < (5 - bleConnectCount) {
                device.addState = .addConnecting
            }else {
                device.addState = .wait
            }
            device.selectedState = .disabled
            reloadDeviceState(device)
        }
        
        DispatchQueue.global().async {
            // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
            let estimatedAddressCount = devices.reduce(0, { (result, device) in result + device.elementCount })
            // 可用地址数量
            let availableUnicastCount = MeshAPI.getNumberOfAvailableUnicastAddresses(meshUUID: self.space.meshUUID)
            
            // 检查剩余地址是否足够添加设备
            guard availableUnicastCount >= estimatedAddressCount else {
                
                // 获取网络内已存在的设备地址数量
                let existingAddressCount = Node.loadAddresses(meshUUID: self.space.meshUUID).count
                // 申请的地址数量
                let applyAddressCount = estimatedAddressCount - availableUnicastCount + Int(Float(existingAddressCount) * 0.2)
                
                // 地址不够
                // 手机是否联网
                guard NetworkRequest.shared.networkable else {
                    // 未联网提示联网以获取地址
                    self.space.applyDeviceAddressCount = applyAddressCount
                    self.space.save()
                    
                    DispatchQueue.main.async {
//                        XWHUDManager.hide()
                        devices.forEach({
                            $0.addState = .none
                            $0.selectedState = .selected
                            self.reloadDeviceState($0)
                        })
                        SRAlertView(title: "notification".localizedString, message: "device_address_insufficient".localizedString, actions: [SRAlertAction(title: "ok".localizedString, actionHandler: {[weak self] _ in
                            if NetworkRequest.shared.networkable {
                                self?.space.applyDeviceAddressCount = nil
                                self?.space.save()
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
    private func applyDeviceAddressesRequest(applyAddressCount: Int, devices: [ProvisioningDevice] = []) {
        
//        // 添加设备需要地址-剩余地址 +（site中所有space已经添加的设备地址+正在添加的设备地址）*20%
//        let estimatedAddressCount = devices.reduce(0, { (result, device) in result + device.elementCount })
//        // 获取网络内已存在的设备地址数量
//        let existingAddressCount = Node.loadAddresses(meshUUID: self.space.meshUUID).count
//        // 申请的地址数量
//        let applyAddressCount = estimatedAddressCount - MeshAPI.getNumberOfAvailableUnicastAddresses() + Int(Float(existingAddressCount) * 0.2)
        // request
        self.applyDeviceAddress = true
        XWHUDManager.showCustomHUD(withMessage: nil, isWindow: true)
        NetworkRequest.shared.request(.applyAddress(siteId: self.space.siteId, type: .device, number: applyAddressCount)) {[weak self] result in
            XWHUDManager.hide()
            guard let self = self else { return }
            self.applyDeviceAddress = false
            switch result {
            case .success(let repsonsed):
                // 新增地址
                if let site = SiteData.load(siteId: self.space.siteId), let provisionerData = JSON(repsonsed)["data"]["provisioner"].dictionaryObject {
                    guard self.validateBatteryPowerSwitchLimit(for: devices) else {
                        self.restoreDevicesForAddRetry(devices)
                        return
                    }
                    site.setProvisioner(provisionerData: provisionerData)
                    // 继续添加设备
                    devices.forEach({
                        self.addDevice($0)
                    })
                }else {
                    devices.forEach({
                        $0.addState = .none
                        $0.selectedState = .selected
                        self.reloadDeviceState($0)
                    })
                    XWHUDManager.showErrorTipHUD(NetworkApiError.unknown.localizedDescription)
                }
            case .failure(let error):
                devices.forEach({
                    $0.addState = .none
                    $0.selectedState = .selected
                    self.reloadDeviceState($0)
                })
                XWHUDManager.showErrorTipHUD(error.localizedDescription)
            }
        }
       
    }
    
    /// 刷新设备UI状态
    private func reloadDeviceState(_ device: ProvisioningDevice, force: Bool = true) {
        
        candidateView.updateDeviceData(device: device)
//        setDataing = true
        var indexPath: IndexPath?
        if let index = inRSSIDevices.firstIndex(where: { $0.peripheral.identifier == device.peripheral.identifier }) {
            indexPath = IndexPath(row: index + 1, section: sectionTypes.firstIndex(of: .inRSSI) ?? 0)
        }else if let index = remainingRSSIDevices.firstIndex(where: { $0.peripheral.identifier == device.peripheral.identifier }) {
            indexPath = IndexPath(row: index + 1, section: sectionTypes.firstIndex(of: .remainingRSSI) ?? 0)
        }
        
        if let indexPath = indexPath {
            if let cell = tableView.cellForRow(at: indexPath) as? DeviceAddViewCell {
                cell.hidesSelectionControl = hidesBatchSelectionControls
                cell.device = device
            }else if force {
                reloadDataing = true
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
        }
    }
    
    /// 归类设备数据
    private func setupDevicesData() {
        // Device1.5 的通用限制在这里统一映射成禁选态，不改变默认扫描结果组织方式。
        scanDevices.forEach { applySelectableState(to: $0) }
        
        let displayedScanDevices = scanDevices.filter { isVisibleDeviceInCurrentAddMode($0) }
        inRSSIDevices = displayedScanDevices.filter({ device in selectRSSIRange.contains(device.rssi.intValue) && !candidateDevices.contains(where: { device.peripheral.identifier == $0.peripheral.identifier }) })
        remainingRSSIDevices = displayedScanDevices.filter({ device in !selectRSSIRange.contains(device.rssi.intValue) && !candidateDevices.contains(where: { device.peripheral.identifier == $0.peripheral.identifier }) })
        
        inRSSIDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
        remainingRSSIDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
        
        self.candidateDevices.sort(by: { $0.rssi.intValue >= $1.rssi.intValue })
        self.syncCandidateDevicesForCurrentAddMode()
        
        
//        if !sectionTypes.contains(.inRSSI) {
//            sectionTypes.insert(.inRSSI, at: 0)
//        }
//        if !sectionTypes.contains(.remainingRSSI) {
//            sectionTypes.append(.remainingRSSI)
//        }
        self.tableView.reloadData()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: {
            self.reloadDataing = false
        })
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
            let shadeView = UIView(frame: view.bounds)
            shadeView.backgroundColor = RGB(0, 0, 0, 0.4)
            emptyView.insertSubview(shadeView, belowSubview: emptyView.contentView)
        }
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
            self.perform(#selector(self.hideDeviceNotFound), with: nil, afterDelay: 5)
        }
        
    }
    
    /// 隐藏找不到设备提示
    @objc private func hideDeviceNotFound() {
        DispatchQueue.main.async {
            NSObject.cancelPreviousPerformRequests(withTarget: self, selector: #selector(self.hideDeviceNotFound), object: nil)
        }
        view.hideEmptyDataView()
    }
    
    // MARK: - 信号排序定时器
    private func startRssiSortTimer() {
        
//        stopRssiSortTimer()
//        if let timer = rssiSortTimer, timer.isValid {
//            timer.fireDate = Date(timeIntervalSinceNow: 1)
//            return
//        }
        guard rssiSortTimer == nil || !rssiSortTimer!.isValid else {
            return
        }
        
        rssiSortTimer = LCWeakTimer.scheduledTimer(timeInterval: 1, aTarget: self, selector: #selector(devicesRssiSort), userInfo: nil, repeats: false)
        RunLoop.current.add(rssiSortTimer!, forMode: .common)
    }
    
    private func stopRssiSortTimer() {
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
    }
    
    /// 设备信号排序定时刷新，避免接收广播包后刷新频率过高
    @objc private func devicesRssiSort() {
        
        if reloadDataing {
            rssiSortTimer?.fireDate = Date(timeIntervalSinceNow: 1)
        }else {
            rssiSortTimer?.invalidate()
            rssiSortTimer = nil
        }
        
        setupDevicesData()
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
    
    
    @objc private func addModeBtnAction(sender: UIButton) {
        
        let touchPoint = CGPoint(x: sender.x, y: sender.frame.maxY + SCRYFrom(2))
        let menuPoint = (devicesFoundView ?? view).convert(touchPoint, to: UIApplication.shared.keyWindow())
        
        let modes: [AddMode] = [.manual, .motionSensing, .lightSening, .rssiRange]
        
        TitleSelectView.show(titles: modes.map({ $0.title }), anchorPoint: menuPoint, selectIndex: modes.firstIndex(of: addMode) ?? 0, menuWidth: SCRXFrom(250)) {[weak self] index in
            guard let self = self else { return }
            self.addMode = modes[index]
            sender.setTitle(self.addMode.title, for: .normal)
            sender.sizeToFit()
            sender.setImagePosition(position: .right, spacing: SCRXFrom(-2), btnMaxWidth: self.addModeBtnMaxWidth)
            
            if self.state == .scanning {
                if self.addMode == .motionSensing || self.addMode == .lightSening {
                    self.startBroadcasting()
                }else {
                    self.stopBroadcasting()
                }
            }
//            self.candidateView?.lightSeningMode = self.addMode == .lightSening
            if self.isRefresh, self.addMode == .rssiRange {
                // 筛选出满足预选条件的设备
                let devices = self.scanDevices.filter({ device in device.selectedState != .disabled && self.isSelectableDevice(device) && !self.candidateDevices.contains(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) && self.selectRSSIRange.contains(device.rssi.intValue) })
                self.candidateDevices.append(contentsOf: devices)
            }
            self.setupDevicesData()
        }
        
    }
    
    /// 信号滑条修改
    @objc private func rssiSliderValueChanged(sender: RangeSlider) {
        let changeRSSIRange = Int(-sender.upperValue)...Int(-sender.lowerValue)
        guard selectRSSIRange != changeRSSIRange else {
            return
        }
        
//        isRefresh = false
        reloadDataing = true
        
        print(changeRSSIRange)
        selectRSSIRange = changeRSSIRange
        // 筛选展示的设备
//        showDevices = scanDevices.filter({ showDeviceTypes.contains($0.deviceType) && selectRSSIRange.contains($0.rssi.intValue) })

        farLabel.text = "\(selectRSSIRange.lowerBound) dBm"
        nearLabel.text = "\(selectRSSIRange.upperBound) dBm"
         
        rssiRangeLabel?.attributedText = NSAttributedString(string: "\(selectRSSIRange.upperBound) dBm \("to".localizedString) \(selectRSSIRange.lowerBound) dBm", attributes: [.underlineStyle: 1])
        
//        if rssiSortTimer?.isValid ?? false {
//            rssiSortTimer?.fireDate = Date(timeIntervalSinceNow: 0.5)
//        }
        rssiSortTimer?.invalidate()
        rssiSortTimer = nil
        if self.isRefresh {
            // 筛选出满足预选条件的设备
            if addMode == .rssiRange {
                let devices = self.scanDevices.filter({ device in device.selectedState != .disabled && self.isSelectableDevice(device) && !self.candidateDevices.contains(where: { $0.peripheral.identifier.uuidString == device.peripheral.identifier.uuidString }) && self.selectRSSIRange.contains(device.rssi.intValue) })
                if devices.count > 0 {
                    self.candidateDevices.append(contentsOf: devices)
                    self.playerNotificationAudio()
                }
            }
     
//            switch addMode {
//            case .motionSensing:
//                self.candidateDevices.append(contentsOf: devices.filter({ $0.triggerActionTypes.contains(.motionSensing) }))
//                if devices.count > 0 {
//                    self.playerNotificationAudio()
//                }
//                
//            case .lightSening:
//                self.candidateDevices.append(contentsOf: devices.filter({ $0.triggerActionTypes.contains(.lightSensing) }))
//                self.playerNotificationAudio()
//            case .manual:
//                break
//            case .rssiRange:
//                self.candidateDevices.append(contentsOf: devices)
//                self.playerNotificationAudio()
//            }
        }
        
        setupDevicesData()
        
//        updateDeviceCategoryCount()
    }
    
    @objc private func pauseBtnAction(sender: UIButton) {
        sender.isSelected = !sender.isSelected
        isRefresh = !sender.isSelected
        
        if !isRefresh {
            stopScanTimer()
        }
        candidateView.isRefresh = isRefresh
    }
    
    /// 设置参数
    @objc private func settingsBtnAction() {
        
        if parameterSettingsView == nil {
            parameterSettingsView = DeviceAddParameterSettingsView(frame: UIScreen.main.bounds, parameterData: deviceSettingsParameterData)
            parameterSettingsView?.volumeChangedEndCallback = { volume in
                try? DeviceAudioManager.manager.startAudio(type: .deviceAdd, volume: volume)
            }
            parameterSettingsView?.settingsCallback = {[weak self] data in
                deviceSettingsParameterData = data
                guard let self = self else { return }
                if self.state == .scanning && (self.addMode == .motionSensing || self.addMode == .lightSening) { // 如果正在发送广播包，修改广播包参数后重新发送广播包
                    self.startBroadcasting()
                }
//                try? DeviceAudioManager.manager.startAudio(type: .deviceAdd)
//                DeviceAudioManager.manager.vibration()
            }
            parameterSettingsView?.helpActionCallback = {[weak self] in
                guard let self = self else { return }
                let vc = DeviceParameterSetupInstructionsController(mode: .add)
                if isIPad {
                    vc.preferredContentSize = iPadPreferredContentSize
                    self.parameterSettingsView?.dismiss()
                }
                if self.presentingViewController == nil {
                    self.present(NavigationViewController(rootViewController: vc), animated: true)
                }else {
                    self.navigationController?.pushViewController(vc, animated: true)
                }
            }
            
        }else {
            parameterSettingsView?.parameterData = deviceSettingsParameterData
        }
        parameterSettingsView?.show()
    }
    
    @objc private func showDeviceListBtnAction() {
        syncCandidateTargetState()
        candidateView.show()
    }
    
    private func setupUI() {
        if isIPad {
            setupIpadUI()
        }else {
            setupIphoneUI()
        }
    }
    
    /// 设置Iphone UI
    private func setupIphoneUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(104))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        nearLabel.sizeToFit()
        headerView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(21))
//            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        farLabel.sizeToFit()
        headerView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(nearLabel)
//            make.width.equalTo(farLabel.width)
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
        rssiSlider.minimumRange = 10
        rssiSlider.addTarget(self, action: #selector(rssiSliderValueChanged), for: .valueChanged)
        headerView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(64))
            make.right.equalTo(SCRXFrom(-65))
            make.centerY.equalTo(nearLabel)
            make.height.equalTo(SCRYFrom(40))
        }
        
        addModeBtn = UIButton(title: addMode.title, titleSize: 12, titleWeight: .medium, titleColor: ImportantText_Color, normalImageName: "arrow_down_black", target: self, action: #selector(addModeBtnAction))
        addModeBtn.titleLabel?.lineBreakMode = .byTruncatingTail
        addModeBtn.setImagePosition(position: .right, spacing: -5, btnMaxWidth: self.addModeBtnMaxWidth)
        headerView.addSubview(addModeBtn)
        addModeBtn.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(rssiSlider.snp.bottom).offset(SCRYFrom(9))
            make.width.lessThanOrEqualTo(addModeBtnMaxWidth)
        }
        
        scanBtn = UIButton(title: "scan".localizedString, titleSize: 13, titleColor: Bottom_Done_Color, normalImageName: "device_scan", target: self, action: #selector(scanBtnClick))
        scanBtn.setTitle("stop".localizedString, for: .selected)
        scanBtn.setTitleColor(Purple_Color.withAlphaComponent(0.5), for: .disabled)
        scanBtn.layer.cornerRadius = SCRYFrom(5)
        scanBtn.layer.borderWidth = 1
        scanBtn.layer.borderColor = Border_Color.cgColor
        scanBtn.backgroundColor = .white
        scanBtn.contentHorizontalAlignment = .left
        scanBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
        scanBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: 0)
        
        headerView.addSubview(scanBtn)
        scanBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(addModeBtn)
            make.width.equalTo(SCRXFrom(72))
            make.height.equalTo(SCRYFrom(32))
        }
        
        pauseBtn = UIButton(normalImageName: "device_add_pause", selectedImageName: "device_add_start", target: self, action: #selector(pauseBtnAction))
        pauseBtn.isHidden = true
        headerView.addSubview(pauseBtn)
        pauseBtn.snp.makeConstraints { make in
            make.right.equalTo(scanBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.equalTo(scanBtn)
        }
        
        settingsBtn = UIButton(normalImageName: "device_add_setting", target: self, action: #selector(settingsBtnAction))
        headerView.addSubview(settingsBtn)
        settingsBtn.snp.makeConstraints { make in
            make.right.equalTo(pauseBtn.snp.left).offset(SCRXFrom(-10))
            make.centerY.equalTo(pauseBtn)
        }
        
        settingsTipView = UIView()
        settingsTipView.layer.cornerRadius = 2.5
        settingsTipView.backgroundColor = RGB(255, 167, 44)
        settingsTipView.isUserInteractionEnabled = false
        settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        settingsBtn.addSubview(settingsTipView)
        settingsTipView.snp.makeConstraints { make in
            make.right.equalTo(-8.5)
            make.centerY.equalToSuperview().offset(0.5)
            make.width.height.equalTo(5)
        }
        
        bottomView = UIView()
        bottomView.isHidden = true
        bottomView.backgroundColor = .white
        view.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(kSafeAreaBottomHeight + SCRYFrom(60))
        }
        
        showDeviceListBtn = UIButton(title: "candidate_device_list".localizedString, titleSize: 15, titleWeight: .light, titleColor: TextBlack_Color, normalImageName: "arrow_up_black", target: self, action: #selector(showDeviceListBtnAction))
        showDeviceListBtn?.setImagePosition(position: .right, spacing: SCRXFrom(2), btnMaxWidth: self.addModeBtnMaxWidth)
        bottomView.addSubview(showDeviceListBtn!)
        showDeviceListBtn!.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
        
        candidateCountLabel = UILabel(text: "", textColor: TextBlack_Color, fontSize: 15, fontWeight: .light)
        bottomView.addSubview(candidateCountLabel!)
        candidateCountLabel!.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-22))
            make.centerY.equalTo(showDeviceListBtn!)
        }
        
        lineView = UIView()
        lineView.backgroundColor = Line_Color
        bottomView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.isHidden = true
        tableView.backgroundColor = Background_Color
        tableView.separatorStyle = .none
        tableView.showsVerticalScrollIndicator = false
        tableView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: SCRYFrom(-16), right: 0)
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceAddSelectAllViewCell.classForCoder(), forCellReuseIdentifier: "selectAllCell")
        tableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "titleHeader")
        tableView.dataSource = self
        tableView.delegate = self
        view.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        messageLabel = UILabel(text: "professional_mode_message".localizedString, textColor: ImportantText_Color, fontSize: 14, fontWeight: .light, fit: false)
        messageLabel!.textAlignment = .center
        messageLabel!.numberOfLines = 0
        view.addSubview(messageLabel!)
        messageLabel!.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(20))
            make.right.equalTo(SCRXFrom(-20))
            make.top.equalTo(headerView.snp.bottom).offset(SCRYFrom(88))
        }
        
        candidateView = DeviceAddCandidateDeviceListView(frame: UIScreen.main.bounds, space: space)
        candidateView.delegate = self
    }
    
    /// 设置Ipad UI
    private func setupIpadUI() {
        
        headerView = UIView()
        view.addSubview(headerView)
        headerView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(SCRYFrom(76))
        }
        
        scanBtn = UIButton(title: "scan".localizedString, titleSize: 13, titleColor: Bottom_Done_Color, normalImageName: "device_scan", target: self, action: #selector(scanBtnClick))
        scanBtn.setTitle("stop".localizedString, for: .selected)
        scanBtn.setTitleColor(Purple_Color.withAlphaComponent(0.5), for: .disabled)
        scanBtn.layer.cornerRadius = SCRYFrom(5)
        scanBtn.layer.borderWidth = 1
        scanBtn.layer.borderColor = Border_Color.cgColor
        scanBtn.backgroundColor = .white
        scanBtn.contentHorizontalAlignment = .left
        scanBtn.imageEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(8), bottom: 0, right: 0)
        scanBtn.titleEdgeInsets = UIEdgeInsets(top: 0, left: SCRXFrom(10), bottom: 0, right: 0)
        headerView.addSubview(scanBtn)
        scanBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalToSuperview()
            make.width.equalTo(SCRXFrom(126))
            make.height.equalTo(SCRYFrom(44))
        }
        
        let rssiRangeView = UIView()
        rssiRangeView.layer.cornerRadius = SCRYFrom(10)
        rssiRangeView.backgroundColor = .white
        headerView.addSubview(rssiRangeView)
        rssiRangeView.snp.makeConstraints { make in
            make.centerY.equalToSuperview()
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(scanBtn.snp.left).offset(SCRXFrom(-16))
            make.height.equalTo(SCRYFrom(44))
        }
        
        nearLabel = UILabel(text: "\(selectRSSIRange.upperBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        nearLabel.sizeToFit()
        rssiRangeView.addSubview(nearLabel)
        nearLabel.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.centerY.equalToSuperview()
//            make.width.equalTo(nearLabel.width)
        }
        
        farLabel = UILabel(text: "\(selectRSSIRange.lowerBound) dBm", textColor: TextBlack_Color, fontSize: 12, fontWeight: .light)
//        farLabel.sizeToFit()
        rssiRangeView.addSubview(farLabel)
        farLabel.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(nearLabel)
//            make.width.equalTo(farLabel.width)
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
        rssiSlider.minimumRange = 10
        rssiSlider.addTarget(self, action: #selector(rssiSliderValueChanged), for: .valueChanged)
        rssiRangeView.addSubview(rssiSlider)
        rssiSlider.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(74))
            make.right.equalTo(SCRXFrom(-74))
            make.centerY.equalToSuperview()
            make.height.equalTo(SCRYFrom(40))
        }
        
        let lineView = UIView()
        lineView.backgroundColor = Line_Color1
        headerView.addSubview(lineView)
        lineView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(1)
        }
        
        devicesFoundView = UIView()
        devicesFoundView!.backgroundColor = .white
        view.addSubview(devicesFoundView!)
        devicesFoundView!.snp.makeConstraints { make in
            make.left.equalToSuperview()
            make.right.equalTo(view.snp.centerX)
            make.top.equalTo(headerView.snp.bottom)
            make.bottom.equalTo(-kSafeAreaBottomHeight)
        }
        
        devicesFoundLabel = UILabel(text: "list_of_devices_found".localizedString, textColor: TextBlack_Color, fontSize: 15)
        devicesFoundView!.addSubview(devicesFoundLabel!)
        devicesFoundLabel!.snp.makeConstraints { make in
            make.centerX.equalToSuperview()
            make.top.equalTo(SCRYFrom(24))
        }
        
        rssiRangeLabel = UILabel(text: "", textColor: ImportantText_Color, fontSize: 12, fontWeight: .light)
        rssiRangeLabel?.attributedText = NSAttributedString(string: "\(selectRSSIRange.upperBound) dBm \("to".localizedString) \(selectRSSIRange.lowerBound) dBm", attributes: [.underlineStyle: 1])
        devicesFoundView!.addSubview(rssiRangeLabel!)
        rssiRangeLabel!.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.top.equalTo(SCRYFrom(65))
        }
        
        settingsBtn = UIButton(normalImageName: "device_add_setting", target: self, action: #selector(settingsBtnAction))
        devicesFoundView!.addSubview(settingsBtn)
        settingsBtn.snp.makeConstraints { make in
            make.right.equalTo(SCRXFrom(-16))
            make.centerY.equalTo(rssiRangeLabel!)
        }
        
        settingsTipView = UIView()
        settingsTipView.layer.cornerRadius = 2.5
        settingsTipView.backgroundColor = RGB(255, 167, 44)
        settingsTipView.isUserInteractionEnabled = false
        settingsTipView.isHidden = SystemVolumeManager.shared.currentVolume >= DeviceSettingsParameterData.systemMinimumVolumeRequire
        settingsBtn.addSubview(settingsTipView)
        settingsTipView.snp.makeConstraints { make in
            make.right.equalTo(-8.5)
            make.centerY.equalToSuperview().offset(0.5)
            make.width.height.equalTo(5)
        }
        
        addModeBtn = UIButton(title: addMode.title, titleSize: 12, titleWeight: .medium, titleColor: ImportantText_Color, normalImageName: "arrow_down_black", target: self, action: #selector(addModeBtnAction))
        addModeBtn.titleLabel?.lineBreakMode = .byTruncatingTail
        addModeBtn.setImagePosition(position: .right, spacing: SCRXFrom(-2), btnMaxWidth: self.addModeBtnMaxWidth)
        devicesFoundView!.addSubview(addModeBtn)
        addModeBtn.snp.makeConstraints { make in
            make.right.equalTo(settingsBtn.snp.left).offset(SCRXFrom(-8))
            make.centerY.equalTo(settingsBtn)
            make.width.lessThanOrEqualTo(addModeBtnMaxWidth)
            
        }
        
        bottomView = UIView()
        bottomView.isHidden = true
        devicesFoundView!.addSubview(bottomView)
        bottomView.snp.makeConstraints { make in
            make.left.right.bottom.equalToSuperview()
            make.height.equalTo(SCRYFrom(60))
        }
        
        let bottomLineView = UIView()
        bottomLineView.backgroundColor = Line_Color1
        bottomView.addSubview(bottomLineView)
        bottomLineView.snp.makeConstraints { make in
            make.left.right.top.equalToSuperview()
            make.height.equalTo(1)
        }
        
        pauseBtn = UIButton(normalImageName: "device_add_pause", selectedImageName: "device_add_start", target: self, action: #selector(pauseBtnAction))
        bottomView.addSubview(pauseBtn)
        pauseBtn.snp.makeConstraints { make in
            make.center.equalToSuperview()
        }
        
        tableView = UITableView(frame: .zero, style: .grouped)
        tableView.separatorStyle = .none
        tableView.backgroundColor = .clear
        tableView.showsVerticalScrollIndicator = false
        tableView.register(DeviceAddViewCell.classForCoder(), forCellReuseIdentifier: "cell")
        tableView.register(DeviceAddSelectAllViewCell.classForCoder(), forCellReuseIdentifier: "selectAllCell")
        tableView.register(SyncDevicesTitleHeaderView.classForCoder(), forHeaderFooterViewReuseIdentifier: "titleHeader")
        tableView.dataSource = self
        tableView.delegate = self
        devicesFoundView!.addSubview(tableView)
        tableView.snp.makeConstraints { make in
            make.left.equalTo(SCRXFrom(16))
            make.right.equalTo(SCRXFrom(-16))
            make.top.equalTo(settingsBtn.snp.bottom).offset(SCRYFrom(4))
            make.bottom.equalTo(bottomView.snp.top)
        }
        
        candidateView = DeviceAddCandidateDeviceListView(frame: .zero, space: space)
        candidateView.candidateDevices = displayedCandidateDevices
        candidateView.addTarget = addTarget
        candidateView.addTargetNameOverride = addTargetNameOverride
        candidateView.isRefresh = isRefresh
//        candidateView?.lightSeningMode = addMode == .lightSening
        candidateView.state = state
        candidateView.delegate = self
        view.addSubview(candidateView)
        candidateView.snp.makeConstraints { make in
            make.left.equalTo(devicesFoundView!.snp.right)
            make.top.bottom.equalTo(devicesFoundView!)
            make.right.equalToSuperview()
        }
        
    }

}

extension DeviceAddProfessionalModeController: UITableViewDataSource, UITableViewDelegate {
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return sectionTypes.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        
        let type = sectionTypes[section]
        switch type {
        case .inRSSI:
            return inRSSIDevices.count + 1
        case .remainingRSSI:
            return remainingRSSIDevices.count + 1
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row == 0 {
            let selectCell = tableView.dequeueReusableCell(withIdentifier: "selectAllCell", for: indexPath) as! DeviceAddSelectAllViewCell
            guard indexPath.section < sectionTypes.count else {
                return selectCell
            }
            let type = sectionTypes[indexPath.section]
            var devices: [ProvisioningDevice] = []
            switch type {
            case .inRSSI:
                devices = inRSSIDevices
            case .remainingRSSI:
                devices = remainingRSSIDevices
            }
            let selectDevices = devices.filter({ $0.selectedState == .selected })
            selectCell.selectBtn.isSelected = selectDevices.count > 0 && selectDevices.count == devices.count
            selectCell.countLabel.text = "\(selectDevices.count)/\(devices.count)"
            selectCell.candidateBtn.isEnabled = selectDevices.count > 0
            selectCell.setSelectionControlsHidden(hidesBatchSelectionControls)
            selectCell.delegate = self
            if type == .inRSSI && !isIPad {
                selectCell.configureCell(isFirst: true, isLast: inRSSIDevices.count == 0)
            }else {
                selectCell.backgroundColor = .clear
                selectCell.contentView.backgroundColor = .clear
            }
            return selectCell
        }else {
            
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! DeviceAddViewCell
            guard let type = sectionTypes[safe: indexPath.section] else {
                return cell
            }
            var device: ProvisioningDevice!
            switch type {
            case .inRSSI:
                device = inRSSIDevices[indexPath.row - 1]
            case .remainingRSSI:
                device = remainingRSSIDevices[indexPath.row - 1]
            }
            cell.hidesSelectionControl = hidesBatchSelectionControls
            cell.device = device
            cell.selectionStyle = .none
            cell.addBtn.setImage(UIImage(named: "device_add_candidate"), for: .normal)
            cell.addBtn.setImage(nil, for: .disabled)
            if virtualTargetAddLocked && !device.addState.blocksVirtualTargetSingleAdd {
                cell.addBtn.isEnabled = false
            }
            cell.delegate = self
            if type == .inRSSI && !isIPad {
                cell.configureCell(isFirst: false, isLast: indexPath.row == tableView.numberOfRows(inSection: indexPath.section) - 1)
            }else {
                cell.backgroundColor = .clear
                cell.contentView.backgroundColor = .clear
            }
            if isIPad {
                cell.lineView.isHidden = tableView.numberOfRows(inSection: indexPath.section) - 1 == indexPath.row
            }
            return cell
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if indexPath.row == 0 {
            if let sectionType = sectionTypes[safe: indexPath.section], sectionType == .inRSSI, inRSSIDevices.isEmpty {
                return SCRYFrom(34 + 70)
            }
            return SCRYFrom(34)
        }
        return SCRYFrom(70)
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let type = sectionTypes[section]
        if type == .remainingRSSI {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: "titleHeader") as! SyncDevicesTitleHeaderView
            headerView.titleLabel.text = "the_remaining_rssi_devices".localizedString
            headerView.titleLabel.textColor = ImportantText_Color
            headerView.titleLabel.font = UIFont.systemFont(ofSize: SCRYFrom(12), weight: .light)
            headerView.titleLeftMargin = 0
            headerView.bottomMargin = SCRYFrom(4)
            return headerView
        }
        return UIView()
    }
    
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        let type = sectionTypes[section]
        return type == .remainingRSSI ? SCRYFrom(36) : 0.01
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        return UIView()
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0.01
    }
    
    // 每个 section 的背景
    func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        guard isIPad, sectionTypes[section] == .inRSSI else { return }
        
        // 先移除旧的
        tableView.subviews.filter { $0 is DeviceAddSectionBackgroundView }.forEach { $0.removeFromSuperview() }
        
        // 计算整个 section 的 rect
        let sectionRect = tableView.rect(forSection: section)
        
        // 添加背景视图
        let bgView = DeviceAddSectionBackgroundView(frame: sectionRect)
        tableView.insertSubview(bgView, at: 0)
    }

    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard indexPath.row > 0, indexPath.section < sectionTypes.count else {
            return
        }
        guard !hidesBatchSelectionControls else {
            return
        }
        let type = sectionTypes[indexPath.section]
        var device: ProvisioningDevice?
        switch type {
        case .inRSSI:
            device = inRSSIDevices[safe: indexPath.row - 1]
        case .remainingRSSI:
            device = remainingRSSIDevices[safe: indexPath.row - 1]
        }
        if let device, device.selectedState == .disabled {
            showDisabledDeviceTip(device)
            return
        }
        guard let device = device, device.selectedState == .unselected || device.selectedState == .selected else {
            return
        }
        if device.selectedState == .unselected {
            device.selectedState = .selected
        }else {
            device.selectedState = .unselected
        }
        if device.selectedState == .selected {
            // 单选模式下清理其它设备选中态，保持默认点击行为不变。
            applySingleSelectionIfNeeded(for: device)
        }
        
        let cacheDevice = scanDevices.first(where: { $0.peripheral.identifier == device.peripheral.identifier })
        cacheDevice?.selectedState = device.selectedState
        
        reloadDataing = true
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }
    
}

extension DeviceAddProfessionalModeController: DeviceAddViewCellDelegate {
    
    /// 设备identify点击事件回调
    func cell(_ cell: DeviceAddViewCell, identify device: ProvisioningDevice) {
        if device.addState == .identifying {
            return
        }
//        if state == .scanning {
//            
//            XWHUDManager.showTipHUD(inView: "device_scaning_disable_identify".localizedString)
//            return
//        }
        identify(device)
    }
    
    /// 设备添加预选点击事件回调
    func cell(_ cell: DeviceAddViewCell, deviceAdd device: ProvisioningDevice) {
        if device.selectedState == .disabled {
            showDisabledDeviceTip(device)
            return
        }
        guard canStartVirtualTargetAdd() else {
            return
        }
        // 单选模式下候选列表只保留一个设备，默认业务仍复用原有候选流程。
        if isSingleSelectionMode {
            applySingleSelectionIfNeeded(for: device)
            candidateDevices = [device]
            setupDevicesData()
            return
        }
        if !candidateDevices.contains(where: { $0.peripheral.identifier == device.peripheral.identifier }) {
            candidateDevices.append(device)
        }
        setupDevicesData()
    }
    
    /// 设备状态图标点击
    func cell(_ cell: DeviceAddViewCell, deviceStateImageClick device: ProvisioningDevice) {
        
    }
}

extension DeviceAddProfessionalModeController: DeviceAddSelectAllViewCellDelegate {
    
    /// 设备点击选择/取消所有 事件回调
    func cell(_ cell: DeviceAddSelectAllViewCell, selectAllAction selectAll: Bool) {
        guard !hidesBatchSelectionControls else {
            return
        }
        // 单选模式下不进入批量勾选逻辑，保持关联页一次只选一个设备。
        if isSingleSelectionMode {
            if let section = tableView.indexPath(for: cell)?.section {
                let devices = sectionTypes[section] == .inRSSI ? inRSSIDevices : remainingRSSIDevices
                inRSSIDevices.forEach { $0.selectedState = .unselected }
                remainingRSSIDevices.forEach { $0.selectedState = .unselected }
                scanDevices.forEach { $0.selectedState = .unselected }
                if selectAll, let firstDevice = devices.first {
                    applySingleSelectionIfNeeded(for: firstDevice)
                }
                reloadDataing = true
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
            }
            return
        }
        if let section = tableView.indexPath(for: cell)?.section {
            switch sectionTypes[section] {
            case .inRSSI:
                inRSSIDevices.forEach({ device in
                    guard device.selectedState != .disabled else { return }
                    device.selectedState = selectAll ? .selected : .unselected
                    
                    let cacheDevice = scanDevices.first(where: {$0.peripheral.identifier == device.peripheral.identifier })
                    cacheDevice?.selectedState = device.selectedState
                })
            case .remainingRSSI:
                remainingRSSIDevices.forEach({ device in
                    guard device.selectedState != .disabled else { return }
                    device.selectedState = selectAll ? .selected : .unselected
                    
                    let cacheDevice = scanDevices.first(where: {$0.peripheral.identifier == device.peripheral.identifier })
                    cacheDevice?.selectedState = device.selectedState
                })
            }
        
            reloadDataing = true
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    /// 设备预选事件回调
    func selectAllCellCandidateAction(_ cell: DeviceAddSelectAllViewCell) {
        guard !hidesBatchSelectionControls else {
            return
        }
        if let section = tableView.indexPath(for: cell)?.section {
            reloadDataing = true
            if isSingleSelectionMode {
                let devices = sectionTypes[section] == .inRSSI ? inRSSIDevices : remainingRSSIDevices
                if let selectedDevice = devices.first(where: { $0.selectedState == .selected }) {
                    applySingleSelectionIfNeeded(for: selectedDevice)
                    candidateDevices = [selectedDevice]
                } else {
                    candidateDevices.removeAll()
                }
                self.candidateCountLabel?.text = "\(displayedCandidateCount)"
                if self.candidateView.window != nil {
                    self.candidateView.candidateDevices = displayedCandidateDevices
                }
                DispatchQueue.main.async {
                    self.tableView.reloadData()
                }
                return
            }
            switch sectionTypes[section] {
            case .inRSSI:
                candidateDevices.append(contentsOf: inRSSIDevices.filter({ $0.selectedState == .selected }))
                inRSSIDevices.removeAll(where: { $0.selectedState == .selected })
            case .remainingRSSI:
                candidateDevices.append(contentsOf: remainingRSSIDevices.filter({ $0.selectedState == .selected }))
                remainingRSSIDevices.removeAll(where: { $0.selectedState == .selected })
            }
            self.candidateCountLabel?.text = "\(displayedCandidateCount)"
            if self.candidateView.window != nil {
                self.candidateView.candidateDevices = displayedCandidateDevices
            }
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
        
    }
    
}

extension DeviceAddProfessionalModeController: DeviceAddCandidateDeviceListViewDelegate {
    
    /// 设备开始identity
    func candidateView(_ view: DeviceAddCandidateDeviceListView, identify device: ProvisioningDevice) {
        identify(device)
    }
    
    /// 开始扫描
    func candidateViewStartScan(_ view: DeviceAddCandidateDeviceListView) {
        view.state = .scanning
        startScan()
    }
    
    /// 停止扫描
    func candidateViewStopScan(_ view: DeviceAddCandidateDeviceListView) {
        view.state = .none
        stopScan()
    }
    
    /// 设备预选撤销
    func candidateView(_ view: DeviceAddCandidateDeviceListView, candidateRevoke devices: [ProvisioningDevice]) {
        reloadDataing = true
        candidateDevices.removeAll(where: { device in devices.contains(where: { device.macAddress == $0.macAddress }) })
        view.candidateDevices = displayedCandidateDevices
        devices.forEach { device in
            device.addState = .none
            if isVisibleDeviceInCurrentAddMode(device) {
                if selectRSSIRange.contains(device.rssi.intValue) {
                    inRSSIDevices.append(device)
                }else {
                    remainingRSSIDevices.append(device)
                }
            }
            let cacheDevice = scanDevices.first(where: { scanDevice in scanDevice.macAddress == device.macAddress  })
            cacheDevice?.addState = .none
        }
       
        self.candidateCountLabel?.text = "\(displayedCandidateCount)"
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
        
//        if let index = candidateDevices.firstIndex(where: { $0.macAddress == device.macAddress }) {
//            reloadDataing = true
//            candidateDevices.remove(at: index)
//            view.candidateDevices = candidateDevices
//            if selectRSSIRange.contains(device.rssi.intValue) {
//                inRSSIDevices.append(device)
//                if !sectionTypes.contains(.inRSSI) {
//                    sectionTypes.append(.inRSSI)
//                }
//            }else {
//                remainingRSSIDevices.append(device)
//                if !sectionTypes.contains(.remainingRSSI) {
//                    sectionTypes.append(.remainingRSSI)
//                }
//            }
//            self.candidateCountLabel.text = "\(candidateDevices.count)"
//            DispatchQueue.main.async {
//                self.tableView.reloadData()
//            }
//        }
    }
    
    /// 设备开始添加
    func candidateView(_ view: DeviceAddCandidateDeviceListView, startAdd devices: [ProvisioningDevice]) {
        let selectableDevices = devices.filter { $0.selectedState != .disabled && isSelectableDevice($0) }
        let devicesToAdd = isSingleSelectionMode ? Array(selectableDevices.prefix(1)) : selectableDevices
        guard canStartVirtualTargetAdd() else {
            return
        }
        guard !devicesToAdd.isEmpty else {
            return
        }
        checkDeviceAddressesAreSufficient(devices: devicesToAdd)
    }
    
    /// 选择设备添加目地的
    func candidateView(_ view: DeviceAddCandidateDeviceListView, selectAddDevicesTarget touchPoint: CGPoint, currentDeviceTypes: [Node.DeviceType]) {
        if candidateDevices.contains(where: { $0.addState == .addConnecting || $0.addState == .adding }) {
            return
        }
        // 这里仅执行外部注入的通用限制，不引入具体设备业务判断。
        guard shouldAllowTargetSelection() else {
            showAddBehaviorTip()
            return
        }

        if forceBindToDongle != nil {
            XWHUDManager.showTipHUD("dongle_cannot_select_message".localizedString, isLineFeed: true)
            return
        }

        if appointGroup != nil {
            XWHUDManager.showTipHUD("group_cannot_select_message".localizedString, isLineFeed: true)
            return
        }

        DeviceAddTargetSelectView.show(
            anchorPoint: touchPoint,
            groups: MeshNetworkManager.instance.groups,
            batteryPowerSwitches: unboundBatteryPowerSwitches,
            acPowerSwitches: unboundACPowerSwitches,
            emergencyFireDevices: unboundEmergencyFireDevices,
            dongles: unboundDongles,
            selectedTarget: currentTargetSelection
        ) { [weak self] selection in
            guard let self else { return }
            self.applyTargetSelection(selection)
            self.setupDevicesData()
            self.tableView.reloadData()
        }
    }
    
    /// 刷新状态更新
    func candidateView(_ view: DeviceAddCandidateDeviceListView, refreshStateUpdate isRefresh: Bool) {
        
        self.isRefresh = isRefresh
        self.pauseBtn.isSelected = !isRefresh
        if !isRefresh {
            stopScanTimer()
        }
        view.isRefresh = isRefresh
    }
    
    
}
