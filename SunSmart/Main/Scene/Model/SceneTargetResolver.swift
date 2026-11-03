import Foundation
import NordicSigMeshSDK

extension Node {
    /// Scene rows and task contexts use canonical hex. Keep the shared Scheduler
    /// identity unchanged because its existing bindings use their original form.
    var sceneConfigurationIdentity: TimedSchedulerNodeIdentity? {
        timedSchedulerIdentity.flatMap { try? SceneConfiguration.identity($0) }
    }

    var sceneSyncReadIdentity: TimedSchedulerNodeIdentity? {
        if let context = NodeSyncReadContext.current { return context.sceneReads.identity(self) }
        return sceneConfigurationIdentity
    }
}

struct SceneTargetSnapshot {
    struct Target {
        let identity: TimedSchedulerNodeIdentity
        let node: Node
        let parameters: SceneParameters
        let displayGroupAddress: Address?
    }
    struct Capability: Equatable {
        let identity: TimedSchedulerNodeIdentity
        let lightness: Bool
        let cct: Bool
        let lightnessRange: ClosedRange<UInt16>
        let cctRange: ClosedRange<UInt16>
    }
    struct Unresolved: Equatable {
        enum Reason: String { case missingIdentity, unsupported, offlineAddition }
        let identity: TimedSchedulerNodeIdentity
        let action: ScenePendingOperation.Action
        let reason: Reason
    }
    struct Comparison: Equatable {
        var kind: SceneKind
        var name: String
        var members: [SceneDeviceMember]
        var groupParameters: [Address: SceneParameters]
        var groupAuxiliaryData: [Address: Data] = [:]
        var isDeleting: Bool
        var targets: [SceneDeviceMember]
        var capabilities: [Capability] = []
    }
    let scope: SceneScope
    let number: SceneNumber?
    let revision: UUID?
    let targets: [Target]
    let cleanupTargets: [Target]
    let targetsByIdentity: [TimedSchedulerNodeIdentity: Target]
    let unresolved: [Unresolved]
    let comparison: Comparison
    /// Synchronization ownership excludes display-only metadata. Editors continue
    /// comparing the full comparison and their captured source name/icon.
    var taskComparison: Comparison {
        var value = comparison
        value.name = ""
        return value
    }
    var hasConfiguredMembers: Bool { !comparison.members.isEmpty || !comparison.groupParameters.isEmpty }

    /// Read desired values without authorizing transport. Blocked writes still
    /// contribute to differences; SceneMessageContext guards sending and ACKs.
    func writeData(scene: Scene, node: Node, identity: TimedSchedulerNodeIdentity? = nil) -> SceneExecuteData? {
        guard let identity = identity ?? node.sceneConfigurationIdentity,
              let resolved = targetsByIdentity[identity] else { return nil }
        if comparison.kind == .groups {
            return scene.info.groups.compactMap { group -> SceneExecuteData? in
                guard group.address.address == resolved.displayGroupAddress else { return nil }
                return group.info.sceneExecuteDatas.first {
                    $0.sceneNumber == scene.number && $0.state == .normal
                }?.deviceTarget(for: node)
            }.first
        }
        return SceneExecuteData(sceneNumber: scene.number, isOn: resolved.parameters.isOn,
            lightness: resolved.parameters.lightness, cct: resolved.parameters.cct)
    }

    func reservesScene(on node: Node) -> Bool {
        guard let raw = node.timedSchedulerIdentity, let identity = try? SceneConfiguration.identity(raw) else { return false }
        return targets.contains { $0.identity == identity } || cleanupTargets.contains { $0.identity == identity }
            || unresolved.contains { $0.identity == identity }
    }
}

enum SceneTargetResolver {
    enum Failure: Error { case staleScope, invalidConfiguration, conflictingMode, invalidGroup }

    /// Execution and ACK validation always take a fresh view, even inside a UI read.
    static func resolve(scene: Scene) throws -> SceneTargetSnapshot {
        let index = IdentityIndex()
        _ = index.advance(until: .infinity)
        let read = try resolution(scene: scene, index: index)
        return try read.advance(until: .infinity)!
    }

    /// Only display/difference readers may reuse the current validated Space batch.
    static func resolveForSyncRead(scene: Scene) throws -> SceneTargetSnapshot {
        if let context = NodeSyncReadContext.current { return try context.sceneReads.snapshot(scene) }
        return try resolve(scene: scene)
    }

