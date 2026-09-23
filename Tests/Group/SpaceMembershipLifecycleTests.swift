import Foundation

enum Permission { case owner, editor, visitor }
enum NetworkApiError: Error { case noNetwork, noSpacePermission, noSitePermission, resourceNotFound, configurationUploadUnconfirmed, incorrectPassword, spacePasswordOverdue }
enum UserData { static var currentUserId = "account", currentServerRegion = "region" }
let SitesDataRefreshNotifiacationName = "sitesChanged"

// SDK decoding and database/transport I/O are controlled boundaries. The tests
// execute the production identity preparation, membership store and leave workflow.
struct TestID { let hex: String }
struct NetworkKey: Decodable {
    let index: Int; let testNetworkID: String
    var networkId: TestID { .init(hex: testNetworkID) }
}
struct ApplicationKey: Decodable { let boundNetworkKeyIndex: Int }
enum SpaceKeyIntegrity {
    struct Pair { let network: NetworkKey }
    static func decodeNetwork(_ payload: [String: Any]) -> NetworkKey? {
        guard let value = payload["netKey"] as? [String: Any],
              let data = try? JSONSerialization.data(withJSONObject: value) else { return nil }
        return try? JSONDecoder().decode(NetworkKey.self, from: data)
    }
    static func pair(_ payload: [String: Any], networkID: String) -> Pair? {
        guard let key = decodeNetwork(payload), key.networkId.hex == networkID,
              let app = payload["appKey"] as? [String: Any],
              app["boundNetworkKeyIndex"] as? Int == key.index else { return nil }
        return .init(network: key)
    }
    @MainActor static func replenish(_ space: SpaceData, from pair: Pair) -> Bool { true }
}
struct SpaceImportOutcome: Equatable {
    enum Status { case applied, rejected, skipped }
    let status: Status
    let rejectionReason: String?
    static func rejected(_ reason: String) -> Self { .init(status: .rejected, rejectionReason: reason) }
    static func preserved(_ reason: String) -> Self { .init(status: .skipped, rejectionReason: reason) }
}
final class SpaceData {
    let id: String
    var siteId = "site", meshNetworkId = "", meshUUID = "mesh"
    var permission = Permission.editor
    var authorizationPassword: String?
    var lastUploadCloudTimestamp: Int64?
    var saveSucceeds = true, deleteSucceeds = true, applySucceeds = true
    var updateCalls = 0, deleteCalls = 0
    var onUpdate: (() -> Void)?
    static var rows: [String: SpaceData] = [:]
    init(_ id: String) { self.id = id }
    func copy() -> SpaceData {
        let result = SpaceData(id); result.applyConfigurationState(from: self)
        result.saveSucceeds = saveSucceeds; result.deleteSucceeds = deleteSucceeds
        result.applySucceeds = applySucceeds; result.onUpdate = onUpdate
        return result
    }
    func applyConfigurationState(from value: SpaceData) {
        meshNetworkId = value.meshNetworkId; lastUploadCloudTimestamp = value.lastUploadCloudTimestamp
        permission = value.permission; updateCalls = value.updateCalls
    }
    func save() -> Bool { if saveSucceeds { Self.rows[id] = self }; return saveSucceeds }
    func delete() -> Bool { deleteCalls += 1; if deleteSucceeds { Self.rows[id] = nil }; return deleteSucceeds }
    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] {
        if let spaceId { return rows[spaceId].map { [$0] } ?? [] }
        return Array(rows.values).filter { $0.siteId == siteId }
    }
    @MainActor func update(spaceJsonData: [String: Any], initialize: Bool) async -> SpaceImportOutcome {
        precondition(spaceJsonData[SpaceMembershipResponseContext.payloadKey] == nil)
        precondition(meshNetworkId == "canonical", "identity must be fixed before production importer starts")
        updateCalls += 1
        await Task.yield(); onUpdate?()
        guard applySucceeds else { return .rejected("configurationPersistenceFailed") }
        lastUploadCloudTimestamp = 42
        return .init(status: .applied, rejectionReason: nil)
    }
    @MainActor private func repairMissingServerKeys(_ remote: [String: Any]) async -> Bool { false }
    // RESTORE_METHOD
}
enum SpaceConfigurationSafety {
    enum Phase { case active, removing, retired }
    struct State { var phase: Phase; var unbindRequested: Bool? }
    static var phases: [String: State] = [:]
    static func recoveryState(_ space: SpaceData) throws -> State { phases[space.meshNetworkId] ?? .init(phase: .active) }
    static func activateImport(_ space: SpaceData) -> Bool {
        guard phases[space.meshNetworkId]?.phase != .removing else { return false }
        phases[space.meshNetworkId] = .init(phase: .active); return true
    }
    static func isBlocked(_ space: SpaceData) -> Bool { false }
    static func beginUnbind(_ space: SpaceData) -> Bool { true }
}
final class SiteData {
    struct Recycle {
        var deviceAddresses = [100], groupAddresses = [50000], sceneAddresses = [10]
        var provisionerData: [String: Any]? = nil
        var exclusionAddresses: [Exclusion]? = nil
    }
    struct Exclusion { let ivIndex: Int; let addresses: [Int] }
    var spaces: [SpaceData]
    var meshUUID = "mesh", localAddress: Int? = 1
    var plans = 0, cleanup = 0
    static var sites: [String: SiteData] = [:]
    init(_ spaces: [SpaceData]) { self.spaces = spaces }
    func getRecycleAddressData(unbindSpaces: [SpaceData], prepareOnly: Bool) async -> Recycle {
        precondition(prepareOnly); plans += 1; return .init()
    }
    static func load(siteId: String) -> SiteData? { sites[siteId] }
    func save() -> Bool { true }
    func deleteProvisionerAddress(deviceAddresses: [Int], groupAddresses: [Int], sceneAddresses: [Int]) -> Bool { cleanup += 1; return true }
}
final class MeshNetwork {
    static var loadAvailable = false
    struct Provisioner { var node: Int? = 1 }
    var localProvisioner: Provisioner? = .init()
    static func load(meshUUID: String, allData: Bool) -> MeshNetwork? { loadAvailable ? MeshNetwork() : nil }
    func remove(node: Int) {}
    func save() -> Bool { true }
}
enum API { case spaceInfo(siteId: String, spaceId: String, password: String?)
    case unbindSpaces(siteId: String, spaceIds: [String], recycleDeviceAddresses: [Int], recycleGroupAddresses: [Int], recycleSceneAddresses: [Int], exclusions: [(Int, [Int])]?, provisionerData: [String: Any]?) }
