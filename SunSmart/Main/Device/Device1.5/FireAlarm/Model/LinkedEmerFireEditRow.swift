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
    case emergencyMode
    case eventOccursHeader
    case fireAlarmBrightness
    case powerLossBrightness
    case triggerInterval
    case eventEndsHeader
    case restoreAction
    case restoreBrightness
    case restoreResuming
    case restoreSendCount
    case restoreTiming
}

extension LinkedEmerFireEditRow {
    enum CardGroup {
        case name
        case report
        case associatedGroups
        case emergencyMode
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
        case .emergencyMode:
            return .emergencyMode
        case .eventOccursHeader,
             .fireAlarmBrightness,
             .powerLossBrightness,
             .triggerInterval:
            return .eventOccurs
        case .eventEndsHeader,
             .restoreAction,
             .restoreBrightness,
             .restoreResuming,
             .restoreSendCount,
             .restoreTiming:
            return .eventEnds
        }
    }
}

struct LinkedEmerFireStepperConfiguration {
    let title: String
    let fieldTitle: String?
    let value: Int
    let range: ClosedRange<Int>
    let suffix: String

    init(title: String, fieldTitle: String? = nil, value: Int, range: ClosedRange<Int>, suffix: String) {
        self.title = title
        self.fieldTitle = fieldTitle
        self.value = value
        self.range = range
        self.suffix = suffix
    }
}

struct LinkedEmerFireRestoreActionOption {
    let title: String
    let type: EmergencyFireRestoreActionType
}
