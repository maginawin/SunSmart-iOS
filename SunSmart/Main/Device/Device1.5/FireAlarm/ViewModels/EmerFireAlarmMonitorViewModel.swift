//
//  EmerFireAlarmMonitorViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

final class EmerFireAlarmMonitorViewModel {
    let space: SpaceData?
    var currentConfig: LinkedEmerFireConfig?
    var currentDevice: DeviceEmerFireData?
    var requestGeneration = 0
    var currentState: EmerFireAlarmMonitorDisplayState = .loading

    init(space: SpaceData?, device: DeviceEmerFireData?, config: LinkedEmerFireConfig?) {
        self.space = space
        self.currentDevice = device
        self.currentConfig = config
    }

    var currentWorkMode: EmergencyFireControllerWorkMode {
        currentConfig?.configuration.workMode ?? currentDevice?.configuration.workMode ?? .allDisabled
    }

    var canConfigureDevice: Bool {
        space?.deviceOperates.contains(.edit) ?? false
    }

    var canOperateEmergencyActions: Bool {
        !isAllEmergencyFunctionsDisabled && canConfigureDevice
    }

    var isAllEmergencyFunctionsDisabled: Bool {
        currentWorkMode == .allDisabled
    }

    var isEmergencySituation: Bool {
        switch currentState {
        case .emergencyTriggered, .fireTriggered:
            return true
        case .loading, .repair, .offline, .disabled, .emergencyNormal, .emergencyResuming, .fireNormal, .fireResuming:
            return false
        }
    }

    var activeAssociatedGroupsContainDevices: Bool {
        activeAssociatedGroupAddresses().contains { address in
            MeshNetworkManager.instance.groups
                .first(where: { $0.address.address == address })?
                .nodes
                .isEmpty == false
        }
    }

    func ensureConfig() {
        if currentConfig == nil, let currentDevice {
            currentConfig = makeConfig(from: currentDevice)
        }
    }

    func reloadCurrentDevice() {
        guard let config = currentConfig,
              let deviceId = config.deviceId,
              let meshUUID = config.meshUUID,
              let meshNetworkId = config.meshNetworkId else {
            return
        }
        currentDevice = DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId)
    }

    func displayGroups() -> [EmerFireAlarmAssociatedGroupItem] {
        guard let currentConfig else { return [] }
        return EmerFireAlarmMonitorStateMapper.displayGroups(from: currentConfig)
    }

    func statusItems() -> [EmerFireAlarmStatusSetView.ItemViewModel] {
        guard let currentConfig else { return [] }
        return EmerFireAlarmMonitorStateMapper.statusItems(for: currentConfig)
    }

    func actionIconNames() -> (trigger: String, stop: String) {
        EmerFireAlarmMonitorStateMapper.actionIconNames(for: currentWorkMode)
    }

    func activeTriggerSceneNumber() -> SceneNumber? {
        EmerFireAlarmMonitorStateMapper.triggerSceneNumber(for: currentWorkMode)
    }

    func activeAssociatedGroupAddresses() -> [UInt16] {
        let configuration = currentConfig?.configuration ?? currentDevice?.configuration
        return EmerFireAlarmMonitorStateMapper.associatedGroupAddresses(configuration: configuration, workMode: currentWorkMode)
    }

    func monitorDisplayState(mode: EmergencyControllerMode, active: Bool) -> EmerFireAlarmMonitorDisplayState {
        EmerFireAlarmMonitorStateMapper.displayState(mode: mode, active: active)
    }

    func configuredNormalState() -> EmerFireAlarmMonitorDisplayState {
        EmerFireAlarmMonitorStateMapper.normalState(for: currentWorkMode)
    }

    func normalState(afterResuming state: EmerFireAlarmMonitorDisplayState) -> EmerFireAlarmMonitorDisplayState? {
        EmerFireAlarmMonitorStateMapper.normalState(afterResuming: state)
    }

    func restoreDelaySeconds(for state: EmerFireAlarmMonitorDisplayState) -> TimeInterval? {
        let configuration = currentConfig?.configuration ?? currentDevice?.configuration
        return EmerFireAlarmMonitorStateMapper.restoreDelaySeconds(configuration: configuration, for: state)
    }

    func makeConfig(from device: DeviceEmerFireData) -> LinkedEmerFireConfig {
        LinkedEmerFireConfig(
            deviceId: device.id,
            spaceId: device.spaceId,
            meshUUID: device.meshUUID,
            meshNetworkId: device.meshNetworkId,
            deviceName: device.name,
            isSynced: device.isSynced,
            reportToGateway: device.reportToGateway,
            publishGroupAddress: device.publishGroupAddress,
            configuration: device.configuration
        )
    }
}
