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
    let bindTarget: AddDeviceBindTarget?
    let addBehavior: PJDevicesAddBehavior?

    init(
        source: PJDevicesEntrySource,
        space: SpaceData,
        title: String?,
        appointGroup: Group?,
        bindTarget: AddDeviceBindTarget? = nil,
        addBehavior: PJDevicesAddBehavior?
    ) {
        self.source = source
        self.space = space
        self.title = title
        self.appointGroup = appointGroup
        self.bindTarget = bindTarget
        self.addBehavior = addBehavior
    }
}
