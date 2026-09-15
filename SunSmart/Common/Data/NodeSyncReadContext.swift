import Foundation
import NordicSigMeshSDK

/// Memoized reads belong to one version of one active network, never to a Node
/// permanently. Installed only while a synchronous refresh slice is executing.
final class NodeSyncReadContext {
    private static let threadKey = "SunSmart.NodeSyncReadContext"
    static var current: NodeSyncReadContext? {
        Thread.current.threadDictionary[threadKey] as? NodeSyncReadContext
    }

    func perform<T>(_ body: () -> T) -> T {
        let previous = Thread.current.threadDictionary[Self.threadKey]
        Thread.current.threadDictionary[Self.threadKey] = self
        defer { Thread.current.threadDictionary[Self.threadKey] = previous }
        return body()
    }

    let network: MeshNetwork
    let networkID: String
    let nodes: [Node]
    private let account = UserData.currentUserId
    private let region = String(describing: UserData.currentServerRegion)
    private let revision = ConfigurationSnapshotRevision.current()
    private let generation = NodeSyncStatusGeneration.current
    private let protection: SpaceProtectionReadSnapshot
    private let capture: NodeSyncTopologyCapture
    private let storage: NodeSyncTopologyStorage.Request
    private var prepared: NodeSyncPreparedTopology?
    private var workerPending = false
    private let cancellation = NodeSyncPreparationCancellation()
    private static let preparationQueue = DispatchQueue(label: "com.sunsmart.sync-topology", qos: .userInitiated)
    private struct OverrideKey: Hashable { let group: Address; let node: Address }
    private var overrides: [OverrideKey: ProximityLightingTopologyPlanner.Plan] = [:]
    private(set) var missingInputs = false
    private struct GroupSyncKey: Hashable {
        let node: ObjectIdentifier
        let explicitGroup: ObjectIdentifier?
    }
    private var groupSyncStates: [GroupSyncKey: Bool] = [:]
    private var memoizedValues: [String: Any] = [:]

    func memoized<Value>(_ key: String, read: () -> Value) -> Value {
        if let value = memoizedValues[key] as? Value { return value }
        let value = read()
        memoizedValues[key] = value
        return value
    }

    func node(elementAddress: Address) -> Node? {
        capture.elementNodes[elementAddress]
    }

    var hasRevision: Bool { revision != nil }
    func commitProtectedCaches(_ body: () -> Void) -> Bool { protection.commit(body) }

    func groupNeedsSync(for node: Node, group: Group?, compute: () -> Bool) -> Bool {
        // An explicit pending/recovery Group is not equivalent to nil context.
        let key = GroupSyncKey(node: ObjectIdentifier(node), explicitGroup: group.map(ObjectIdentifier.init))
        if let result = groupSyncStates[key] { return result }
        let result = compute()
        groupSyncStates[key] = result
        return result
    }

