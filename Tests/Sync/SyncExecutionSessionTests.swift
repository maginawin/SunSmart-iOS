import Foundation

private final class Harness {
    struct Send { let handles: [MeshMessageHandle]; let success: ((MeshMessageHandle, Int) -> Void)?; let finish: (([MeshMessageHandle]) -> Void)? }
    let environment = SyncExecutionEnvironment()
    let lane = SyncSessionTransportLane()
    var queued: [() -> Void] = []
    var delays: [TimeInterval] = []
    var sends: [Send] = []
    var stopFinished: (() -> Void)?
    var stopCount = 0
    var authorization: ((String?) -> Void)?
    var cancelledAuthorizations = 0
    var sceneUnknown = true
    var sceneReads: [(nodes: [Node], completion: (Bool) -> Void)] = []
    var sceneValidations: [(node: Node, number: UInt16)] = []
    var sceneValidationError: Error?
    var sceneFailures = 0
    init() {
        SceneCapacity.unknownNodesHandler = { [unowned self] in sceneUnknown ? $0 : [] }
        SceneCapacity.readHandler = { [unowned self] in sceneReads.append(($0, $1)) }
        SceneCapacity.validateHandler = { [unowned self] node, number in
            sceneValidations.append((node, number))
            if let error = sceneValidationError { throw error }
        }
        SceneCapacity.failureHandler = { [unowned self] _ in sceneFailures += 1 }
        environment.delay = { [unowned self] delay, action in delays.append(delay); queued.append(action) }
        environment.send = { [unowned self] handles, _, success, _, finished in
            if handles.isEmpty { queued.append { finished?([]) } }
            else { sends.append(Send(handles: handles, success: success, finish: finished)) }
        }
        environment.stop = { [unowned self] finished in stopCount += 1; stopFinished = finished }
        environment.authorize = { [unowned self] _, _, finished in
            authorization = finished
            return { [weak self] in self?.cancelledAuthorizations += 1 }
        }
    }
    func flush() {
        var count = 0
        while !queued.isEmpty {
            count += 1; precondition(count < 100, "must wait for an external callback")
            queued.removeFirst()()
        }
    }
    func make(_ action: ActionType = .pirEnabled(true)) -> (SyncExecutionSession, SyncDevicesModel, SyncDeviceStepTaskModel, Node) {
        let node = Node(); node.testHandles = [MeshMessageHandle()]
        let network = MeshNetwork(); network.nodes = [node]; MeshNetworkManager.instance.meshNetwork = network
        let task = SyncDeviceStepTaskModel(name: "task", operationType: .configuration(node: node, type: action))
        let step = SyncDeviceStepModel(type: "step", state: .none, tasks: [task])
        let device = SyncDevicesModel(name: "device", address: 1)
        device.steps = [step]; step.parentDeviceModel = device; task.parentStepModel = step
        let section = SyncDevicesSectionModel(title: "configuration"); section.devices = [device]
        let session = SyncExecutionSession(type: .devices([node]), reSync: false, environment: environment, lane: lane)
        session.sections = [section]
        return (session, device, task, node)
    }
    func finish(_ index: Int, success: Bool = true) {
        sends[index].handles.forEach { $0.isSuccessful = success }
        sends[index].finish?(sends[index].handles)
    }
}

