import Foundation
import NordicSigMeshSDK

/// The Scene tombstone owns the complete cleanup, including devices outside its light members.
enum SceneDeletionCascade {
    typealias Failure = SceneConfigurationStore.Failure

    struct Preparation {
        var references = SceneDeletionReferences()
        var schedules: [Schedule] = []
        var switches: [DeviceSwitchData] = []
        var emergency: [DeviceEmerFireData] = []
        let scope: SceneScope

        func persist() throws {
            for schedule in schedules {
                guard schedule.save(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID) else { throw Failure.persistence }
            }
            for item in switches {
                guard item.save(meshUUID: scope.meshUUID, networkId: scope.networkID) else { throw Failure.persistence }
                if let power = item as? PJEightKeySwitchData {
                    guard PJEightKeySwitchRepository.shared.save(power, meshUUID: scope.meshUUID, networkId: scope.networkID) else { throw Failure.persistence }
                }
            }
            for item in emergency {
                guard item.save(meshUUID: scope.meshUUID, networkId: scope.networkID) else { throw Failure.persistence }
            }
        }

        func install() {
            let manager = MeshNetworkManager.instance
            for item in schedules {
                if let i = manager.schedules.firstIndex(where: { $0.id == item.id }) { manager.schedules[i] = item }
            }
            for item in switches {
                if let i = manager.switchs.firstIndex(where: { $0.id == item.id }) { manager.switchs[i] = item }
            }
            if !emergency.isEmpty {
                _ = DeviceEmerFireStore.shared.loadDevices(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
                NotificationCenter.default.post(name: .deviceEmerFireDataDidChange, object: nil)
            }
            manager.realNodes.forEach { $0.clearSyncStateCache() }
        }
    }

