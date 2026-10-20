import Foundation
import NordicSigMeshSDK

enum HDBDeviceSyncService {
    /// Each sensorGroupId belongs to one device; elements and Lighting Zones are not members.
    static var sensorPublicationRetransmit: Publish.Retransmit {
        SensorPublicationPolicy.retransmit(memberCount: 1)
    }

    /// Only the post-provisioning caller can confirm that an empty Zone target is already satisfied.
    static func prepareIntent(context: HDBDeviceSyncContext, subscriptionsWereReset: Bool = false) throws {
        guard context.isCurrent() else { throw HDBConfigurationError.unavailable }
        _ = try HDBLightingZonePolicy.requiredTargets(from: context.targets)
        let node = context.node, space = context.space
        var metadata = try HDBConfigurationStore.deviceConfiguration(node: node)
        if subscriptionsWereReset { metadata.lightingZonesStatus = .synced }
        let config = try HDBConfigurationStore.load(space: space)
        var restoredIdentity = false
        if let saved = config.devices.first(where: { $0.nodeUuid == node.uuid }) {
            if subscriptionsWereReset || saved.mac != metadata.mac || saved.nodeAddress != metadata.nodeAddress || !saved.hasSameModels(as: metadata) {
                try HDBConfigurationStore.restoreDevice(space: space, nodeUuid: node.uuid,
                    nodeAddress: metadata.nodeAddress, mac: metadata.mac, modelConfiguration: metadata, subscriptionsWereReset: subscriptionsWereReset)
                restoredIdentity = true
            }
        } else {
            try HDBConfigurationStore.update(space: space) { $0.devices.append(metadata) }
        }
        if context.hasSensor { _ = try HDBConfigurationStore.ensureSensorGroup(space: space, nodeUuid: node.uuid) }
        let latest = try HDBConfigurationStore.load(space: space)
        let plan = try context.plan(in: latest)
        let identity = try signature(context: context, plan: plan)
        let storedIdentity = node.preConfiguration.hdbInitializationSignature
        guard storedIdentity != identity, storedIdentity != "pending:" + identity else { return }
        // Establish the new provisioning identity before retaining per-field progress.
        // This also repairs a failed restore save, including an address change.
        if !restoredIdentity {
            try HDBConfigurationStore.restoreDevice(space: space, nodeUuid: node.uuid,
                nodeAddress: metadata.nodeAddress, mac: metadata.mac, modelConfiguration: metadata, subscriptionsWereReset: subscriptionsWereReset)
        }
        try saveInitializationSignature(context: context, signature: "pending:" + identity)

    }

    /// Mutations precede the ordinary task scope snapshot, which captures Group identities.
    static func prepareIntents(nodes: [Node]) {
        for node in nodes {
            do {
                if let context = try HDBDeviceSyncContext.resolve(node: node), node.isKeybindComplete {
                    try HDBConfigurationStore.finishSensorGroupCleanup(space: context.space)
                    try prepareIntent(context: context)
                }
            } catch {
                // The builder retains this failure as an explicit task, never an empty success.
            }
        }
    }

    static func signature(context: HDBDeviceSyncContext, plan: HDBDevicePreparationPlan) throws -> String {
        try HDBDevicePreparationPolicy.signature(plan, deviceKey: context.node.deviceKey, createdTimestamp: context.node.createdTimestamp)
    }

    static func saveInitializationSignature(context: HDBDeviceSyncContext, signature: String) throws {
        let previous = context.node.preConfiguration.hdbInitializationSignature
        context.node.preConfiguration.hdbInitializationSignature = signature
        guard context.node.preConfiguration.save(meshUUID: context.space.meshUUID, nodeAddress: context.node.primaryUnicastAddress),
              Node.PreConfiguration.load(meshUUID: context.space.meshUUID, nodeAddress: context.node.primaryUnicastAddress)?.hdbInitializationSignature == signature else {
            context.node.preConfiguration.hdbInitializationSignature = previous
            throw HDBConfigurationError.persistenceFailed
        }
    }

