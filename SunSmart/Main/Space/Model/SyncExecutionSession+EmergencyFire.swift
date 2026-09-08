import Foundation
import NordicSigMeshSDK

extension SyncExecutionSession {
    func isEmergencyFireControllerLocalGroupCleanupTask(_ task: EmergencyFireControllerSyncTask) -> Bool {
        SyncEmergencyFireTaskBuilder().isEmergencyFireControllerLocalGroupCleanupTask(task)
    }

    func emergencyFireControllerTask(for model: SyncCellModel) -> (task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData)? {
        let operationType = (model as? SyncDevicesModel)?.operationType ?? (model as? SyncDeviceStepTaskModel)?.operationType
        guard case .configuration(_, let type) = operationType,
              case .emergencyFireController(let task, let data) = type else {
            return nil
        }
        return (task, data)
    }

    func emergencyFireControllerTaskContexts() -> [(model: SyncCellModel, task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData)] {
        sections
            .flatMap { $0.allModels }
            .compactMap { model in
                guard let taskContext = emergencyFireControllerTask(for: model) else {
                    return nil
                }
                return (model: model, task: taskContext.task, data: taskContext.data)
            }
    }

    func clearEmergencyFireControllerPendingIfNeeded(for model: SyncCellModel) {
        guard let taskContext = emergencyFireControllerTask(for: model) else { return }
        taskContext.data.clearPending(for: taskContext.task, meshUUID: taskContext.data.meshUUID, subnetworkId: taskContext.data.meshNetworkId)
    }

    func completeEmptyEmergencyFireControllerTaskIfNeeded(for model: SyncCellModel, messageHandles: [MeshMessageHandle]) -> Bool {
        guard messageHandles.isEmpty, let taskContext = emergencyFireControllerTask(for: model) else {
            return false
        }
        guard !taskContext.task.isUnsupported else {
            model.state = .failed
            (model as? SyncDevicesModel)?.failedCount += 1
            (model as? SyncDeviceStepTaskModel)?.failedCount += 1
            updateCell(model: model)
            return true
        }
        model.state = .successful
        clearEmergencyFireControllerPendingIfNeeded(for: model)
        persistEmergencyFireDeleteCleanupProgressIfNeeded(for: model)
        updateCell(model: model)
        return true
    }

    var emergencyFireSyncContext: EmergencyFireSyncContext? {
        guard case .emergencyFire(_, _, let context) = type else {
            return nil
        }
        return context
    }

    func isEmergencyFireControllerDeleteCleanup(_ model: SyncCellModel) -> Bool {
        guard case .emergencyFire(_, _, let context) = type,
              context.isDeleteCleanup,
              let taskContext = emergencyFireControllerTask(for: model) else {
            return false
        }
        return taskContext.task.kind == .deleteCleanup
    }

    func persistEmergencyFireDeleteCleanupProgressIfNeeded(for model: SyncCellModel) {
        guard emergencyFireSyncContext?.isDeleteCleanup == true,
              let taskContext = emergencyFireControllerTask(for: model),
              taskContext.task.kind == .deleteCleanup,
              let groupAddress = taskContext.task.pendingGroupAddress,
              let groupModel = emergencyFireGroupModel(for: model),
              groupModel.deviceModels.allSatisfy(emergencyFireDeviceModelSucceeded(_:)) else {
            return
        }
        taskContext.data.markDeleteCleanupSucceeded(
            groupAddress: groupAddress,
            meshUUID: taskContext.data.meshUUID,
            subnetworkId: taskContext.data.meshNetworkId
        )
    }

    func emergencyFireGroupModel(for model: SyncCellModel) -> SyncDevicesGroupModel? {
        if let deviceModel = model as? SyncDevicesModel {
            return deviceModel.parentGroupModel
        }
        if let taskModel = model as? SyncDeviceStepTaskModel {
            return taskModel.parentStepModel?.parentDeviceModel?.parentGroupModel
        }
        return nil
    }

    func emergencyFireDeviceModelSucceeded(_ deviceModel: SyncDevicesModel) -> Bool {
        if let operationType = deviceModel.operationType,
           case .configuration(_, let type) = operationType,
           case .emergencyFireController = type {
            return deviceModel.state == .successful
        }
        let tasks = deviceModel.steps.flatMap { $0.tasks }
        return !tasks.isEmpty && tasks.allSatisfy { $0.state == .successful }
    }

    func persistEmergencyFireDeleteCleanupFailureIfNeeded() {
        guard emergencyFireSyncContext?.isDeleteCleanup == true,
              case .emergencyFire(let data, _, _) = type else {
            return
        }
        data.markDeleteCleanupInterrupted(meshUUID: data.meshUUID, subnetworkId: data.meshNetworkId)
    }

    func ackTimeout(for model: SyncCellModel) -> TimeInterval {
        SyncOperationResultPolicy.ackTimeout(isEmergencyFireDeleteCleanup: isEmergencyFireControllerDeleteCleanup(model))
    }