    static func resolution(scene: Scene, index: IdentityIndex) throws -> Resolution {
        AppPerformance.event("SyncSceneResolve")
        let manager = MeshNetworkManager.instance
        guard let meshUUID = manager.meshNetwork?.uuid.uuidString,
              scene.network?.uuid.uuidString == meshUUID,
              scene.subNetworkId == manager.currentNetworkKey.networkId.hex,
              !scene.info.configurationLoadFailed, !scene.number.isSpecialScene else { throw Failure.invalidConfiguration }
        let scope = SceneScope(meshUUID: meshUUID, networkID: manager.currentNetworkKey.networkId.hex)
        let configuration = try scene.info.configuration?.normalized()
        let kind = configuration?.kind ?? .groups
        let groups = scene.info.groups
        guard kind != .devices || groups.isEmpty else { throw Failure.conflictingMode }
        var parameters: [Address: SceneParameters] = [:]
        var cleanup: [Group] = []
        for group in groups {
            let values = group.info.sceneExecuteDatas.filter { $0.sceneNumber == scene.number }
            guard values.count == 1, let data = values.first else { throw Failure.invalidConfiguration }
            if data.state == .waitDelete { cleanup.append(group) }
            else { parameters[group.address.address] = .init(data) }
        }
        // Legal legacy groups have no persisted revision. Their scope UUID is a
        // stable initial revision until the first configuration edit. Metadata
        // promotion preserves it; number/scope/identity still distinguish tasks.
        return try Resolution(index: index, scope: scope, number: scene.number, revision: configuration?.revision ?? UUID(uuidString: meshUUID),
            kind: kind, name: configuration?.name ?? scene.name, groupParameters: parameters,
            members: configuration?.deviceMembers ?? [], operations: configuration?.pendingOperations ?? [],
            isDeleting: configuration?.isDeleting ?? false, groups: groups, cleanupGroups: cleanup)
    }

