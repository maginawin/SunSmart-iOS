import Foundation
import NordicSigMeshSDK
import ObjectiveC

enum SceneCommandBuilder {
    enum RecallFailure: Error { case unavailable, emergency }

    /// Pending device writes are executable; a deleted/stale projection is not.
    /// Configuration editor authorization is deliberately not used for control.
    static func isSelectable(scene: Scene) -> Bool {
        !scene.info.projectionPending && scene.info.configuration?.isDeleting != true
            && MeshNetworkManager.instance.scenes.contains { $0 === scene }
            && (try? SceneTargetResolver.resolve(scene: scene)) != nil
    }

    static func recallHandles(scene: Scene) throws -> [MeshMessageHandle] {
        guard isSelectable(scene: scene) else { throw RecallFailure.unavailable }
        let snapshot = try SceneTargetResolver.resolve(scene: scene)
        guard !snapshot.targets.contains(where: { EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: $0.node) }) else {
            throw RecallFailure.emergency
        }
        if snapshot.comparison.kind == .groups {
            // Keep the established group Scene broadcast, including empty preconfiguration.
            return [MeshMessageHandle(message: SceneRecallUnacknowledged(scene.number), address: .allNodes)]
        }
        return try snapshot.targets.map { target in
            guard let model = target.node.sceneModel else { throw RecallFailure.unavailable }
            return MeshMessageHandle(message: SceneRecallUnacknowledged(scene.number), model: model)
        }
    }

    /// Optimistic display uses only a confirmed stored version. Pending desired
    /// configuration is shown in details, never presented as a lamp's actual state.
    /// A per-node transport callback must not update other scene members.
    static func applyRecallFeedback(scene: Scene, node: Node? = nil) {
        guard isSelectable(scene: scene), let snapshot = try? SceneTargetResolver.resolve(scene: scene) else { return }
        let pending = Set(scene.info.configuration?.pendingOperations.map(\.identity) ?? [])
        for target in snapshot.targets where node == nil || target.node === node {
            guard !pending.contains(target.identity),
                  let stored = target.node.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number && $0.state == .normal }) else { continue }
            if snapshot.comparison.kind == .devices {
                guard SceneParameters(stored) == target.parameters else { continue }
            }
            target.node.isOn = stored.isOn
            target.node.lightness = stored.lightness
            if target.node.effectiveSupportCct { target.node.temperature = target.node.clampEffectiveCct(stored.cct) }
        }
        guard node == nil, snapshot.comparison.kind == .groups else { return }
        for group in scene.info.groups {
            guard let data = group.info.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number && $0.state == .normal }),
                  snapshot.targets.filter({ $0.displayGroupAddress == group.address.address }).allSatisfy({ target in
                      !pending.contains(target.identity)
                          && target.node.sceneExecuteDatas.first(where: { $0.sceneNumber == scene.number })?
                              .isSynced(with: data, for: target.node) == true
                  }) else { continue }
            group.lightness = data.lightness
            group.cct = Int(group.clampEffectiveCct(data.cct))
            group.isOn = data.isOn
        }
    }

    /// Like Scheduler reservation, persist ownership before constructing a physical task.
    static func reserveGroupOperation(scene: Scene, node: Node, action: ScenePendingOperation.Action) -> Bool {
        let scope: SceneScope
        do {
            scope = try SceneTargetResolver.resolve(scene: scene).scope
            try SceneConfigurationStore.validateAccess(scope)
        } catch {
            #if DEBUG
            print("[SceneSync] stage=reservationRejected scene=\(scene.number) address=\(node.primaryUnicastAddress) reason=resolveOrAccess errorType=\(Swift.type(of: error)) targetFailure=\(String(describing: error as? SceneTargetResolver.Failure)) storeFailure=\(String(describing: error as? SceneConfigurationStore.Failure))")
            #endif
            return false
        }
        guard action == .remove || !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: node) else {
            #if DEBUG
            print("[SceneSync] stage=reservationRejected scene=\(scene.number) address=\(node.primaryUnicastAddress) reason=emergencyBlocked")
            #endif
            return false
        }
        guard scene.info.configuration?.kind == .groups else { return true }
        guard !scene.info.projectionPending, let identity = node.sceneConfigurationIdentity,
              let snapshot = try? SceneTargetResolver.resolve(scene: scene) else {
            #if DEBUG
            print("[SceneSync] stage=reservationRejected scene=\(scene.number) address=\(node.primaryUnicastAddress) reason=projectionIdentityOrSnapshot projectionPending=\(scene.info.projectionPending) hasIdentity=\(node.timedSchedulerIdentity != nil)")
            #endif
            return false
        }
        let current = scene.info.configuration?.pendingOperations.first { $0.identity == identity }
        if current?.action == action { return true }
        if action == .write {
            guard snapshot.targets.contains(where: { $0.identity == identity }) else {
                #if DEBUG
                print("[SceneSync] stage=reservationRejected scene=\(scene.number) address=\(node.primaryUnicastAddress) reason=notWriteTarget")
                #endif
                return false
            }
        } else {
            guard snapshot.cleanupTargets.contains(where: { $0.identity == identity })
                || (node.groupState == .exitFailure && node.group?.info.sceneExecuteDatas.contains(where: { $0.sceneNumber == scene.number }) == true) else { return false }
        }
        let previous = scene.info.configuration
        scene.info.configuration?.pendingOperations.removeAll { $0.identity == identity }
        scene.info.configuration?.pendingOperations.append(.init(identity: identity, action: action))
        do { try scene.info.saveConfiguration(meshUUID: snapshot.scope.meshUUID, subnetworkId: snapshot.scope.networkID); return true }
        catch {
            #if DEBUG
            print("[SceneSync] stage=reservationRejected scene=\(scene.number) address=\(node.primaryUnicastAddress) reason=persistence errorType=\(Swift.type(of: error))")
            #endif
            scene.info.configuration = previous; return false
        }
    }

    static func captureConfigurations(progress: SceneSyncProgress? = nil) -> () -> Bool {
        let manager = MeshNetworkManager.instance
        let scenes = manager.scenes.filter { !$0.number.isSpecialScene }
        let snapshots = scenes.map { scene -> SceneTargetSnapshot? in
            guard !scene.info.projectionPending else { return nil }
            return try? SceneTargetResolver.resolve(scene: scene)
        }
        return {
            guard progress?.isCurrent() != false else { return false }
            guard manager.scenes.filter({ !$0.number.isSpecialScene }).map(\.number).sorted() == scenes.map(\.number).sorted() else { return false }
            return zip(scenes, snapshots).allSatisfy { scene, old in
                guard manager.scenes.contains(where: { $0 === scene }), !scene.info.projectionPending,
                      let old, let current = try? SceneTargetResolver.resolve(scene: scene) else { return false }
                return old.revision == current.revision
                    && (progress?.comparison(old) ?? old.taskComparison) == (progress?.comparison(current) ?? current.taskComparison)
            }
        }
    }

    static func parameterHandles(node: Node, parameters: SceneParameters) -> [MeshMessageHandle] {
        let parameters = parameters.resolved(for: node)
        return parameterHandles(node: node, target: SceneExecuteData(sceneNumber: 0,
            isOn: parameters.isOn, lightness: parameters.lightness, cct: parameters.cct))
    }

    // Group callers supply their complete deviceTarget; do not reapply device trim semantics.
    static func parameterHandles(node: Node, target: SceneExecuteData) -> [MeshMessageHandle] {
        guard let onoff = node.onoffModel else { return [] }
        let handle: MeshMessageHandle
        if !target.isOn {
            handle = MeshMessageHandle(message: GenericOnOffSet(false), model: onoff)
        } else if let ctl = node.ctlModel, node.effectiveSupportCct {
            handle = MeshMessageHandle(message: LightCTLSet(lightness: target.lightness,
                temperature: node.clampEffectiveCct(target.cct), deltaUV: 0, transitionTime: .immediate, delay: 0), model: ctl)
        } else if let lightness = node.lightnessModel {
            handle = MeshMessageHandle(message: LightLightnessSet(lightness: target.lightness,
                transitionTime: .immediate, delay: 0), model: lightness)
        } else {
            handle = MeshMessageHandle(message: GenericOnOffSet(target.isOn), model: onoff)
        }
        handle.continuous = false
        return [handle]
    }
}