    func emergencyFireDeleteCleanupRetryPolicy(for model: SyncCellModel) -> SyncOperationResultPolicy.RetryPolicy? {
        guard isEmergencyFireControllerDeleteCleanup(model) else {
            return nil
        }
        return SyncOperationResultPolicy.emergencyFireDeleteCleanupRetryPolicy
    }

    func finishEmergencyFireControllerSyncIfNeeded(success: Bool) {
        guard case .emergencyFire(let data, _, let context) = type else {
            return
        }

        if context.persistsSyncResult {
            refreshEmergencyFireControllerSelfSyncPending(data)
            refreshEmergencyFireControllerSyncState(data)
        }
        let postSyncNotifications = {
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            NotificationCenter.default.postLinkedEmerFireConfigDidChange(data.toConfig())
        }
        if Thread.isMainThread {
            postSyncNotifications()
        } else {
            DispatchQueue.main.async {
                postSyncNotifications()
            }
        }
    }

    func finishEmergencyFireControllerAssociationSyncIfNeeded() {
        guard emergencyFireSyncContext == nil else {
            return
        }
        let controllers = emergencyFireControllerTaskContexts().reduce(into: [String: DeviceEmerFireData]()) { result, context in
            result[context.data.id] = context.data
        }
        guard !controllers.isEmpty else {
            return
        }
        controllers.values.forEach { data in
            refreshEmergencyFireControllerSyncState(data)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .init(deviceOthersRefreshNotificationName), object: nil)
            controllers.values.forEach {
                NotificationCenter.default.postLinkedEmerFireConfigDidChange($0.toConfig())
            }
        }
    }

    func refreshEmergencyFireControllerSelfSyncPending(_ data: DeviceEmerFireData) {
        let selfTaskContexts = emergencyFireControllerTaskContexts().filter {
            $0.data.id == data.id && isEmergencyFireControllerSelfTaskKind($0.task.kind)
        }
        guard !selfTaskContexts.isEmpty else {
            return
        }
        data.controllerSelfSyncPending = !selfTaskContexts.allSatisfy { $0.model.state == .successful }
    }

    func refreshEmergencyFireControllerSyncState(_ data: DeviceEmerFireData) {
        data.refreshEmergencyFireControllerSyncState(
            meshUUID: data.meshUUID,
            subnetworkId: data.meshNetworkId
        )
        DeviceEmerFireStore.shared.save(data)
    }

    func isEmergencyFireControllerSelfTaskKind(_ kind: EmergencyFireControllerSyncTaskKind) -> Bool {
        switch kind {
        case .publication, .workingMode, .resend, .restoreDelay, .actionConfig:
            return true
        case .lightnessSubscription, .lightLCSubscription, .associationSubscription, .associationCleanup, .deleteCleanup, .deleteConfiguration:
            return false
        }
    }

    func logEmergencyFireDeleteCleanupResultIfNeeded(
        for model: SyncCellModel,
        resultMessageHandles: [MeshMessageHandle],
        resultSuccessful: Bool,
        attempt: Int,
        maxAttempts: Int,
        willRetry: Bool
    ) {
        #if DEBUG
        guard let taskContext = emergencyFireControllerTask(for: model),
              taskContext.task.kind == .deleteCleanup else {
            return
        }
        let groupModel = emergencyFireGroupModel(for: model)
        let failedTaskCount = groupModel?.deviceModels
            .flatMap { $0.steps }
            .flatMap { $0.tasks }
            .filter { $0.state == .failed }
            .count ?? 0
        let handleLogs = resultMessageHandles.map { handle in
            let messageName = String(describing: Swift.type(of: handle.message))
            let all = formatEmergencyFireAddresses(handle.allAddresss)
            let responded = formatEmergencyFireAddresses(handle.respondAddresss)
            let missing = formatEmergencyFireAddresses(handle.notRespondAddresss)
            return "\(messageName){success=\(handle.isSuccessful),all=[\(all)],respond=[\(responded)],missing=[\(missing)]}"
        }.joined(separator: ";")
        print("[EFC Delete Cleanup] task=\(taskContext.task.kind.rawValue), group=\(formatEmergencyFireAddress(taskContext.task.pendingGroupAddress)), node=\(formatEmergencyFireAddress(taskContext.task.address)), attempt=\(attempt)/\(maxAttempts), willRetry=\(willRetry), resultSuccessful=\(resultSuccessful), state=\(model.state), failedTasksInGroup=\(failedTaskCount), handles=\(handleLogs)")
        #endif
    }

    func formatEmergencyFireAddress(_ address: Address?) -> String {
        guard let address else {
            return "nil"
        }
        return String(format: "0x%04X", address)
    }

    func formatEmergencyFireAddresses(_ addresses: [Address]) -> String {
        addresses.map { formatEmergencyFireAddress($0) }.joined(separator: ",")
    }

}
