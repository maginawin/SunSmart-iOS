//
//  PJDevicesAddEntryContext.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation
import NordicSigMeshSDK

struct PJDevicesAddEntryContext {
    let source: PJDevicesEntrySource
    let space: SpaceData
    let title: String?
    let appointGroup: Group?
    let forceBindToDongle: DeviceDongleData?
    let addBehavior: PJDevicesAddBehavior?
}
