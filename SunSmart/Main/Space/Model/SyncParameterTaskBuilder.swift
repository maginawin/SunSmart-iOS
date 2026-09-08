import Foundation
import NordicSigMeshSDK

struct SyncParameterTaskBuilder {
    func appendParameters(to configurationSection: SyncDevicesSectionModel, datas: [(node: Node, parameters: [DeviceParameterType])]) {
        datas.forEach { (node: Node, parameters: [DeviceParameterType]) in

            if parameters.count > 0 {
                var steps: [SyncDeviceStepModel] = []
                parameters.forEach { type in
                    switch type {
                    case .pwmFrequency(let frequency):
                        let taskModel = SyncDeviceStepTaskModel(name: "pwm_frequency".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .pwmFrequency(frequency: frequency))))

                        let step = SyncDeviceStepModel(type: "pwm_frequency".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .ratedPower(let value):
                        let taskModel = SyncDeviceStepTaskModel(name: "rated_power".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .ratedPower(datas: value))))

                        let step = SyncDeviceStepModel(type: "rated_power".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .motionSensitivityRange(range: let range):
                        let taskModel = SyncDeviceStepTaskModel(name: "relative_sensitivity".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .motionSensitivityRange(range: range))))

                        let step = SyncDeviceStepModel(type: "relative_sensitivity".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .defaultTransitionTime(let transitionTime):
                        let taskModel = SyncDeviceStepTaskModel(name: "transition_time".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .defaultTransitionTime(transitionTime: transitionTime))))

                        let step = SyncDeviceStepModel(type: "transition_time".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .powerCalibration(let calibrationValue):
                        let taskModel = SyncDeviceStepTaskModel(name: "power_calibrate".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .powerCalibration(calibrationValue: calibrationValue))))

                        let step = SyncDeviceStepModel(type: "power_calibrate".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .absoluteCctRange(let range):
                        let taskModel = SyncDeviceStepTaskModel(name: "absolute_cct_range".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .absoluteCctRange(range: range))))

                        let step = SyncDeviceStepModel(type: "absolute_cct_range".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    case .photosensorException(let state):
                        let taskModel = SyncDeviceStepTaskModel(name: "photosensor_exception".localizedString, operationType: .configuration(node: node, type: .deviceParameters(parameterType: .photosensorException(state))))
                        let step = SyncDeviceStepModel(type: "photosensor_exception".localizedString, state: .none, tasks: [taskModel])
                        taskModel.parentStepModel = step
                        steps.append(step)
                    }
                }

                let deviceModel = SyncDevicesModel(name: node.name ?? "", address: node.primaryUnicastAddress)
                deviceModel.steps = steps
                steps.forEach({
                    $0.parentDeviceModel = deviceModel
                })
                configurationSection.devices.append(deviceModel)
            }
        }
    }

}
