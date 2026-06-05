//
//  GroupPowerSwitchesViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

final class GroupPowerSwitchesViewModel {

    enum Kind {
        case battery
        case ac

        var title: String {
            switch self {
            case .battery:
                return "Battery Power Switch"
            case .ac:
                return "AC Power Switch"
            }
        }

        var powerSwitchKind: PJEightKeyPowerSwitchKind {
            switch self {
            case .battery:
                return .battery
            case .ac:
                return .ac
            }
        }
    }

    struct EditSnapshot: Equatable {
        let panelType: PJEightKeySwitchPanelDefinition.PanelType
        let periodicReporting: PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption
        let ledIndicatorEnabled: Bool
        let sceneANumber: SceneNumber?
        let sceneBNumber: SceneNumber?
        let sceneCNumber: SceneNumber?
        let sceneDNumber: SceneNumber?
    }

    let group: Group
    let kind: Kind
    private(set) var switchDatas: [PJEightKeySwitchData] = []
    private var sourceSwitchDatas: [String: PJEightKeySwitchData] = [:]

    init(group: Group, kind: Kind) {
        self.group = group
        self.kind = kind
        reloadFromCurrentNetwork()
    }

    var groupAddress: Address {
        group.address.address
    }

    func reloadFromCurrentNetwork() {
        switchDatas = powerSwitches(in: group).map { $0.copy() }
        sourceSwitchDatas = Dictionary(uniqueKeysWithValues: switchDatas.map { ($0.id, $0.copy()) })
    }

    func switchData(at index: Int) -> PJEightKeySwitchData {
        switchDatas[index]
    }

    func sourceSwitchData(id: String) -> PJEightKeySwitchData? {
        sourceSwitchDatas[id]
    }

    func isRealSwitch(_ switchData: PJEightKeySwitchData) -> Bool {
        switchData.proxyNode?.isPowerSwitch == true
    }

    func detailText(for switchData: PJEightKeySwitchData) -> String {
        guard isRealSwitch(switchData) else {
            return "not_linked_to_switch".localizedString
        }
        if let mac = switchData.proxyNode?.macAddressResult, !mac.isEmpty {
            return "MAC: \(mac)"
        }
        if let mac = switchData.enOceanMacAddress, !mac.isEmpty {
            return "MAC: \(mac.getMacAddressSegmentString())"
        }
        return "MAC: N/A"
    }

    func groupTitle(for switchData: PJEightKeySwitchData) -> String {
        let names = switchData.bindGroups.map(\.name)
        return names.isEmpty ? "N/A" : names.joined(separator: ", ")
    }

    func sceneTitle(for switchData: PJEightKeySwitchData) -> String {
        guard switchData.eightKeyPanelType == .scene8Key else {
            return "N/A"
        }
        let names = [switchData.sceneA, switchData.sceneB, switchData.sceneC, switchData.sceneD]
            .compactMap { $0?.name }
        return names.isEmpty ? "N/A" : names.joined(separator: ", ")
    }

    func moreSettingsTitle(for switchData: PJEightKeySwitchData) -> String {
        let reporting = switchData.moreSettingsState.periodicReporting.title
        let led = switchData.moreSettingsState.ledIndicatorEnabled ? "ON".localizedString : "OFF".localizedString
        return "\(reporting), LED \(led)"
    }

    func showsSceneRow(for switchData: PJEightKeySwitchData) -> Bool {
        switchData.eightKeyPanelType == .scene8Key
    }

    func hasSaveChanges(_ switchData: PJEightKeySwitchData) -> Bool {
        guard let source = sourceSwitchDatas[switchData.id] else {
            return true
        }
        return editSnapshot(for: switchData) != editSnapshot(for: source)
    }

    func updatePanelType(_ panelType: PJEightKeySwitchPanelDefinition.PanelType, for switchData: PJEightKeySwitchData) {
        switchData.eightKeyPanelType = panelType
        switchData.panelType = panelType == .scene8Key ? .scenes_4key : .default_4key
        if panelType == .brightness8Key {
            clearScenes(for: switchData)
        }
    }

    func updateScenes(_ sceneDatas: [SwitchSceneData], for switchData: PJEightKeySwitchData) {
        sceneDatas.forEach { sceneData in
            switch sceneData.type {
            case .sceneA:
                switchData.sceneANumber = sceneData.scene?.number
            case .sceneB:
                switchData.sceneBNumber = sceneData.scene?.number
            case .sceneC:
                switchData.sceneCNumber = sceneData.scene?.number
            case .sceneD:
                switchData.sceneDNumber = sceneData.scene?.number
            }
        }
    }

    func updateMoreSettings(_ state: PJEightKeySwitchMoreSettingsViewModel.State, for switchData: PJEightKeySwitchData) {
        switchData.moreSettingsState = state
    }

