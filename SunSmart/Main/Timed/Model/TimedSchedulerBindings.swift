import Foundation
import NordicSigMeshSDK
import ObjectiveC

extension Node {
    var timedSchedulerIdentity: TimedSchedulerNodeIdentity? {
        guard let key = deviceKey,
              let fingerprint = try? SchedulerModelSnapshot.keyFingerprint(["deviceKey": key.hex]) else { return nil }
        return .init(nodeUUID: uuid.uuidString.uppercased(), unicastAddress: primaryUnicastAddress.hex,
                     deviceKeyFingerprint: fingerprint)
    }

    var observedTimedSlots: Set<Int>? {
        guard !schedulerSetupModels.isEmpty,
              schedulerSetupModels.allSatisfy({ allSchedulerModelEntrys[$0] != nil }) else { return nil }
        return Set(schedulerSetupModels.flatMap { model in
            allSchedulerModelEntrys[model]!.filter { $0.value.isValid }.map(\.key)
        })
    }

    func timedActionAddress(contextGroup: Group? = nil) -> TimedSchedulerActionAddress? {
        let autoOwner = Schedule.schedulerModelOwner(for: .turnOn, on: self, contextGroup: contextGroup)
        guard let ordinary = schedulerSetupModel(for: .ordinary)?.parentElement?.unicastAddress,
              let auto = schedulerSetupModel(for: autoOwner)?.parentElement?.unicastAddress else { return nil }
        return .init(autoOn: auto.hex, off: ordinary.hex, recall: ordinary.hex)
    }

    func timedSchedule(at slot: Int) -> Schedule? {
        let matching = MeshNetworkManager.instance.schedules.filter { $0.slot(on: self) == slot }
        return matching.count == 1 ? matching.first : nil
    }

    /// Preserve captured task ownership before updating App state from a reply.
    @discardableResult
    func applyMessageHandle(_ handle: MeshMessageHandle, isSuccess: Bool = true, finalizeSchedulerBinding: Bool = true) -> Bool {
        guard handle.schedulerTask?.isCancelled != true else { return false }
        if let context = handle.timedSchedulerContext, !context.matches(node: self) { return false }
        if let context = handle.sceneContext {
            guard context.matches(node: self) else { return false }
            if handle.message is SceneStore || handle.message is SceneDelete {
                guard context.removesGroupRelationship else { return context.apply(node: self, successful: isSuccess) }
                guard let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == context.number }) else { return false }
                let previousCache = sceneExecuteDatas, previousConfiguration = scene.info.configuration
                let affectedGroup = group
                let previousRelations = affectedGroup?.info.sceneExecuteDatas
                let previousSchedules = affectedGroup?.info.bindSchedules
                enum PersistenceFailure: Error { case groupSceneRemoval }
                let saved = SunSmartDataManager.shared.configurationTransaction {
                    guard context.apply(node: self, successful: isSuccess, beforePersist: {
                        self.completeGroupSceneRemoval(sceneId: context.number)
                    }) else { throw PersistenceFailure.groupSceneRemoval }
                }
                guard saved else {
                    sceneExecuteDatas = previousCache
                    scene.info.configuration = previousConfiguration
                    if let previousRelations { affectedGroup?.info.sceneExecuteDatas = previousRelations }
                    if let previousSchedules { affectedGroup?.info.bindSchedules = previousSchedules }
                    clearSyncStateCache()
                    // The SDK cache may already be committed. The rolled-back
                    // waitDelete relation remains a retryable cleanup intent.
                    return false
                }
                return true
            }
        }
        updateData(message: handle.message, isSuccess: isSuccess, model: handle.model, finalizeSchedulerBinding: finalizeSchedulerBinding)
        return isSuccess
    }
}

