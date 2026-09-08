import Foundation
import NordicSigMeshSDK

final class SyncSwitchTaskBuilder {
    private(set) var failed = false
    private let imageExists: (String) -> Bool
    init(imageExists: @escaping (String) -> Bool) { self.imageExists = imageExists }

    func appendEnOcean(to configurationSection: SyncDevicesSectionModel, removal removeSection: SyncDevicesSectionModel, switchData: DeviceSwitchData, deleteSwitch: Bool) {
        guard switchData.linkGroup != nil else {
            return
        }
        let data = switchData.getNeedSyncDatas(deleteSwitch: deleteSwitch)
        // 删除动能开关
        let deleteProxyModels = data.deleteProxies.map { proxyNode in
            let deviceModel = SyncDevicesModel(name: proxyNode.name ?? "", address: proxyNode.primaryUnicastAddress)
            deviceModel.imageName = proxyNode.iconName
            deviceModel.operationType = .delete(node: proxyNode, type: .enOceanProxy(switchData: switchData))
            return deviceModel
        }
        if let proxyModel = deleteProxyModels.first {
            removeSection.switchProxy = SyncDevicesSwitchProxyModel(
                name: "enocean_proxy".localizedString,
                deviceModel: proxyModel
            )
            removeSection.devices.append(contentsOf: deleteProxyModels.dropFirst())
        }
        // 同步动能开关
        if let syncNode = data.syncProxy {

            let deviceModel = SyncDevicesModel(name: syncNode.name ?? "", address: syncNode.primaryUnicastAddress)
            deviceModel.imageName = syncNode.iconName
            deviceModel.operationType = .configuration(node: syncNode, type: .enOceanProxy(switchData: switchData))
            linkProxyReplacementDependency(
                deleteModel: deleteProxyModels.first,
                configurationModel: deviceModel
            )

            let proxyModel = SyncDevicesSwitchProxyModel(name: "enocean_proxy".localizedString, deviceModel: deviceModel)
            configurationSection.switchProxy = proxyModel
        }

        // 需解绑动能开关的组
        var deleteSwitchGroupModels = data.deleteGroups.map { (group, nodes) in
            let deviceModels = nodes.map({
                let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                model.imageName = $0.iconName
                model.operationType = .delete(node: $0, type: .enOceanSwitch(switchData: switchData))
                return model
            })

            let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
            deviceModels.forEach({ $0.parentGroupModel = groupModel })
            return groupModel
        }
        deleteSwitchGroupModels = deleteSwitchGroupModels.sorted(by: { $0.address < $1.address })
        removeSection.groups.append(contentsOf: deleteSwitchGroupModels)

        // 需订阅开关的组
        var syncSwitchGroupModels = data.syncGroups.map { (group, nodes) in

            let deviceModels = nodes.map({
                let model = SyncDevicesModel(name: $0.name ?? "", address: $0.primaryUnicastAddress)
                model.imageName = $0.iconName
                model.operationType = .configuration(node: $0, type: .enOceanSwitch(switchData: switchData))
                return model
            })
            let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
            deviceModels.forEach({ $0.parentGroupModel = groupModel })
            return groupModel
        }
        syncSwitchGroupModels = syncSwitchGroupModels.sorted(by: { $0.address < $1.address })
        configurationSection.groups.append(contentsOf: syncSwitchGroupModels)
    }

    private func linkProxyReplacementDependency(
        deleteModel: SyncDevicesModel?,
        configurationModel: SyncDevicesModel
    ) {
        guard let deleteModel,
              let deleteOperation = deleteModel.operationType,
              let configurationOperation = configurationModel.operationType else {
            return
        }

        let deleteTask = SyncDeviceStepTaskModel(
            name: deleteModel.name,
            operationType: deleteOperation
        )
        let proxyDeletionStep = SyncDeviceStepModel(
            type: "remove".localizedString,
            state: .none,
            tasks: [deleteTask]
        )
        deleteTask.parentStepModel = proxyDeletionStep
        proxyDeletionStep.parentDeviceModel = deleteModel
        deleteModel.operationType = nil
        deleteModel.steps = [proxyDeletionStep]

        let configurationTask = SyncDeviceStepTaskModel(
            name: configurationModel.name,
            operationType: configurationOperation
        )
        let proxyConfigurationStep = SyncDeviceStepModel(
            type: "configuration".localizedString,
            state: .none,
            tasks: [configurationTask]
        )
        proxyConfigurationStep.relevanceStepModels = [proxyDeletionStep]
        configurationTask.parentStepModel = proxyConfigurationStep
        proxyConfigurationStep.parentDeviceModel = configurationModel
        configurationModel.operationType = nil
        configurationModel.steps = [proxyConfigurationStep]
    }

