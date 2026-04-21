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

struct LinkedEmerFireStepperConfiguration {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String
}
