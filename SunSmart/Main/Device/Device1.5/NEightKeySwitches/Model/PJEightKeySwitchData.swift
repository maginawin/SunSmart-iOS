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
        return copy as! Self
    }

    var displayStatus: PJEightKeySwitchStatus {
        if let node = proxyNode, !node.isKeybindComplete {
            return .repairRequiredMode
        }
        let isBound = proxyNodeAddress != nil || !(enOceanMacAddress?.isEmpty ?? true)
        if isBound && needSyncData {
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