    static func hasInitializationReceipt(context: HDBDeviceSyncContext, plan: HDBDevicePreparationPlan) throws -> Bool {
        context.node.preConfiguration.hdbInitializationSignature == (try signature(context: context, plan: plan))
    }

    static func hasInitializationIntent(context: HDBDeviceSyncContext, plan: HDBDevicePreparationPlan) throws -> Bool {
        context.node.preConfiguration.hdbInitializationSignature == "pending:" + (try signature(context: context, plan: plan))
    }

    static func pendingLinks(context: HDBDeviceSyncContext, plan: HDBDevicePreparationPlan) -> [HDBPreparationStepID] {
        func model(_ target: HDBModelTarget) -> Model? {
            context.node.elements.first { $0.unicastAddress == target.elementAddress }?.models.first {
                $0.modelIdentifier == target.modelIdentifier && $0.companyIdentifier == target.companyIdentifier
            }
        }
        guard let address = plan.sensorGroupId else { return [] }
        return plan.subscriptionTargets.filter { target in
            model(target)?.subscriptions.contains { $0.address.address == address } != true
        }.map(HDBPreparationStepID.subscription) + plan.publicationTargets.filter { target in
            guard let publish = model(target)?.publish else { return true }
            return publish.publicationAddress.address != address || publish.index != plan.appKeyIndex
                || publish.ttl != SensorPublicationPolicy.ttl || publish.period != .disabled
                || publish.retransmit != sensorPublicationRetransmit
        }.map(HDBPreparationStepID.publication)
    }

    static func isPrepared(context: HDBDeviceSyncContext, config: HDBConfiguration) throws -> Bool {
        let plan = try context.plan(in: config)
        guard let device = config.devices.first(where: { $0.nodeUuid == context.node.uuid && $0.nodeAddress == context.node.primaryUnicastAddress }),
              device.mac == (try HDBDeviceConfiguration.normalizedMAC(context.node.macAddress)),
              device.hasSameModels(as: try HDBConfigurationStore.deviceConfiguration(node: context.node)),
              !context.hasSensor || device.sensorGroupId != nil else { return false }
        return try hasInitializationReceipt(context: context, plan: plan) && pendingLinks(context: context, plan: plan).isEmpty
    }

    /// Zone rebuilding repairs its LC receivers, but never owns Sensor Server subscriptions.
    static func canSetZones(context: HDBDeviceSyncContext, config: HDBConfiguration) throws -> Bool {
        let plan = try context.plan(in: config)
        guard config.devices.contains(where: { $0.nodeUuid == context.node.uuid && $0.nodeAddress == context.node.primaryUnicastAddress }),
              try hasInitializationReceipt(context: context, plan: plan) else { return false }
        let repairableTargets = Set(try context.zoneSensorTargets(in: config))
        return pendingLinks(context: context, plan: plan).allSatisfy { step in
            if case .subscription(let target) = step { return repairableTargets.contains(target) }
            return false
        }
    }

    static func needsSync(node: Node) -> Bool {
        do {
            guard let context = try HDBDeviceSyncContext.resolve(node: node, allowNonLights: true) else { return false }
            let read = { Result { try HDBConfigurationStore.load(space: context.space) } }
            let result = NodeSyncReadContext.current?.memoized("hdb.config." + context.space.id, read: read) ?? read()
            let config = try result.get()
            if try !cleanupOperations(context: context, config: config).isEmpty { return true }
            guard node.deviceType == .light else { return false }
            guard try isPrepared(context: context, config: config) else { return true }
            guard let device = config.devices.first(where: { $0.nodeUuid == node.uuid }) else { return true }
            return device.lightingZonesStatus == .pending
                || restorationCommands(device).count > 0
        } catch { return true }
    }

