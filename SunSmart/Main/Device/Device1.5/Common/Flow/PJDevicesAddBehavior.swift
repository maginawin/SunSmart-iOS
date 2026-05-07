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
}
