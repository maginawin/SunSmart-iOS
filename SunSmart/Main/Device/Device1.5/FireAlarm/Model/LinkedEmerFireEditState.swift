//
//  LinkedEmerFireEditState.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

final class LinkedEmerFireEditState {

    var editable = true
    var deviceId: String?
    var spaceId: String?
    var meshUUID: String?
    var meshNetworkId: String?
    var deviceName = "linked_emer_fire_controller_name".localizedString
    var isSynced = false

    var reportToGateway = true
    var publishGroupAddress: Address?
    var configuration = EmergencyFireControllerConfiguration.defaultValue

    var associatedGroupAddresses: [UInt16] = []
    var fireAlarmBrightness = 100
    var powerLossBrightness = 10
    var triggerIntervalSeconds = 5
    var restoreActionType: EmergencyFireRestoreActionType = .restoreAuto
    var restoreBrightness = 100
    var restoreResumingSeconds = 2
    var restoreSendCount = 2

    convenience init(config: LinkedEmerFireConfig) {
        self.init()
        apply(config: config)
    }

    func apply(config: LinkedEmerFireConfig) {
        deviceId = config.deviceId
        spaceId = config.spaceId
        meshUUID = config.meshUUID
        meshNetworkId = config.meshNetworkId
        deviceName = config.deviceName
        isSynced = config.isSynced
        reportToGateway = config.reportToGateway
        publishGroupAddress = config.publishGroupAddress
        configuration = config.configuration
        associatedGroupAddresses = Array(configuration.activeLightLCGroupAddresses).sorted()
        fireAlarmBrightness = configuration.fireAlarmSettings.triggerBrightness
        powerLossBrightness = configuration.powerLossSettings.triggerBrightness
        triggerIntervalSeconds = Int(configuration.powerLossSettings.triggerIntervalSeconds)
        restoreActionType = configuration.restoreSettings.actionType
        restoreBrightness = configuration.restoreSettings.brightness
        restoreResumingSeconds = Int(configuration.restoreSettings.resumingSeconds)
        restoreSendCount = Int(configuration.restoreSettings.sendCount)
        normalizeStepperValues()
    }

    private func normalizeStepperValues() {
        fireAlarmBrightness = min(max(fireAlarmBrightness, 10), 100)
        powerLossBrightness = min(max(powerLossBrightness, 1), 100)
        triggerIntervalSeconds = min(max(triggerIntervalSeconds, 1), 10)
        restoreBrightness = min(max(restoreBrightness, 1), 100)
        restoreResumingSeconds = min(max(restoreResumingSeconds, 0), 120)
        restoreSendCount = min(max(restoreSendCount, 1), 5)
    }

    func groupText() -> String {
        groupNames(for: associatedGroupAddresses)
    }

    func selectedGroupAddresses() -> [UInt16] {
        associatedGroupAddresses
    }

    func updateSelectedGroupAddresses(_ addresses: [UInt16]) {
        let sortedAddresses = addresses.sorted()
        associatedGroupAddresses = sortedAddresses
        configuration.powerLossSettings.associateGroupAddresses = sortedAddresses
        configuration.fireAlarmSettings.associateGroupAddresses = sortedAddresses
    }

    func disabledAssociatedGroupAddresses() -> Set<UInt16> {
        guard let meshUUID, let meshNetworkId else { return [] }
        let devices = DeviceEmerFireStore.shared.loadDevices(meshUUID: meshUUID, meshNetworkId: meshNetworkId)
        let scopedDevices = devices.filter { device in
            if let spaceId {
                return device.spaceId == spaceId
            }
            return true
        }

        return Set(
            scopedDevices
                .filter { $0.id != deviceId }
                .flatMap {
                    $0.configuration.powerLossSettings.associateGroupAddresses +
                    $0.configuration.fireAlarmSettings.associateGroupAddresses
                }
        )
    }

    func conflictingAssociatedGroupNames() -> [String] {
        let conflictAddresses = disabledAssociatedGroupAddresses().intersection(associatedGroupAddresses)
        return conflictAddresses
            .sorted()
            .compactMap { address in
                MeshNetworkManager.instance.groups.first(where: { $0.address.address == address })?.name
            }
    }

    private func groupNames(for addresses: [UInt16]) -> String {
        let names = addresses.compactMap { address in
            MeshNetworkManager.instance.groups.first(where: { $0.address.address == address })?.name
        }
        return names.joined(separator: ",")
    }