    static func restorationCommands(_ device: HDBDeviceConfiguration) -> [HDBLightingCommand] {
        guard let saved = device.lightingConfiguration else { return [] }
        return [.intensity, .softDimming, .timeDelay].filter { saved.status(for: $0).map { $0 != .synced } ?? false }
    }

    static func cleanupOperations(context: HDBDeviceSyncContext, config: HDBConfiguration) throws -> [HDBDeviceSyncTask] {
        var tasks: [HDBDeviceSyncTask] = []
        for address in try HDBConfigurationStore.pendingSensorGroupAddresses(space: context.space) {
            for element in context.node.elements {
                for model in element.models {
                    let target = HDBModelTarget(elementAddress: element.unicastAddress, modelIdentifier: model.modelIdentifier, companyIdentifier: model.companyIdentifier)
                    if model.publish?.publicationAddress.address == address {
                        tasks.append(.init(context: context, operation: .cleanup(address, target, true)))
                    }
                    if model.subscriptions.contains(where: { $0.address.address == address }) {
                        tasks.append(.init(context: context, operation: .cleanup(address, target, false)))
                    }
                }
            }
        }
        return tasks
    }

    static func deletionSyncType(datas: [(node: Node, syncData: NodeSyncData)]) -> SyncDevicesViewController.SyncType? {
        let cleanupNodes = MeshNetworkManager.instance.meshNetwork?.nodes.filter { node in
            guard let context = try? HDBDeviceSyncContext.resolve(node: node, allowNonLights: true),
                  context.isCurrent(), let config = try? HDBConfigurationStore.load(space: context.space) else { return false }
            return (try? cleanupOperations(context: context, config: config).isEmpty) != true
        } ?? []
        guard !cleanupNodes.isEmpty else { return datas.isEmpty ? nil : .spaceTriggerZones(datas: datas) }
        var seen = Set<UUID>()
        return .devices((cleanupNodes + datas.map(\.node)).filter { seen.insert($0.uuid).inserted })
    }

    static func makeSteps(context: HDBDeviceSyncContext) throws -> [SyncDeviceStepModel] {
        let config = try HDBConfigurationStore.load(space: context.space)
        let cleanup = try cleanupOperations(context: context, config: config)
        if context.node.deviceType != .light { return steps(cleanup) }
        guard let device = config.devices.first(where: { $0.nodeUuid == context.node.uuid }) else { throw HDBConfigurationError.unavailable }
        let plan = try context.plan(in: config)
        guard !context.hasSensor || device.sensorGroupId != nil else { throw HDBConfigurationError.addressUnavailable }
        var operations = cleanup + pendingLinks(context: context, plan: plan).map {
            HDBDeviceSyncTask(context: context, operation: .preparation(plan, $0))
        }
        let initialized = try hasInitializationReceipt(context: context, plan: plan)
        let intentEstablished = try hasInitializationIntent(context: context, plan: plan)
        guard initialized || intentEstablished,
              device.nodeAddress == context.node.primaryUnicastAddress else { throw HDBConfigurationError.persistenceFailed }
        guard let saved = device.lightingConfiguration else { throw HDBConfigurationError.invalidData }
        if !initialized { operations.append(.init(context: context, operation: .initialization(plan, saved))) }
        let zoneOperations = try context.zoneOperations(in: config)
        operations += zoneOperations.map { .init(context: context, operation: .zone($0)) }
        if initialized {
            operations += restorationCommands(device).map { .init(context: context, operation: .configuration($0, saved)) }
        }
        return steps(operations)
    }

    private static func steps(_ operations: [HDBDeviceSyncTask]) -> [SyncDeviceStepModel] {
        var steps: [SyncDeviceStepModel] = []
        for operation in operations {
            let task = SyncDeviceStepTaskModel(name: operation.title, operationType: .configuration(node: operation.context.node, type: .hdb(operation)))
            let step = SyncDeviceStepModel(type: operation.title, state: .none, tasks: [task])
            task.parentStepModel = step
            if let previous = steps.last { step.relevanceStepModels = [previous] }
            steps.append(step)
        }
        return steps
    }
}

