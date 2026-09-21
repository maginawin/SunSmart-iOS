import Foundation
import Darwin

typealias Address = UInt16
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    var isGroup: Bool { self >= 0xC000 }
    var isSpecialGroup: Bool { self >= 0xFF00 }
    static let meshOTAGroupAddress: UInt16 = 0xFF01
    static let localClientGroupAddress: UInt16 = 0xFF02
    static let subElementBroadcastGroupAddress: UInt16 = 0xFF03
}
extension String { var hex: String { self }; var localizedString: String { self } }
struct MeshAddress: Equatable { let address: Address }
struct SpaceTriggerZone { struct Item { let groupAddress: Address; let deviceAddress: Address }; var items: [Item] }
final class Profile {
    enum Kind { case ordinary, proximityLighting, proximityLightingWithPhotocell }
    var type = Kind.proximityLighting
    var proximityLightingNumber: UInt8 = 2
}
final class GroupProximityLightingPathData {
    struct Item { let address: Address? }
    struct Path { let items: [Item] }
    struct Zone { let addresses: [Address] }
    var paths: [Path] = []; var zones: [Zone] = []
}
final class GroupInfo {
    var imageText: String?, imageId = 1
    var profile = Profile(), proximityLightingPath: GroupProximityLightingPathData? = nil
    var profileLoadFailed = false, topologyLoadFailed = false
    static func load(meshUUID: String, address: Address, subnetworkId: String?) -> GroupInfo? { GroupInfo() }
    static func unavailable(address: Address) -> GroupInfo { let i = GroupInfo(); i.profileLoadFailed = true; return i }
}
final class Group: Equatable {
    var name = "Group 1"
    let address: MeshAddress
    let subscriptionAddress: String
    var isVirtual = false, info = GroupInfo(), subNetworkId: String? = "net"
    weak var network: MeshNetwork?
    init(_ address: Address) { self.address = .init(address: address); subscriptionAddress = address.hex }
    var nodes: [Node] { MeshNetworkManager.instance.realNodes.filter { $0.group?.address == address } }
    static func ==(lhs: Group, rhs: Group) -> Bool { lhs === rhs }
}
final class Element {
    var models: [Model] = []; let unicastAddress: Address
    weak var parentNode: Node?
    init(_ address: Address) { unicastAddress = address }
}
final class Model {
    static var subscriptionReads = 0
    static var makeSubscriptionLookup: (([Address]) -> (Address) -> Bool)?
    private var lookup: ((Address) -> Bool)?
    weak var parentElement: Element?
    private var strings: [String] = []
    var subscribe: [Address] {
        get { strings.compactMap { UInt16($0, radix: 16) } }
        set { strings = newValue.map { $0.hex }; lookup = Self.makeSubscriptionLookup?(newValue) }
    }
    var subscriptions: [Group] {
        Self.subscriptionReads += 1
        return (parentElement?.parentNode?.network?.groups ?? []).filter { lookup?($0.address.address) ?? strings.contains($0.subscriptionAddress) }
    }
    func isSubscribed(to address: MeshAddress) -> Bool { lookup?(address.address) ?? strings.contains(address.address.hex) }
}
final class Node: Equatable {
    enum GroupState { case inGroup, exitFailure }
    let uuid = UUID(), primaryUnicastAddress: Address
    weak var network: MeshNetwork?
    var subNetworkId: String? = "net", elements: [Element] = []
    var isLocalProvisioner = false, isProvisioner = false, isConfigComplete = false
    var groupState = GroupState.inGroup
    var isOn = false
    var state = true, isKeybindComplete = true, deviceOnlyNeedSync = false
    var elControllerLightsIconName: String { "device_normal" }
    var unsyncIconName: String { "device_unsynced" }
    var effectiveSupportCct = false
    var effectiveCctRange: ClosedRange<UInt16> = 2700...6500
    var sceneChecks = 0
    static var onSceneCheck: ((Node) -> Void)?
    var group: Group? {
        for element in elements {
            for model in element.models {
                if let group = model.subscriptions.first(where: NodeSyncTopologyCapture.isMembershipGroup) { return group }
            }
        }
        return nil
    }
    var sunricherVendorModel: Model? { elements.first?.models.first }
    var proximityLightingEnabled = false, proximityLightingRelayCount: UInt8? = nil
    var proximityLightingNeighborAddresses: [Address] = []
    var cacheNeedSync: Bool?, cacheGroupNeedSync: Bool?
    struct RestoreData { var addGroup: Group? }
    var restoreData: RestoreData?
    var checks = 0
    static var perNodeDelay = 0.0
    static var onCheck: ((Node) -> Void)?
    init(_ address: Address) {
        primaryUnicastAddress = address
        let element = Element(address); element.parentNode = self
        let model = Model(); model.parentElement = element; element.models = [model]; elements = [element]
    }
    func getNeedSync() -> Bool {
        if deviceOnlyNeedSync { return true }
        guard let pending = restoreData?.addGroup else { return false }
        return getNodeSyncProximityLighting(group: pending) != nil
    }
    func getNeedSyncGroup() -> Bool {
        checks += 1
        guard SpaceConfigurationSafety.configurationAvailable(for: self, group: nil) else { return true }
        if Self.perNodeDelay > 0 { Thread.sleep(forTimeInterval: Self.perNodeDelay) }
        let result = getNodeSyncProximityLighting() != nil
        Self.onCheck?(self)
        return result
    }
    static func ==(lhs: Node, rhs: Node) -> Bool { lhs.uuid == rhs.uuid && lhs.isConfigComplete == rhs.isConfigComplete }
}
final class MeshNetwork {
    let uuid = UUID(); var nodes: [Node] = [], groups: [Group] = []
    static func load(meshUUID: String, subnetworkId: String) -> MeshNetwork? { nil }
}
final class MeshNetworkManager {
    struct Key { var networkId = "net" }
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?, currentNetworkKey = Key()
    var scenes: [Scene] = [], schedules: [Schedule] = []
    var realNodes: [Node] { meshNetwork?.nodes.filter { !$0.isProvisioner && !$0.isConfigComplete } ?? [] }
}
final class SpaceData {
    var meshUUID: String, meshNetworkId = "net", triggerZones: [SpaceTriggerZone] = []
    var triggerZonesLoadFailed = false
    init(_ network: MeshNetwork) { meshUUID = network.uuid.uuidString }
    static var current: SpaceData?
    static func load(subNetworkId: String) -> SpaceData? { current }
}
enum UserData { static var currentUserId = "test", currentServerRegion = "region" }
struct ConfigurationSnapshotRevision: Equatable {
    static var value: Int? = 0
    let value: Int
    static func current() -> Self? { value.map { .init(value: $0) } }
}
enum SpaceConfigurationSafety {
    static var currentConfigurationAvailable = true {
        didSet { SpaceProtectionReadGeneration.invalidate() }
    }
    static let root = FileManager.default.temporaryDirectory.appendingPathComponent("sync-empty-" + UUID().uuidString)
    static func syncReadRequest(meshUUID: String, networkId: String) -> SpaceProtectionReadRequest {
        .init(scope: .init(account: UserData.currentUserId, region: UserData.currentServerRegion,
                           meshUUID: meshUUID, networkID: networkId), root: root, defaults: .standard)
    }
    static func configurationAvailable(for node: Node, group: Group?) -> Bool {
        currentConfigurationAvailable && (NodeSyncReadContext.current?.configurationAvailable(for: node, group: group) ?? true)
    }
    static func testSnapshot(_ network: MeshNetwork) -> SpaceProtectionReadSnapshot {
        syncReadRequest(meshUUID: network.uuid.uuidString, networkId: "net").read()
    }
}
enum NodeSyncData: Equatable {
    case proximityLightingEnabled(Bool), proximityLightingRelayNumber(UInt8), proximityLightingNeighbor(relayNumber: UInt8, neighborAddresses: [Address])
}
struct SiteTriggerZoneTopologyPolicy {
    struct DeviceID: Hashable { let spaceID: String; let nodeUUID: UUID }
    struct Plan { let targets: [DeviceID: ProximityLightingTopologyPolicy.Target] }
}
enum SiteTriggerZoneTopologyReader {
    static var reads = 0
    static var value = LocalTargetSnapshot.localOnly
    // LOCAL_TARGET_SNAPSHOT
    static func localTargetSnapshot(for node: Node) -> LocalTargetSnapshot { reads += 1; return value }
    static func mergedLocalTarget(for node: Node, local: ProximityLightingTopologyPolicy.Target) -> ProximityLightingTopologyPolicy.Target? {
        localTargetSnapshot(for: node).target(for: node, local: local)
    }
}

