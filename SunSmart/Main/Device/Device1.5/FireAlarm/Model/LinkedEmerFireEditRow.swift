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
    case associatedGroups
    case eventOccursHeader
    case fireAlarmBrightness
    case powerLossBrightness
    case triggerInterval
    case eventEndsHeader
    case restoreAction
    case restoreBrightness
    case restoreResuming
    case restoreSendCount
}

extension LinkedEmerFireEditRow {
    enum CardGroup {
        case name
        case report
        case associatedGroups
        case eventOccurs
        case eventEnds
    }

    var cardGroup: CardGroup {
        switch self {
        case .name:
            return .name
        case .reportToGateway:
            return .report
        case .associatedGroups:
            return .associatedGroups
        case .eventOccursHeader,
             .fireAlarmBrightness,
             .powerLossBrightness,
             .triggerInterval:
            return .eventOccurs
        case .eventEndsHeader,
             .restoreAction,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount:
            return .eventEnds
        }
    }
}

struct LinkedEmerFireStepperConfiguration {
    let title: String
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String
}

struct LinkedEmerFireRestoreActionOption {
    let title: String
    let type: EmergencyFireRestoreActionType
}
