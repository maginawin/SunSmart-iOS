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
        enum Layout {
            case battery
            case centeredStatus
        }

        enum StatusStyle {
            case normal
            case lowBattery
            case unknown
            case unlinked
        }

        let batteryText: String
        let batteryIconSystemName: String
        let statusPrefixText: String
        let statusText: String
        let statusColor: UIColor
        let updatedText: String
        let style: StatusStyle
        let showsRefreshButton: Bool
        let layout: Layout
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
    private let batteryStaleInterval: TimeInterval = 7 * 24 * 60 * 60

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

    var isUnlinkedVirtualBatteryPowerSwitch: Bool {
        !isRealBatteryPowerSwitch
    }

    var informationNode: Node? {
        guard let node = switchData.proxyNode, node.isPowerSwitch else {
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
        switchData.proxyNode?.isPowerSwitch == true && switchData.needsBatteryPowerSwitchSync
    }

    var canRefreshBattery: Bool {
        switchData.powerSwitchKind == .battery && switchData.proxyNode?.isBatteryPowerSwitch == true && space.permission != .visitor
    }

    var panelDefinition: PJEightKeySwitchPanelDefinition {
        .make(type: switchData.eightKeyPanelType)
    }

    var headerState: HeaderState {
        if switchData.powerSwitchKind == .ac {
            return acHeaderState()
        }
        let style = batteryStatusStyle()
        return HeaderState(
            batteryText: batteryDisplayText(),
            batteryIconSystemName: "battery_ek",
            statusPrefixText: "neightkeyswitches_status_prefix".localizedString,
            statusText: statusText(for: style),
            statusColor: statusColor(for: style),
            updatedText: batteryUpdatedText(),
            style: style,
            showsRefreshButton: canRefreshBattery,
            layout: .battery
        )
    }

    var settingsState: SettingsState {
        SettingsState(
            groupNames: switchData.bindGroups.map(\.name),
            isGroupLinked: !switchData.bindGroups.isEmpty,
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

    func applyTxEnableSucceeded(_ isEnabled: Bool) {
        switchData.enabled = isEnabled
        switchData.markBatteryPowerSwitchTxEnableSucceeded()
    }

    func prepareBatteryPowerSwitchDesiredConfigIfNeeded() -> Bool {
        guard switchData.proxyNode?.isPowerSwitch == true else {
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

    @discardableResult
    func saveBatteryLevel(_ level: UInt8, updatedAt date: Date = Date()) -> Bool {
        guard level <= 100 else {
            return false
        }
        let timestamp = Int64(date.timeIntervalSince1970)
        return PJEightKeySwitchRepository.shared.saveBattery(
            level: level,
            lastUpdateTime: timestamp,
            for: switchData
        )
    }

    @discardableResult
    func persist() -> Bool {
        let baseSaved = switchData.save()
        let metadataSaved = PJEightKeySwitchRepository.shared.save(switchData)
        if let index = MeshNetworkManager.instance.switchs.firstIndex(where: { $0.id == switchData.id }) {
            MeshNetworkManager.instance.switchs[index].update(switchData: switchData)
        }
        return baseSaved && metadataSaved
    }
}

private extension PJEightKeySwitchMonitorViewModel {

    func acHeaderState() -> HeaderState {
        if isUnlinkedVirtualBatteryPowerSwitch {
            return HeaderState(
                batteryText: "",
                batteryIconSystemName: "",
                statusPrefixText: "",
                statusText: "neightkeyswitches_unlinked".localizedString,
                statusColor: RGB(148, 163, 184),
                updatedText: "",
                style: .unlinked,
                showsRefreshButton: false,
                layout: .centeredStatus
            )
        }

        let online = informationNode?.state == true
        return HeaderState(
            batteryText: "",
            batteryIconSystemName: "",
            statusPrefixText: "",
            statusText: online ? "online".localizedString : "Offline".localizedString,
            statusColor: online ? RGB(69, 197, 122) : RGB(148, 163, 184),
            updatedText: "",
            style: online ? .normal : .unknown,
            showsRefreshButton: false,
            layout: .centeredStatus
        )
    }

    func batteryDisplayText() -> String {
        guard let level = reportedBatteryLevel() else {
            return "--"
        }
        return "\(level)%"
    }

    func batteryStatusStyle(now: Date = Date()) -> HeaderState.StatusStyle {
        if isUnlinkedVirtualBatteryPowerSwitch {
            return .unlinked
        }
        guard let batteryLastUpdateTime = switchData.batteryLastUpdateTime else {
            return .unknown
        }
        let elapsed = max(0, now.timeIntervalSince1970 - TimeInterval(batteryLastUpdateTime))
        if elapsed > batteryStaleInterval {
            return .unknown
        }
        guard let level = reportedBatteryLevel() else {
            return .unknown
        }
        return level <= 10 ? .lowBattery : .normal
    }

    func batteryUpdatedText(now: Date = Date()) -> String {
        guard let batteryLastUpdateTime = switchData.batteryLastUpdateTime else {
            return "--"
        }
        let elapsed = max(0, now.timeIntervalSince1970 - TimeInterval(batteryLastUpdateTime))
        if elapsed < 60 {
            return "neightkeyswitches_updated_just_now".localizedString
        }
        if elapsed < 60 * 60 {
            return String(format: "neightkeyswitches_updated_min_ago_format".localizedString, Int(elapsed / 60))
        }
        if elapsed < 24 * 60 * 60 {
            return String(format: "neightkeyswitches_updated_hr_ago_format".localizedString, Int(elapsed / (60 * 60)))
        }
        return String(format: "neightkeyswitches_updated_day_ago_format".localizedString, Int(elapsed / (24 * 60 * 60)))
    }

    func reportedBatteryLevel() -> Int? {
        guard let level = switchData.batteryLevel, level <= 100 else {
            return nil
        }
        return Int(level)
    }

    func statusText(for style: HeaderState.StatusStyle) -> String {
        switch style {
        case .normal:
            return "neightkeyswitches_status_normal".localizedString
        case .lowBattery:
            return "neightkeyswitches_status_low_battery".localizedString
        case .unknown:
            return "neightkeyswitches_status_unknown".localizedString
        case .unlinked:
            return "neightkeyswitches_unlinked".localizedString
        }
    }

    func statusColor(for style: HeaderState.StatusStyle) -> UIColor {
        switch style {
        case .normal:
            return RGB(69, 197, 122)
        case .unknown, .unlinked:
            return RGB(148, 163, 184)
        case .lowBattery:
            return RGB(240, 162, 55)
        }
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
