//
//  PJPreAddEightKeySwitchesViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

struct PJPreAddEightKeySwitchesViewModel {

    enum CreationKind {
        case kineticSwitch
        case batteryPowerSwitch
    }

    let space: SpaceData
    let sourceSwitchData: PJEightKeySwitchData?
    let creationKind: CreationKind
    var deviceName: String
    var isEnabled = true
    var selectedPanelType: PJEightKeySwitchPanelDefinition.PanelType = .scene8Key
    var selectedGroups: [Group] = []
    var moreSettings = PJEightKeySwitchMoreSettingsViewModel.State.default
    var sceneDatas: [SwitchSceneData] = [
        .init(type: .sceneA),
        .init(type: .sceneB),
        .init(type: .sceneC),
        .init(type: .sceneD)
    ]

    init(space: SpaceData, creationKind: CreationKind = .kineticSwitch) {
        self.space = space
        self.sourceSwitchData = nil
        self.creationKind = creationKind
        self.deviceName = MeshNetworkManager.instance.getNextSwitchName()
    }

    init(space: SpaceData, switchData: PJEightKeySwitchData) {
        self.space = space
        self.sourceSwitchData = switchData
        self.creationKind = .batteryPowerSwitch
        self.deviceName = switchData.name
        self.isEnabled = switchData.enabled
        self.selectedPanelType = switchData.eightKeyPanelType
        self.selectedGroups = switchData.bindGroups
        self.moreSettings = switchData.moreSettingsState
        self.sceneDatas = [
            .init(type: .sceneA, scene: switchData.sceneA),
            .init(type: .sceneB, scene: switchData.sceneB),
            .init(type: .sceneC, scene: switchData.sceneC),
            .init(type: .sceneD, scene: switchData.sceneD)
        ]
    }

    var panelTitle: String {
        selectedPanelType.title
    }

    var selectedPanelDefinition: PJEightKeySwitchPanelDefinition {
        PJEightKeySwitchPanelDefinition.make(type: selectedPanelType)
    }

    var groupTitle: String {
        let names = selectedGroups.map(\.name)
        return names.isEmpty ? "N/A" : names.joined(separator: ",")
    }

    var sceneTitle: String {
        let names = sceneDatas.compactMap(\.scene?.name)
        return names.isEmpty ? "N/A" : names.joined(separator: ",")
    }

    var showsSceneRow: Bool {
        selectedPanelType == .scene8Key
    }

    var isBatteryPowerSwitchPreCreate: Bool {
        sourceSwitchData == nil && creationKind == .batteryPowerSwitch
    }

    mutating func clearSceneDatas() {
        sceneDatas = [
            .init(type: .sceneA),
            .init(type: .sceneB),
            .init(type: .sceneC),
            .init(type: .sceneD)
        ]
    }

    func buildSwitchData() -> PJEightKeySwitchData {
        let switchData = sourceSwitchData?.copy() ?? PJEightKeySwitchData(
            id: UUID().uuidString,
            enabled: isEnabled,
            name: deviceName,
            linkGroupAddress: nil,
            subLinkGroupAddress: nil,
            bindGroupAddresses: selectedGroups.map(\.address.address),
            sceneANumber: sceneDatas.first(where: { $0.type == .sceneA })?.scene?.number,
            sceneBNumber: sceneDatas.first(where: { $0.type == .sceneB })?.scene?.number,
            sceneCNumber: sceneDatas.first(where: { $0.type == .sceneC })?.scene?.number,
            sceneDNumber: sceneDatas.first(where: { $0.type == .sceneD })?.scene?.number,
            proxyNodeAddress: nil
        )
        switchData.enabled = isEnabled
        switchData.name = deviceName
        switchData.bindGroupAddresses = selectedGroups.map(\.address.address)
        switchData.sceneANumber = sceneDatas.first(where: { $0.type == .sceneA })?.scene?.number
        switchData.sceneBNumber = sceneDatas.first(where: { $0.type == .sceneB })?.scene?.number
        switchData.sceneCNumber = sceneDatas.first(where: { $0.type == .sceneC })?.scene?.number
        switchData.sceneDNumber = sceneDatas.first(where: { $0.type == .sceneD })?.scene?.number
        switchData.maxKeyCount = 8
        switchData.panelType = selectedPanelType == .scene8Key ? .scenes_4key : .default_4key
        switchData.eightKeyPanelType = selectedPanelType
        switchData.moreSettingsState = moreSettings
        if isBatteryPowerSwitchPreCreate {
            switchData.syncState = .synced
            switchData.desiredConfigVersion = 0
            switchData.desiredConfigHash = ""
            switchData.appliedConfigHash = ""
            switchData.lastSyncFailedReason = nil
            switchData.lastSyncedAt = nil
            switchData.appliedTxEnabled = nil
            switchData.appliedLEDIndicatorEnabled = nil
        }
        return switchData
    }
}
