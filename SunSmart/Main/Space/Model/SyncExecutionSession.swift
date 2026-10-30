import Foundation
import NordicSigMeshSDK

/// 应用层任务状态仅在主线程访问。发送、授权和等待均以回调推进，不阻塞主线程。
final class SyncExecutionSession {
    typealias SyncType = SyncDevicesViewController.SyncType
    typealias SyncState = SyncDevicesViewController.SyncState
    typealias EmergencyFireSyncContext = SyncDevicesViewController.EmergencyFireSyncContext
    var type: SyncType
    let coordinator: SyncSessionCoordinator
    let environment: SyncExecutionEnvironment
    var sections: [SyncDevicesSectionModel] = []
    /// Draft sends use this same lane/cancel/retry lifecycle, but never update formal configuration.
    var parameterOnlyOperations: [ObjectIdentifier: () -> [MeshMessageHandle]] = [:]
    var syncState: SyncState
    var profileSensorProtectionContext: ProfileSensorProtectionContext?
    var proximityLightingTaskModels: [SyncDeviceStepTaskModel] = []
    var luxTriggerLockDevices: [Node] = []
    var deviceBlinkMode: DeviceBlinkMode = .none
    var automationRestore = false
    var retryCount = 2
    var batteryPowerSwitchOwnConfigurationFailed = false
    var batteryPowerSwitchKeyConfigurationCompleted = false
    var batteryPowerSwitchKeyConfigEarliestDate: Date?
    var daylightConditionRecallRecoveryKeys: Set<String> = []
    private(set) var currentTask: SyncCellModel?
    private var cancelAuthorization: (() -> Void)?
    private var pendingPreparations: [() -> Void] = []
    private var restoreOperation: DeviceOperationType?
    // Keep failed saves as well as the active task until stop/close has settled.
    private var hdbZoneCachePersistenceFailed = false
    var pendingHDBZoneCacheTasks: [ObjectIdentifier: HDBDeviceSyncTask] = [:]
    private var hdbZoneAcknowledgementAttempt: UUID?

    var onPlanInvalidated: (() -> Void)?
    private var invalidatingPlan = false
    var onRunBegan: ((UUID) -> Void)?
    var onTaskStarted: ((SyncCellModel, UUID) -> Void)?
    var onProgress: (() -> Void)?
    var onReload: (() -> Void)?
    var onCompleted: ((SyncState) -> Void)?
    var onSettled: ((SyncState) -> Void)?
    /// Embedded device-add sessions persist normally; their owner submits the complete batch.
    var publishesCloudChange = true
    var onStopped: (() -> Void)?
    var onError: ((String) -> Void)?
    var onBatteryActivationRequired: (() -> Void)?
    var onRetryExhausted: (() -> Void)?
    var identifier: UUID { coordinator.identifier }

    init(type: SyncType, reSync: Bool, environment: SyncExecutionEnvironment = SyncExecutionEnvironment(),
         lane: SyncSessionTransportLane = .shared) {
        self.type = type
        self.syncState = reSync ? .syncFailure : .inSync
        self.environment = environment
        coordinator = SyncSessionCoordinator(lane: lane)
    }

    func enqueuePreparation(_ action: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        guard !coordinator.closed else { return }
        pendingPreparations.append(action)
    }

    #if DEBUG
    private func traceSceneSync(_ stage: String, detail: String = "") {
        guard case .scene(let scene) = type else { return }
        print("[SceneSync] run=\(identifier) scene=\(scene.number) stage=\(stage) \(detail)")
    }
    #endif