    static func resolve(draft: SceneDraft) throws -> SceneTargetSnapshot {
        // ACKs can finish cleanup while an editor is open. Preflight must use
        // that same committed revision's current reservations, not revive its
        // removed members from the editor's original snapshot.
        let existing = Set(draft.sourceConfiguration?.deviceMembers.map(\.identity) ?? [])
        var removals = draft.sourceConfiguration?.pendingOperations.filter { $0.action == .remove } ?? []
        var cleanupIdentities = draft.sourceCleanupIdentities
        if let number = draft.number,
           let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }),
           scene.info.configuration?.revision == draft.sourceConfiguration?.revision {
            let current = try resolve(scene: scene)
            guard current.scope == draft.scope else { throw Failure.staleScope }
            removals = scene.info.configuration?.pendingOperations.filter { $0.action == .remove } ?? []
            cleanupIdentities = current.cleanupTargets.map(\.identity)
                + current.unresolved.filter { $0.action == .remove }.map(\.identity)
        }
        for identity in cleanupIdentities where !removals.contains(where: { $0.identity == identity }) {
            removals.append(.init(identity: identity, action: .remove))
        }
        return try resolve(scope: draft.scope, number: draft.number, revision: draft.revision,
            kind: draft.kind, name: draft.name, groupParameters: draft.groupParameters, members: draft.deviceMembers,
            operations: removals,
            isDeleting: false, groups: MeshNetworkManager.instance.groups, existingMembers: existing)
    }

    /// One index per operation, or per versioned UI batch. Keep every match so
    /// duplicate identities remain ambiguous rather than silently choosing a Node.
    final class IdentityIndex {
        private weak var context: NodeSyncReadContext?
        private let nodes = MeshNetworkManager.instance.realNodes
        private let meshUUID = MeshNetworkManager.instance.meshNetwork?.uuid.uuidString
        private let networkID = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
        private var cursor = 0
        private var reported = false
        private(set) var identities: [ObjectIdentifier: TimedSchedulerNodeIdentity] = [:]
        private(set) var matches: [TimedSchedulerNodeIdentity: [Node]] = [:]
        private(set) var groupAddresses: [ObjectIdentifier: Address] = [:]
        private(set) var groupNodes: [Address: [Node]] = [:]

        init(context: NodeSyncReadContext? = nil) { self.context = context }

        func advance(until deadline: TimeInterval) -> Bool {
            while cursor < nodes.count {
                if ProcessInfo.processInfo.systemUptime >= deadline { return false }
                let node = nodes[cursor], key = ObjectIdentifier(nodes[cursor])
                cursor += 1
                let group = context.map { $0.sceneGroup(for: node) } ?? node.group
                if let address = group?.address.address {
                    groupAddresses[key] = address
                    groupNodes[address, default: []].append(node)
                }
                if let identity = node.sceneConfigurationIdentity {
                    identities[key] = identity
                    if node.network?.uuid.uuidString == meshUUID, node.subNetworkId == networkID {
                        matches[identity, default: []].append(node)
                    }
                }
            }
            if !reported {
                reported = true
                AppPerformance.event("SyncSceneIdentityIndex", value: nodes.count)
            }
            return true
        }
    }

    private static func resolve(scope: SceneScope, number: SceneNumber?, revision: UUID?, kind: SceneKind,
                                name: String, groupParameters: [Address: SceneParameters], members: [SceneDeviceMember],
                                operations: [ScenePendingOperation], isDeleting: Bool, groups: [Group], cleanupGroups: [Group] = [],
                                existingMembers: Set<TimedSchedulerNodeIdentity>? = nil) throws -> SceneTargetSnapshot {
        let index = IdentityIndex()
        _ = index.advance(until: .infinity)
        let read = try Resolution(index: index, scope: scope, number: number, revision: revision, kind: kind,
            name: name, groupParameters: groupParameters, members: members, operations: operations,
            isDeleting: isDeleting, groups: groups, cleanupGroups: cleanupGroups, existingMembers: existingMembers)
        return try read.advance(until: .infinity)!
    }

    /// The same resolver serves fresh operations and incremental status reads.
    /// Each expensive unit is one target or one Group payload, not an entire Scene.
    final class Resolution {
        private enum Work {
            case identity(TimedSchedulerNodeIdentity, SceneParameters, ScenePendingOperation.Action)
            case groupNode(Node, SceneParameters, ScenePendingOperation.Action)
            case auxiliary(Group)
        }
        private let index: IdentityIndex
        private let scope: SceneScope
        private let number: SceneNumber?
        private let revision: UUID?
        private let kind: SceneKind
        private let name: String
        private let groupParameters: [Address: SceneParameters]
        private let members: [SceneDeviceMember]
        private let isDeleting: Bool
        private let existingMembers: Set<TimedSchedulerNodeIdentity>?
        private var work: [Work] = []
        private var cursor = 0
        private var targets: [SceneTargetSnapshot.Target] = [], cleanup: [SceneTargetSnapshot.Target] = []
        private var unresolved: [SceneTargetSnapshot.Unresolved] = []
        private var auxiliary: [Address: Data] = [:]
        private var capabilities: [TimedSchedulerNodeIdentity: SceneTargetSnapshot.Capability] = [:]
        private var result: SceneTargetSnapshot?

        init(index: IdentityIndex, scope: SceneScope, number: SceneNumber?, revision: UUID?, kind: SceneKind,
             name: String, groupParameters: [Address: SceneParameters], members: [SceneDeviceMember],
             operations: [ScenePendingOperation], isDeleting: Bool, groups: [Group], cleanupGroups: [Group] = [],
             existingMembers: Set<TimedSchedulerNodeIdentity>? = nil) throws {
            let manager = MeshNetworkManager.instance
            guard scope.meshUUID == manager.meshNetwork?.uuid.uuidString,
                  scope.networkID == manager.currentNetworkKey.networkId.hex else { throw Failure.staleScope }
            self.index = index; self.scope = scope; self.number = number; self.revision = revision
            self.kind = kind; self.name = name; self.groupParameters = groupParameters
            self.members = members; self.isDeleting = isDeleting; self.existingMembers = existingMembers
            if kind == .devices {
                if !isDeleting { work += members.map { .identity($0.identity, $0.parameters, .write) } }
            } else if !isDeleting {
                for (address, parameters) in groupParameters.sorted(by: { $0.key < $1.key }) {
                    guard groups.contains(where: { $0.address.address == address }) else { throw Failure.invalidGroup }
                    work += (index.groupNodes[address] ?? []).map { .groupNode($0, parameters, .write) }
                }
            }
            let neutral = SceneParameters(isOn: false, lightness: 0, cct: 0)
            for group in cleanupGroups where !isDeleting {
                work += (index.groupNodes[group.address.address] ?? []).map { .groupNode($0, neutral, .remove) }
            }
            work += operations.filter { $0.action == .remove }.map { .identity($0.identity, neutral, .remove) }
            work += groups.filter { groupParameters[$0.address.address] != nil }.map(Work.auxiliary)
        }

        func advance(until deadline: TimeInterval) throws -> SceneTargetSnapshot? {
            if let result { return result }
            while cursor < work.count {
                if ProcessInfo.processInfo.systemUptime >= deadline { return nil }
                let item = work[cursor]; cursor += 1
                switch item {
                case .identity(let identity, let parameters, let action):
                    append(identity: identity, parameters: parameters, action: action)
                case .groupNode(let node, let parameters, let action):
                    // Keep legacy non-light and exited member semantics.
                    guard node.sceneSetupModel != nil,
                          action == .remove || (node.onoffModel != nil && node.groupState != .exitFailure) else { continue }
                    guard let identity = index.identities[ObjectIdentifier(node)] else { throw Failure.invalidConfiguration }
                    append(identity: identity, parameters: parameters, action: action)
                case .auxiliary(let group):
                    if let data = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == number }) {
                        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! [String: Any]
                        for key in ["sceneNumber", "state", "isOn", "lightness", "cct"] { object.removeValue(forKey: key) }
                        auxiliary[group.address.address] = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
                    }
                }
            }
            if ProcessInfo.processInfo.systemUptime >= deadline { return nil }
            func unique(_ values: [SceneTargetSnapshot.Target]) throws -> [SceneTargetSnapshot.Target] {
                var result: [TimedSchedulerNodeIdentity: SceneTargetSnapshot.Target] = [:]
                for value in values {
                    if let previous = result[value.identity], previous.parameters != value.parameters { throw Failure.invalidConfiguration }
                    result[value.identity] = value
                }
                return result.values.sorted { SceneConfiguration.key($0.identity) < SceneConfiguration.key($1.identity) }
            }
            targets = try unique(targets); cleanup = try unique(cleanup)
            let snapshot = SceneTargetSnapshot(scope: scope, number: number, revision: revision, targets: targets,
                cleanupTargets: cleanup, targetsByIdentity: Dictionary(uniqueKeysWithValues: targets.map { ($0.identity, $0) }),
                unresolved: unresolved,
                comparison: .init(kind: kind, name: name, members: members, groupParameters: groupParameters,
                    groupAuxiliaryData: auxiliary, isDeleting: isDeleting,
                    targets: targets.map { .init(identity: $0.identity, parameters: $0.parameters) },
                    capabilities: targets.compactMap { capabilities[$0.identity] }))
            result = snapshot
            return snapshot
        }

        private func append(identity: TimedSchedulerNodeIdentity, parameters: SceneParameters, action: ScenePendingOperation.Action) {
            let matching = index.matches[identity] ?? []
            guard matching.count == 1, let node = matching.first else {
                unresolved.append(.init(identity: identity, action: action, reason: .missingIdentity)); return
            }
            guard node.sceneSetupModel != nil, action == .remove || node.onoffModel != nil else {
                unresolved.append(.init(identity: identity, action: action, reason: .unsupported)); return
            }
            if kind == .devices, action == .write, let existingMembers, !existingMembers.contains(identity), !node.state {
                unresolved.append(.init(identity: identity, action: action, reason: .offlineAddition)); return
            }
            let effectiveParameters: SceneParameters
            if action == .remove {
                // Delete has no lighting parameters. Duplicate cleanup intents
                // from a group and the durable operation describe the same work.
                effectiveParameters = .init(isOn: false, lightness: 0, cct: 0)
            } else if kind == .groups {
                let legacy = SceneExecuteData(sceneNumber: number ?? 0, isOn: parameters.isOn,
                                              lightness: parameters.lightness, cct: parameters.cct)
                effectiveParameters = SceneParameters(legacy.deviceTarget(for: node))
            } else { effectiveParameters = parameters.resolved(for: node) }
            let target = SceneTargetSnapshot.Target(identity: identity, node: node,
                parameters: effectiveParameters, displayGroupAddress: index.groupAddresses[ObjectIdentifier(node)])
            if action == .write { targets.append(target) } else { cleanup.append(target) }
            if action == .write {
                capabilities[identity] = .init(identity: identity, lightness: node.lightnessModel != nil,
                    cct: node.effectiveSupportCct, lightnessRange: node.lightnessRange, cctRange: node.effectiveCctRange)
            }
        }
    }

}

