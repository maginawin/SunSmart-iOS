//
//  EmerFireAlarmMonitorState.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

struct EmerFireAlarmAssociatedGroupItem {
    let group: Group
}

enum EmerFireAlarmMonitorDisplayState: Equatable {
    case loading
    case repair
    case offline
    case disabled
    case emergencyTriggered
    case emergencyNormal
    case emergencyResuming
    case fireTriggered
    case fireNormal
    case fireResuming
}

enum EmerFireAlarmMonitorStateMapper {
    static func displayState(status: EmergencyFireComprehensiveStatus) -> EmerFireAlarmMonitorDisplayState {
        guard status.enabled else {
            return .disabled
        }
        if status.fireActive {
            return .fireTriggered
        }
        if status.emergencyActive {
            return .emergencyTriggered
        }
        return normalState()
    }

    static func normalState() -> EmerFireAlarmMonitorDisplayState {
        .emergencyNormal
    }

    static func normalState(afterResuming state: EmerFireAlarmMonitorDisplayState) -> EmerFireAlarmMonitorDisplayState? {
        switch state {
        case .emergencyResuming:
            return .emergencyNormal
        case .fireResuming:
            return .fireNormal
        case .loading, .repair, .offline, .disabled, .emergencyTriggered, .emergencyNormal, .fireTriggered, .fireNormal:
            return nil
        }
    }

    static func restoreDelaySeconds(configuration: EmergencyFireControllerConfiguration?, for state: EmerFireAlarmMonitorDisplayState) -> TimeInterval? {
        switch state {
        case .emergencyResuming:
            return TimeInterval(configuration?.restoreDelaySeconds() ?? EmergencyFireControllerRestoreSettings.defaultValue.resumingSeconds)
        case .fireResuming:
            return TimeInterval(configuration?.restoreDelaySeconds() ?? EmergencyFireControllerRestoreSettings.defaultValue.resumingSeconds)
        case .loading, .repair, .offline, .disabled, .emergencyTriggered, .emergencyNormal, .fireTriggered, .fireNormal:
            return nil
        }
    }

    static func triggerSceneNumber() -> SceneNumber {
        DeviceEmerFireData.powerLossTriggerSceneNumber
    }

    static func actionIconNames() -> (trigger: String, stop: String) {
        (EmergencyFireControllerIconName.Monitor.Action.powerLossTrigger, EmergencyFireControllerIconName.Monitor.Action.powerLossStop)
    }

    static func associatedGroupAddresses(configuration: EmergencyFireControllerConfiguration?) -> [UInt16] {
        Array(configuration?.activeLightLCGroupAddresses ?? []).sorted()
    }

    static func displayGroups(from config: LinkedEmerFireConfig) -> [EmerFireAlarmAssociatedGroupItem] {
        var displayGroups: [EmerFireAlarmAssociatedGroupItem] = []
        var addedAddresses: Set<Address> = []
        let addresses = associatedGroupAddresses(
            configuration: config.configuration
        ).sorted()

        addresses.forEach { address in
            guard !addedAddresses.contains(address),
                  let group = MeshNetworkManager.instance.groups.first(where: { $0.address.address == address }) else {
                return
            }
            addedAddresses.insert(address)
            displayGroups.append(.init(group: group))
        }

        return displayGroups
    }

    static func statusItems(for config: LinkedEmerFireConfig) -> [EmerFireAlarmStatusSetView.ItemViewModel] {
        let powerLossSettings = config.configuration.powerLossSettings
        let fireAlarmSettings = config.configuration.fireAlarmSettings
        let restoreDelay = config.configuration.restoreSettings.resumingSeconds
        return [
            .init(
                kind: .powerLossTrigger,
                title: "power_supply_fails".localizedString,
                subtitle: "set_brightness_to".localizedString,
                value: "\(powerLossSettings.triggerBrightness)%"
            ),
            .init(
                kind: .powerLossStop,
                title: "power_is_restored".localizedString,
                subtitle: "resuming_in".localizedString,
                value: "\(restoreDelay)s"
            ),
            .init(
                kind: .fireTrigger,
                title: "fire_alarm_occurs".localizedString,
                subtitle: "set_brightness_to".localizedString,
                value: "\(fireAlarmSettings.triggerBrightness)%"
            ),
            .init(
                kind: .fireStop,
                title: "fire_alarm_stops".localizedString,
                subtitle: "resuming_in".localizedString,
                value: "\(restoreDelay)s"
            )
        ]
    }
}