// Only persistence and non-topology device fields are replaced. The capture,
// scheduling, string subscription cost and pure planner run in this fixture.
enum NodeSyncTopologyStorage {
    struct NodeEvidence {}
    struct KeyEvidence {}
    static func nodeEvidence(_ node: Node) -> NodeEvidence { .init() }
    static func keyEvidence(network: MeshNetwork, networkID: String) -> KeyEvidence { .init() }
    struct Request {
        let zones: [SpaceTriggerZone]
        let site: SiteTriggerZoneTopologyReader.LocalTargetSnapshot
        let valid: Bool
        init(protection: SpaceProtectionReadRequest) {
            zones = SpaceData.current?.triggerZones ?? []
            site = SiteTriggerZoneTopologyReader.value
            valid = SpaceData.current?.triggerZonesLoadFailed == false
        }
        func read(_ input: NodeSyncTopologySnapshot, isCancelled: () -> Bool = { false }) -> NodeSyncPreparedTopology {
            precondition(!Thread.isMainThread, "topology must compute on worker")
            guard !isCancelled() else { return .unavailable }
            SiteTriggerZoneTopologyReader.reads += 1
            let groups = input.groupSnapshots()
            let zones = ProximityLightingTopologyPlanner.makeSpaceZoneSnapshots(zones)
            let interval = AppPerformance.begin("SyncTopologyPlan")
            let plan = ProximityLightingTopologyPolicy.makePlan(groups: groups, spaceZones: zones)
            interval.end()
            let available: Bool
            if case .unavailable = site { available = false } else { available = valid && input.isAvailable }
            return .init(groups: groups, spaceZones: zones, plan: plan, site: site, isAvailable: available)
        }
    }
}

