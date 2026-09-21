import Foundation
import NordicSigMeshSDK

/// UI reuse follows the same conservative invalidation boundary as sync reads.
struct SpacePageRevision {
    private let network = MeshNetworkManager.instance.meshNetwork
    private let networkID = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
    private let revision = ConfigurationSnapshotRevision.current()
    private let generation = NodeSyncStatusGeneration.current
    private let protection = SpaceProtectionReadGeneration.current

    var isCurrent: Bool {
        network === MeshNetworkManager.instance.meshNetwork
            && networkID == MeshNetworkManager.instance.currentNetworkKey.networkId.hex
            && revision != nil && revision == ConfigurationSnapshotRevision.current()
            && generation == NodeSyncStatusGeneration.current
            && protection != nil && protection == SpaceProtectionReadGeneration.current
    }
}

/// Display-only queries. Execution still builds its complete, authorized plan.
/// The refresher's read context supplies one version of membership/protection.
final class SpacePageSyncRead {
    private enum Check {
        case scene(Node, Scene)
        case schedule(Node, Schedule, Group?, delete: Bool)

        func needsSync() -> Bool {
            switch self {
            case .scene(let node, let scene):
                return !node.getSyncData(type: .scenes(scene: scene)).isEmpty
            case .schedule(let node, let schedule, let group, let delete):
                return delete ? schedule.needsDelete(from: node, contextGroup: group)
                    : schedule.needsSync(on: node, contextGroup: group)
            }
        }
    }

    private var checks: [Check] = []
    private var cursor = 0

    init(scene: Scene, context: NodeSyncReadContext) {
        checks = scene.info.groups.flatMap { group in
            context.members(of: group).map { .scene($0, scene) }
        }
    }

    init(schedule: Schedule, context: NodeSyncReadContext) {
        var targets: [(Node, Group?)] = []
        switch schedule.selectTargetType {
        case .devices:
            let addresses = Set(schedule.nodeAddresses)
            targets = context.nodes.filter { addresses.contains($0.primaryUnicastAddress) }.map { ($0, nil) }
        case .groups, .scene:
            let groups = schedule.selectTargetType == .groups ? schedule.groups : schedule.scene?.info.groups ?? []
            for group in groups {
                targets += context.members(of: group)
                    .filter { schedule.targets(node: $0, contextGroup: group) }.map { ($0, group) }
            }
        case .profile:
            break
        }
        checks = targets.map { .schedule($0.0, schedule, $0.1, delete: false) }
        let targetIDs = Set(targets.map { ObjectIdentifier($0.0) })
        // The full planner also scans all real nodes for orphaned entries.
        // Preserve explicit pending Group contexts, which may change targets().
        let pendingGroups = schedule.needDeleteGroups
            + schedule.needDeleteScenes.flatMap { $0.info.groups }
        for group in pendingGroups {
            checks += context.members(of: group).filter { !targetIDs.contains(ObjectIdentifier($0)) }
                .map { .schedule($0, schedule, group, delete: true) }
        }
        checks += context.nodes.filter { !targetIDs.contains(ObjectIdentifier($0)) }
            .map { .schedule($0, schedule, nil, delete: true) }
    }

    func advance(until deadline: TimeInterval) -> Bool? {
        while cursor < checks.count {
            AppPerformance.event("SyncPageNodeCheck")
            let result = checks[cursor].needsSync()
            cursor += 1
            if result { return true }
            if ProcessInfo.processInfo.systemUptime >= deadline { return nil }
        }
        return false
    }
}

extension NodeSyncStatusRefresh {
    static func request(scene: Scene, owner: AnyObject, completion: @escaping (Bool) -> Void) {
        requestSceneGroups(scene: scene, owner: owner) { snapshot in
            completion(snapshot?.needsSync.isEmpty != true)
        }
    }

    /// The list, detail and settings use the same completed result and in-flight
    /// reader. The context owns its lifetime and invalidates it with protection.
    static func requestSceneGroups(scene: Scene, owner: AnyObject,
                                   completion: @escaping (SceneGroupSyncSnapshot?) -> Void) {
        requestRead(object: scene, owner: owner, isValid: {
            MeshNetworkManager.instance.scenes.contains { $0 === scene }
        }, makeRead: { context in
            let read = context.sceneGroupRead(scene)
            return { read.advance(until: $0) }
        }, completion: { _ in
            // Successful publication runs inside the validated read context;
            // unavailable input deliberately publishes no synchronized snapshot.
            completion(NodeSyncReadContext.current?.sceneGroupRead(scene).result)
        })
    }