    func start() {
        precondition(Thread.isMainThread)
        #if DEBUG
        traceSceneSync("startRequested", detail: "sections=\(sections.count)")
        #endif
        let preparations = pendingPreparations
        pendingPreparations.removeAll()
        coordinator.start { [self] identifier in
            guard validatePlan(identifier) else { return }
            guard environment.configurationAvailable() else {
                #if DEBUG
                traceSceneSync("startRejected", detail: "reason=configurationUnavailable")
                #endif
                syncState = .syncFailure
                onError?("configuration_sync_unavailable".localizedString)
                finishRun(identifier, publishesCompletion: false, forcedState: .syncFailure)
                return
            }
            preparations.forEach { $0() }
            syncState = .inSync
            hdbZoneCachePersistenceFailed = false
            batteryPowerSwitchOwnConfigurationFailed = false
            batteryPowerSwitchKeyConfigurationCompleted = false
            daylightConditionRecallRecoveryKeys.removeAll()
            batteryPowerSwitchKeyConfigEarliestDate = batteryPowerSwitchDataForSync?.requiresActivationBeforeOwnConfiguration == true
                ? Date().addingTimeInterval(1) : nil
            sections.forEach { section in
                section.allModels.forEach {
                    if $0.state == .none { $0.state = .wait }
                    $0.isFineshed = false
                    ($0 as? SyncDevicesGroupModel)?.isSelected = false
                    ($0 as? SyncDevicesModel)?.isSelected = false
                }
            }
            onRunBegan?(identifier)
            onReload?()
            advance(identifier)
        }
    }

    func isActiveSyncRun(_ identifier: UUID) -> Bool { coordinator.lifecycle.isActive(identifier) }

    private func advance(_ identifier: UUID) {
        environment.delay(0) { [self] in
            guard isActiveSyncRun(identifier) else { return }
            processNext(identifier)
        }
    }

    private func processNext(_ identifier: UUID) {
        precondition(Thread.isMainThread)
        guard isActiveSyncRun(identifier) else { return }
        guard validatePlan(identifier) else { return }
        guard let model = getNextHandleModel() else {
            #if DEBUG
            traceSceneSync("noNextTask")
            #endif
            currentTask = nil
            finishRun(identifier)
            return
        }
        currentTask = model
        #if DEBUG
        let device = (model as? SyncDevicesModel) ?? (model as? SyncDeviceStepTaskModel)?.parentStepModel?.parentDeviceModel
        traceSceneSync("taskSelected", detail: "address=\(device?.address ?? 0) state=\(model.state)")
        #endif
        guard environment.configurationAvailable() else {
            #if DEBUG
            traceSceneSync("taskRejected", detail: "reason=configurationUnavailable")
            #endif
            model.state = .failed
            finishRun(identifier, publishesCompletion: false, forcedState: .syncFailure)
            return
        }
        if let recoveryNode = gatewayRecoveryNode, !recoveryNode.state {
            markPendingGatewayRecoveryTasksSkipped()
            finishRun(identifier)
            return
        }
        guard environment.bluetoothAvailable() else {
            #if DEBUG
            traceSceneSync("taskRejected", detail: "reason=bluetoothUnavailable")
            #endif
            if gatewayRecoveryNode != nil { markPendingGatewayRecoveryTasksSkipped() }
            else { sections.flatMap { $0.allModels }.forEach { $0.state = .failed } }
            finishRun(identifier, publishesCompletion: false, forcedState: .syncFailure)
            return
        }
        if case .configuration(let node, .scene(let number, _)) = operationType(for: model) {
            if !SceneCapacity.unknownNodes([node]).isEmpty {
                #if DEBUG
                traceSceneSync("registerRead", detail: "address=\(node.primaryUnicastAddress)")
                #endif
                SceneCapacity.readUnknownState(nodes: [node]) { [self] resolved in
                    guard isActiveSyncRun(identifier), validatePlan(identifier) else { return }
                    #if DEBUG
                    traceSceneSync("registerReadResult", detail: "address=\(node.primaryUnicastAddress) resolved=\(resolved)")
                    #endif
                    if !resolved { finishOperation(model, successful: false) }
                    advance(identifier)
                }
                return
            }
            do { try SceneCapacity.validateStore(node: node, number: number) }
            catch {
                #if DEBUG
                traceSceneSync("taskRejected", detail: "reason=capacityValidation errorType=\(Swift.type(of: error))")
                #endif
                SceneCapacity.showFailure(error)
                finishOperation(model, successful: false)
                advance(identifier)
                return
            }
        }
        var handles = parameterOnlyOperations[ObjectIdentifier(model)]?() ?? operationType(for: model)?.messageHandles ?? []
        handles = prepareDaylightHandles(for: model, handles: handles)
        handles = batteryPowerSwitchMessageHandles(for: model, defaultHandles: handles)
        #if DEBUG
        traceSceneSync("commandsBuilt", detail: "count=\(handles.count)")
        #endif
        if case .configuration(_, .hdbUnavailable) = operationType(for: model) {
            finishOperation(model, successful: false)
            advance(identifier)
            return
        }
        if case .configuration(_, .hdb) = operationType(for: model), handles.isEmpty {
            finishOperation(model, successful: false)
            advance(identifier)
            return
        }
        if handles.isEmpty {
            switch operationType(for: model) {
            case .configuration(_, .scene), .delete(_, .scene):
                #if DEBUG
                traceSceneSync("taskRejected", detail: "reason=emptySceneHandles")
                #endif
                finishOperation(model, successful: false); advance(identifier); return
            default: break
            }
        }
        if parameterOnlyOperations[ObjectIdentifier(model)] != nil, handles.isEmpty {
            finishOperation(model, successful: false); advance(identifier); return
        }
        model.state = .inSettings
        onTaskStarted?(model, identifier)
        if completeGatewayServerAuthorizationTaskIfNeeded(for: model, syncRunIdentifier: identifier) { return }
        _ = completeProfileSensorProtectionTaskIfNeeded(for: model)
        if completeEmptyEmergencyFireControllerTaskIfNeeded(for: model, messageHandles: handles) {
            advance(identifier)
            return
        }
        if isMissingRequiredTimeSynchronizationHandle(model, messageHandles: handles)
            || (batteryPowerSwitchOwnConfigurationFailed && isBatteryPowerSwitchOwnConfiguration(model)) {
            finishOperation(model, successful: false)
            advance(identifier)
            return
        }
        if isMissingRequiredBatteryPowerSwitchConfigurationHandles(model, messageHandles: handles) {
            finishOperation(model, successful: false)
            batteryPowerSwitchOwnConfigurationFailed = true
            markBatteryPowerSwitchOwnConfigurationTasksFailed()
            advance(identifier)
            return
        }
        let wait = isBatteryPowerSwitchKeyConfigConfiguration(model)
            ? max(0, batteryPowerSwitchKeyConfigEarliestDate?.timeIntervalSinceNow ?? 0) : 0
        environment.delay(wait) { [self] in
            guard isActiveSyncRun(identifier) else { return }
            if isBatteryPowerSwitchKeyConfigConfiguration(model) { batteryPowerSwitchKeyConfigEarliestDate = nil }
            send(model, handles: handles, identifier: identifier, attempt: 1)
        }
    }

