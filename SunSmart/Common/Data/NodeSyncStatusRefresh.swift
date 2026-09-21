import Foundation
import NordicSigMeshSDK

/// One main-queue batch replaces the independent Cell, page and warm-up jobs.
/// Existing sync readers use live Mesh objects, so slices run alongside their
/// main-queue owners instead of introducing more concurrent mutable reads.
enum NodeSyncStatusRefresh {
    private struct Status {
        let device: Bool
        let group: Bool
    }

    private enum Selection {
        case nodes([Node])
        case nodeGroup(Node)
        case group(Group)
        case warmUp([Node])
        case read(AnyObject, MeshNetwork?, String, () -> Bool, (NodeSyncReadContext) -> (TimeInterval) -> Bool?)
    }

    private final class Request {
        let selection: Selection
        let completion: (Bool) -> Void
        var cursor = 0
        var validated = false
        var read: ((TimeInterval) -> Bool?)?
        init(selection: Selection, completion: @escaping (Bool) -> Void) {
            self.selection = selection; self.completion = completion
        }
        var isWarmUp: Bool { if case .warmUp = selection { return true }; return false }
    }

    private static var requests: [ObjectIdentifier: Request] = [:]
    private static var context: NodeSyncReadContext?
    private static var results: [ObjectIdentifier: Status] = [:]
    private static var readResults: [ObjectIdentifier: (object: AnyObject, value: Bool)] = [:]
    private static weak var sessionOwner: AnyObject?
    private static var sessionOwnerID: ObjectIdentifier?
    private static var scheduled = false
    private static let protectionQueue = DispatchQueue(label: "com.sunsmart.sync-protection-read", qos: .userInitiated)
    private static var preparing: UUID?
    private static var preparationNetwork: MeshNetwork?
    private static var batch: AppPerformance.Interval?
    private static let foregroundObserver = NotificationCenter.default.addObserver(
        forName: .init("UIApplicationWillEnterForegroundNotification"), object: nil, queue: nil
    ) { _ in SpaceProtectionReadGeneration.invalidate() }

    static func request(nodes: [Node], owner: AnyObject, completion: @escaping (Bool) -> Void) {
        AppPerformance.event("SyncNodeRequest", value: nodes.count)
        enqueue(.nodes(nodes), owner: owner, completion: completion)
    }

    static func request(group: Group, owner: AnyObject, completion: @escaping (Bool) -> Void) {
        AppPerformance.event("SyncGroupRequest")
        enqueue(.group(group), owner: owner, completion: completion)
    }

    /// Same nil-Group semantics as Node.needSyncGroupData, not device needSync.
    static func requestGroupData(node: Node, owner: AnyObject, completion: @escaping (Bool) -> Void) {
        enqueue(.nodeGroup(node), owner: owner, completion: completion)
    }

    /// Live appearance never waits for protection/topology preparation. Reuse
    /// only membership from a valid context, not the cached synchronization result.
    static func groupOnOffStates(_ groups: [Group]) -> [Bool] {
        mapGroupMembers(groups) { group, members in group.isOn(members: members()) }
    }

    static func sceneGroupAppearances(_ groups: [Group]) -> [ObjectIdentifier: SceneGroupAppearance] {
        let values = mapGroupMembers(groups) { group, members in
            let nodes = members()
            return (ObjectIdentifier(group), SceneGroupAppearance(
                isOn: group.isOn(members: nodes), cctRange: group.effectiveCctRange(members: nodes)))
        }
        return Dictionary(uniqueKeysWithValues: values)
    }

