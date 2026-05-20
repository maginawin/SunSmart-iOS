//
//  PJEightKeySwitchMonitorViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK
import UIKit

final class PJEightKeySwitchMonitorViewModel {

    struct HeaderState {
        enum StatusStyle {
            case normal
            case lowBattery
            case fault
            case unknown
        }

        let batteryText: String
        let batteryIconSystemName: String
        let statusPrefixText: String
        let statusText: String
        let statusColor: UIColor
        let updatedText: String
        let style: StatusStyle
    }

    struct KeyItem {
        enum Style {
            case scene
            case brightness
            case dimming(direction: Direction)
            case toggle(kind: ToggleKind)
        }

        enum Direction {
            case up
            case down
        }

        enum ToggleKind {
            case on
            case off
        }

        let style: Style
        let topText: String?
        let mainText: String
        let detailText: String?
    }

    struct SettingsState {
        let groupNames: [String]
        let isGroupLinked: Bool
        let isEnabled: Bool
    }

    let space: SpaceData
    private(set) var switchData: PJEightKeySwitchData

    init(space: SpaceData, switchData: PJEightKeySwitchData) {
        self.space = space
        self.switchData = switchData
    }

    var title: String {
        switchData.name
    }

    var isRealBatteryPowerSwitch: Bool {
        informationNode != nil
    }

    var informationNode: Node? {
        guard let node = switchData.proxyNode, node.isBatteryPowerSwitch else {
            return nil
        }
        return node
    }

