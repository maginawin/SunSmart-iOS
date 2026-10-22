import Foundation

// Durable data and network are explicit boundaries. Production Manager/Handle/
// AddBatch perform all admission, coalescing, cancellation and upload scheduling.
enum UserData { static var currentUserId = "owner", currentServerRegion = "test" }
enum NetworkApiError: Error { case noNetwork, configurationUnavailable, unknown }
protocol Cancellable { func cancel() }
final class Node {
    let uuid = UUID()
    let primaryUnicastAddress: UInt16
    init(_ address: UInt16 = 1) { primaryUnicastAddress = address }
    func export() async -> [String: Any]? { [:] }
}
enum MeshAPI { static var addresses: [UInt16] = []
    static func getTheUsedDeviceAddresses(meshUUID: String) -> [UInt16] { addresses }
    static var stop: (([Node], [Node]) -> Void)?
    static func stopFastAddDevice(finishBack: (([Node], [Node]) -> Void)?) { stop = finishBack }
}
enum SpaceChangeDataType { case network(type: Kind); enum Kind { case address } }
final class SpaceData {
    static var rows: [String: SpaceData] = [:]
    let id: String, siteId: String
    var meshUUID: String, meshNetworkId = "network", canEditing = true
    var lastUpdate: Int64 = 1, lastUploadCloudTimestamp: Int64? = 1
    var syncCloudError: NetworkApiError?
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) }
    var pending: Int64?, blocked = false, member = true
    var siteCreationTimestamp: Int64?
    var hdb: Int? = nil, hdbPersistenceBaseline: Int? = nil, hdbLoadFailed = false
    init(_ id: String, site: String = "site") { self.id = id; siteId = site; meshUUID = site }
    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] {
        rows.values.filter { $0.siteId == siteId && (spaceId == nil || $0.id == spaceId) }
    }
    @discardableResult func save() -> Bool { Self.rows[id] = self; return true }
    func refreshSummaryCountsFromSpaceMesh() {}
    func markLocalChangePendingCloudSync() { lastUpdate += 1; save() }
    func commitLocalChangeForCloudSync(changeType: SpaceChangeDataType) {
        markLocalChangePendingCloudSync()
        guard let site = SiteData.load(siteId: siteId) else { return }
        site.markSiteUploadNeededForSpaceAddressChange()
        CloudSynchronizationManager.shared.addSynchronizationHandle(operation: .syncSite(site: site, syncSpaces: [self]), level: .promptly)
    }
    enum Purpose { case cloudSync }
    func export(purpose: Purpose) async -> [String: Any]? { ["uuid": id, "updateTimestamp": lastUpdate] }
}
final class SiteData {
    static var rows: [String: SiteData] = [:]
    let id: String
    var meshUUID: String, spaces: [SpaceData] = []
    var uploadCloud: Bool { lastUploadCloudTimestamp != nil }
    var restoredProvisioner = false
    var lastUpdate: Int64 = 1, lastUploadCloudTimestamp: Int64? = 1
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) }
    enum State { case normal }; var state = State.normal
    var canManageSiteTriggerZones = true
    var syncCloudError: NetworkApiError?, timezone: String?, name = "Site", imageId = 0
    var pendingSitePropsMask = 0, pendingSitePropsTimestamp: Int64? = nil
    init(_ id: String = "site") { self.id = id; meshUUID = id }
    static func load(siteId: String) -> SiteData? { rows[siteId] }
    static func loadAll() -> [SiteData] { Array(rows.values) }
    @discardableResult func save() -> Bool { Self.rows[id] = self; return true }
    func markSiteUploadNeededForSpaceAddressChange() { lastUpdate += 1; save() }
    func setOwnerProvisioner(addressData: [String: Any]) {}
    func setProvisioner(provisionerData: [String: Any]) { restoredProvisioner = true }
    func export(spaceIds: [String]) async -> [String: Any]? {
        ["uuid": id, "updateTimestamp": lastUpdate, "spaces": spaceIds.compactMap { SpaceData.rows[$0] }.map { ["uuid": $0.id, "updateTimestamp": $0.lastUpdate] as [String: Any] }]
    }
}
enum NetowrkReqeustApi {
    case spaceInfo(siteId: String, spaceId: String)
    case siteInfo(siteId: String)
    case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any])
    case siteUpload(siteData: [String: Any])
    case siteAdd(siteData: [String: Any], useDeivceAddressNum: Int)
    case gatewayRegister(siteId: String, gatewayId: String, nodeId: String, node: [String: Any], updateTimestamp: Int64)
}
final class NetworkRequest {
    static let shared = NetworkRequest()
    var networkable = true
    var requests: [NetowrkReqeustApi] = []
    var holdNextPost = false
    var held: CheckedContinuation<Result<[String: Any], NetworkApiError>, Never>?
    func request(_ api: NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> {
        requests.append(api)
        if !networkable { return .failure(.noNetwork) }
        switch api {
        case .siteInfo(let id): return .success(["data": ["uuid": id, "provisioner": [:] as [String: Any]]])
        case .siteUpload, .spaceUpload:
            if holdNextPost { holdNextPost = false; return await withCheckedContinuation { held = $0 } }
        default: break
        }
        return .success([:])
    }
    var posts: Int { requests.filter { if case .siteUpload = $0 { return true }; if case .spaceUpload = $0 { return true }; return false }.count }
    var reads: Int { requests.filter { if case .spaceInfo = $0 { return true }; return false }.count }
}
struct SpaceRecoveryState { var siteCreationTimestamp: Int64?; var unbindRequested = false }
enum SpaceConfigurationSafety {
    static let uploadUnconfirmed = NetworkApiError.unknown
    static var refuseRead = false
    static func recoveryState(_ space: SpaceData) throws -> SpaceRecoveryState { .init(siteCreationTimestamp: space.siteCreationTimestamp) }
    static func isCurrent(_ state: SpaceRecoveryState, space: SpaceData) -> Bool { true }
    static func hasPendingUpload(_ space: SpaceData) -> Bool { space.pending != nil }
    static func canAutomaticallyUpload(_ space: SpaceData) -> Bool { space.member && space.canEditing }
    static func canResumePendingUpload(_ space: SpaceData) -> Bool { hasPendingUpload(space) }
    static func isBlocked(_ space: SpaceData) -> Bool { space.blocked }
    static func resumeLocalRemovals() {}
    static func resumeUnbind(_ space: SpaceData) async -> Bool { true }
    static func resumeUpload(_ space: SpaceData) async -> Result<Void, NetworkApiError> {
        let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id))
        guard case .success = response, !refuseRead else { return .failure(.unknown) }
        if let submitted = space.pending { space.lastUploadCloudTimestamp = submitted; space.pending = nil }
        return .success(())
    }
    static func prepareSubmission(_ space: SpaceData, payload: [String: Any], siteCreationTimestamp: Int64?) -> SpaceRecoveryState? {
        space.pending = payload["updateTimestamp"] as? Int64; return .init()
    }
    static func discardUnsentSubmission(_ context: SpaceRecoveryState, space: SpaceData) { space.pending = nil }
    static func markSubmissionAccepted(_ context: SpaceRecoveryState, space: SpaceData) -> Bool { true }
    static func rejectSubmission(_ context: SpaceRecoveryState, space: SpaceData, error: NetworkApiError) {}
    static func finishCloudRemovalUpload(_ space: SpaceData) async -> Result<Void, NetworkApiError> { .success(()) }
}
enum SpaceMembershipCoordinator {
    static func resumeLeaves() async {}
    static func isLeaving(_ space: SpaceData) -> Bool { !space.member }
    static func allowsConfiguration(_ space: SpaceData) -> Bool { space.member }
}
enum SiteDeviceOwnershipReconciler { static func reconcile(siteId: String) {} }
enum SpaceSyncCleanupCoordinator {
    static var prepared: [String] = []
    static func prepare(_ space: SpaceData) async -> Bool { prepared.append(space.id); return true }
    static func prepareBatch(site: SiteData, spaces: [SpaceData], requiringSuccessfulPreparation: Bool = true,
                             shouldContinue: () -> Bool = { true }, shouldPrepare: (SpaceData) -> Bool = { _ in true }) async -> SiteData? {
        for space in spaces where shouldContinue() && shouldPrepare(space) { _ = await prepare(space) }
        return site
    }
}
enum SiteExtensionStore { struct State { var pending: Int? = nil }; static func load(_ site: SiteData) throws -> State { .init() } }
struct SiteTriggerZoneCoordinator { let site: SiteData; func synchronize() async -> Bool { true } }
enum SpaceConfigurationIntegrityPolicy {
    static func integer(_ value: Any?) -> Int64? { value as? Int64 }
    static func confirmedTimestamp(previous: Int64?, submitted: Int64) -> Int64 { max(previous ?? 0, submitted) }
}
struct SiteTimeZoneValue { init?(storageValue: String) {} }
struct SiteInitialTimeZoneSubmission { let timezone: SiteTimeZoneValue; let timestamp: Int64 }
struct SitePropsValues { let siteName: String; let imageId: Int; let timezone: SiteTimeZoneValue? }
struct SitePropsPendingState { let fields: Int; let timestamp: Int64? }
struct SitePropsLocalState { let values: SitePropsValues; let lastUpdate: Int64; let lastUploadCloudTimestamp: Int64?; let pending: SitePropsPendingState }
enum SitePropsEditPolicy {
    static func localStateAfterSuccessfulInitialSiteUpload(current: SitePropsLocalState, submission: SiteInitialTimeZoneSubmission) -> SitePropsLocalState { current }
}
struct JSON {
    let value: Any
    init(_ value: Any) { self.value = value }
    subscript(key: String) -> JSON { JSON((value as? [String: Any])?[key] as Any) }
    var dictionaryObject: [String: Any]? { value as? [String: Any] }
}
final class GatewayModel {
    var mac = "gateway", siteId = "site", lastUpdate: Int64 = 1, lastUploadCloudTimestamp: Int64? = nil
    var syncCloudError: NetworkApiError?, activate = true
    var isServerDeletionInProgress = false, serverDeletionPendingLocalReset = false
    struct Snapshot { var nodeData: [String: Any]? }; var registrationProtectionSnapshot: Snapshot?
    struct Space { let appKeyIndex: Int }; var associatedSpaces: [Space] = []
    func export() -> [String: Any] { [:] }; func save() {}
}
enum GatewayRegistrationPayloadPolicy {
    static func mergeOpaqueAssociationData(localNode: [String: Any], remoteNode: [String: Any]?, associatedAppKeyIndexes: [Int], isActivated: Bool) -> [String: Any] { localNode }
}
enum GatewayCloudSyncGenerationPolicy {
    static func confirmed(previous: Int64?, submitted: Int64) -> Int64 { submitted }
    static func needsAnotherUpload(current: Int64, confirmed: Int64?) -> Bool { current != confirmed }
}
final class GatewayServerAuthorizationService {
    static let shared = GatewayServerAuthorizationService()
    struct Receipt { let submittedGeneration: Int64 }; struct Failure: Error { let networkApiError = NetworkApiError.unknown }
    enum Policy { case always }
    func authorizeWithReceipt(gateway: GatewayModel, node: Node, policy: Policy, requestedGeneration: Int64) async -> Result<Receipt, Failure> { .success(.init(submittedGeneration: requestedGeneration)) }
}
final class HDBDeviceAddCompletion {
    var isRunning = false
    var stopped: (() -> Void)?
    func cancel() { stopped?() }
    static func currentBatchNodes(addresses: Set<UInt16>, nodes: [Node]) -> [Node] { nodes.filter { addresses.contains($0.primaryUnicastAddress) } }
}