    private static func mapGroupMembers<Value>(_ groups: [Group],
                                               read: (Group, () -> [Node]) -> Value) -> [Value] {
        precondition(Thread.isMainThread)
        guard !groups.isEmpty else { return [] }
        if let context, context.isPrepared, context.inputsAvailable, context.isCurrent,
           groups.allSatisfy({ $0.network === context.network && $0.subNetworkId == context.networkID }) {
            return groups.map { group in read(group, { context.members(of: group) }) }
        }
        // One lazy projection per display batch also works when sync inputs are
        // unavailable. A local Group override does not require any member read.
        var members: [Address: [Node]]?
        func liveMembers(of group: Group) -> [Node] {
            if members == nil {
                var grouped: [Address: [Node]] = [:]
                for node in MeshNetworkManager.instance.realNodes {
                    if let address = node.group?.address.address {
                        grouped[address, default: []].append(node)
                    }
                }
                members = grouped
            }
            return members?[group.address.address] ?? []
        }
        return groups.map { group in read(group, { liveMembers(of: group) }) }
    }

    static func warmUp(nodes: [Node], owner: AnyObject) {
        AppPerformance.event("SyncWarmUpRequest", value: nodes.count)
        enqueue(.warmUp(nodes), owner: owner, completion: { _ in })
    }

    /// A Space owns reuse; closing a child page only cancels that page's request.
    static func beginSession(owner: AnyObject) {
        precondition(Thread.isMainThread)
        requests.removeAll()
        reset()
        sessionOwner = owner
        sessionOwnerID = ObjectIdentifier(owner)
        AppPerformance.event("SyncSessionBegin")
    }

    static func endSession(owner: AnyObject) {
        precondition(Thread.isMainThread)
        // A weak reference may already be nil when the owner's deinit runs.
        guard sessionOwnerID == ObjectIdentifier(owner) else { return }
        sessionOwner = nil
        sessionOwnerID = nil
        requests.removeAll()
        reset()
        AppPerformance.event("SyncSessionEnd")
    }

    /// nil means that another slice is needed, not that the item is synchronized.
    static func requestRead(object: AnyObject, owner: AnyObject,
                            isValid: @escaping () -> Bool = { true },
                            makeRead: @escaping (NodeSyncReadContext) -> (TimeInterval) -> Bool?,
                            completion: @escaping (Bool) -> Void) {
        let manager = MeshNetworkManager.instance
        enqueue(.read(object, manager.meshNetwork, manager.currentNetworkKey.networkId.hex, isValid, makeRead),
                owner: owner, completion: completion)
    }

    static func cancel(owner: AnyObject) {
        precondition(Thread.isMainThread)
        AppPerformance.event("SyncCancelled")
        requests.removeValue(forKey: ObjectIdentifier(owner))
        if requests.isEmpty { finishBatch() }
    }

    private static func enqueue(_ selection: Selection, owner: AnyObject, completion: @escaping (Bool) -> Void) {
        precondition(Thread.isMainThread)
        _ = foregroundObserver
        AppPerformance.event("SyncRequest")
        requests[ObjectIdentifier(owner)] = Request(selection: selection, completion: completion)
        schedule()
    }

    private static func schedule() {
        guard !scheduled else { return }
        scheduled = true
        DispatchQueue.main.async { step() }
    }