    private func send(_ model: SyncCellModel, handles: [MeshMessageHandle], identifier: UUID, attempt: Int) {
        guard isActiveSyncRun(identifier) else { return }
        guard validatePlan(identifier, handles: handles) else { return }
        #if DEBUG
        traceSceneSync("sendPrepared", detail: "count=\(handles.count) hasStore=\(handles.contains { $0.message is SceneStore }) attempt=\(attempt)")
        #endif
        // A failed parameter batch must never enqueue Store against the lamp's old state.
        if let storeIndex = handles.firstIndex(where: { $0.message is SceneStore }), storeIndex > 0 {
            let parameters = Array(handles[..<storeIndex])
            let gate = SyncAttemptCompletionGate()
            #if DEBUG
            traceSceneSync("submitParameters", detail: "count=\(parameters.count)")
            #endif
            environment.addMessage(messageHandles: parameters, ackMessageTimeout: ackTimeout(for: model),
                successfulBack: { [self] handle, status in
                    guard isActiveSyncRun(identifier), !gate.isCompleted, validatePlan(identifier, handles: handles) else { return }
                    received(handle: handle, statusMessage: status, model: model, messageHandles: handles)
                }, finishedBack: { [self] result in
                    guard isActiveSyncRun(identifier), gate.claim(), validatePlan(identifier, handles: handles) else { return }
                    #if DEBUG
                    traceSceneSync("parameterResult", detail: "expected=\(parameters.count) returned=\(result.count) successful=\(result.filter { $0.isSuccessful }.count)")
                    #endif
                    guard result.count == parameters.count, result.allSatisfy({ $0.isSuccessful }) else {
                        finishOperation(model, successful: false); advance(identifier); return
                    }
                    send(model, handles: Array(handles[storeIndex...]), identifier: identifier, attempt: attempt)
                })
            return
        }
        let completionGate = SyncAttemptCompletionGate()
        let acknowledgementAttempt = UUID()
        if case .configuration(_, .hdb(let task)) = operationType(for: model), task.isLightingZoneOperation {
            hdbZoneAcknowledgementAttempt = acknowledgementAttempt
        }
        #if DEBUG
        traceSceneSync("submitCommands", detail: "count=\(handles.count) hasStore=\(handles.contains { $0.message is SceneStore })")
        #endif
        environment.addMessage(messageHandles: handles, ackMessageTimeout: ackTimeout(for: model), successfulBack: { [self] handle, status in
            guard !completionGate.isCompleted else { return }
            if isActiveSyncRun(identifier), validatePlan(identifier, handles: handles) {
                received(handle: handle, statusMessage: status, model: model, messageHandles: handles)
            } else if coordinator.isSettling, hdbZoneAcknowledgementAttempt == acknowledgementAttempt {
                received(handle: handle, statusMessage: status, model: model, messageHandles: handles, cacheOnly: true)
            }
        }, failedBack: { [self] handle in
            guard isActiveSyncRun(identifier), !completionGate.isCompleted, validatePlan(identifier, handles: handles) else { return }
            failed(handle: handle)
        }) { [self] resultMessageHandles in
            precondition(Thread.isMainThread)
            guard isActiveSyncRun(identifier), completionGate.claim(), validatePlan(identifier, handles: handles) else { return }
            if hdbZoneAcknowledgementAttempt == acknowledgementAttempt { hdbZoneAcknowledgementAttempt = nil }
            let successful = applyResult(resultMessageHandles, model: model, messageHandles: handles)
            #if DEBUG
            traceSceneSync("batchResult", detail: "returned=\(resultMessageHandles.count) acknowledged=\(resultMessageHandles.filter { $0.isSuccessful }.count) applied=\(successful)")
            #endif
            let retry = emergencyFireDeleteCleanupRetryPolicy(for: model)
            let maxAttempts = retry?.maxAttempts ?? 1
            let shouldRetry = !successful && attempt < maxAttempts && retry != nil
            logEmergencyFireDeleteCleanupResultIfNeeded(for: model, resultMessageHandles: resultMessageHandles,
                resultSuccessful: resultMessageHandles.allSatisfy { $0.isSuccessful }, attempt: attempt,
                maxAttempts: maxAttempts, willRetry: shouldRetry)
            if shouldRetry, let retry {
                resetMessageHandlesForResync(handles)
                environment.delay(retry.retryDelay) { [self] in
                    guard isActiveSyncRun(identifier) else { return }
                    send(model, handles: handles, identifier: identifier, attempt: attempt + 1)
                }
                return
            }
            finishOperation(model, successful: successful)
            let delay: TimeInterval = successful && isBatteryPowerSwitchKeyConfigConfiguration(model)
                && batteryPowerSwitchDataForSync?.requiresActivationBeforeOwnConfiguration == true ? 0.5 : 0
            environment.delay(delay) { [self] in
                guard isActiveSyncRun(identifier) else { return }
                advance(identifier)
            }
        }
    }