/// A task owns expected values and strict ACKs; the shared Sync session owns transport.
final class HDBDeviceSyncTask {
    enum Operation {
        case preparation(HDBDevicePreparationPlan, HDBPreparationStepID)
        case initialization(HDBDevicePreparationPlan, HDBLightingConfiguration)
        case zone(HDBZoneOperation)
        case configuration(HDBLightingCommand, HDBLightingConfiguration)
        case cleanup(UInt16, HDBModelTarget, Bool)
    }
    let context: HDBDeviceSyncContext
    let operation: Operation
    private var handles: [MeshMessageHandle] = []
    private var acknowledged = Set<ObjectIdentifier>()
    private var rejected = false
    private var expectedRevision: Int64?
    private var fieldHandles: [String: [MeshMessageHandle]] = [:]
    private(set) var hasPendingZoneCacheSave = false
    private(set) var isSuccessful = false

    init(context: HDBDeviceSyncContext, operation: Operation) { self.context = context; self.operation = operation }
    var isLightingZoneOperation: Bool {
        if case .zone = operation { return true }
        return false
    }
    var title: String {
        switch operation {
        case .preparation(_, .subscription): return "hdb_sensor_subscription".localizedString
        case .preparation(_, .publication): return "hdb_sensor_publication".localizedString
        case .initialization: return "hdb_preparation".localizedString
        case .cleanup: return "hdb_sensor_cleanup".localizedString
        case .zone: return "hdb_lighting_zones".localizedString
        case .configuration(let command, _): return command.titleKey.localizedString
        }
    }
    func isCurrent() -> Bool {
        guard context.isCurrent() else { trace("invalid", reason: "context"); return false }
        guard let config = try? HDBConfigurationStore.load(space: context.space) else { trace("invalid", reason: "configuration-unavailable"); return false }
        if let expectedRevision, (try? HDBConfigurationStore.revision(space: context.space)) != expectedRevision {
            trace("invalid", reason: "revision-changed"); return false
        }
        if case .cleanup(let address, _, _) = operation {
            return (try? HDBConfigurationStore.pendingSensorGroupAddresses(space: context.space).contains(address)) == true
        }
        guard let device = config.devices.first(where: { $0.nodeUuid == context.node.uuid && $0.nodeAddress == context.node.primaryUnicastAddress }) else {
            trace("invalid", reason: "device-identity"); return false
        }
        let current: Bool
        switch operation {
        case .cleanup: return false
        case .preparation(let plan, _): current = (try? context.plan(in: config)) == plan
        case .initialization(let plan, let saved):
            let identityIsReady = (try? HDBDeviceSyncService.hasInitializationIntent(context: context, plan: plan)) == true
                || (isSuccessful && (try? HDBDeviceSyncService.hasInitializationReceipt(context: context, plan: plan)) == true)
            current = identityIsReady && (try? context.plan(in: config)) == plan && device.lightingConfiguration?.values == saved.values
        case .zone(let operation):
            current = HDBLightingZonePolicy.matches(operation.plan, in: config)
                && (try? HDBLightingZonePolicy.requiredZoneTargets(from: context.targets, primaryAddress: context.node.primaryUnicastAddress)) == operation.targets
                && (try? context.zoneSensorTargets(in: config)) == operation.plan.sensorTargets
                && (try? context.zoneBroadcastTargets()) == operation.plan.broadcastTargets
        case .configuration(let command, let saved):
            current = device.lightingConfiguration?.values.selected(command) == saved.values.selected(command)

        }
        if !current { trace("invalid", reason: "intent-changed") }
        return current
    }

