import Foundation
import SQLite

// Real production coordinator, Zone classifier, JSON state and SQLite store.
// Only Mesh/Space repair and network transport are replaced by controlled inputs.
enum ServerRegion: Int { case first, second }
enum NetworkApiError: Error, Equatable { case noNetwork }
enum UserData { static var currentUserId = "account", currentServerRegion = ServerRegion.first }
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
}
final class SiteData {
    enum State { case normal, deleted }
    static var stored: [String: SiteData] = [:]
    let id: String, meshUUID: String, region: ServerRegion
    var state = State.normal
    var spaces: [SpaceData] = []
    var canManageSiteTriggerZones = true, uploadCloud = true
    var needUploadCloud = false
    var lastUpdate: Int64 = 0
    var siteExtensionData = SiteExtensionData()
    init(_ id: String = "site", region: ServerRegion = .first) {
        self.id = id; meshUUID = id; self.region = region
    }
    static func load(siteId: String) -> SiteData? {
        guard let source = stored[siteId], source.region == UserData.currentServerRegion else { return nil }
        let copy = SiteData(source.id, region: source.region)
        copy.state = source.state; copy.spaces = SpaceData.load(siteId: source.id)
        copy.canManageSiteTriggerZones = source.canManageSiteTriggerZones
        copy.lastUpdate = source.lastUpdate; copy.uploadCloud = source.uploadCloud
        copy.needUploadCloud = source.needUploadCloud
        copy.siteExtensionData = source.siteExtensionData
        return copy
    }
    static func loadAll() -> [SiteData] { stored.values.filter { $0.region == UserData.currentServerRegion } }
    @MainActor
    func export(spaceIds: [String]) async -> [String: Any]? {
        CleanupFixture.exportedMembers = (try? SiteExtensionStore.load(self).data.zones?.first?.displayMembers.count) ?? -1
        CleanupFixture.exportedRevisions = spaces.filter { spaceIds.contains($0.id) }.map(\.revision)
        CleanupFixture.onSiteExport?()
        return ["members": CleanupFixture.exportedMembers]
    }
}
final class SpaceData {
    static var stored: [SpaceData] = []
    let id: String, siteId: String, meshUUID: String
    var canEditing = true, blocked = false, needUploadCloud = true, pendingUpload = false, synchronizing = false
    var revision = 0
    var initialized = true
    var syncCloudError: NetworkApiError?
    init(_ id: String, site: String = "site") { self.id = id; siteId = site; meshUUID = site }
    static func load(siteId: String) -> [SpaceData] {
        stored.filter { $0.siteId == siteId }.map { source in
            let copy = SpaceData(source.id, site: source.siteId)
            copy.canEditing = source.canEditing; copy.blocked = source.blocked
            copy.needUploadCloud = source.needUploadCloud; copy.pendingUpload = source.pendingUpload
            copy.synchronizing = source.synchronizing; copy.revision = source.revision
            copy.initialized = source.initialized
            return copy
        }
    }
    enum Purpose { case cloudSync }
    @MainActor func export(purpose: Purpose) async -> [String: Any]? {
        CleanupFixture.spaceExports += 1
        guard !pendingUpload else { return nil }
        return ["id": id]
    }
}
struct MeshAddress { let address: UInt16 }
final class Group {
    struct Profile { var type = 1 }
    struct Info { var profile = Profile() }
    let address = MeshAddress(address: 0xC001)
    var isVirtual = false, info = Info()
}
final class Node {
    enum State { case normal, exitFailure }
    let uuid = UUID(), primaryUnicastAddress: UInt16 = 16
    var groupState = State.normal, group: Group?
    var elements = [0, 1]
    var cacheInvalidations = 0
    func clearSyncStateCache() { cacheInvalidations += 1 }
}
final class MeshNetwork {
    var uuid = UUID()
    var nodes: [Node] = [], groups: [Group] = []
    var valid = true, destructive = false
}
enum NodeSyncStatusGeneration {
    static var invalidations = 0
    static func invalidate() { invalidations += 1 }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
}
enum ProximityLightingTopologyContext {
    static var networks: [String: MeshNetwork] = [:], loads: [String: Int] = [:]
    static func network(for space: SpaceData) -> MeshNetwork? {
        loads[space.id, default: 0] += 1
        return networks[space.id]
    }
    static func loadGroupInfo(network: MeshNetwork, space: SpaceData) {}
    static func realNodes(in network: MeshNetwork) -> [Node] { network.nodes }
}
enum ProximityLightingTopologyPlanner {
    struct Target { var enabled = true }
    struct Plan { func target(for address: UInt16) -> Target { .init() } }
    static func normalizedAddress(for node: Node) -> UInt16 { node.primaryUnicastAddress }
}
enum ProximityLightingLifecycleCoordinator {
    struct Preparation {
        struct Normalized { let hasDestructiveRepairs: Bool }
        let network: MeshNetwork
        var isValid: Bool { network.valid }
        var normalized: Normalized { .init(hasDestructiveRepairs: network.destructive) }
    }
    struct Session { let network: MeshNetwork; func prepare() -> Preparation { .init(network: network) } }
    struct Preview { let plan = ProximityLightingTopologyPlanner.Plan() }
    static func begin(space: SpaceData, groups: [Group], nodes: [Node], network: MeshNetwork) -> Session { .init(network: network) }
    static func preview(_ preparation: Preparation) -> Preview? { .init() }
    static func isEligible(_ type: Int) -> Bool { type == 1 }
}
enum SpaceConfigurationSafety {
    struct Recovery { var unbindRequested = false }
    static func recoveryState(_ space: SpaceData) throws -> Recovery { .init() }
    static func resumeLocalRemovals() {}
    static func resumeUnbind(_ space: SpaceData) async -> Bool { true }
    static func canAutomaticallyUpload(_ space: SpaceData) -> Bool { !space.blocked && space.initialized }
    static func canResumePendingUpload(_ space: SpaceData) -> Bool { !space.blocked && space.pendingUpload }
    static func hasPendingUpload(_ space: SpaceData) -> Bool { space.pendingUpload }
    static func isBlocked(_ space: SpaceData) -> Bool { space.blocked }
    @MainActor static func resumeUpload(_ space: SpaceData) async -> Swift.Result<Void, NetworkApiError> {
        CleanupFixture.events.append("readback")
        if space.blocked { return .failure(.noNetwork) }
        if space.pendingUpload {
            space.pendingUpload = false; space.needUploadCloud = false; space.initialized = true
        }
        return .success(())
    }
}
final class NetworkRequest { static let shared = NetworkRequest(); var networkable = true }
enum SiteDeviceOwnershipReconciler { static func reconcile(siteId: String) {} }
enum SpaceMembershipCoordinator {
    static func resumeLeaves() async {}
    static func isLeaving(_ space: SpaceData) -> Bool { false }
}
final class CloudSynchronizationManager {
    let recoveryGate = PendingSynchronizationRecoveryGate()
    enum Level { case promptly }
    var uploads = 0
    var uploadedIDs: [String] = []
    func getSpaceCurrentSyncState(_ space: SpaceData) -> Int? {
        SpaceData.stored.first { $0.id == space.id }?.synchronizing == true ? 1 : nil
    }
    func addSynchronizationHandle(operation: SyncOperation, level: Level) {
        uploads += 1
        if case .syncSite(_, let spaces) = operation { uploadedIDs += spaces.map(\.id) }
    }
}
enum NetowrkReqeustApi {
    case siteUpload(siteData: [String: Any])
    case siteAdd(siteData: [String: Any], useDeivceAddressNum: Int)
    case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any])
}
enum MeshAPI { static func getTheUsedDeviceAddresses(meshUUID: String) -> [UInt16] { [] } }

