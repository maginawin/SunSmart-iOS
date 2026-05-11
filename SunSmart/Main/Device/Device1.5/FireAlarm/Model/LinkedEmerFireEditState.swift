//
//  LinkedEmerFireEditState.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

final class LinkedEmerFireEditState {

    enum EmergencyMode {
        case powerLoss
        case fireAlarm
    }

    let powerLossInstructions = [
        "linked_power_loss_instruction_1".localizedString,
        "linked_power_loss_instruction_2".localizedString
    ]

    let powerRestoreInstructions = [
        "linked_power_restore_instruction_1".localizedString,
        "linked_power_restore_instruction_2".localizedString,
        "linked_power_restore_instruction_3".localizedString
    ]

    let fireAlarmInstructions = [
        "linked_fire_alarm_instruction_1".localizedString,
        "linked_fire_alarm_instruction_2".localizedString
        
    ]

    let fireAlarmStopInstructions = [
        "linked_fire_alarm_stop_instruction_1".localizedString,
        "linked_fire_alarm_stop_instruction_2".localizedString,
        "linked_fire_alarm_stop_instruction_3".localizedString
    ]

    var editable = true
    var deviceId: String?
    var spaceId: String?
    var meshUUID: String?
    var meshNetworkId: String?
    var deviceName = "linked_emer_fire_controller_name".localizedString
    var isSynced = false

    var reportToGateway = true
    var publishGroupAddress: Address?
    var configuration = EmergencyFireControllerConfiguration.defaultValue
    var enablePowerLossEmergency = true
    var enableFireAlarmEmergency = false

    var powerLossGroupIndex = 1
    var fireAlarmGroupIndex = 1
    var powerLossGroupAddresses: [UInt16] = []
    var fireAlarmGroupAddresses: [UInt16] = []

    var powerLossBrightness = 100
    var powerLossResuming = 2
    var powerLossSendCount = 2

    var fireAlarmBrightness = 100
    var fireAlarmResuming = 2
    var fireAlarmSendCount = 2

    convenience init(config: LinkedEmerFireConfig) {
        self.init()
        deviceId = config.deviceId
        spaceId = config.spaceId
        meshUUID = config.meshUUID
        meshNetworkId = config.meshNetworkId
        deviceName = config.deviceName
        isSynced = config.isSynced
        reportToGateway = config.reportToGateway
        publishGroupAddress = config.publishGroupAddress
        configuration = config.configuration
        enablePowerLossEmergency = configuration.workMode == .powerLossEmergency
        enableFireAlarmEmergency = configuration.workMode == .fireAlarmEmergency
        powerLossGroupAddresses = configuration.powerLossSettings.associateGroupAddresses
        fireAlarmGroupAddresses = configuration.fireAlarmSettings.associateGroupAddresses
        powerLossBrightness = configuration.powerLossSettings.triggerBrightness
        powerLossResuming = Int(configuration.powerLossSettings.restoreDelaySeconds)
        powerLossSendCount = Int(configuration.powerLossSettings.stopCount)
        fireAlarmBrightness = configuration.fireAlarmSettings.triggerBrightness
        fireAlarmResuming = Int(configuration.fireAlarmSettings.restoreDelaySeconds)
        fireAlarmSendCount = Int(configuration.fireAlarmSettings.stopCount)
        normalizeStepperValues()
    }

    func updateEmergencySelection(for row: LinkedEmerFireEditRow, value: Bool) {
        switch row {
        case .powerLossEmergency:
            enablePowerLossEmergency = value
            if value {
                enableFireAlarmEmergency = false
                configuration.workMode = .powerLossEmergency
                clearAssociatedGroups(for: .fireAlarmEmergency)
            } else if configuration.workMode == .powerLossEmergency {
                clearAssociatedGroups(for: .powerLossEmergency)
                configuration.workMode = enableFireAlarmEmergency ? .fireAlarmEmergency : .allDisabled
            }
        case .fireAlarmEmergency:
            enableFireAlarmEmergency = value
            if value {
                enablePowerLossEmergency = false
                configuration.workMode = .fireAlarmEmergency
                clearAssociatedGroups(for: .powerLossEmergency)
            } else if configuration.workMode == .fireAlarmEmergency {
                clearAssociatedGroups(for: .fireAlarmEmergency)
                configuration.workMode = enablePowerLossEmergency ? .powerLossEmergency : .allDisabled
            }
        default:
            break
        }
    }

