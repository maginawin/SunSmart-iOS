import Foundation
import NordicSigMeshSDK

extension SyncExecutionSession {
    var batteryPowerSwitchDataForSync: PJEightKeySwitchData? {
        guard case .batteryPowerSwitch(let switchData) = type else {
            return nil
        }
        return switchData
    }

    func isBatteryPowerSwitchConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        return operationType.isPowerSwitchOwnConfigurationOperation
    }

    func isBatteryPowerSwitchOwnConfigurationOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        return operationType.isPowerSwitchOwnConfigurationOperation
    }

    func isBatteryPowerSwitchSyncOperation(_ operationType: DeviceOperationType) -> Bool {
        guard batteryPowerSwitchDataForSync != nil else {
            return false
        }
        return operationType.isPowerSwitchSyncOperation
    }

    func operationType(for model: SyncCellModel) -> DeviceOperationType? {
        if let deviceModel = model as? SyncDevicesModel {
            return deviceModel.operationType
        }
        if let taskModel = model as? SyncDeviceStepTaskModel {
            return taskModel.operationType
        }
        return nil
    }

    func isMissingRequiredTimeSynchronizationHandle(
        _ model: SyncCellModel,
        messageHandles: [MeshMessageHandle]
    ) -> Bool {
        guard let operationType = operationType(for: model),
              operationType.requiresSiteTimeSetHandle else {
            return false
        }
        return messageHandles.isEmpty
    }

    func isNormalDeviceInitialization(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model),
              case .configuration(_, let actionType) = operationType,
              case .deviceInitialize = actionType else {
            return false
        }
        return true
    }

    func isGatewayRecoveryInitialization(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model),
              case .configuration(_, let actionType) = operationType,
              case .gatewayRecoveryInitialization = actionType else {
            return false
        }
        return true
    }

    func isGatewayRepairInitialization(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model),
              case .configuration(_, let actionType) = operationType,
              case .gatewayRepairInitialization = actionType else {
            return false
        }
        return true
    }

    func containsBatteryPowerSwitchConfiguration(_ device: SyncDevicesModel) -> Bool {
        if let operationType = device.operationType {
            return isBatteryPowerSwitchConfigurationOperation(operationType)
        }
        return device.steps.contains { step in
            containsBatteryPowerSwitchConfiguration(step)
        }
    }

    func containsBatteryPowerSwitchConfiguration(_ step: SyncDeviceStepModel) -> Bool {
        step.tasks.contains { task in
            isBatteryPowerSwitchConfigurationOperation(task.operationType)
        }
    }

    func isBatteryPowerSwitchOwnConfiguration(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model) else {
            return false
        }
        return isBatteryPowerSwitchOwnConfigurationOperation(operationType)
    }

    func isBatteryPowerSwitchKeyConfigConfiguration(_ model: SyncCellModel) -> Bool {
        guard let operationType = operationType(for: model) else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            if case .batteryPowerSwitchKeyConfig = actionType {
                return true
            }
            return false
        default:
            return false
        }
    }

    func batteryPowerSwitchMessageHandles(for model: SyncCellModel, defaultHandles: [MeshMessageHandle]) -> [MeshMessageHandle] {
        guard let operationType = operationType(for: model) else {
            return defaultHandles
        }
        switch operationType {
        case .configuration(let node, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig(let switchData):
                guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
                      let vendorModel = node.sunricherVendorModel else {
                    return defaultHandles
                }
                let appKeyIndex = MeshNetworkManager.instance.currentApplicationKey.index
                return switchData.batteryPowerSwitchKeyConfigurations(appKeyIndex: appKeyIndex).map { configuration in
                    let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig(configuration)), model: vendorModel)
                    handle.continuous = false
                    return handle
                }
            case .batteryPowerSwitchTxEnable(let switchData):
                guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
                      let vendorModel = node.sunricherVendorModel else {
                    return defaultHandles
                }
                let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchTxEnabled(switchData.enabled)), model: vendorModel)
                handle.continuous = false
                return [handle]
            case .batteryPowerSwitchLEDIndicator(let switchData):
                guard node.primaryUnicastAddress == switchData.proxyNodeAddress,
                      let vendorModel = node.sunricherVendorModel else {
                    return defaultHandles
                }
                let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchLEDEnabled(switchData.moreSettingsState.ledIndicatorEnabled)), model: vendorModel)
                handle.continuous = false
                return [handle]
            default:
                return defaultHandles
            }
        default:
            return defaultHandles
        }
    }

    func isMissingRequiredBatteryPowerSwitchConfigurationHandles(_ model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        guard messageHandles.isEmpty,
              let operationType = operationType(for: model) else {
            return false
        }
        switch operationType {
        case .configuration(_, let actionType):
            switch actionType {
            case .batteryPowerSwitchKeyConfig, .batteryPowerSwitchTxEnable, .batteryPowerSwitchLEDIndicator:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    func isSyncOperationSuccessful(
        model: SyncCellModel,
        resultSuccessful: Bool,
        operationSuccessful: Bool,
        messageHandles: [MeshMessageHandle]
    ) -> Bool {
        let category: SyncOperationResultPolicy.Category
        if isGatewayRepairInitialization(model) {
            category = .gatewayRepairInitialization
        } else if isGatewayRecoveryInitialization(model) {
            category = .gatewayRecoveryInitialization
        } else if isEmergencyFireControllerDeleteCleanup(model) {
            category = .emergencyFireDeleteCleanup
        } else if isBatteryPowerSwitchOwnConfiguration(model) {
            category = .batteryPowerSwitchOwnConfiguration
        } else {
            category = .ordinary
        }
        return SyncOperationResultPolicy.isSuccessful(
            category: category,
            hasMessages: !messageHandles.isEmpty,
            resultSuccessful: resultSuccessful,
            operationSuccessful: operationSuccessful
        )
    }

    func resetBatteryPowerSwitchConfigurationForResync() {
        batteryPowerSwitchOwnConfigurationFailed = false
        sections.forEach { section in
            section.devices.forEach { resetBatteryPowerSwitchConfigurationIfNeeded($0) }
            section.groups.forEach { group in
                group.deviceModels.forEach { resetBatteryPowerSwitchConfigurationIfNeeded($0) }
            }
        }
        onReload?()
    }
    func resetBatteryPowerSwitchConfigurationIfNeeded(_ device: SyncDevicesModel) {
        guard containsBatteryPowerSwitchSync(device) else {
            return
        }
        device.isFineshed = false
        device.isSelected = false
        device.failedCount = 0
        if let operationType = device.operationType,
           isBatteryPowerSwitchSyncOperation(operationType) {
            device.state = .none
            return
        }
        device.steps.forEach { step in
            guard containsBatteryPowerSwitchSync(step) else {
                return
            }
            step.isFineshed = false
            step.tasks.forEach { task in
                guard isBatteryPowerSwitchSyncOperation(task.operationType) else {
                    return
                }
                task.isFineshed = false
                task.failedCount = 0
                task.state = .none
            }
        }
    }
    func containsBatteryPowerSwitchSync(_ device: SyncDevicesModel) -> Bool {
        if let operationType = device.operationType {
            return isBatteryPowerSwitchSyncOperation(operationType)
        }
        return device.steps.contains { step in
            containsBatteryPowerSwitchSync(step)
        }
    }
    func containsBatteryPowerSwitchSync(_ step: SyncDeviceStepModel) -> Bool {
        step.tasks.contains { task in
            isBatteryPowerSwitchSyncOperation(task.operationType)
        }
    }
    func markBatteryPowerSwitchOwnConfigurationTasksFailed() {
        sections.forEach { section in
            section.devices.forEach { markBatteryPowerSwitchOwnConfigurationTasksFailed(in: $0) }
            section.groups.forEach { group in
                group.deviceModels.forEach { markBatteryPowerSwitchOwnConfigurationTasksFailed(in: $0) }
            }
        }
    }
    func markBatteryPowerSwitchOwnConfigurationTasksFailed(in device: SyncDevicesModel) {
        guard containsBatteryPowerSwitchConfiguration(device) else {
            return
        }
        if let operationType = device.operationType,
           isBatteryPowerSwitchOwnConfigurationOperation(operationType) {
            if device.state != .failed {
                device.failedCount += 1
            }
            device.state = .failed
            return
        }
        device.steps.forEach { step in
            step.tasks.forEach { task in
                guard isBatteryPowerSwitchOwnConfigurationOperation(task.operationType) else {
                    return
                }
                if task.state != .failed {
                    task.failedCount += 1
                }
                task.state = .failed
            }
        }
    }
}