    private func validatePlan(_ identifier: UUID, handles: [MeshMessageHandle] = []) -> Bool {
        guard !invalidatingPlan else { return false }
        let sceneContextsAreCurrent = handles.allSatisfy { handle in
            guard let context = handle.sceneContext else { return true }
            guard let node = MeshNetworkManager.instance.realNodes.first(where: { $0.sceneConfigurationIdentity == context.identity }) else { return false }
            return context.matches(node: node)
        }
        guard !environment.configurationIsCurrent() || !sceneContextsAreCurrent else { return true }
        #if DEBUG
        traceSceneSync("planInvalidated", detail: "sceneContextsCurrent=\(sceneContextsAreCurrent)")
        #endif
        invalidatingPlan = true
        pendingPreparations.removeAll()
        cancelAuthorization?()
        cancelAuthorization = nil
        // Old desired Profile values must not be replayed as compensation.
        restoreOperation = nil
        coordinator.finish(identifier, settle: { [self] done in
            environment.stop { [self] in
                hdbZoneAcknowledgementAttempt = nil
                restoreSensorsAndUnlock(done, currentTargets: true)
            }
        }) { [self] in
            profileSensorProtectionContext = nil
            currentTask = nil
            syncState = .syncFailure
            invalidatingPlan = false
            onPlanInvalidated?()
        }
        return false
    }