final class Scene {
    struct Info { var groups: [Group] = [] }
    var info = Info(), unsynced = Set<Address>()
    var comparisons: [Address: (cached: SceneExecuteData, target: SceneExecuteData)] = [:]
}
extension Group: Hashable { func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) } }
enum PageNodeSyncType { case scenes(scene: Scene) }
enum NodeAbsoluteCctRange { static let defaultRange: ClosedRange<UInt16> = 2700...6500 }
extension Node {
    func getSyncData(type: PageNodeSyncType) -> [Int] {
        sceneChecks += 1
        Self.onSceneCheck?(self)
        switch type {
        case .scenes(let scene):
            if let comparison = scene.comparisons[primaryUnicastAddress] {
                return comparison.cached.isSynced(with: comparison.target, for: self) ? [] : [1]
            }
            return scene.unsynced.contains(primaryUnicastAddress) ? [1] : []
        }
    }
}
final class Schedule {
    enum TargetType: CaseIterable { case devices, groups, scene, profile }
    var nodeAddresses: [Address] = [], groups: [Group] = [], scene: Scene?
    var selectTargetType = TargetType.groups
    var needDeleteNodes: [Node] = [], needDeleteGroups: [Group] = [], needDeleteScenes: [Scene] = []
    var nodes: [Node] { MeshNetworkManager.instance.realNodes.filter { nodeAddresses.contains($0.primaryUnicastAddress) } }
    var syncRead: (Node, Group?) -> Bool = { _, _ in false }
    var deleteRead: (Node, Group?) -> Bool = { _, _ in false }
    func needsSync(on node: Node, contextGroup: Group? = nil) -> Bool { syncRead(node, contextGroup) }
    func needsDelete(from node: Node, contextGroup: Group? = nil) -> Bool { deleteRead(node, contextGroup) }
}
enum TestMetrics { static var planBuilds = 0 }