extension SceneParameters {
    init(_ data: SceneExecuteData) {
        self.init(isOn: data.isOn, lightness: data.lightness, cct: data.cct)
    }

    func resolved(for node: Node) -> SceneParameters {
        // Preserve the existing Mesh unit/trim interpretation. CCT uses the same
        // effective range as group SceneExecuteData.deviceTarget(for:).
        let dimmable = node.lightnessModel != nil
        let on = isOn && (!dimmable || lightness > 0)
        let brightness = on && dimmable ? min(node.lightnessRange.upperBound, max(node.lightnessRange.lowerBound, lightness)) : 0
        return .init(isOn: on, lightness: brightness, cct: node.effectiveSupportCct ? node.clampEffectiveCct(cct) : 0)
    }
}

extension SceneDraft {
    /// Capture the committed baseline once on entry; later edits only affect values.
    init(scene: Scene) throws {
        let snapshot = try SceneTargetResolver.resolve(scene: scene)
        try self.init(number: scene.number, scope: snapshot.scope, name: snapshot.comparison.name,
                      imageId: scene.info.imageId, kind: snapshot.comparison.kind,
                      groupParameters: snapshot.comparison.groupParameters,
                      deviceMembers: snapshot.comparison.members, sourceConfiguration: scene.info.configuration,
                      sourceGroupAddresses: Set(scene.info.groups.map { $0.address.address }),
                      sourceCleanupIdentities: snapshot.cleanupTargets.map(\.identity)
                        + snapshot.unresolved.filter { $0.action == .remove }.map(\.identity),
                      sourceGroupAuxiliaryData: snapshot.comparison.groupAuxiliaryData)
    }
}

