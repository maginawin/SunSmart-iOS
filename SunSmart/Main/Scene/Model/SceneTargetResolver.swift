import Foundation
import NordicSigMeshSDK

extension Node {
    /// Scene rows and task contexts use canonical hex. Keep the shared Scheduler
    /// identity unchanged because its existing bindings use their original form.
    var sceneConfigurationIdentity: TimedSchedulerNodeIdentity? {
        timedSchedulerIdentity.flatMap { try? SceneConfiguration.identity($0) }
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

    func reservesScene(on node: Node) -> Bool {
        guard let raw = node.timedSchedulerIdentity, let identity = try? SceneConfiguration.identity(raw) else { return false }
        return targets.contains { $0.identity == identity } || cleanupTargets.contains { $0.identity == identity }
            || unresolved.contains { $0.identity == identity }
    }
}

enum SceneTargetResolver {
    enum Failure: Error { case staleScope, invalidConfiguration, conflictingMode, invalidGroup }

    static func resolve(scene: Scene) throws -> SceneTargetSnapshot {
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
        return try resolve(scope: scope, number: scene.number, revision: configuration?.revision ?? UUID(uuidString: meshUUID),
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

    private static func resolve(scope: SceneScope, number: SceneNumber?, revision: UUID?, kind: SceneKind,
                                name: String, groupParameters: [Address: SceneParameters], members: [SceneDeviceMember],
                                operations: [ScenePendingOperation], isDeleting: Bool, groups: [Group], cleanupGroups: [Group] = [],
                                existingMembers: Set<TimedSchedulerNodeIdentity>? = nil) throws -> SceneTargetSnapshot {
        let manager = MeshNetworkManager.instance
        guard scope.meshUUID == manager.meshNetwork?.uuid.uuidString,
              scope.networkID == manager.currentNetworkKey.networkId.hex else { throw Failure.staleScope }
        let nodes = manager.realNodes.filter { $0.network?.uuid.uuidString == scope.meshUUID && $0.subNetworkId == scope.networkID }
        var targets: [SceneTargetSnapshot.Target] = [], cleanup: [SceneTargetSnapshot.Target] = []
        var unresolved: [SceneTargetSnapshot.Unresolved] = []
        func append(identity: TimedSchedulerNodeIdentity, parameters: SceneParameters, action: ScenePendingOperation.Action) {
            let matching = nodes.filter { $0.timedSchedulerIdentity.flatMap { try? SceneConfiguration.identity($0) } == identity }
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
                parameters: effectiveParameters, displayGroupAddress: node.group?.address.address)
            if action == .write { targets.append(target) } else { cleanup.append(target) }
        }
        if kind == .devices {
            if !isDeleting { members.forEach { append(identity: $0.identity, parameters: $0.parameters, action: .write) } }
        } else if !isDeleting {
            for (address, parameters) in groupParameters.sorted(by: { $0.key < $1.key }) {
                guard let group = groups.first(where: { $0.address.address == address }) else { throw Failure.invalidGroup }
                for node in group.nodes where node.groupState != .exitFailure {
                    // Legacy groups may contain non-light devices. They have never
                    // been Scene targets; keep that compatibility boundary.
                    guard node.sceneSetupModel != nil, node.onoffModel != nil else { continue }
                    guard let identity = node.timedSchedulerIdentity else { throw Failure.invalidConfiguration }
                    append(identity: try SceneConfiguration.identity(identity), parameters: parameters, action: isDeleting ? .remove : .write)
                }
            }
        }
        let neutral = SceneParameters(isOn: false, lightness: 0, cct: 0)
        for group in cleanupGroups where !isDeleting {
            for node in group.nodes where node.sceneSetupModel != nil {
                guard let identity = node.timedSchedulerIdentity else { throw Failure.invalidConfiguration }
                append(identity: try SceneConfiguration.identity(identity), parameters: neutral, action: .remove)
            }
        }
        for operation in operations where operation.action == .remove {
            append(identity: operation.identity, parameters: neutral, action: .remove)
        }
        func unique(_ values: [SceneTargetSnapshot.Target]) throws -> [SceneTargetSnapshot.Target] {
            var result: [TimedSchedulerNodeIdentity: SceneTargetSnapshot.Target] = [:]
            for value in values {
                if let previous = result[value.identity], previous.parameters != value.parameters { throw Failure.invalidConfiguration }
                result[value.identity] = value
            }
            return result.values.sorted { SceneConfiguration.key($0.identity) < SceneConfiguration.key($1.identity) }
        }
        targets = try unique(targets); cleanup = try unique(cleanup)
        var auxiliary: [Address: Data] = [:]
        for group in groups where groupParameters[group.address.address] != nil {
            if let data = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == number }) {
                var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(data)) as! [String: Any]
                for key in ["sceneNumber", "state", "isOn", "lightness", "cct"] { object.removeValue(forKey: key) }
                auxiliary[group.address.address] = try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
            }
        }
        return .init(scope: scope, number: number, revision: revision, targets: targets, cleanupTargets: cleanup,
            unresolved: unresolved,
            comparison: .init(kind: kind, name: name, members: members, groupParameters: groupParameters,
                groupAuxiliaryData: auxiliary, isDeleting: isDeleting, targets: targets.map { .init(identity: $0.identity, parameters: $0.parameters) },
                capabilities: targets.map { .init(identity: $0.identity, lightness: $0.node.lightnessModel != nil,
                    cct: $0.node.effectiveSupportCct, lightnessRange: $0.node.lightnessRange, cctRange: $0.node.effectiveCctRange) }))
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
