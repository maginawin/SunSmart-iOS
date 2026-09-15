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
        requestRead(object: scene, owner: owner, isValid: {
            MeshNetworkManager.instance.scenes.contains { $0 === scene }
        }, makeRead: { context in
            let read = SpacePageSyncRead(scene: scene, context: context)
            return { read.advance(until: $0) }
        }, completion: completion)
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