@main
enum SyncExecutionSessionTests {
    static func main() {
        DeviceOperationType.allowsMessageFactory = true
        sceneReadSuccess()
        sceneReadFailureAndRetry()
        sceneStoreValidationFailure()
        sceneReadAfterCancellation()
        sceneReadFromPreviousRun()
        print("PASS: production Session scene capacity read success/failure, validation, retry and late callback isolation")
        changedConfigurationInvalidatesOldCallbacks()
        changedConfigurationBeforeStart()
        unavailableConfigurationNeedsReviewWithoutSending()
        hdbCleanupSettlesAfterLastTask()
        hdbCannotPassWithoutHandles()
        hdbCacheSettlesOnEveryExit()
        hdbInFlightAcknowledgementDuringStop()
        closeWaitingSessionSettlesCaller()
        callerOwnsCloudCompletion()
        normalAndDuplicateCompletion()
        stopBeforePlanDeliveryAndManualRetry()
        stopBeforeRetryAndLateCompletion()
        profileCompensationBeforeRetry()
        authorizationCancellation()
        authorizationBeforeDynamicMessages()
        automaticRetryBudget()
        print("PASS: production Session scheduling, writeback ordering, late completion, stop/retry, Profile/PIR compensation and authorization cancellation")
    }
    static func sceneReadSuccess() {
        let h = Harness()
        let (session, _, task, node) = h.make(.scene(sceneId: 42, executeData: nil))
        var completed = 0
        session.onCompleted = { _ in completed += 1 }
        session.start(); h.flush()
        precondition(h.sceneReads.count == 1 && h.sceneReads[0].nodes.count == 1 && h.sceneReads[0].nodes[0] === node)
        precondition(h.sends.isEmpty && h.sceneValidations.isEmpty && task.state == .wait && completed == 0,
                     "unknown capacity must wait for its read before validating or storing")
        h.sceneUnknown = false
        h.sceneReads[0].completion(true); h.flush()
        precondition(h.sceneReads.count == 1 && h.sceneValidations.count == 1)
        precondition(h.sceneValidations[0].node === node && h.sceneValidations[0].number == 42)
        precondition(h.sends.count == 1 && task.state == .inSettings && node.updates == 0 && completed == 0,
                     "read success must validate the same target and scene; Store still needs its own completion")
        h.finish(0); h.flush()
        precondition(task.state == .successful && node.updates == 1 && completed == 1 && session.syncState == .syncSuccess)
        session.close(); h.flush()
    }
    static func sceneReadFailureAndRetry() {
        let h = Harness()
        let (session, device, task, node) = h.make(.scene(sceneId: 42, executeData: nil))
        var states: [SyncDevicesViewController.SyncState] = []
        session.onCompleted = { states.append($0) }
        session.start(); h.flush()
        h.sceneReads[0].completion(false); h.flush()
        precondition(task.state == .failed && task.failedCount == 1 && session.syncState == .syncFailure)
        precondition(h.sends.isEmpty && h.sceneValidations.isEmpty && node.updates == 0 && states == [.syncFailure],
                     "read failure must settle as failure without sending Store or writing back")
        session.prepareDeviceForResync(device)
        session.start(); h.flush()
        precondition(h.sceneReads.count == 2 && h.sends.isEmpty, "manual retry must read unknown capacity again")
        h.sceneUnknown = false
        h.sceneReads[1].completion(true); h.flush()
        precondition(h.sends.count == 1)
        h.finish(0); h.flush()
        precondition(task.state == .successful && states == [.syncFailure, .syncSuccess])
        session.close(); h.flush()
    }
    static func sceneStoreValidationFailure() {
        enum Full: Error { case capacity }
        let h = Harness()
        let (session, _, task, node) = h.make(.scene(sceneId: 42, executeData: nil))
        session.start(); h.flush()
        h.sceneUnknown = false
        h.sceneValidationError = Full.capacity
        h.sceneReads[0].completion(true); h.flush()
        precondition(h.sceneValidations.count == 1 && h.sceneFailures == 1 && h.sends.isEmpty && node.updates == 0,
                     "successful read does not permit Store when capacity validation rejects it")
        precondition(task.state == .failed && session.syncState == .syncFailure)
        session.close(); h.flush()
    }
    static func sceneReadAfterCancellation() {
        for close in [false, true] {
            for resolved in [false, true] {
                let h = Harness()
                let (session, _, task, node) = h.make(.scene(sceneId: 42, executeData: nil))
                var completed = 0, progress = 0
                session.onCompleted = { _ in completed += 1 }
                session.onProgress = { progress += 1 }
                session.start(); h.flush()
                let read = h.sceneReads[0].completion
                if close { session.close() } else { session.stop() }
                h.flush()
                let state = task.state, failures = task.failedCount, previousProgress = progress
                // Deliver both while STOP is settling and after transport release.
                h.sceneUnknown = !resolved
                read(resolved); h.flush()
                h.stopFinished?(); h.flush()
                read(resolved); h.flush()
                precondition(h.sends.isEmpty && h.sceneValidations.isEmpty && node.updates == 0 && completed == 0)
                precondition(task.state == state && task.failedCount == failures && progress == previousProgress,
                             "late read success/failure cannot mutate a cancelled task or publish completion")
                session.close(); h.flush()
            }
        }
    }
    static func sceneReadFromPreviousRun() {
        for resolved in [false, true] {
            let h = Harness()
            let (session, device, task, node) = h.make(.scene(sceneId: 42, executeData: nil))
            var completed = 0
            session.onCompleted = { _ in completed += 1 }
            session.start(); h.flush()
            let oldRead = h.sceneReads[0].completion
            session.stop(); h.flush()
            h.stopFinished?(); h.flush()
            session.prepareDeviceForResync(device)
            session.start(); h.flush()
            precondition(h.sceneReads.count == 2)
            let failures = task.failedCount
            oldRead(resolved); h.flush()
            precondition(task.state == .wait && task.failedCount == failures && h.sceneReads.count == 2)
            precondition(h.sends.isEmpty && h.sceneValidations.isEmpty && node.updates == 0 && completed == 0,
                         "previous generation's read must not advance or fail the new run")
            h.sceneUnknown = false
            h.sceneReads[1].completion(true); h.flush()
            precondition(h.sends.count == 1)
            h.finish(0); h.flush()
            precondition(task.state == .successful && completed == 1)
            session.close(); h.flush()
        }
    }
    static func callerOwnsCloudCompletion() {
        for publishes in [false, true] {
            let h = Harness()
            let (session, _, _, _) = h.make()
            session.publishesCloudChange = publishes
            var notifications = 0, settled = 0, completed = 0
            let observer = NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: nil) { _ in notifications += 1 }
            session.onSettled = { _ in settled += 1 }
            session.onCompleted = { _ in completed += 1 }
            session.start(); h.flush(); h.finish(0); h.flush()
            precondition(settled == 1 && completed == 1)
            precondition(notifications == (publishes ? 1 : 0))
            NotificationCenter.default.removeObserver(observer)
        }
    }
    static func hdbCacheSettlesOnEveryExit() {
        for exit in 0..<3 {
            let h = Harness(), payload = HDBDeviceSyncTask()
            payload.isLightingZoneOperation = true
            let (session, _, _, _) = h.make(.hdb(payload))
            session.start(); h.flush()
            let send = h.sends[0]
            send.success?(send.handles[0], 0)
            precondition(payload.hasPendingZoneCacheSave && session.pendingHDBZoneCacheTasks.count == 1)
            // An earlier task's failed save must not be forgotten when another task starts.
            let earlier = HDBDeviceSyncTask(); earlier.hasPendingZoneCacheSave = true
            session.pendingHDBZoneCacheTasks[ObjectIdentifier(earlier)] = earlier
            if exit == 0 { session.stop() }
            else if exit == 1 { session.close() }
            else {
                h.environment.configurationIsCurrent = { false }
                send.finish?(send.handles)
            }
            h.flush()
            precondition(payload.cacheFlushes == 0, "flush only after transport stops")
            h.stopFinished?(); h.flush()
            precondition(payload.cacheFlushes == 1 && earlier.cacheFlushes == 1)
            precondition(payload.persistCalls == 0 && !payload.hasPendingZoneCacheSave)
            send.success?(send.handles[0], 0); send.finish?(send.handles); h.flush()
            precondition(!payload.hasPendingZoneCacheSave, "late callbacks cannot dirty a stopped attempt")
            session.close(); h.flush()
        }
    }
    static func hdbInFlightAcknowledgementDuringStop() {
        for close in [false, true] {
            let h = Harness(), payload = HDBDeviceSyncTask()
            payload.isLightingZoneOperation = true
            let (session, _, _, _) = h.make(.hdb(payload))
            session.start(); h.flush()
            let send = h.sends[0]
            if close { session.close() } else { session.stop() }
            h.flush()
            precondition(!payload.hasPendingZoneCacheSave)
            send.success?(send.handles[0], 0)
            precondition(payload.hasPendingZoneCacheSave && payload.cacheOnlyAcknowledgements == 1)
            precondition(payload.persistCalls == 0)
            h.stopFinished?(); h.flush()
            precondition(payload.cacheFlushes == 1 && !payload.hasPendingZoneCacheSave)
            send.success?(send.handles[0], 0); send.finish?(send.handles); h.flush()
            precondition(!payload.hasPendingZoneCacheSave && payload.cacheOnlyAcknowledgements == 1)
            session.close(); h.flush()
        }
    }
    static func closeWaitingSessionSettlesCaller() {
        let h = Harness()
        let owner = SyncSessionCoordinator(lane: h.lane)
        owner.start { _ in }
        let (session, _, _, _) = h.make()
        var stopped = 0
        session.onStopped = { stopped += 1 }
        session.start(); h.flush(); session.close(); h.flush()
        precondition(stopped == 0 && h.sends.isEmpty)
        owner.close { $0() }; h.flush()
        precondition(stopped == 1, "cancel while waiting must return after compensation, without issuing transport STOP")
    }
    static func hdbCleanupSettlesAfterLastTask() {
        let h = Harness(), cleanup = HDBDeviceSyncTask()
        let (session, device, _, node) = h.make(.hdb(cleanup))
        let followup = SyncDeviceStepTaskModel(name: "followup", operationType: .configuration(node: node, type: .pirEnabled(true)))
        let step = SyncDeviceStepModel(type: "followup", state: .none, tasks: [followup])
        step.relevanceStepModels = device.steps
        device.steps.append(step); step.parentDeviceModel = device; followup.parentStepModel = step
        var released = false, completed = 0
        cleanup.finalize = { released = true; return true }
        h.environment.configurationIsCurrent = { !released }
        session.onCompleted = { state in precondition(state == .syncSuccess); completed += 1 }
        session.start(); h.flush(); h.finish(0); h.flush()
        precondition(!released && h.sends.count == 2, "cleanup must not invalidate the following task scope")
        h.finish(1); h.flush()
        precondition(released && cleanup.finalizations == 1 && completed == 1, "release only after the complete batch settles")
        session.close(); h.flush()
    }
    static func hdbCannotPassWithoutHandles() {
        let h = Harness(), task = HDBDeviceSyncTask()
        let (session, _, _, node) = h.make(.hdb(task))
        node.testHandles = []
        session.start(); h.flush()
        precondition(session.syncState == .syncFailure && task.persistCalls == 0)
        session.close(); h.flush()
    }
    static func changedConfigurationBeforeStart() {
        let h = Harness(); let (session, _, _, node) = h.make()
        h.environment.configurationIsCurrent = { false }
        var invalidations = 0
        session.onPlanInvalidated = { invalidations += 1 }
        session.start(); h.flush()
        precondition(h.sends.isEmpty && node.updates == 0, "Deleted device or replaced Profile must never send an old plan")
        h.stopFinished?(); h.flush()
        precondition(invalidations == 1, "Rebuild only after transport has stopped")
        session.close(); h.flush()
    }
    static func unavailableConfigurationNeedsReviewWithoutSending() {
        let h = Harness(); let (session, _, _, node) = h.make()
        var available = false
        h.environment.configurationAvailable = { available }
        var errors: [String] = []
        var prepared = false, completed = 0
        session.onError = { errors.append($0) }
        session.onCompleted = { _ in completed += 1 }
        session.enqueuePreparation { prepared = true }
        session.start(); h.flush()
        precondition(errors == ["configuration_sync_unavailable".localizedString],
                     "A general configuration barrier must not report invalid proximity lighting")
        precondition(!prepared && h.sends.isEmpty && node.updates == 0 && completed == 0,
                     "Unavailable configuration must block preparation, commands, writeback and success")
        precondition(session.syncState == .syncFailure, "The blocked run must remain failed")
        available = true
        session.start(); h.flush()
        precondition(h.sends.count == 1 && !prepared, "Recovery permits a fresh run without replaying rejected preparation")
        h.finish(0); h.flush()
        precondition(session.syncState == .syncSuccess && completed == 1 && node.updates == 1,
                     "A recovered configuration must still synchronize normally")
        session.close(); h.flush()
    }
    static func changedConfigurationInvalidatesOldCallbacks() {
        let h = Harness(); let (session, _, task, node) = h.make(.profile(type: .occupancyLevel))
        var current = true
        h.environment.configurationIsCurrent = { current }
        var invalidations = 0, completed = 0
        session.onPlanInvalidated = { invalidations += 1 }
        session.onCompleted = { _ in completed += 1 }
        session.start(); h.flush()
        current = false
        h.finish(0); h.finish(0); h.flush()
        precondition(node.updates == 0 && task.state != .successful && completed == 0,
                     "Old response must not update a new device instance or acknowledge new Profile values")
        precondition(h.stopCount == 1 && invalidations == 0, "One stopped transport owns invalidation")
        h.stopFinished?(); h.flush()
        precondition(invalidations == 1 && h.sends.count == 1, "Do not replay old Profile compensation")
        session.close(); h.flush()
    }
    static func normalAndDuplicateCompletion() {
        let h = Harness(); let (session, _, task, node) = h.make()
        var completed = 0; session.onCompleted = { _ in completed += 1 }
        session.start(); h.flush()
        precondition(h.sends.count == 1 && task.state == .inSettings, "starts one operation")
        h.finish(0); h.finish(0); h.flush()
        precondition(node.updates == 1 && task.state == .successful && completed == 1, "write back once before evaluating business success")
        session.close(); h.flush()
    }
    static func stopBeforeRetryAndLateCompletion() {
        let h = Harness(); let (session, device, task, node) = h.make()
        session.start(); h.flush()
        session.stop(); h.flush()
        precondition(h.stopCount == 1 && task.state == .failed, "STOP fails the interrupted operation")
        session.enqueuePreparation { session.prepareDeviceForResync(device) }; session.start(); h.flush()
        precondition(h.sends.count == 1, "retry must not send before stop and compensation finish")
        h.finish(0); precondition(node.updates == 0 && task.state == .failed, "late completion cannot write to stopped or new state")
        h.stopFinished?(); h.flush()
        precondition(h.sends.count == 2 && task.state == .inSettings, "queued retry begins after cleanup")
        h.finish(1); h.flush()
        precondition(node.updates == 1 && task.state == .successful, "new round owns its own completion")
        session.close(); h.flush()
    }
    static func stopBeforePlanDeliveryAndManualRetry() {
        let h = Harness(); let (session, device, task, node) = h.make()
        let output = SyncTaskPlanResult(sections: session.sections, initialState: session.syncState,
            proximityLightingTasks: [], failureMessages: [])
        session.sections = [] // The builder owns these models until main-thread delivery.
        let controller = SessionPlanInstallationHarness(session: session)
        session.stop()
        controller.installTaskPlan(output)
        h.flush()
        precondition(session.syncState == .syncFailure && h.sends.isEmpty,
                     "production STOP followed by plan delivery must not send configuration")
        precondition(device.state == .failed && task.state == .failed && task.isFineshed,
                     "late tasks must be available for manual retry after STOP")
        device.isSelected = true
        let selected = session.selectedFailedDevicesForResync()
        precondition(selected.count == 1 && selected[0] === device, "user can select the stopped device")
        selected.forEach { session.prepareDeviceForResync($0) }
        session.start(); h.flush()
        precondition(h.sends.count == 1 && task.state == .inSettings,
                     "only explicit retry starts the installed task")
        h.finish(0); h.flush()
        precondition(node.updates == 1 && task.state == .successful && session.syncState == .syncSuccess,
                     "manual retry after late installation can finish successfully")
        session.close(); h.flush()
    }
    static func profileCompensationBeforeRetry() {
        let h = Harness(); let (session, device, task, node) = h.make()
        let restore = SyncDeviceStepTaskModel(name: "restore", operationType: .configuration(node: node, type: .profile(type: .lightControlRestore)))
        task.parentStepModel!.tasks.append(restore); restore.parentStepModel = task.parentStepModel
        let sensor = ProfileSensorProtectionContext(); let sensorHandle = MeshMessageHandle(); sensorHandle.message = 9
        sensor.handles = [sensorHandle]; session.profileSensorProtectionContext = sensor
        session.start(); h.flush(); session.stop(); h.flush()
        session.enqueuePreparation { session.prepareDeviceForResync(device) }; session.start()
        h.stopFinished?(); h.flush()
        precondition(h.sends.count == 2 && h.delays.contains(0.5), "STOP restores the current task's Profile after the original delay")
        h.finish(1); h.flush()
        precondition(h.sends.count == 3 && h.sends[2].handles[0].message == 9, "PIR target follows Profile restore")
        h.finish(2); h.flush()
        precondition(h.sends.count == 4, "retry waits until both compensation stages complete")
        session.close(); h.flush(); h.stopFinished?(); h.flush()
        // Finish the close compensation without authorizing another run.
        if h.sends.count > 4 { h.finish(4); h.flush() }
        if h.sends.count > 5 { h.finish(5); h.flush() }
    }
    static func authorizationCancellation() {
        let h = Harness(); let (session, _, task, node) = h.make(.gatewayServerAuthorization(gateway: GatewayModel()))
        node.testHandles = []
        session.start(); h.flush()
        precondition(h.authorization != nil && h.sends.isEmpty, "authorization is an asynchronous local task")
        session.stop(); h.flush()
        h.authorization?(nil)
        precondition(h.cancelledAuthorizations == 1 && task.state == .failed, "cancelled authorization cannot publish success")
        h.stopFinished?(); h.flush(); session.close(); h.flush()
    }
    static func authorizationBeforeDynamicMessages() {
        let h = Harness(); let gateway = GatewayModel()
        let (session, _, authorization, node) = h.make(.gatewayServerAuthorization(gateway: gateway))
        node.testHandles = []
        let information = SyncDeviceStepTaskModel(name: "information", operationType: .configuration(node: node, type: .gatewayServerInformation(gateway: gateway)))
        information.parentStepModel = authorization.parentStepModel
        information.relevanceTaskModels = [authorization]
        authorization.parentStepModel!.tasks.append(information)
        session.start(); h.flush()
        precondition(h.sends.isEmpty && information.state == .wait, "information waits for authorization")
        let fresh = MeshMessageHandle(); fresh.message = 42
        node.testHandles = [fresh]
        h.authorization?(nil); h.flush()
        precondition(h.sends.count == 1 && h.sends[0].handles[0].message == 42,
            "message factory reads the newly authorized information at execution time")
        h.finish(0); h.flush()
        precondition(information.state == .successful, "dynamic message finishes normally")
        session.close(); h.flush()
    }
    static func automaticRetryBudget() {
        let h = Harness(); let (session, _, _, _) = h.make()
        session.automationRestore = true
        var exhausted = 0; session.onRetryExhausted = { exhausted += 1 }
        session.start(); h.flush()
        for attempt in 0..<3 { precondition(h.sends.count == attempt + 1); h.finish(attempt, success: false); h.flush() }
        precondition(h.sends.count == 3 && exhausted == 1, "automatic recovery allows two extra attempts and emits exhaustion once")
        session.close(); h.flush()
    }
}