    static func prepare(scene: Scene, snapshot: SceneTargetSnapshot, additionalNodes: [Node] = []) throws -> Preparation {
        let manager = MeshNetworkManager.instance
        var result = Preparation(scope: snapshot.scope)
        var schedulerTargets: [TimedSchedulerNodeIdentity: Set<Int>] = [:]
        func capture(_ node: Node, slot: Int? = nil) throws {
            guard !node.schedulerSetupModels.isEmpty else { return }
            guard let identity = node.sceneConfigurationIdentity else { throw Failure.invalidTargets }
            if schedulerTargets[identity] == nil { schedulerTargets[identity] = [] }
            if let slot { schedulerTargets[identity, default: []].insert(slot) }
        }
        for target in snapshot.targets + snapshot.cleanupTargets { try capture(target.node) }
        for node in additionalNodes { try capture(node) }
        for old in manager.schedules where old.sceneNumber == scene.number || old.needDeleteSceneNumbers.contains(scene.number) {
            guard old.selectTargetType != .profile, !old.nodeSlotsLoadFailed else { throw Failure.invalidTargets }
            let deleting = old.sceneNumber == scene.number
            for node in old.existNodes { try capture(node, slot: deleting ? old.slot(on: node) : nil) }
            if deleting {
                let copy = old.copy()
                // Timed bindings retain their original identity format; only Scene references use canonical identity.
                // Capture legacy slot ownership before clearing targets; no capacity allocation is needed for deletion.
                if copy.nodeSlots == nil {
                    copy.nodeSlots = try old.existNodes.filter { !$0.schedulerSetupModels.isEmpty }.map { node in
                        guard let identity = node.timedSchedulerIdentity, let slot = old.slot(on: node) else { throw Failure.invalidTargets }
                        return .init(identity: identity, slot: slot, state: .pendingRemoval)
                    }
                }
                for binding in copy.nodeSlots ?? [] {
                    schedulerTargets[try SceneConfiguration.identity(binding.identity), default: []].insert(binding.slot)
                }
                copy.action = .noAction
                copy.needDeleteNodeAddresses = Array(Set(copy.needDeleteNodeAddresses + old.existNodes.map(\.primaryUnicastAddress)))
                copy.nodeAddresses = []; copy.groupAddresses = []; copy.sceneNumber = nil
                copy.needDeleteGroupAddresses = Array(Set(copy.needDeleteGroupAddresses + old.groupAddresses))
                copy.needDeleteSceneNumbers = Array(Set(copy.needDeleteSceneNumbers + [scene.number]))
                copy.nodeSlots = copy.nodeSlots?.map { var binding = $0; binding.state = .pendingRemoval; return binding }
                result.references.scheduleIDs.append(copy.id)
                result.schedules.append(copy)
            }
        }
        // Known orphan recalls must also be cleared even if their business target was removed earlier.
        for node in manager.realNodes where node.allSchedulerModelEntrys.values.contains(where: { entries in
            entries.values.contains { $0.isValid && $0.sceneNumber == scene.number }
        }) { try capture(node) }
        for (identity, slots) in schedulerTargets {
            guard let address = Address(identity.unicastAddress, radix: 16) else { throw Failure.invalidTargets }
            let node = manager.realNodes.first { $0.sceneConfigurationIdentity == identity }
            result.references.pending.append(.init(kind: .scheduler, identity: identity, address: address,
                name: node?.name ?? identity.unicastAddress, slots: slots.sorted()))
        }
        for old in manager.switchs {
            let oldPower = (old as? PJEightKeySwitchData) ?? PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: old)
            let appliedNumbers = oldPower.map { appliedScenes($0.appliedConfigHash) } ?? []
            let observedKeys = manager.realNodes.filter { $0.enOceanMacAddress == old.enOceanMacAddress && old.enOceanMacAddress != nil }
                .flatMap(\.enOceanProxySwitchKeys)
            let observedReference = observedKeys.contains { key in
                if case .sceneRecall(let number, _) = key.shortPressAction { return number == scene.number }
                return false
            }
            guard sceneNumbers(old).contains(scene.number) || appliedNumbers.contains(scene.number) || observedReference else { continue }
            let power = (old as? PJEightKeySwitchData) ?? PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: old)
            let copy: DeviceSwitchData = power?.copy() ?? old.copy()
            var keyIndexes = (old.switchKeys + observedKeys).filter { key in
                if case .sceneRecall(let number, _) = key.shortPressAction { return number == scene.number }
                return false
            }.map(\.key)
            let desired = [old.sceneANumber, old.sceneBNumber, old.sceneCNumber, old.sceneDNumber]
            if power != nil {
                keyIndexes = (0..<4).filter { desired[$0] == scene.number || (appliedNumbers.indices.contains($0) && appliedNumbers[$0] == scene.number) }
            } else {
                // switchKeys is empty after group removal; the saved panel mapping still owns these old short presses.
                let mapped: [Int]
                switch old.panelType {
                case .default_4key: mapped = [2, 1]
                case .default_2key: mapped = []
                case .scenes_4key: mapped = [4, 3, 2, 1]
                case .scenes_2key: mapped = [4, 3]
                }
                keyIndexes += mapped.enumerated().compactMap { desired[$0.offset] == scene.number ? $0.element : nil }
            }
            if copy.sceneANumber == scene.number { copy.sceneANumber = nil }
            if copy.sceneBNumber == scene.number { copy.sceneBNumber = nil }
            if copy.sceneCNumber == scene.number { copy.sceneCNumber = nil }
            if copy.sceneDNumber == scene.number { copy.sceneDNumber = nil }
            if let power = copy as? PJEightKeySwitchData {
                power.prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: manager.currentApplicationKey.index)
            }
            let observedProxies = manager.realNodes.filter { $0.enOceanMacAddress == old.enOceanMacAddress && old.enOceanMacAddress != nil }.map(\.primaryUnicastAddress)
            for address in Set([old.proxyNodeAddress, old.deleteProxyNodeAddress].compactMap({ $0 }) + observedProxies) where !keyIndexes.isEmpty {
                let node = manager.realNodes.first { $0.primaryUnicastAddress == address }
                result.references.pending.append(.init(kind: power == nil ? .kinetic : .powerSwitch,
                    identity: node?.sceneConfigurationIdentity, address: address, objectID: old.id,
                    name: old.name, keys: Array(Set(keyIndexes)).sorted()))
            }
            result.switches.append(copy)
        }
        for old in DeviceEmerFireRepository.shared.load(meshUUID: snapshot.scope.meshUUID, meshNetworkId: snapshot.scope.networkID) {
            let copy = old.copy()
            var states: [Int] = []
            if copy.configuration.powerLossSettings.triggerActionPreset == .sceneRecall(scene.number) {
                copy.configuration.powerLossSettings.triggerActionPreset = .invalid; states.append(0)
            }
            if copy.configuration.fireAlarmSettings.triggerActionPreset == .sceneRecall(scene.number) {
                copy.configuration.fireAlarmSettings.triggerActionPreset = .invalid; states.append(1)
            }
            guard !states.isEmpty else { continue }
            if let address = copy.bindNodeAddress {
                result.references.pending.append(.init(kind: .emergency, identity: copy.bindNode?.sceneConfigurationIdentity,
                    address: address, objectID: copy.id, name: copy.name, keys: states))
            }
            result.emergency.append(copy)
        }
        result.references.scheduleIDs.sort()
        result.references.pending.sort { $0.address == $1.address ? $0.id.uuidString < $1.id.uuidString : $0.address < $1.address }
        return result
    }

    /// Older deletion intents could miss residual nodes when raw Timed identities were compared with Scene identities.
    /// Only revisit identities still waiting for physical Scene removal; completed removals never acquire new work.
    static func restoringSchedulerCoverage(_ configuration: SceneConfiguration, nodes: [Node]) throws -> SceneConfiguration {
        var updated = try configuration.normalized()
        guard updated.isDeleting, updated.deletionReferences != nil else { return updated }
        let pendingRemovals = Set(updated.pendingOperations.filter { $0.action == .remove }.map(\.identity))
        var captured = Set(updated.deletionReferences!.pending.filter { $0.kind == .scheduler }.compactMap(\.identity))
        for node in nodes where !node.schedulerSetupModels.isEmpty {
            guard let identity = node.sceneConfigurationIdentity,
                  pendingRemovals.contains(identity), captured.insert(identity).inserted else { continue }
            updated.deletionReferences?.pending.append(.init(kind: .scheduler, identity: identity,
                address: node.primaryUnicastAddress, name: node.name ?? identity.unicastAddress))
        }
        return try updated.normalized()
    }

    static func appliedScenes(_ hash: String) -> [SceneNumber?] {
        guard let value = hash.split(separator: "|").first(where: { $0.hasPrefix("scenes=") }) else { return [] }
        return value.dropFirst(7).split(separator: ",", omittingEmptySubsequences: false).map { SceneNumber($0) }
    }

    static func sceneNumbers(_ item: DeviceSwitchData) -> [SceneNumber] {
        [item.sceneANumber, item.sceneBNumber, item.sceneCNumber, item.sceneDNumber].compactMap { $0 }
    }

    static func confirmationMessage(scene: Scene) -> String {
        var message = "scene_delete_message".localizedString
        guard let snapshot = try? SceneTargetResolver.resolve(scene: scene),
              let impact = try? prepare(scene: scene, snapshot: snapshot) else { return message }
        if !impact.schedules.isEmpty {
            message += "\n\n" + String(format: "scene_delete_timers_impact".localizedString,
                impact.schedules.map(\.name).sorted().joined(separator: "\n"))
        }
        let actions = Array(Set(impact.switches.map(\.name) + impact.emergency.map(\.name))).sorted()
        if !actions.isEmpty {
            message += "\n\n" + String(format: "scene_delete_actions_impact".localizedString, actions.joined(separator: "\n"))
        }
        return message
    }

    static func hasPending(_ info: SceneInfo) -> Bool {
        info.configuration?.deletionReferences?.pending.isEmpty == false
    }

    static func owns(scheduleID: Int) -> Bool {
        MeshNetworkManager.instance.scenes.contains {
            $0.info.configuration?.isDeleting == true && $0.info.configuration?.deletionReferences?.scheduleIDs.contains(scheduleID) == true
        }
    }

    /// A failed final transaction may already have removed the SDK Scene. Its database tombstone still owns the Timed ID.
    static func owns(scheduleID: Int, meshUUID: String, networkID: String) -> Bool {
        guard let infos = try? SceneInfo.loadAll(meshUUID: meshUUID, subnetworkId: networkID) else { return true }
        return infos.contains { $0.configurationLoadFailed || ($0.configuration?.isDeleting == true
            && $0.configuration?.deletionReferences?.scheduleIDs.contains(scheduleID) == true) }
    }

    /// Admission at persistence boundaries also rejects stale editors, not just picker selection.
    static func permitsReferences(_ numbers: [SceneNumber], meshUUID: String, networkID: String) -> Bool {
        guard !numbers.isEmpty else { return true }
        guard let infos = try? SceneInfo.loadAll(meshUUID: meshUUID, subnetworkId: networkID) else { return false }
        return !infos.contains { numbers.contains($0.sceneId) && ($0.configurationLoadFailed || $0.configuration?.isDeleting == true) }
    }

    static func finalizeReferences(info: SceneInfo, scope: SceneScope) throws {
        guard let refs = info.configuration?.deletionReferences else { return }
        guard refs.pending.isEmpty else { throw Failure.invalidTargets }
        let schedules = Schedule.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
        for schedule in schedules where refs.scheduleIDs.contains(schedule.id) {
            guard schedule.action == .noAction, schedule.sceneNumber == nil,
                  schedule.nodeAddresses.isEmpty, schedule.groupAddresses.isEmpty,
                  schedule.deleteData(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID) else { throw Failure.persistence }
        }
        for schedule in schedules where !refs.scheduleIDs.contains(schedule.id) && schedule.needDeleteSceneNumbers.contains(info.sceneId) {
            schedule.needDeleteSceneNumbers.removeAll { $0 == info.sceneId }
            guard schedule.save(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID) else { throw Failure.persistence }
        }
    }

    static func refreshSchedules(scope: SceneScope) {
        MeshNetworkManager.instance.schedules = Schedule.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
    }

    /// Called only by the final whole-switch deletion, after its unbinding flow.
    /// Keep the business record and Scene receipts atomic so a failed save remains retryable.
    static func deleteSwitchRecords(_ item: DeviceSwitchData, scope: SceneScope) -> Bool {
        guard let infos = try? SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) else { return false }
        var updated: [SceneInfo] = []
        let saved = SunSmartDataManager.shared.configurationTransaction {
            for info in infos {
                guard !info.configurationLoadFailed else { throw Failure.persistence }
                guard var configuration = info.configuration, configuration.isDeleting,
                      var references = configuration.deletionReferences else { continue }
                let previousCount = references.pending.count
                references.pending.removeAll {
                    ($0.kind == .kinetic || $0.kind == .powerSwitch) && $0.objectID == item.id
                }
                guard references.pending.count != previousCount else { continue }
                configuration.deletionReferences = references
                info.configuration = configuration
                try info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
                updated.append(info)
            }
            guard item.delete(meshUUID: scope.meshUUID, networkId: scope.networkID) else { throw Failure.persistence }
        }
        guard saved else { return false }
        for info in updated {
            MeshNetworkManager.instance.scenes.first { $0.number == info.sceneId }?.info.configuration = info.configuration
        }
        return true
    }

    /// The old guard remains for legacy deletions. New tombstones use durable cleanup receipts instead of self-blocking references.
    static func canFinish(info: SceneInfo) -> Bool {
        guard let refs = info.configuration?.deletionReferences else {
            return SceneConfigurationStore.deletionReferenceNames(number: info.sceneId).isEmpty
        }
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork else { return false }
        let efcs = DeviceEmerFireRepository.shared.load(meshUUID: network.uuid.uuidString, meshNetworkId: manager.currentNetworkKey.networkId.hex)
        guard !efcs.contains(where: { $0.configuration.powerLossSettings.triggerActionPreset == .sceneRecall(info.sceneId)
            || $0.configuration.fireAlarmSettings.triggerActionPreset == .sceneRecall(info.sceneId) }) else { return false }
        return refs.pending.isEmpty
            && !manager.schedules.contains { $0.sceneNumber == info.sceneId }
            && !manager.switchs.contains { sceneNumbers($0).contains(info.sceneId) }
            && !Schedule.load(meshUUID: network.uuid.uuidString, meshNetworkId: manager.currentNetworkKey.networkId.hex).contains { $0.sceneNumber == info.sceneId }
            && !DeviceSwitchData.load(meshUUID: network.uuid.uuidString, meshNetworkId: manager.currentNetworkKey.networkId.hex).contains { sceneNumbers($0).contains(info.sceneId) }
            && !manager.realNodes.contains { $0.allSchedulerModelEntrys.values.contains { entries in
                entries.values.contains { $0.isValid && $0.sceneNumber == info.sceneId }
            } }
    }

    static func appendTasks(scene: Scene, to section: SyncDevicesSectionModel) -> [SyncDeviceStepModel] {
        guard let references = scene.info.configuration?.deletionReferences else { return [] }
        var dependencies: [SyncDeviceStepModel] = []
        section.prefersDevicesBeforeGroups = true
        for reference in references.pending {
            guard let node = MeshNetworkManager.instance.realNodes.first(where: { $0.sceneConfigurationIdentity == reference.identity && reference.identity != nil }) else {
                #if DEBUG
                print("[SceneSync] stage=referenceUnresolved scene=\(scene.number) address=\(reference.address) kind=\(reference.kind.rawValue) hasIdentity=\(reference.identity != nil)")
                #endif
                continue
            }
            let device = SyncDevicesModel(name: reference.name, address: reference.address)
            device.imageName = node.iconName
            var steps: [SyncDeviceStepModel] = []
            let phases: [SceneDeletionTask.Phase] = reference.kind == .scheduler ? [.read, .apply] : [.apply]
            for phase in phases {
                let cleanup = SceneDeletionTask(scene: scene, reference: reference, node: node, phase: phase)
                let task = SyncDeviceStepTaskModel(name: reference.name, operationType: .configuration(node: node, type: .sceneReferenceCleanup(cleanup)))
                let step = SyncDeviceStepModel(type: "scene_reference_cleanup".localizedString, state: .none, tasks: [task])
                step.relevanceStepModels = steps; step.parentDeviceModel = device; task.parentStepModel = step
                steps.append(step)
            }
            device.steps = steps; section.devices.append(device); dependencies.append(contentsOf: steps)
        }
        return dependencies
    }
}