    private func normalizeStepperValues() {
        powerLossSendCount = min(max(powerLossSendCount, 1), 10)
        fireAlarmSendCount = min(max(fireAlarmSendCount, 1), 10)
    }

    func groupText(for row: LinkedEmerFireEditRow) -> String {
        switch row {
        case .powerLossGroups:
            return groupNames(for: powerLossGroupAddresses)
        case .fireAlarmGroups:
            return groupNames(for: fireAlarmGroupAddresses)
        default:
            return ""
        }
    }

    func selectedGroupAddresses(for row: LinkedEmerFireEditRow) -> [UInt16] {
        switch row {
        case .powerLossGroups:
            return powerLossGroupAddresses
        case .fireAlarmGroups:
            return fireAlarmGroupAddresses
        default:
            return []
        }
    }

    func updateSelectedGroupAddresses(for row: LinkedEmerFireEditRow, addresses: [UInt16]) {
        let sortedAddresses = addresses.sorted()
        switch row {
        case .powerLossGroups:
            powerLossGroupAddresses = sortedAddresses
            configuration.powerLossSettings.associateGroupAddresses = sortedAddresses
        case .fireAlarmGroups:
            fireAlarmGroupAddresses = sortedAddresses
            configuration.fireAlarmSettings.associateGroupAddresses = sortedAddresses
        default:
            break
        }
    }

    func disabledGroupAddresses(for row: LinkedEmerFireEditRow) -> Set<UInt16> {
        let mode: EmergencyMode
        switch row {
        case .powerLossGroups:
            mode = .powerLoss
        case .fireAlarmGroups:
            mode = .fireAlarm
        default:
            return []
        }

        guard let meshUUID, let meshNetworkId else { return [] }
        let devices = DeviceEmerFireStore.shared.loadDevices(meshUUID: meshUUID, meshNetworkId: meshNetworkId)
        let scopedDevices = devices.filter { device in
            if let spaceId {
                return device.spaceId == spaceId
            }
            return true
        }

        return Set(
            scopedDevices
                .filter { $0.id != deviceId }
                .filter {
                    switch mode {
                    case .powerLoss:
                        return $0.configuration.workMode == .powerLossEmergency
                    case .fireAlarm:
                        return $0.configuration.workMode == .fireAlarmEmergency
                    }
                }
                .flatMap {
                    switch mode {
                    case .powerLoss:
                        return $0.configuration.powerLossSettings.associateGroupAddresses
                    case .fireAlarm:
                        return $0.configuration.fireAlarmSettings.associateGroupAddresses
                    }
                }
        )
    }

    func conflictingAssociatedGroupNames() -> [String] {
        var conflictAddresses = Set<UInt16>()

        if enablePowerLossEmergency {
            let disabledPowerLossAddresses = disabledGroupAddresses(for: .powerLossGroups)
            conflictAddresses.formUnion(disabledPowerLossAddresses.intersection(powerLossGroupAddresses))
        }

        if enableFireAlarmEmergency {
            let disabledFireAlarmAddresses = disabledGroupAddresses(for: .fireAlarmGroups)
            conflictAddresses.formUnion(disabledFireAlarmAddresses.intersection(fireAlarmGroupAddresses))
        }

        return conflictAddresses
            .sorted()
            .compactMap { address in
                MeshNetworkManager.instance.groups.first(where: { $0.address.address == address })?.name
            }
    }

    private func groupNames(for addresses: [UInt16]) -> String {
        let names = addresses.compactMap { address in
            MeshNetworkManager.instance.groups.first(where: { $0.address.address == address })?.name
        }
        return names.joined(separator: ",")
    }

