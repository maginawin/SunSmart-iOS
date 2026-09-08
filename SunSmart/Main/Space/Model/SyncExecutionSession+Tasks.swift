import Foundation
import NordicSigMeshSDK

extension SyncExecutionSession {
    func completeProfileSensorProtectionTaskIfNeeded(for model: SyncCellModel) -> Bool {
        guard let taskModel = model as? SyncDeviceStepTaskModel else {
            return false
        }

        switch taskModel.operationType {
        case .configuration(let node, let type):
            switch type {
            case .profileSensorProtectionDisable:
                profileSensorProtectionContext?.markPreDisableStarted()
                return false
            case .profileSensorTargetEnable:
                profileSensorProtectionContext?.markTargetStateTaskStarted(for: node)
                return false
            default:
                return false
            }
        default:
            return false
        }
    }
    func prepareDeviceForResync(_ device: SyncDevicesModel) {
        SyncRetryPolicy().prepareDeviceForResync(device)
    }
    func prepareStepForResync(_ step: SyncDeviceStepModel) {
        SyncRetryPolicy().prepareStepForResync(step)
    }
    func prepareTaskForResync(_ task: SyncDeviceStepTaskModel) {
        SyncRetryPolicy().prepareTaskForResync(task)
    }
    func resetMessageHandlesForResync(_ messageHandles: [MeshMessageHandle]) {
        SyncRetryPolicy().resetMessageHandlesForResync(messageHandles)
    }
    func markPendingGatewayRecoveryTasksSkipped() {
        guard gatewayRecoveryNode != nil else {
            return
        }
        sections.forEach { section in
            section.allModels
                .compactMap { $0 as? SyncDeviceStepTaskModel }
                .filter { $0.state == .none || $0.state == .wait }
                .forEach { $0.markSkipped() }
        }
    }
    func getNextHandleModel() -> SyncCellModel? {

        for section in sections {
            let devices = section.allModels.filter({ $0.isKind(of: SyncDevicesModel.classForCoder()) }) as! [SyncDevicesModel]
            for device in devices {
                if device.operationType != nil && device.steps.isEmpty && (device.state == .none || device.state == .wait) {
                    return device
                }
                for step in device.steps {
                    if step.relevanceStepModels.contains(where: { $0.state == .failed }) {
                        continue
                    }
                    if step.relevanceStepModels.contains(where: { $0.state != .successful }) {
                        continue
                    }
                    if let model = step.tasks.first(where: { $0.state == .none || $0.state == .wait }) {
                        if model.relevanceTaskModels.contains(where: { $0.state == .failed }) {
                            continue
                        }
                        return model
                    }
                }
            }
        }
        return nil
    }
    func selectedFailedDevicesForResync() -> [SyncDevicesModel] {
        var selectedDevices: [SyncDevicesModel] = []
        sections.forEach { section in
            let models = section.allModels.filter {
                (($0 as? SyncDevicesModel)?.isSelected ?? false) && $0.state == .failed
            } as! [SyncDevicesModel]
            selectedDevices.append(contentsOf: models)
        }
        return selectedDevices
    }
    var gatewayRecoveryNode: Node? {
        switch type {
        case .gatewayRecovery(let node, _, _),
             .gatewayServerRecovery(let node, _):
            return node
        default:
            return nil
        }
    }
}