@MainActor final class SyncPreparationFixture {
    enum State { case waiting, successful }
    let configurationSpaces: [SpaceData]
    let operation: SyncOperation
    var state = State.waiting
    var failed = false, requestReady = false
    var handleCallback: ((SyncPreparationFixture, State) -> Void)?
    init(space: SpaceData) { configurationSpaces = [space]; operation = .syncSpace(space: space) }
    init(operation: SyncOperation, spaces: [SpaceData]) {
        self.operation = operation; configurationSpaces = spaces
    }
    func finishConfigurationFailure(_ error: NetworkApiError) { failed = true }
    func finishInvalidatedConfiguration() { failed = true }
    func finishExportFailure() { failed = true }
}

@MainActor
enum CleanupFixture {
    static var events: [String] = []
    static var prepared: [String] = []
    static var failures = Set<String>()
    static var suspended: CheckedContinuation<Void, Never>?
    static var pauseSpace: String?
    static var onPrepare: ((SpaceData) -> Void)?
    static var onSiteExport: (() -> Void)?
    static var exportedMembers = -1, exportedRevisions: [Int] = []
    static var spaceExports = 0
    static var synchronizations = 0, membersAtSynchronization = -1
    static func perform(_ space: SpaceData) async -> Bool {
        events.append("cleanup")
        prepared.append(space.id)
        if pauseSpace == space.id {
            pauseSpace = nil
            await withCheckedContinuation { suspended = $0 }
        }
        onPrepare?(space)
        SpaceData.stored.first { $0.id == space.id }?.revision += 1
        space.syncCloudError = failures.contains(space.id) ? .noNetwork : nil
        return !failures.contains(space.id)
    }
}