/// A captured cleanup operation. Read/apply are separate steps in the existing serial execution lane.
final class SceneDeletionTask {
    enum Phase { case read, apply }
    let scene: Scene
    let reference: SceneReferenceRemoval
    let node: Node
    let phase: Phase
    let scope: SceneScope
    let revision: UUID?
    private var snapshot: Data?
    private var prepared = false
    private var appliedPower: PJEightKeySwitchData?
    private var plannedHandles: [MeshMessageHandle] = []
    private var schedulerActionsBeforeRead: [Int: SchedulerRegistryEntry]?
    private var schedulerBitmaps: [Model: UInt16] = [:]
    private var schedulerEntries: [Model: [Int: SchedulerRegistryEntry]] = [:]
    private var receivedSchedulerHandles = Set<ObjectIdentifier>()
    private var readingSchedulerDetails = false
    private(set) var followUpMessageHandles: [MeshMessageHandle] = []
    private(set) var allowsEmpty = false

    init(scene: Scene, reference: SceneReferenceRemoval, node: Node, phase: Phase) {
        self.scene = scene; self.reference = reference; self.node = node; self.phase = phase
        let manager = MeshNetworkManager.instance
        scope = .init(meshUUID: manager.meshNetwork?.uuid.uuidString ?? "", networkID: manager.currentNetworkKey.networkId.hex)
        revision = scene.info.configuration?.revision
    }

