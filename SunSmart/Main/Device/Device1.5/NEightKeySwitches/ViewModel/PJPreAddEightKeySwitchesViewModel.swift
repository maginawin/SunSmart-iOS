//
//  PJPreAddEightKeySwitchesViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

struct PJPreAddEightKeySwitchesViewModel {

    let space: SpaceData
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

    init(space: SpaceData) {
        self.space = space
        self.deviceName = MeshNetworkManager.instance.getNextSwitchName()
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

    func buildSwitchData() -> PJEightKeySwitchData {
        let switchData = PJEightKeySwitchData(
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
        switchData.maxKeyCount = 8
        switchData.panelType = selectedPanelType == .scene8Key ? .scenes_4key : .default_4key
        switchData.eightKeyPanelType = selectedPanelType
        switchData.moreSettingsState = moreSettings
        return switchData
    }
}