extension Schedule {
    #if DEBUG
    private func traceSchedulerResult(on node: Node, stage: String, detail: String = "") {
        let binding = nodeSlots?.first { $0.identity == node.timedSchedulerIdentity }
        let models = node.schedulerSetupModels.map { model -> String in
            let address = model.parentElement?.unicastAddress.hex ?? "none"
            guard let entries = node.allSchedulerModelEntrys[model] else { return "\(address):unknown" }
            let slots = entries.filter { $0.value.isValid }.keys.sorted().map(String.init).joined(separator: ",")
            return "\(address):[\(slots)]"
        }.joined(separator: ";")
        print("[ScheduleResult] node=\(node.primaryUnicastAddress.hex) schedule=\(id) stage=\(stage) slot=\(binding.map { String($0.slot) } ?? "none") binding=\(binding.map { String(describing: $0.state) } ?? "none") proxyBusy=\(MeshProxyMessageCommand.shared.isBusy) models=\(models) \(detail)")
    }
    #endif

    private func schedulerResultFailure(_ reason: String, on node: Node) -> Bool {
        #if DEBUG
        traceSchedulerResult(on: node, stage: "failed", detail: "reason=\(reason)")
        #endif
        return false
    }

    /// Accept receipts before applying progress can invalidate their send intent.
    /// Keep the binding until every Model result has been applied and persisted.
    func applySchedulerResults(_ results: [MeshMessageHandle], expected: [MeshMessageHandle], on node: Node) -> Bool {
        let expectedIDs = Set(expected.map(ObjectIdentifier.init))
        guard expectedIDs.count == expected.count, results.count == expected.count,
              Set(results.map(ObjectIdentifier.init)) == expectedIDs else {
            return schedulerResultFailure("receiptMembership", on: node)
        }
        guard !expected.contains(where: { $0.schedulerTask?.isCancelled == true }) else {
            return schedulerResultFailure("cancelledBeforeApply", on: node)
        }
        let accepted = results.map { $0.isSuccessful }
        #if DEBUG
        let receipts = zip(results, accepted).map { handle, valid in
            "task=\(handle.schedulerTask.map { String(describing: ObjectIdentifier($0)) } ?? "none"),accepted=\(valid),responses=\(handle.respondAddresss.count)/\(handle.allAddresss.count)"
        }.joined(separator: ";")
        traceSchedulerResult(on: node, stage: "accepted", detail: "expected=\(expected.count) returned=\(results.count) receipts=\(receipts)")
        #endif
        var applied = true
        for (handle, successful) in zip(results, accepted) where successful {
            if !node.applyMessageHandle(handle, finalizeSchedulerBinding: false) { applied = false }
        }
        node.clearSyncStateCache()
        // Persist partial progress too, so retry only sends unfinished Models.
        guard node.savePropertys() else { return schedulerResultFailure("nodeSave", on: node) }
        guard applied else { return schedulerResultFailure("messageContext", on: node) }
        guard accepted.allSatisfy({ $0 }) else { return schedulerResultFailure("receiptNotAccepted", on: node) }
        guard !expected.contains(where: { $0.schedulerTask?.isCancelled == true }) else {
            return schedulerResultFailure("cancelledDuringApply", on: node)
        }
        let persisted = reconcileBinding(on: node)
        guard persisted else { return false } // Reconciliation logs its specific failure below.
        guard !expected.contains(where: { $0.schedulerTask?.isCancelled == true }) else {
            return schedulerResultFailure("cancelledDuringReconcile", on: node)
        }
        #if DEBUG
        traceSchedulerResult(on: node, stage: "completed", detail: "accepted=\(accepted.filter { $0 }.count)")
        #endif
        return true
    }

    /// A current result is complete only when every Model is known. A partial
    /// ACK must not turn an unknown Model into an observed empty register.
    @discardableResult
    func reconcileBinding(on node: Node) -> Bool {
        guard selectTargetType != .profile, !nodeSlotsLoadFailed,
              let identity = node.timedSchedulerIdentity, let nodeSlots else {
            return schedulerResultFailure("invalidBindingState", on: node)
        }
        guard let index = nodeSlots.firstIndex(where: { $0.identity == identity }) else { return true }
        guard nodeSlots[index].isV3 else { return schedulerResultFailure("legacyBinding", on: node) }
        if nodeSlots[index].state == .pendingRemoval {
            return releaseClearedBinding(on: node)
        }
        let state: TimedSchedulerNodeSlot.State = targets(node: node)
            && nodeSlots[index].actionAddress == node.timedActionAddress()
            && schedulerSyncDifference(on: node) == .synchronized ? .synced : .pendingApply
        guard nodeSlots[index].state != state else { return true }
        guard state != .synced || node.savePropertys() else { return schedulerResultFailure("reconcileNodeSave", on: node) }
        let previous = nodeSlots
        self.nodeSlots![index].state = state
        guard save() else { self.nodeSlots = previous; return schedulerResultFailure("reconcileScheduleSave", on: node) }
        return true
    }
    var activeSceneGroups: [Group] {
        guard let scene, !scene.info.configurationLoadFailed,
              scene.info.configuration?.kind != .devices else { return [] }
        return scene.info.groups.filter { group in
            group.info.sceneExecuteDatas.contains { $0.sceneNumber == scene.number && $0.state != .waitDelete }
        }
    }