    func resetForRetry() {
        invalidateIncompleteSchedulerRead()
        prepared = false; snapshot = nil
        plannedHandles = []; appliedPower = nil; allowsEmpty = false
        schedulerBitmaps = [:]; schedulerEntries = [:]; receivedSchedulerHandles = []
        readingSchedulerDetails = false; followUpMessageHandles = []
    }

    /// The SDK writes each reply immediately. A partial read is not a known register.
    /// Cancellation calls this after transport STOP settles, including replies received while draining.
    func invalidateIncompleteSchedulerRead() {
        guard let actions = schedulerActionsBeforeRead else { return }
        schedulerActionsBeforeRead = nil
        followUpMessageHandles = []
        guard node.sceneConfigurationIdentity == reference.identity else { return }
        var entries = node.allSchedulerModelEntrys
        node.schedulerSetupModels.forEach { entries.removeValue(forKey: $0) }
        node.allSchedulerModelEntrys = entries
        node.schedulerActions = actions
        node.scheduleIds = actions.keys.sorted()
        node.savePropertys()
        node.clearSyncStateCache()
    }

    private func storedSwitch() -> DeviceSwitchData? {
        guard let base = DeviceSwitchData.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
            .first(where: { $0.id == reference.objectID }) else { return nil }
        return PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: base) ?? base
    }

    private func desiredSnapshot() -> Data? {
        let manager = MeshNetworkManager.instance
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        switch reference.kind {
        case .scheduler:
            func configuration(_ schedules: [Schedule]) -> [Schedule] {
                schedules.sorted { $0.id < $1.id }.map { original in
                    let value = original.copy()
                    value.needDeleteNodeAddresses = []; value.needDeleteGroupAddresses = []; value.needDeleteSceneNumbers = []
                    return value
                }
            }
            return try? encoder.encode([configuration(manager.schedules),
                configuration(Schedule.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID))])
        case .kinetic, .powerSwitch:
            guard let live = manager.switchs.first(where: { $0.id == reference.objectID }), let stored = storedSwitch() else { return nil }
            func configuration(_ item: DeviceSwitchData) -> [String] {
                let power = (item as? PJEightKeySwitchData) ?? PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: item)
                // Private ownership/configuration snapshot; never logged or exported.
                return [item.proxyNodeAddress?.hex ?? "", item.deleteProxyNodeAddress?.hex ?? "",
                    item.linkGroupAddress?.hex ?? "", item.subLinkGroupAddress?.hex ?? "", String(item.panelType.rawValue),
                    item.sceneANumber?.hex ?? "", item.sceneBNumber?.hex ?? "", item.sceneCNumber?.hex ?? "", item.sceneDNumber?.hex ?? "",
                    item.enOceanMacAddress ?? "", power?.desiredConfigHash ?? "", power.map { String($0.desiredConfigVersion) } ?? "",
                    String(manager.currentApplicationKey.index)]
            }
            // An old editor can retain a different object; persisted edits also invalidate the captured operation.
            return try? encoder.encode([configuration(live), configuration(stored)])
        case .emergency:
            guard let item = DeviceEmerFireRepository.shared.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
                .first(where: { $0.id == reference.objectID }),
                  let configuration = try? encoder.encode(item.configuration) else { return nil }
            return try? encoder.encode([configuration.base64EncodedString(), item.bindNodeAddress?.hex ?? "",
                item.publishGroupAddress?.hex ?? "", String(manager.currentApplicationKey.index)])
        }
    }

    var isCurrent: Bool {
        let manager = MeshNetworkManager.instance
        guard manager.meshNetwork?.uuid.uuidString == scope.meshUUID, manager.currentNetworkKey.networkId.hex == scope.networkID,
              manager.realNodes.contains(where: { $0 === node }), node.sceneConfigurationIdentity == reference.identity,
              scene.info.configuration?.revision == revision, scene.info.configuration?.isDeleting == true,
              scene.info.configuration?.deletionReferences?.pending.contains(reference) == true else { return false }
        return !prepared || desiredSnapshot() == snapshot
    }

    var activationSwitch: PJEightKeySwitchData? {
        guard phase == .apply, reference.kind == .powerSwitch,
              let item = storedSwitch(),
              let power = (item as? PJEightKeySwitchData) ?? PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: item),
              power.requiresActivationBeforeOwnConfiguration else { return nil }
        let target = power.copy()
        target.proxyNodeAddress = reference.address
        return target
    }

    var messageHandles: [MeshMessageHandle] {
        guard !prepared else { return isCurrent ? plannedHandles : [] }
        guard isCurrent else { return [] }
        snapshot = desiredSnapshot()
        guard snapshot != nil else { return [] }
        do {
            plannedHandles = try makeHandles()
            allowsEmpty = phase == .apply && plannedHandles.isEmpty
            prepared = true
            return plannedHandles
        } catch {
            prepared = true; allowsEmpty = false
            return []
        }
    }

    private func makeHandles() throws -> [MeshMessageHandle] {
        let manager = MeshNetworkManager.instance
        switch reference.kind {
        case .scheduler:
            guard !node.schedulerSetupModels.isEmpty else { throw SceneDeletionCascade.Failure.invalidTargets }
            if phase == .read {
                // First discover occupied slots on every Model; details stay in this same serial task.
                schedulerActionsBeforeRead = node.schedulerActions
                return node.schedulerSetupModels.map { model in
                    MeshMessageHandle(message: SchedulerGet(), model: model)
                }
            }
            let schedules = Schedule.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
            var handles: [MeshMessageHandle] = []
            for model in node.schedulerSetupModels {
                guard let entries = node.allSchedulerModelEntrys[model] else { throw SceneDeletionCascade.Failure.invalidTargets }
                for slot in 0..<16 {
                    guard let entry = entries[slot], entry.isValid,
                          entry.sceneNumber == scene.number || reference.slots.contains(slot) else { continue }
                    let owners = schedules.filter { $0.slot(on: node) == slot }
                    guard owners.count <= 1 else { throw SceneDeletionCascade.Failure.invalidTargets }
                    if let owner = owners.first, !SceneDeletionCascade.owns(scheduleID: owner.id) {
                        guard owner.selectTargetType != .profile else { throw SceneDeletionCascade.Failure.invalidTargets }
                        // Restore the current owner only where it still targets this node. Other Models are cleaned independently.
                        let targetModel = node.schedulerSetupModel(for: owner.schedulerModelOwner(on: node, contextGroup: node.group))
                        let replacement = owner.targets(node: node) && targetModel === model ? owner.schedulerEntry : SchedulerRegistryEntry()
                        handles.append(.init(message: SchedulerActionSet(index: UInt8(slot), entry: replacement), model: model))
                    } else {
                        handles.append(.init(message: SchedulerActionSet(index: UInt8(slot), entry: SchedulerRegistryEntry()), model: model))
                    }
                }
            }
            return handles
        case .kinetic:
            guard let item = storedSwitch(),
                  let mac = item.enOceanMacAddress, let model = node.sunricherVendorModel else { throw SceneDeletionCascade.Failure.invalidTargets }
            // Rewrite only affected short presses. Never disable shared publications or unbind the whole key.
            guard node.enOceanMacAddress == nil || node.enOceanMacAddress == mac else { throw SceneDeletionCascade.Failure.invalidTargets }
            let current = item.proxyNodeAddress == reference.address
            guard current || node.enOceanMacAddress == mac else { throw SceneDeletionCascade.Failure.invalidTargets }
            // A panel/group edit may remove a desired key. Its observed old key still needs its short press cleared.
            let selected = reference.keys.compactMap { index in
                (current ? item.switchKeys.first { $0.key == index } : nil)
                    ?? node.enOceanProxySwitchKeys.first { $0.key == index }
            }
            guard !selected.isEmpty, selected.count == reference.keys.count else { throw SceneDeletionCascade.Failure.invalidTargets }
            return selected.map { old in
                var key = old
                if case .sceneRecall(let number, let address) = key.shortPressAction, number == scene.number {
                    key = SwitchKey(key: old.key, shortPressAction: .sceneRecall(nil, address: address),
                                    longPressAction: old.longPressAction, direction: old.direction)
                }
                return .init(message: SunricherVendorSet(function: .enOceanSwitchKeySet(key: key, macAddress: mac)), model: model)
            }
        case .powerSwitch:
            guard let base = storedSwitch(),
                  let power = (base as? PJEightKeySwitchData) ?? PJEightKeySwitchRepository.shared.makeEightKeySwitch(from: base),
                  let model = node.sunricherVendorModel else { throw SceneDeletionCascade.Failure.invalidTargets }
            var configurations = power.proxyNodeAddress == reference.address
                ? power.batteryPowerSwitchKeyConfigurations(appKeyIndex: manager.currentApplicationKey.index) : []
            if !configurations.isEmpty {
                appliedPower = power.copy()
            } else {
                // Removing the group produces no desired config, but the old device action still must be disabled.
                guard !reference.keys.isEmpty else { throw SceneDeletionCascade.Failure.invalidTargets }
                configurations = try reference.keys.map { index in
                    guard (0..<4).contains(index), let button = UInt8(exactly: index) else { throw SceneDeletionCascade.Failure.invalidTargets }
                    return BatteryPowerSwitchKeyConfiguration(button: button, trigger: .click, type: .disabled,
                        address: power.linkGroupAddress ?? 0x0000, appKeyIndex: manager.currentApplicationKey.index)
                }
            }
            return configurations.map {
                let handle = MeshMessageHandle(message: SunricherVendorSet(function: .batteryPowerSwitchKeyConfig($0)), model: model)
                handle.continuous = false; return handle
            }
        case .emergency:
            guard let item = DeviceEmerFireRepository.shared.load(meshUUID: scope.meshUUID, meshNetworkId: scope.networkID)
                .first(where: { $0.id == reference.objectID }),
                  item.bindNodeAddress == reference.address, let model = node.sunricherVendorModel else { throw SceneDeletionCascade.Failure.invalidTargets }
            return reference.keys.map { state in
                let config = item.configuration.actionConfig(for: state == 0 ? .emergencyTrigger : .fireTrigger,
                    targetAddress: item.publishGroupAddress, appKeyIndex: manager.currentApplicationKey.index,
                    ttl: DeviceEmerFireData.emergencyActionTTL)
                return .init(message: SunricherVendorSet(function: .emergencyActionConfig(config)), model: model)
            }
        }
    }

    func receive(handle: MeshMessageHandle, status: StaticMeshMessage) {
        guard reference.kind == .scheduler, phase == .read, isCurrent,
              schedulerActionsBeforeRead != nil,
              plannedHandles.contains(where: { $0 === handle }),
              let model = node.schedulerSetupModels.first(where: { $0 === handle.model }) else { return }
        if !readingSchedulerDetails, handle.message is SchedulerGet, let response = status as? SchedulerStatus {
            schedulerBitmaps[model] = response.schedules
            schedulerEntries[model] = [:]
        } else if readingSchedulerDetails, let request = handle.message as? SchedulerActionGet,
                  let response = status as? SchedulerActionStatus, response.index == request.index {
            // A slot may become empty between bitmap and detail reads.
            if response.entry.isValid { schedulerEntries[model, default: [:]][Int(response.index)] = response.entry }
            else { schedulerEntries[model]?.removeValue(forKey: Int(response.index)) }
        } else { return }
        receivedSchedulerHandles.insert(ObjectIdentifier(handle))
    }

    private func applySchedulerRead(expected: [MeshMessageHandle]) -> Bool {
        guard schedulerActionsBeforeRead != nil,
              expected.count == plannedHandles.count,
              zip(expected, plannedHandles).allSatisfy({ $0 === $1 }),
              expected.allSatisfy({ receivedSchedulerHandles.contains(ObjectIdentifier($0)) }),
              node.schedulerSetupModels.allSatisfy({ schedulerBitmaps[$0] != nil }) else {
            invalidateIncompleteSchedulerRead()
            return false
        }
        followUpMessageHandles = []
        if !readingSchedulerDetails {
            readingSchedulerDetails = true
            let details = node.schedulerSetupModels.flatMap { model in
                (0..<16).compactMap { index -> MeshMessageHandle? in
                    guard schedulerBitmaps[model]! & (UInt16(1) << index) != 0 else { return nil }
                    return MeshMessageHandle(message: SchedulerActionGet(index: UInt8(index)), model: model)
                }
            }
            if !details.isEmpty {
                plannedHandles = details
                receivedSchedulerHandles = []
                followUpMessageHandles = details
                return true
            }
        }
        // Publish only this complete read, including authoritative empty Models.
        var entries = node.allSchedulerModelEntrys
        node.schedulerSetupModels.forEach { entries[$0] = schedulerEntries[$0] ?? [:] }
        node.allSchedulerModelEntrys = entries
        node.rebuildSchedulerActions()
        node.savePropertys()
        node.clearSyncStateCache()
        schedulerActionsBeforeRead = nil
        return true
    }

    func apply(results: [MeshMessageHandle], expected: [MeshMessageHandle]) -> Bool {
        guard isCurrent, results.count == expected.count, results.allSatisfy(\.isSuccessful),
              !expected.isEmpty || allowsEmpty else {
            invalidateIncompleteSchedulerRead()
            return false
        }
        if phase == .read {
            return applySchedulerRead(expected: expected)
        }
        for handle in results { _ = node.applyMessageHandle(handle, isSuccess: true) }
        let previous = scene.info.configuration
        let saved = SunSmartDataManager.shared.configurationTransaction {
            if let power = appliedPower {
                guard PJEightKeySwitchRepository.shared.confirmSceneKeyConfiguration(power,
                    meshUUID: scope.meshUUID, networkId: scope.networkID) else { throw SceneDeletionCascade.Failure.persistence }
            }
            scene.info.configuration?.deletionReferences?.pending.removeAll { $0.id == reference.id }
            try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        }
        if !saved { scene.info.configuration = previous; return false }
        // Refresh only the applied key hash; TX/LED/other pending operations remain independent.
        if let power = appliedPower,
           let live = MeshNetworkManager.instance.switchs.first(where: { $0.id == power.id }) as? PJEightKeySwitchData {
            live.appliedConfigHash = power.desiredConfigHash
            if !live.needsBatteryPowerSwitchSync { live.syncState = .synced }
        }
        node.clearSyncStateCache()
        return true
    }
}