    func makeHandles() -> [MeshMessageHandle] {
        handles = []; acknowledged.removeAll(); fieldHandles = [:]; expectedRevision = nil; rejected = false; isSuccessful = false
        do {
            guard isCurrent(), let key = context.key else { throw HDBConfigurationError.unavailable }
            let ready: Bool
            if case .zone(let operation) = operation {
                let receivers = operation.plan.broadcastTargets.compactMap(context.model).flatMap { model in
                    [model] + model.relatedModels.filter { $0.parentElement === model.parentElement }
                }
                ready = context.node.isKeybindComplete(restoringSubelementSubscriptionsFor: Array(Set(receivers)))
            } else {
                ready = context.node.isKeybindComplete
            }
            guard ready else { throw HDBConfigurationError.unavailable }
            expectedRevision = try HDBConfigurationStore.revision(space: context.space)
            func bound(_ target: HDBModelTarget) throws -> Model { try HDBLightingMessages.model(target, node: context.node, key: key) }
            switch operation {
            case .cleanup(let address, let target, let publication):
                if publication {
                    guard let model = context.node.elements.first(where: { $0.unicastAddress == target.elementAddress })?.models.first(where: { $0.modelIdentifier == target.modelIdentifier && $0.companyIdentifier == target.companyIdentifier }),
                          let message = ConfigModelPublicationSet(disablePublicationFor: model) else { throw HDBConfigurationError.invalidData }
                    handles = [MeshMessageHandle(message: message, address: context.node.primaryUnicastAddress)]
                } else {
                    handles = [try Self.subscription(target, address: address, node: context.node.primaryUnicastAddress, add: false)]
                }
            case .preparation(let plan, let step):
                switch step {
                case .subscription(let target):
                    guard let address = plan.sensorGroupId else { throw HDBConfigurationError.addressUnavailable }
                    _ = try bound(target)
                    handles = [try Self.subscription(target, address: address, node: context.node.primaryUnicastAddress, add: true)]
                case .publication(let target):
                    guard let address = plan.sensorGroupId,
                          let message = ConfigModelPublicationSet(Publish(to: MeshAddress(address), using: key,
                            usingFriendshipMaterial: false, ttl: SensorPublicationPolicy.ttl, period: .disabled,
                            retransmit: HDBDeviceSyncService.sensorPublicationRetransmit), to: try bound(target)) else { throw HDBConfigurationError.invalidData }
                    handles = [MeshMessageHandle(message: message, address: context.node.primaryUnicastAddress)]

                }
            case .zone(let operation):
                handles = try HDBLightingZoneService.handles(for: operation)
            case .initialization(let plan, let saved):
                let base = try HDBLightingMessages.preparation(plan.baseTargets)
                handles = try base.filter { !($0.1 is LightLCModeSet) }.map {
                    MeshMessageHandle(message: $0.1, model: try bound($0.0))
                }
                for command in [HDBLightingCommand.intensity, .softDimming, .timeDelay] {
                    try appendConfiguration(command, saved: saved, bound: bound)
                }
                // LC Mode enables the controller; Auto is a separate Light OnOff command.
                let modes = try base.filter { $0.1 is LightLCModeSet }.map {
                    MeshMessageHandle(message: $0.1, model: try bound($0.0))
                }
                handles += modes
                fieldHandles["lightingControl", default: []] += modes
                var activation = saved
                activation.lightingControl?.status = .pending
                try appendConfiguration(.override, saved: activation, bound: bound)
            case .configuration(let command, let saved):
                try appendConfiguration(command, saved: saved, bound: bound)

            }
            handles.forEach { $0.continuous = false }
            trace("planned")
        } catch {
            rejected = true; handles = []
            trace("plan-failed", reason: (error as? HDBConfigurationError).map { String(describing: $0) } ?? "unexpected")
        }
        return handles
    }