    func slot(on node: Node) -> Int? {
        guard !nodeSlotsLoadFailed else { return nil }
        guard let nodeSlots else { return (0..<16).contains(id) ? id : nil }
        guard let identity = node.timedSchedulerIdentity else { return nil }
        let matches = nodeSlots.filter { $0.identity == identity && $0.isValid }
        return matches.count == 1 ? matches[0].slot : nil
    }

    func hasObservedEntry(on node: Node) -> Bool {
        guard let slot = slot(on: node) else { return false }
        return node.schedulerActions[slot]?.isValid == true
            || node.allSchedulerModelEntrys.values.contains { $0[slot]?.isValid == true }
    }

    func deletionIsSynchronized(on node: Node) -> Bool {
        guard !nodeSlotsLoadFailed else { return false }
        guard let slot = slot(on: node) else { return nodeSlots != nil }
        return node.observedTimedSlots.map { !$0.contains(slot) } ?? false
    }

    /// Release only references whose old Scene is absent from every observed
    /// Scheduler Model. Unknown/missing identities remain retryable; overlapping
    /// targets may keep their slot after it has been rewritten for the new Scene.
    func reconcilePendingSceneReferences() {
        guard selectTargetType != .profile else { return }
        guard !nodeSlotsLoadFailed else { return }
        let cleared = needDeleteScenes.filter { oldScene in
            guard oldScene.number != sceneNumber,
                  let snapshot = try? SceneTargetResolver.resolve(scene: oldScene),
                  snapshot.unresolved.isEmpty else { return false }
            return (snapshot.targets + snapshot.cleanupTargets).allSatisfy { target in
                let node = target.node
                guard let slot = slot(on: node) else { return nodeSlots != nil }
                guard !node.schedulerSetupModels.isEmpty else { return false }
                return node.schedulerSetupModels.allSatisfy { model in
                    guard let entries = node.allSchedulerModelEntrys[model] else { return false }
                    guard let entry = entries[slot], entry.isValid else { return true }
                    return entry.sceneNumber != oldScene.number
                }
            }
        }.map(\.number)
        guard !cleared.isEmpty else { return }
        let previous = needDeleteSceneNumbers
        needDeleteSceneNumbers.removeAll { cleared.contains($0) }
        if !save() { needDeleteSceneNumbers = previous }
    }

    @discardableResult
    func releaseClearedBinding(on node: Node) -> Bool {
        guard selectTargetType != .profile else { return schedulerResultFailure("protectedProfile", on: node) }
        guard !MeshProxyMessageCommand.shared.isBusy else { return schedulerResultFailure("proxyBusy", on: node) }
        guard let identity = node.timedSchedulerIdentity, let slot = slot(on: node) else {
            return schedulerResultFailure("missingIdentityOrSlot", on: node)
        }
        guard deletionIsSynchronized(on: node) else {
            return schedulerResultFailure(node.observedTimedSlots == nil ? "unknownModels" : "slotStillOccupied", on: node)
        }
        guard nodeSlots?.contains(where: { $0.identity == identity && $0.slot == slot && $0.state == .pendingRemoval }) == true else {
            return schedulerResultFailure("notPendingRemoval", on: node)
        }
        guard node.savePropertys() else { return schedulerResultFailure("releaseNodeSave", on: node) }
        let previous = nodeSlots
        nodeSlots?.removeAll { $0.identity == identity && $0.slot == slot }
        guard save() else { nodeSlots = previous; return schedulerResultFailure("releaseScheduleSave", on: node) }
        return true
    }
}

