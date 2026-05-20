//
//  PJEightKeySwitchData.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import UIKit
import NordicSigMeshSDK

final class PJEightKeySwitchData: DeviceSwitchData {

    var eightKeyPanelType: PJEightKeySwitchPanelDefinition.PanelType = .scene8Key
    var moreSettingsState: PJEightKeySwitchMoreSettingsViewModel.State = .default
    var syncState: PJEightKeySwitchSyncState = .pending
    var desiredConfigVersion: Int = 0
    var desiredConfigHash: String = ""
    var appliedConfigHash: String = ""
    var lastSyncFailedReason: String?
    var lastSyncedAt: Int64?

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
        moreSettingsState = metadata.moreSettingsState
        syncState = metadata.syncState
        desiredConfigVersion = metadata.desiredConfigVersion
        desiredConfigHash = metadata.desiredConfigHash
        appliedConfigHash = metadata.appliedConfigHash
        lastSyncFailedReason = metadata.lastSyncFailedReason
        lastSyncedAt = metadata.lastSyncedAt
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
        copy.moreSettingsState = moreSettingsState
        copy.syncState = syncState
        copy.desiredConfigVersion = desiredConfigVersion
        copy.desiredConfigHash = desiredConfigHash
        copy.appliedConfigHash = appliedConfigHash
        copy.lastSyncFailedReason = lastSyncFailedReason
        copy.lastSyncedAt = lastSyncedAt
        return copy as! Self
    }

    var needsBatteryPowerSwitchConfigurationSync: Bool {
        guard proxyNode?.isBatteryPowerSwitch == true else {
            return false
        }
        let currentHash = batteryPowerSwitchDesiredConfigHash(appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index)
        return desiredConfigHash != currentHash || appliedConfigHash != currentHash
    }

    var needsBatteryPowerSwitchSync: Bool {
        guard proxyNode?.isBatteryPowerSwitch == true else {
            return false
        }
        return needsBatteryPowerSwitchConfigurationSync || needSyncData
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
            "enabled=\(enabled)",
            "link=\(linkGroupAddress?.hex ?? "nil")",
            "publication=profileClients@link,retransmit=1/200",
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

    func batteryPowerSwitchKeyConfigurations(appKeyIndex: KeyIndex) -> [BatteryPowerSwitchKeyConfiguration] {
        guard enabled, let linkGroupAddress else {
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
        let needsSync = proxyNode?.isBatteryPowerSwitch == true ? needsBatteryPowerSwitchSync : needSyncData
        if isBound && needsSync {
            return .syncIssueBoundSwitch
        }
        if isBound {
            return enabled ? .boundEnabled : .boundDisabled
        }
        return enabled ? .unboundEnabled : .unboundDisabled
    }

    var displayIconAssetName: String {
        UIImage(named: displayStatus.iconAssetName) != nil ? displayStatus.iconAssetName : "eight_key_switch_bound_enabled"
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

    static let dimmingStepLevel: Int16 = 13107

    func sceneRecallConfigurations(address: Address, appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        let sceneNumbers = [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber]
        return sceneNumbers.enumerated().compactMap { index, sceneNumber in
            guard let sceneNumber else {
                return nil
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
            dimmingConfiguration(button: 4, trigger: .click, level: Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .press, level: Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 4, trigger: .pressRelease, level: 0, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .click, level: -Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
            dimmingConfiguration(button: 5, trigger: .press, level: -Self.dimmingStepLevel, address: address, appKeyIndex: appKeyIndex),
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