#if os(macOS)
@main
#endif
@MainActor
struct NodeSyncStatusRefreshTests {
    static var summary = ""
    static func resourceUsage() -> (cpu: Double, peakMB: Double) {
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
            + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        return (cpu, Double(usage.ru_maxrss) / 1_048_576)
    }
    static func require(_ value: @autoclosure () -> Bool, _ reason: String) {
        if !value() {
            #if DEBUG
            FileHandle.standardError.write(Data(("FAIL: " + reason + "\n").utf8))
            #endif
            fatalError(reason)
        }
    }
    static func fixture(_ count: Int) -> MeshNetwork {
        let network = MeshNetwork(); let group = Group(0xC001); group.network = network
        network.groups = [group]
        network.nodes = (0..<count).map { value in
            let node = Node(Address(value + 1)); node.network = network
            node.sunricherVendorModel?.subscribe = [group.address.address]; return node
        }
        let path = GroupProximityLightingPathData()
        path.paths = [.init(items: network.nodes.map { .init(address: $0.primaryUnicastAddress) })]
        group.info.proximityLightingPath = path
        MeshNetworkManager.instance.meshNetwork = network
        MeshNetworkManager.instance.currentNetworkKey.networkId = "net"
        SpaceData.current = SpaceData(network)
        ConfigurationSnapshotRevision.value = 0
        SiteTriggerZoneTopologyReader.value = .localOnly
        let plan = ProximityLightingTopologyPlanner.makePlan(space: SpaceData.current!)
        for node in network.nodes {
            let target = plan.target(for: node.primaryUnicastAddress)
            node.proximityLightingEnabled = target.enabled
            node.proximityLightingRelayCount = target.relayNumber
            node.proximityLightingNeighborAddresses = target.neighborAddresses
        }
        Model.subscriptionReads = 0; TestMetrics.planBuilds = 0; SiteTriggerZoneTopologyReader.reads = 0
        return network
    }
    static func drain(until finished: () -> Bool) async {
        let deadline = Date().addingTimeInterval(10)
        while !finished() && Date() < deadline { try? await Task.sleep(nanoseconds: 1_000_000) }
        require(finished(), "batch did not complete")
    }
    #if SUNSMART_PERFORMANCE
    static func topologyPreparationRaces() async {
        // Pause after pure calculation, while the main queue can still replace
        // requests, invalidate live inputs or cancel the last owner.
        for cancelLast in [false, true] {
            let network = fixture(8), owner = NSObject()
            let resume = DispatchSemaphore(value: 0), lock = NSLock()
            var paused = false, reached = false, done = false
            AppPerformance.observe { sample in
                guard sample.name == "SyncTopologyPlan" else { return }
                let first = lock.withLock { () -> Bool in
                    if paused { return false }; paused = true; return true
                }
                guard first else { return }
                require(!sample.main, "topology preparation ran on main")
                DispatchQueue.main.async { reached = true }
                require(resume.wait(timeout: .now() + 5) == .success, "topology worker was not released")
            }
            NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owner) { _ in
                preconditionFailure("obsolete topology callback ran")
            }
            await drain { reached }
            if cancelLast { NodeSyncStatusRefresh.cancel(owner: owner) }
            network.nodes[0].proximityLightingEnabled = false
            NodeSyncStatusGeneration.invalidate()
            NodeSyncStatusRefresh.request(nodes: [network.nodes[0]], owner: owner) { result in
                require(result, "topology completion published stale status"); done = true
            }
            resume.signal()
            await drain { done }
            AppPerformance.observe(nil)
            require(network.nodes[0].checks == 1 && network.nodes.dropFirst().allSatisfy { $0.checks == 0 },
                    "cancelled or replaced work survived topology preparation")
        }

