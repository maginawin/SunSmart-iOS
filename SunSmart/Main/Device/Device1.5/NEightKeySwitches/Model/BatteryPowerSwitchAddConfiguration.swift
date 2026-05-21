//
//  BatteryPowerSwitchAddConfiguration.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

enum BatteryPowerSwitchAddConfiguration {

    static func isSupportedAddNode(_ node: Node) -> Bool {
        guard node.isBatteryPowerSwitch else {
            return false
        }
        switch node.productIdentifier {
        case 0x2A01, 0x2A02:
            return true
        default:
            return false
        }
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

    static func markSucceeded(_ switchData: PJEightKeySwitchData) {
        switchData.markBatteryPowerSwitchSyncSucceeded()
        persist(switchData)
    }

    static func markFailed(_ switchData: PJEightKeySwitchData, reason: String?) {
        switchData.markBatteryPowerSwitchSyncFailed(reason: reason)
        persist(switchData)
    }

    private static func persist(_ switchData: PJEightKeySwitchData) {
        switchData.save()
        PJEightKeySwitchRepository.shared.save(switchData)
    }
}
