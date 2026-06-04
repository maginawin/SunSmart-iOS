//
//  BatteryPowerSwitchAddConfiguration.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

enum BatteryPowerSwitchAddConfiguration {

    enum LinkPreparationError: Error {
        case unsupportedNode
        case alreadyLinked(String)
        case insufficientGroupAddress

        var message: String {
            switch self {
            case .unsupportedNode:
                return "Cannot add, type mismatch"
            case .alreadyLinked(let name):
                return String(format: "switch_proxy_exist".localizedString, name)
            case .insufficientGroupAddress:
                return "group_address_insufficient_message".localizedString
            }
        }
    }

    enum RestorePreparationError: Error {
        case unsupportedNode
        case alreadyLinked(String)
        case missingLinkGroup

        var message: String {
            switch self {
            case .unsupportedNode:
                return "Cannot add, type mismatch"
            case .alreadyLinked(let name):
                return String(format: "switch_proxy_exist".localizedString, name)
            case .missingLinkGroup:
                return "group_address_insufficient_message".localizedString
            }
        }
    }

    static func isSupportedAddNode(_ node: Node) -> Bool {
        return node.isPowerSwitch
    }

    static func prepareSwitchData(for node: Node) -> PJEightKeySwitchData? {
        guard isSupportedAddNode(node) else {
            return nil
        }
        guard let switchData = MeshNetworkManager.instance
            .createDefaultSwitch(forBatteryPowerSwitch: node)?
            .batteryPowerSwitchData else {
            return nil
        }

        if let kind = node.powerSwitchKind {
            switchData.powerSwitchKind = kind
        }
        switchData.enabled = true
        switchData.appliedTxEnabled = true
        switchData.moreSettingsState.ledIndicatorEnabled = true
        switchData.appliedLEDIndicatorEnabled = true
        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
            markFailed(switchData, reason: "group_address_insufficient_message".localizedString)
            return switchData
        }

        switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        persist(switchData)
        return switchData
    }

    static func prepareLinkedSwitchData(
        sourceSwitchData: PJEightKeySwitchData,
        node: Node
    ) -> Result<PJEightKeySwitchData, LinkPreparationError> {
        guard isSupportedAddNode(node) else {
            return .failure(.unsupportedNode)
        }
        guard node.powerSwitchKind == sourceSwitchData.powerSwitchKind,
              node.batteryPowerSwitchPanelType == sourceSwitchData.eightKeyPanelType else {
            return .failure(.unsupportedNode)
        }

        if let existingSwitch = MeshNetworkManager.instance.switchs.first(where: {
            $0.id != sourceSwitchData.id && $0.proxyNodeAddress == node.primaryUnicastAddress
        }) {
            return .failure(.alreadyLinked(existingSwitch.name))
        }

        let switchData = sourceSwitchData.copy()
        switchData.proxyNodeAddress = node.primaryUnicastAddress
        switchData.powerSwitchKind = sourceSwitchData.powerSwitchKind
        switchData.maxKeyCount = 8
        switchData.panelType = switchData.eightKeyPanelType == .scene8Key ? .scenes_4key : .default_4key
        switchData.subLinkGroupAddress = nil

        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            return .failure(.insufficientGroupAddress)
        }

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        switchData.appliedConfigHash = ""
        switchData.lastSyncFailedReason = nil
        return .success(switchData)
    }

    static func prepareRestoreSwitchData(
        sourceSwitchData: PJEightKeySwitchData,
        node: Node
    ) -> Result<PJEightKeySwitchData, RestorePreparationError> {
        guard isSupportedAddNode(node) else {
            return .failure(.unsupportedNode)
        }
        guard node.powerSwitchKind == sourceSwitchData.powerSwitchKind,
              node.batteryPowerSwitchPanelType == sourceSwitchData.eightKeyPanelType else {
            return .failure(.unsupportedNode)
        }

        if let existingSwitch = MeshNetworkManager.instance.switchs.first(where: {
            $0.id != sourceSwitchData.id && $0.proxyNodeAddress == node.primaryUnicastAddress
        }) {
            return .failure(.alreadyLinked(existingSwitch.name))
        }

        guard sourceSwitchData.linkGroupAddress != nil else {
            return .failure(.missingLinkGroup)
        }

        let switchData = sourceSwitchData.copy()
        switchData.proxyNodeAddress = node.primaryUnicastAddress
        switchData.powerSwitchKind = sourceSwitchData.powerSwitchKind
        switchData.maxKeyCount = 8
        switchData.subLinkGroupAddress = nil
        switchData.batteryLevel = nil
        switchData.batteryLastUpdateTime = nil
        switchData.appliedConfigHash = ""
        switchData.appliedTxEnabled = nil
        switchData.appliedLEDIndicatorEnabled = nil
        switchData.lastSyncFailedReason = nil

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        return .success(switchData)
    }

    static func defaultConfigurationMessageHandles(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> [MeshMessageHandle] {
        guard isSupportedAddNode(node),
              node.primaryUnicastAddress == switchData.proxyNodeAddress,
              let vendorModel = node.sunricherVendorModel else {
            return []
        }

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        let keyConfigHandles = switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
            let handle = MeshMessageHandle(
                message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)),
                model: vendorModel
            )
            handle.continuous = false
            return handle
        }

        return keyConfigHandles
    }

    static func linkedConfigurationMessageHandles(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> [MeshMessageHandle] {
        guard isSupportedAddNode(node),
              node.primaryUnicastAddress == switchData.proxyNodeAddress,
              let vendorModel = node.sunricherVendorModel else {
            return []
        }

        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        var handles = switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
            let handle = MeshMessageHandle(
                message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)),
                model: vendorModel
            )
            handle.continuous = false
            return handle
        }

        let txHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(switchData.enabled)),
            model: vendorModel
        )
        txHandle.continuous = false
        handles.append(txHandle)

        let ledHandle = MeshMessageHandle(
            message: SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(switchData.moreSettingsState.ledIndicatorEnabled)),
            model: vendorModel
        )
        ledHandle.continuous = false
        handles.append(ledHandle)

        return handles
    }

    static func restoreConfigurationMessageHandles(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> [MeshMessageHandle] {
        linkedConfigurationMessageHandles(for: switchData, node: node)
    }

    struct InitialBatteryReadRequest {
        let switchData: PJEightKeySwitchData
        let nodeAddress: Address
    }

    static func makeInitialBatteryReadRequest(
        for switchData: PJEightKeySwitchData,
        node: Node
    ) -> InitialBatteryReadRequest? {
        guard isSupportedAddNode(node),
              node.isBatteryPowerSwitch else {
            return nil
        }
        return InitialBatteryReadRequest(
            switchData: switchData,
            nodeAddress: node.primaryUnicastAddress
        )
    }

    static func readInitialBatteryLevelsAndDisconnect(
        _ requests: [InitialBatteryReadRequest],
        fallbackDisconnectNodes: [Node],
        delay: TimeInterval = 0.5
    ) {
        let requestAddresses = Set(requests.map { $0.nodeAddress })
        fallbackDisconnectNodes
            .filter { $0.isBatteryPowerSwitch && !requestAddresses.contains($0.primaryUnicastAddress) }
            .forEach { MeshLibManager.manager.disconnectProxy(node: $0) }

        guard !requests.isEmpty else {
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            readInitialBatteryLevelsIfPossible(requests) {
                requests.forEach {
                    disconnectBatteryPowerSwitchNode(address: $0.nodeAddress)
                }
            }
        }
    }

    private static func readInitialBatteryLevelsIfPossible(
        _ requests: [InitialBatteryReadRequest],
        completion: @escaping () -> Void
    ) {
        readInitialBatteryLevelsIfPossible(
            requests,
            index: 0,
            completion: completion
        )
    }

    private static func readInitialBatteryLevelsIfPossible(
        _ requests: [InitialBatteryReadRequest],
        index: Int,
        completion: @escaping () -> Void
    ) {
        guard requests.indices.contains(index) else {
            completion()
            return
        }

        let request = requests[index]
        readInitialBatteryLevelIfPossible(for: request) {
            readInitialBatteryLevelsIfPossible(
                requests,
                index: index + 1,
                completion: completion
            )
        }
    }

    private static func readInitialBatteryLevelIfPossible(
        for request: InitialBatteryReadRequest,
        completion: @escaping () -> Void
    ) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: request.nodeAddress),
              isSupportedAddNode(node),
              node.isBatteryPowerSwitch else {
            DispatchQueue.main.async {
                completion()
            }
            return
        }

        MeshBatteryPowerSwitchBatteryReader().readBatteryLevel(from: node) { level in
            DispatchQueue.main.async {
                defer { completion() }
                guard let level else {
                    return
                }
                let timestamp = Int64(Date().timeIntervalSince1970)
                guard PJEightKeySwitchRepository.shared.saveBattery(
                    level: level,
                    lastUpdateTime: timestamp,
                    for: request.switchData
                ) else {
                    return
                }
                NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
            }
        }
    }

    private static func disconnectBatteryPowerSwitchNode(address: Address) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              isSupportedAddNode(node),
              node.isBatteryPowerSwitch else {
            return
        }
        MeshLibManager.manager.disconnectProxy(node: node)
    }

    @discardableResult
    static func markSucceeded(_ switchData: PJEightKeySwitchData, clearRemovedGroups: Bool = true) -> Bool {
        switchData.markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: clearRemovedGroups)
        return persist(switchData)
    }

    @discardableResult
    static func markFailed(_ switchData: PJEightKeySwitchData, reason: String?) -> Bool {
        switchData.markBatteryPowerSwitchSyncFailed(reason: reason)
        return persist(switchData)
    }

    @discardableResult
    private static func persist(_ switchData: PJEightKeySwitchData) -> Bool {
        guard switchData.save(),
              PJEightKeySwitchRepository.shared.save(switchData) else {
            return false
        }

        if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
            MeshNetworkManager.instance.switchs[index] = switchData
        } else {
            MeshNetworkManager.instance.switchs.append(switchData)
        }

        NotificationCenter.default.post(name: .init(switchsRefreshNotificationName), object: nil)
        NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.common)
        return true
    }
}
