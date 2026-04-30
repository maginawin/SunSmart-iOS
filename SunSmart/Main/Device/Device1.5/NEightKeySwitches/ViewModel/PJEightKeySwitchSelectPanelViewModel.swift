//
//  PJEightKeySwitchSelectPanelViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

struct PJEightKeySwitchSelectPanelViewModel {

    let panelTypes: [PJEightKeySwitchPanelDefinition.PanelType] = PJEightKeySwitchPanelDefinition.PanelType.allCases
    var selectedPanelType: PJEightKeySwitchPanelDefinition.PanelType

    init(selectedPanelType: PJEightKeySwitchPanelDefinition.PanelType) {
        self.selectedPanelType = selectedPanelType
    }

    func definition(at section: Int) -> PJEightKeySwitchPanelDefinition {
        PJEightKeySwitchPanelDefinition.make(type: panelTypes[section])
    }
}