    private static func step() {
        precondition(Thread.isMainThread)
        let fullStep = AppPerformance.begin("SyncMainStep")
        defer { fullStep.end() }
        scheduled = false
        guard !requests.isEmpty else { finishBatch(); return }
        let manager = MeshNetworkManager.instance
        guard let network = manager.meshNetwork else { requests.removeAll(); reset(); return }
        let networkID = manager.currentNetworkKey.networkId.hex
        guard preparing == nil else { return }
        if context?.isCurrent != true {
            reset()
            batch = AppPerformance.begin("SyncBatch")
            let request = SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: networkID)
            let ticket = UUID()
            preparing = ticket
            preparationNetwork = network
            // Protection and topology have separate scoped, read-only inputs.
            protectionQueue.async {
                let protection = request.read()
                DispatchQueue.main.async {
                    let preparation = AppPerformance.begin("SyncMainPrepare")
                    defer { preparation.end() }
                    guard preparing == ticket else { return }
                    preparing = nil
                    guard !requests.isEmpty else { finishBatch(); return }
                    let manager = MeshNetworkManager.instance
                    guard let current = manager.meshNetwork, current === preparationNetwork,
                          current.uuid.uuidString == request.scope.meshUUID,
                          manager.currentNetworkKey.networkId.hex == request.scope.networkID,
                          UserData.currentUserId == request.scope.account,
                          String(describing: UserData.currentServerRegion) == request.scope.region else {
                        schedule(); return
                    }
                    preparationNetwork = nil
                    // Do not spin while an import/recovery writer is active.
                    guard let currentVersion = SpaceProtectionReadGeneration.current else {
                        finishUnavailable(); return
                    }
                    guard protection.version == currentVersion else {
                        // A writer finished (or invalidation occurred) before
                        // this callback. Keep all pending/replaced requests and
                        // read the now-stable generation instead of failing them.
                        reset(); schedule(); return
                    }
                    guard protection.failure == nil else { finishUnavailable(); return }
                    context = NodeSyncReadContext(network: current, networkID: networkID,
                                                  nodes: manager.realNodes, protection: protection)
                    AppPerformance.event("SyncProtectionGeneration", value: Int(truncatingIfNeeded: protection.version ?? 0))
                    guard context?.hasRevision == true else { finishUnavailable(); return }
                    schedule()
                }
            }
            return
        }
        guard let context else { return }
        guard context.hasRevision else {
            finishUnavailable()
            return
        }
        let start = ProcessInfo.processInfo.systemUptime
        if !context.isPrepared {
            if context.prepareSlice(until: start + 0.004, onReady: { schedule() }) { schedule() }
            return
        }
        guard context.inputsAvailable else { finishUnavailable(); return }
        var waitingForInputs = false
        var completed: [(ObjectIdentifier, Request, Bool?)] = []
        var exhaustedBudget = false
        var calculated: [(Node, Status)] = []
        context.perform {
            let pending = requests.sorted { !$0.value.isWarmUp && $1.value.isWarmUp }
            for (owner, request) in pending {
                if case .read(let object, let sourceNetwork, let sourceID, let isValid, let makeRead) = request.selection {
                    guard sourceNetwork === network, sourceID == networkID, isValid() else {
                        completed.append((owner, request, nil)); continue
                    }
                    let key = ObjectIdentifier(object)
                    if let cached = readResults[key] {
                        AppPerformance.event("SyncPageResultHit")
                        completed.append((owner, request, cached.value))
                    } else {
                        let interval = AppPerformance.begin("SyncPageRead")
                        if request.read == nil { request.read = makeRead(context) }
                        let result = request.read?(start + 0.004)
                        interval.end()
                        if let result {
                            readResults[key] = (object, result)
                            completed.append((owner, request, result))
                        }
                    }
                    if ProcessInfo.processInfo.systemUptime - start >= 0.004 { exhaustedBudget = true }
                    if exhaustedBudget { break }
                    continue
                }
                let nodes: [Node]
                let groupOnly: Bool
                let warmUp: Bool
                switch request.selection {
                case .nodes(let selected): nodes = selected; groupOnly = false; warmUp = false
                case .nodeGroup(let node): nodes = [node]; groupOnly = true; warmUp = false
                case .warmUp(let selected): nodes = selected; groupOnly = false; warmUp = true
                case .group(let group):
                    guard group.network === network, group.subNetworkId == networkID else {
                        completed.append((owner, request, nil)); continue
                    }
                    nodes = context.members(of: group); groupOnly = true; warmUp = false
                case .read: continue
                }
                // Requests from the previous Space never inspect the new active network.
                if !request.validated {
                    guard nodes.allSatisfy({ $0.network === network && $0.subNetworkId == networkID }) else {
                        completed.append((owner, request, nil)); continue
                    }
                    request.validated = true
                }
                var needsSync = false
                var finished = true
                while request.cursor < nodes.count {
                    let node = nodes[request.cursor]
                    let key = ObjectIdentifier(node)
                    let status: Status
                    if let cached = results[key] {
                        status = cached
                        AppPerformance.event("SyncResultHit")
                    } else {
                        guard context.prepareNode(node, onReady: { schedule() }) else {
                            waitingForInputs = true; finished = false; break
                        }
                        AppPerformance.event("SyncNodeComputed")
                        let nodeInterval = AppPerformance.begin("SyncNodeCheck")
                        defer { nodeInterval.end() }
                        let groupNeedsSync = node.getNeedSyncGroup()
                        status = Status(device: groupNeedsSync || node.getNeedSync(), group: groupNeedsSync)
                        results[key] = status
                        calculated.append((node, status))
                    }
                    request.cursor += 1
                    if !warmUp && (groupOnly ? status.group : status.device) {
                        needsSync = true
                        break
                    }
                    if ProcessInfo.processInfo.systemUptime - start >= 0.004 {
                        finished = false; exhaustedBudget = true; break
                    }
                }
                if finished { completed.append((owner, request, needsSync)) }
                if waitingForInputs || exhaustedBudget || ProcessInfo.processInfo.systemUptime - start >= 0.004 { break }
            }
        }
        guard !context.missingInputs else { finishUnavailable(); return }
        // Persisted changes or explicit device invalidation during a read must
        // not publish stale UI/cache results. Retry against the new generation.
        guard context.isCurrent else {
            AppPerformance.event("SyncInvalidated")
            reset()
            schedule()
            return
        }
        let publication = AppPerformance.begin("SyncPublish")
        defer { publication.end() }
        guard context.commitProtectedCaches({
            for (node, status) in calculated {
                node.cacheGroupNeedSync = status.group
                node.cacheNeedSync = status.group ? false : status.device
            }
        }) else { reset(); schedule(); return }
        for (owner, request, result) in completed {
            // A prior callback may replace/cancel another owner's selection.
            guard requests[owner] === request else { continue }
            guard context.isCurrent else { reset(); schedule(); return }
            requests.removeValue(forKey: owner)
            if let result { context.perform { request.completion(result) } }
        }
        if requests.isEmpty { finishBatch() } else if !waitingForInputs { schedule() }
    }

    private static func finishBatch() {
        batch?.end()
        batch = nil
        // Do not retain an unfinished worker after all request owners cancelled.
        guard sessionOwner != nil, context?.isPrepared == true else { reset(); return }
    }

    private static func finishUnavailable() {
        let pending = requests
        reset()
        AppPerformance.event("SyncUnavailable")
        for (owner, request) in pending where requests[owner] === request {
            requests.removeValue(forKey: owner)
            request.completion(true)
        }
        if !requests.isEmpty { schedule() }
    }

    private static func reset() {
        batch?.end()
        batch = nil
        preparing = nil
        preparationNetwork = nil
        for request in requests.values { request.cursor = 0; request.validated = false; request.read = nil }
        context?.cancelPreparation()
        context = nil
        results.removeAll()
        readResults.removeAll()
    }
}