@main enum DeviceAddCloudBatchTests {
    static func main() {
        Task { @MainActor in await run(); exit(0) }
        RunLoop.main.run()
    }
    @MainActor static func ticks(_ count: Int = 20) async {
        for _ in 0..<count { await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } } }
    }
    @MainActor static func fixture(_ id: String = "a", site: String = "site") -> SpaceData {
        if SiteData.rows[site] == nil { SiteData(site).save() }
        let space = SpaceData(id, site: site); space.save()
        SiteData.rows[site]!.spaces = SpaceData.load(siteId: site)
        return space
    }
    @MainActor static func resetRequests() { NetworkRequest.shared.requests = []; SpaceSyncCleanupCoordinator.prepared = [] }
    @MainActor static func run() async {
        let manager = CloudSynchronizationManager.shared
        let a = fixture(), b = fixture("b"), c = fixture("c", site: "other")
        for count in [1, 10] {
            resetRequests()
            let batch = HDBDeviceAddBatch(); var started = 0, callbacks = 0
            for _ in 0..<count { batch.enqueue(space: a) { if $0 { started += 1 } } }
            await ticks(); precondition(started == count)
            for index in 0..<count {
                batch.recordProvisioned(Node(UInt16(index + 1)), batch: batch.identifier)
                for _ in 0..<9 {
                    a.markLocalChangePendingCloudSync()
                    manager.addSynchronizationHandle(operation: .syncSpace(space: a), level: .promptly) { if case .successful = $0 { callbacks += 1 } }
                }
            }
            manager.resumePendingSynchronizations(); await ticks()
            precondition(NetworkRequest.shared.requests.isEmpty && SpaceSyncCleanupCoordinator.prepared.isEmpty)
            batch.finish(); await ticks()
            precondition(NetworkRequest.shared.posts == 1 && NetworkRequest.shared.reads == 2)
            precondition(callbacks == count * 9 && !a.needUploadCloud)
            batch.finish(); await ticks(); precondition(NetworkRequest.shared.requests.count == 3)
        }
        // A mixed Site request keeps its other Space. Independent sites and
        // direct uploads of another Space continue while A is provisioning.
        resetRequests()
        let batch = HDBDeviceAddBatch(); batch.enqueue(space: a) { precondition($0) }; await ticks()
        manager.addSynchronizationHandle(operation: .syncSpace(space: b), level: .promptly)
        manager.addSynchronizationHandle(operation: .syncSpace(space: c), level: .promptly)
        await ticks(); precondition(NetworkRequest.shared.posts == 2)
        manager.addSynchronizationHandle(operation: .syncSite(site: SiteData.rows["site"]!, syncSpaces: [a, b]), level: .promptly)
        batch.recordProvisioned(Node(20), batch: batch.identifier); batch.finish(); await ticks()
        precondition(NetworkRequest.shared.posts == 3)
        guard case .siteUpload(let payload) = NetworkRequest.shared.requests.first(where: { if case .siteUpload = $0 { return true }; return false })! else { fatalError() }
        precondition(Set((payload["spaces"] as! [[String: Any]]).map { $0["uuid"] as! String }) == ["a", "b"])
        // Empty/cancelled admission does not manufacture an upload.
        resetRequests()
        let empty = HDBDeviceAddBatch(); empty.enqueue(space: a) { _ in }; empty.cancelWaiting(); await ticks()
        precondition(NetworkRequest.shared.requests.isEmpty && !empty.isActive)
        // Page release/stop waits for FastAdd teardown, including partial failure.
        let closing = HDBDeviceAddBatch(); closing.enqueue(space: a) { _ in }; await ticks()
        closing.recordProvisioned(Node(30), batch: closing.identifier)
        closing.close(completion: HDBDeviceAddCompletion()); await ticks()
        precondition(NetworkRequest.shared.requests.isEmpty && closing.isActive)
        MeshAPI.stop?([], []); MeshAPI.stop = nil; await ticks()
        precondition(NetworkRequest.shared.posts == 1)
        // Offline finalization leaves durable dirty data for foreground recovery.
        resetRequests(); NetworkRequest.shared.networkable = false
        let offline = HDBDeviceAddBatch(); offline.enqueue(space: a) { _ in }; await ticks()
        offline.recordProvisioned(Node(31), batch: offline.identifier); offline.finish(); await ticks()
        precondition(NetworkRequest.shared.requests.isEmpty && a.needUploadCloud)
        NetworkRequest.shared.networkable = true; manager.resumePendingSynchronizations(); await ticks(80)
        precondition(NetworkRequest.shared.posts == 1 && !a.needUploadCloud)
        // An in-flight prior generation must settle before the next batch starts.
        resetRequests(); a.markLocalChangePendingCloudSync(); NetworkRequest.shared.holdNextPost = true
        manager.addSynchronizationHandle(operation: .syncSpace(space: a), level: .promptly); await ticks()
        precondition(NetworkRequest.shared.held != nil)
        let next = HDBDeviceAddBatch(); var admitted = false
        next.enqueue(space: a) { admitted = $0 }; await ticks(); precondition(!admitted)
        NetworkRequest.shared.held?.resume(returning: .success([:])); NetworkRequest.shared.held = nil; await ticks()
        precondition(admitted); next.finish(); await ticks()
        // Old account tokens and late provision callbacks cannot mutate a new context.
        resetRequests(); let stale = HDBDeviceAddBatch(); stale.enqueue(space: a) { _ in }; await ticks()
        let oldToken = stale.identifier; UserData.currentUserId = "replacement"
        stale.recordProvisioned(Node(32), batch: oldToken); stale.finish(); await ticks()
        precondition(NetworkRequest.shared.requests.isEmpty)
        UserData.currentUserId = "owner"
        // Existing timers and callback owners are absorbed, including Site-only work.
        resetRequests(); var oldCallbacks = 0
        let oldSpace = manager.addSynchronizationHandle(operation: .syncSpace(space: a), level: .slow) { if case .successful = $0 { oldCallbacks += 1 } }
        let oldSite = manager.addSynchronizationHandle(operation: .syncSite(site: SiteData.rows["site"]!), level: .slow) { if case .successful = $0 { oldCallbacks += 1 } }
        let timers = HDBDeviceAddBatch(); timers.enqueue(space: a) { _ in }; await ticks()
        precondition(NetworkRequest.shared.requests.isEmpty)
        timers.recordProvisioned(Node(40), batch: timers.identifier); timers.finish()
        // An immediate new intent before the final timer fires must retain Site/address upload.
        a.markLocalChangePendingCloudSync()
        manager.addSynchronizationHandle(operation: .syncSpace(space: a), level: .promptly)
        manager.setSynchronizationHandleLevel(handle: oldSpace, level: .promptly)
        await ticks()
        precondition(NetworkRequest.shared.posts == 1 && oldCallbacks == 2)
        precondition(oldSpace.state.rawValue == 2 && oldSite.state.rawValue == 2)
        // New selections during the HDB tail remain inside the same cloud batch.
        resetRequests(); let overlapping = HDBDeviceAddBatch(); overlapping.enqueue(space: a) { _ in }; await ticks()
        let firstNode = Node(41), secondNode = Node(42)
        overlapping.recordProvisioned(firstNode, batch: overlapping.identifier); overlapping.beginPreparation()
        var nextStarted = false
        overlapping.enqueue(space: a) { nextStarted = $0 }
        precondition(!nextStarted)
        overlapping.finish(); await ticks()
        precondition(nextStarted && overlapping.isActive && NetworkRequest.shared.requests.isEmpty)
        overlapping.recordProvisioned(secondNode, batch: overlapping.identifier)
        precondition(overlapping.nodes(addresses: [42], currentNodes: [firstNode, secondNode]).map(\.uuid) == [secondNode.uuid])
        overlapping.finish(); await ticks(); precondition(NetworkRequest.shared.posts == 1)
        // New edits after POST form another generation; the old acknowledgement
        // cannot cancel the new request or claim its newer version was uploaded.
        resetRequests(); let posting = HDBDeviceAddBatch(); posting.enqueue(space: a) { _ in }; await ticks()
        posting.recordProvisioned(Node(43), batch: posting.identifier)
        NetworkRequest.shared.holdNextPost = true; posting.finish(); await ticks()
        precondition(NetworkRequest.shared.held != nil)
        a.markLocalChangePendingCloudSync(); let newVersion = a.lastUpdate
        manager.addSynchronizationHandle(operation: .syncSpace(space: a), level: .promptly)
        await ticks(); precondition(NetworkRequest.shared.posts == 1 && a.lastUploadCloudTimestamp != newVersion)
        NetworkRequest.shared.held?.resume(returning: .success([:])); NetworkRequest.shared.held = nil; await ticks(60)
        precondition(NetworkRequest.shared.posts == 2 && a.lastUploadCloudTimestamp == newVersion)
        // Historical receipt must be read before admission. A failed read or
        // revoked membership cannot start provisioning or bypass the final gate.
        resetRequests(); a.pending = a.lastUpdate
        SpaceConfigurationSafety.refuseRead = true
        let historical = HDBDeviceAddBatch(); var rejected = false
        historical.enqueue(space: a) { rejected = !$0 }; await ticks()
        precondition(rejected && !historical.isActive && NetworkRequest.shared.reads == 1 && NetworkRequest.shared.posts == 0)
        SpaceConfigurationSafety.refuseRead = false
        let recovered = HDBDeviceAddBatch(); recovered.enqueue(space: a) { precondition($0) }; await ticks()
        recovered.finish(); await ticks(); precondition(NetworkRequest.shared.posts == 0 && a.pending == nil)
        resetRequests(); let revoked = HDBDeviceAddBatch(); revoked.enqueue(space: a) { _ in }; await ticks()
        revoked.recordProvisioned(Node(44), batch: revoked.identifier)
        SpaceConfigurationSafety.refuseRead = true; revoked.finish(); await ticks()
        precondition(NetworkRequest.shared.posts == 0 && a.needUploadCloud)
        SpaceConfigurationSafety.refuseRead = false
        a.member = false; let forbidden = HDBDeviceAddBatch(); forbidden.enqueue(space: a) { precondition(!$0) }; await ticks()
        precondition(!forbidden.isActive); a.member = true
        // A crashed first Site POST also owns address resources. Admission must
        // recover Site acceptance, not only clear the Space receipt.
        resetRequests(); let firstSiteSpace = fixture("new-space", site: "new-site")
        let firstSite = SiteData.rows["new-site"]!
        firstSite.lastUploadCloudTimestamp = nil
        firstSiteSpace.pending = 1; firstSiteSpace.siteCreationTimestamp = 1
        let firstCreation = HDBDeviceAddBatch(); var creationAdmitted = false
        firstCreation.enqueue(space: firstSiteSpace) { creationAdmitted = $0 }; await ticks(60)
        precondition(creationAdmitted && firstSite.uploadCloud && firstSite.restoredProvisioner)
        firstCreation.finish(); await ticks()
        precondition(NetworkRequest.shared.posts == 0 && NetworkRequest.shared.requests.count == 2)
        print("PASS: production add batch + cloud manager/HTTP flow: 1/10 nodes, 3 requests, callbacks, mixed scopes, empty, stop, offline recovery, in-flight admission, queued selections, subsequent generations, historical receipt/authority and account isolation")
    }
}
