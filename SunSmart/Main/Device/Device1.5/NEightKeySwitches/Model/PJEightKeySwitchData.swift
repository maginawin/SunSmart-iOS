//
//  PJEightKeySwitchData.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

enum PJEightKeyPowerSwitchKind: Int {
    case battery = 0
    case ac = 1

    static let companyIdentifier: UInt16 = 0x0A78
    static let batteryProductIdentifiers: Set<UInt16> = [0x2A01, 0x2A02]
    static let acProductIdentifiers: Set<UInt16> = [0x2A11, 0x2A12]

    static func make(companyIdentifier: UInt16?, productIdentifier: UInt16?) -> PJEightKeyPowerSwitchKind? {
        guard companyIdentifier == Self.companyIdentifier,
              let productIdentifier else {
            return nil
        }
        if batteryProductIdentifiers.contains(productIdentifier) {
            return .battery
        }
        if acProductIdentifiers.contains(productIdentifier) {
            return .ac
        }
        return nil
    }

    static func panelType(productIdentifier: UInt16?) -> PJEightKeySwitchPanelDefinition.PanelType? {
        switch productIdentifier {
        case 0x2A01, 0x2A11:
            return .scene8Key
        case 0x2A02, 0x2A12:
            return .brightness8Key
        default:
            return nil
        }
    }

    var deviceIconAssetName: String {
        switch self {
        case .battery:
            return "device_BatteryPowerSwitch"
        case .ac:
            return "device_ACPowerSwitch"
        }
    }
}

final class PJEightKeySwitchData: DeviceSwitchData {

    var eightKeyPanelType: PJEightKeySwitchPanelDefinition.PanelType = .scene8Key
    var powerSwitchKind: PJEightKeyPowerSwitchKind = .battery
    var moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State = .default
    var syncState: PJEightKeySwitchSyncState = .pending
    var desiredConfigVersion: Int = 0
    var desiredConfigHash: String = ""
    var appliedConfigHash: String = ""
    var lastSyncFailedReason: String?
    var lastSyncedAt: Int64?
    var batteryLevel: UInt8?
    var batteryLastUpdateTime: Int64?
    var appliedTxEnabled: Bool?
    var appliedLEDIndicatorEnabled: Bool?

    convenience init(baseSwitchData: DeviceSwitchData, metadata: PJEightKeySwitchRepository.Metadata) {
        self.init(
            id: baseSwitchData.id,
            enabled: baseSwitchData.enabled,
            name: baseSwitchData.name,
            linkGroupAddress: baseSwitchData.linkGroupAddress,
            subLinkGroupAddress: baseSwitchData.subLinkGroupAddress,
            bindGroupAddresses: baseSwitchData.bindGroupAddresses,
            sceneANumber: baseSwitchData.sceneANumber,
            sceneBNumber: baseSwitchData.sceneBNumber,
            sceneCNumber: baseSwitchData.sceneCNumber,
            sceneDNumber: baseSwitchData.sceneDNumber,
            proxyNodeAddress: baseSwitchData.proxyNodeAddress
        )
        update(switchData: baseSwitchData)
        unbindGroupAddresses = baseSwitchData.unbindGroupAddresses
        deleteProxyNodeAddress = baseSwitchData.deleteProxyNodeAddress
        enOceanMacAddress = baseSwitchData.enOceanMacAddress
        enOceanSecurityKey = baseSwitchData.enOceanSecurityKey
        maxKeyCount = 8
        eightKeyPanelType = metadata.panelType
        powerSwitchKind = metadata.powerSwitchKind
        moreSettingsState = metadata.moreSettingsState
        syncState = metadata.syncState
        desiredConfigVersion = metadata.desiredConfigVersion
        desiredConfigHash = metadata.desiredConfigHash
        appliedConfigHash = metadata.appliedConfigHash
        lastSyncFailedReason = metadata.lastSyncFailedReason
        lastSyncedAt = metadata.lastSyncedAt
        batteryLevel = metadata.batteryLevel
        batteryLastUpdateTime = metadata.batteryLastUpdateTime
        appliedTxEnabled = metadata.appliedTxEnabled
        appliedLEDIndicatorEnabled = metadata.appliedLEDIndicatorEnabled
    }