/// A display owner can reuse a result only for the same object and Space revision.
/// The refresher still owns shared computation, protection and in-flight retries.
final class GroupSyncDisplayState {
    private weak var object: AnyObject?
    private var revision: SpacePageRevision?
    private var value: Bool?
    private var reading = false
    private var ticket = UUID()

    func needsSync(for object: AnyObject) -> Bool? {
        self.object === object && revision?.isCurrent == true ? value : nil
    }

    func refresh(node: Node, didUpdate: @escaping () -> Void) {
        refresh(object: node, request: { completion in
            NodeSyncStatusRefresh.requestGroupData(node: node, owner: self, completion: completion)
        }, didUpdate: didUpdate)
    }

    func refresh(group: Group, didUpdate: @escaping () -> Void) {
        refresh(object: group, request: { completion in
            NodeSyncStatusRefresh.request(group: group, owner: self, completion: completion)
        }, didUpdate: didUpdate)
    }

    private func refresh(object: AnyObject, request: (@escaping (Bool) -> Void) -> Void,
                         didUpdate: @escaping () -> Void) {
        if self.object === object, needsSync(for: object) != nil || reading { return }
        cancel()
        self.object = object
        value = nil
        reading = true
        let ticket = self.ticket
        request { [weak self] value in
            guard let self, self.ticket == ticket else { return }
            self.reading = false
            self.value = value
            self.revision = SpacePageRevision()
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