enum TimedSchedulerBindings {
    enum Failure: Error { case persistence, staleNetwork, invalidMapping, unsupportedProfile, deviceCapacity(String), deviceUnknown(String) }
    struct Plan {
        let meshUUID: String
        let networkID: String
        let schedules: [Schedule]
        let bindings: [Int: [TimedSchedulerNodeSlot]]
    }

    /// Profile targets are retained from cloud, but their topology cannot yet
    /// be rewritten by this App. Unrelated Groups remain editable.
    static func hasProtectedProfile(group: Group, node: Node? = nil) -> Bool {
        let addresses = Set([group.address.address] + [node?.group?.address.address].compactMap { $0 })
        return MeshNetworkManager.instance.schedules.contains { schedule in
            schedule.selectTargetType == .profile && schedule.profiles.contains {
                addresses.contains($0.groupAddress)
            }
        }
    }

    /// Preflight uses candidate schedules and prospective group membership. It
    /// never changes schedules, groups, caches or the database.
    static func prepare(schedules: [Schedule], contextGroups: [Address: Group] = [:],
                        targetOverrides: [Int: Set<Address>] = [:]) throws -> Plan {
        let manager = MeshNetworkManager.instance
        guard let meshUUID = manager.meshNetwork?.uuid.uuidString,
              Set(schedules.map(\.id)).count == schedules.count,
              !schedules.contains(where: \.nodeSlotsLoadFailed) else { throw Failure.invalidMapping }
        let networkID = manager.currentNetworkKey.networkId.hex
        let nodes = manager.realNodes.filter { !$0.schedulerSetupModels.isEmpty }
        var bindings = Dictionary(uniqueKeysWithValues: schedules.map { ($0.id, $0.nodeSlots ?? []) })
        // Resolve old cleanup before allocating anything. A v2 cleanup with no
        // owned slot must not be mistaken for an empty device, even when the
        // node is also a target of the replacement Scene.
        for schedule in schedules {
            guard schedule.needDeleteNodeAddresses.allSatisfy({ address in nodes.contains { $0.primaryUnicastAddress == address } }),
                  schedule.needDeleteGroupAddresses.allSatisfy({ address in manager.groups.contains { $0.address.address == address } }),
                  schedule.needDeleteSceneNumbers.allSatisfy({ number in manager.scenes.contains { $0.number == number } }) else {
                throw Failure.invalidMapping
            }
            var cleanup = nodes.filter { schedule.needDeleteNodeAddresses.contains($0.primaryUnicastAddress) }
            cleanup += manager.groups.filter { schedule.needDeleteGroupAddresses.contains($0.address.address) }.flatMap(\.nodes)
            for scene in manager.scenes where schedule.needDeleteSceneNumbers.contains(scene.number) {
                let snapshot = try SceneTargetResolver.resolveForSyncRead(scene: scene)
                guard snapshot.unresolved.isEmpty else { throw Failure.invalidMapping }
                cleanup += (snapshot.targets + snapshot.cleanupTargets).map(\.node)
            }
            if schedule.nodeSlots != nil {
                guard cleanup.filter({ !$0.schedulerSetupModels.isEmpty }).allSatisfy({ schedule.slot(on: $0) != nil }) else {
                    throw Failure.invalidMapping
                }
            }
        }
        for node in nodes {
            guard let identity = node.timedSchedulerIdentity else { throw Failure.invalidMapping }
            let observed = node.observedTimedSlots
            let intents = try schedules.map { schedule -> TimedSchedulerSlotPolicy.Intent in
                let existing = (schedule.nodeSlots ?? []).filter { $0.identity == identity }
                guard existing.count <= 1 else { throw Failure.invalidMapping }
                let preservesBinding = schedule.selectTargetType == .profile
                let target = !preservesBinding && (targetOverrides[schedule.id]?.contains(node.primaryUnicastAddress)
                    ?? schedule.targets(node: node, contextGroup: contextGroups[node.primaryUnicastAddress]))
                var binding = existing.first
                // A prior failed deletion confirmed empty by a complete read can
                // finish without sending another clear. Never reuse in-flight slots.
                if !preservesBinding, !target, binding?.state == .pendingRemoval,
                   let slot = binding?.slot, observed?.contains(slot) == false,
                   !MeshProxyMessageCommand.shared.isBusy {
                    binding = nil
                }
                return .init(scheduleID: schedule.id, targetsNode: target,
                             legacy: schedule.nodeSlots == nil, binding: binding, preservesBinding: preservesBinding)
            }
            let nodePlan: [Int: TimedSchedulerNodeSlot]
            do {
                nodePlan = try TimedSchedulerSlotPolicy.plan(identity: identity, intents: intents, observedSlots: observed)
            } catch TimedSchedulerSlotPolicy.Failure.capacityExceeded {
                throw Failure.deviceCapacity(node.name ?? node.primaryUnicastAddress.hex)
            } catch TimedSchedulerSlotPolicy.Failure.unknownCapacity {
                throw Failure.deviceUnknown(node.name ?? node.primaryUnicastAddress.hex)
            }
            for schedule in schedules {
                bindings[schedule.id]?.removeAll { $0.identity == identity }
                if var binding = nodePlan[schedule.id] {
                    // Native Profile bindings are shared read-only results. Local
                    // routing/observations cannot recompute them; only legacy
                    // bindings still need conversion to the v3 representation.
                    if schedule.selectTargetType == .profile, binding.isV3 {
                        bindings[schedule.id]?.append(binding)
                        continue
                    }
                    guard let route = node.timedActionAddress(contextGroup: contextGroups[node.primaryUnicastAddress]) else {
                        throw Failure.invalidMapping
                    }
                    let previous = schedule.nodeSlots?.first { $0.identity == identity }
                    binding.actionAddress = binding.state == .pendingRemoval ? (previous?.actionAddress ?? route) : route
                    if binding.state != .pendingRemoval {
                        // Preserve unchanged confirmed work. New/changed intent,
                        // legacy observations and unknown Models need confirmation.
                        binding.state = schedule.schedulerSyncDifference(on: node,
                                contextGroup: contextGroups[node.primaryUnicastAddress]) == .synchronized
                            ? .synced : .pendingApply
                    }
                    bindings[schedule.id]?.append(binding)
                }
            }
        }
        // Old cleanup references must be resolvable before dropping their
        // only durable description. A v2 missing slot cannot be guessed.
        for schedule in schedules {
            guard bindings[schedule.id]?.allSatisfy({ binding in
                binding.isV3 && nodes.contains { $0.timedSchedulerIdentity == binding.identity }
            }) == true else { throw Failure.invalidMapping }
        }
        return .init(meshUUID: meshUUID, networkID: networkID, schedules: schedules, bindings: bindings)
    }

