//
//  PreCreateEmerFireViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/27.
//

import Foundation

final class PreCreateEmerFireViewModel {

    let space: SpaceData
    let originalDevice: DeviceEmerFireData?
    let isEditMode: Bool

    private let store = DeviceEmerFireStore.shared

    var deviceName: String
    var isSynced: Bool
    var reportToGateway: Bool
    var gateWayData: GatewayModel?
    var enablePowerLossEmergency: Bool
    var enableFireAlarmEmergency: Bool

    init(space: SpaceData, deviceData: DeviceEmerFireData? = nil) {
        self.space = space
        originalDevice = deviceData
        isEditMode = deviceData != nil
        deviceName = deviceData?.name ?? DeviceEmerFireData.default(space: space).name
        isSynced = deviceData?.isSynced ?? false
        reportToGateway = deviceData?.reportToGateway ?? true
        gateWayData = deviceData?.gateWayData
        enablePowerLossEmergency = deviceData?.enablePowerLossEmergency ?? true
        enableFireAlarmEmergency = deviceData?.enableFireAlarmEmergency ?? false
    }

    func save() {
        let device = buildDevice()
        store.save(device)
    }

    func delete() {
        guard let originalDevice else { return }
        store.delete(originalDevice)
    }

    private func buildDevice() -> DeviceEmerFireData {
        let device = originalDevice?.copy() ?? DeviceEmerFireData.default(space: space)
        device.name = deviceName
        device.isSynced = isSynced
        device.gateWayData = gateWayData
        device.reportToGateway = gateWayData != nil ? reportToGateway : false
        device.enablePowerLossEmergency = enablePowerLossEmergency
        device.enableFireAlarmEmergency = enableFireAlarmEmergency
        return device
    }
}
