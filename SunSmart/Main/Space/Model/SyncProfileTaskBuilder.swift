import Foundation
import NordicSigMeshSDK

struct SyncProfileTaskBuilder {
    func appendProfile(to configurationSection: SyncDevicesSectionModel, datas: [(node: Node, profiles: [ProfileType])]) {
        datas.forEach { (node: Node, profiles: [ProfileType]) in
            // 锁定配置切换操作
            var luxTriggerLockStep: SyncDeviceStepModel?
            // 设置白天/晚上lux阈值操作
            var luxThresholdStep: SyncDeviceStepModel?
            // 切换到对应profile操作
            var switchProfileStep: SyncDeviceStepModel?
            // 保存到profile 场景
            var lastProfileStoreStep: SyncDeviceStepModel?
            /// 同步profile场景的操作list
            var syncProfileSceneSteps: [SyncDeviceStepModel] = []
            let syncProfileSteps = profiles.map({

                let task = SyncDeviceStepTaskModel(name: $0.title, operationType: .configuration(node: node, type: .profile(type: $0)))

                let step = SyncDeviceStepModel(type: $0.title, state: .none, tasks: [task])
                task.parentStepModel = step

                // 设置前置条件关联
                switch $0 {
                case .profileToggleTriggerConditionLuxLock:
                    luxTriggerLockStep = step
                case .profileDayToggleTriggerConditionLux, .profileNightToggleTriggerConditionLux:
                    luxThresholdStep = step
                case .lightControlSwitch, .daylightSensorConditionRecall:
                    switchProfileStep = step
                    if luxTriggerLockStep != nil {
                        step.relevanceStepModels.append(luxTriggerLockStep!)
                    }
                    if luxThresholdStep != nil {
                        step.relevanceStepModels.append(luxThresholdStep!)
                    }
                    if lastProfileStoreStep != nil {
                        step.relevanceStepModels.append(lastProfileStoreStep!)
                    }
                case .lightControlStore:
                    step.relevanceStepModels = syncProfileSceneSteps
                    syncProfileSceneSteps.removeAll()
                    lastProfileStoreStep = step
                case .powerOnState, .daylightCalibration, .daylightCalibrateRate, .daylightCalibrateInflectionPoint, .sensitivity, .lightControlDelete, .profileToggleTriggerConditionLuxDelete:
                    break
                default:
                    if luxTriggerLockStep != nil {
                        step.relevanceStepModels.append(luxTriggerLockStep!)
                    }
                    if switchProfileStep != nil {
                        step.relevanceStepModels.append(switchProfileStep!)
                    }
                    syncProfileSceneSteps.append(step)
                }
                return step
            })

            let deviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
            deviceModel.steps = syncProfileSteps
            syncProfileSteps.forEach { step in
                step.parentDeviceModel = deviceModel
            }
            configurationSection.devices.append(deviceModel)
        }

    }

}
