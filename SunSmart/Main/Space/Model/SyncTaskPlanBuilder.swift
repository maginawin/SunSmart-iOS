import Foundation
import NordicSigMeshSDK

final class SyncTaskPlanBuilder {
    typealias SyncType = SyncDevicesViewController.SyncType
    typealias SyncState = SyncDevicesViewController.SyncState
    private let type: SyncType
    private var syncState: SyncState
    private let profileSensorProtectionContext: ProfileSensorProtectionContext?
    private let groupProfileSyncContext: GroupProfileSyncContext?
    private let supplementaryProximityLightingSyncDatas: [(node: Node, syncData: NodeSyncData)]
    private var sections: [SyncDevicesSectionModel] = []
    private var failureMessages: [String] = []
    private let proximityBuilder = SyncProximityTaskBuilder()
    private let emergencyBuilder = SyncEmergencyFireTaskBuilder()
    private let switchBuilder: SyncSwitchTaskBuilder
    private var hasBuilt = false

    init(type: SyncType, initialState: SyncState,
         profileSensorProtectionContext: ProfileSensorProtectionContext?,
         groupProfileSyncContext: GroupProfileSyncContext?,
         supplementaryProximityLightingSyncDatas: [(node: Node, syncData: NodeSyncData)],
         imageExists: @escaping (String) -> Bool) {
        self.type = type
        self.syncState = initialState
        self.profileSensorProtectionContext = profileSensorProtectionContext
        self.groupProfileSyncContext = groupProfileSyncContext
        self.supplementaryProximityLightingSyncDatas = supplementaryProximityLightingSyncDatas
        self.switchBuilder = SyncSwitchTaskBuilder(imageExists: imageExists)
    }

