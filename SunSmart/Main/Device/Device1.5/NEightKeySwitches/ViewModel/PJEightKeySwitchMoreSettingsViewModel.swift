//
//  PJEightKeySwitchMoreSettingsViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

struct PJEightKeySwitchMoreSettingsViewModel {

    enum PeriodicReportingOption: Int, CaseIterable {
        case disabled
        case fifteenMinutes
        case thirtyMinutes
        case oneHour
        case fiveHours
        case tenHours

        var title: String {
            switch self {
            case .disabled:
                return "disable".localizedString
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

    struct State {
        var periodicReporting: PeriodicReportingOption
        var ledIndicatorEnabled: Bool

        static let `default` = State(periodicReporting: .fifteenMinutes, ledIndicatorEnabled: true)
    }

    var state: State

    init(state: State) {
        self.state = state
    }

    let periodicReportingTitle = "neightkeyswitches_periodic_reporting".localizedString
    let periodicReportingDescription = "neightkeyswitches_periodic_reporting_tip".localizedString
    let ledIndicatorTitle = "neightkeyswitches_led_indicator".localizedString
    let ledIndicatorDescription = "neightkeyswitches_led_indicator_tip".localizedString

    var periodicReportingOptions: [PeriodicReportingOption] {
        PeriodicReportingOption.allCases
    }
}
