//
//  DeviceEmerFireData+Sync.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

extension DeviceEmerFireData {

    /// EFC 联动灯时使用的保留场景号。
    /// 这些场景号只给应急火警内部使用，后续如果接手人调整场景逻辑，要避开普通用户场景。
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

    var hasSyncableConfiguration: Bool {
        !configuration.activeLightLCGroupAddresses.isEmpty ||
        !configuration.powerLossSettings.pendingUnassociateGroupAddresses.isEmpty ||
        !configuration.fireAlarmSettings.pendingUnassociateGroupAddresses.isEmpty
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

        // 每个 EFC 只创建一个内部 virtual group，并持久化地址。
        // Scene Client / Light LC Client publication 都发布到这个组，灯节点也订阅这个组。
        // 不要在每次同步时重复创建，否则旧订阅无法可靠清理。
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
        // EFC 控制器侧 publication 是整条链路的源头：
        // 控制器发布到内部 virtual group，关联灯再通过订阅该组接收应急场景/LC 命令。
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

    func makeControllerSyncTasks(
        meshUUID: String,
        subnetworkId: String,
        changedFrom oldConfiguration: EmergencyFireControllerConfiguration? = nil
    ) throws -> [EmergencyFireControllerSyncTask] {
        guard let node = bindNode, let vendorModel = node.sunricherVendorModel else {
            throw EmergencyFireControllerPublishGroupError.missingBoundNode
        }

        var tasks: [EmergencyFireControllerSyncTask] = []
        // oldConfiguration 不为空表示从编辑页保存而来，只展示/执行关键变更项；
        // 首次同步或修复同步时 oldConfiguration 为空，需要完整补齐 publication 和 vendor 参数。
        let onlyChangedKeyParameters = oldConfiguration != nil
        let scenePublicationHandles = try getSceneClientPublicationMessageHandles(meshUUID: meshUUID, subnetworkId: subnetworkId)
        if !scenePublicationHandles.isEmpty {
            tasks.append(EmergencyFireControllerSyncTask(title: "Scene Publication", kind: .publication, address: node.primaryUnicastAddress, messageHandles: scenePublicationHandles))
        }

        let lightLCPublicationHandles = try getLightLCClientPublicationMessageHandles(meshUUID: meshUUID, subnetworkId: subnetworkId)
        if !lightLCPublicationHandles.isEmpty {
            tasks.append(EmergencyFireControllerSyncTask(title: "LC Publication", kind: .lightLCClientPublication, address: node.primaryUnicastAddress, messageHandles: lightLCPublicationHandles))
        }

        if oldConfiguration == nil || oldConfiguration?.workMode != configuration.workMode {
            tasks.append(EmergencyFireControllerSyncTask(
                title: "Mode",
                kind: .workMode,
                address: node.primaryUnicastAddress,
                messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyMode(configuration.workMode.vendorMode)), model: vendorModel)],
                changedOnly: onlyChangedKeyParameters
            ))
        }

        if let settings = activeModeSettings {
            let oldSettings = oldConfiguration.flatMap { oldConfiguration in
                oldConfiguration.workMode == configuration.workMode ? modeSettings(for: oldConfiguration.workMode, in: oldConfiguration) : nil
            }
            // resend/restoreDelay 属于 EFC 控制器自身参数，不是灯组参数。
            // 灯组关联和订阅清理由 EmergencyFireControllerSyncPlanner 负责。
            let resend = EmergencyControllerResendParameters(
                triggerIntervalSeconds: settings.triggerIntervalSeconds,
                triggerCount: settings.triggerCount,
                stopIntervalSeconds: settings.stopIntervalSeconds,
                stopCount: settings.stopCount
            )
            if oldConfiguration == nil ||
                oldSettings?.triggerIntervalSeconds != settings.triggerIntervalSeconds ||
                oldSettings?.triggerCount != settings.triggerCount ||
                oldSettings?.stopIntervalSeconds != settings.stopIntervalSeconds ||
                oldSettings?.stopCount != settings.stopCount {
                tasks.append(EmergencyFireControllerSyncTask(
                    title: "Resend",
                    kind: .resend,
                    address: node.primaryUnicastAddress,
                    messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyResendParameters(resend)), model: vendorModel)],
                    changedOnly: onlyChangedKeyParameters
                ))
            }
            if oldConfiguration == nil || oldSettings?.restoreDelaySeconds != settings.restoreDelaySeconds {
                tasks.append(EmergencyFireControllerSyncTask(
                    title: "Restore Delay",
                    kind: .restoreDelay,
                    address: node.primaryUnicastAddress,
                    messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyRestoreDelay(seconds: settings.restoreDelaySeconds)), model: vendorModel)],
                    changedOnly: onlyChangedKeyParameters
                ))
            }
        }
        return tasks
    }

    private func modeSettings(
        for mode: EmergencyFireControllerWorkMode,
        in configuration: EmergencyFireControllerConfiguration
    ) -> EmergencyFireControllerModeSettings? {
        switch mode {
        case .powerLossEmergency:
            return configuration.powerLossSettings
        case .fireAlarmEmergency:
            return configuration.fireAlarmSettings
        case .allDisabled:
            return nil
        }
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

        // 用户取消关联或切换模式时，不能直接丢掉旧组地址。
        // 旧灯组已经订阅了 EFC 内部 publish group，需要进入 pending，等同步成功后再清。
        cleanupGroups.forEach { address in
            if !settings.pendingUnassociateGroupAddresses.contains(address) {
                settings.pendingUnassociateGroupAddresses.append(address)
            }
        }
        // 如果这个组又被当前配置重新选中，就不再需要清理。
        settings.pendingUnassociateGroupAddresses.removeAll { newDesiredGroups.contains($0) }
        updateSettings(settings, for: mode)
    }
}