    var informationGroupText: String? {
        let names = switchData.bindGroups.map(\.name)
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var showsInformationSceneSection: Bool {
        switchData.eightKeyPanelType == .scene8Key
    }

    var informationSceneText: String? {
        guard showsInformationSceneSection else {
            return nil
        }
        let names = [switchData.sceneA, switchData.sceneB, switchData.sceneC, switchData.sceneD]
            .compactMap { $0?.name }
        return names.isEmpty ? nil : names.joined(separator: ", ")
    }

    var needsBatteryPowerSwitchSync: Bool {
        switchData.proxyNode?.isBatteryPowerSwitch == true && switchData.needsBatteryPowerSwitchSync
    }

    var panelDefinition: PJEightKeySwitchPanelDefinition {
        .make(type: switchData.eightKeyPanelType)
    }

    var headerState: HeaderState {
        switch switchData.displayStatus {
        case .boundEnabled:
            return HeaderState(
                batteryText: "95%",
                batteryIconSystemName: "battery.100",
                statusPrefixText: "neightkeyswitches_status_prefix".localizedString,
                statusText: "neightkeyswitches_status_normal".localizedString,
                statusColor: RGB(69, 197, 122),
                updatedText: "neightkeyswitches_updated_2min".localizedString,
                style: .normal
            )
        case .boundDisabled:
            return HeaderState(
                batteryText: "10%",
                batteryIconSystemName: "battery.25",
                statusPrefixText: "neightkeyswitches_status_prefix".localizedString,
                statusText: "neightkeyswitches_status_low_battery".localizedString,
                statusColor: RGB(240, 162, 55),
                updatedText: "neightkeyswitches_updated_2min".localizedString,
                style: .lowBattery
            )
        case .syncIssueBoundSwitch, .repairRequiredMode:
            return HeaderState(
                batteryText: "--",
                batteryIconSystemName: "battery.25",
                statusPrefixText: "neightkeyswitches_status_prefix".localizedString,
                statusText: "neightkeyswitches_status_fault".localizedString,
                statusColor: RGB(247, 94, 82),
                updatedText: "neightkeyswitches_updated_2min".localizedString,
                style: .fault
            )
        case .unboundEnabled, .unboundDisabled:
            return HeaderState(
                batteryText: "--",
                batteryIconSystemName: "battery.25",
                statusPrefixText: "neightkeyswitches_status_prefix".localizedString,
                statusText: "neightkeyswitches_status_unknown".localizedString,
                statusColor: RGB(164, 174, 200),
                updatedText: "neightkeyswitches_updated_7day".localizedString,
                style: .unknown
            )
        }
    }

    var settingsState: SettingsState {
        SettingsState(
            groupNames: switchData.bindGroups.map(\.name),
            isGroupLinked: switchData.linkGroupAddress != nil,
            isEnabled: switchData.enabled
        )
    }

    var keyItems: [KeyItem] {
        switch switchData.eightKeyPanelType {
        case .scene8Key:
            return [
                .init(style: .scene, topText: nil, mainText: "1", detailText: switchData.sceneA?.name),
                .init(style: .scene, topText: nil, mainText: "2", detailText: switchData.sceneB?.name),
                .init(style: .scene, topText: nil, mainText: "3", detailText: switchData.sceneC?.name),
                .init(style: .scene, topText: nil, mainText: "4", detailText: switchData.sceneD?.name),
                .init(style: .dimming(direction: .up), topText: "neightkeyswitches_long_press_dimming".localizedString, mainText: "", detailText: nil),
                .init(style: .dimming(direction: .down), topText: "neightkeyswitches_long_press_dimming".localizedString, mainText: "", detailText: nil),
                .init(style: .toggle(kind: .on), topText: "neightkeyswitches_long_press_auto".localizedString, mainText: "ON".localizedString, detailText: nil),
                .init(style: .toggle(kind: .off), topText: nil, mainText: "OFF".localizedString, detailText: nil)
            ]
        case .brightness8Key:
            return [
                .init(style: .brightness, topText: nil, mainText: "1", detailText: "100%"),
                .init(style: .brightness, topText: nil, mainText: "2", detailText: "75%"),
                .init(style: .brightness, topText: nil, mainText: "3", detailText: "50%"),
                .init(style: .brightness, topText: nil, mainText: "4", detailText: "25%"),
                .init(style: .dimming(direction: .up), topText: "neightkeyswitches_long_press_dimming".localizedString, mainText: "", detailText: nil),
                .init(style: .dimming(direction: .down), topText: "neightkeyswitches_long_press_dimming".localizedString, mainText: "", detailText: nil),
                .init(style: .toggle(kind: .on), topText: "neightkeyswitches_long_press_auto".localizedString, mainText: "ON".localizedString, detailText: nil),
                .init(style: .toggle(kind: .off), topText: nil, mainText: "OFF".localizedString, detailText: nil)
            ]
        }
    }

    func updateEnabled(_ isEnabled: Bool) {
        switchData.enabled = isEnabled
    }

    func prepareBatteryPowerSwitchDesiredConfigIfNeeded() -> Bool {
        guard switchData.proxyNode?.isBatteryPowerSwitch == true else {
            return true
        }
        guard MeshNetworkManager.instance.ensureBatteryPowerSwitchLinkGroup(switchData) else {
            return false
        }
        let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
        if switchData.needsBatteryPowerSwitchConfigurationSync {
            switchData.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: appKeyIndex)
        }
        return true
    }

    func updateSwitchData(_ switchData: PJEightKeySwitchData) {
        self.switchData = switchData
    }

    func persist() {
        switchData.save()
        PJEightKeySwitchRepository.shared.save(switchData)
    }
}

private extension PJEightKeySwitchMoreSettingsViewModel.PeriodicReportingOption {
    var displayTitle: String {
        switch self {
        case .disabled:
            return "neightkeyswitches_reporting_disable".localizedString
        case .fifteenMinutes:
            return "neightkeyswitches_reporting_15min".localizedString
        case .thirtyMinutes:
            return "neightkeyswitches_reporting_30min".localizedString
        case .oneHour:
            return "neightkeyswitches_reporting_1hr".localizedString
        case .fiveHours:
            return "neightkeyswitches_reporting_5hr".localizedString
        case .tenHours:
            return "neightkeyswitches_reporting_10hr".localizedString
        }
    }
}
