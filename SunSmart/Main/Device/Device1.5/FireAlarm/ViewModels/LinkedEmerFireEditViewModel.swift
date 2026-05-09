//
//  LinkedEmerFireEditViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation

final class LinkedEmerFireEditViewModel {

    let state: LinkedEmerFireEditState

    init(config: LinkedEmerFireConfig? = nil, space: SpaceData? = nil) {
        if let config {
            state = LinkedEmerFireEditState(config: config)
        } else {
            state = LinkedEmerFireEditState()
            if let space {
                state.spaceId = space.id
                state.meshUUID = space.meshUUID
                state.meshNetworkId = space.meshNetworkId
                state.deviceName = DeviceEmerFireStore.shared.nextDefaultName(space: space)
            }
        }
    }

    @discardableResult
    func create(in space: SpaceData) -> DeviceEmerFireData? {
        let device = DeviceEmerFireData.default(space: space)
        apply(state.makeConfig(), to: device)
        DeviceEmerFireStore.shared.save(device)
        return device
    }

    @discardableResult
    func save() -> DeviceEmerFireData? {
        let config = state.makeConfig()
        if let deviceId = config.deviceId,
           let meshUUID = config.meshUUID,
           let meshNetworkId = config.meshNetworkId,
           let device = DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId)?.copy() {
            apply(config, to: device)
            DeviceEmerFireStore.shared.save(device)
            NotificationCenter.default.post(name: .linkedEmerFireConfigDidChange, object: config)
            return device
        }
        return nil
    }

    @discardableResult
    func delete() -> Bool {
        let config = state.makeConfig()
        guard let deviceId = config.deviceId,
              let meshUUID = config.meshUUID,
              let meshNetworkId = config.meshNetworkId,
              let device = DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId) else {
            return false
        }
        DeviceEmerFireStore.shared.delete(device)
        return true
    }

    func currentDevice() -> DeviceEmerFireData? {
        let config = state.makeConfig()
        guard let deviceId = config.deviceId,
              let meshUUID = config.meshUUID,
              let meshNetworkId = config.meshNetworkId else {
            return nil
        }
        return DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId)
    }

    @discardableResult
    func refreshSyncStatusFromStore() -> Bool {
        guard let device = currentDevice() else { return false }
        let oldValue = state.isSynced
        state.isSynced = device.isSynced
        return oldValue != state.isSynced
    }

    private func apply(_ config: LinkedEmerFireConfig, to device: DeviceEmerFireData) {
        let needsSync = device.configuration != config.configuration || device.publishGroupAddress != config.publishGroupAddress
        device.name = config.deviceName
        device.isSynced = needsSync ? false : config.isSynced
        device.reportToGateway = config.reportToGateway
        device.publishGroupAddress = config.publishGroupAddress
        device.mergePendingChanges(from: device.configuration, to: config.configuration)
    }
}