/// Owned by NodeSyncReadContext, including failed results. No permanent Node cache
/// and no reuse by save/transport/ACK authorization paths.
final class SceneSyncReadPreparation {
    private struct DifferenceKey: Hashable {
        let node: ObjectIdentifier
        let group: ObjectIdentifier?
        let scene: ObjectIdentifier?
    }
    private let scenes = MeshNetworkManager.instance.scenes
    private let index: SceneTargetResolver.IdentityIndex
    private var cursor = 0
    private var pending: SceneTargetResolver.Resolution?
    private var results: [ObjectIdentifier: Result<SceneTargetSnapshot, Error>] = [:]
    private var differences: [DifferenceKey: [(scene: Scene, data: SceneExecuteData)]] = [:]

    init(context: NodeSyncReadContext? = nil) { index = .init(context: context) }

    func advance(until deadline: TimeInterval) -> Bool {
        guard !scenes.isEmpty else { return true }
        guard index.advance(until: deadline) else { return false }
        while cursor < scenes.count {
            if ProcessInfo.processInfo.systemUptime >= deadline { return false }
            let scene = scenes[cursor]
            do {
                if pending == nil { pending = try SceneTargetResolver.resolution(scene: scene, index: index) }
                guard let snapshot = try pending?.advance(until: deadline) else { return false }
                results[ObjectIdentifier(scene)] = .success(snapshot)
            } catch { results[ObjectIdentifier(scene)] = .failure(error) }
            pending = nil; cursor += 1
        }
        return true
    }

    func snapshot(_ scene: Scene) throws -> SceneTargetSnapshot {
        guard let result = results[ObjectIdentifier(scene)] else { throw SceneTargetResolver.Failure.staleScope }
        return try result.get()
    }

    func identity(_ node: Node) -> TimedSchedulerNodeIdentity? { index.identities[ObjectIdentifier(node)] }

    func contains(_ node: Node, in group: Group) -> Bool {
        index.groupAddresses[ObjectIdentifier(node)] == group.address.address
    }

    func difference(node: Node, group: Group?, scene: Scene?,
                    read: () -> [(scene: Scene, data: SceneExecuteData)]) -> [(scene: Scene, data: SceneExecuteData)] {
        let key = DifferenceKey(node: ObjectIdentifier(node), group: group.map(ObjectIdentifier.init),
                                scene: scene.map(ObjectIdentifier.init))
        if let value = differences[key] { return value }
        let value = read()
        differences[key] = value
        return value
    }
}

extension NodeSyncReadContext {
    var sceneReads: SceneSyncReadPreparation {
        memoized("scene-targets") { SceneSyncReadPreparation(context: self) }
    }
}