    func appendBatteryPowerSwitchItems(
        to section: SyncDevicesSectionModel,
        removeSection: SyncDevicesSectionModel,
        switchData: PJEightKeySwitchData
    ) {
        guard let switchNode = switchData.proxyNode, switchData.linkGroup != nil else {
            failed = true
            return
        }

        let switchDeviceModel = SyncDevicesModel(name: switchData.name, address: switchNode.primaryUnicastAddress)
        let switchIconName = imageExists(switchData.powerSwitchKind.deviceIconAssetName)
            ? switchData.powerSwitchKind.deviceIconAssetName
            : switchNode.iconName
        switchDeviceModel.imageName = switchIconName

        var configurationDependencies: [SyncDeviceStepModel] = []
        let needsKeyConfigSync = switchData.needsBatteryPowerSwitchConfigurationSync
        let needsTxEnableSync = switchData.needsBatteryPowerSwitchTxEnableSync
        let needsLEDIndicatorSync = switchData.needsBatteryPowerSwitchLEDIndicatorSync
        var ownConfigurationTasks: [SyncDeviceStepTaskModel] = []
        if needsKeyConfigSync {
            ownConfigurationTasks.append(SyncDeviceStepTaskModel(
                name: "Key Config",
                operationType: .configuration(node: switchNode, type: .batteryPowerSwitchKeyConfig(switchData: switchData))
            ))
        }
        if needsTxEnableSync {
            ownConfigurationTasks.append(SyncDeviceStepTaskModel(
                name: "TX Enable",
                operationType: .configuration(node: switchNode, type: .batteryPowerSwitchTxEnable(switchData: switchData))
            ))
        }
        if needsLEDIndicatorSync {
            ownConfigurationTasks.append(SyncDeviceStepTaskModel(
                name: "LED Indicator",
                operationType: .configuration(node: switchNode, type: .batteryPowerSwitchLEDIndicator(switchData: switchData))
            ))
        }
        if !ownConfigurationTasks.isEmpty {
            let ownConfigurationStep = SyncDeviceStepModel(type: "Switch Configuration", state: .none, tasks: ownConfigurationTasks)
            ownConfigurationTasks.forEach { $0.parentStepModel = ownConfigurationStep }
            ownConfigurationStep.parentDeviceModel = switchDeviceModel
            switchDeviceModel.steps = [ownConfigurationStep]
            section.devices.append(switchDeviceModel)
            configurationDependencies = [ownConfigurationStep]
        }

        let targetGroups = switchData.bindGroups.sorted { $0.address.address < $1.address.address }
        targetGroups.compactMap {
            makeBatteryPowerSwitchTargetGroupModel(group: $0, switchData: switchData, unsubscribe: false, dependencies: configurationDependencies)
        }.forEach { section.groups.append($0) }

        let removedGroups = switchData.unbindGroupAddresses
            .compactMap { MeshNetworkManager.instance.meshNetwork?.group(withAddress: MeshAddress($0)) }
            .sorted { $0.address.address < $1.address.address }
        removedGroups.compactMap {
            makeBatteryPowerSwitchTargetGroupModel(group: $0, switchData: switchData, unsubscribe: true, dependencies: configurationDependencies)
        }.forEach { removeSection.groups.append($0) }
    }

    private func makeBatteryPowerSwitchTargetGroupModel(
        group: Group,
        switchData: PJEightKeySwitchData,
        unsubscribe: Bool,
        dependencies: [SyncDeviceStepModel]
    ) -> SyncDevicesGroupModel? {
        guard switchData.linkGroup != nil else { return nil }

        let title = unsubscribe ? "Group Unsubscription" : "Group Subscription"
        let deviceModels = group.nodes.compactMap { node -> SyncDevicesModel? in
            let handles = node.getBatteryPowerSwitchTargetSubscriptionMessageHandles(
                switchData: switchData,
                unsubscribe: unsubscribe
            )
            guard !handles.isEmpty else {
                return nil
            }

            let task = SyncDeviceStepTaskModel(
                name: title,
                operationType: .configuration(
                    node: node,
                    type: .batteryPowerSwitchTargetSubscription(switchData: switchData, group: group, unsubscribe: unsubscribe)
                )
            )
            let step = SyncDeviceStepModel(type: title, state: .none, tasks: [task])
            step.relevanceStepModels = dependencies
            task.parentStepModel = step

            let model = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            model.imageName = node.iconName
            model.steps = [step]
            step.parentDeviceModel = model
            return model
        }

        guard !deviceModels.isEmpty else {
            return nil
        }

        let groupModel = SyncDevicesGroupModel(groupName: group.name, groupAddress: group.address.address, deviceModels: deviceModels)
        deviceModels.forEach { $0.parentGroupModel = groupModel }
        return groupModel
    }

}
