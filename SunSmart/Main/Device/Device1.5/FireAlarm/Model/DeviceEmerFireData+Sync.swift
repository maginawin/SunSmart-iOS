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

        let oldDesiredGroups = oldConfiguration.activeLightLCGroupAddresses
        let newDesiredGroups = newConfiguration.activeLightLCGroupAddresses
        let noLongerDesiredGroups = oldDesiredGroups.subtracting(newDesiredGroups)

        mergePendingChanges(
            for: .powerLossEmergency,
            oldSettings: oldConfiguration.powerLossSettings,
            newSettings: newConfiguration.powerLossSettings,
            newDesiredGroups: newDesiredGroups,
            noLongerDesiredGroups: noLongerDesiredGroups
        )
        mergePendingChanges(
            for: .fireAlarmEmergency,
            oldSettings: oldConfiguration.fireAlarmSettings,
            newSettings: newConfiguration.fireAlarmSettings,
            newDesiredGroups: newDesiredGroups,
            noLongerDesiredGroups: noLongerDesiredGroups
        )
    }

    func clearPending(for task: EmergencyFireControllerSyncTask, meshUUID: String, subnetworkId: String) {
        guard !task.pendingModes.isEmpty else {
            return
        }

        task.pendingModes.forEach { mode in
            guard let groupAddress = task.pendingGroupAddress,
                  var settings = settings(for: mode) else {
                return
            }

            if task.clearsUnassociatePending {
                settings.pendingUnassociateGroupAddresses.removeAll { $0 == groupAddress }
            }
            updateSettings(settings, for: mode)
        }
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

    private func getPublicationMessageHandles(model: Model?, missingModelError: EmergencyFireControllerPublishGroupError, meshUUID: String, subnetworkId: String) throws -> [MeshMessageHandle] {
        let publishGroupAddress = try ensurePublishGroup(meshUUID: meshUUID, subnetworkId: subnetworkId)

        guard let node = bindNode else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }
        guard node.isKeybindComplete, node.state else {
            throw EmergencyFireControllerPublishGroupError.nodeNotReady
        }
        guard let model else {
            throw missingModelError
        }
        guard model.publish?.publicationAddress.address != publishGroupAddress else {
            print("[EFC] publication already set device=\(name), node=\(node.primaryUnicastAddress), address=\(String(format: "0x%04X", publishGroupAddress))")
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
            to: model
        ) else {
            throw missingModelError
        }
        print("[EFC] set publication device=\(name), node=\(node.primaryUnicastAddress), address=\(String(format: "0x%04X", publishGroupAddress))")
        return [MeshMessageHandle(message: message, address: node.primaryUnicastAddress)]
    }

    func getSceneClientPublicationMessageHandles(meshUUID: String, subnetworkId: String) throws -> [MeshMessageHandle] {
        guard let node = bindNode else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }
        return try getPublicationMessageHandles(
            model: node.sceneClientModel,
            missingModelError: .missingSceneClientModel,
            meshUUID: meshUUID,
            subnetworkId: subnetworkId
        )
    }

    func getLightLCClientPublicationMessageHandles(meshUUID: String, subnetworkId: String) throws -> [MeshMessageHandle] {
        guard let node = bindNode else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }
        return try getPublicationMessageHandles(
            model: node.lightLCClientModel,
            missingModelError: .missingLightLCClientModel,
            meshUUID: meshUUID,
            subnetworkId: subnetworkId
        )
    }

    func makeControllerSyncTasks(meshUUID: String, subnetworkId: String) throws -> [EmergencyFireControllerSyncTask] {
        guard let node = bindNode, let vendorModel = node.sunricherVendorModel else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }

        var tasks: [EmergencyFireControllerSyncTask] = []
        let scenePublicationHandles = try getSceneClientPublicationMessageHandles(meshUUID: meshUUID, subnetworkId: subnetworkId)
        if !scenePublicationHandles.isEmpty {
            tasks.append(EmergencyFireControllerSyncTask(title: "Scene Publication", kind: .publication, address: node.primaryUnicastAddress, messageHandles: scenePublicationHandles))
        }

        let lightLCPublicationHandles = try getLightLCClientPublicationMessageHandles(meshUUID: meshUUID, subnetworkId: subnetworkId)
        if !lightLCPublicationHandles.isEmpty {
            tasks.append(EmergencyFireControllerSyncTask(title: "LC Publication", kind: .lightLCClientPublication, address: node.primaryUnicastAddress, messageHandles: lightLCPublicationHandles))
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

    private func mergePendingChanges(
        for mode: EmergencyFireControllerWorkMode,
        oldSettings: EmergencyFireControllerModeSettings,
        newSettings: EmergencyFireControllerModeSettings,
        newDesiredGroups: Set<Address>,
        noLongerDesiredGroups: Set<Address>
    ) {
        var settings = newSettings
        let oldGroups = Set(oldSettings.associateGroupAddresses)
        let newGroups = Set(newSettings.associateGroupAddresses)
        let removedFromThisMode = oldGroups.subtracting(newGroups)
        let removedByModeSwitch = oldGroups.intersection(noLongerDesiredGroups)
        let cleanupGroups = removedFromThisMode.union(removedByModeSwitch)

        cleanupGroups.forEach { address in
            if !settings.pendingUnassociateGroupAddresses.contains(address) {
                settings.pendingUnassociateGroupAddresses.append(address)
            }
        }
        settings.pendingUnassociateGroupAddresses.removeAll { newDesiredGroups.contains($0) }
        updateSettings(settings, for: mode)
    }
}