    func updateStepperValue(for row: LinkedEmerFireEditRow, delta: Int) {
        switch row {
        case .powerLossBrightness:
            setStepperValue(for: row, value: powerLossBrightness + delta)
        case .powerLossResuming:
            setStepperValue(for: row, value: powerLossResuming + delta)
        case .powerLossSendCount:
            setStepperValue(for: row, value: powerLossSendCount + delta)
        case .fireAlarmBrightness:
            setStepperValue(for: row, value: fireAlarmBrightness + delta)
        case .fireAlarmResuming:
            setStepperValue(for: row, value: fireAlarmResuming + delta)
        case .fireAlarmSendCount:
            setStepperValue(for: row, value: fireAlarmSendCount + delta)
        default:
            break
        }
    }

    func setStepperValue(for row: LinkedEmerFireEditRow, value: Int) {
        switch row {
        case .powerLossBrightness:
            powerLossBrightness = min(max(value, 0), 100)
            configuration.powerLossSettings.triggerBrightness = powerLossBrightness
        case .powerLossResuming:
            powerLossResuming = min(max(value, 0), 120)
            configuration.powerLossSettings.restoreDelaySeconds = UInt8(powerLossResuming)
        case .powerLossSendCount:
            powerLossSendCount = min(max(value, 1), 10)
            configuration.powerLossSettings.stopCount = UInt16(powerLossSendCount)
        case .fireAlarmBrightness:
            fireAlarmBrightness = min(max(value, 0), 100)
            configuration.fireAlarmSettings.triggerBrightness = fireAlarmBrightness
        case .fireAlarmResuming:
            fireAlarmResuming = min(max(value, 0), 120)
            configuration.fireAlarmSettings.restoreDelaySeconds = UInt8(fireAlarmResuming)
        case .fireAlarmSendCount:
            fireAlarmSendCount = min(max(value, 1), 10)
            configuration.fireAlarmSettings.stopCount = UInt16(fireAlarmSendCount)
        default:
            break
        }
    }

    func stepperConfiguration(for row: LinkedEmerFireEditRow) -> LinkedEmerFireStepperConfiguration {
        switch row {
        case .powerLossBrightness:
            return .init(title: "linked_set_brightness_to".localizedString, value: powerLossBrightness, range: 0...100, suffix: "%")
        case .powerLossResuming:
            return .init(title: "linked_resuming".localizedString, value: powerLossResuming, range: 0...120, suffix: "s")
        case .powerLossSendCount:
            return .init(title: "linked_send_count_per_5_seconds".localizedString, value: powerLossSendCount, range: 1...10, suffix: "")
        case .fireAlarmBrightness:
            return .init(title: "linked_set_brightness_to".localizedString, value: fireAlarmBrightness, range: 0...100, suffix: "%")
        case .fireAlarmResuming:
            return .init(title: "linked_resuming".localizedString, value: fireAlarmResuming, range: 0...120, suffix: "s")
        case .fireAlarmSendCount:
            return .init(title: "linked_send_count_per_5_seconds".localizedString, value: fireAlarmSendCount, range: 1...10, suffix: "")
        default:
            return .init(title: "", value: 0, range: 0...0, suffix: "")
        }
    }

    func makeConfig() -> LinkedEmerFireConfig {
        syncConfigurationWorkMode()
        return LinkedEmerFireConfig(
            deviceId: deviceId,
            spaceId: spaceId,
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId,
            deviceName: deviceName,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            publishGroupAddress: publishGroupAddress,
            configuration: configuration
        )
    }

    private func syncConfigurationWorkMode() {
        if enableFireAlarmEmergency {
            configuration.workMode = .fireAlarmEmergency
        } else if enablePowerLossEmergency {
            configuration.workMode = .powerLossEmergency
        } else {
            clearAssociatedGroups(for: .powerLossEmergency)
            clearAssociatedGroups(for: .fireAlarmEmergency)
            configuration.workMode = .allDisabled
        }
    }

    private func clearAssociatedGroups(for mode: EmergencyFireControllerWorkMode) {
        switch mode {
        case .powerLossEmergency:
            powerLossGroupAddresses = []
            configuration.powerLossSettings.associateGroupAddresses = []
        case .fireAlarmEmergency:
            fireAlarmGroupAddresses = []
            configuration.fireAlarmSettings.associateGroupAddresses = []
        case .allDisabled:
            break
        }
    }
}