    func updateStepperValue(for row: LinkedEmerFireEditRow, delta: Int) {
        switch row {
        case .fireAlarmBrightness:
            setStepperValue(for: row, value: fireAlarmBrightness + delta)
        case .powerLossBrightness:
            setStepperValue(for: row, value: powerLossBrightness + delta)
        case .triggerInterval:
            setStepperValue(for: row, value: triggerIntervalSeconds + delta)
        case .restoreBrightness:
            setStepperValue(for: row, value: restoreBrightness + delta)
        case .restoreResuming:
            setStepperValue(for: row, value: restoreResumingSeconds + delta)
        case .restoreSendCount:
            setStepperValue(for: row, value: restoreSendCount + delta)
        default:
            break
        }
    }

    func setStepperValue(for row: LinkedEmerFireEditRow, value: Int) {
        switch row {
        case .fireAlarmBrightness:
            fireAlarmBrightness = min(max(value, 10), 100)
            configuration.fireAlarmSettings.triggerBrightness = fireAlarmBrightness
        case .powerLossBrightness:
            powerLossBrightness = min(max(value, 1), 100)
            configuration.powerLossSettings.triggerBrightness = powerLossBrightness
        case .triggerInterval:
            triggerIntervalSeconds = min(max(value, 1), 10)
            configuration.powerLossSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
            configuration.fireAlarmSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
        case .restoreBrightness:
            restoreBrightness = min(max(value, 1), 100)
            configuration.restoreSettings.brightness = restoreBrightness
        case .restoreResuming:
            restoreResumingSeconds = min(max(value, 0), 120)
            configuration.restoreSettings.resumingSeconds = UInt8(restoreResumingSeconds)
        case .restoreSendCount:
            restoreSendCount = min(max(value, 1), 5)
            configuration.restoreSettings.sendCount = UInt16(restoreSendCount)
        default:
            break
        }
    }

    func updateRestoreActionType(_ actionType: EmergencyFireRestoreActionType) {
        restoreActionType = actionType
        configuration.restoreSettings.actionType = actionType
    }

    func stepperConfiguration(for row: LinkedEmerFireEditRow) -> LinkedEmerFireStepperConfiguration {
        switch row {
        case .fireAlarmBrightness:
            return .init(title: "Fire Alarm Emergency", fieldTitle: "Set Brightness To:", value: fireAlarmBrightness, range: 10...100, suffix: "%")
        case .powerLossBrightness:
            return .init(title: "Power Loss Emergency", fieldTitle: "Set Brightness To:", value: powerLossBrightness, range: 1...100, suffix: "%")
        case .triggerInterval:
            return .init(title: "Repeatedly Send Emergency Control Every", value: triggerIntervalSeconds, range: 1...10, suffix: "s")
        case .restoreBrightness:
            return .init(title: "Set Brightness to", value: restoreBrightness, range: 1...100, suffix: "%")
        case .restoreResuming:
            return .init(title: "Resuming in:", value: restoreResumingSeconds, range: 0...120, suffix: "s")
        case .restoreSendCount:
            return .init(title: "Send Count (5-second interval):", value: restoreSendCount, range: 1...5, suffix: "")
        default:
            return .init(title: "", value: 0, range: 0...0, suffix: "")
        }
    }

    func makeConfig() -> LinkedEmerFireConfig {
        syncConfiguration()
        return LinkedEmerFireConfig(
            deviceId: deviceId,
            spaceId: spaceId,
            meshUUID: meshUUID,
            meshNetworkId: meshNetworkId,
            deviceName: deviceName,
            isSynced: isSynced,
            reportToGateway: reportToGateway,
            publishGroupAddress: publishGroupAddress,
            configuration: configuration
        )
    }

    private func syncConfiguration() {
        normalizeStepperValues()
        configuration.powerLossSettings.associateGroupAddresses = associatedGroupAddresses
        configuration.fireAlarmSettings.associateGroupAddresses = associatedGroupAddresses
        configuration.powerLossSettings.triggerBrightness = powerLossBrightness
        configuration.fireAlarmSettings.triggerBrightness = fireAlarmBrightness
        configuration.powerLossSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
        configuration.fireAlarmSettings.triggerIntervalSeconds = UInt16(triggerIntervalSeconds)
        configuration.restoreSettings.actionType = restoreActionType
        configuration.restoreSettings.brightness = restoreBrightness
        configuration.restoreSettings.resumingSeconds = UInt8(restoreResumingSeconds)
        configuration.restoreSettings.sendCount = UInt16(restoreSendCount)
    }
}
