//
//  LinkedEmerFireEditState.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
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
    var enablePowerLossEmergency = true
    var enableFireAlarmEmergency = false

    var powerLossGroupIndex = 1
    var fireAlarmGroupIndex = 1
    var powerLossGroupAddresses: [UInt16] = []
    var fireAlarmGroupAddresses: [UInt16] = []

    var powerLossBrightness = 25
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
        enablePowerLossEmergency = config.enablePowerLossEmergency
        enableFireAlarmEmergency = config.enableFireAlarmEmergency
        normalizeEmergencySelection()
        powerLossGroupIndex = config.powerLossGroupIndex
        fireAlarmGroupIndex = config.fireAlarmGroupIndex
        powerLossGroupAddresses = config.powerLossGroupAddresses
        fireAlarmGroupAddresses = config.fireAlarmGroupAddresses
        powerLossBrightness = config.powerLossBrightness
        powerLossResuming = config.powerLossResuming
        powerLossSendCount = config.powerLossSendCount
        fireAlarmBrightness = config.fireAlarmBrightness
        fireAlarmResuming = config.fireAlarmResuming
        fireAlarmSendCount = config.fireAlarmSendCount
        normalizeStepperValues()
    }

    func updateEmergencySelection(for row: LinkedEmerFireEditRow, value: Bool) {
        switch row {
        case .powerLossEmergency:
            enablePowerLossEmergency = value
            enableFireAlarmEmergency = !value
        case .fireAlarmEmergency:
            enableFireAlarmEmergency = value
            enablePowerLossEmergency = !value
        default:
            break
        }
        normalizeEmergencySelection()
    }

    private func normalizeEmergencySelection() {
        if enablePowerLossEmergency == enableFireAlarmEmergency {
            enablePowerLossEmergency = true
            enableFireAlarmEmergency = false
        }
    }

    private func normalizeStepperValues() {
        powerLossSendCount = min(max(powerLossSendCount, 1), 5)
        fireAlarmSendCount = min(max(fireAlarmSendCount, 1), 5)
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
        case .fireAlarmGroups:
            fireAlarmGroupAddresses = sortedAddresses
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
                        return $0.enablePowerLossEmergency
                    case .fireAlarm:
                        return $0.enableFireAlarmEmergency
                    }
                }
                .flatMap {
                    switch mode {
                    case .powerLoss:
                        return $0.powerLossGroupAddresses
                    case .fireAlarm:
                        return $0.fireAlarmGroupAddresses
                    }
                }
        )
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
            powerLossBrightness = min(max(powerLossBrightness + delta, 0), 100)
        case .powerLossResuming:
            powerLossResuming = min(max(powerLossResuming + delta, 0), 10)
        case .powerLossSendCount:
            powerLossSendCount = min(max(powerLossSendCount + delta, 1), 5)
        case .fireAlarmBrightness:
            fireAlarmBrightness = min(max(fireAlarmBrightness + delta, 0), 100)
        case .fireAlarmResuming:
            fireAlarmResuming = min(max(fireAlarmResuming + delta, 0), 120)
        case .fireAlarmSendCount:
            fireAlarmSendCount = min(max(fireAlarmSendCount + delta, 1), 5)
        default:
            break
        }
    }

    func setStepperValue(for row: LinkedEmerFireEditRow, value: Int) {
        switch row {
        case .powerLossBrightness:
            powerLossBrightness = min(max(value, 0), 100)
        case .powerLossResuming:
            powerLossResuming = min(max(value, 0), 10)
        case .powerLossSendCount:
            powerLossSendCount = min(max(value, 1), 5)
        case .fireAlarmBrightness:
            fireAlarmBrightness = min(max(value, 0), 100)
        case .fireAlarmResuming:
            fireAlarmResuming = min(max(value, 0), 120)
        case .fireAlarmSendCount:
            fireAlarmSendCount = min(max(value, 1), 5)
        default:
            break
        }
    }

    func stepperConfiguration(for row: LinkedEmerFireEditRow) -> LinkedEmerFireStepperConfiguration {
        switch row {
        case .powerLossBrightness:
            return .init(title: "linked_set_brightness_to".localizedString, value: powerLossBrightness, range: 0...100, suffix: "%")
        case .powerLossResuming:
            return .init(title: "linked_resuming".localizedString, value: powerLossResuming, range: 0...10, suffix: "s")
        case .powerLossSendCount:
            return .init(title: "linked_send_count_per_5_seconds".localizedString, value: powerLossSendCount, range: 1...5, suffix: "")
        case .fireAlarmBrightness:
            return .init(title: "linked_set_brightness_to".localizedString, value: fireAlarmBrightness, range: 0...100, suffix: "%")
        case .fireAlarmResuming:
            return .init(title: "linked_resuming".localizedString, value: fireAlarmResuming, range: 0...120, suffix: "s")
        case .fireAlarmSendCount:
            return .init(title: "linked_send_count_per_5_seconds".localizedString, value: fireAlarmSendCount, range: 1...5, suffix: "")
        default:
            return .init(title: "", value: 0, range: 0...0, suffix: "")
        }
    }

    func makeConfig() -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceId: deviceId,
            spaceId: spaceId,
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId,
            deviceName: deviceName,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            enablePowerLossEmergency: enablePowerLossEmergency,
            enableFireAlarmEmergency: enableFireAlarmEmergency,
            powerLossGroupIndex: powerLossGroupIndex,
            fireAlarmGroupIndex: fireAlarmGroupIndex,
            powerLossGroupAddresses: powerLossGroupAddresses,
            fireAlarmGroupAddresses: fireAlarmGroupAddresses,
            powerLossBrightness: powerLossBrightness,
            powerLossResuming: powerLossResuming,
            powerLossSendCount: powerLossSendCount,
            fireAlarmBrightness: fireAlarmBrightness,
            fireAlarmResuming: fireAlarmResuming,
            fireAlarmSendCount: fireAlarmSendCount
        )
    }
}