    static func showFailure(_ error: Error) {
        if error is SceneCapacity.Failure { SceneCapacity.showFailure(error); return }
        let message: String
        switch error {
        case Failure.unsupportedProfile:
            message = "timed_profile_topology_unavailable".localizedString
        case Failure.deviceCapacity(let name):
            message = String(format: "timed_device_capacity_exceeded".localizedString, name)
        case Failure.deviceUnknown(let name):
            message = String(format: "timed_device_capacity_unknown".localizedString, name)
        default: message = "save_failure".localizedString
        }
        XWHUDManager.showTipHUD(message, isLineFeed: true)
    }

    /// Use prospective membership, including removals, before a topology edit.
    static func prepareTopology(group: Group? = nil, members: [Node] = [], addingMembers: [Node] = [],
                                scene: Scene? = nil, sceneGroups: [Group] = [],
                                sceneSnapshot: SceneTargetSnapshot? = nil, requiresSceneRegister: Bool = true) throws -> Plan {
        if let group, hasProtectedProfile(group: group)
            || addingMembers.contains(where: { hasProtectedProfile(group: group, node: $0) }) {
            throw Failure.unsupportedProfile
        }
        try SceneCapacity.validateTopology(group: group, members: members, addingMembers: addingMembers,
                                           scene: scene, sceneGroups: sceneGroups, sceneSnapshot: sceneSnapshot,
                                           requiresObservation: requiresSceneRegister)
        let targets = try topologyTargets(group: group, members: members, addingMembers: addingMembers,
                                          scene: scene, sceneGroups: sceneGroups, sceneSnapshot: sceneSnapshot)
        return try prepare(schedules: MeshNetworkManager.instance.schedules, targetOverrides: targets)
    }