    func build() -> SyncTaskPlanResult {
        precondition(!hasBuilt, "A task plan builder is single-use")
        hasBuilt = true

        let removeSection = SyncDevicesSectionModel(title: "remove".localizedString)
        let configurationSection = SyncDevicesSectionModel(title: "configuration".localizedString)

        switch self.type {
        case .group(let group, let inNodes, let outNodes):
            let currentNodes = group.nodes
            let remainingNodes = currentNodes.filter { node in
                !(outNodes?.contains(node) ?? false)
            }
            let addedNodes = (inNodes ?? []).filter { node in
                !remainingNodes.contains(node)
            }
            let effectiveMemberCount = remainingNodes.count + addedNodes.count
            let profileSyncContext = (inNodes == nil && outNodes == nil) ? groupProfileSyncContext : nil
            let addedMemberProfileSyncContext: GroupProfileSyncContext? = addedNodes.isEmpty ? nil : .init(reason: .memberAdded)

            outNodes?.forEach({ node in
                let result = self.getSyncDeviceModel(group: group, node: node, effectiveMemberCount: effectiveMemberCount)
                if let removceDevice = result.removeDevice {
                    removeSection.devices.append(removceDevice)
                }
            })

            inNodes?.forEach({ node in
                let memberProfileSyncContext = addedNodes.contains(node) ? addedMemberProfileSyncContext : nil
                let result = self.getSyncDeviceModel(
                    group: group,
                    node: node,
                    effectiveMemberCount: effectiveMemberCount,
                    profileSyncContext: memberProfileSyncContext
                )
                if let removceDevice = result.removeDevice {
                    removeSection.devices.append(removceDevice)
                }
                if let configurationDevice = result.configturationDevice {
                    configurationSection.devices.append(configurationDevice)
                }
            })

            group.nodes.filter({ node in !(outNodes?.contains(node) ?? false) }).forEach { node in
                let result = self.getSyncDeviceModel(
                    group: group,
                    node: node,
                    effectiveMemberCount: effectiveMemberCount,
                    profileSyncContext: profileSyncContext
                )
                if let removceDevice = result.removeDevice {
                    removeSection.devices.append(removceDevice)
                }
                if let configurationDevice = result.configturationDevice {
                    configurationSection.devices.append(configurationDevice)
                }
            }
            if inNodes == nil, outNodes == nil, let context = profileSensorProtectionContext {
                if let preDisableDevice = context.preDisableDeviceModel() {
                    configurationSection.devices.insert(preDisableDevice, at: 0)
                }
                if let postTargetStateDevice = context.postTargetStateDeviceModel() {
                    configurationSection.devices.append(postTargetStateDevice)
                }
            }
            emergencyBuilder.appendEmergencyFireControllerGroupMutationItems(to: configurationSection, group: group, addNodes: inNodes ?? [], exitNodes: outNodes ?? [])
            let coveredAddresses = Set(
                (group.nodes + (inNodes ?? []) + (outNodes ?? []))
                    .map(\.primaryUnicastAddress)
            )
            proximityBuilder.appendProximityLightingItems(
                to: configurationSection,
                datas: supplementaryProximityLightingSyncDatas.filter {
                    !coveredAddresses.contains($0.node.primaryUnicastAddress)
                },
                title: "path_sequence".localizedString
            )
        case .emergencyFire(let data, let suppliedItems, let context):
            let targetSection = context.persistsSyncResult ? configurationSection : removeSection
            targetSection.prefersDevicesBeforeGroups = true
            emergencyBuilder.appendEmergencyFireControllerItems(
                to: targetSection,
                data: data,
                items: suppliedItems ?? emergencyBuilder.makeEmergencyFireControllerItems(data: data, context: context)
            )
        case .profile(let datas):
            SyncProfileTaskBuilder().appendProfile(to: configurationSection, datas: datas)
        case .scene(let scene):
            SyncSceneScheduleTaskBuilder().appendScene(to: configurationSection, removal: removeSection, scene: scene)
        case .schedule(let schedule):
            SyncSceneScheduleTaskBuilder().appendSchedule(to: configurationSection, removal: removeSection, schedule: schedule)
        case .enOceanSwitch(let switchData, let deleteSwitch):
            switchBuilder.appendEnOcean(to: configurationSection, removal: removeSection, switchData: switchData, deleteSwitch: deleteSwitch)
        case .batteryPowerSwitch(let switchData):
            configurationSection.prefersDevicesBeforeGroups = true
            switchBuilder.appendBatteryPowerSwitchItems(to: configurationSection, removeSection: removeSection, switchData: switchData)

        case .devices(let nodes):

            nodes.forEach { node in
                let result = self.getSyncDeviceModel(group: nil, node: node)
                if let configurationDevice = result.configturationDevice {
                    configurationSection.devices.append(configurationDevice)
                }
                if let removeDevice = result.removeDevice {
                    removeSection.devices.append(removeDevice)
                }
            }
        case .gatewayRecovery(let node, let gateway, let trigger):
            switch SyncGatewayTaskBuilder().makeRecoveryDevice(
                node: node,
                gateway: gateway,
                trigger: trigger
            ) {
            case .success(let deviceModel):
                configurationSection.devices.append(deviceModel)
            case .failure:
                syncState = .syncFailure
                failureMessages.append("failed_to_retrieve_data".localizedString)
            }
        case .gatewayServerRecovery(let node, let gateway):
            guard node.isWiFiGateway else {
                syncState = .syncFailure
                break
            }
            let steps = SyncGatewayTaskBuilder().makeServerRecoverySteps(
                node: node,
                gateway: gateway,
                authorizationDependencies: [],
                includesVerification: true
            )
            let deviceModel = SyncDevicesModel(
                name: node.name ?? gateway.name,
                address: node.primaryUnicastAddress
            )
            deviceModel.imageName = node.iconName
            deviceModel.steps = steps
            steps.forEach { $0.parentDeviceModel = deviceModel }
            configurationSection.devices.append(deviceModel)
        case .devicesParameter(let datas):
            SyncParameterTaskBuilder().appendParameters(to: configurationSection, datas: datas)
        case .dongle(let dongleData):
            let result = SyncDongleTaskBuilder().makeDeviceModels(data: dongleData)
            if let device = result.configturationDevice {
                configurationSection.devices.append(device)
            }
            if let device = result.removeDevice {
                removeSection.devices.append(device)
            }
        case .proximityLightingPath(let datas):
            proximityBuilder.appendProximityLightingItems(
                to: configurationSection,
                datas: datas,
                title: "path_sequence".localizedString
            )
        case .spaceTriggerZones(let datas):
            proximityBuilder.appendProximityLightingItems(
                to: configurationSection,
                datas: datas,
                title: "trigger_zone".localizedString
            )
        }

        let appendSectionIfNeeded: (SyncDevicesSectionModel) -> Void = { section in
            if section.groups.count > 0 || section.devices.count > 0 || section.switchProxy != nil {
                self.sections.append(section)
            }
        }

        if case .batteryPowerSwitch = self.type {
            appendSectionIfNeeded(configurationSection)
            appendSectionIfNeeded(removeSection)
        } else {
            appendSectionIfNeeded(removeSection)
            appendSectionIfNeeded(configurationSection)
        }
        failureMessages.append(contentsOf: emergencyBuilder.failureMessages)
        if switchBuilder.failed || !failureMessages.isEmpty { syncState = .syncFailure }
        for (index, section) in self.sections.enumerated() {
            section.groups.forEach({
                $0.parentSectionIndex = index
            })
            section.devices.forEach({
                $0.parentSectionIndex = index
            })
            section.switchProxy?.parentSectionIndex = index
            section.switchProxy?.deviceModel.parentSectionIndex = index
            if self.syncState == .syncFailure {
                section.allModels.forEach({
                    $0.isFineshed = true
                    $0.state = .failed
                })
            }
        }
        return SyncTaskPlanResult(
            sections: sections,
            initialState: syncState,
            proximityLightingTasks: proximityBuilder.proximityLightingTaskModels,
            failureMessages: failureMessages
        )
    }

    private func getSyncDeviceModel(
        group: Group?,
        node: Node,
        effectiveMemberCount: Int? = nil,
        profileSyncContext: GroupProfileSyncContext? = nil
    ) -> (configturationDevice: SyncDevicesModel?, removeDevice: SyncDevicesModel?) {
        SyncDeviceTaskBuilder().makeDeviceModels(
            group: group,
            node: node,
            effectiveMemberCount: effectiveMemberCount,
            profileSyncContext: profileSyncContext,
            protectsProfileSensors: profileSensorProtectionContext != nil
        )
    }

}

/// 兼容阶段的构建结果，仍包含现有可变任务模型，交给执行方后 Builder 不再访问。
struct SyncTaskPlanResult {
    let sections: [SyncDevicesSectionModel]
    let initialState: SyncDevicesViewController.SyncState
    let proximityLightingTasks: [SyncDeviceStepTaskModel]
    let failureMessages: [String]
}
