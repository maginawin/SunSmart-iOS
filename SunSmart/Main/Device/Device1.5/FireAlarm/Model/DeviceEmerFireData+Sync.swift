//
//  DeviceEmerFireData+Sync.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

extension DeviceEmerFireData {

    static let powerLossTriggerSceneNumber: SceneNumber = 0xFF20
    static let powerLossStopSceneNumber: SceneNumber = 0xFF21
    static let fireAlarmTriggerSceneNumber: SceneNumber = 0xFF22
    static let fireAlarmStopSceneNumber: SceneNumber = 0xFF23
    static let reservedSceneNumbers: Set<SceneNumber> = [
        powerLossTriggerSceneNumber,
        powerLossStopSceneNumber,
        fireAlarmTriggerSceneNumber,
        fireAlarmStopSceneNumber
    ]

    var activeModeSettings: EmergencyFireControllerModeSettings? {
        settings(for: configuration.workMode)
    }

    func settings(for mode: EmergencyFireControllerWorkMode) -> EmergencyFireControllerModeSettings? {
        switch mode {
        case .powerLossEmergency:
            return configuration.powerLossSettings
        case .fireAlarmEmergency:
            return configuration.fireAlarmSettings
        case .allDisabled:
            return nil
        }
    }

    func updateSettings(_ settings: EmergencyFireControllerModeSettings, for mode: EmergencyFireControllerWorkMode) {
        switch mode {
        case .powerLossEmergency:
            configuration.powerLossSettings = settings
        case .fireAlarmEmergency:
            configuration.fireAlarmSettings = settings
        case .allDisabled:
            break
        }
    }

    func mergePendingChanges(from oldConfiguration: EmergencyFireControllerConfiguration, to newConfiguration: EmergencyFireControllerConfiguration) {
        configuration = newConfiguration
        mergePendingChanges(
            for: .powerLossEmergency,
            oldSettings: oldConfiguration.powerLossSettings,
            newSettings: newConfiguration.powerLossSettings,
            tracksRemovedGroups: oldConfiguration.workMode == .powerLossEmergency && newConfiguration.workMode == .powerLossEmergency
        )
        mergePendingChanges(
            for: .fireAlarmEmergency,
            oldSettings: oldConfiguration.fireAlarmSettings,
            newSettings: newConfiguration.fireAlarmSettings,
            tracksRemovedGroups: oldConfiguration.workMode == .fireAlarmEmergency && newConfiguration.workMode == .fireAlarmEmergency
        )
    }

    func markStopSceneRewriteNeeded(groupAddress: Address) {
        [EmergencyFireControllerWorkMode.powerLossEmergency, .fireAlarmEmergency].forEach { mode in
            guard var settings = settings(for: mode),
                  settings.associateGroupAddresses.contains(groupAddress) else {
                return
            }
            if !settings.pendingStopSceneRewriteGroupAddresses.contains(groupAddress) {
                settings.pendingStopSceneRewriteGroupAddresses.append(groupAddress)
                updateSettings(settings, for: mode)
            }
        }
    }

    func clearPending(for task: EmergencyFireControllerSyncTask, meshUUID: String, subnetworkId: String) {
        guard let mode = task.pendingMode,
              let groupAddress = task.pendingGroupAddress,
              var settings = settings(for: mode) else {
            return
        }

        if task.clearsUnassociatePending {
            settings.pendingUnassociateGroupAddresses.removeAll { $0 == groupAddress }
        }
        if task.clearsStopRewritePending {
            settings.pendingStopSceneRewriteGroupAddresses.removeAll { $0 == groupAddress }
        }
        updateSettings(settings, for: mode)
        save(meshUUID: meshUUID, networkId: subnetworkId)
    }

    @discardableResult
    func ensurePublishGroup(meshUUID: String, subnetworkId: String) throws -> Address {
        if let publishGroupAddress {
            print("[EFC] reuse publish group device=\(name), address=\(String(format: "0x%04X", publishGroupAddress))")
            return publishGroupAddress
        }

        let availableGroupAddresses = MeshAPI.getAvailableGroupAddresses(meshUUID: meshUUID, subnetworkId: subnetworkId)
        guard !availableGroupAddresses.isEmpty else {
            throw EmergencyFireControllerPublishGroupError.groupAddressInsufficient
        }
        guard let group = try? MeshAPI.createGroup(name: name + "-Group", isVirtual: true) else {
            throw EmergencyFireControllerPublishGroupError.createGroupFailed
        }

        publishGroupAddress = group.address.address
        save(meshUUID: meshUUID, networkId: subnetworkId)
        print("[EFC] created publish group device=\(name), address=\(String(format: "0x%04X", group.address.address))")
        EmergencyFireControllerSceneEventManager.refreshProxyFilterAddresses()
        return group.address.address
    }

