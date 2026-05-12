//
//  PJDevicesAddBehavior.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

enum PJDevicesAddSelectableType {
    case lights
    case switches
    case sensors
    case others
}

enum PJDevicesAddSelectionMode {
    case single
    case multiple
}

struct PJDevicesAddBehavior {
    let allowsTargetSelection: Bool
    let allowsCategorySelection: Bool
    let allowedTypes: [PJDevicesAddSelectableType]
    let blockedDeviceTypes: [Node.DeviceType]
    let selectionMode: PJDevicesAddSelectionMode
    let forbiddenSelectionTip: String
    let forbiddenDeviceTypeTip: String
    let allowsEmergencyFireVirtualTargetSelection: Bool

    init(
        allowsTargetSelection: Bool,
        allowsCategorySelection: Bool,
        allowedTypes: [PJDevicesAddSelectableType],
        blockedDeviceTypes: [Node.DeviceType],
        selectionMode: PJDevicesAddSelectionMode,
        forbiddenSelectionTip: String,
        forbiddenDeviceTypeTip: String,
        allowsEmergencyFireVirtualTargetSelection: Bool = false
    ) {
        self.allowsTargetSelection = allowsTargetSelection
        self.allowsCategorySelection = allowsCategorySelection
        self.allowedTypes = allowedTypes
        self.blockedDeviceTypes = blockedDeviceTypes
        self.selectionMode = selectionMode
        self.forbiddenSelectionTip = forbiddenSelectionTip
        self.forbiddenDeviceTypeTip = forbiddenDeviceTypeTip
        self.allowsEmergencyFireVirtualTargetSelection = allowsEmergencyFireVirtualTargetSelection
    }
}