    private func completeGatewayServerAuthorizationTaskIfNeeded(for model: SyncCellModel, syncRunIdentifier: UUID) -> Bool {
        guard let taskModel = model as? SyncDeviceStepTaskModel,
              case .configuration(let node, let action) = taskModel.operationType,
              case .gatewayServerAuthorization(let gateway) = action else { return false }
        let gate = SyncAttemptCompletionGate()
        cancelAuthorization = environment.authorize(gateway, node) { [self] error in
            precondition(Thread.isMainThread)
            guard isActiveSyncRun(syncRunIdentifier), gate.claim() else { return }
            cancelAuthorization = nil
            taskModel.failureMessage = error
            taskModel.state = error == nil ? .successful : .failed
            if error != nil { taskModel.failedCount += 1 }
            updateCell(model: taskModel)
            advance(syncRunIdentifier)
        }
        return true
    }

    func stop() {
        precondition(Thread.isMainThread)
        captureRestoreOperation()
        cancelAuthorization?()
        cancelAuthorization = nil
        pendingPreparations.removeAll()
        coordinator.stop { [self] finished in stopAndCompensate(finished) }
        markStopped()
    }

    func close() {
        precondition(Thread.isMainThread)
        guard !coordinator.closed else { return }
        captureRestoreOperation()
        cancelAuthorization?()
        cancelAuthorization = nil
        pendingPreparations.removeAll()
        coordinator.close(didClose: { [self] in onStopped?() }, idleCleanup: { [self] finished in compensate(finished) }) { [self] finished in stopAndCompensate(finished) }
        currentTask = nil
    }

    private func captureRestoreOperation() {
        guard restoreOperation == nil, let task = currentTask as? SyncDeviceStepTaskModel,
              let step = task.parentStepModel else { return }
        restoreOperation = step.tasks.first {
            guard $0.state == .wait, case .configuration(_, let action) = $0.operationType,
                  case .profile(let profile) = action, case .lightControlRestore = profile else { return false }
            return true
        }?.operationType
    }

    private func stopAndCompensate(_ finished: @escaping () -> Void) {
        let gate = SyncAttemptCompletionGate()
        environment.delay(0) { [self] in
            environment.stop { [self] in
                guard gate.claim() else { return }
                hdbZoneAcknowledgementAttempt = nil
                compensate { [self] in finished(); if !coordinator.closed { onStopped?() } }
            }
        }
    }

    private func compensate(_ finished: @escaping () -> Void) {
        precondition(Thread.isMainThread)
        if !environment.configurationIsCurrent() {
            restoreOperation = nil
            restoreSensorsAndUnlock(finished, currentTargets: true)
            return
        }
        if let operation = restoreOperation {
            restoreOperation = nil
            let gate = SyncAttemptCompletionGate()
            environment.delay(0.5) { [self] in
                environment.addMessage(messageHandles: operation.messageHandles) { [self] _ in
                    guard gate.claim() else { return }
                    restoreSensorsAndUnlock(finished)
                }
            }
        } else {
            restoreSensorsAndUnlock(finished)
        }
    }