    func getSceneClientPublicationMessageHandles(meshUUID: String, subnetworkId: String) throws -> [MeshMessageHandle] {
        let publishGroupAddress = try ensurePublishGroup(meshUUID: meshUUID, subnetworkId: subnetworkId)

        guard let node = bindNode else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }
        guard node.isKeybindComplete, node.state else {
            throw EmergencyFireControllerPublishGroupError.nodeNotReady
        }
        guard let sceneClientModel = node.sceneClientModel else {
            throw EmergencyFireControllerPublishGroupError.missingSceneClientModel
        }
        guard sceneClientModel.publish?.publicationAddress.address != publishGroupAddress else {
            print("[EFC] scene client publication already set device=\(name), node=\(node.primaryUnicastAddress), address=\(String(format: "0x%04X", publishGroupAddress))")
            return []
        }
        guard let message = ConfigModelPublicationSet(
            Publish(
                to: MeshAddress(publishGroupAddress),
                using: MeshNetworkManager.instance.currentApplicationKey,
                usingFriendshipMaterial: false,
                ttl: MeshNetworkManager.instance.networkParameters.defaultTtl,
                period: .disabled,
                retransmit: .disabled
            ),
            to: sceneClientModel
        ) else {
            throw EmergencyFireControllerPublishGroupError.missingSceneClientModel
        }
        print("[EFC] set scene client publication device=\(name), node=\(node.primaryUnicastAddress), address=\(String(format: "0x%04X", publishGroupAddress))")
        return [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)]
    }

    func makeControllerSyncTasks(meshUUID: String, subnetworkId: String) throws -> [EmergencyFireControllerSyncTask] {
        guard let node = bindNode, let vendorModel = node.sunricherVendorModel else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }

        var tasks: [EmergencyFireControllerSyncTask] = []
        let publicationHandles = try getSceneClientPublicationMessageHandles(meshUUID: meshUUID, subnetworkId: subnetworkId)
        if !publicationHandles.isEmpty {
            tasks.append(EmergencyFireControllerSyncTask(title: "Publication", kind: .publication, address: node.primaryUnicastAddress, messageHandles: publicationHandles))
        }

        tasks.append(EmergencyFireControllerSyncTask(
            title: "Mode",
            kind: .workMode,
            address: node.primaryUnicastAddress,
            messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyMode(configuration.workMode.vendorMode)), model: vendorModel)]
        ))

        if let settings = activeModeSettings {
            let resend = EmergencyControllerResendParameters(
                triggerIntervalSeconds: settings.triggerIntervalSeconds,
                triggerCount: settings.triggerCount,
                stopIntervalSeconds: settings.stopIntervalSeconds,
                stopCount: settings.stopCount
            )
            tasks.append(EmergencyFireControllerSyncTask(
                title: "Resend",
                kind: .resend,
                address: node.primaryUnicastAddress,
                messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyResendParameters(resend)), model: vendorModel)]
            ))
            tasks.append(EmergencyFireControllerSyncTask(
                title: "Restore Delay",
                kind: .restoreDelay,
                address: node.primaryUnicastAddress,
                messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyRestoreDelay(seconds: settings.restoreDelaySeconds)), model: vendorModel)]
            ))
        }
        return tasks
    }

    private func mergePendingChanges(for mode: EmergencyFireControllerWorkMode, oldSettings: EmergencyFireControllerModeSettings, newSettings: EmergencyFireControllerModeSettings, tracksRemovedGroups: Bool) {
        var settings = newSettings
        if tracksRemovedGroups {
            let removedAddresses = oldSettings.associateGroupAddresses.filter { !newSettings.associateGroupAddresses.contains($0) }
            removedAddresses.forEach { address in
                if !settings.pendingUnassociateGroupAddresses.contains(address) {
                    settings.pendingUnassociateGroupAddresses.append(address)
                }
            }
        }
        settings.pendingUnassociateGroupAddresses.removeAll { newSettings.associateGroupAddresses.contains($0) }
        updateSettings(settings, for: mode)
    }
}