    static func topologyTargets(group: Group? = nil, members: [Node] = [], addingMembers: [Node] = [],
                                scene: Scene? = nil, sceneGroups: [Group] = [],
                                sceneSnapshot: SceneTargetSnapshot? = nil) throws -> [Int: Set<Address>] {
        let manager = MeshNetworkManager.instance
        var targets: [Int: Set<Address>] = [:]
        for schedule in manager.schedules {
            let usesSnapshot = sceneSnapshot != nil && sceneSnapshot?.number == schedule.scene?.number
            let groups = schedule.groups + (usesSnapshot ? [] : (schedule.scene == scene && scene != nil
                ? sceneGroups : schedule.activeSceneGroups))
            var addresses = Set(schedule.nodeAddresses)
            if let targetScene = schedule.scene {
                let snapshot: SceneTargetSnapshot
                if let sceneSnapshot, sceneSnapshot.number == targetScene.number {
                    snapshot = sceneSnapshot
                } else { snapshot = try SceneTargetResolver.resolve(scene: targetScene) }
                if usesSnapshot || snapshot.comparison.kind == .devices {
                    addresses.formUnion(snapshot.targets.map { $0.node.primaryUnicastAddress })
                }
            }
            for target in groups {
                let nodes = target == group ? members : target.nodes
                // Failed unsubscription can leave exiting nodes in Group.nodes.
                // Only an explicit addition to this edited group revives them.
                addresses.formUnion(nodes.filter {
                    $0.groupState != .exitFailure || (target == group && addingMembers.contains($0))
                }.map(\.primaryUnicastAddress))
            }
            targets[schedule.id] = addresses
        }
        return targets
    }

    /// A read is needed only for a genuinely new reservation. Existing ownership
    /// and removals remain editable when all Models or the Mesh are offline.
    static func nodesRequiringTopologyRead(sceneSnapshot: SceneTargetSnapshot) throws -> [Node] {
        let manager = MeshNetworkManager.instance
        let targets = try topologyTargets(sceneSnapshot: sceneSnapshot)
        return manager.realNodes.filter { node in
            guard !node.schedulerSetupModels.isEmpty, node.observedTimedSlots == nil else { return false }
            return manager.schedules.contains { schedule in
                guard targets[schedule.id]?.contains(node.primaryUnicastAddress) == true else { return false }
                if schedule.nodeSlots == nil { return !schedule.targets(node: node) }
                return schedule.nodeSlots?.contains { $0.identity == node.timedSchedulerIdentity && $0.isValid } != true
            }
        }
    }

    static func canAddDevice(to group: Group, node: Node? = nil) -> Bool {
        if hasProtectedProfile(group: group, node: node) {
            showFailure(Failure.unsupportedProfile)
            return false
        }
        if let node, !SceneCapacity.canAddDevice(to: group, node: node) { return false }
        // Composition is required before applying a Scheduler capacity limit.
        guard let node, !node.schedulerSetupModels.isEmpty else { return true }
        let schedules = MeshNetworkManager.instance.schedules.filter {
            $0.groupAddresses.contains(group.address.address) || $0.activeSceneGroups.contains(group)
        }
        guard schedules.count <= 16 else {
            showFailure(Failure.deviceCapacity(node.name ?? node.primaryUnicastAddress.hex))
            return false
        }
        return true
    }

    static func reserveGroup(_ group: Group, node: Node) -> Bool {
        guard !hasProtectedProfile(group: group, node: node) else { return false }
        do {
            try SceneCapacity.validateTopology(group: group,
                members: group.nodes.filter { $0 !== node } + [node], addingMembers: [node])
            try commit(prepare(schedules: MeshNetworkManager.instance.schedules,
                               contextGroups: [node.primaryUnicastAddress: group]))
            return true
        } catch { return false }
    }

