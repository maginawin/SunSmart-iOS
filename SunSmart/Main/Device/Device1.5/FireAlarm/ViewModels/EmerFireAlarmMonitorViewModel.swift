//
//  EmerFireAlarmMonitorViewModel.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

/// 应急火警监控页的业务状态桥。
/// 页面可能从本地持久化设备进入，也可能从编辑页带一份未完全刷新过的 config 进入，
/// 因此这里同时保留 currentDevice 和 currentConfig，并在渲染时优先使用最新 config。
final class EmerFireAlarmMonitorViewModel {
    let space: SpaceData?
    var currentConfig: LinkedEmerFireConfig?
    var currentDevice: DeviceEmerFireData?
    var requestGeneration = 0
    var currentState: EmerFireAlarmMonitorDisplayState = .loading

    init(space: SpaceData?, device: DeviceEmerFireData, config: LinkedEmerFireConfig?) {
        self.space = space
        self.currentDevice = device
        self.currentConfig = config
    }

    var canConfigureDevice: Bool {
        space?.deviceOperates.contains(.edit) ?? false
    }

    var canOperateEmergencyActions: Bool {
        canConfigureDevice
    }

    var isAllEmergencyFunctionsDisabled: Bool {
        false
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
        // 用于判断触发/停止类操作是否有实际可控对象。
        // 这里只检查当前激活模式下的目标组，pending cleanup 组不参与监控页操作。
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
        guard let reloadedDevice = DeviceEmerFireStore.shared.device(id: deviceId, meshUUID: meshUUID, meshNetworkId: meshNetworkId) else {
            return
        }
        currentDevice = reloadedDevice
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
        EmerFireAlarmMonitorStateMapper.actionIconNames()
    }

    func activeTriggerSceneNumber() -> SceneNumber {
        EmerFireAlarmMonitorStateMapper.triggerSceneNumber()
    }

    func activeAssociatedGroupAddresses() -> [UInt16] {
        let configuration = currentConfig?.configuration ?? currentDevice?.configuration
        return EmerFireAlarmMonitorStateMapper.associatedGroupAddresses(configuration: configuration)
    }

    func monitorDisplayState(status: EmergencyFireComprehensiveStatus) -> EmerFireAlarmMonitorDisplayState {
        // 真实设备上报的是 v2 comprehensive status，页面显示态统一交给 mapper 转换。
        EmerFireAlarmMonitorStateMapper.displayState(status: status)
    }

    func configuredNormalState() -> EmerFireAlarmMonitorDisplayState {
        EmerFireAlarmMonitorStateMapper.normalState()
    }

    func normalState(afterResuming state: EmerFireAlarmMonitorDisplayState) -> EmerFireAlarmMonitorDisplayState? {
        EmerFireAlarmMonitorStateMapper.normalState(afterResuming: state)
    }

    func restoreDelaySeconds(for state: EmerFireAlarmMonitorDisplayState) -> TimeInterval? {
        let configuration = currentConfig?.configuration ?? currentDevice?.configuration
        return EmerFireAlarmMonitorStateMapper.restoreDelaySeconds(configuration: configuration, for: state)
    }

    func makeConfig(from device: DeviceEmerFireData) -> LinkedEmerFireConfig {
        // 监控页和编辑页都使用 LinkedEmerFireConfig 作为轻量快照，避免 UI 层直接改数据库实体。
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