/// Only commands submitted by this plan may advance its observed Scene inputs.
/// Desired Scene data and per-message ownership retain their strict comparisons.
final class SceneSyncProgress {
    enum Change {
        case subscription(Group, adding: Bool)
        case lightnessRange(ClosedRange<UInt16>)
    }

    private struct Observation: Equatable {
        let identity: TimedSchedulerNodeIdentity?
        let network: ObjectIdentifier?
        let subNetworkID: String?
        var group: ObjectIdentifier?
        var groupAddress: Address?
        var pendingGroupAddress: Address?
        let hasScene: Bool
        let hasOnOff: Bool
        let hasLightness: Bool
        let hasCct: Bool
        var lightnessRange: ClosedRange<UInt16>
        let cctRange: ClosedRange<UInt16>
        var exiting: Bool

        init(_ node: Node) {
            identity = node.sceneConfigurationIdentity
            network = node.network.map(ObjectIdentifier.init)
            subNetworkID = node.subNetworkId
            group = node.group.map(ObjectIdentifier.init)
            groupAddress = node.group?.address.address
            pendingGroupAddress = node.restoreData?.addGroupAddress
            hasScene = node.sceneSetupModel != nil
            hasOnOff = node.onoffModel != nil
            hasLightness = node.lightnessModel != nil
            hasCct = node.effectiveSupportCct
            lightnessRange = node.lightnessRange
            cctRange = node.effectiveCctRange
            exiting = node.groupState == .exitFailure
        }
    }