    static func request(schedule: Schedule, owner: AnyObject, completion: @escaping (Bool) -> Void) {
        requestRead(object: schedule, owner: owner, isValid: {
            MeshNetworkManager.instance.schedules.contains { $0 === schedule }
        }, makeRead: { context in
            let read = SpacePageSyncRead(schedule: schedule, context: context)
            return { read.advance(until: $0) }
        }, completion: completion)
    }
}

struct SceneGroupSyncSnapshot {
    let groups: [Group]
    let needsSync: Set<ObjectIdentifier>
    private let revision = SpacePageRevision()
    var isCurrent: Bool { revision.isCurrent }
}

struct SceneGroupAppearance {
    let isOn: Bool
    let cctRange: ClosedRange<UInt16>
}

/// One page owns cancellation; reusable results remain in the Space read context.
final class SceneGroupDisplayState {
    private var snapshot: SceneGroupSyncSnapshot?
    private weak var scene: Scene?
    private var ticket = UUID()
    private var reading = false

    var currentSnapshot: SceneGroupSyncSnapshot? {
        snapshot?.isCurrent == true ? snapshot : nil
    }

    func refresh(scene: Scene, didUpdate: @escaping () -> Void) {
        if self.scene === scene, currentSnapshot != nil || reading { return }
        cancel()
        self.scene = scene
        snapshot = nil
        reading = true
        let ticket = self.ticket
        NodeSyncStatusRefresh.requestSceneGroups(scene: scene, owner: self) { [weak self] snapshot in
            guard let self, self.ticket == ticket else { return }
            self.reading = false
            self.snapshot = snapshot
            didUpdate()
        }
    }

    func cancel() {
        ticket = UUID()
        reading = false
        NodeSyncStatusRefresh.cancel(owner: self)
    }

    deinit { NodeSyncStatusRefresh.cancel(owner: self) }
}

private extension NodeSyncReadContext {
    func sceneGroupRead(_ scene: Scene) -> SceneGroupSyncRead {
        memoized("scene-groups-\(ObjectIdentifier(scene))") {
            SceneGroupSyncRead(scene: scene, context: self)
        }
    }
}

/// Each member is checked at most once per Scene/version, including overlapping
/// list and detail requests. Only the existing Scene comparison is evaluated.
final class SceneGroupSyncRead {
    private let scene: Scene
    private let groups: [(group: Group, nodes: [Node])]
    private var groupIndex = 0
    private var nodeIndex = 0
    private var needsSync = Set<ObjectIdentifier>()
    private(set) var result: SceneGroupSyncSnapshot?

    init(scene: Scene, context: NodeSyncReadContext) {
        self.scene = scene
        groups = scene.info.groups.map { ($0, context.members(of: $0)) }
    }

    func advance(until deadline: TimeInterval) -> Bool? {
        if let result { return !result.needsSync.isEmpty }
        guard let context = NodeSyncReadContext.current, context.isProtectionAvailable else { return true }
        while groupIndex < groups.count {
            let entry = groups[groupIndex]
            if nodeIndex < entry.nodes.count {
                let node = entry.nodes[nodeIndex]
                guard context.configurationAvailable(for: node, group: entry.group) == true else { return true }
                AppPerformance.event("SyncPageNodeCheck")
                nodeIndex += 1
                if !node.getSyncData(type: .scenes(scene: scene)).isEmpty {
                    needsSync.insert(ObjectIdentifier(entry.group))
                    nodeIndex = entry.nodes.count
                }
            }
            if nodeIndex == entry.nodes.count { groupIndex += 1; nodeIndex = 0 }
            if ProcessInfo.processInfo.systemUptime >= deadline { return nil }
        }
        result = SceneGroupSyncSnapshot(groups: groups.map(\.group), needsSync: needsSync)
        return !needsSync.isEmpty
    }
}
