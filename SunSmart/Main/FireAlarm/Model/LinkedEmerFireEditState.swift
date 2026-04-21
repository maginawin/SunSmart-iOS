//
//  LinkedEmerFireEditState.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import Foundation

final class LinkedEmerFireEditState {

    let groupOptions = [
        "Group 1",
        "Group 1,Group 2,Group 3",
        "Group 1,Group 2,Group 3,Group 4"
    ]

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
    var deviceName = "linked_emer_fire_controller_name".localizedString
    var isSynced = false

    var reportToGateway = true
    var enablePowerLossEmergency = false
    var enableFireAlarmEmergency = true

    var powerLossGroupIndex = 1
    var fireAlarmGroupIndex = 1

    var powerLossBrightness = 25
    var powerLossResuming = 2
    var powerLossSendCount = 2

    var fireAlarmBrightness = 100
    var fireAlarmResuming = 0
    var fireAlarmSendCount = 0

    convenience init(config: LinkedEmerFireConfig) {
        self.init()
        deviceName = config.deviceName
        isSynced = config.isSynced
        reportToGateway = config.reportToGateway
        enablePowerLossEmergency = config.enablePowerLossEmergency
        enableFireAlarmEmergency = config.enableFireAlarmEmergency
        powerLossGroupIndex = config.powerLossGroupIndex
        fireAlarmGroupIndex = config.fireAlarmGroupIndex
        powerLossBrightness = config.powerLossBrightness
        powerLossResuming = config.powerLossResuming
        powerLossSendCount = config.powerLossSendCount
        fireAlarmBrightness = config.fireAlarmBrightness
        fireAlarmResuming = config.fireAlarmResuming
        fireAlarmSendCount = config.fireAlarmSendCount
    }

    func groupText(for row: LinkedEmerFireEditRow) -> String {
        switch row {
        case .powerLossGroups:
            return groupOptions[powerLossGroupIndex]
        case .fireAlarmGroups:
            return groupOptions[fireAlarmGroupIndex]
        default:
            return ""
        }
    }

    func updateStepperValue(for row: LinkedEmerFireEditRow, delta: Int) {
        switch row {
        case .powerLossBrightness:
            powerLossBrightness = min(max(powerLossBrightness + delta, 0), 100)
        case .powerLossResuming:
            powerLossResuming = min(max(powerLossResuming + delta, 0), 10)
        case .powerLossSendCount:
            powerLossSendCount = min(max(powerLossSendCount + delta, 0), 5)
        case .fireAlarmBrightness:
            fireAlarmBrightness = min(max(fireAlarmBrightness + delta, 0), 100)
        case .fireAlarmResuming:
            fireAlarmResuming = min(max(fireAlarmResuming + delta, 0), 10)
        case .fireAlarmSendCount:
            fireAlarmSendCount = min(max(fireAlarmSendCount + delta, 0), 5)
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
            powerLossSendCount = min(max(value, 0), 5)
        case .fireAlarmBrightness:
            fireAlarmBrightness = min(max(value, 0), 100)
        case .fireAlarmResuming:
            fireAlarmResuming = min(max(value, 0), 10)
        case .fireAlarmSendCount:
            fireAlarmSendCount = min(max(value, 0), 5)
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
            return .init(title: "linked_send_count_per_5_seconds".localizedString, value: powerLossSendCount, range: 0...5, suffix: "")
        case .fireAlarmBrightness:
            return .init(title: "linked_set_brightness_to".localizedString, value: fireAlarmBrightness, range: 0...100, suffix: "%")
        case .fireAlarmResuming:
            return .init(title: "linked_resuming".localizedString, value: fireAlarmResuming, range: 0...10, suffix: "s")
        case .fireAlarmSendCount:
            return .init(title: "linked_send_count_per_5_seconds".localizedString, value: fireAlarmSendCount, range: 0...5, suffix: "")
        default:
            return .init(title: "", value: 0, range: 0...0, suffix: "")
        }
    }

    func makeConfig() -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceName: deviceName,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            enablePowerLossEmergency: enablePowerLossEmergency,
            enableFireAlarmEmergency: enableFireAlarmEmergency,
            powerLossGroupIndex: powerLossGroupIndex,
            fireAlarmGroupIndex: fireAlarmGroupIndex,
            powerLossBrightness: powerLossBrightness,
            powerLossResuming: powerLossResuming,
            powerLossSendCount: powerLossSendCount,
            fireAlarmBrightness: fireAlarmBrightness,
            fireAlarmResuming: fireAlarmResuming,
            fireAlarmSendCount: fireAlarmSendCount
        )
    }
}