@main
@MainActor
enum SiteZoneCleanupBatchTests {
    static func require(_ condition: Bool, _ message: String) {
        precondition(condition, message)
    }
    static func wait(_ condition: () -> Bool) async {
        for _ in 0..<500 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 1_000_000)
        }
        require(condition(), "Timed out waiting for test continuation")
    }
    static func settle() async { try? await Task.sleep(nanoseconds: 20_000_000) }
    static func reset(count: Int = 4, references: Int = 3) throws -> SiteData {
        NodeSyncStatusGeneration.invalidations = 0
        MeshNetworkManager.instance.meshNetwork = nil
        UserData.currentUserId = "account"; UserData.currentServerRegion = .first
        SunSmartDataManager.shared.db = try Connection(.inMemory)
        try SiteExtensionStore.createTable()
        let site = SiteData()
        SiteData.stored = [site.id: site]
        SpaceData.stored = (0..<count).map { SpaceData("space-\($0)") }
        site.spaces = SpaceData.load(siteId: site.id)
        ProximityLightingTopologyContext.networks = [:]; ProximityLightingTopologyContext.loads = [:]
        var members: [SiteJSONValue] = []
        for space in site.spaces.prefix(references) {
            let network = MeshNetwork(), group = Group(), node = Node()
            node.group = group; network.nodes = [node]; network.groups = [group]
            ProximityLightingTopologyContext.networks[space.id] = network
            // Two references share the same Space. Only the missing node is obsolete.
            for uuid in [node.uuid, UUID()] {
                members.append(.object(SiteTriggerZoneMember(identity: .init(spaceID: space.id, nodeUUID: uuid),
                    groupAddress: 0xC001, primaryAddress: 16, deviceAddress: 16).fields))
            }
        }
        var zone = SiteTriggerZone(); zone.fields["members"] = .array(members)
        try SiteExtensionStore.update(site) { $0.data.replaceZones([zone]) }
        CleanupFixture.prepared = []; CleanupFixture.failures = []; CleanupFixture.onPrepare = nil
        CleanupFixture.onSiteExport = nil
        CleanupFixture.suspended = nil; CleanupFixture.pauseSpace = nil
        CleanupFixture.exportedMembers = -1; CleanupFixture.exportedRevisions = []
        CleanupFixture.synchronizations = 0; CleanupFixture.membersAtSynchronization = -1
        CleanupFixture.events = []
        NetworkRequest.shared.networkable = true
        return site
    }
    static func request(_ site: SiteData, account: String = "account") -> UUID? {
        try! SiteExtensionStore.load(site).referenceCleanupRequests?[account]
    }
    static func main() async throws {
        try testStoreCacheInvalidation()
        try await testCountsAndExports()
        try await testPreparationFailureGatesUpload()
        try await testPersistenceAndFailures()
        try await testOverlap()
        try await testCancellationAndScope()
        try await testRecovery()
        try await testPendingReadbackBeforeCleanup()
        try await testSitePendingAfterReadback()
        print("PASS: production batch/three entries, SQLite restart, read counts, conservative cleanup, failure/cancellation, scope and overlapping ownership")
    }

    static func testStoreCacheInvalidation() throws {
        _ = try reset(count: 0, references: 0)
        let network = MeshNetwork(), node = Node()
        network.nodes = [node]
        MeshNetworkManager.instance.meshNetwork = network
        let site = SiteData(network.uuid.uuidString)
        try SiteExtensionStore.update(site) { $0.data.replaceZones([]) }
        require(NodeSyncStatusGeneration.invalidations == 0 && node.cacheInvalidations == 0,
                "ordinary Zone writes do not invalidate HDB type caches")
        try SiteExtensionStore.update(site) { $0.data.isHdbSite = true }
        require(NodeSyncStatusGeneration.invalidations == 1 && node.cacheInvalidations == 1,
                "a persisted HDB type change invalidates the matching active network")
        let db = SunSmartDataManager.shared.db!
        try db.run("CREATE TRIGGER fail_type BEFORE INSERT ON site_extensions BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        do {
            try SiteExtensionStore.update(site) { $0.data.isHdbSite = false }
            preconditionFailure("failed persistence was accepted")
        } catch {}
        let persisted = try SiteExtensionStore.load(site)
        require(persisted.data.isHdbSite && site.siteExtensionData.isHdbSite
                && NodeSyncStatusGeneration.invalidations == 1 && node.cacheInvalidations == 1,
                "rollback preserves stored and in-memory type without premature cache invalidation")
        try db.run("DROP TRIGGER fail_type")
        let otherSite = SiteData(UUID().uuidString)
        try SiteExtensionStore.update(otherSite) { $0.data.isHdbSite = true }
        require(NodeSyncStatusGeneration.invalidations == 2 && node.cacheInvalidations == 1,
                "another Site change must not clear the active network's node cache")
        print("PASS: real Site Store type changes, cache scope and SQLite rollback")
    }

    static func testSitePendingAfterReadback() async throws {
        for add in [false, true] {
            for variant in ["clean", "zone-cleanup", "pending-empty-zone", "site-edit", "zone-read-failed", "site-missing"] {
                let site = try reset(count: 1, references: variant == "zone-cleanup" ? 1 : 0)
                let space = site.spaces[0]
                space.pendingUpload = true; space.initialized = false
                if variant == "pending-empty-zone" {
                    try SiteExtensionStore.update(site) { state in
                        var data = state.data
                        data.replaceZones([])
                        state.commit(data, now: 1, siteTimestamp: site.lastUpdate)
                    }
                }
                if variant == "site-edit" {
                    // The queued Site instance is stale; completion must reload it.
                    let current = SiteData.load(siteId: site.id)!
                    current.needUploadCloud = true
                    SiteData.stored[site.id] = current
                }
                if variant == "zone-read-failed" {
                    CleanupFixture.onSiteExport = { SunSmartDataManager.shared.db = nil }
                }
                if variant == "site-missing" {
                    CleanupFixture.onSiteExport = { SiteData.stored[site.id] = nil }
                }
                let operation: SyncOperation = add ? .addSpaces(site: site, spaces: [space])
                    : .syncSite(site: site, syncSpaces: [space])
                let sync = SyncPreparationFixture(operation: operation, spaces: [space])
                await sync.run()
                require(!space.pendingUpload && !space.needUploadCloud,
                        "Readback confirms the old Space generation without new Space edits")
                require(CleanupFixture.events == ["readback", "cleanup"],
                        "Site upload prepares cleanup after receipt confirmation")
                switch variant {
                case "clean":
                    require(sync.state == .successful && !sync.requestReady && !sync.failed,
                            "Clean Site and Zone finish without a redundant POST")
                case "zone-read-failed", "site-missing":
                    require(sync.failed && !sync.requestReady && sync.state != .successful,
                            "Unavailable durable state cannot report successful completion")
                default:
                    require(sync.requestReady && sync.state != .successful && !sync.failed,
                            "\(add ? "addSpaces" : "syncSite") \(variant) must keep its prepared upload")
                }
                if variant == "zone-cleanup" || variant == "pending-empty-zone" {
                    let state = try SiteExtensionStore.load(site)
                    require(state.pending != nil && state.pending?.target == state.data
                        && SiteData.load(siteId: site.id)?.needUploadCloud == false,
                            "Zone-only changes remain durable independently of the Site timestamp")
                    if variant == "zone-cleanup" {
                        require(CleanupFixture.exportedMembers == 1,
                                "Prepared Site payload retains the valid member and removes the obsolete member")
                    }
                }
            }
        }
        print("PASS: syncSite/addSpaces readback completion respects cleaned or existing Zone pending, Site edits, no-op and storage failures")
    }

    static func testPendingReadbackBeforeCleanup() async throws {
        for variant in ["clean", "new-edit", "readback-failed", "cleanup-failed", "cancel", "new-pending"] {
            let site = try reset(count: 1, references: 0)
            let space = site.spaces[0]
            space.pendingUpload = true; space.initialized = false; space.syncCloudError = .noNetwork
            require(!(await SpaceSyncCleanupCoordinator.prepare(space)), "Entry defers pending cleanup")
            require(CleanupFixture.prepared.isEmpty && space.syncCloudError == .noNetwork && request(site) == nil,
                    "Deferred cleanup preserves diagnosis and does not mutate Site requests")
            if variant == "readback-failed" { space.blocked = true }
            if variant == "cleanup-failed" { CleanupFixture.failures = [space.id] }
            CleanupFixture.onPrepare = { current in
                if variant == "new-edit" { current.needUploadCloud = true }
            }
            let sync = SyncPreparationFixture(space: space)
            if variant == "cancel" || variant == "new-pending" {
                CleanupFixture.pauseSpace = space.id
                let task = Task { @MainActor in await sync.run() }
                await wait { CleanupFixture.suspended != nil }
                if variant == "cancel" { task.cancel() }
                else { space.pendingUpload = true }
                let continuation = CleanupFixture.suspended!; CleanupFixture.suspended = nil; continuation.resume()
                await task.value
            } else { await sync.run() }
            if variant == "clean" {
                require(sync.state == .successful && !sync.requestReady && !sync.failed,
                        "Confirmed clean generation finishes without a redundant POST")
                require(CleanupFixture.events == ["readback", "cleanup"], "Confirmation must precede deferred cleanup")
            } else if variant == "new-edit" {
                require(sync.requestReady && sync.state == .waiting, "Cleanup edits require a fresh upload")
            } else {
                require(!sync.requestReady && sync.state != .successful, "Failure/cancellation cannot report success")
            }
            if variant == "readback-failed" { require(CleanupFixture.prepared.isEmpty, "Failed readback never cleans") }
        }
        print("PASS: deferred entry cleanup, production readback-before-cleanup, no-op completion, cleanup edits and failures/cancellation")
    }
    static func testCountsAndExports() async throws {
        for count in [1, 100] {
            let references = min(count, 80)
            let site = try reset(count: count, references: references)
            let current = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: site.spaces)
            require(current != nil && CleanupFixture.prepared.count == count, "Batch prepares each Space")
            require(NodeSyncStatusGeneration.invalidations == 0, "ordinary batch cleanup does not change the HDB type generation")
            require(ProximityLightingTopologyContext.loads.count == references
                && ProximityLightingTopologyContext.loads.values.allSatisfy { $0 == 1 }, "One classifier inventory per referenced Space")
            require(request(site) == nil, "Completed batch clears recovery")
            require(current!.spaces.allSatisfy { $0.revision == 1 }, "Batch returns fresh stored Spaces")
            print("Batch K=\(count), R=\(references): \(ProximityLightingTopologyContext.loads.values.reduce(0, +)) inventory reads")
        }
        for add in [false, true] {
            let site = try reset()
            let operation: SyncOperation = add ? .addSpaces(site: site, spaces: site.spaces) : .syncSite(site: site, syncSpaces: site.spaces)
            let api = await operation.getNetworkApi()
            require(api != nil && CleanupFixture.exportedMembers == 3, "Upload exports cleaned Zone state")
            require(CleanupFixture.exportedRevisions == [1, 1, 1, 1], "Upload sees fresh Space revisions")
            require(ProximityLightingTopologyContext.loads.values.allSatisfy { $0 == 1 }, "Upload batch must not regress to K x R")
        }
        let empty = try reset(references: 0)
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: empty, spaces: empty.spaces)
        require(ProximityLightingTopologyContext.loads.isEmpty, "Empty Zones load no Mesh")
        let single = try reset()
        require(await SpaceSyncCleanupCoordinator.prepare(single.spaces[0]), "Single preparation succeeds")
        require(ProximityLightingTopologyContext.loads.count == 3 && (request(single)) == nil, "Single caller completes Site cleanup")
        let unavailable = try reset()
        ProximityLightingTopologyContext.networks["space-1"] = nil
        SpaceData.stored[2].blocked = true
        CleanupFixture.failures = ["space-0"]
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: unavailable, spaces: unavailable.spaces)
        let data = try SiteExtensionStore.load(unavailable).data
        require(data.zones!.first!.displayMembers.count == 5, "Partial failures preserve unknown/blocked members and still clean readable obsolete references")
        require(ProximityLightingTopologyContext.loads == ["space-0": 1, "space-1": 1], "Failed Mesh read is cached and blocked Space is not loaded")
        let readsBeforeRemote = ProximityLightingTopologyContext.loads["space-0"]!
        _ = try SiteTriggerZoneCoordinator(site: unavailable).cleanObsoleteMembers()
        require(ProximityLightingTopologyContext.loads["space-0"] == readsBeforeRemote + 1,
                "Independent post-remote cleanup is not suppressed by a completed batch")
    }

    static func testPreparationFailureGatesUpload() async throws {
        for kind in ["space", "site", "addSpaces"] {
            let site = try reset(count: 2, references: 0)
            CleanupFixture.failures = [site.spaces[0].id]
            CleanupFixture.spaceExports = 0
            let operation: SyncOperation
            switch kind {
            case "space": operation = .syncSpace(space: site.spaces[0])
            case "site": operation = .syncSite(site: site, syncSpaces: site.spaces)
            default: operation = .addSpaces(site: site, spaces: site.spaces)
            }
            let failed = await operation.getNetworkApi()
            require(failed == nil && CleanupFixture.spaceExports == 0 && CleanupFixture.exportedMembers == -1,
                    "\(kind) must not export after failed preparation")
            CleanupFixture.failures = []
            require(await operation.getNetworkApi() != nil, "\(kind) preparation can retry without permanent blocking")
        }
        let site = try reset(count: 2, references: 0)
        CleanupFixture.failures = [site.spaces[0].id]
        let discovered = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: site.spaces,
                                                                        requiringSuccessfulPreparation: false)
        require(discovered != nil && CleanupFixture.prepared.count == 2,
                "background discovery must still inspect independent Spaces")
        let shared = try reset(count: 1, references: 0)
        let first = shared.spaces[0], second = SpaceData.load(siteId: shared.id)[0]
        CleanupFixture.failures = [first.id]; CleanupFixture.pauseSpace = first.id
        let started = Task { await SpaceSyncCleanupCoordinator.prepare(first) }
        await wait { CleanupFixture.suspended != nil }
        let joined = Task { await SpaceSyncCleanupCoordinator.prepare(second) }
        await settle()
        CleanupFixture.suspended?.resume(); CleanupFixture.suspended = nil
        let firstResult = await started.value, secondResult = await joined.value
        require(!firstResult && !secondResult && CleanupFixture.prepared.count == 1
                && first.syncCloudError == .noNetwork && second.syncCloudError == .noNetwork,
                "joining the same preparation must receive its network error on a different Space instance")
        print("PASS: single/batch upload stops before export on preparation failure and retries; independent discovery remains available")
    }
    static func testPersistenceAndFailures() async throws {
        let site = try reset()
        let generation = UUID()
        try SiteExtensionStore.update(site) { $0.referenceCleanupRequests = ["account": generation, "other": UUID()] }
        // Reopen an actual SQLite file to model an empty process-local owner map.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: url) }
        let saved = try SiteExtensionStore.load(site)
        SunSmartDataManager.shared.db = try Connection(url.path)
        try SiteExtensionStore.createTable()
        try SiteExtensionStore.update(site) { $0 = saved }
        SunSmartDataManager.shared.db = nil
        SunSmartDataManager.shared.db = try Connection(url.path)
        require(request(site) == generation, "Cleanup generation survives database reopen")
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: [])
        require(request(site) == nil, "No-candidate recovery consumes interrupted cleanup")
        require(request(site, account: "other") != nil, "Cleanup keeps another account's request")
        for protection in 0..<4 {
            let site = try reset()
            try SiteExtensionStore.update(site) { state in
                state.referenceCleanupRequests = ["account": generation]
                if protection == 0 { state.conflict = true }
                if protection == 1 { state.ambiguousRemote = true }
                if protection == 2 { state.rejectedRemote = Data() }
                if protection == 3 { state.submitted = .init(operationId: UUID(), timestamp: 1, base: nil, target: state.data) }
            }
            _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: [])
            require(request(site) == generation, "Deferred cleanup retains durable request")
            require(ProximityLightingTopologyContext.loads.isEmpty, "Protected state is not scanned")
        }
        let denied = try reset()
        denied.canManageSiteTriggerZones = false
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: denied, spaces: denied.spaces)
        require(request(denied) != nil, "Permission-deferred cleanup survives")
        let failing = try reset()
        let db = SunSmartDataManager.shared.db!
        try db.run("CREATE TRIGGER fail_cleanup BEFORE INSERT ON site_extensions BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        let result = await SpaceSyncCleanupCoordinator.prepareBatch(site: failing, spaces: failing.spaces)
        require(result == nil && CleanupFixture.prepared.isEmpty, "No mutations before durable request succeeds")
        try db.run("DROP TRIGGER fail_cleanup")
        CleanupFixture.onPrepare = { _ in
            try! db.run("CREATE TRIGGER IF NOT EXISTS fail_cleanup BEFORE INSERT ON site_extensions BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        }
        let failedFinish = await SpaceSyncCleanupCoordinator.prepareBatch(site: failing, spaces: failing.spaces)
        require(failedFinish == nil && (request(failing)) != nil, "Failed Zone commit retains request")
        try db.run("DROP TRIGGER fail_cleanup")
        CleanupFixture.onPrepare = nil
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: failing, spaces: [])
        require(request(failing) == nil, "Later recovery finishes failed commit")
    }
    static func testOverlap() async throws {
        let site = try reset()
        CleanupFixture.pauseSpace = "space-0"
        let batch = Task { await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: site.spaces) }
        await wait { CleanupFixture.suspended != nil }
        let before = request(site)
        // Different Space: the single caller finishes while the batch has future writes.
        let single = await SpaceSyncCleanupCoordinator.prepare(site.spaces[1])
        require(single && (request(site)) != nil, "Single cleanup cannot erase another owner's recovery")
        require(request(site) != before, "Overlapping operation advances generation")
        let continuation = CleanupFixture.suspended!; CleanupFixture.suspended = nil
        continuation.resume()
        _ = await batch.value
        require(request(site) == nil, "Last owner clears fully completed work")
        let shared = try reset(count: 1, references: 1)
        CleanupFixture.pauseSpace = "space-0"
        let first = Task { await SpaceSyncCleanupCoordinator.prepareBatch(site: shared, spaces: shared.spaces) }
        await wait { CleanupFixture.suspended != nil }
        let waiter = Task { await SpaceSyncCleanupCoordinator.prepare(shared.spaces[0]) }
        await settle()
        require(CleanupFixture.prepared.count == 1, "Single/batch share the same in-flight Space repair")
        let completion = CleanupFixture.suspended!; CleanupFixture.suspended = nil; completion.resume()
        _ = await first.value
        require(await waiter.value, "Shared-task single still finishes cleanup")
        require(request(shared) == nil, "Both owners finish without orphaning a marker")
    }
    static func testCancellationAndScope() async throws {
        let site = try reset()
        CleanupFixture.pauseSpace = "space-0"
        let task = Task { await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: site.spaces) }
        await wait { CleanupFixture.suspended != nil }
        task.cancel()
        let completion = CleanupFixture.suspended!; CleanupFixture.suspended = nil; completion.resume()
        require(await task.value == nil, "Cancelled batch stops before further work")
        require(CleanupFixture.prepared.count == 1 && (request(site)) != nil, "Cancellation keeps recovery after shared repair settles")
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: [])
        require(request(site) == nil, "Cancelled batch is recoverable without upload candidates")
        for regionChange in [false, true] {
            let site = try reset()
            CleanupFixture.pauseSpace = "space-0"
            let task = Task { await SpaceSyncCleanupCoordinator.prepareBatch(site: site, spaces: site.spaces) }
            await wait { CleanupFixture.suspended != nil }
            let generation = request(site)
            if regionChange { UserData.currentServerRegion = .second } else { UserData.currentUserId = "other" }
            let completion = CleanupFixture.suspended!; CleanupFixture.suspended = nil; completion.resume()
            require(await task.value == nil, "Old scope cannot finish or return an upload snapshot")
            require(ProximityLightingTopologyContext.loads.isEmpty && (request(site)) == generation, "Old task leaves cleanup in original scope")
        }
        let site2 = try reset()
        let other = SiteData("other-site"); SiteData.stored[other.id] = other
        let foreign = SpaceData("foreign", site: other.id)
        require(await SpaceSyncCleanupCoordinator.prepareBatch(site: site2, spaces: [foreign]) == nil,
                "Batch rejects cross-Site inputs")
        require(CleanupFixture.prepared.isEmpty, "Foreign input never starts repair")
    }
    static func testRecovery() async throws {
        let site = try reset(count: 100, references: 80)
        let manager = CloudSynchronizationManager()
        manager.resumePendingSynchronizations()
        await wait { manager.uploads == 1 }
        require(CleanupFixture.prepared.count == 100 && ProximityLightingTopologyContext.loads.values.allSatisfy { $0 == 1 },
                "Foreground entry runs one batch")
        require(CleanupFixture.membersAtSynchronization == 80, "Zone pending sync sees cleanup before upload scheduling")
        let idle = try reset()
        SpaceData.stored.forEach { $0.needUploadCloud = false }
        try SiteExtensionStore.update(idle) { $0.referenceCleanupRequests = ["account": UUID()] }
        let idleManager = CloudSynchronizationManager()
        idleManager.resumePendingSynchronizations()
        await wait { CleanupFixture.synchronizations == 1 }
        require(CleanupFixture.prepared.isEmpty && (request(idle)) == nil && idleManager.uploads == 0,
                "Foreground recovers Site-only pending cleanup")
        _ = try reset(count: 3, references: 0)
        SpaceData.stored.forEach { $0.needUploadCloud = false; $0.initialized = false }
        SpaceData.stored[0].pendingUpload = true
        SpaceData.stored[1].pendingUpload = true; SpaceData.stored[1].blocked = true
        let pendingManager = CloudSynchronizationManager()
        pendingManager.resumePendingSynchronizations()
        await wait { pendingManager.uploads == 1 }
        require(pendingManager.uploadedIDs == ["space-0"] && CleanupFixture.prepared.isEmpty,
                "Uninitialized pending readbacks are queued before cleanup; unauthorized receipts and placeholders are excluded")
        let skipped = try reset(count: 1, references: 1)
        var checks = 0
        _ = await SpaceSyncCleanupCoordinator.prepareBatch(site: skipped, spaces: skipped.spaces,
            shouldPrepare: { _ in checks += 1; return checks == 1 })
        require(CleanupFixture.prepared.isEmpty && ProximityLightingTopologyContext.loads.isEmpty,
                "Upload starting during queue handoff is skipped")
        let offline = try reset()
        NetworkRequest.shared.networkable = false
        CloudSynchronizationManager().resumePendingSynchronizations()
        await settle()
        require(CleanupFixture.prepared.isEmpty && (request(offline)) == nil, "Offline recovery does no local preparation")
        let interrupted = try reset()
        var online = true
        CleanupFixture.onPrepare = { _ in online = false }
        let interruptedResult = await SpaceSyncCleanupCoordinator.prepareBatch(
            site: interrupted, spaces: interrupted.spaces, shouldContinue: { online })
        require(interruptedResult == nil && CleanupFixture.prepared.count == 1
            && request(interrupted) != nil, "Network loss between Spaces retains unfinished Site cleanup")
        let failingSite = try reset(count: 1, references: 1)
        let other = SiteData("other-site"); SiteData.stored[other.id] = other
        let foreign = SpaceData("other-space", site: other.id)
        SpaceData.stored.append(foreign)
        other.spaces = [foreign]
        try SunSmartDataManager.shared.db!.run("CREATE TRIGGER fail_one_site BEFORE INSERT ON site_extensions WHEN NEW.siteId = 'site' BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        let partialManager = CloudSynchronizationManager()
        partialManager.resumePendingSynchronizations()
        await wait { partialManager.uploads == 1 }
        await settle()
        require(CleanupFixture.prepared == ["other-space"] && request(failingSite) == nil,
                "A Site storage failure does not skip another Site's recoverable work")
        _ = site
    }
}
