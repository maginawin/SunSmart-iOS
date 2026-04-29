//
//  LinkedEmerFireEditViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/27.
//

import Foundation

final class LinkedEmerFireEditViewModel {

    let state: LinkedEmerFireEditState

    init(config: LinkedEmerFireConfig? = nil) {
        if let config {
            state = LinkedEmerFireEditState(config: config)
        } else {
            state = LinkedEmerFireEditState()
        }
    }

    func save() {
        let config = state.makeConfig()
        if let deviceId = config.deviceId,
           let meshUUID = config.meshUUID,
           let meshNetworkId = config.meshNetworkId,
           let device = DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId)?.copy() {
            device.name = config.deviceName
            device.isSynced = config.isSynced
            device.reportToGateway = config.reportToGateway
            device.enablePowerLossEmergency = config.enablePowerLossEmergency
            device.enableFireAlarmEmergency = config.enableFireAlarmEmergency
            device.powerLossGroupIndex = config.powerLossGroupIndex
            device.fireAlarmGroupIndex = config.fireAlarmGroupIndex
            device.powerLossGroupAddresses = config.powerLossGroupAddresses
            device.fireAlarmGroupAddresses = config.fireAlarmGroupAddresses
            device.powerLossBrightness = config.powerLossBrightness
            device.powerLossResuming = config.powerLossResuming
            device.powerLossSendCount = config.powerLossSendCount
            device.fireAlarmBrightness = config.fireAlarmBrightness
            device.fireAlarmResuming = config.fireAlarmResuming
            device.fireAlarmSendCount = config.fireAlarmSendCount
            DeviceEmerFireStore.shared.save(device)
        }
        NotificationCenter.default.post(name: .linkedEmerFireConfigDidChange, object: config)
    }
}
