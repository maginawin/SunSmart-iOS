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

enum EmerFireAlarmMonitorDisplayState {
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
    static func displayState(mode: EmergencyControllerMode, active: Bool) -> EmerFireAlarmMonitorDisplayState {
        switch mode {
        case .disabled:
            return .disabled
        case .emergency:
            return active ? .emergencyTriggered : .emergencyNormal
        case .fire:
            return active ? .fireTriggered : .fireNormal
        @unknown default:
            return .offline
        }
    }

    static func normalState(for workMode: EmergencyFireControllerWorkMode) -> EmerFireAlarmMonitorDisplayState {
        switch workMode {
        case .powerLossEmergency:
            return .emergencyNormal
        case .fireAlarmEmergency:
            return .fireNormal
        case .allDisabled:
            return .disabled
        }
    }

    static func triggerSceneNumber(for workMode: EmergencyFireControllerWorkMode) -> SceneNumber? {
        switch workMode {
        case .powerLossEmergency:
            return DeviceEmerFireData.powerLossTriggerSceneNumber
        case .fireAlarmEmergency:
            return DeviceEmerFireData.fireAlarmTriggerSceneNumber
        case .allDisabled:
            return nil
        }
    }

    static func actionIconNames(for workMode: EmergencyFireControllerWorkMode) -> (trigger: String, stop: String) {
        switch workMode {
        case .fireAlarmEmergency:
            return (EmergencyFireControllerIconName.Monitor.Action.fireTrigger, EmergencyFireControllerIconName.Monitor.Action.fireStop)
        case .powerLossEmergency, .allDisabled:
            return (EmergencyFireControllerIconName.Monitor.Action.powerLossTrigger, EmergencyFireControllerIconName.Monitor.Action.powerLossStop)
        }
    }

    static func associatedGroupAddresses(configuration: EmergencyFireControllerConfiguration?, workMode: EmergencyFireControllerWorkMode) -> [UInt16] {
        switch workMode {
        case .powerLossEmergency:
            return configuration?.powerLossSettings.associateGroupAddresses ?? []
        case .fireAlarmEmergency:
            return configuration?.fireAlarmSettings.associateGroupAddresses ?? []
        case .allDisabled:
            return []
        }
    }

    static func displayGroups(from config: LinkedEmerFireConfig) -> [EmerFireAlarmAssociatedGroupItem] {
        var displayGroups: [EmerFireAlarmAssociatedGroupItem] = []
        var addedAddresses: Set<Address> = []
        let addresses = (config.configuration.powerLossSettings.associateGroupAddresses + config.configuration.fireAlarmSettings.associateGroupAddresses).sorted()

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
        switch config.configuration.workMode {
        case .powerLossEmergency:
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
                    value: "\(powerLossSettings.restoreDelaySeconds)s"
                )
            ]
        case .fireAlarmEmergency:
            return [
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
                    value: "\(fireAlarmSettings.restoreDelaySeconds)s"
                )
            ]
        case .allDisabled:
            return []
        }
    }
}
