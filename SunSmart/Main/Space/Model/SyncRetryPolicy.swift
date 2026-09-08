import Foundation
import NordicSigMeshSDK

/// 重置失败任务及本轮必需前置条件，保留已成功的无关操作。
struct SyncRetryPolicy {
    func prepareDeviceForResync(_ device: SyncDevicesModel) {
        device.isFineshed = false
        device.isSelected = false

        // 直接操作设备（无步骤）
        if device.steps.isEmpty {
            if device.state != .successful {
                device.state = .none
                if let operationType = device.operationType {
                    resetMessageHandlesForResync(operationType.messageHandles)
                }
            }
            return
        }

        // 按步骤操作设备：将非成功任务统一重置为 none，避免 wait/failed 混用导致错误聚合
        device.steps.forEach { step in
            step.isFineshed = false
            step.tasks.forEach { task in
                if task.state != .successful {
                    prepareTaskForResync(task)
                }
            }
        }
    }

    func prepareStepForResync(_ step: SyncDeviceStepModel) {
        step.isFineshed = false
        step.parentDeviceModel?.isFineshed = false
        step.parentDeviceModel?.isSelected = false
        step.tasks.forEach { task in
            if task.state != .successful {
                prepareTaskForResync(task)
            }
        }
    }

    func prepareTaskForResync(_ task: SyncDeviceStepTaskModel) {
        task.isFineshed = false
        task.failedCount = 0
        task.resetSkippedState()
        task.state = .none
        resetMessageHandlesForResync(task.operationType.messageHandles)
        task.parentStepModel?.isFineshed = false
        task.parentStepModel?.parentDeviceModel?.isFineshed = false
        task.parentStepModel?.parentDeviceModel?.isSelected = false
        if task.relevanceTaskModels.count > 0 {
            task.resyncRelevanceCheck().forEach({
                $0.state = .wait
            })
        }
    }

    func resetMessageHandlesForResync(_ messageHandles: [MeshMessageHandle]) {
        messageHandles.forEach { handle in
            handle.respondAddresss = []
            handle.notRespondAddresss = []
        }
    }

}

extension SyncDeviceStepTaskModel {

    /// 检查对应task相关联的条件task，如需重试同步时需要把前置关联的task也一起同步
    /// - Parameter task: 重新同步的task数据
    /// - Returns: 返回需要一起同步的关联task数据
    func resyncRelevanceCheck() -> [SyncDeviceStepTaskModel] {

        var relevanceTaskModels: [SyncDeviceStepTaskModel] = []
        // 检查是否有profile数据需要加锁、切换场景前置要求，需要则重试必须连带前置条件一起设置
        if self.relevanceTaskModels.count > 0 {
            relevanceTaskModels = self.relevanceTaskModels.filter { task in
                if task.operationType.isTimedScheduleTimeSyncOperation {
                    return true
                }
                if case .configuration(_, let actionType) = task.operationType, case .profile(let profileType) = actionType {
                    switch profileType {
                    case .profileToggleTriggerConditionLuxLock,
                            .profileDayToggleTriggerConditionLux,
                            .profileNightToggleTriggerConditionLux,
                            .lightControlSwitch,
                            .daylightSensorConditionRecall:
                        return true
                    default:
                        return false
                    }
                }
                return false
            }
        }
        return relevanceTaskModels
    }

}