    /// Persist user intent and its upload revision together. Device observations
    /// and ordinary preparation use commit's default, without publishing intent.
    static func withLocalChange(_ changes: () throws -> Void) throws {
        let manager = MeshNetworkManager.instance
        guard let meshUUID = manager.meshNetwork?.uuid.uuidString,
              SunSmartDataManager.shared.db != nil else { throw Failure.staleNetwork }
        let networkID = manager.currentNetworkKey.networkId.hex
        guard let space = SpaceData.load(subNetworkId: networkID), space.meshUUID == meshUUID else {
            throw Failure.staleNetwork
        }
        func storedConfiguration() throws -> Data {
            let schedules = Schedule.load(meshUUID: meshUUID, meshNetworkId: networkID)
            let encoder = JSONEncoder()
            var rows = try JSONSerialization.jsonObject(with: encoder.encode(schedules)) as! [[String: Any]]
            for index in rows.indices {
                if let slots = rows[index]["nodeSlots"] as? [[String: Any]] {
                    rows[index]["nodeSlots"] = slots.sorted {
                        let lhs = $0["identity"] as? [String: Any], rhs = $1["identity"] as? [String: Any]
                        return (lhs?["nodeUUID"] as? String ?? "") < (rhs?["nodeUUID"] as? String ?? "")
                    }
                }
            }
            rows.sort { ($0["id"] as? Int ?? -1) < ($1["id"] as? Int ?? -1) }
            return try JSONSerialization.data(withJSONObject: rows, options: .sortedKeys)
        }
        let saved = SunSmartDataManager.shared.configurationTransaction {
            let before = try storedConfiguration()
            try changes()
            guard before != (try storedConfiguration()) else { return }
            space.markLocalChangePendingCloudSync()
            guard space.save() else { throw Failure.persistence }
        }
        guard saved else { throw Failure.persistence }
    }

    /// Persist the complete reservation before any device message is constructed.
    static func commit(_ plan: Plan, markCloudChange: Bool = false, applying changes: () throws -> Void = {}) throws {
        let manager = MeshNetworkManager.instance
        guard manager.meshNetwork?.uuid.uuidString == plan.meshUUID,
              manager.currentNetworkKey.networkId.hex == plan.networkID,
              let db = SunSmartDataManager.shared.db else { throw Failure.staleNetwork }
        let previous = plan.schedules.map { ($0.nodeSlots, $0.needDeleteNodeAddresses, $0.needDeleteGroupAddresses, $0.needDeleteSceneNumbers) }
        if !plan.schedules.isEmpty {
            guard let space = SpaceData.load(subNetworkId: plan.networkID), space.meshUUID == plan.meshUUID else {
                throw Failure.staleNetwork
            }
            guard !SpaceConfigurationSafety.needsTimedUpgradeBaseline(space) else { throw Failure.persistence }
        }
        do {
            func persist() throws {
                try db.savepoint {
                    for schedule in plan.schedules {
                        schedule.nodeSlots = plan.bindings[schedule.id] ?? []
                        for binding in schedule.nodeSlots! where binding.state == .synced {
                            guard let node = manager.realNodes.first(where: { $0.timedSchedulerIdentity == binding.identity }),
                                  node.savePropertys() else { throw Failure.persistence }
                        }
                        schedule.needDeleteNodeAddresses = []
                        schedule.needDeleteGroupAddresses = []
                        schedule.needDeleteSceneNumbers = []
                        guard schedule.save(meshUUID: plan.meshUUID, meshNetworkId: plan.networkID) else {
                            throw Failure.persistence
                        }
                    }
                    if !plan.schedules.isEmpty {
                        guard let space = SpaceData.load(subNetworkId: plan.networkID), space.meshUUID == plan.meshUUID else {
                            throw Failure.staleNetwork
                        }
                        space.timedSchemaVersion = 3
                        guard space.save() else { throw Failure.persistence }
                    }
                    try changes()
                }
            }
            if markCloudChange { try withLocalChange(persist) }
            else { try persist() }
        } catch {
            for (schedule, old) in zip(plan.schedules, previous) {
                schedule.nodeSlots = old.0
                schedule.needDeleteNodeAddresses = old.1
                schedule.needDeleteGroupAddresses = old.2
                schedule.needDeleteSceneNumbers = old.3
            }
            throw error
        }
    }

