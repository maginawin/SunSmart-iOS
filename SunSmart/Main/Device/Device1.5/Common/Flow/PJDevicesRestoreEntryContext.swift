//
//  PJDevicesRestoreEntryContext.swift
//  SunSmart
//
//  Created by Plato Jobs.
//

import Foundation

struct PJDevicesRestoreEntryContext {
    let source: PJDevicesEntrySource
    let site: SiteData
    let space: SpaceData?
    let restoreMode: DeviceRestoreViewController.RestoreMode
    let title: String?
}
