//
//  LinkedEmerFireEditRow.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/20.
//

import Foundation

enum LinkedEmerFireEditRow: Int, CaseIterable {
    case name
    case reportToGateway
    case powerLossEmergency
    case powerLossGroups
    case powerLossInstructions
    case powerLossBrightness
    case powerRestoreInstructions
    case powerLossResuming
    case powerLossSendCount
    case fireAlarmEmergency
    case fireAlarmGroups
    case fireAlarmInstructions
    case fireAlarmBrightness
    case fireAlarmStopInstructions
    case fireAlarmResuming
    case fireAlarmSendCount
}

extension LinkedEmerFireEditRow {
    enum CardGroup {
        case name
        case report
        case powerLoss
        case fireAlarm
    }

    var cardGroup: CardGroup {
        switch self {
        case .name:
            return .name
        case .reportToGateway:
            return .report
        case .powerLossEmergency,
             .powerLossGroups,
             .powerLossInstructions,
             .powerLossBrightness,
             .powerRestoreInstructions,
             .powerLossResuming,
             .powerLossSendCount:
            return .powerLoss
        case .fireAlarmEmergency,
             .fireAlarmGroups,
             .fireAlarmInstructions,
             .fireAlarmBrightness,
             .fireAlarmStopInstructions,
             .fireAlarmResuming,
             .fireAlarmSendCount:
            return .fireAlarm
        }
    }
}

struct LinkedEmerFireStepperConfiguration {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String
}
