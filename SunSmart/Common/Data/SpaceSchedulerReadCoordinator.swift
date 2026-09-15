import Foundation
import NordicSigMeshSDK

/// A Space owns one queue. Page appearances express demand, not a new scan job.
final class SpaceSchedulerReadQueue<Item> {
    private let candidates: () -> [Item]
    private let identifier: (Item) -> UUID
    private let isCurrent: () -> Bool
    private let connected: () -> Bool
    private let busy: () -> Bool
    private let read: ([Item], @escaping () -> Void) -> Void
    private let updated: () -> Void
    private let now: () -> TimeInterval
    private var retryAfter: [UUID: TimeInterval] = [:]
    private var pending: [Item] = []
    private var cursor = 0
    private var running = false
    private var stopped = false
    private var continuation: DispatchWorkItem?

    init(candidates: @escaping () -> [Item], identifier: @escaping (Item) -> UUID,
         isCurrent: @escaping () -> Bool, connected: @escaping () -> Bool,
         busy: @escaping () -> Bool, now: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         read: @escaping ([Item], @escaping () -> Void) -> Void, updated: @escaping () -> Void) {
        self.candidates = candidates; self.identifier = identifier
        self.isCurrent = isCurrent; self.connected = connected; self.busy = busy
        self.now = now; self.read = read; self.updated = updated
    }

    func request() {
        precondition(Thread.isMainThread)
        guard !stopped, !running, isCurrent(), connected() else { return }
        var selected = Set<UUID>()
        pending = candidates().filter {
            let id = identifier($0)
            return selected.insert(id).inserted && (retryAfter[id] ?? 0) <= now()
        }
        guard !pending.isEmpty else { return }
        cursor = 0; running = true
        schedule(after: 0)
    }

    func stop() {
        precondition(Thread.isMainThread)
        stopped = true; running = false
        continuation?.cancel(); continuation = nil
        pending.removeAll(); retryAfter.removeAll()
    }

    private func schedule(after delay: TimeInterval) {
        let work = DispatchWorkItem { [weak self] in self?.step() }
        continuation = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func step() {
        continuation = nil
        guard !stopped else { return }
        guard isCurrent() else { stop(); return }
        guard connected(), cursor < pending.count else {
            pending.removeAll(); running = false; return
        }
        guard !busy() else { schedule(after: 0.5); return }
        // Foreground reads may have made pending nodes known while Mesh was
        // busy or the previous batch was in flight. Resolve current instances
        // immediately before submission, without expanding this demand's scope.
        let currentCandidates = Dictionary(candidates().map { (identifier($0), $0) },
                                           uniquingKeysWith: { first, _ in first })
        var batch: [Item] = []
        while cursor < pending.count && batch.count < 2 {
            let id = identifier(pending[cursor])
            cursor += 1
            if let item = currentCandidates[id], (retryAfter[id] ?? 0) <= now() {
                batch.append(item)
            }
        }
        guard !batch.isEmpty else { pending.removeAll(); running = false; return }
        // Preserve SDK node-level atomicity, while keeping the shared Mesh queue short.
        read(batch) { [weak self] in
            guard let self, !self.stopped else { return }
            guard self.isCurrent() else { self.stop(); return }
            // Known-empty entries remain cached by the SDK. Unknown/failed nodes
            // can be attempted by later demand, after cooldown, never in a loop.
            for item in batch { self.retryAfter[self.identifier(item)] = self.now() + 30 }
            self.updated()
            self.schedule(after: 0.1)
        }
    }
}

final class SpaceSchedulerReadCoordinator {
    static let didUpdate = Notification.Name("SpaceSchedulerReadDidUpdate")
    private let queue: SpaceSchedulerReadQueue<Node>

    init(space: SpaceData) {
        let network = MeshNetworkManager.instance.meshNetwork
        let account = UserData.currentUserId
        let region = String(describing: UserData.currentServerRegion)
        let meshUUID = space.meshUUID, networkID = space.meshNetworkId
        queue = SpaceSchedulerReadQueue(candidates: {
            let manager = MeshNetworkManager.instance
            let explicitTargets = Set(manager.schedules.flatMap(\.nodeAddresses))
            let unknown = manager.realNodes.filter { node in
                node.deviceType != .dongle && TimedSchedulerCacheRepairPolicy.needsAuthoritativeRead(
                    modelKnownStates: node.schedulerSetupModels.map { node.allSchedulerModelEntrys[$0] != nil })
            }
            // Legacy entries are not authoritative, but they are a useful hint
            // for read priority without expanding every Group on page entry.
            let priority = Set(unknown.filter {
                explicitTargets.contains($0.primaryUnicastAddress) || !$0.schedulerActions.isEmpty
            }.map(\.uuid))
            return unknown.filter { priority.contains($0.uuid) } + unknown.filter { !priority.contains($0.uuid) }
        }, identifier: { $0.uuid }, isCurrent: {
            let manager = MeshNetworkManager.instance
            return network != nil && manager.meshNetwork === network
                && network?.uuid.uuidString == meshUUID
                && manager.currentNetworkKey.networkId.hex == networkID
                && account == UserData.currentUserId
                && region == String(describing: UserData.currentServerRegion)
        }, connected: { MeshLibManager.manager.isMeshNetworkConnected }, busy: {
            MeshProxyMessageCommand.shared.isBusy
        }, read: { nodes, completion in
            AppPerformance.event("SchedulerRepairBatch", value: nodes.count)
            MeshAPI.getSchedule(index: nil, nodes: nodes, successful: nil, failed: nil,
                                finished: { successful, failed in
                DispatchQueue.main.async {
                    #if DEBUG
                    print("[SchedulerModelCacheRepair] batch success=\(successful.count) failed=\(failed.count)")
                    #endif
                    completion()
                }
            })
        }, updated: {
            NodeSyncStatusGeneration.invalidate()
            NotificationCenter.default.post(name: Self.didUpdate, object: nil)
        })
    }

    func request() { queue.request() }
    func stop() { queue.stop() }
}