    private func restoreSensorsAndUnlock(_ finished: @escaping () -> Void, currentTargets: Bool = false) {
        for task in pendingHDBZoneCacheTasks.values {
            if !task.flushAcknowledgedZoneCache() {
                hdbZoneCachePersistenceFailed = true
                syncState = .syncFailure
            }
        }
        pendingHDBZoneCacheTasks.removeAll()
        let handles = (currentTargets ? profileSensorProtectionContext?.remainingCurrentTargetStateMessageHandles()
            : profileSensorProtectionContext?.remainingTargetStateMessageHandles()) ?? []
        let gate = SyncAttemptCompletionGate()
        environment.addMessage(messageHandles: handles, ackMessageTimeout: 7) { [self] result in
            guard gate.claim() else { return }
            result.forEach { handle in
                if let address = handle.address ?? handle.model?.parentElement?.unicastAddress,
                   let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address) {
                    node.applyMessageHandle(handle, isSuccess: handle.isSuccessful)
                    node.clearSyncStateCache()
                }
            }
            unlockLuxTriggers(allowBroadcast: !currentTargets)
            currentTask = nil
            finished()
        }
    }

    private func unlockLuxTriggers(allowBroadcast: Bool = true) {
        let current = MeshNetworkManager.instance.meshNetwork?.nodes ?? []
        luxTriggerLockDevices = luxTriggerLockDevices.filter { node in current.contains { $0 === node } }
        guard !luxTriggerLockDevices.isEmpty else { return }
        let message = SunricherVendorSet(function: .daylightLuxTriggerLock(delay: 0))
        if allowBroadcast && luxTriggerLockDevices.count > 3 { MeshAPI.sendMessage(message: message, address: .allNodes) }
        else { luxTriggerLockDevices.forEach { if let model = $0.sunricherVendorModel { MeshAPI.sendMessage(message: message, model: model) } } }
        luxTriggerLockDevices.removeAll()
    }

    private func markStopped() {
        sections.flatMap { $0.allModels }.forEach {
            if $0.state == .none || $0.state == .wait || $0.state == .inSettings {
                $0.state = .failed
                ($0 as? SyncDevicesModel)?.failedCount += 1
                ($0 as? SyncDeviceStepTaskModel)?.failedCount += 1
            }
        }
        if batteryPowerSwitchDataForSync != nil {
            batteryPowerSwitchOwnConfigurationFailed = true
            markBatteryPowerSwitchOwnConfigurationTasksFailed()
        }
        syncState = .syncFailure
        persistEmergencyFireDeleteCleanupFailureIfNeeded()
        finishEmergencyFireControllerSyncIfNeeded(success: false)
        finishEmergencyFireControllerAssociationSyncIfNeeded()
        onReload?()
    }

    private func finishRun(_ identifier: UUID, publishesCompletion: Bool = true, forcedState: SyncState? = nil) {
        coordinator.finish(identifier, settle: { [self] done in compensate(done) }) { [self] in
            for model in sections.flatMap({ $0.allModels }) {
                if case .configuration(_, .hdb(let task)) = operationType(for: model), model.state == .successful,
                   !task.finishCleanup() { model.state = .failed }
            }
            markPendingGatewayRecoveryTasksSkipped()
            sections.flatMap { $0.allModels }.forEach { $0.isFineshed = true }
            syncState = hdbZoneCachePersistenceFailed ? .syncFailure : forcedState ?? (sections.contains { $0.allModels.contains { $0.state == .failed } } ? .syncFailure : .syncSuccess)
            // Missing identities cannot produce executable models. Their durable
            // scene intent must still prevent a false zero-task success.
            if syncState == .syncSuccess, case .scene(let scene) = type, scene.needSync {
                #if DEBUG
                traceSceneSync("completionRejected", detail: "reason=sceneStillPending")
                #endif
                syncState = .syncFailure
            }
            #if DEBUG
            traceSceneSync("finished", detail: "state=\(syncState) forced=\(String(describing: forcedState)) failedModels=\(sections.flatMap { $0.allModels }.filter { $0.state == .failed }.count)")
            #endif
            if syncState == .syncFailure { persistEmergencyFireDeleteCleanupFailureIfNeeded() }
            finishEmergencyFireControllerSyncIfNeeded(success: syncState == .syncSuccess)
            finishEmergencyFireControllerAssociationSyncIfNeeded()
            onReload?()
            onSettled?(syncState)
            guard publishesCompletion else { return }
            if publishesCloudChange {
                NotificationCenter.default.post(name: .init(spaceDataChangedNotificaitonName), object: SpaceChangeDataType.device)
            }
            onCompleted?(syncState)
            if syncState == .syncFailure, automationRestore, !coordinator.closed {
                if retryCount > 0 {
                    retryCount -= 1
                    let failed = sections.flatMap { $0.allModels }.compactMap { $0 as? SyncDevicesModel }.filter { $0.state == .failed }
                    if failed.contains(where: { containsBatteryPowerSwitchConfiguration($0) }) {
                        onBatteryActivationRequired?()
                    } else {
                        enqueuePreparation { [self] in failed.forEach { prepareDeviceForResync($0) } }
                        start()
                    }
                } else { onRetryExhausted?() }
            }
        }
    }

    func updateCell(model: SyncCellModel) { onProgress?() }
}