    func applyEnabled(_ enabled: Bool, to switchData: PJEightKeySwitchData, markTxEnableSucceeded: Bool) {
        switchData.enabled = enabled
        if markTxEnableSucceeded {
            switchData.markBatteryPowerSwitchTxEnableSucceeded()
        }
        replaceLocalSwitchData(switchData)
        if let source = sourceSwitchDatas[switchData.id] {
            source.enabled = enabled
            if markTxEnableSucceeded {
                source.markBatteryPowerSwitchTxEnableSucceeded()
            }
        }
    }

    func makeVirtualSwitch() -> PJEightKeySwitchData? {
        guard MeshNetworkManager.instance.switchs.count < 16 else {
            return nil
        }
        let switchData = PJEightKeySwitchData(
            id: UUID().uuidString,
            enabled: true,
            name: MeshNetworkManager.instance.getNextSwitchName(),
            linkGroupAddress: nil,
            subLinkGroupAddress: nil,
            bindGroupAddresses: [groupAddress],
            sceneANumber: nil,
            sceneBNumber: nil,
            sceneCNumber: nil,
            sceneDNumber: nil,
            proxyNodeAddress: nil
        )
        switchData.maxKeyCount = 8
        switchData.panelType = .scenes_4key
        switchData.eightKeyPanelType = .scene8Key
        switchData.powerSwitchKind = kind.powerSwitchKind
        switchData.moreSettingsState = .default
        switchData.syncState = .synced
        switchData.desiredConfigVersion = 0
        switchData.desiredConfigHash = ""
        switchData.appliedConfigHash = ""
        switchData.lastSyncFailedReason = nil
        switchData.lastSyncedAt = nil
        switchData.appliedTxEnabled = nil
        switchData.appliedLEDIndicatorEnabled = nil
        return switchData
    }

    func detachCurrentGroup(from switchData: PJEightKeySwitchData, requiresCleanupSync: Bool) {
        switchData.bindGroupAddresses.removeAll(where: { $0 == groupAddress })
        if requiresCleanupSync, !switchData.unbindGroupAddresses.contains(groupAddress) {
            switchData.unbindGroupAddresses.append(groupAddress)
        }
        replaceLocalSwitchData(switchData)
    }

    @discardableResult
    func persist(_ switchData: PJEightKeySwitchData) -> Bool {
        guard switchData.save(),
              PJEightKeySwitchRepository.shared.save(switchData) else {
            return false
        }

        if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
            MeshNetworkManager.instance.switchs[index] = switchData
        } else {
            MeshNetworkManager.instance.switchs.append(switchData)
        }
        replaceLocalSwitchData(switchData)
        sourceSwitchDatas[switchData.id] = switchData.copy()
        return true
    }

    func removeLocalSwitchData(id: String) {
        switchDatas.removeAll(where: { $0.id == id })
        sourceSwitchDatas.removeValue(forKey: id)
    }

    func replaceLocalSwitchData(_ switchData: PJEightKeySwitchData) {
        if let index = switchDatas.firstIndex(where: { $0.id == switchData.id }) {
            switchDatas[index] = switchData
        } else if switchData.bindGroupAddresses.contains(groupAddress),
                  switchData.powerSwitchKind == kind.powerSwitchKind {
            switchDatas.append(switchData)
        }
    }

    private func powerSwitches(in group: Group) -> [PJEightKeySwitchData] {
        group.info.switchs.compactMap { switchData in
            let powerSwitch = makePowerSwitch(from: switchData)
            guard powerSwitch?.powerSwitchKind == kind.powerSwitchKind else {
                return nil
            }
            return powerSwitch
        }
    }

    private func makePowerSwitch(from switchData: DeviceSwitchData) -> PJEightKeySwitchData? {
        if let powerSwitch = switchData as? PJEightKeySwitchData {
            return powerSwitch
        }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: switchData)
    }

    private func clearScenes(for switchData: PJEightKeySwitchData) {
        switchData.sceneANumber = nil
        switchData.sceneBNumber = nil
        switchData.sceneCNumber = nil
        switchData.sceneDNumber = nil
    }

    private func editSnapshot(for switchData: PJEightKeySwitchData) -> EditSnapshot {
        EditSnapshot(
            panelType: switchData.eightKeyPanelType,
            periodicReporting: switchData.moreSettingsState.periodicReporting,
            ledIndicatorEnabled: switchData.moreSettingsState.ledIndicatorEnabled,
            sceneANumber: switchData.eightKeyPanelType == .scene8Key ? switchData.sceneANumber : nil,
            sceneBNumber: switchData.eightKeyPanelType == .scene8Key ? switchData.sceneBNumber : nil,
            sceneCNumber: switchData.eightKeyPanelType == .scene8Key ? switchData.sceneCNumber : nil,
            sceneDNumber: switchData.eightKeyPanelType == .scene8Key ? switchData.sceneDNumber : nil
        )
    }
}