        // Invalidate after the first capture slice; the new batch must start its
        // Model cursor from zero and use the updated profile.
        let network = stressFixture(), owner = NSObject()
        var changed = false, done = false
        AppPerformance.observe { sample in
            guard sample.name == "SyncTopologyCapture" && sample.main && !changed else { return }
            changed = true
            network.groups[0].info.profile.proximityLightingNumber = 4
            NodeSyncStatusGeneration.invalidate()
        }
        NodeSyncStatusRefresh.request(nodes: [network.nodes[0]], owner: owner) { result in
            require(result, "capture retained a previous profile"); done = true
        }
        await drain { done }
        AppPerformance.observe(nil)
        require(changed && network.nodes[0].checks == 1, "capture invalidation did not restart before calculation")
    }

    static func protectionPreparationRaces() async {
        // Pause the real worker during I/O, after a completed read, and after
        // observing an active writer. In each case cleanup finishes before the
        // main-queue preparation receives the old snapshot.
        for (event, writingAtStart) in [("ProtectionRead", false), ("ProtectionFileRead", false), ("ProtectionRead", true)] {
            let network = fixture(2)
            let owners = (0..<4).map { _ in NSObject() }
            let read = SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: "net")
            let folder = read.root.appendingPathComponent(read.scope.storageKey)
            let marker = folder.appendingPathComponent("pending-import.json")
            SpaceProtectionReadGeneration.beginMutation()
            try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try! Data("pending".utf8).write(to: marker)
            if !writingAtStart { SpaceProtectionReadGeneration.endMutation() }

            let resume = DispatchSemaphore(value: 0), lock = NSLock()
            var paused = false, readCount = 0, reachedPause = false, completions = 0
            AppPerformance.observe { sample in
                lock.lock()
                if sample.name == "ProtectionRead" { readCount += 1 }
                let shouldPause = sample.name == event && !paused
                if shouldPause { paused = true }
                lock.unlock()
                guard shouldPause else { return }
                require(!sample.main, "protection read must run on worker")
                DispatchQueue.main.async { reachedPause = true }
                require(resume.wait(timeout: .now() + 5) == .success, "cleanup did not release protection worker")
            }
            NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { _ in
                preconditionFailure("replaced preparation callback ran")
            }
            NodeSyncStatusRefresh.request(group: network.groups[0], owner: owners[1]) { result in
                require(Thread.isMainThread && !result, "pending request used stale protection"); completions += 1
            }
            NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[2]) { _ in
                preconditionFailure("cancelled preparation callback ran")
            }
            await drain { reachedPause }
            if !writingAtStart { SpaceProtectionReadGeneration.beginMutation() }
            try! FileManager.default.removeItem(at: read.root)
            SpaceProtectionReadGeneration.endMutation()
            NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { result in
                require(Thread.isMainThread && !result, "replacement request used stale protection"); completions += 1
            }
            NodeSyncStatusRefresh.request(group: network.groups[0], owner: owners[3]) { result in
                require(Thread.isMainThread && !result, "new request used stale protection"); completions += 1
            }
            NodeSyncStatusRefresh.cancel(owner: owners[2])
            resume.signal()
            await drain { completions == 3 }
            AppPerformance.observe(nil)
            require(lock.withLock { readCount == 2 }, "completed cleanup must trigger exactly one fresh read")
            require(network.nodes.allSatisfy { $0.checks == 1 && $0.cacheNeedSync == false && $0.cacheGroupNeedSync == false },
                    "fresh protection did not compute and publish synchronized nodes")
        }

        // A writer that remains active must complete conservatively without
        // spinning. A normal refresh after it ends must still work.
        let network = fixture(2), owner = NSObject(), lock = NSLock()
        var readCount = 0, unavailableDone = false, refreshed = false
        AppPerformance.observe { sample in
            if sample.name == "ProtectionRead" { lock.withLock { readCount += 1 } }
        }
        SpaceProtectionReadGeneration.beginMutation()
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owner) { result in
            require(result, "active writer must remain protected"); unavailableDone = true
        }
        await drain { unavailableDone }
        require(lock.withLock { readCount == 1 }, "active writer caused repeated protection reads")
        require(network.nodes.allSatisfy { $0.checks == 0 }, "active writer allowed node computation")
        SpaceProtectionReadGeneration.endMutation()
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owner) { result in
            require(!result, "refresh after writer completion stayed unavailable"); refreshed = true
        }
        await drain { refreshed }
        AppPerformance.observe(nil)
        require(lock.withLock { readCount == 2 }, "refresh after writer completion did not read fresh protection")
    }
    #endif
    static func prepare(_ context: NodeSyncReadContext, node: Node? = nil, group: Group? = nil) async {
        while !context.isPrepared {
            if context.prepareSlice(until: ProcessInfo.processInfo.systemUptime + 0.004, onReady: {}) {
                try? await Task.sleep(nanoseconds: 1_000_000)
            } else { await drain { context.isPrepared } }
        }
        if let node {
            while !context.prepareNode(node, additionalGroup: group, onReady: {}) {
                try? await Task.sleep(nanoseconds: 1_000_000)
            }
        }
    }
    static func stressFixture() -> MeshNetwork {
        let network = fixture(500)
        network.groups = (0..<50).map { index in
            let group = Group(Address(0xC001 + index)); group.network = network
            let path = GroupProximityLightingPathData()
            path.paths = [.init(items: network.nodes[(index * 10)..<(index * 10 + 10)].map {
                .init(address: $0.primaryUnicastAddress)
            })]
            group.info.proximityLightingPath = path
            return group
        }
        for (index, node) in network.nodes.enumerated() {
            let element = node.elements[0]
            element.models = (0..<20).map { _ in
                let model = Model(); model.parentElement = element
                model.subscribe = [network.groups[index / 10].address.address]
                return model
            }
        }
        let plan = ProximityLightingTopologyPlanner.makePlan(space: SpaceData.current!)
        for node in network.nodes {
            let target = plan.target(for: node.primaryUnicastAddress)
            node.proximityLightingEnabled = target.enabled
            node.proximityLightingRelayCount = target.relayNumber
            node.proximityLightingNeighborAddresses = target.neighborAddresses
        }
        return network
    }
    static func main() async { await run(); print(summary) }
    static func run() async {
        require(Thread.isMainThread, "test refresh on main queue")
        await spaceRuntimeCacheTests()
        await sceneGroupSyncReadTests()
        await groupDeviceSyncReadTests()
        #if os(macOS)
        await groupsLiveAppearanceTests()
        await groupDeviceSyncDisplayTests()
        scenePresentationLayoutTests()
        #endif
        var network = fixture(500)
        let owners = (0..<14).map { _ in NSObject() }
        var finished = 0
        let started = ProcessInfo.processInfo.systemUptime
        for owner in owners.prefix(7) {
            NodeSyncStatusRefresh.request(group: network.groups[0], owner: owner) { result in
                require(!result, "synchronized group changed"); finished += 1
            }
        }
        for owner in owners.dropFirst(7).prefix(6) {
            NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owner) { result in
                require(!result, "synchronized devices changed"); finished += 1
            }
        }
        NodeSyncStatusRefresh.warmUp(nodes: network.nodes, owner: owners.last!)
        await drain { finished == 13 && network.nodes.allSatisfy { $0.checks > 0 } }
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        require(network.nodes.allSatisfy { $0.checks == 1 }, "overlapping readers recomputed a node")
        require(TestMetrics.planBuilds == 1, "batch must compute one base topology plan")
        require(SiteTriggerZoneTopologyReader.reads == 1, "Site target snapshot must be shared")
        require(Model.subscriptionReads <= 500, "inner topology loop still constructs subscription arrays")
        let subscriptionReads = Model.subscriptionReads
        let memo = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes,
                                       protection: SpaceConfigurationSafety.testSnapshot(network))
        var implicitChecks = 0, explicitChecks = 0
        for _ in 0..<2 {
            require(!memo.groupNeedsSync(for: network.nodes[0], group: nil) { implicitChecks += 1; return false }, "nil group changed")
            require(memo.groupNeedsSync(for: network.nodes[0], group: network.groups[0]) { explicitChecks += 1; return true }, "explicit group reused nil result")
        }
        require(implicitChecks == 1 && explicitChecks == 1, "semantic cache keys did not memoize independently")
        let damagedRead = SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: "net")
        try! FileManager.default.createDirectory(at: damagedRead.root, withIntermediateDirectories: true)
        let damagedFile = damagedRead.root.appendingPathComponent(damagedRead.scope.storageKey + ".json")
        SpaceProtectionReadGeneration.beginMutation()
        try! Data("broken".utf8).write(to: damagedFile)
        SpaceProtectionReadGeneration.endMutation()
        var damagedDone = false
        NodeSyncStatusRefresh.request(nodes: [], owner: owners[0]) { result in
            require(result, "unreadable protection returned synchronized for empty selection"); damagedDone = true
        }
        await drain { damagedDone }
        SpaceProtectionReadGeneration.beginMutation()
        try! FileManager.default.removeItem(at: damagedRead.root)
        SpaceProtectionReadGeneration.endMutation()

        // A protection mutation during node computation must discard the old
        // synchronized result. The next snapshot observes the real pending file.
        network = fixture(24); Node.perNodeDelay = 0.001
        let read = SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: "net")
        let folder = read.root.appendingPathComponent(read.scope.storageKey)
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let marker = folder.appendingPathComponent("pending-import.json")
        var protectionChanged = false, protectionDone = false
        Node.onCheck = { node in
            if !protectionChanged && node.primaryUnicastAddress == 8 {
                protectionChanged = true
                SpaceProtectionReadGeneration.beginMutation()
                defer { SpaceProtectionReadGeneration.endMutation() }
                try! Data("pending".utf8).write(to: marker, options: .atomic)
            }
        }
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { result in
            require(result, "old allowed protection snapshot published"); protectionDone = true
        }
        await drain { protectionDone }
        Node.onCheck = nil; Node.perNodeDelay = 0
        SpaceProtectionReadGeneration.beginMutation()
        try! FileManager.default.removeItem(at: read.root)
        SpaceProtectionReadGeneration.endMutation()

        #if SUNSMART_PERFORMANCE
        await protectionPreparationRaces()
        await topologyPreparationRaces()
        // A single selected node must never build the whole topology in its
        // synchronous check, even when all 10,000 Models use SDK lookups.
        network = stressFixture(); TestMetrics.planBuilds = 0
        var firstDone = false, firstSteps: [Double] = [], mainPlans = 0
        var probeQueued = false, probeDelay: Double?
        AppPerformance.observe { sample in
            if sample.main && (sample.name == "SyncMainStep" || sample.name == "SyncMainPrepare") { firstSteps.append(sample.seconds) }
            if sample.main && sample.name == "SyncTopologyPlan" { mainPlans += 1 }
            if sample.main && sample.name == "SyncSubscriptionCapture" && !probeQueued {
                probeQueued = true
                let queued = ProcessInfo.processInfo.systemUptime
                DispatchQueue.main.async { probeDelay = ProcessInfo.processInfo.systemUptime - queued }
            }
        }
        NodeSyncStatusRefresh.request(nodes: [network.nodes[0]], owner: owners[0]) { result in
            require(!result, "first node changed status"); firstDone = true
        }
        await drain { firstDone }
        AppPerformance.observe(nil)
        require(network.nodes.map(\.checks).reduce(0, +) == 1 && TestMetrics.planBuilds == 1, "first node did not share one background plan")
        require(mainPlans == 0 && firstSteps.max()! <= 0.0167, "first node blocked main queue")
        require(probeDelay != nil && probeDelay! <= 0.0167, "capture starved the queued main-thread probe")
        var steps: [Double] = [], mainFileReads = 0, batchReads = 0
        var wallSamples: [Double] = [], cpuTotal = 0.0
        let metricsLock = NSLock()
        AppPerformance.observe { sample in
            metricsLock.lock(); defer { metricsLock.unlock() }
            if sample.name == "SyncMainStep" || sample.name == "SyncMainPrepare" { steps.append(sample.seconds) }
            if sample.name == "ProtectionFileRead" { batchReads += sample.value; if sample.main { mainFileReads += sample.value } }
        }
        for batchIndex in 0..<15 {
            network = stressFixture()
            TestMetrics.planBuilds = 0
            let readerCount = batchIndex.isMultiple(of: 2) ? 14 : 1
            var done = 0
            let wallStart = ProcessInfo.processInfo.systemUptime, cpuStart = resourceUsage().cpu
            for owner in owners.prefix(readerCount) {
                NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owner) { result in
                    require(!result, "stress status changed"); done += 1
                }
            }
            await drain { done == readerCount }
            require(TestMetrics.planBuilds == 1 && network.nodes.allSatisfy { $0.checks == 1 },
                    "stress readers duplicated topology or node work")
            wallSamples.append(ProcessInfo.processInfo.systemUptime - wallStart)
            cpuTotal += resourceUsage().cpu - cpuStart
        }
        AppPerformance.observe(nil)
        require(mainFileReads == 0 && batchReads == 30, "refresh must read protection once per batch on worker")
        let sortedSteps = steps.sorted()
        require(sortedSteps[Int(Double(sortedSteps.count - 1) * 0.95)] <= 0.008, "main-queue P95 exceeded 8 ms")
        require(sortedSteps.last! < 0.0167, "full main-queue step exceeded 16.7 ms with string subscriptions")
        let timings = String(format: "; first-node max %.3f ms/probe %.3f ms; 15 batches (500 nodes/50 groups/20 models, 1 or 14 readers) main step p95 %.3f ms max %.3f ms, wall median %.3f s/CPU total %.3f s/process peak %.1f MiB, protection reads %d/main %d",
            firstSteps.max()! * 1000, probeDelay! * 1000,
            sortedSteps[Int(Double(sortedSteps.count - 1) * 0.95)] * 1000, sortedSteps.last! * 1000,
            wallSamples.sorted()[wallSamples.count / 2], cpuTotal, resourceUsage().peakMB, batchReads, mainFileReads)
        #else
        let timings = ""
        #endif

        // Ordinary groups, excluded/exit-failure members and pending membership
        // must agree with the original per-node planner, including Space zones.
        network = fixture(12)
        let second = Group(0xC002); second.network = network; second.info.profile.type = .ordinary
        network.groups.append(second)
        network.nodes[0].groupState = .exitFailure
        network.nodes[1].sunricherVendorModel?.subscribe = [second.address.address]
        network.nodes[2].sunricherVendorModel?.subscribe = []
        SpaceData.current!.triggerZones = [.init(items: [.init(groupAddress: 0xC001, deviceAddress: 4), .init(groupAddress: 0xC001, deviceAddress: 7)])]
        let context = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes, protection: SpaceConfigurationSafety.testSnapshot(network))
        for node in network.nodes {
            for group in [nil, network.groups.first, second] as [Group?] {
                let expected = ProximityLightingTopologyPlanner.makePlan(for: node, contextGroup: group)
                await prepare(context, node: node, group: group)
                let actual = context.perform { ProximityLightingTopologyPlanner.makePlan(for: node, contextGroup: group) }
                require(expected.target(for: node.primaryUnicastAddress) == actual.target(for: node.primaryUnicastAddress) && expected.isComplete == actual.isComplete, "per-node override/Space zone changed")
            }
        }
        let schedule = Schedule(); schedule.groups = [network.groups[0]]
        for node in network.nodes {
            let expected = schedule.targets(node: node)
            require(expected == context.perform { schedule.targets(node: node) }, "schedule member semantics changed")
        }
        let first = network.nodes[3]
        SiteTriggerZoneTopologyReader.value = .site(spaceID: "space", plan: .init(targets: [
            .init(spaceID: "space", nodeUUID: first.uuid): .init(enabled: true, relayNumber: 4, neighborAddresses: [7])]))
        let siteContext = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes, protection: SpaceConfigurationSafety.testSnapshot(network))
        await prepare(siteContext)
        let expected = first.getNodeSyncProximityLighting()
        require(expected != nil && expected == siteContext.perform { first.getNodeSyncProximityLighting() }, "Site target merge was skipped")
        require(siteContext.perform { network.nodes[4].getNodeSyncProximityLighting() } == nil, "missing Site target must remain unavailable")
        SiteTriggerZoneTopologyReader.value = .unavailable
        let blocked = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes, protection: SpaceConfigurationSafety.testSnapshot(network))
        await prepare(blocked)
        require(blocked.perform { first.getNodeSyncProximityLighting() } == nil, "unavailable Site target must not become local-only")
        require(NodeSyncReadContext.current == nil, "read context leaked outside synchronous slice")

        network = fixture(2)
        let recovering = network.nodes[0]
        recovering.sunricherVendorModel?.subscribe = []
        recovering.proximityLightingEnabled = false
        recovering.restoreData = .init(addGroup: network.groups[0])
        var recoveryDone = false
        NodeSyncStatusRefresh.request(nodes: [recovering], owner: owners[0]) { result in
            require(result, "pending recovery group was omitted from preparation")
            recoveryDone = true
        }
        await drain { recoveryDone }
        require(recovering.cacheNeedSync == true && recovering.cacheGroupNeedSync == false,
                "recovery override did not reach the device status check")

        network = fixture(0); SpaceData.current!.triggerZonesLoadFailed = true
        var emptyUnavailable = false
        NodeSyncStatusRefresh.request(nodes: [], owner: owners[0]) { result in
            require(result, "unavailable topology reported an empty selection as synchronized")
            emptyUnavailable = true
        }
        await drain { emptyUnavailable }

        // A newer request from the same Cell replaces its previous selection.
        network = fixture(8); var replacementDone = false
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { _ in preconditionFailure("obsolete callback ran") }
        network.nodes[0].proximityLightingEnabled = false
        NodeSyncStatusRefresh.request(nodes: [network.nodes[0]], owner: owners[0]) { result in require(result, "latest selection not evaluated"); replacementDone = true }
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[1]) { _ in preconditionFailure("cancelled callback ran") }
        NodeSyncStatusRefresh.cancel(owner: owners[1])
        await drain { replacementDone }
        require(network.nodes.dropFirst().allSatisfy { $0.checks == 0 }, "cancelled/obsolete work was still computed")

        // Invalidation between slices must discard computed results as well as
        // the plan; previously processed nodes can now require synchronization.
        network = fixture(24); Node.perNodeDelay = 0.001
        var changed = false, invalidationDone = false
        Node.onCheck = { node in
            if !changed && node.primaryUnicastAddress == 8 {
                changed = true; network.nodes[0].proximityLightingEnabled = false
                NodeSyncStatusGeneration.invalidate()
            }
        }
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { result in
            require(result, "stale false result survived invalidation"); invalidationDone = true
        }
        await drain { invalidationDone }
        Node.onCheck = nil; Node.perNodeDelay = 0
        require(network.nodes[0].checks == 2, "invalidated processed node was not recomputed")
        var unavailableDone = false; ConfigurationSnapshotRevision.value = nil
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { result in
            require(result, "unavailable revision must not report synchronized"); unavailableDone = true
        }
        await drain { unavailableDone }
        ConfigurationSnapshotRevision.value = 1
        require(!context.isCurrent, "network/revision switch did not invalidate context")
        network = fixture(2)
        for change in [
            { UserData.currentUserId += "x" },
            { UserData.currentServerRegion += "x" },
            { ConfigurationSnapshotRevision.value = 100 },
            { SpaceConfigurationSafety.currentConfigurationAvailable.toggle() },
            { NotificationCenter.default.post(name: .init("UIApplicationWillEnterForegroundNotification"), object: nil) }
        ] {
            let captured = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes, protection: SpaceConfigurationSafety.testSnapshot(network))
            require(captured.isCurrent, "fresh context unexpectedly invalid")
            change()
            require(!captured.isCurrent, "scope/configuration change did not invalidate context")
        }
        SpaceConfigurationSafety.currentConfigurationAvailable = true
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[0]) { _ in preconditionFailure("previous network callback ran") }
        network = fixture(2); var currentDone = false
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: owners[1]) { _ in currentDone = true }
        await drain { currentDone }
        try? await Task.sleep(nanoseconds: 20_000_000)
        summary = String(format: "PASS: 500 nodes, 14 readers, 1 plan, %d subscription reads, %.3f s; overrides, Site targets, schedules, cancellation, invalidation and protection preparation races", subscriptionReads, elapsed)
            + timings
    }
}
