import Foundation
import ObjectiveC
import NordicSigMeshSDK

extension SyncExecutionSession {

    func attemptDaylightConditionRecallRecovery(handle: MeshMessageHandle, status: SunricherVendorStatus, syncModel: SyncCellModel) -> Bool {
        guard !status.status.isSuccessful,
              status.status.code == .daylightConditionRecall,
              status.status.errorCode == 2,
              let vendorSet = handle.message as? SunricherVendorSet,
              case .daylightConditionRecall(let index) = vendorSet.function,
              let node = handle.model?.parentElement?.parentNode,
              let vendorModel = node.sunricherVendorModel else {
            return false
        }
        let recoveryKey = "\(node.primaryUnicastAddress)-\(index)"
        guard !daylightConditionRecallRecoveryKeys.contains(recoveryKey),
              let recoveryHandles = daylightConditionRecallRecoveryMessageHandles(node: node, index: index, syncModel: syncModel, vendorModel: vendorModel),
              !recoveryHandles.isEmpty else {
            return false
        }
        daylightConditionRecallRecoveryKeys.insert(recoveryKey)
        environment.addMessage(messageHandles: recoveryHandles, ackMessageTimeout: ackTimeout(for: syncModel), finishedBack: nil)
        return true
    }

    func daylightConditionRecallRecoveryMessageHandles(node: Node, index: UInt8, syncModel: SyncCellModel, vendorModel: Model) -> [MeshMessageHandle]? {
        guard let conditionProfile = daylightConditionRecallRecoveryProfile(node: node, index: index, syncModel: syncModel) else {
            return nil
        }
        var messageHandles = conditionProfile.getMessageHandles(node: node)
        messageHandles.forEach { $0.continuous = false }
        let recallHandle = MeshMessageHandle(message: SunricherVendorSet(function: .daylightConditionRecall(index: index)), model: vendorModel)
        recallHandle.continuous = false
        messageHandles.append(recallHandle)
        return messageHandles
    }

    func daylightConditionRecallRecoveryProfile(node: Node, index: UInt8, syncModel: SyncCellModel) -> ProfileType? {
        if let taskModel = syncModel as? SyncDeviceStepTaskModel,
           let profile = daylightConditionRecallRecoveryProfile(index: index, taskModels: taskModel.parentStepModel?.tasks ?? []) {
            return profile
        }
        return daylightConditionRecallRecoveryProfileFromGroup(node: node, index: index)
    }

    func daylightConditionRecallRecoveryProfile(index: UInt8, taskModels: [SyncDeviceStepTaskModel]) -> ProfileType? {
        for task in taskModels {
            guard case .configuration(_, let actionType) = task.operationType,
                  case .profile(let profileType) = actionType else {
                continue
            }
            switch profileType {
            case .profileDayToggleTriggerConditionLux(let id, let minLux, let maxLux, let useCalibrationValues, let destination, let sceneNumber, _):
                if id == index {
                    return .profileDayToggleTriggerConditionLux(id: id, minLux: minLux, maxLux: maxLux, useCalibrationValues: useCalibrationValues, destination: destination, sceneNumber: sceneNumber, forceFullSet: true)
                }
            case .profileNightToggleTriggerConditionLux(let id, let minLux, let maxLux, let useCalibrationValues, let destination, let sceneNumber, _):
                if id == index {
                    return .profileNightToggleTriggerConditionLux(id: id, minLux: minLux, maxLux: maxLux, useCalibrationValues: useCalibrationValues, destination: destination, sceneNumber: sceneNumber, forceFullSet: true)
                }
            default:
                continue
            }
        }
        return nil
    }

    func daylightConditionRecallRecoveryProfileFromGroup(node: Node, index: UInt8) -> ProfileType? {
        guard case .group(let group, _, _) = type else {
            return nil
        }
        let sceneDestination = node.lightLCSceneModel?.parentElement?.unicastAddress ?? node.lightLCModel?.parentElement?.unicastAddress ?? node.primaryUnicastAddress
        if let nightData = group.info.profile.nightData, nightData.id == index {
            let targetLux = node.preConfiguration.nightProfileStartsBelowLux ?? nightData.startsBelowLux
            return .profileNightToggleTriggerConditionLux(id: nightData.id, minLux: 0, maxLux: targetLux, useCalibrationValues: nightData.useCalibrationValues, destination: sceneDestination, sceneNumber: nightData.sceneData.sceneNumber, forceFullSet: true)
        }
        if let dayData = group.info.profile.dayData, dayData.id == index {
            let targetLux = node.preConfiguration.dayProfileStartsAboveLux ?? dayData.startsBelowLux
            return .profileDayToggleTriggerConditionLux(id: dayData.id, minLux: targetLux, maxLux: .max, useCalibrationValues: dayData.useCalibrationValues, destination: sceneDestination, sceneNumber: dayData.sceneData.sceneNumber, forceFullSet: true)
        }
        return nil
    }
}

private extension Node {

    static var daylightRecallConditionIdKey: UInt8 = 0
    /// 光照传感器当前激活的条件id
    var daylightRecallConditionId: UInt8? {
        get {
            objc_getAssociatedObject(self, &Node.daylightRecallConditionIdKey) as? UInt8
        }set {
            objc_setAssociatedObject(self, &Node.daylightRecallConditionIdKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}

extension SyncExecutionSession {
    func prepareDaylightHandles(for model: SyncCellModel, handles: [MeshMessageHandle]) -> [MeshMessageHandle] {
        var messageHandles = handles
        if case .configuration(let node, let type) = operationType(for: model), node.capabilities.contains(.lightSensorConditionRecall), case .profile(let profiletType) = type {
            if let vendorModel = node.sunricherVendorModel {
                switch profiletType {
                case .profileToggleTriggerConditionLuxLock: // 加锁
                    node.daylightRecallConditionId = nil
                    messageHandles.insert(MeshMessageHandle(message: SunricherVendorGet(function: .daylightConditionRecallGet), model: vendorModel), at: 0)
                case .profileToggleTriggerConditionLuxUnLock: // 解锁
                    if let index = node.daylightRecallConditionId {
                        messageHandles.insert(MeshMessageHandle(message: SunricherVendorSet(function: .daylightConditionRecall(index: index)), model: vendorModel), at: 0)
                    }
                default:
                    break
                }
            }
        }
        return messageHandles
    }
    func recordDaylightCondition(node: Node, index: UInt8) { node.daylightRecallConditionId = index }
}