    override func copy() -> Self {
        let copy = PJEightKeySwitchData(
            id: id,
            enabled: enabled,
            name: name,
            linkGroupAddress: linkGroupAddress,
            subLinkGroupAddress: subLinkGroupAddress,
            bindGroupAddresses: bindGroupAddresses,
            sceneANumber: sceneANumber,
            sceneBNumber: sceneBNumber,
            sceneCNumber: sceneCNumber,
            sceneDNumber: sceneDNumber,
            proxyNodeAddress: proxyNodeAddress
        )
        copy.enOceanMacAddress = enOceanMacAddress
        copy.enOceanSecurityKey = enOceanSecurityKey
        copy.unbindGroupAddresses = unbindGroupAddresses
        copy.deleteProxyNodeAddress = deleteProxyNodeAddress
        copy.panelType = panelType
        copy.maxKeyCount = maxKeyCount
        copy.eightKeyPanelType = eightKeyPanelType
        copy.powerSwitchKind = powerSwitchKind
        copy.moreSettingsState = moreSettingsState
        copy.syncState = syncState
        copy.desiredConfigVersion = desiredConfigVersion
        copy.desiredConfigHash = desiredConfigHash
        copy.appliedConfigHash = appliedConfigHash
        copy.lastSyncFailedReason = lastSyncFailedReason
        copy.lastSyncedAt = lastSyncedAt
        copy.batteryLevel = batteryLevel
        copy.batteryLastUpdateTime = batteryLastUpdateTime
        copy.appliedTxEnabled = appliedTxEnabled
        copy.appliedLEDIndicatorEnabled = appliedLEDIndicatorEnabled
        return copy as! Self
    }

    var isACPowerSwitch: Bool {
        powerSwitchKind == .ac
    }

    var isBatteryPowerSwitchKind: Bool {
        powerSwitchKind == .battery
    }

    var requiresActivationBeforeOwnConfiguration: Bool {
        powerSwitchKind == .battery
    }

    var needsBatteryPowerSwitchConfigurationSync: Bool {
        guard proxyNode?.isPowerSwitch == true else {
            return false
        }
        let currentHash = batteryPowerSwitchDesiredConfigHash(appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index)
        return desiredConfigHash != currentHash || appliedConfigHash != currentHash
    }

    var needsBatteryPowerSwitchSync: Bool {
        guard proxyNode?.isPowerSwitch == true else {
            return false
        }
        return needsBatteryPowerSwitchConfigurationSync || needsBatteryPowerSwitchTxEnableSync || needsBatteryPowerSwitchLEDIndicatorSync || needSyncData
    }

    var needsBatteryPowerSwitchTxEnableSync: Bool {
        guard proxyNode?.isPowerSwitch == true else {
            return false
        }
        return appliedTxEnabled != enabled
    }

    var needsBatteryPowerSwitchLEDIndicatorSync: Bool {
        guard proxyNode?.isPowerSwitch == true else {
            return false
        }
        return appliedLEDIndicatorEnabled != moreSettingsState.ledIndicatorEnabled
    }

    func batteryPowerSwitchDesiredConfigHash(appKeyIndex: KeyIndex) -> String {
        let sceneTargets: String
        switch eightKeyPanelType {
        case .scene8Key:
            let sceneNumbers = [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber]
            let sceneTexts = sceneNumbers.map { sceneNumber -> String in
                guard let sceneNumber else {
                    return "nil"
                }
                return String(sceneNumber)
            }
            sceneTargets = sceneTexts.joined(separator: ",")
        case .brightness8Key:
            sceneTargets = "unused"
        }

        return [
            "panel=\(eightKeyPanelType.storageIdentifier)",
            "link=\(linkGroupAddress?.hex ?? "nil")",
            "keyConfigWire=16,retransmit=0/0,transition=FF",
            "scenes=\(sceneTargets)",
            "appKey=\(appKeyIndex)"
        ].joined(separator: "|")
    }