    private func appendConfiguration(_ command: HDBLightingCommand, saved: HDBLightingConfiguration,
                                     bound: (HDBModelTarget) throws -> Model) throws {
        let targets = try HDBLightingZonePolicy.requiredTargets(from: context.targets)
        let recipient = HDBLightingRecipient(nodeUuid: context.node.uuid, nodeAddress: context.node.primaryUnicastAddress, targets: targets)
        for write in try HDBLightingConfigurationPolicy.writes(command, values: saved.values) {
            let field = write.fieldName
            guard saved.status(field: field) == .pending else { continue }
            for target in try HDBLightingConfigurationPolicy.targets(for: write, recipient: recipient) {
                let handle = MeshMessageHandle(message: HDBLightingMessages.message(write), model: try bound(target))
                handles.append(handle); fieldHandles[field, default: []].append(handle)
            }
        }
    }

    static func subscription(_ target: HDBModelTarget, address: UInt16, node: UInt16, add: Bool) throws -> MeshMessageHandle {
        var data = Data()
        func append(_ value: UInt16) { data.append(UInt8(value & 255)); data.append(UInt8(value >> 8)) }
        append(target.elementAddress); append(address)
        if let company = target.companyIdentifier { append(company) }; append(target.modelIdentifier)
        let message: MeshMessage? = add ? ConfigModelSubscriptionAdd(parameters: data) : ConfigModelSubscriptionDelete(parameters: data)
        guard let message else { throw HDBConfigurationError.invalidData }
        return MeshMessageHandle(message: message, address: node)
    }

    func receive(handle: MeshMessageHandle, response: MeshMessage, cacheOnly: Bool = false) {
        // wait:true STOP can still acknowledge the in-flight request. Its physical
        // result remains valid for this identity, even after the desired intent changed.
        guard cacheOnly ? (isLightingZoneOperation && context.isCurrent()) : isCurrent() else {
            rejected = true; trace("ack-rejected", reason: "stale-task"); return
        }
        if cacheOnly { rejected = true } // Never complete a stopped operation.
        guard handles.contains(where: { $0 === handle }) else { rejected = true; trace("ack-rejected", reason: "unknown-handle"); return }
        let matches: Bool
        if case .zone(let operation) = operation {
            guard let index = handles.firstIndex(where: { $0 === handle }),
                  let status = response as? ConfigModelSubscriptionStatus,
                  handle.address == operation.nodeAddress else { rejected = true; return }
            matches = HDBLightingZoneService.matches(operation.subscriptions[index], status: status)
            if matches {
                HDBLightingZoneService.applyAcknowledgedSubscription(operation.subscriptions[index], to: context.node)
                hasPendingZoneCacheSave = true
            }
        } else if let request = handle.message as? ConfigModelPublicationSet, let status = response as? ConfigModelPublicationStatus {
            matches = HDBDevicePreparationPolicy.matchesConfigurationStatus(request: request.parameters, response: status.parameters, successful: status.isSuccess)
        } else if handle.message is ConfigModelSubscriptionAdd || handle.message is ConfigModelSubscriptionDelete,
                  let status = response as? ConfigModelSubscriptionStatus {
            matches = HDBDevicePreparationPolicy.matchesConfigurationStatus(request: handle.message.parameters, response: status.parameters, successful: status.isSuccess)
        } else { matches = HDBLightingMessages.matches(handle.message, response: response) }
        if matches { acknowledged.insert(ObjectIdentifier(handle)) }
        else { rejected = true; trace("ack-rejected", reason: "response-mismatch") }
    }

    /// Stop may replace the batch completion callback. Save only already accepted ACKs;
    /// this never completes the Zone intent and never writes to a replaced identity.
    @discardableResult
    func flushAcknowledgedZoneCache() -> Bool {
        guard hasPendingZoneCacheSave else { return true }
        guard context.isCurrent(), context.node.save() else {
            rejected = true; isSuccessful = false
            trace("persist-failed", reason: "zone-cache")
            return false
        }
        hasPendingZoneCacheSave = false
        context.node.clearSyncStateCache()
        return true
    }

    // Releasing a Group changes the session scope; do it only after all tasks settle.
    func finishCleanup() -> Bool {
        guard case .cleanup = operation else { return true }
        guard isSuccessful, context.isCurrent() else { return false }
        do {
            try HDBConfigurationStore.finishSensorGroupCleanup(space: context.space)
            return true
        } catch { return false }
    }

