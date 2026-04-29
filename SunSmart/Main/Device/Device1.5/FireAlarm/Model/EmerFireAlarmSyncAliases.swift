//
//  EmerFireAlarmSyncAliases.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/23.
//

import Foundation

// FireAlarm sync flow currently reuses the existing sync infrastructure
// under FireAlarm-specific type names so the new controller can evolve
// independently without touching the old sync module.
typealias EmerFireAlarmSyncCellModel = SyncCellModel
typealias EmerFireAlarmSyncSectionModel = SyncDevicesSectionModel
typealias EmerFireAlarmSyncGroupModel = SyncDevicesGroupModel
typealias EmerFireAlarmSyncDeviceModel = SyncDevicesModel
typealias EmerFireAlarmSyncSwitchProxyModel = SyncDevicesSwitchProxyModel
typealias EmerFireAlarmSyncStepModel = SyncDeviceStepModel
typealias EmerFireAlarmSyncStepTaskModel = SyncDeviceStepTaskModel

typealias EmerFireAlarmSyncTitleHeaderView = SyncDevicesTitleHeaderView
typealias EmerFireAlarmSyncGroupViewCell = SyncDevicesGroupViewCell
typealias EmerFireAlarmSyncDeviceViewCell = SyncDeviceViewCell
typealias EmerFireAlarmSyncDeviceStepViewCell = SyncDeviceStepViewCell
typealias EmerFireAlarmSyncProgressView = SyncDevicesProgressView

typealias EmerFireAlarmSyncGroupViewCellDelegate = SyncDevicesGroupViewCellDelegate
typealias EmerFireAlarmSyncDeviceViewCellDelegate = SyncDeviceViewCellDelegate
typealias EmerFireAlarmSyncDeviceStepViewCellDelegate = SyncDeviceStepViewCellDelegate
