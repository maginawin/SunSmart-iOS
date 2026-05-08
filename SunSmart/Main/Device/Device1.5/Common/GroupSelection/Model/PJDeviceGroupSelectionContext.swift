//
//  PJDeviceGroupSelectionContext.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

struct PJDeviceGroupSelectionContext {
    let title: String
    let groups: [Group]
    let selectedGroupAddresses: [UInt16]
    let disabledGroupAddresses: Set<UInt16>
    let disabledSelectionTip: String
}
