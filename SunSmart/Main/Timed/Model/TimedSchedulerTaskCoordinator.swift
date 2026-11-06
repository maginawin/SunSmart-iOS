import Foundation
import NordicSigMeshSDK

/// Runtime task ownership; persisted schedules remain the source of retry work.
enum TimedSchedulerTaskCoordinator {
    struct Resource: Hashable {
        let meshUUID: String
        let networkID: String
        let identity: TimedSchedulerNodeIdentity
        let slot: Int
        // Collection uses a separate register and must not cancel ordinary Timed.
        let collection: Bool
    }
    private struct Current {
        let task: MeshSchedulerTask
        let scheduleID: Int?
        let intent: Data?
        let binding: TimedSchedulerNodeSlot?
    }
    private static let lock = NSRecursiveLock()
    private static var current: [Resource: Current] = [:]
    private static var lifecycle = MeshSchedulerTask()
    private static var operations: [String: Operation] = [:]

    final class Operation {
        let key: String
        let meshUUID: String?
        let networkID: String
        var cancelled = false
        let desired: Data?
        init(schedule: Schedule) {
            desired = businessIntent(schedule)
            let manager = MeshNetworkManager.instance
            meshUUID = manager.meshNetwork?.uuid.uuidString
            networkID = manager.currentNetworkKey.networkId.hex
            key = "\(meshUUID ?? "")/\(networkID)/\(schedule.id)"
        }
        var isCurrent: Bool {
            lock.lock(); defer { lock.unlock() }
            return !cancelled && operations[key] === self
                && MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID
                && MeshNetworkManager.instance.currentNetworkKey.networkId.hex == networkID
        }
    }

    static func begin(schedule: Schedule) -> Operation {
        lock.lock(); defer { lock.unlock() }
        let operation = Operation(schedule: schedule)
        operations[operation.key]?.cancelled = true
        operations[operation.key] = operation
        return operation
    }

    static func finish(_ operation: Operation) {
        lock.lock(); defer { lock.unlock() }
        if operations[operation.key] === operation { operations.removeValue(forKey: operation.key) }
    }