    static func reserveForDeletion(schedule: Schedule, node: Node? = nil) -> Bool {
        guard schedule.selectTargetType != .profile else { return false }
        guard !schedule.nodeSlotsLoadFailed else { return false }
        if schedule.nodeSlots == nil || schedule.nodeSlots?.contains(where: { !$0.isV3 }) == true {
            do {
                try commit(prepare(schedules: MeshNetworkManager.instance.schedules))
            } catch { return false }
        }
        guard schedule.nodeSlots != nil else { return false }
        guard let node else { return true }
        guard let identity = node.timedSchedulerIdentity else { return false }
        let matches = schedule.nodeSlots!.indices.filter { schedule.nodeSlots![$0].identity == identity }
        guard !matches.isEmpty else { return true }
        guard matches.count == 1, let index = matches.first,
              schedule.nodeSlots![index].isValid else { return false }
        guard schedule.nodeSlots![index].state != .pendingRemoval else { return true }
        // Group exit also uses this entry point, without deleting the Schedule.
        // Keep other nodes and this task's slot and identity intact until clearing.
        let previous = schedule.nodeSlots
        schedule.nodeSlots![index].state = .pendingRemoval
        guard schedule.save() else { schedule.nodeSlots = previous; return false }
        return true
    }

    static func reserveForSending(schedule: Schedule, node: Node, contextGroup: Group?) -> Bool {
        guard schedule.selectTargetType != .profile else { return false }
        guard schedule.targets(node: node, contextGroup: contextGroup) else { return false }
        if let identity = node.timedSchedulerIdentity,
           schedule.nodeSlots?.contains(where: { $0.identity == identity && $0.isV3 && $0.state != .pendingRemoval
               && $0.actionAddress == node.timedActionAddress(contextGroup: contextGroup) }) == true {
            guard let slot = schedule.slot(on: node) else { return false }
            let previous = schedule.nodeSlots
            if let index = schedule.nodeSlots?.firstIndex(where: { $0.identity == identity }), schedule.nodeSlots![index].state != .pendingApply {
                schedule.nodeSlots![index].state = .pendingApply
                guard schedule.save() else { schedule.nodeSlots = previous; return false }
            }
            return !MeshNetworkManager.instance.schedules.contains { $0.id != schedule.id && $0.slot(on: node) == slot }
        }
        var schedules = MeshNetworkManager.instance.schedules
        if let index = schedules.firstIndex(where: { $0.id == schedule.id }) { schedules[index] = schedule }
        else { schedules.append(schedule) }
        do {
            let contexts = contextGroup.map { [node.primaryUnicastAddress: $0] } ?? [:]
            try commit(prepare(schedules: schedules, contextGroups: contexts))
            return schedule.slot(on: node) != nil
        } catch { return false }
    }
}

final class TimedSchedulerMessageContext {
    let meshUUID: String
    let networkID: String
    let scheduleID: Int
    let binding: TimedSchedulerNodeSlot

    init?(schedule: Schedule, node: Node) {
        guard let meshUUID = node.network?.uuid.uuidString, let networkID = node.subNetworkId,
              let identity = node.timedSchedulerIdentity,
              let binding = schedule.nodeSlots?.first(where: { $0.identity == identity }) else { return nil }
        self.meshUUID = meshUUID
        self.networkID = networkID
        scheduleID = schedule.id
        self.binding = binding
    }

    func matches(node: Node) -> Bool {
        guard node.network?.uuid.uuidString == meshUUID, node.subNetworkId == networkID,
              node.timedSchedulerIdentity == binding.identity,
              MeshNetworkManager.instance.meshNetwork?.uuid.uuidString == meshUUID,
              MeshNetworkManager.instance.currentNetworkKey.networkId.hex == networkID else { return false }
        return MeshNetworkManager.instance.schedules.first { $0.id == scheduleID && $0.selectTargetType != .profile }?.nodeSlots?
            .contains { $0.identity == binding.identity && $0.slot == binding.slot
                && ($0.state == .pendingRemoval) == (binding.state == .pendingRemoval)
                && $0.actionAddress == binding.actionAddress } == true
    }
}

private var timedSchedulerContextKey: UInt8 = 0
extension MeshMessageHandle {
    var timedSchedulerContext: TimedSchedulerMessageContext? {
        get { objc_getAssociatedObject(self, &timedSchedulerContextKey) as? TimedSchedulerMessageContext }
        set { objc_setAssociatedObject(self, &timedSchedulerContextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