    private struct Entry {
        let node: Node
        var observed: Observation
        var expected: Observation
        var completesExit = false
    }
    private var entries: [ObjectIdentifier: Entry] = [:]
    private var changingIdentities = Set<TimedSchedulerNodeIdentity>()

    init() {
        for node in MeshNetworkManager.instance.realNodes {
            let observation = Observation(node)
            entries[ObjectIdentifier(node)] = Entry(node: node, observed: observation, expected: observation)
        }
    }

    func expect(node: Node, change: Change) {
        let key = ObjectIdentifier(node)
        guard var entry = entries[key] else { return }
        let initial = entry.observed
        guard let identity = initial.identity else { return }
        switch change {
        case .subscription(let group, let adding):
            if adding {
                // Subscribing an auxiliary group must not authorize moving a member.
                guard initial.group == nil || initial.group == ObjectIdentifier(group) else { return }
                guard initial.pendingGroupAddress == nil || initial.pendingGroupAddress == group.address.address else { return }
                entry.expected.group = ObjectIdentifier(group)
                entry.expected.groupAddress = group.address.address
                entry.expected.pendingGroupAddress = nil
            } else {
                guard initial.group == ObjectIdentifier(group) else { return }
                entry.expected.group = nil
                entry.expected.groupAddress = nil
                entry.completesExit = true
            }
        case .lightnessRange(let range): entry.expected.lightnessRange = range
        }
        entries[key] = entry
        changingIdentities.insert(identity)
    }

    func isCurrent() -> Bool {
        let nodes = MeshNetworkManager.instance.realNodes
        guard nodes.count == entries.count else { return false }
        let currentNodes = Set(nodes.map(ObjectIdentifier.init))
        var updated = entries
        for (key, var entry) in entries {
            guard currentNodes.contains(key) else { return false }
            let current = Observation(entry.node)
            var allowed = entry.observed
            if current.group == entry.expected.group {
                allowed.group = current.group
                allowed.groupAddress = entry.expected.groupAddress
                if current.pendingGroupAddress == entry.expected.pendingGroupAddress {
                    allowed.pendingGroupAddress = current.pendingGroupAddress
                }
            }
            if current.lightnessRange == entry.expected.lightnessRange { allowed.lightnessRange = current.lightnessRange }
            // The final unsubscribe also completes the existing exit intent.
            if entry.completesExit, entry.observed.exiting, current.group == nil {
                allowed.exiting = current.exiting
            }
            guard current == allowed else { return false }
            entry.observed = current // Once observed, an old value is no longer accepted.
            updated[key] = entry
        }
        entries = updated
        return true
    }

    func comparison(_ snapshot: SceneTargetSnapshot) -> SceneTargetSnapshot.Comparison {
        var value = snapshot.taskComparison
        // These derived values are protected by the exact observation transitions
        // above. Configuration, revision, members and group parameters stay strict.
        value.targets.removeAll { changingIdentities.contains($0.identity) }
        value.capabilities.removeAll { changingIdentities.contains($0.identity) }
        return value
    }
}

struct SceneMessageContext {
    let number: SceneNumber
    let scope: SceneScope
    let identity: TimedSchedulerNodeIdentity
    let revision: UUID?
    let operation: ScenePendingOperation?
    let action: ScenePendingOperation.Action
    let comparison: SceneTargetSnapshot.Comparison
    let target: SceneExecuteData?