final class NetworkRequest {
    static let shared = NetworkRequest()
    var networkable = true, calls = 0
    var result: Result<[String: Any], NetworkApiError> = .success([:])
    var probeError: NetworkApiError?
    var onRequest: (() -> Void)?
    func request(_ api: API) async -> Result<[String: Any], NetworkApiError> {
        calls += 1; await Task.yield(); onRequest?()
        if case .spaceInfo = api, let probeError { return .failure(probeError) }
        return result
    }
}
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    var suspensions = 0
    func suspendForMembershipLeave(space: SpaceData) { suspensions += 1 }
}

@main struct SpaceMembershipLifecycleTests {
    @MainActor static func main() async throws {
        let store = SpaceMembershipCoordinator.store
        defer { try? FileManager.default.removeItem(at: store.root) }
        func payload(_ space: SpaceData, networkID: String = "canonical") -> [String: Any] {
            ["uuid": space.id, "netKey": ["index": 5, "testNetworkID": networkID],
             "appKey": ["boundNetworkKeyIndex": 5]]
        }

        let first = SpaceData("first"), second = SpaceData("second")
        try store.write(.init(scope: SpaceMembershipCoordinator.scope(first)))
        try store.write(.init(scope: SpaceMembershipCoordinator.scope(second)))
        precondition(try store.records(account: "account", region: "region").count == 2)
        let restarted = SpaceMembershipStore(root: store.root)
        precondition(try restarted.read(SpaceMembershipCoordinator.scope(first)) == store.read(SpaceMembershipCoordinator.scope(first)))
        precondition(!SpaceMembershipCoordinator.allowsConfiguration(first))
        SpaceConfigurationSafety.phases["canonical"] = .init(phase: .retired, unbindRequested: true)
        let restored = await first.restoreConfiguration(spaceJsonData: payload(first))
        precondition(restored.status == .applied && first.meshNetworkId == "canonical")
        MeshNetwork.loadAvailable = true
        precondition(SpaceMembershipCoordinator.allowsConfiguration(first))
        let emptyReplacement = SpaceData(first.id)
        precondition(!SpaceMembershipCoordinator.allowsConfiguration(emptyReplacement), "an old membership receipt cannot authorize a new placeholder")
        precondition(!SpaceMembershipCoordinator.allowsConfiguration(second))

        let original = try store.read(SpaceMembershipCoordinator.scope(first))!
        var changed = original; changed.generation = UUID()
        try store.replace(changed, expected: original)
        do { try store.replace(original, expected: original); preconditionFailure("stale writer accepted") } catch {}
        let oldContext = SpaceMembershipResponseContext.capture(account: "account", region: "region")
        let delayed = SpaceMembershipResponseContext.annotate(["data": payload(first)], context: oldContext)["data"] as! [String: Any]
        SpaceMembershipResponseContext.invalidate()
        let stale = await first.restoreConfiguration(spaceJsonData: delayed)
        precondition(stale.rejectionReason == "staleMembershipResponse")
        let mismatch = await first.restoreConfiguration(spaceJsonData: payload(first, networkID: "other-network"))
        precondition(mismatch.rejectionReason == "networkIdentityMismatch")

        let failed = SpaceData("failed"); failed.applySucceeds = false
        let failure = await failed.restoreConfiguration(spaceJsonData: payload(failed))
        precondition(failure.status == .rejected && failed.meshNetworkId.isEmpty)
        precondition(!SpaceMembershipCoordinator.allowsConfiguration(failed))
        precondition(SpaceData.rows[failed.id]?.meshNetworkId == "canonical", "crash must resume in canonical scope")
        let unsaved = SpaceData("unsaved"); unsaved.saveSucceeds = false
        let unsavedResult = await unsaved.restoreConfiguration(spaceJsonData: payload(unsaved))
        precondition(unsavedResult.status == .rejected)

        let request = NetworkRequest.shared
        MeshNetwork.loadAvailable = false
        let site = SiteData([second]); SiteData.sites["site"] = site
        _ = second.save()
        request.networkable = false
        try await SpaceMembershipCoordinator.queueLeave(second, site: site)
        precondition(site.plans == 0, "placeholder must never infer unused addresses")
        precondition(!SpaceMembershipCoordinator.canJoin(second))
        precondition(!SpaceMembershipCoordinator.canReceiveSite("site"))
        precondition(!SpaceMembershipCoordinator.allowsConfiguration(second))
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(second))
        precondition(request.calls == 0 && second.deleteCalls == 0)
        request.networkable = true; request.result = .failure(.noNetwork)
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(second))
        precondition(second.deleteCalls == 0 && site.cleanup == 0)
        precondition(try store.read(SpaceMembershipCoordinator.scope(second))?.phase == .unknown)
        request.result = .success(["data": ["uuid": second.id, "role": "editor"]]); second.deleteSucceeds = false
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(second))
        precondition(try store.read(SpaceMembershipCoordinator.scope(second))?.phase == .confirmed)
        let callsAfterConfirmation = request.calls
        second.deleteSucceeds = true
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(second))
        precondition(request.calls == callsAfterConfirmation, "confirmed leave must not call server again")
        precondition(try store.read(SpaceMembershipCoordinator.scope(second))?.phase == .left)
        precondition(SpaceMembershipCoordinator.canReceiveSite("site"))
        precondition(SpaceMembershipCoordinator.authorizeSiteReceipt("site"))
        precondition(try store.read(SpaceMembershipCoordinator.scope(second))?.phase == .joined)
        precondition(SpaceMembershipCoordinator.authorizeJoin(second))
        precondition(!SpaceMembershipCoordinator.allowsConfiguration(second), "rejoin needs a new complete import")

        let changedPassword = SpaceData("changed-password"); _ = changedPassword.save()
        try await SpaceMembershipCoordinator.queueLeave(changedPassword, site: site)
        request.result = .failure(.noNetwork)
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(changedPassword))
        request.probeError = .incorrectPassword; request.result = .success([:])
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(changedPassword))
        precondition(try store.read(SpaceMembershipCoordinator.scope(changedPassword))?.phase == .left)
        request.probeError = nil

        let accountChange = SpaceData("account-change"); _ = accountChange.save()
        try await SpaceMembershipCoordinator.queueLeave(accountChange, site: site)
        request.onRequest = { UserData.currentUserId = "other-account" }
        _ = await SpaceMembershipCoordinator.resumeLeave(SpaceMembershipCoordinator.scope(accountChange))
        precondition(accountChange.deleteCalls == 0)
        UserData.currentUserId = "account"; request.onRequest = nil
        print("PASS: production membership identity, retired rejoin, persistence, upload barrier, stale response, offline/unknown/confirmed leave, cleanup retry and account isolation")
    }
}
