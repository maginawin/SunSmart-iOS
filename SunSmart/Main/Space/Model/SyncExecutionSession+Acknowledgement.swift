import Foundation
import NordicSigMeshSDK

extension SyncExecutionSession {
    func received(handle: MeshMessageHandle, statusMessage: StaticMeshMessage, model: SyncCellModel, messageHandles: [MeshMessageHandle]) {
        if let operation = operationType(for: model),
           case .delete(let node, .missingGroupSubscriptions) = operation {
            _ = MissingGroupSubscriptionCleanup.acknowledge(handle, status: statusMessage, for: node)
            return
        }
        // 判断如果是设备初始化消息，则需要再初始化完成后完成基本配置
        if self.isGatewayRepairInitialization(model),
           statusMessage is ConfigCompositionDataStatus,
           let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
           let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
            let appendedHandles = node.getGatewayRepairInitializationMessageHandles()
            if !appendedHandles.isEmpty {
                environment.addMessage(
                    messageHandles: appendedHandles,
                    finishedBack: nil
                )
            }
        } else if self.isNormalDeviceInitialization(model),
                  statusMessage is ConfigCompositionDataStatus || statusMessage is ConfigAppKeyStatus {
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
               let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
               node.isInitialize {
                environment.addMessage(
                    messageHandles: node.getConfigMessageHandles(),
                    finishedBack: nil
                )
            }
        }else if (statusMessage is GenericOnOffStatus || statusMessage is LightLightnessStatus || statusMessage is LightCTLTemperatureStatus || statusMessage is LightCTLStatus || statusMessage is LightHSLStatus), messageHandles.contains(where: { $0.message is SceneStore }) { // 设置场景时需要及时更新状态属性
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.updateNodeStatus(message: statusMessage, source: address)
                if let onOffStatus = statusMessage as? GenericOnOffStatus,
                   !(onOffStatus.targetState ?? onOffStatus.isOn) {
                    node.lightness = 0
                }
            }
        }else if let vendorStatusMessage = statusMessage as? SunricherVendorStatus {
            if vendorStatusMessage.status.code == .dimmerPowerCalibrate {
                if vendorStatusMessage.status.errorCode == 2 { // 功率校准异常
                    if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                        if case .dimmerPowerCalibrateError(let maxPower) = vendorStatusMessage.status.parameters {
                            node.powerCalibrateError = .powerExceed(maxPower: Int(maxPower / 10))
                        }else {
                            node.powerCalibrateError = .powerExceed(maxPower: 300)
                        }
                    }
                }
            }else if vendorStatusMessage.status.code == .daylightLuxTriggerLock { // lux触发场景锁定/解锁
                if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                    if let vendorSet = handle.message as? SunricherVendorSet, case .daylightLuxTriggerLock(let delay) = vendorSet.function {
                        if delay > 0 {
                            if !self.luxTriggerLockDevices.contains(node) {
                                self.luxTriggerLockDevices.append(node)
                            }
                        }else {
                            if let index = self.luxTriggerLockDevices.firstIndex(of: node) {
                                self.luxTriggerLockDevices.remove(at: index)
                            }
                        }
                    }
                }
            }else if handle.message is SunricherVendorGet, case .daylightConditionRecall(let index) = vendorStatusMessage.status.parameters, index >= 0 { // 记录当前运行的白天/黑夜条件配置
                if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                    recordDaylightCondition(node: node, index: UInt8(index))
                }
            }else if self.attemptDaylightConditionRecallRecovery(handle: handle, status: vendorStatusMessage, syncModel: model) {
                handle.respondAddresss = handle.allAddresss
                handle.notRespondAddresss = []
            }
        }
    }
    func failed(handle: MeshMessageHandle) {
        if let vendorSetMessage = handle.message as? SunricherVendorSet, case .dimmerPowerCalibrate = vendorSetMessage.function { // 功率校准超时
            if let address = handle.address ?? handle.model?.parentElement?.unicastAddress, let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                node.powerCalibrateError = .timeout
            }
        }
    }
}