    private static func businessIntent(_ schedule: Schedule) -> Data? {
        guard let data = try? JSONEncoder().encode(schedule),
              var value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        for field in ["nodeSlots", "name", "needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"] {
            value.removeValue(forKey: field)
        }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func intent(_ schedule: Schedule, node: Node, binding: TimedSchedulerNodeSlot? = nil) -> Data? {
        guard let binding = binding ?? schedule.nodeSlots?.first(where: { $0.identity == node.timedSchedulerIdentity }), binding.isValid,
              let encoded = try? JSONEncoder().encode(binding),
              var object = (try? JSONSerialization.jsonObject(with: encoded)) as? [String: Any] else { return nil }
        // Result progress does not replace the intent that owns the transport.
        object["state"] = binding.state == .pendingRemoval ? "pendingRemoval" : "pendingApply"
        return try? JSONSerialization.data(withJSONObject: [
            "binding": object, "target": schedule.targets(node: node),
            "entry": SchedulerRegistryEntry.marshal(index: UInt8(binding.slot), entry: schedule.schedulerEntry).base64EncodedString()
        ], options: [.sortedKeys])
    }

    /// Attaching context does not cancel anything. Ownership changes only when
    /// the SDK admits the batch, after UI preflight and persistence succeed.
    static func attach(_ handles: [MeshMessageHandle], node: Node, schedule: Schedule? = nil) {
        guard let meshUUID = node.network?.uuid.uuidString, let networkID = node.subNetworkId,
              let identity = node.timedSchedulerIdentity else { return }
        lock.lock(); let capturedLifecycle = lifecycle; lock.unlock()
        var groups: [Resource: [MeshMessageHandle]] = [:]
        for handle in handles where handle.schedulerTask == nil {
            guard let set = handle.message as? SchedulerActionSet else { continue }
            let resource = Resource(meshUUID: meshUUID, networkID: networkID, identity: identity,
                                    slot: Int(set.index), collection: handle.model != nil && handle.model === node.collectionSchedulerSetupModel)
            groups[resource, default: []].append(handle)
        }
        for (resource, messages) in groups {
            let task = MeshSchedulerTask()
            let desired = schedule.flatMap { intent($0, node: node) }
            let binding = schedule?.nodeSlots?.first { $0.identity == identity && $0.slot == resource.slot }
            let valid: () -> Bool = { [weak node] in
                guard let node, !capturedLifecycle.isCancelled, !task.isCancelled,
                      node.timedSchedulerIdentity == identity,
                      node.network?.uuid.uuidString == meshUUID, node.subNetworkId == networkID,
                      MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID,
                      MeshNetworkManager.instance.currentNetworkKey.networkId.hex == networkID else { return false }
                if let schedule {
                    guard let currentSchedule = MeshNetworkManager.instance.schedules.first(where: { $0.id == schedule.id }) else { return false }
                    return intent(currentSchedule, node: node) == desired
                }
                return true
            }
            var admitted = false
            for handle in messages {
                handle.schedulerTask = task
                let previousValidity = handle.transmissionIsValid
                handle.transmissionIsValid = { valid() && (previousValidity?() ?? true) }
                let previousResponse = handle.responseIsValid
                handle.responseIsValid = { valid() && (previousResponse?($0) ?? true) }
                handle.schedulerAdmission = {
                    guard !admitted else { return }
                    admitted = true
                    guard valid() else { task.cancel(); return }
                    lock.lock()
                    let previous = current.updateValue(Current(task: task, scheduleID: schedule?.id, intent: desired, binding: binding), forKey: resource)
                    lock.unlock()
                    if let previous, previous.task !== task {
                        MeshProxyMessageCommand.shared.cancelSchedulerTasks([previous.task])
                    }
                }
            }
        }
    }

    static func configurationSaved(_ schedule: Schedule, meshUUID: String, networkID: String) {
        lock.lock()
        let operationKey = "\(meshUUID)/\(networkID)/\(schedule.id)"
        if let operation = operations[operationKey], operation.desired != businessIntent(schedule) {
            operation.cancelled = true
            operations.removeValue(forKey: operationKey)
        }
        lock.unlock()
        invalidate { resource, value in
            guard resource.meshUUID == meshUUID && resource.networkID == networkID,
                  value.scheduleID == schedule.id else { return false }
            guard let node = MeshNetworkManager.instance.realNodes.first(where: { $0.timedSchedulerIdentity == resource.identity }) else { return true }
            // Applying a successful clear after Proxy reset may save the removal
            // of its own binding. Preserve that receipt, but keep tracking the task
            // so later slot reuse or lifecycle invalidation still cancels it.
            if !resource.collection, let binding = value.binding, binding.state == .pendingRemoval,
               value.intent != nil,
               schedule.nodeSlots?.contains(where: { $0.identity == resource.identity }) == false,
               !MeshProxyMessageCommand.shared.isBusy,
               node.observedTimedSlots?.contains(resource.slot) == false,
               value.intent == intent(schedule, node: node, binding: binding) {
                return false
            }
            return value.intent != intent(schedule, node: node)
        }
    }

    static func invalidateAll() {
        lock.lock()
        lifecycle.cancel()
        lifecycle = MeshSchedulerTask()
        operations.values.forEach { $0.cancelled = true }
        operations.removeAll()
        lock.unlock()
        invalidate { _, _ in true }
    }

    static func invalidate(node: Node) {
        guard let identity = node.timedSchedulerIdentity else { return }
        invalidate { resource, _ in resource.identity == identity && resource.meshUUID == node.network?.uuid.uuidString }
    }

    private static func invalidate(_ matches: (Resource, Current) -> Bool) {
        lock.lock()
        let keys = current.keys.filter { matches($0, current[$0]!) }
        let tasks = keys.compactMap { current.removeValue(forKey: $0)?.task }
        tasks.forEach { $0.cancel() }
        lock.unlock()
        if !tasks.isEmpty { MeshProxyMessageCommand.shared.cancelSchedulerTasks(tasks) }
    }
}