    func prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: KeyIndex) {
        let hash = batteryPowerSwitchDesiredConfigHash(appKeyIndex: appKeyIndex)
        if desiredConfigHash != hash {
            desiredConfigVersion = max(desiredConfigVersion + 1, 1)
        } else if desiredConfigVersion == 0 {
            desiredConfigVersion = 1
        }
        desiredConfigHash = hash
        syncState = .pending
        lastSyncFailedReason = nil
    }

    func markBatteryPowerSwitchSyncSucceeded(clearRemovedGroups: Bool = true) {
        syncState = .synced
        appliedConfigHash = desiredConfigHash
        appliedTxEnabled = enabled
        appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled
        lastSyncFailedReason = nil
        lastSyncedAt = Int64(Date().timeIntervalSince1970)
        if clearRemovedGroups {
            unbindGroupAddresses.removeAll()
        }
    }

    func markBatteryPowerSwitchSyncFailed(reason: String?) {
        syncState = .failed
        lastSyncFailedReason = reason
    }

    func markBatteryPowerSwitchTxEnableSucceeded() {
        appliedTxEnabled = enabled
        lastSyncFailedReason = nil
    }

    func markBatteryPowerSwitchLEDIndicatorSucceeded() {
        appliedLEDIndicatorEnabled = moreSettingsState.ledIndicatorEnabled
        lastSyncFailedReason = nil
    }

    func batteryPowerSwitchKeyConfigurations(appKeyIndex: KeyIndex) -> [BatteryPowerSwitchKeyConfiguration] {
        guard let linkGroupAddress else {
            return []
        }

        let appKeyIndex = UInt16(appKeyIndex)
        var configurations: [BatteryPowerSwitchKeyConfiguration] = []

        switch eightKeyPanelType {
        case .scene8Key:
            configurations.append(contentsOf: sceneRecallConfigurations(address: linkGroupAddress, appKeyIndex: appKeyIndex))
        case .brightness8Key:
            configurations.append(contentsOf: brightnessConfigurations(address: linkGroupAddress, appKeyIndex: appKeyIndex))
        }

        configurations.append(contentsOf: dimmingConfigurations(address: linkGroupAddress, appKeyIndex: appKeyIndex))
        configurations.append(contentsOf: onOffAndAutoConfigurations(address: linkGroupAddress, appKeyIndex: appKeyIndex))
        return configurations
    }

    var displayStatus: PJEightKeySwitchStatus {
        if let node = proxyNode, !node.isKeybindComplete {
            return .repairRequiredMode
        }
        let isBound = proxyNodeAddress != nil || !(enOceanMacAddress?.isEmpty ?? true)
        let needsSync = proxyNode?.isPowerSwitch == true ? needsBatteryPowerSwitchSync : needSyncData
        if isBound && needsSync {
            return .syncIssueBoundSwitch
        }
        if isBound {
            return enabled ? .boundEnabled : .boundDisabled
        }
        return enabled ? .unboundEnabled : .unboundDisabled
    }

    var displayIconAssetName: String {
        if powerSwitchKind == .ac, proxyNode?.state == false {
            return "device_ACPowerSwitch_offline"
        }
        return powerSwitchKind.deviceIconAssetName
    }
}

private extension PJEightKeySwitchPanelDefinition.PanelType {
    var storageIdentifier: String {
        switch self {
        case .scene8Key:
            return "scene8Key"
        case .brightness8Key:
            return "brightness8Key"
        }
    }
}

private extension PJEightKeySwitchData {

    static let dimmingDeltaStepLevel: Int16 = 13107
    static let dimmingMoveStepLevel: Int16 = 6553

    func sceneRecallConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        let sceneNumbers = [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber]
        return sceneNumbers.enumerated().map { index, sceneNumber in
            guard let sceneNumber else {
                return BatteryPowerSwitchKeyConfiguration(
                    button: UInt8(index),
                    trigger: .click,
                    type: .disabled,
                    address: address,
                    appKeyIndex: appKeyIndex
                )
            }
            return BatteryPowerSwitchKeyConfiguration(
                button: UInt8(index),
                trigger: .click,
                type: .sceneRecall,
                sceneId: sceneNumber,
                address: address,
                appKeyIndex: appKeyIndex
            )
        }
    }

    func brightnessConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        [100, 75, 50, 25].enumerated().map { index, lightness in
            BatteryPowerSwitchKeyConfiguration(
                button: UInt8(index),
                trigger: .click,
                type: .lightnessSet,
                level: Int16(bitPattern: Node.getLightness(lightness100: lightness)),
                address: address,
                appKeyIndex: appKeyIndex
            )
        }
    }

    func dimmingConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        [
            dimmingConfiguration(button: 4, trigger: .click, level: Self.dimmingDeltaStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .press, level: Self.dimmingMoveStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .click, level: -Self.dimmingDeltaStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .press, level: -Self.dimmingMoveStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex)
        ]
    }

    func dimmingConfiguration(button: UInt8, trigger: BatteryPowerSwitchTrigger, level: Int16, address: Address, appKeyIndex: UInt16) -> BatteryPowerSwitchKeyConfiguration {
        BatteryPowerSwitchKeyConfiguration(
            button: button,
            trigger: trigger,
            type: trigger == .click ? .levelDelta : .levelMove,
            level: level,
            address: address,
            appKeyIndex: appKeyIndex
        )
    }

    func onOffAndAutoConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        [
            BatteryPowerSwitchKeyConfiguration(
                button: 6,
                trigger: .click,
                type: .onOffSet,
                value: 1,
                address: address,
                appKeyIndex: appKeyIndex
            ),
            BatteryPowerSwitchKeyConfiguration(
                button: 6,
                trigger: .press,
                type: .lightCtrlOnOff,
                value: 1,
                address: address,
                appKeyIndex: appKeyIndex
            ),
            BatteryPowerSwitchKeyConfiguration(
                button: 7,
                trigger: .click,
                type: .onOffSet,
                value: 0,
                address: address,
                appKeyIndex: appKeyIndex
            )
        ]
    }
}
