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

    func timedSchedule(at slot: Int) -> Schedule? {
        let matching = MeshNetworkManager.instance.schedules.filter { $0.slot(on: self) == slot }
        return matching.count == 1 ? matching.first : nil
    }

    /// Preserve captured task ownership before updating App state from a reply.
    func applyMessageHandle(_ handle: MeshMessageHandle, isSuccess: Bool = true) {
        if let context = handle.timedSchedulerContext, !context.matches(node: self) { return }
        updateData(message: handle.message, isSuccess: isSuccess, model: handle.model)
    }
}

extension Schedule {
    var activeSceneGroups: [Group] {
        guard let scene else { return [] }
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

    func releaseClearedBinding(on node: Node) {
        guard !MeshProxyMessageCommand.shared.isBusy,
              let identity = node.timedSchedulerIdentity, let slot = slot(on: node),
              deletionIsSynchronized(on: node),
              nodeSlots?.contains(where: { $0.identity == identity && $0.slot == slot && $0.state == .pendingRemoval }) == true else { return }
        let previous = nodeSlots
        nodeSlots?.removeAll { $0.identity == identity && $0.slot == slot }
        if !save() { nodeSlots = previous }
    }
}

enum TimedSchedulerBindings {
    enum Failure: Error { case persistence, staleNetwork, invalidMapping, deviceCapacity(String), deviceUnknown(String) }
    struct Plan {
        let meshUUID: String
        let networkID: String
        let schedules: [Schedule]
        let bindings: [Int: [TimedSchedulerNodeSlot]]
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
        for node in nodes {
            guard let identity = node.timedSchedulerIdentity else { throw Failure.invalidMapping }
            let observed = node.observedTimedSlots
            let intents = try schedules.map { schedule -> TimedSchedulerSlotPolicy.Intent in
                let existing = (schedule.nodeSlots ?? []).filter { $0.identity == identity }
                guard existing.count <= 1 else { throw Failure.invalidMapping }
                let target = targetOverrides[schedule.id]?.contains(node.primaryUnicastAddress)
                    ?? schedule.targets(node: node, contextGroup: contextGroups[node.primaryUnicastAddress])
                var binding = existing.first
                // A prior failed deletion confirmed empty by a complete read can
                // finish without sending another clear. Never reuse in-flight slots.
                if !target, binding?.state == .pendingRemoval,
                   let slot = binding?.slot, observed?.contains(slot) == false,
                   !MeshProxyMessageCommand.shared.isBusy {
                    binding = nil
                }
                return .init(scheduleID: schedule.id, targetsNode: target,
                             legacy: schedule.nodeSlots == nil, binding: binding)
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
                if let binding = nodePlan[schedule.id] { bindings[schedule.id]?.append(binding) }
            }
        }
        return .init(meshUUID: meshUUID, networkID: networkID, schedules: schedules, bindings: bindings)
    }

    static func showFailure(_ error: Error) {
        let message: String
        switch error {
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
                                scene: Scene? = nil, sceneGroups: [Group] = []) throws -> Plan {
        let manager = MeshNetworkManager.instance
        var targets: [Int: Set<Address>] = [:]
        for schedule in manager.schedules {
            let groups = schedule.groups + (schedule.scene == scene && scene != nil
                ? sceneGroups : schedule.activeSceneGroups)
            var addresses = Set(schedule.nodeAddresses)
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
        return try prepare(schedules: manager.schedules, targetOverrides: targets)
    }

    static func canAddDevice(to group: Group, node: Node? = nil) -> Bool {
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
        do {
            try commit(prepare(schedules: MeshNetworkManager.instance.schedules,
                               contextGroups: [node.primaryUnicastAddress: group]))
            return true
        } catch { return false }
    }

    /// Persist the complete reservation before any device message is constructed.
    static func commit(_ plan: Plan, applying changes: () throws -> Void = {}) throws {
        let manager = MeshNetworkManager.instance
        guard manager.meshNetwork?.uuid.uuidString == plan.meshUUID,
              manager.currentNetworkKey.networkId.hex == plan.networkID,
              let db = SunSmartDataManager.shared.db else { throw Failure.staleNetwork }
        let previous = plan.schedules.map(\.nodeSlots)
        if !plan.schedules.isEmpty {
            guard let space = SpaceData.load(subNetworkId: plan.networkID), space.meshUUID == plan.meshUUID else {
                throw Failure.staleNetwork
            }
            guard !SpaceConfigurationSafety.needsTimedUpgradeBaseline(space) else { throw Failure.persistence }
        }
        do {
            try db.savepoint {
                for schedule in plan.schedules {
                    schedule.nodeSlots = plan.bindings[schedule.id] ?? []
                    guard schedule.save(meshUUID: plan.meshUUID, meshNetworkId: plan.networkID) else {
                        throw Failure.persistence
                    }
                }
                if !plan.schedules.isEmpty {
                    guard let space = SpaceData.load(subNetworkId: plan.networkID), space.meshUUID == plan.meshUUID else {
                        throw Failure.staleNetwork
                    }
                    space.timedSchemaVersion = 2
                    guard space.save() else { throw Failure.persistence }
                }
                try changes()
            }
        } catch {
            for (schedule, bindings) in zip(plan.schedules, previous) { schedule.nodeSlots = bindings }
            throw error
        }
    }

    static func reserveForDeletion(schedule: Schedule, node: Node? = nil) -> Bool {
        guard !schedule.nodeSlotsLoadFailed else { return false }
        if schedule.nodeSlots == nil {
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
        // Keep other nodes and this task's slot/generation intact until clearing.
        let previous = schedule.nodeSlots
        schedule.nodeSlots![index].state = .pendingRemoval
        guard schedule.save() else { schedule.nodeSlots = previous; return false }
        return true
    }

    static func reserveForSending(schedule: Schedule, node: Node, contextGroup: Group?) -> Bool {
        guard schedule.targets(node: node, contextGroup: contextGroup) else { return false }
        if let identity = node.timedSchedulerIdentity,
           schedule.nodeSlots?.contains(where: { $0.identity == identity && $0.state == .assigned }) == true {
            guard let slot = schedule.slot(on: node) else { return false }
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
        return MeshNetworkManager.instance.schedules.first { $0.id == scheduleID }?.nodeSlots?
            .contains { $0.identity == binding.identity && $0.slot == binding.slot && $0.generation == binding.generation } == true
    }
}

private var timedSchedulerContextKey: UInt8 = 0
extension MeshMessageHandle {
    var timedSchedulerContext: TimedSchedulerMessageContext? {
        get { objc_getAssociatedObject(self, &timedSchedulerContextKey) as? TimedSchedulerMessageContext }
        set { objc_setAssociatedObject(self, &timedSchedulerContextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
