import Foundation
import NordicSigMeshSDK

extension SyncExecutionSession {
    func applyResult(_ resultMessageHandles: [MeshMessageHandle], model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        resultMessageHandles.forEach { handle in
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.updateData(
                    message: handle.message,
                    isSuccess: handle.isSuccessful,
                    model: handle.model
                )
                // 清空同步缓存状态
                node.clearSyncStateCache()
            }
        }

        var resultSuccessful = !resultMessageHandles.contains(where: { !$0.isSuccessful })
        if resultSuccessful, let operation = operationType(for: model),
           case .delete(let node, .missingGroupSubscriptions) = operation {
            resultSuccessful = MissingGroupSubscriptionCleanup.finish(for: node)
        }
        let operationSuccessful = ((model as? SyncDevicesModel)?.operationType?.isSuccessful ?? (model as? SyncDeviceStepTaskModel)?.operationType.isSuccessful) ?? false
        let isSuccessful = self.isSyncOperationSuccessful(
            model: model,
            resultSuccessful: resultSuccessful,
            operationSuccessful: operationSuccessful,
            messageHandles: messageHandles
        )
        return isSuccessful
    }
    func finishOperation(_ model: SyncCellModel, successful isSuccessful: Bool) {
        let isBatteryPowerSwitchKeyConfigModel = isBatteryPowerSwitchKeyConfigConfiguration(model)
        if isSuccessful {
            model.state = .successful
            self.clearEmergencyFireControllerPendingIfNeeded(for: model)
            self.persistEmergencyFireDeleteCleanupProgressIfNeeded(for: model)
            if isBatteryPowerSwitchKeyConfigModel {
                self.batteryPowerSwitchKeyConfigurationCompleted = true
            }

            if self.deviceBlinkMode != .none {
                let deviceModel: SyncDevicesModel? =
                (model as? SyncDevicesModel)
                ?? (model as? SyncDeviceStepTaskModel)?.parentStepModel?.parentDeviceModel
                // 设备全部成功判断
                if let deviceModel = deviceModel,
                   let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: deviceModel.address),
                    deviceModel.state == .successful {
                    // 发送设备闪烁命令
                    node.sendHandleCompleteIdentify(deviceBlinkMode: self.deviceBlinkMode)
                }
            }

        }else {
            model.state = .failed
            (model as? SyncDevicesModel)?.failedCount += 1
            (model as? SyncDeviceStepTaskModel)?.failedCount += 1
            if self.isBatteryPowerSwitchOwnConfiguration(model) {
                self.batteryPowerSwitchOwnConfigurationFailed = true
                self.markBatteryPowerSwitchOwnConfigurationTasksFailed()
            }
        }
        updateCell(model: model)
    }
}