    func persist(result: [MeshMessageHandle]) -> Bool {
        guard isCurrent() else { trace("persist-rejected", reason: "stale-task"); return false }
        let success = !rejected && !handles.isEmpty && result.count == handles.count
            && result.allSatisfy { $0.isSuccessful && acknowledged.contains(ObjectIdentifier($0)) }
        do {
            for handle in result where handle.isSuccessful && acknowledged.contains(ObjectIdentifier(handle))
                && !(handle.message is ConfigModelSubscriptionAdd) && !(handle.message is ConfigModelSubscriptionDelete)
                && !(handle.message is ConfigModelSubscriptionOverwrite) && !(handle.message is ConfigModelSubscriptionDeleteAll) {
                context.node.applyMessageHandle(handle, isSuccess: true)
            }
            guard context.node.save() else { throw HDBConfigurationError.persistenceFailed }
            hasPendingZoneCacheSave = false
            if case .cleanup = operation {
                guard success else { return false }
                context.node.clearSyncStateCache()
                isSuccessful = true
                return true
            }
            if case .zone(let operation) = operation {
                guard success else { trace("incomplete"); return false }
                if operation.isLast {
                    try HDBConfigurationStore.update(space: context.space) { config in
                        try HDBLightingZonePolicy.complete(operation, in: &config)
                    }
                }
                expectedRevision = try HDBConfigurationStore.revision(space: context.space)
                context.node.clearSyncStateCache()
                isSuccessful = true
                trace("persisted")
                return true
            }
            try HDBConfigurationStore.update(space: context.space) { config in
                guard let index = config.devices.firstIndex(where: { $0.nodeUuid == context.node.uuid }) else { throw HDBConfigurationError.unavailable }
                switch operation {
                case .cleanup: break
                case .preparation: break
                case .initialization, .configuration:
                    for (field, expected) in fieldHandles {
                        let completed = !expected.isEmpty && expected.allSatisfy { handle in
                            result.contains(where: { $0 === handle }) && handle.isSuccessful && acknowledged.contains(ObjectIdentifier(handle))
                        }
                        config.devices[index].lightingConfiguration?.mark(fields: [field], status: completed ? .synced : .pending)
                    }
                case .zone: break

                }
            }
            expectedRevision = try HDBConfigurationStore.revision(space: context.space)
            if success, case .initialization(let plan, _) = operation {
                try HDBDeviceSyncService.saveInitializationSignature(context: context,
                    signature: HDBDeviceSyncService.signature(context: context, plan: plan))
            }
            context.node.clearSyncStateCache()
            isSuccessful = success
        } catch {
            isSuccessful = false
            trace("persist-failed", reason: (error as? HDBConfigurationError).map { String(describing: $0) } ?? "unexpected")
        }
        trace(isSuccessful ? "persisted" : "incomplete")
        return isSuccessful
    }

    private func trace(_ stage: String, reason: String = "none") {
        #if DEBUG
        let kind: String
        switch operation {
        case .preparation(_, .subscription): kind = "subscription"
        case .preparation(_, .publication): kind = "publication"
        case .initialization: kind = "initialization"
        case .zone: kind = "zone"
        case .configuration: kind = "configuration"
        case .cleanup: kind = "cleanup"
        }
        let currentRevision = try? HDBConfigurationStore.revision(space: context.space)
        let address = String(format: "%04X", context.node.primaryUnicastAddress)
        let expected = expectedRevision.map(String.init) ?? "none"
        let current = currentRevision.map(String.init) ?? "unavailable"
        print("[HDB][DeviceTask] stage=\(stage) kind=\(kind) node=\(address) expectedRevision=\(expected) currentRevision=\(current) handles=\(handles.count) ack=\(acknowledged.count) reason=\(reason)")
        #endif
    }
}
