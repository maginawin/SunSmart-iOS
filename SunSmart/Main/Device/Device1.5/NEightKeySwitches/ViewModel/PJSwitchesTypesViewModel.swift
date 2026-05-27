//
//  PJSwitchesTypesViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

struct PJSwitchesTypesViewModel {
    struct Item {
        let imageName: String
        let title: String
    }

    let title = "switches".localizedString
    let items: [Item] = [
        Item(imageName: "Kinetics_device", title: "kinetic_switch".localizedString),
        Item(imageName: "BatteryPowersw_device", title: "neightkeyswitches_battery_power_switch".localizedString),
        Item(imageName: "ACPowersw_device", title: "neightkeyswitches_ac_power_switch".localizedString)
    ]
}
