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
    static let fireAlarmTriggerSceneNumber: SceneNumber = 0xFF21
    static let restoreSceneNumber: SceneNumber = 0xFF22
    static let reservedSceneNumbers: Set<SceneNumber> = [
        powerLossTriggerSceneNumber,
        fireAlarmTriggerSceneNumber,
        restoreSceneNumber
    ]

    var hasSyncableConfiguration: Bool {
        configuration.hasSyncIntent
    }

    func settings(for function: EmergencyFireControllerFunction) -> EmergencyFireControllerModeSettings {
        switch function {
        case .powerLossEmergency:
            return configuration.powerLossSettings
        case .fireAlarmEmergency:
            return configuration.fireAlarmSettings
        }
    }

    func updateSettings(_ settings: EmergencyFireControllerModeSettings, for function: EmergencyFireControllerFunction) {
        switch function {
        case .powerLossEmergency:
            configuration.powerLossSettings = settings
        case .fireAlarmEmergency:
            configuration.fireAlarmSettings = settings
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
        guard !task.pendingFunctions.isEmpty else {
            return
        }

        task.pendingFunctions.forEach { function in
            guard let groupAddress = task.pendingGroupAddress else {
                return
            }

            var settings = settings(for: function)
            if task.clearsUnassociatePending {
                settings.pendingUnassociateGroupAddresses.removeAll { $0 == groupAddress }
            }
            updateSettings(settings, for: function)
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

        if oldConfiguration == nil || oldConfiguration?.enabled != configuration.enabled {
            tasks.append(EmergencyFireControllerSyncTask(
                title: "Enable",
                kind: .enabled,
                address: node.primaryUnicastAddress,
                messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyEnabled(configuration.enabled)), model: vendorModel)],
                changedOnly: onlyChangedKeyParameters
            ))
        }

        EmergencyFireControllerState.allCases.forEach { state in
            let resend = configuration.resendParameters(for: state)
            let oldResend = oldConfiguration?.resendParameters(for: state)
            if oldConfiguration == nil || !resendParametersEqual(oldResend, resend) {
                tasks.append(EmergencyFireControllerSyncTask(
                    title: "\(state.taskTitle) Resend",
                    kind: .resend,
                    address: node.primaryUnicastAddress,
                    messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyResendParameters(resend)), model: vendorModel)],
                    changedOnly: onlyChangedKeyParameters
                ))
            }

            let actionConfig = configuration.actionConfig(
                for: state,
                targetAddress: publishGroupAddress,
                appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index,
                ttl: MeshNetworkManager.instance.networkParameters.defaultTtl
            )
            let oldActionConfig = oldConfiguration?.actionConfig(
                for: state,
                targetAddress: publishGroupAddress,
                appKeyIndex: MeshNetworkManager.instance.currentApplicationKey.index,
                ttl: MeshNetworkManager.instance.networkParameters.defaultTtl
            )
            if oldConfiguration == nil || oldActionConfig != actionConfig {
                tasks.append(EmergencyFireControllerSyncTask(
                    title: "\(state.taskTitle) Action",
                    kind: .actionConfig,
                    address: node.primaryUnicastAddress,
                    messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyActionConfig(actionConfig)), model: vendorModel)],
                    changedOnly: onlyChangedKeyParameters
                ))
            }
        }

        if oldConfiguration == nil || oldConfiguration?.restoreDelaySeconds() != configuration.restoreDelaySeconds() {
            tasks.append(EmergencyFireControllerSyncTask(
                title: "Restore Delay",
                kind: .restoreDelay,
                address: node.primaryUnicastAddress,
                messageHandles: [MeshMessageHandle(message: SunricherVendorSet(function: .emergencyRestoreDelay(seconds: configuration.restoreDelaySeconds())), model: vendorModel)],
                changedOnly: onlyChangedKeyParameters
            ))
        }
        return tasks
    }

    private func resendParametersEqual(_ lhs: EmergencyFireResendParameters?, _ rhs: EmergencyFireResendParameters) -> Bool {
        guard let lhs else {
            return false
        }
        return lhs.stateIndex == rhs.stateIndex &&
            lhs.intervalSeconds == rhs.intervalSeconds &&
            lhs.count == rhs.count
    }

    private func mergePendingChanges(
        for function: EmergencyFireControllerFunction,
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
        updateSettings(settings, for: function)
    }
}