    init(network: MeshNetwork, networkID: String, nodes: [Node], protection: SpaceProtectionReadSnapshot) {
        self.network = network
        self.networkID = networkID
        self.nodes = nodes
        self.protection = protection
        capture = NodeSyncTopologyCapture(network: network, networkID: networkID)
        storage = .init(protection: SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: networkID))
    }

    var isPrepared: Bool { prepared != nil }
    var inputsAvailable: Bool { prepared?.isAvailable == true }

    func cancelPreparation() { cancellation.cancel() }

    /// Returns true only when another capture slice should be scheduled. Worker
    /// completion schedules its own continuation, avoiding main-queue polling.
    func prepareSlice(until deadline: TimeInterval, onReady: @escaping () -> Void) -> Bool {
        precondition(Thread.isMainThread)
        guard !workerPending && !cancellation.isCancelled && prepared == nil else { return false }
        guard capture.advance(until: deadline) else { return true }
        let input = capture.snapshot(), storage = self.storage, cancellation = self.cancellation
        workerPending = true
        Self.preparationQueue.async {
            let result = storage.read(input, isCancelled: { cancellation.isCancelled })
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.cancellation.isCancelled else { return }
                self.workerPending = false
                self.prepared = result
                onReady()
            }
        }
        return false
    }

    func prepareNode(_ node: Node, additionalGroup: Group? = nil, onReady: @escaping () -> Void) -> Bool {
        guard let prepared, !workerPending else { return false }
        guard prepared.isAvailable, node.groupState != .exitFailure else { return true }
        for group in [group(for: node), node.restoreData?.addGroup, additionalGroup].compactMap({ $0 }) {
            guard group.network?.uuid == network.uuid, group.subNetworkId == networkID else { continue }
            let key = OverrideKey(group: group.address.address, node: ProximityLightingTopologyPlanner.normalizedAddress(for: node))
            guard let source = prepared.groups.first(where: { $0.address == key.group }),
                  !source.memberAddresses.contains(key.node), overrides[key] == nil else { continue }
            workerPending = true
            let cancellation = self.cancellation
            Self.preparationQueue.async {
                guard !cancellation.isCancelled else { return }
                let result = prepared.override(groupAddress: key.group, nodeAddress: key.node)
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.cancellation.isCancelled else { return }
                    self.workerPending = false
                    self.overrides[key] = result
                    onReady()
                }
            }
            return false
        }
        return true
    }

    /// Only the status reader installs this context. Execution/authorization
    /// paths outside it continue to consult SpaceConfigurationSafety directly.
    func configurationAvailable(for node: Node, group: Group?) -> Bool? {
        guard node.network === network, node.subNetworkId == networkID else { return nil }
        let group = group ?? self.group(for: node)
        if let group, !group.isVirtual, group.info.profileLoadFailed || group.info.topologyLoadFailed { return false }
        return capture.damagedGroups.isEmpty && !protection.isBlocked && prepared?.isAvailable == true
    }

    var isCurrent: Bool {
        let manager = MeshNetworkManager.instance
        return manager.meshNetwork === network
            && manager.currentNetworkKey.networkId.hex == networkID
            && account == UserData.currentUserId
            && region == String(describing: UserData.currentServerRegion)
            && generation == NodeSyncStatusGeneration.current
            && protection.isCurrent
            && protection.scope.account == account && protection.scope.region == region
            && protection.scope.meshUUID == network.uuid.uuidString && protection.scope.networkID == networkID
            && (!isPrepared || capture.damagedGroups == Set(network.groups.filter {
                !$0.isVirtual && $0.subNetworkId == networkID && ($0.info.profileLoadFailed || $0.info.topologyLoadFailed)
            }.map(ObjectIdentifier.init)))
            && revision != nil && revision == ConfigurationSnapshotRevision.current()
    }

    func group(for node: Node) -> Group? {
        capture.memberships[ObjectIdentifier(node)]
    }

    func members(of group: Group) -> [Node] {
        capture.groupNodes[group.address.address] ?? []
    }

    func contains(_ node: Node, in group: Group) -> Bool {
        self.group(for: node)?.address == group.address
    }

    func plan(for node: Node, contextGroup: Group?) -> ProximityLightingTopologyPlanner.Plan? {
        guard node.network === network, node.subNetworkId == networkID, let prepared else {
            missingInputs = true; return .unavailable
        }
        let group = contextGroup ?? self.group(for: node)
        if let group {
            guard group.network?.uuid == network.uuid, group.subNetworkId == networkID else { return .unavailable }
            let key = OverrideKey(group: group.address.address, node: ProximityLightingTopologyPlanner.normalizedAddress(for: node))
            if node.groupState != .exitFailure,
               let source = prepared.groups.first(where: { $0.address == key.group }),
               !source.memberAddresses.contains(key.node) {
                guard let plan = overrides[key] else { missingInputs = true; return .unavailable }
                return plan
            }
        }
        return prepared.plan
    }

    func mergedTarget(for node: Node, local: ProximityLightingTopologyPolicy.Target)
        -> ProximityLightingTopologyPolicy.Target? {
        guard node.network === network, node.subNetworkId == networkID, let prepared else {
            missingInputs = true; return nil
        }
        return prepared.site.target(for: node, local: local)
    }

}

extension Node {
    var syncReadGroup: Group? {
        guard let context = NodeSyncReadContext.current else { return group }
        return context.group(for: self)
    }
}

/// Device-state cache invalidation also invalidates in-flight batch reads,
/// including changes that have not yet been persisted to either database.
enum NodeSyncStatusGeneration {
    private static let lock = NSLock()
    private static var value: UInt64 = 0

    static var current: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value
    }

    static func invalidate() {
        lock.lock(); defer { lock.unlock() }
        value &+= 1
    }
}