    init(scene: Scene, node: Node, action: ScenePendingOperation.Action) throws {
        guard !scene.info.projectionPending else { throw SceneTargetResolver.Failure.invalidConfiguration }
        let snapshot = try SceneTargetResolver.resolve(scene: scene)
        try SceneConfigurationStore.validateAccess(snapshot.scope)
        guard action == .remove || !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: node) else {
            throw SceneTargetResolver.Failure.invalidConfiguration
        }
        guard let raw = node.timedSchedulerIdentity else { throw SceneTargetResolver.Failure.invalidConfiguration }
        let identity = try SceneConfiguration.identity(raw)
        self.identity = identity
        number = scene.number; scope = snapshot.scope; revision = snapshot.revision
        comparison = snapshot.taskComparison; self.action = action
        operation = scene.info.configuration?.pendingOperations.first { $0.identity == identity }
        if action == .write {
            guard let data = snapshot.writeData(scene: scene, node: node) else {
                throw SceneTargetResolver.Failure.invalidConfiguration
            }
            target = data
        } else { target = nil }
        let groupExit = snapshot.comparison.kind == .groups && node.groupState == .exitFailure
            && node.group?.info.sceneExecuteDatas.contains(where: { $0.sceneNumber == scene.number }) == true
        let groupReadd = snapshot.comparison.kind == .groups && action == .write
            && snapshot.targets.contains { $0.identity == identity }
        if let operation, operation.action != action, !groupExit, !groupReadd { throw SceneTargetResolver.Failure.invalidConfiguration }
        if scene.info.configuration != nil, action == .remove, operation == nil, !groupExit {
            throw SceneTargetResolver.Failure.invalidConfiguration
        }
    }

    func matches(node: Node) -> Bool {
        let manager = MeshNetworkManager.instance
        guard (try? SceneConfigurationStore.validateAccess(scope)) != nil,
              action == .remove || !EmergencyFireControllerSceneEventManager.isManualControlBlocked(for: node),
              scope.meshUUID == manager.meshNetwork?.uuid.uuidString,
              scope.networkID == manager.currentNetworkKey.networkId.hex,
              manager.realNodes.contains(where: { $0 === node }),
              node.timedSchedulerIdentity.flatMap({ try? SceneConfiguration.identity($0) }) == identity,
              let scene = manager.scenes.first(where: { $0.number == number }),
              !scene.info.projectionPending,
              let current = try? SceneTargetResolver.resolve(scene: scene),
              current.revision == revision, current.taskComparison == comparison else { return false }
        return scene.info.configuration?.pendingOperations.first(where: { $0.identity == identity }) == operation
    }

    var removesGroupRelationship: Bool { action == .remove && comparison.kind == .groups }

    /// Durable intent is cleared last. Cache persistence failure leaves the write/remove retryable.
    func apply(node: Node, successful: Bool, beforePersist: (() -> Bool)? = nil) -> Bool {
        guard successful, matches(node: node),
              let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) else { return false }
        if action == .remove, comparison.isDeleting {
            let models = node.elements.compactMap { $0.model(withSigModelId: .sceneSetupServerModelId) }
            guard !models.isEmpty, models.allSatisfy({ $0.parentElement?.observedSceneRegister?.contains(number) == false }) else { return false }
        }
        let previous = node.sceneExecuteDatas
        node.sceneExecuteDatas.removeAll { $0.sceneNumber == number }
        if let target { node.sceneExecuteDatas.append(target) }
        let previousConfiguration = scene.info.configuration
        if let operation { scene.info.configuration?.pendingOperations.removeAll { $0 == operation } }
        // Group relationship writes join the caller's App transaction before
        // touching the independent SDK cache database.
        guard beforePersist?() ?? true, node.savePropertys() else {
            scene.info.configuration = previousConfiguration
            node.sceneExecuteDatas = previous
            return false
        }
        node.clearSyncStateCache()
        guard operation != nil else { return true }
        do { try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID) }
        catch {
            scene.info.configuration = previousConfiguration
            node.sceneExecuteDatas = previous
            return false
        }
        return true
    }
}

private var sceneMessageContextKey: UInt8 = 0
extension MeshMessageHandle {
    var sceneContext: SceneMessageContext? {
        get { objc_getAssociatedObject(self, &sceneMessageContextKey) as? SceneMessageContext }
        set { objc_setAssociatedObject(self, &sceneMessageContextKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
