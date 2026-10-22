// The full Schedule codec has its own production-code fixture. This harness
// isolates upload receipt and import preparation state transitions.
let jsonDecoder = JSONDecoder()
struct Schedule: Decodable {}
import Foundation
import CryptoKit

enum Permission { case owner, editor, visitor }
struct UserData {
    let name: String; let uuid: String
    static var currentUserId = "test-account", currentServerRegion = "test-region"
}
extension String {
    var localizedString: String {
        switch self {
        case "configuration_baseline_devices": return "Local: %d; cloud: %d"
        case "configuration_baseline_local_only", "configuration_baseline_cloud_only", "configuration_baseline_proxy": return "%@"
        default: return self
        }
    }
}
// NETWORK_ERROR_TYPE
final class SpaceData {
    var timedSchemaVersion = 1

    enum State: Int { case normal = 1, waitDeleted }
    enum GatewayStatus { case online, offline, notBound }
    let id: String
    var meshUUID: String { "mesh-" + id }
    var meshNetworkId = "network", siteId = "site", authorizationPassword: String? = nil
    var permission = Permission.owner, state = State.normal
    var shareCode: String?, vistorPassword: String?, owner: UserData?, editor: UserData?
    var vistorPasswordEnable = false, requiresPasswordVerification = false
    var applyDeviceAddressCount: Int?, applyGroupAddressCount: Int?
    var releaseAddress = false, disableEditorPermission = false
    var visitors: [UserData] = [], relevanceGatewayId: String?, gatewayLastOnline: Int64?
    var gatewayStatus = GatewayStatus.notBound
    var lastUpdate: Int64 = 50, lastUploadCloudTimestamp: Int64?, syncCloudError: NetworkApiError?
    var savesSucceed = true
    var onSave: (() -> Void)?
    var uploadCloud: Bool { lastUploadCloudTimestamp != nil }
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) && permission != .visitor }
    var nodes: [[String: Any]] = []
    var triggerZones: [SpaceTriggerZone] = [], triggerZonesLoadFailed = false
    var groups: [[String: Any]] = []
    var profileMergeFails = false
    var exportValues: [String: Any] = [:]
    var payload: [String: Any] {
        let result: [String: Any] = ["uuid": id, "groups": groups, "scenes": [], "schedules": [], "nodes": nodes, "updateTimestamp": lastUpdate,
         "netKey": ["key": id], "appKey": ["key": "app"]]
        return result.merging(exportValues) { _, value in value }
    }
    init(_ id: String = UUID().uuidString) { self.id = id }
    func markLocalChangePendingCloudSync() { lastUpdate += 1 }
    @discardableResult func save() -> Bool { onSave?(); return savesSucceed }
    @discardableResult func delete() -> Bool {
        SpaceConfigurationSafety.beginRemoval(self) && SpaceConfigurationSafety.archiveDeletedSpace(self)
    }
    enum Purpose { case cloudSync, localBackup, cleanupInspection }
    @MainActor func export(purpose: Purpose) async -> [String: Any]? {
        if case .cleanupInspection = purpose {
            await Task.yield()
            ProximityLightingImportPreflight.onExport?()
            return payload
        }
        return await SpaceConfigurationSafety.prepareUpload(self, payload: payload) ? payload : nil
    }
    @MainActor func export(allowsProtectedInspection: Bool) async -> [String: Any]? {
        await Task.yield()
        ProximityLightingImportPreflight.onExport?()
        return payload
    }
    @MainActor func applyNewerCloudProfiles(_ remote: [String: Any], expectedRevision: Int64) -> Bool {
        guard !profileMergeFails, lastUpdate == expectedRevision,
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]) else { return false }
        groups = remote["groups"] as! [[String: Any]]
        lastUpdate = timestamp + 1
        return true
    }
    // METADATA_METHOD
    // IMPORT_PREPARATION_METHOD
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    func configurationTransaction(_ changes: () throws -> Void) -> Bool {
        do { try changes(); return true } catch { return false }
    }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    struct Node { var network: Network?; var subNetworkId: String?; func clearSyncStateCache() {} }
    struct Network { let uuid: UUID }
    var realNodes: [Node] = []
}
final class MeshNetwork {
    let meshUUID: String
    init(_ meshUUID: String) { self.meshUUID = meshUUID }
    static func load(meshUUID: String, allData: Bool) -> MeshNetwork? { .init(meshUUID) }
}
enum SpaceKeyIntegrity {
    struct Pair { let fingerprint: String; let application: Application }
    struct Application { let index: UInt16 }
    static func pair(_ payload: [String: Any], networkID: String) -> Pair? {
        guard networkID == "network", let id = payload["uuid"] as? String,
              let net = payload["netKey"] as? [String: Any],
              let app = payload["appKey"] as? [String: Any],
              let value = net["key"] as? String, let appValue = app["key"] as? String else { return nil }
        guard value == id || value == String(repeating: "0", count: 32),
              appValue == "app" || appValue == String(repeating: "1", count: 32) else {
            return .init(fingerprint: "different-key", application: .init(index: 1))
        }
        return .init(fingerprint: id + ":app", application: .init(index: 1))
    }
    static func pair(_ network: MeshNetwork, networkID: String, applicationIndex: UInt16? = nil) -> Pair? {
        networkID == "network"
            ? .init(fingerprint: String(network.meshUUID.dropFirst(5)) + ":app", application: .init(index: 1)) : nil
    }
    static func presentServerKeysMatchLocal(_ payload: [String: Any], local: Pair) -> Bool {
        let net = payload["netKey"] as? [String: String]
        let app = payload["appKey"] as? [String: String]
        guard (net == nil) != (app == nil) else { return false }
        if let net { return net["key"] == String(local.fingerprint.dropLast(4)) }
        return app?["key"] == "app"
    }
}
enum API { case spaceInfo(siteId: String, spaceId: String, password: String?)
    case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any]) }
final class NetworkRequest {
    static let shared = NetworkRequest()
    var networkable = true
    var result: Swift.Result<[String: Any], NetworkApiError> = .failure(.noNetwork)
    var calls = 0, uploads = 0
    var lastSpaceUpload: [String: Any]?
    var responses: [Swift.Result<[String: Any], NetworkApiError>] = []
    var onRequest: (() -> Void)?
    func request(_ api: API) async -> Swift.Result<[String: Any], NetworkApiError> {
        calls += 1
        if case .spaceUpload(_, _, let payload) = api {
            uploads += 1
            lastSpaceUpload = payload
        }
        let action = onRequest; onRequest = nil; action?()
        return responses.isEmpty ? result : responses.removeFirst()
    }
}
@main struct SpaceRecoveryReceiptTests {
    @MainActor static func main() async throws {
        defer {
            try? FileManager.default.removeItem(at: SpaceConfigurationSafety.testRoot)
            SpaceConfigurationSafety.testDefaults.removePersistentDomain(forName: SpaceConfigurationSafety.suite)
        }
        try await testProfileConflictResolution()
        try await testLegacyUpgradeRetry()
        try await testLegacyUpgradeRecovery()
        try await testLegacyTimedBaselineBackfill()
        try await testDefaultedTimedImport()
        try await testStaleTimedImport()
        try await testStaleTimedCloudRemoval()
        try await testFirstUploadMembershipRecovery()
        try await testLegacyUninitializedReceiptRecovery()
        try await testEmptyZoneImportGate()
        try await testUnusedTaskLevelReadback()
        try testHDBV2ImportFinalization()
        precondition(NetworkApiError(code: -2002) == .configurationUploadUnconfirmed)
        precondition(NetworkApiError(code: -2003) == .configurationExportInvalid)
        precondition(NetworkApiError.configurationUploadUnconfirmed.localizedDescription == "configuration_upload_unconfirmed")
        let request = NetworkRequest.shared
        func remote(_ space: SpaceData) { request.result = .success(["data": space.payload]) }
        func addReceipt(_ space: SpaceData) {
            precondition(SpaceConfigurationSafety.updateDeletionJournal(space) {
                $0.entries.append(.init(id: UUID(), nodeUUID: "device", primaryAddress: 2,
                    elementAddresses: [2, 3], macAddress: nil, productId: nil,
                    stage: .cleaned, completedTimestamp: 50))
            })
        }
        let a = SpaceData("A"), b = SpaceData("B")
        a.applyRemoteSpaceMetadata(["uuid": "B", "role": "visitor"])
        precondition(a.permission == .owner)
        addReceipt(a)
        let context = SpaceConfigurationSafety.prepareSubmission(a, payload: a.payload, siteCreationTimestamp: 45)!
        let initialState = try SpaceConfigurationSafety.recoveryState(a)
        precondition(initialState.siteCreationTimestamp == 45)
        precondition(SpaceConfigurationSafety.markSubmissionAccepted(context, space: a))
        request.result = .failure(.noNetwork)
        let callsBeforeAccepted = request.calls
        let offline = await SpaceConfigurationSafety.resumeUpload(a)
        if case .success = offline { preconditionFailure("accepted upload requires Key readback") }
        precondition(request.calls == callsBeforeAccepted + 1 && SpaceConfigurationSafety.hasPendingUpload(a))
        remote(a)
        if case .failure = await SpaceConfigurationSafety.resumeUpload(a) { preconditionFailure("complete readback must confirm") }
        precondition(!SpaceConfigurationSafety.hasPendingUpload(a) && !SpaceConfigurationSafety.preservesLocalChanges(a))
        precondition(SpaceConfigurationSafety.testMigrated(a) && request.uploads == 0)
        a.lastUpdate = 51
        let nextAdd = await SpaceConfigurationSafety.prepareUpload(a, payload: a.payload)
        precondition(nextAdd, "first upload must establish a baseline before the next addition")

        // Failed receipt write must retain a durable accepted submission.
        addReceipt(b)
        let bContext = SpaceConfigurationSafety.prepareSubmission(b, payload: b.payload)!
        precondition(SpaceConfigurationSafety.markSubmissionAccepted(bContext, space: b))
        let journalURL = try SpaceConfigurationSafety.testDirectory(b).appendingPathComponent("device-deletions.json")
        let journalData = try Data(contentsOf: journalURL)
        try FileManager.default.removeItem(at: journalURL)
        try FileManager.default.createDirectory(at: journalURL, withIntermediateDirectories: false)
        remote(b)
        let failedWrite = await SpaceConfigurationSafety.resumeUpload(b)
        if case .success = failedWrite { preconditionFailure("receipt write failure cannot report success") }
        precondition(b.lastUploadCloudTimestamp == nil && SpaceConfigurationSafety.hasPendingUpload(b))
        try FileManager.default.removeItem(at: journalURL)
        try journalData.write(to: journalURL)
        b.savesSucceed = false
        let failedSave = await SpaceConfigurationSafety.resumeUpload(b)
        if case .success = failedSave { preconditionFailure("DB save failure cannot report success") }
        precondition(b.lastUploadCloudTimestamp == nil)
        b.savesSucceed = true
        let callsBeforeRetry = request.calls
        let saved = await SpaceConfigurationSafety.resumeUpload(b)
        if case .failure = saved { preconditionFailure("local confirmation must be retryable") }
        precondition(request.calls == callsBeforeRetry && b.lastUploadCloudTimestamp == 50)

        // A later local edit survives completion of the older submitted generation.
        let c = SpaceData("C")
        addReceipt(c)
        let cContext = SpaceConfigurationSafety.prepareSubmission(c, payload: c.payload)!
        let submitted = c.payload
        c.lastUpdate = 60
        _ = SpaceConfigurationSafety.updateDeletionJournal(c) {
            $0.entries.append(.init(id: UUID(), nodeUUID: "new-delete", primaryAddress: 8,
                elementAddresses: [8], macAddress: nil, productId: nil, stage: .cleaned, completedTimestamp: 60))
        }
        precondition(SpaceConfigurationSafety.markSubmissionAccepted(cContext, space: c))
        request.result = .success(["data": submitted])
        _ = await SpaceConfigurationSafety.resumeUpload(c)
        precondition(c.lastUploadCloudTimestamp == 50 && c.needUploadCloud)
        let newerJournal = try SpaceConfigurationSafety.deletionJournal(c)
        precondition(newerJournal.entries.count == 1)

        let d = SpaceData("D")
        addReceipt(d)
        let dContext = SpaceConfigurationSafety.prepareSubmission(d, payload: d.payload)!
        d.applyRemoteSpaceMetadata(["uuid": "D", "role": "visitor", "visitProtected": true,
            "userEvents": ["VisitorPasswdChanged"]])
        precondition(d.permission == .visitor && d.requiresPasswordVerification)
        precondition(!SpaceConfigurationSafety.preservesLocalChanges(d))
        precondition(!SpaceConfigurationSafety.isCurrent(dContext, space: d))
        precondition(!SpaceConfigurationSafety.markSubmissionAccepted(dContext, space: d))
        precondition(!SpaceConfigurationSafety.canAutomaticallyUpload(d))
        precondition(SpaceConfigurationSafety.requiresAuthorityImport(d), "Visitor must import remote data even if the local version is newer")

        let e = SpaceData("E")
        addReceipt(e)
        SpaceConfigurationSafety.handleAuthorityError(.spacePasswordOverdue, space: e)
        precondition(e.requiresPasswordVerification && SpaceConfigurationSafety.preservesLocalChanges(e))
        precondition(!SpaceConfigurationSafety.canAutomaticallyUpload(e))
        SpaceConfigurationSafety.handleAuthorityError(.noSpacePermission, space: e)
        precondition(e.state == .waitDeleted && !SpaceConfigurationSafety.preservesLocalChanges(e))

        let f = SpaceData("F")
        addReceipt(f)
        let old = try SpaceConfigurationSafety.recoveryState(f)
        precondition(SpaceConfigurationSafety.beginRemoval(f))
        precondition(!SpaceConfigurationSafety.activateImport(f), "incomplete removal must not race re-import")
        SpaceConfigurationSafety.failArchiveMove = true
        precondition(SpaceConfigurationSafety.archiveDeletedSpace(f))
        precondition(SpaceConfigurationSafety.activateImport(f))
        precondition(!SpaceConfigurationSafety.isCurrent(old, space: f))
        precondition(!SpaceConfigurationSafety.preservesLocalChanges(f))
        SpaceConfigurationSafety.failArchiveMove = false
        SpaceConfigurationSafety.retryArchiveMoves(f)
        let archivedState = try SpaceConfigurationSafety.recoveryState(f)
        precondition(archivedState.pendingArchives?.isEmpty == true)
        let archiveSuccess = SpaceData("archive-success")
        addReceipt(archiveSuccess)
        precondition(archiveSuccess.delete())
        let files = try FileManager.default.contentsOfDirectory(at: SpaceConfigurationSafety.testRoot, includingPropertiesForKeys: nil)
        precondition(files.contains { $0.lastPathComponent.hasPrefix("archived-") })

        let g = SpaceData("G")
        let gContext = SpaceConfigurationSafety.prepareSubmission(g, payload: g.payload)!
        precondition(!SpaceConfigurationSafety.finishAcceptedSubmission(gContext, space: g))
        var stale = g.payload
        stale["deviceCount"] = 0
        stale["nodes"] = [["uuid": "old-device", "unicastAddress": "0002"]]
        request.result = .success(["data": stale])
        let beforeMismatch = request.calls
        let mismatch = await SpaceConfigurationSafety.resumeUpload(g)
        if case .success = mismatch { preconditionFailure("stale members cannot confirm deletion") }
        precondition(request.calls - beforeMismatch == 3 && SpaceConfigurationSafety.hasPendingUpload(g))
        precondition(SpaceConfigurationSafety.isBlocked(g))
        remote(g)
        _ = await SpaceConfigurationSafety.resumeUpload(g)
        precondition(!SpaceConfigurationSafety.isBlocked(g))

        let h = SpaceData("H")
        let hContext = SpaceConfigurationSafety.prepareSubmission(h, payload: h.payload)!
        remote(h)
        request.onRequest = { _ = h.delete(); _ = SpaceConfigurationSafety.activateImport(h) }
        let late = await SpaceConfigurationSafety.resumeUpload(h)
        if case .success = late { preconditionFailure("late callbacks cannot confirm a new lifecycle") }
        precondition(!SpaceConfigurationSafety.isCurrent(hContext, space: h))
        precondition(h.lastUploadCloudTimestamp == nil)

        // A transient GET error during upgrade is not a permanent topology block.
        let upgrade = SpaceData("upgrade")
        upgrade.lastUploadCloudTimestamp = 49
        request.result = .failure(.requestTimeout)
        let timeout = await SpaceConfigurationSafety.prepareUpload(upgrade, payload: upgrade.payload)
        precondition(!timeout && !SpaceConfigurationSafety.isBlocked(upgrade))
        remote(upgrade)
        let retryUpgrade = await SpaceConfigurationSafety.prepareUpload(upgrade, payload: upgrade.payload)
        precondition(retryUpgrade)

        // Password reauthorization cannot replay a stale local edit over a changed cloud.
        SpaceConfigurationSafety.handleAuthorityError(.spacePasswordOverdue, space: a)
        a.requiresPasswordVerification = false
        var changedAuthority = a.payload
        changedAuthority["nodes"] = [["uuid": "another-phone", "unicastAddress": "0010"]]
        SpaceConfigurationSafety.reconcileAuthority(a, remote: changedAuthority)
        precondition(!SpaceConfigurationSafety.canAutomaticallyUpload(a))
        precondition(SpaceConfigurationSafety.requiresConfigurationReview(a))

        try await testCloudSiteConfirmation()
        try await testDirectUploadConfirmation()
        try await testSceneTargetReadback()
        try await testEmptySceneTargetReadback()
        try await testEmptySceneSchedulesAddedDuringUpload()
        try await testEmptyZoneReadback()
        try await testSchedulerModelReadback()
        try await testEmptyGroupAddressRecovery()
        try await testSiteHandoffReadback()
        try await testCloudMembershipRemoval()
        try await testImportPreparation()
        try await testUnuploadedTimedMigration()
        try await testParseRejectionRecovery()
        try await testOlderCloudBaseline()
        try testReferenceCleanupReceipts()
        try testProximityAllImportRecovery()
        try testProtectionGenerationWriters()

        // Account changes invalidate pending callbacks before looking up another store.
        let accountContext = try SpaceConfigurationSafety.recoveryState(b)
        UserData.currentUserId = "another-account"
        precondition(!SpaceConfigurationSafety.isCurrent(accountContext, space: b))
        UserData.currentUserId = "test-account"
        print("PASS: production direct acceptance, unknown-outcome recovery, first-upload baseline, persistence failures, versions, authority and lifecycle isolation")
    }

    @MainActor static func testProtectionGenerationWriters() throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("protection-generation")
        var state = try S.recoveryState(space)
        let request = SpaceProtectionReadRequest(scope: .init(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion), meshUUID: space.meshUUID,
            networkID: space.meshNetworkId), root: S.testRoot, defaults: S.testDefaults)
        let original = request.read()
        precondition(!original.isBlocked)
        S.failStateWrite = true
        do { try S.testSaveState(state, space: space); preconditionFailure("expected failed write") } catch {}
        S.failStateWrite = false
        precondition(!original.isCurrent && SpaceProtectionReadGeneration.current != nil)
        let beforeAuthority = request.read()
        state.authority = .readOnly
        try S.testSaveState(state, space: space)
        precondition(!beforeAuthority.isCurrent && request.read().authority == .readOnly)
        let beforeJournal = request.read()
        precondition(S.updateDeletionJournal(space) {
            $0.entries.append(.init(id: UUID(), nodeUUID: "node", primaryAddress: 1,
                elementAddresses: [1], macAddress: nil, productId: nil))
        })
        precondition(!beforeJournal.isCurrent && request.read().pendingDeletion)
        let beforeBlock = request.read()
        S.block(space, reason: "generation-test")
        precondition(!beforeBlock.isCurrent && request.read().blockedReason == "generation-test")
        #if DEBUG
        print("PASS: production save failure, authority, deletion journal and blocked writer invalidate real snapshots")
        #endif
    }

    /// A complete, synthetic legacy Space. No customer identities or keys.
    static func legacyUpgradePayload(_ space: SpaceData, modern: Bool) -> [String: Any] {
        var payload = space.payload
        var profile: [String: Any] = ["id": "legacy-profile", "type": 7,
            "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 100,
            "vacantLevel": 50, "standbyLevel": 0, "taskLevel": 100,
            "timeT1": 2, "timeT2": 1200, "timeT3": 2, "timeT4": 600, "timeT5": 2,
            "manualOverrideTimeout": 4294967295, "powerUpState": 255, "proximityLightingNumber": 1]
        if modern { profile["calibrationMode"] = "none"; profile["targetNightBrightness"] = 50 }
        payload["groups"] = [["address": "C008", "profile": profile,
            "proximityLightingPath": ["paths": [["items": [554, 557]]], "zones": [["addresses": [554, 557]]]]]]
        payload["nodes"] = [554, 557].map { address -> [String: Any] in
            ["uuid": String(format: "00000000-0000-0000-0000-%012d", address),
             "unicastAddress": String(format: "%04X", address), "groupAddress": "C008", "groupState": 1,
             "deviceKey": String(repeating: "A", count: 32),
             "elements": [["index": 0, "models": [["modelId": "0A780001", "subscribe": ["C008"]]]]]]
        }
        payload["scenes"] = [[String: Any]](); payload["schedules"] = [[String: Any]]()
        payload["switches"] = [[String: Any]](); payload["emergencyFireControllers"] = [[String: Any]]()
        payload["spaceData"] = modern ? ["proximityLightingSchemaVersion": 1, "triggerZones": []] : [:]
        payload["netKey"] = ["index": 1, "key": String(repeating: "0", count: 32)]
        payload["appKey"] = ["index": 1, "boundNetKey": 1, "key": String(repeating: "1", count: 32)]
        return payload
    }

    @MainActor static func testLegacyUpgradeRetry() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        let space = SpaceData("legacy-upgrade-retry")
        space.lastUploadCloudTimestamp = space.lastUpdate
        let remote = legacyUpgradePayload(space, modern: false)
        let local = legacyUpgradePayload(space, modern: true)
        precondition(SpaceSyncCleanupPolicy.baseline(remote) == SpaceSyncCleanupPolicy.baseline(local))
        request.result = .failure(.noNetwork)
        let failed = await S.verifySyncCleanupBaseline(space, local: local)
        precondition(!failed && !S.isBlocked(space) && space.syncCloudError == .noNetwork)
        request.result = .success(["data": remote])
        let retry = await S.prepareUpload(space, payload: local)
        precondition(retry && !S.isBlocked(space), "known legacy defaults must not create a permanent upgrade block")
        precondition(S.testMigrated(space))
        // A submitted snapshot still requires exact readback, including new fields.
        let strictReadback = await S.verifyUploadedConfiguration(space, payload: local)
        precondition(!strictReadback, "upgrade compatibility must never weaken submission readback")
        let conflicting = SpaceData("legacy-real-conflict"); conflicting.lastUploadCloudTimestamp = conflicting.lastUpdate
        var changed = legacyUpgradePayload(conflicting, modern: false)
        var groups = changed["groups"] as! [[String: Any]]
        var profile = groups[0]["profile"] as! [String: Any]; profile["timeT2"] = 42
        groups[0]["profile"] = profile; changed["groups"] = groups
        request.result = .success(["data": changed])
        let conflict = await S.verifySyncCleanupBaseline(conflicting, local: legacyUpgradePayload(conflicting, modern: true))
        precondition(!conflict && S.isBlocked(conflicting) && conflicting.syncCloudError == .configurationReviewRequired)
        let importing = SpaceData("legacy-entry-baseline"); importing.lastUploadCloudTimestamp = importing.lastUpdate
        _ = try S.recoveryState(importing)
        S.failStateWrite = true
        S.verifyUpgradeBaseline(importing, local: legacyUpgradePayload(importing, modern: true),
                                remote: legacyUpgradePayload(importing, modern: false))
        precondition(!S.testMigrated(importing), "failed state persistence must not establish a migration receipt")
        S.failStateWrite = false
        S.verifyUpgradeBaseline(importing, local: legacyUpgradePayload(importing, modern: true),
                                remote: legacyUpgradePayload(importing, modern: false))
        precondition(S.testMigrated(importing))
        print("PASS: failed upgrade precheck retries with legacy compatibility; submission readback stays strict")
    }

    @MainActor static func testLegacyUpgradeRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for reason in ["upgradeBaselineNeedsImport", "legacySpaceZoneDeletionNeedsReview"] {
            func localPayload(_ space: SpaceData) -> [String: Any] {
                var payload = legacyUpgradePayload(space, modern: true)
                payload["spaceData"] = ["proximityLightingSchemaVersion": 1,
                    "triggerZones": Array(repeating: ["items": [[String: Any]]()], count: 5)]
                return payload
            }
            func blocked() -> SpaceData {
                let space = SpaceData()
                space.lastUploadCloudTimestamp = space.lastUpdate
                S.block(space, reason: reason)
                space.syncCloudError = .configurationExportInvalid
                return space
            }
            for role in [Permission.owner, .editor] {
                for emptySpace in [false, true] {
                    let space = blocked(); space.permission = role
                    var local = localPayload(space), remote = legacyUpgradePayload(space, modern: false)
                    if emptySpace {
                        local["nodes"] = [[String: Any]](); remote["nodes"] = [[String: Any]]()
                        local["groups"] = [[String: Any]](); remote["groups"] = [[String: Any]]()
                    }
                    let original = try JSONSerialization.data(withJSONObject: local, options: [.sortedKeys])
                    request.result = .success(["data": remote])
                    var reads = 0
                    let result = await S.recoverUpgradeBaselineIfNeeded(space) { reads += 1; return local }
                    precondition(result && reads == 2 && !S.isBlocked(space) && S.testMigrated(space) && space.syncCloudError == nil)
                    let calls = request.calls
                    let repeated = await S.recoverUpgradeBaselineIfNeeded(space) { preconditionFailure("already recovered") }
                    precondition(repeated && request.calls == calls)
                    precondition(!S.needsUpgradeBaseline(space), "migration receipt survives a new recovery-state read")
                    let snapshot = try Data(contentsOf: S.testDirectory(space).appendingPathComponent("last-complete-export.json"))
                    precondition(snapshot == original && space.lastUploadCloudTimestamp == space.lastUpdate,
                                 "Recovery must preserve all empty slots and the confirmed timestamp")
                    let uploadable = await S.prepareUpload(space, payload: local)
                    precondition(uploadable, "Recovered empty zones must pass the downstream upload gate")
                }
            }
            // Even if timestamps match, real configuration/identity differences stay protected.
            for field in ["profile", "members", "path", "zone", "netKey", "appKey", "deviceKey", "missingDeviceKey", "scene", "schedule", "switch", "version", "invalid"] {
                let space = blocked(), local = localPayload(space)
                var remote = legacyUpgradePayload(space, modern: false)
                var groups = remote["groups"] as! [[String: Any]]
                switch field {
                case "profile":
                    var profile = groups[0]["profile"] as! [String: Any]; profile["timeT2"] = 1201; groups[0]["profile"] = profile
                case "members": remote["nodes"] = Array((remote["nodes"] as! [[String: Any]]).prefix(1))
                case "path": groups[0]["proximityLightingPath"] = ["paths": [["items": [557, 554]]], "zones": [["addresses": [554, 557]]]]
                case "zone": remote["spaceData"] = ["triggerZones": [["items": [["groupAddress": 49160, "deviceAddress": 554]]]]]
                case "netKey": remote["netKey"] = ["index": 1, "key": String(repeating: "2", count: 32)]
                case "appKey": remote["appKey"] = ["index": 1, "boundNetKey": 1, "key": String(repeating: "2", count: 32)]
                case "deviceKey", "missingDeviceKey":
                    var nodes = remote["nodes"] as! [[String: Any]]
                    nodes[0]["deviceKey"] = field == "deviceKey" ? String(repeating: "B", count: 32) : nil
                    remote["nodes"] = nodes
                case "scene": remote["scenes"] = [["number": "0001", "name": "changed", "addresses": [554]]]
                case "schedule": remote["schedules"] = [["id": 1, "hour": 12]]
                case "switch": remote["switches"] = [["id": "changed"]]
                case "version": remote["updateTimestamp"] = space.lastUpdate + 1
                default: remote["spaceData"] = "invalid"
                }
                remote["groups"] = groups
                request.result = .success(["data": remote])
                let result = await S.recoverUpgradeBaselineIfNeeded(space) { local }
                precondition(!result && S.isBlocked(space) && !S.testMigrated(space), "must preserve \(field) difference")
            }
            for condition in ["visitor", "password", "localWrite", "import", "cleanup", "deletion", "submission", "authority", "unreadableZones", "unbind", "otherReason"] {
                let space = SpaceData(); space.lastUploadCloudTimestamp = space.lastUpdate
                let local = localPayload(space)
                if condition == "submission" { precondition(S.prepareSubmission(space, payload: local) != nil) }
                S.block(space, reason: condition == "otherReason" ? "invalidRemoteTopology" : reason)
                switch condition {
                case "visitor": space.permission = .visitor
                case "password": space.requiresPasswordVerification = true
                case "localWrite": space.lastUpdate += 1
                case "import": precondition(S.beginImport(space, payload: local))
                case "cleanup": try Data("{}".utf8).write(to: S.testDirectory(space).appendingPathComponent("pending-reference-cleanup.json"))
                case "deletion": precondition(S.updateDeletionJournal(space) {
                    $0.entries.append(.init(id: UUID(), nodeUUID: "deleted-node", primaryAddress: 5, elementAddresses: [5], macAddress: nil, productId: nil))
                })
                case "authority": var state = try S.recoveryState(space); state.requiresRemoteImport = true; try S.testSaveState(state, space: space)
                case "unreadableZones": space.triggerZonesLoadFailed = true
                case "unbind": var state = try S.recoveryState(space); state.unbindRequested = true; try S.testSaveState(state, space: space)
                default: break
                }
                let calls = request.calls
                let result = await S.recoverUpgradeBaselineIfNeeded(space) { preconditionFailure("ineligible local read") }
                precondition(result == (condition == "otherReason") && S.isBlocked(space) && !S.testMigrated(space) && request.calls == calls)
            }
            for failure in ["network", "stateSave", "spaceSave", "firstRead", "secondRead", "sameSecondEdit", "versionChange", "accountChange", "permissionChange", "cancel"] {
                let space = blocked(); var local = localPayload(space)
                let remote = legacyUpgradePayload(space, modern: false)
                _ = try S.recoveryState(space)
                request.result = failure == "network" ? .failure(.noNetwork) : .success(["data": remote])
                S.failStateWrite = failure == "stateSave"
                space.savesSucceed = failure != "spaceSave"
                request.onRequest = {
                    switch failure {
                    case "sameSecondEdit": local["spaceName"] = "changed-during-await"
                    case "versionChange": space.lastUpdate += 1
                    case "accountChange": UserData.currentUserId = "different-account"
                    case "permissionChange": space.permission = .visitor
                    case "cancel": withUnsafeCurrentTask { $0?.cancel() }
                    default: break
                    }
                }
                var reads = 0
                let task = Task { @MainActor in
                    await S.recoverUpgradeBaselineIfNeeded(space) {
                        reads += 1
                        if failure == "firstRead" || (failure == "secondRead" && reads == 2) { return nil }
                        return local
                    }
                }
                let result = await task.value
                UserData.currentUserId = "test-account"; request.onRequest = nil; S.failStateWrite = false
                precondition(!result && S.isBlocked(space) && !S.testMigrated(space), "must retain recovery on \(failure)")
            }
            let retry = blocked(), local = localPayload(retry)
            request.result = .failure(.noNetwork)
            let failed = await S.recoverUpgradeBaselineIfNeeded(retry) { local }
            precondition(!failed && S.isBlocked(retry))
            request.result = .success(["data": legacyUpgradePayload(retry, modern: false)])
            let succeeded = await S.recoverUpgradeBaselineIfNeeded(retry) { local }
            precondition(succeeded && !S.isBlocked(retry) && retry.syncCloudError == nil)
        }
        // A real member cannot be auto-cleared under the historical deletion reason,
        // even if both current snapshots happen to contain the same member.
        let populated = SpaceData(); populated.lastUploadCloudTimestamp = populated.lastUpdate
        S.block(populated, reason: "legacySpaceZoneDeletionNeedsReview")
        var same = legacyUpgradePayload(populated, modern: true)
        same["spaceData"] = ["proximityLightingSchemaVersion": 1,
            "triggerZones": [["items": [["groupAddress": 49160, "deviceAddress": 554]]]]]
        request.result = .success(["data": same])
        let calls = request.calls
        let rejected = await S.recoverUpgradeBaselineIfNeeded(populated) { same }
        precondition(!rejected && S.isBlocked(populated) && request.calls == calls)
        for (error, key) in [(NetworkApiError.configurationUnavailable, "configuration_sync_unavailable"),
                             (.configurationReviewRequired, "configuration_review_message"),
                             (.configurationExportInvalid, "proximity_lighting_export_invalid")] {
            precondition(NetworkApiError(code: error.code) == error && error.localizedDescription == key)
        }
        print("PASS: legacy block recovery; full valid inputs, roles, strict conflicts, pending operations, repeated reads, persistence, cancellation and error round-trip")
    }

    @MainActor static func testEmptyZoneReadback() async throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("empty-zone-readback")
        let empty: [String: Any] = ["items": [[String: Any]]()]
        var local = space.payload
        local["spaceData"] = ["proximityLightingSchemaVersion": 1, "triggerZones": Array(repeating: empty, count: 5)]
        guard let context = S.prepareSubmission(space, payload: local) else { preconditionFailure("Empty zones must submit") }
        precondition(S.markSubmissionAccepted(context, space: space))
        let populated: [String: Any] = ["items": [["groupAddress": 49160, "deviceAddress": 554]]]
        for zones in [nil, [], [empty], Array(repeating: populated, count: 5)] as [[[String: Any]]?] {
            var remote = local
            remote["spaceData"] = zones.map { ["proximityLightingSchemaVersion": 1, "triggerZones": $0] } ?? [:]
            NetworkRequest.shared.result = .success(["data": remote])
            let direct = await S.verifyUploadedConfiguration(space, payload: local)
            precondition(!direct)
            if case .success = await S.resumeUpload(space) { preconditionFailure("Lost/changed slots cannot confirm the submission") }
            precondition(S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == nil)
        }
        NetworkRequest.shared.result = .success(["data": local])
        let direct = await S.verifyUploadedConfiguration(space, payload: local)
        precondition(direct)
        if case .failure = await S.resumeUpload(space) { preconditionFailure("Exact empty slots must confirm on retry") }
        precondition(!S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == space.lastUpdate)
        print("PASS: empty Zone submission readback remains strict and retries after matching all slots")
    }

    @MainActor static func testDirectUploadConfirmation() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for variant in ["complete", "missing-net", "different-app"] {
            let space = SpaceData("accepted-" + variant)
            let context = S.prepareSubmission(space, payload: space.payload)!
            precondition(S.markSubmissionAccepted(context, space: space))
            precondition(!S.finishAcceptedSubmission(context, space: space))
            var remote = space.payload
            if variant == "missing-net" { remote.removeValue(forKey: "netKey") }
            if variant == "different-app" { remote["appKey"] = ["key": "different"] }
            request.result = .success(["data": remote])
            let result = await S.resumeUpload(space)
            if variant == "complete" {
                if case .failure = result { preconditionFailure("complete Key readback must confirm") }
                precondition(!S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == 50)
            } else {
                if case .success = result { preconditionFailure("missing or different Key must retain receipt") }
                precondition(S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == nil)
            }
        }
        let serverMissing = SpaceData("server-missing-single-key")
        let missingContext = S.prepareSubmission(serverMissing, payload: serverMissing.payload)!
        precondition(S.markSubmissionAccepted(missingContext, space: serverMissing))
        var partial = serverMissing.payload
        partial.removeValue(forKey: "netKey")
        partial["role"] = "owner"
        request.result = .success(["data": partial])
        if case .failure = await S.resumeUpload(serverMissing) {
            preconditionFailure("confirmed business data with one missing server Key may retry full upload")
        }
        precondition(!S.hasPendingUpload(serverMissing) && serverMissing.lastUploadCloudTimestamp == nil
                     && serverMissing.needUploadCloud)
        for succeeds in [false, true] {
            let space = SpaceData("unbind-direct-\(succeeds)")
            request.result = succeeds ? .success([:]) : .failure(.requestTimeout)
            if succeeds { request.responses = [.success([:]), .success(["data": space.payload])] }
            let calls = request.calls, uploads = request.uploads
            // A new edit arrives while the submitted version is in flight.
            request.onRequest = { space.lastUpdate = 60 }
            let result = await S.uploadBeforeUnbind(space)
            if succeeds {
                if case .failure = result { preconditionFailure("successful upload needs a complete GET") }
                precondition(space.lastUploadCloudTimestamp == 50 && !S.hasPendingUpload(space))
            } else {
                if case .success = result { preconditionFailure("timeout must not confirm") }
                precondition(space.lastUploadCloudTimestamp == nil && S.hasPendingUpload(space))
            }
            precondition(space.needUploadCloud)
            precondition(request.calls == calls + (succeeds ? 2 : 1) && request.uploads == uploads + 1)
        }
        // Older accepted snapshots never move the confirmed version backwards.
        let monotonic = SpaceData("accepted-monotonic")
        let context = S.prepareSubmission(monotonic, payload: monotonic.payload)!
        precondition(S.markSubmissionAccepted(context, space: monotonic))
        monotonic.lastUploadCloudTimestamp = 80
        request.result = .success(["data": monotonic.payload])
        if case .failure = await S.resumeUpload(monotonic) { preconditionFailure("valid readback must keep newer timestamp") }
        precondition(monotonic.lastUploadCloudTimestamp == 80)

        // One failed local confirmation must not undo another accepted Space.
        let first = SpaceData("partial-first"), second = SpaceData("partial-second")
        let firstContext = S.prepareSubmission(first, payload: first.payload)!
        let secondContext = S.prepareSubmission(second, payload: second.payload)!
        precondition(S.markSubmissionAccepted(firstContext, space: first))
        precondition(S.markSubmissionAccepted(secondContext, space: second))
        request.result = .success(["data": first.payload])
        if case .failure = await S.resumeUpload(first) { preconditionFailure("first Space must confirm") }
        second.savesSucceed = false
        precondition(!S.finishAcceptedSubmission(secondContext, space: second))
        precondition(!S.hasPendingUpload(first) && S.hasPendingUpload(second))
        second.savesSucceed = true
        let persisted = try S.recoveryState(second)
        precondition(persisted.submission?.phase == .accepted)
        request.result = .success(["data": second.payload])
        if case .failure = await S.resumeUpload(second) { preconditionFailure("second Space must confirm independently") }
        precondition(!S.hasPendingUpload(second))
        print("PASS: accepted uploads verify Key and configuration, preserve receipts on mismatch, and keep newer edits")
    }

    @MainActor static func testUnusedTaskLevelReadback() async throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("unused-task-level-readback")
        var submitted = space.payload
        let scenes: [[String: Any]] = ["FF00", "FF01", "FF02"].map { number in
            ["number": number, "name": number, "occupancyLevel": 100, "vacantLevel": 50,
             "standbyLevel": 0, "taskLevel": 100, "timeT1": 2, "timeT2": 30,
             "timeT3": 2, "timeT4": 60, "timeT5": 2]
        }
        let profile: [String: Any] = ["id": "web-photocell", "type": 8,
            "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 100, "vacantLevel": 50,
            "standbyLevel": 0, "taskLevel": 100, "timeT1": 2, "timeT2": 30, "timeT3": 2,
            "timeT4": 60, "timeT5": 2, "manualOverrideTimeout": 60, "powerUpState": 0,
            "proximityLightingNumber": 2, "scenes": scenes,
            "day": ["id": 1, "startsBelowLux": 70, "sceneNumber": "FF02"],
            "night": ["id": 0, "startsBelowLux": 30, "sceneNumber": "FF01"]]
        submitted["groups"] = [["address": "C002", "profile": profile]]
        let context = S.prepareSubmission(space, payload: submitted)!
        precondition(S.markSubmissionAccepted(context, space: space))
        var missing = profile; missing.removeValue(forKey: "taskLevel")
        missing["scenes"] = scenes.map { scene in
            var result = scene; result.removeValue(forKey: "taskLevel"); return result
        }
        var remote = submitted
        var invalid = missing; invalid["taskLevel"] = NSNull()
        remote["groups"] = [["address": "C002", "profile": invalid]]
        NetworkRequest.shared.result = .success(["data": remote])
        if case .success = await S.resumeUpload(space) {
            preconditionFailure("An explicit malformed taskLevel must retain the pending receipt")
        }
        precondition(S.hasPendingUpload(space))
        remote["groups"] = [["address": "C002", "profile": missing]]
        NetworkRequest.shared.result = .success(["data": remote])
        let matches = await S.verifyUploadedConfiguration(space, payload: submitted)
        precondition(matches, "Missing unused defaults must confirm direct upload readback")
        if case .failure = await S.resumeUpload(space) {
            preconditionFailure("A complete retry with missing unused defaults must finish the receipt")
        }
        precondition(!S.hasPendingUpload(space) && !S.isBlocked(space))
        print("PASS: malformed taskLevel retains receipt; missing unused defaults confirm direct readback and retry")

        let blocked = SpaceData("unused-task-level-import")
        var importedPayload = blocked.payload
        importedPayload["groups"] = [["address": "C002", "profile": missing]]
        S.block(blocked, reason: "invalidRemoteProfile:C002:invalidProfileField:taskLevel")
        precondition(S.isBlocked(blocked) && !S.hasPendingImport(blocked))
        precondition(SpaceConfigurationIntegrityPolicy.profilesIssue(in: importedPayload) == nil)
        let revision = blocked.lastUpdate
        precondition(S.beginImport(blocked, payload: importedPayload))
        precondition(S.hasPendingImport(blocked))
        precondition(S.finishImport(blocked))
        precondition(!S.isBlocked(blocked) && !S.hasPendingImport(blocked))
        precondition(blocked.lastUpdate == revision && !S.preservesLocalChanges(blocked),
                     "Default compatibility must not create a local repair upload")
        let baseline = try S.recoveryState(blocked).authorizationBaseline
        importedPayload["groups"] = [["address": "C002", "profile": profile]]
        precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(
            baseline, SpaceConfigurationIntegrityPolicy.configurationData(importedPayload)))
        print("PASS: existing taskLevel block clears after import finalization without a repair upload")
    }

    @MainActor static func testHDBV2ImportFinalization() throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("hdb-v2-import")
        var payload = space.payload
        payload["spaceData"] = ["hdb": ["schemaVersion": 2,
            "lightingZones": [[String: Any]](), "devices": [[String: Any]]()]]
        let config = try HDBLightingZonePolicy.decode(payload: payload)!
        S.block(space, reason: "invalidStoredHDB")
        precondition(S.isBlocked(space))
        precondition(S.beginImport(space, payload: payload))
        precondition(S.finishImport(space, validatedTopology: true))
        precondition(!S.isBlocked(space) && !S.hasPendingImport(space))
        let baseline = try S.recoveryState(space).authorizationBaseline
        payload["spaceData"] = ["hdb": try HDBLightingZonePolicy.json(config)]
        precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(
            baseline, SpaceConfigurationIntegrityPolicy.configurationData(payload)))
        precondition(!S.preservesLocalChanges(space), "valid v2 recovery must not create pending local edits")
        print("PASS: v2 HDB import clears invalidStoredHDB and records a comparable baseline")
    }

    @MainActor static func testSceneTargetReadback() async throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("scene-target-readback")
        var submitted = space.payload
        submitted["scenes"] = [["number": "0006", "name": "All off"]]
        submitted["schedules"] = [["name": "Schedule 1", "enabled": true, "action": 2, "hour": 8, "minute": 0, "dayOfWeek": 127, "fadeTime": 0, "id": 0, "selectTarget": 2, "sceneAddress": "0006"]]
        let context = S.prepareSubmission(space, payload: submitted)!
        precondition(context.submission?.scheduleTargets != nil)
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as! [String: Any]
        var legacySubmission = legacy["submission"] as! [String: Any]
        legacySubmission.removeValue(forKey: "scheduleTargets")
        legacy["submission"] = legacySubmission
        let legacyData = try JSONSerialization.data(withJSONObject: legacy)
        let decodedLegacy = try JSONDecoder().decode(SpaceRecoveryState.self, from: legacyData)
        precondition(decodedLegacy.submission?.scheduleTargets == nil,
                     "Old receipts must remain decodable")
        precondition(S.markSubmissionAccepted(context, space: space))

        var missingTarget = submitted
        missingTarget["schedules"] = [["name": "Schedule 1", "enabled": true, "action": 2, "hour": 8, "minute": 0, "dayOfWeek": 127, "fadeTime": 0, "id": 0, "selectTarget": 2, "sceneAddress": NSNull()]]
        NetworkRequest.shared.result = .success(["data": missingTarget])
        let directMismatch = await S.verifyUploadedConfiguration(space, payload: submitted)
        precondition(!directMismatch, "Direct readback must detect a lost nonempty scene target")
        let calls = NetworkRequest.shared.calls
        if case .success = await S.resumeUpload(space) {
            preconditionFailure("A stripped scene target cannot confirm the upload")
        }
        precondition(NetworkRequest.shared.calls == calls + 3 && S.hasPendingUpload(space) && S.isBlocked(space))
        NetworkRequest.shared.result = .success(["data": submitted])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("Correct readback must finish the receipt") }
        precondition(!S.hasPendingUpload(space) && !S.isBlocked(space))
        print("PASS: scene target readback mismatch retains receipt and succeeds on retry")
    }

    @MainActor static func testEmptySceneSchedulesAddedDuringUpload() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared, space = SpaceData("empty-scene-concurrent-adds")
        space.timedSchemaVersion = 2
        let schedules: [[String: Any]] = (0..<17).map { id in
            ["id": id, "name": "Empty \(id)", "enabled": true, "selectTarget": 2,
             "sceneAddress": "0006", "action": 2, "hour": 8, "minute": id,
             "dayOfWeek": 127, "fadeTime": 0, "nodeSlots": [[String: Any]]()]
        }
        space.exportValues = ["spaceData": ["timedSchemaVersion": 2],
                              "scenes": [["number": "0006", "name": "Empty scene"]],
                              "schedules": Array(schedules.prefix(1))]
        let firstPayload = space.payload
        let first = S.prepareSubmission(space, payload: firstPayload)!
        precondition(S.markSubmissionAccepted(first, space: space))
        space.exportValues["schedules"] = schedules
        space.lastUpdate += 16
        request.result = .failure(.noNetwork)
        if case .success = await S.resumeUpload(space) { preconditionFailure("offline readback must retain receipt") }
        precondition(S.hasPendingUpload(space) && space.needUploadCloud)
        // Reload the durable receipt as on re-entry, then confirm only its one
        // submitted schedule. This must not acknowledge the other sixteen.
        let reloaded = try S.recoveryState(space)
        precondition(reloaded.submission?.id == first.submission?.id)
        request.result = .success(["data": firstPayload])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("first snapshot should confirm") }
        precondition(space.lastUploadCloudTimestamp == 50 && space.lastUpdate == 66 && space.needUploadCloud)
        precondition((space.payload["schedules"] as? [[String: Any]])?.count == 17)
        let fullPayload = space.payload
        let full = S.prepareSubmission(space, payload: fullPayload)!
        precondition(S.markSubmissionAccepted(full, space: space))
        request.result = .success(["data": fullPayload])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("all seventeen should confirm on retry") }
        precondition(space.lastUploadCloudTimestamp == 66 && !space.needUploadCloud && !S.hasPendingUpload(space))
        print("PASS: empty Scene 1-to-17 additions survive failed readback and persisted receipt reload; old confirmation keeps newer edits pending, full retry confirms")
    }

    @MainActor static func testEmptySceneTargetReadback() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for enabled in [true, false] {
            let space = SpaceData("empty-scene-target-\(enabled)")
            var submitted = space.payload
            submitted["scenes"] = [["number": "0001", "name": "Scene 1"], ["number": "0002", "name": "Scene 2"]]
            let schedule: [String: Any] = ["id": 0, "name": "Schedule 1", "enabled": enabled,
                "selectTarget": 2, "sceneAddress": NSNull(), "action": 2, "hour": 8,
                "minute": 0, "dayOfWeek": 12, "fadeTime": 4,
                "groupAddresses": [], "deviceAddresses": [], "profiles": []]
            submitted["schedules"] = [schedule]
            guard let context = S.prepareSubmission(space, payload: submitted) else {
                preconditionFailure("An explicitly empty scene target must permit a durable upload receipt")
            }
            precondition(context.submission?.scheduleTargets != nil)
            precondition(S.markSubmissionAccepted(context, space: space))
            request.result = .failure(.noNetwork)
            if case .success = await S.resumeUpload(space) {
                preconditionFailure("An unavailable readback must retain the empty-target receipt")
            }
            precondition(S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == nil)

            var changed = schedule
            changed["sceneAddress"] = "0001"
            var omitted = schedule
            omitted.removeValue(forKey: "sceneAddress")
            for schedules in [[changed], [omitted], [[String: Any]]()] {
                var remote = submitted
                remote["schedules"] = schedules
                request.result = .success(["data": remote])
                let directMatches = await S.verifyUploadedConfiguration(space, payload: submitted)
                precondition(!directMatches, "Empty targets must not absorb added targets, missing fields or deleted schedules")
                if case .success = await S.resumeUpload(space) {
                    preconditionFailure("Changed empty-target readback must not confirm an upload")
                }
                let pending = try S.recoveryState(space)
                precondition(pending.submission?.id == context.submission?.id
                    && space.lastUploadCloudTimestamp == nil)
            }

            let readback = try JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: submitted)) as! [String: Any]
            request.result = .success(["data": readback])
            let directMatches = await S.verifyUploadedConfiguration(space, payload: submitted)
            precondition(directMatches, "Matching empty targets must pass direct readback")
            if case .failure = await S.resumeUpload(space) {
                preconditionFailure("Matching empty-target retry must finish the receipt")
            }
            precondition(!S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == 50)
        }
        print("PASS: enabled/disabled empty scene targets submit, retain receipts on failed/changed readback, and confirm on matching retry")
    }

    @MainActor static func testSchedulerModelReadback() async throws {
        typealias S = SpaceConfigurationSafety
        for permission in [Permission.owner, .editor] {
            let space = SpaceData("scheduler-readback-\(permission)")
            space.permission = permission
            space.lastUploadCloudTimestamp = 49 // An editor must have completed its initial import.
            var node: [String: Any] = [
                "uuid": "00000000-0000-0000-0000-000000000010", "unicastAddress": "0010",
                "deviceKey": String(repeating: "A1", count: 16), "schedules": [],
                "elements": [["index": 0, "models": [["modelId": "1207"]]]]
            ]
            let snapshot = SchedulerModelSnapshot(schemaVersion: 1, nodeUUID: node["uuid"] as! String,
                unicastAddress: "0010", deviceKeyFingerprint: try SchedulerModelSnapshot.keyFingerprint(node),
                models: [.init(elementAddress: "0010", modelId: "1207", entriesData: Data())], legacyEntriesData: Data())
            node["custProps"] = ["schedulerModelStates": try snapshot.dictionary()]
            space.nodes = [node]
            let submitted = space.payload
            let context = S.prepareSubmission(space, payload: submitted)!
            precondition(context.submission?.schedulerModelStates != nil)
            var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(context)) as! [String: Any]
            var receipt = old["submission"] as! [String: Any]
            receipt.removeValue(forKey: "schedulerModelStates")
            old["submission"] = receipt
            let decoded = try JSONDecoder().decode(SpaceRecoveryState.self, from: JSONSerialization.data(withJSONObject: old))
            precondition(decoded.submission?.schedulerModelStates == nil)
            precondition(S.markSubmissionAccepted(context, space: space))

            var stripped = submitted
            node.removeValue(forKey: "custProps")
            stripped["nodes"] = [node]
            stripped["role"] = permission == .owner ? "owner" : "editor"
            NetworkRequest.shared.result = .success(["data": stripped])
            let calls = NetworkRequest.shared.calls
            if case .success = await S.resumeUpload(space) { preconditionFailure("Missing snapshots cannot confirm") }
            precondition(NetworkRequest.shared.calls == calls + 3 && S.hasPendingUpload(space),
                         "role=\(permission) calls=\(NetworkRequest.shared.calls - calls) pending=\(S.hasPendingUpload(space))")
            let strippedMatches = await S.verifyUploadedConfiguration(space, payload: submitted)
            precondition(!strippedMatches)
            var partial = try snapshot.dictionary()
            partial["models"] = []
            node["custProps"] = ["schedulerModelStates": partial]
            stripped["nodes"] = [node]
            NetworkRequest.shared.result = .success(["data": stripped])
            if case .success = await S.resumeUpload(space) { preconditionFailure("Lost known-empty containers cannot confirm") }
            for raw in ["null", "\"invalid\"", "0", "true", "[]", "{}", "{\"schemaVersion\":1}"] {
                node["custProps"] = try JSONSerialization.jsonObject(with: Data("{\"schedulerModelStates\":\(raw)}".utf8))
                stripped["nodes"] = [node]
                NetworkRequest.shared.result = .success(["data": stripped])
                let malformedMatches = await S.verifyUploadedConfiguration(space, payload: submitted)
                precondition(!malformedMatches, "Malformed snapshots cannot confirm a direct readback")
                if case .success = await S.resumeUpload(space) {
                    preconditionFailure("Malformed snapshots cannot finish an upload receipt")
                }
                let pending = try S.recoveryState(space)
                precondition(S.hasPendingUpload(space) && pending.submission?.id == context.submission?.id)
                precondition(pending.schedulerModelStatesBaseline == context.schedulerModelStatesBaseline)
                precondition(SchedulerModelSnapshot.spaceData(space.payload) == SchedulerModelSnapshot.spaceData(submitted),
                             "Malformed readback must not replace local scheduler data")
            }
            NetworkRequest.shared.result = .success(["data": submitted])
            let directMatches = await S.verifyUploadedConfiguration(space, payload: submitted)
            precondition(directMatches)
            if case .failure = await S.resumeUpload(space) { preconditionFailure("Correct retry must finish") }
            precondition(!S.hasPendingUpload(space))
            let state = try S.recoveryState(space)
            precondition(state.schedulerModelStatesBaseline == SchedulerModelSnapshot.spaceData(submitted))
            precondition(!SchedulerModelSnapshot.remoteChanged(SchedulerModelSnapshot.spaceData(submitted)!, since: state.schedulerModelStatesBaseline))
        }
        let visitor = SpaceData("snapshot-read-only")
        visitor.permission = .visitor
        precondition(!S.canAutomaticallyUpload(visitor))
        print("PASS: Model snapshot readback rejects malformed roots/stripping/partial loss, retains receipts and local schedules, retries, preserves old receipts and visitor write restrictions")
    }

    @MainActor static func testProximityAllImportRecovery() throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("proximity-all-import")
        let profile: [String: Any] = ["id": "profile", "type": 7,
            "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 100,
            "vacantLevel": 50, "taskLevel": 100, "timeT1": 0, "timeT2": 5,
            "timeT3": 60, "timeT4": 0, "timeT5": 0,
            "manualOverrideTimeout": 5, "powerUpState": 0, "proximityLightingNumber": 21]
        var original = space.payload
        original["groups"] = [["address": "C00D", "profile": profile]]
        original["scenes"] = [[String: Any]]()
        original["schedules"] = [[String: Any]]()
        original["spaceData"] = ["proximityLightingSchemaVersion": 1, "triggerZones": []]
        let cleaned = try SpaceSyncCleanupPolicy.normalize(original)
        S.block(space, reason: "invalidRemoteProfile:C00D:invalidProfileRelay")
        precondition(S.isBlocked(space))
        precondition(S.preserveRemoteReferenceCleanup(space, payload: original, candidate: cleaned.payload))
        precondition(S.beginImport(space, payload: cleaned.payload))
        precondition(S.hasPendingImport(space) && S.isBlocked(space))
        precondition(S.finishImport(space, validatedTopology: true))
        precondition(!S.isBlocked(space) && !S.hasPendingImport(space),
                     "Successful canonical import must lift the previously persisted invalid relay barrier")
        let baseline = try S.recoveryState(space).authorizationBaseline
        precondition(baseline != nil && baseline == SpaceConfigurationIntegrityPolicy.configurationData(original)
                     && baseline == SpaceConfigurationIntegrityPolicy.configurationData(cleaned.payload),
                     "The original cloud alias and saved canonical value share the upload authorization baseline")
        precondition(S.preservesLocalChanges(space), "The repair remains pending until its upload is confirmed")
        let timestamp = space.lastUpdate
        let repeated = try SpaceSyncCleanupPolicy.normalize(cleaned.payload)
        precondition(!repeated.didChange && !S.isBlocked(space) && timestamp == space.lastUpdate)
        print("PASS: ALL alias import clears historical Profile block, preserves original baseline and retains repair upload intent")
    }

    @MainActor static func testReferenceCleanupReceipts() throws {
        let space = SpaceData("reference-cleanup")
        space.syncCloudError = .configurationExportInvalid
        SpaceConfigurationSafety.block(space, reason: "entryTopologyNeedsReview")
        precondition(SpaceConfigurationSafety.beginSyncReferenceCleanup(space, payload: space.payload))
        precondition(SpaceConfigurationSafety.isBlocked(space) && SpaceConfigurationSafety.preservesLocalChanges(space))
        space.savesSucceed = false
        precondition(!SpaceConfigurationSafety.finishSyncReferenceCleanup(space, changed: true))
        precondition(SpaceConfigurationSafety.hasPendingReferenceCleanup(space)
            && space.syncCloudError == .configurationExportInvalid, "Save failure retains retry intent and prior error")
        space.savesSucceed = true
        precondition(SpaceConfigurationSafety.finishSyncReferenceCleanup(space, changed: true))
        precondition(!SpaceConfigurationSafety.isBlocked(space) && space.syncCloudError == nil)
        precondition(SpaceConfigurationSafety.preservesLocalChanges(space), "Cleanup stays local until its own upload receipt")
        let timestamp = space.lastUpdate
        precondition(SpaceConfigurationSafety.finishSyncReferenceCleanup(space, changed: false))
        precondition(space.lastUpdate == timestamp, "Repeated validation does not create another edit")
        SpaceConfigurationSafety.block(space, reason: "unrelatedConflict")
        precondition(!SpaceConfigurationSafety.finishSyncReferenceCleanup(space, changed: false))
        precondition(SpaceConfigurationSafety.isBlocked(space), "Reference cleanup never clears other conflicts")

        let importing = SpaceData("reference-import")
        let original = importing.payload
        var candidate = original
        candidate["nodes"] = [["uuid": "retained", "unicastAddress": "0010", "groupState": 2]]
        precondition(SpaceConfigurationSafety.preserveRemoteReferenceCleanup(importing, payload: original, candidate: candidate))
        precondition(SpaceConfigurationSafety.beginImport(importing, payload: candidate))
        precondition(SpaceConfigurationSafety.originalReferenceCleanupImport(importing, candidate: candidate) != nil)
        precondition(SpaceConfigurationSafety.originalReferenceCleanupImport(importing, candidate: original) == nil,
                     "A stale receipt cannot claim a different import")
        importing.savesSucceed = false
        precondition(!SpaceConfigurationSafety.finishImport(importing))
        precondition(SpaceConfigurationSafety.hasPendingImport(importing), "Interrupted import remains resumable")
        importing.savesSucceed = true
        precondition(SpaceConfigurationSafety.finishImport(importing))
        let state = try SpaceConfigurationSafety.recoveryState(importing)
        precondition(state.authorizationBaseline == SpaceConfigurationIntegrityPolicy.configurationData(original),
                     "Authorization compares the actual original cloud version")
        precondition(SpaceConfigurationSafety.preservesLocalChanges(importing) && !SpaceConfigurationSafety.hasPendingImport(importing))
        precondition(SpaceConfigurationSafety.originalReferenceCleanupImport(importing, candidate: candidate) == nil)
        print("PASS: reference cleanup save failure/retry, import interruption, original baseline, scoped unblock and upload intent")
    }

    @MainActor static func testParseRejectionRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        let body = #"{"code":"parse_error","message":"Invalid UTF-8"}"#
        // Persisted legacy errors used integer code 0; both shapes must classify.
        for code in [0, 400] {
            let space = SpaceData("parse-rejected-\(code)")
            precondition(S.updateDeletionJournal(space) {
                $0.entries.append(.init(id: UUID(), nodeUUID: "deleted", primaryAddress: 2,
                    elementAddresses: [2], macAddress: nil, productId: nil, stage: .cleaned, completedTimestamp: 50))
            })
            let journal = try S.deletionJournal(space)
            let context = S.prepareSubmission(space, payload: space.payload, siteCreationTimestamp: 45)!
            let error = NetworkApiError(code: code, message: "Invalid UTF-8", httpStatusCode: 400, responseBody: body)
            S.rejectSubmission(context, space: space, error: error)
            let state = try S.recoveryState(space)
            precondition(state.submission == nil && state.siteCreationTimestamp == nil)
            precondition(space.needUploadCloud && space.lastUploadCloudTimestamp == nil)
            let remaining = try S.deletionJournal(space)
            precondition(remaining.entries.count == journal.entries.count && remaining.entries[0].id == journal.entries[0].id)
            let calls = NetworkRequest.shared.calls
            if case .failure = await S.resumeUpload(space) { preconditionFailure("rejected attempt must not block retry") }
            precondition(NetworkRequest.shared.calls == calls, "known parse rejection must not trigger three stale readbacks")
            let newer = S.prepareSubmission(space, payload: space.payload)!
            S.rejectSubmission(context, space: space, error: error)
            let afterLate = try S.recoveryState(space)
            precondition(afterLate.submission?.id == newer.submission?.id, "old failure cannot remove a newer receipt")
            precondition(S.markSubmissionAccepted(newer, space: space))
            S.rejectSubmission(newer, space: space, error: error)
            let accepted = try S.recoveryState(space)
            precondition(accepted.submission?.phase == .accepted, "a late rejection must preserve accepted evidence")
        }
        let unknownErrors: [NetworkApiError] = [
            .requestTimeout, .noNetwork, .serverNotRespond,
            .init(code: 500, message: "failed", httpStatusCode: 500, responseBody: body),
            .init(code: 400, message: "failed", httpStatusCode: 400, responseBody: #"{"code":"validation_error"}"#),
            .init(code: 400, message: "failed", httpStatusCode: 400, responseBody: "truncated"),
            .init(code: 400, message: "failed", httpStatusCode: 400, responseBody: body,
                  underlyingError: NSError(domain: NSURLErrorDomain, code: -1005))
        ]
        for (index, error) in unknownErrors.enumerated() {
            let space = SpaceData("unknown-result-\(index)")
            let context = S.prepareSubmission(space, payload: space.payload)!
            S.rejectSubmission(context, space: space, error: error)
            precondition(S.hasPendingUpload(space), "unknown outcomes cannot drop their receipt")
        }
        // Previously persisted prepared receipts retain baseline-based recovery.
        for conflict in [false, true] {
            let space = SpaceData("legacy-prepared-\(conflict)")
            space.lastUploadCloudTimestamp = 49
            var state = try S.recoveryState(space)
            var baseline = space.payload
            baseline["nodes"] = [["uuid": "old", "unicastAddress": "0002"]]
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(baseline)
            try S.testSaveState(state, space: space)
            _ = S.prepareSubmission(space, payload: space.payload)!
            if conflict { baseline["nodes"] = [["uuid": "other", "unicastAddress": "0005"]] }
            NetworkRequest.shared.result = .success(["data": baseline])
            let calls = NetworkRequest.shared.calls
            let result = await S.resumeUpload(space)
            precondition(NetworkRequest.shared.calls == calls + 3)
            if conflict {
                if case .success = result { preconditionFailure("real conflict must remain protected") }
                precondition(S.hasPendingUpload(space) && S.isBlocked(space))
            } else {
                if case .failure = result { preconditionFailure("unchanged baseline allows a new submission") }
                precondition(!S.hasPendingUpload(space) && space.needUploadCloud)
            }
        }
        print("PASS: parse rejection preserves edits/journals, skips readback, isolates new/accepted receipts and retains unknown/conflict recovery")
    }

    @MainActor static func testSiteHandoffReadback() async throws {
        typealias S = SpaceConfigurationSafety
        for unrelatedChange in [false, true] {
            let space = SpaceData("handoff-\(unrelatedChange)")
            let old: [String: Any] = ["uuid": "moved", "unicastAddress": "0002", "groupState": 0]
            let peer: [String: Any] = ["uuid": "peer", "unicastAddress": "0005", "groupState": 0]
            space.nodes = [old, peer]
            let context = S.prepareSubmission(space, payload: space.payload)!
            precondition(!S.finishAcceptedSubmission(context, space: space))
            space.lastUpdate = 60
            space.nodes = [peer]
            precondition(S.updateDeletionJournal(space) {
                $0.entries.append(.init(id: UUID(), nodeUUID: "moved", primaryAddress: 2, elementAddresses: [2],
                    macAddress: "AABBCCDDEEFF", productId: nil, stage: .cleaned, completedTimestamp: 60,
                    replacement: .init(siteId: space.siteId, spaceId: "winner", networkId: "new", uuid: "moved", address: 70, created: 55, mac: "AABBCCDDEEFF")))
            })
            var remote = space.payload
            remote["updateTimestamp"] = 50
            if unrelatedChange { remote["nodes"] = [[String: Any]]() }
            NetworkRequest.shared.result = .success(["data": remote])
            if !unrelatedChange {
                S.handleAuthorityError(.spacePasswordOverdue, space: space)
                space.requiresPasswordVerification = false
                S.reconcileAuthority(space, remote: remote)
                precondition(S.canAutomaticallyUpload(space), "handoff evidence also applies to pending reauthorization")
            }
            let result = await S.resumeUpload(space)
            if unrelatedChange {
                if case .success = result { preconditionFailure("handoff cannot hide an unrelated missing peer") }
                precondition(S.hasPendingUpload(space))
            } else {
                if case .failure = result { preconditionFailure("cloud-side removal of the superseded instance can confirm old submission") }
                precondition(space.lastUploadCloudTimestamp == 50 && space.needUploadCloud)
                precondition(!S.hasPendingUpload(space))
                let journal = try S.deletionJournal(space)
                precondition(journal.entries.count == 1, "new cleanup still requires its own verified upload")
            }
        }
        print("PASS: Site handoff supersedes only old membership, retains newer cleanup and protects unrelated peers")
    }

    @MainActor static func testEmptyGroupAddressRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for storedEmpty in [false, true] {
            let space = SpaceData("empty-address-\(storedEmpty)")
            let node: [String: Any] = ["uuid": "node", "unicastAddress": "0046", "groupState": 0]
            var storedNode = node, remoteNode = node
            if storedEmpty { storedNode["groupAddress"] = "" } else { remoteNode["groupAddress"] = "" }
            // Seed an accepted pre-fix snapshot on disk, including the old block.
            let legacy = try JSONSerialization.data(withJSONObject: ["groups": [], "memberships": [storedNode]])
            var state = try S.recoveryState(space)
            state.submission = .init(id: UUID(), timestamp: 50, configuration: legacy, phase: .accepted)
            try S.testSaveState(state, space: space)
            S.block(space, reason: "uploadReadbackConflict")
            space.lastUpdate = 60
            space.nodes = [node, ["uuid": "new-node", "unicastAddress": "0049", "groupState": 0]]
            precondition(S.updateDeletionJournal(space) { journal in
                for timestamp: Int64 in [50, 60] {
                    journal.entries.append(.init(id: UUID(), nodeUUID: "deleted-\(timestamp)", primaryAddress: 2,
                        elementAddresses: [2], macAddress: nil, productId: nil, stage: .cleaned, completedTimestamp: timestamp))
                }
            })
            var oldRemote = space.payload
            oldRemote["nodes"] = [remoteNode]
            oldRemote["updateTimestamp"] = 50
            request.result = .success(["data": oldRemote])
            let calls = request.calls, uploads = request.uploads
            if case .failure = await S.resumeUpload(space) { preconditionFailure("legacy empty address must confirm") }
            precondition(request.calls == calls + 1 && request.uploads == uploads)
            precondition(!S.isBlocked(space) && !S.hasPendingUpload(space))
            precondition(space.lastUploadCloudTimestamp == 50 && space.lastUpdate == 60 && space.needUploadCloud)
            let remaining = try S.deletionJournal(space)
            precondition(remaining.entries.count == 1 && remaining.entries[0].completedTimestamp == 60)

            // The shared production upload path can now export and confirm the
            // newer two-node payload; it must not mark that version done early.
            // Even receipts without identity/Model fields now check the current
            // cloud version before a new upload; an equal version remains valid.
            request.responses = [.success(["data": oldRemote]), .success([:]), .success(["data": space.payload])]
            if case .failure = await S.uploadBeforeUnbind(space) { preconditionFailure("newer edit must remain uploadable") }
            precondition(request.responses.isEmpty && request.uploads == uploads + 1)
            precondition(space.lastUploadCloudTimestamp == 60 && !space.needUploadCloud)
            let finished = try S.deletionJournal(space)
            precondition(finished.entries.isEmpty)

            // Password reauthorization must compare old on-disk baselines with
            // the same semantics, while preserving real remote changes.
            state = try S.recoveryState(space)
            state.authority = .waitingForAuthorization
            state.authorizationBaseline = legacy
            try S.testSaveState(state, space: space)
            space.lastUpdate = 70
            S.reconcileAuthority(space, remote: oldRemote)
            precondition(S.canAutomaticallyUpload(space) && !S.isBlocked(space))
            state = try S.recoveryState(space)
            state.authority = .waitingForAuthorization
            try S.testSaveState(state, space: space)
            remoteNode["groupAddress"] = "C000"
            oldRemote["nodes"] = [remoteNode]
            S.reconcileAuthority(space, remote: oldRemote)
            precondition(S.isBlocked(space) && !S.canAutomaticallyUpload(space))
        }
        print("PASS: persisted empty address in both directions, older receipts, newer upload and authorization baseline")
    }
}


extension SpaceRecoveryReceiptTests {
    static func membershipNode(_ value: Int) throws -> [String: Any] {
        let address = String(format: "%04X", value * 3)
        var node: [String: Any] = ["uuid": String(format: "00000000-0000-0000-0000-%012d", value),
            "unicastAddress": address, "groupState": 0, "deviceKey": String(repeating: "A1", count: 16),
            "schedules": [], "elements": [["index": 0, "models": [["modelId": "1207", "subscribe": []]]]]]
        let snapshot = SchedulerModelSnapshot(schemaVersion: 1, nodeUUID: node["uuid"] as! String,
            unicastAddress: address, deviceKeyFingerprint: try SchedulerModelSnapshot.keyFingerprint(node),
            models: [.init(elementAddress: address, modelId: "1207", entriesData: Data())], legacyEntriesData: Data())
        node["custProps"] = ["schedulerModelStates": try snapshot.dictionary()]
        return node
    }

    @MainActor static func testCloudMembershipRemoval() async throws {
        typealias S = SpaceConfigurationSafety
        let original = try (1...5).map(membershipNode)
        for mode in ["accepted", "import", "legacy", "all", "prepared", "unknown", "stale", "malformed", "peerKey", "peerModels", "unrelated", "writeFailure"] {
            let space = SpaceData("cloud-membership-" + mode)
            space.lastUploadCloudTimestamp = 49; space.nodes = original
            let context = S.prepareSubmission(space, payload: space.payload)!
            if mode != "prepared" { precondition(S.markSubmissionAccepted(context, space: space)) }
            if mode == "unknown" || mode == "legacy" {
                var state = try S.recoveryState(space)
                state.submission?.permitsCloudRemoval = mode == "unknown" ? false : nil
                state.submission?.nodeIdentities = nil
                try S.testSaveState(state, space: space)
            }
            var remote = space.payload
            var remoteNodes = mode == "all" ? [] : Array(original.prefix(3))
            if mode == "peerKey" { remoteNodes[0]["deviceKey"] = String(repeating: "B2", count: 16) }
            if mode == "peerModels" { remoteNodes[0].removeValue(forKey: "custProps") }
            remote["nodes"] = remoteNodes
            remote["deviceCount"] = 5 // Stale server summary is deliberately not authoritative.
            if mode == "stale" { remote["updateTimestamp"] = 49 }
            if mode == "malformed" { remote["nodes"] = NSNull() }
            if mode == "unrelated" { remote["triggerZones"] = [["items": [["groupAddress": 49152, "deviceAddress": 3]]]] }
            // An unsent local addition must survive removal of older submitted instances.
            space.nodes.append(try membershipNode(9)); space.lastUpdate = 55
            NetworkRequest.shared.result = .success(["data": remote])
            DevicePermanentDeletionContext.failCloudRemoval = mode == "writeFailure"
            if mode == "import" {
                _ = await space.update(spaceJsonData: remote)
                precondition(space.nodes.count == 4 && S.hasPendingUpload(space), "entry import cleans nodes but preserves the immutable pending receipt")
                _ = await space.update(spaceJsonData: remote)
                let replayed = try S.deletionJournal(space)
                precondition(replayed.entries.count == 2, "entry retry must not create duplicate removals")
            }
            let result = await S.resumeUpload(space)
            DevicePermanentDeletionContext.failCloudRemoval = false
            if ["accepted", "import", "legacy", "all"].contains(mode) {
                if case .failure = result { preconditionFailure("current Space removal must complete: " + mode) }
                precondition(space.nodes.count == remoteNodes.count + 1 && space.needUploadCloud)
                precondition(space.lastUploadCloudTimestamp == 50 && !S.hasPendingUpload(space))
                let state = try S.recoveryState(space)
                precondition(state.schedulerModelStatesBaseline == SchedulerModelSnapshot.spaceData(remote))
                precondition(trySnapshotCount(state.schedulerModelStatesBaseline) == remoteNodes.count)
                let entries = try S.deletionJournal(space).entries
                precondition(entries.count == 5 - remoteNodes.count && entries.allSatisfy { $0.cloudRemoval != nil })
                // Finish the newer cleanup upload, never resurrecting either old node.
                NetworkRequest.shared.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
                if case .failure = await S.finishCloudRemovalUpload(space) { preconditionFailure("sync completion must upload and verify the cleaned version") }
                precondition(NetworkRequest.shared.responses.isEmpty)
                let finished = try S.deletionJournal(space)
                precondition(finished.entries.isEmpty && !space.needUploadCloud)
            } else {
                if case .success = result { preconditionFailure("invalid removal must stay unconfirmed: " + mode) }
                precondition(space.nodes.count == 6 && S.hasPendingUpload(space))
            }
        }
        // No pending submission: a previously confirmed Space may lose a member
        // while this phone adds another device offline.
        let space = SpaceData("cloud-baseline-only")
        space.nodes = original; space.lastUploadCloudTimestamp = 50
        var state = try S.recoveryState(space)
        state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(space.payload)
        state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(space.payload)
        state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(space.payload)
        try S.testSaveState(state, space: space)
        var remote = space.payload; remote["nodes"] = Array(original.prefix(3))
        space.nodes.append(try membershipNode(9)); space.lastUpdate = 55
        NetworkRequest.shared.result = .success(["data": remote])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("baseline-only cleanup must precede upload") }
        precondition(space.nodes.count == 4 && space.needUploadCloud)
        let updated = try S.recoveryState(space)
        precondition(updated.nodeIdentitiesBaseline?.count == 3)
        if case .failure = await S.resumeUpload(space) { preconditionFailure("baseline cleanup replay must remain uploadable") }
        remote["triggerZones"] = [["items": [["groupAddress": 49152, "deviceAddress": 3]]]]
        NetworkRequest.shared.result = .success(["data": remote])
        if case .success = await S.resumeUpload(space) { preconditionFailure("offline local edit must not overwrite unrelated remote changes") }
        let clean = SpaceData("cloud-ordinary-import")
        clean.nodes = original; clean.lastUploadCloudTimestamp = clean.lastUpdate
        var cleanState = try S.recoveryState(clean)
        cleanState.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(clean.payload)
        cleanState.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(clean.payload)
        try S.testSaveState(cleanState, space: clean)
        remote["uuid"] = clean.id
        precondition(S.reconcileCloudMembership(clean, remote: remote), "without protected local work, ordinary import owns remote changes")
        print("PASS: current-Space accepted/legacy/baseline removal, all removed, unsent addition, exact Scheduler baseline, strict invalid/unknown/readback rejection and cleanup upload")
    }

    static func trySnapshotCount(_ data: Data?) -> Int {
        guard let data else { return -1 }
        return (try? JSONDecoder().decode([SchedulerModelSnapshot].self, from: data).count) ?? -1
    }
}

extension SpaceRecoveryReceiptTests {
    @MainActor static func testProfileConflictResolution() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = SpaceConfigurationIntegrityPolicy
        defer { ProximityLightingImportPreflight.storedSpace = nil; ProximityLightingImportPreflight.onExport = nil; S.failStateWrite = false }
        for mode in ["local", "cloud", "sameTime", "nonProfile", "accepted", "prepared", "mergeFailure", "receiptFailure", "cloudReceiptFailure", "localChanged", "cancelled", "staleRead", "invalid", "network", "revoked"] {
            let space = SpaceData()
            ProximityLightingImportPreflight.storedSpace = space
            space.lastUploadCloudTimestamp = 40
            space.nodes = [try membershipNode(1)]
            var profile: [String: Any] = ["id": "profile", "type": 1, "highEndTrim": 100,
                "lowEndTrim": 1, "occupancyLevel": 734, "vacantLevel": 100, "taskLevel": 100,
                "timeT1": 2, "timeT2": 10, "timeT3": 2, "timeT4": 0, "timeT5": 2,
                "manualOverrideTimeout": 60, "powerUpState": 255]
            space.groups = [["address": "C003", "profile": profile]]
            var state = try S.recoveryState(space)
            state.authorizationBaseline = P.configurationData(space.payload)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(space.payload)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(space.payload)
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(space.payload)
            try S.testSaveState(state, space: space)
            if mode == "accepted" || mode == "prepared" {
                let context = S.prepareSubmission(space, payload: space.payload)!
                if mode == "accepted" { precondition(S.markSubmissionAccepted(context, space: space)) }
            }
            var remote = space.payload
            profile["occupancyLevel"] = 414
            remote["groups"] = [["address": "C003", "profile": profile]]
            remote["updateTimestamp"] = ["cloud", "mergeFailure", "cloudReceiptFailure"].contains(mode) ? 55 : mode == "sameTime" ? 50 : mode == "staleRead" ? 39 : 45
            if mode == "nonProfile" { remote["triggerZones"] = [["items": [["groupAddress": 49155, "deviceAddress": 1]]]] }
            if mode == "invalid" { remote["nodes"] = NSNull() }
            if mode == "revoked" { remote["role"] = "visitor" }
            NetworkRequest.shared.result = mode == "network" ? .failure(.noNetwork) : .success(["data": remote])
            let calls = NetworkRequest.shared.calls
            space.profileMergeFails = mode == "mergeFailure"
            S.failStateWrite = ["receiptFailure", "cloudReceiptFailure"].contains(mode)
            ProximityLightingImportPreflight.onExport = mode == "localChanged" ? { space.lastUpdate += 1 } : nil
            let result: Swift.Result<Void, NetworkApiError>
            if mode == "cancelled" {
                let task = Task { @MainActor in await S.resumeUpload(space) }
                task.cancel()
                result = await task.value
            } else {
                result = await S.resumeUpload(space)
            }
            ProximityLightingImportPreflight.onExport = nil
            S.failStateWrite = false
            if ["local", "cloud", "accepted", "prepared"].contains(mode) {
                if case .failure = result { preconditionFailure("Profile conflict must resolve: " + mode) }
                let savedProfile = space.groups[0]["profile"] as! [String: Any]
                precondition(P.integer(savedProfile["occupancyLevel"]) == (mode == "cloud" ? 414 : 734))
                precondition(space.lastUploadCloudTimestamp == 40 && space.needUploadCloud,
                             "Choosing a Profile never confirms an unuploaded merged snapshot")
                precondition(!S.hasPendingUpload(space))
                // Persisted rebase must survive a retry before the next upload.
                if case .failure = await S.resumeUpload(space) { preconditionFailure("resolved Profile must remain retryable") }
                let context = S.prepareSubmission(space, payload: space.payload)!
                precondition(S.markSubmissionAccepted(context, space: space))
                NetworkRequest.shared.result = .success(["data": space.payload])
                if case .failure = await S.resumeUpload(space) { preconditionFailure("merged version must confirm normally") }
                precondition(!space.needUploadCloud && !S.hasPendingUpload(space))
            } else {
                if case .success = result { preconditionFailure("invalid/conflicting input must not resolve: " + mode) }
                precondition(P.integer((space.groups[0]["profile"] as! [String: Any])["occupancyLevel"]) == (mode == "cloudReceiptFailure" ? 414 : 734))
                precondition(space.lastUploadCloudTimestamp == 40)
                if ["receiptFailure", "cloudReceiptFailure", "mergeFailure"].contains(mode) {
                    space.profileMergeFails = false
                    if case .failure = await S.resumeUpload(space) { preconditionFailure("failed persistence must retry safely") }
                    precondition(space.needUploadCloud && space.lastUploadCloudTimestamp == 40)
                }
                if ["sameTime", "nonProfile"].contains(mode) { precondition(S.isBlocked(space)) }
                else { precondition(!S.isBlocked(space), "transient failures must not create review blocks") }
                precondition(NetworkRequest.shared.calls == calls + (["receiptFailure", "cloudReceiptFailure", "mergeFailure"].contains(mode) ? 2 : 1))
            }
        }
        print("PASS: Profile latest-Space-version resolution, equal-time review, protected topology, receipt replacement, retries and failures")
    }
}

extension SpaceRecoveryReceiptTests {
    @MainActor static func testFirstUploadMembershipRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        typealias M = SpaceMembershipCoordinator
        let request = NetworkRequest.shared
        defer {
            S.failMembershipWrite = false; S.failStateWrite = false
            request.onRequest = nil; ProximityLightingImportPreflight.onExport = nil
        }
        func remote(_ space: SpaceData) -> [String: Any] {
            var payload = space.payload
            payload["role"] = "owner"
            payload["owner"] = ["userId": UserData.currentUserId, "username": "fixture"]
            return payload
        }
        func historical(_ name: String, nodes: [[String: Any]] = []) throws -> SpaceData {
            let space = SpaceData("first-upload-" + name)
            space.nodes = nodes
            let receipt = S.prepareSubmission(space, payload: space.payload)!
            precondition(S.markSubmissionAccepted(receipt, space: space))
            var membership = try M.store.read(M.scope(space))!
            membership.initialized = false // Already persisted by the previous App version.
            try M.store.write(membership)
            precondition(!S.canAutomaticallyUpload(space) && S.canResumePendingUpload(space))
            return space
        }
        func expectFailure(_ result: Result<Void, NetworkApiError>, _ error: NetworkApiError? = nil) {
            guard case .failure(let actual) = result else { preconditionFailure("must retain protection") }
            if let error { precondition(actual == error, "unexpected error: \(actual)") }
        }
        func initialized(_ space: SpaceData) throws -> Bool { try M.store.read(M.scope(space))?.initialized == true }

        // New local exports stay initialized while a GET preserves the pending upload.
        let fresh = SpaceData("first-upload-new")
        let receipt = S.prepareSubmission(fresh, payload: fresh.payload)!
        try expectMembership(initialized(fresh))
        precondition(S.markSubmissionAccepted(receipt, space: fresh))
        for _ in 0..<2 {
            let record = try M.preparedRecord(fresh, networkID: fresh.meshNetworkId)
            let outcome = await fresh.update(spaceJsonData: remote(fresh))
            precondition(record.initialized && outcome == .preserved("localDeletionOrRecoveryPendingUpload"))
        }
        request.result = .success(["data": remote(fresh)])
        if case .failure = await S.resumeUpload(fresh) { preconditionFailure("new upload must finish") }
        precondition(!S.hasPendingUpload(fresh) && fresh.lastUploadCloudTimestamp == 50)

        // Reopen an old accepted receipt using a new model object, with empty and nonempty data.
        for nodes in [[], [try membershipNode(1)]] {
            let old = try historical(nodes.isEmpty ? "empty" : "nonempty", nodes: nodes)
            let reopened = SpaceData(old.id); reopened.nodes = nodes
            request.result = .success(["data": remote(reopened)])
            if case .failure = await S.resumeUpload(reopened) { preconditionFailure("matching historical receipt must recover") }
            try expectMembership(initialized(reopened))
            precondition(!S.hasPendingUpload(reopened) && reopened.lastUploadCloudTimestamp == 50
                && S.canAutomaticallyUpload(reopened) && S.canCleanSyncReferences(reopened))
        }

        // No receipt cannot authorize a true import placeholder, even if its role is owner.
        for role in [Permission.owner, .editor, .visitor] {
            let placeholder = SpaceData("first-upload-placeholder-\(role)"); placeholder.permission = role
            _ = try M.preparedRecord(placeholder, networkID: placeholder.meshNetworkId)
            precondition(!S.canAutomaticallyUpload(placeholder) && !S.canResumePendingUpload(placeholder))
            precondition(S.prepareSubmission(placeholder, payload: placeholder.payload) == nil)
            try expectMembership(!initialized(placeholder))
        }

        // Mismatched remote data, missing Keys, local data loss and stale joins never initialize.
        for variant in ["remote-key", "remote-config", "local-missing", "network", "owner", "role", "leave", "rejoin", "account", "region", "import", "password", "cancel"] {
            let space = try historical(variant, nodes: [try membershipNode(1)])
            let payload = remote(space)
            var server = payload
            switch variant {
            case "remote-key": server.removeValue(forKey: "netKey")
            case "remote-config": server["nodes"] = [[String: Any]]()
            case "local-missing": space.nodes = []
            case "network":
                var record = try M.store.read(M.scope(space))!; record.networkID = "different"
                try M.store.write(record)
            case "owner": server["owner"] = ["userId": "different-account"]
            case "role": server["role"] = "visitor"
            case "leave":
                var record = try M.store.read(M.scope(space))!; record.phase = .queued
                try M.store.write(record)
            case "rejoin": request.onRequest = { precondition(M.authorizeJoin(space)) }
            case "account": request.onRequest = { UserData.currentUserId = "another-account" }
            case "region": request.onRequest = { UserData.currentServerRegion = "another-region" }
            case "import": precondition(S.beginImport(space, payload: payload))
            case "password": space.requiresPasswordVerification = true
            default: break
            }
            request.result = .success(["data": server])
            if variant == "cancel" {
                let task = Task { @MainActor in await S.resumeUpload(space) }
                task.cancel(); expectFailure(await task.value)
            } else {
                expectFailure(await S.resumeUpload(space), variant == "role" ? .noSpacePermission : nil)
            }
            UserData.currentUserId = "test-account"; UserData.currentServerRegion = "test-region"
            try expectMembership(!initialized(space))
            // Actual authority revocation retains the old receipt in the existing archive.
            if variant != "role" { precondition(S.hasPendingUpload(space)) }
        }

        // Failed metadata/confirmation writes are not reported as server permission errors.
        for variant in ["metadata", "membership", "receipt"] {
            let space = try historical("persist-" + variant)
            request.result = .success(["data": remote(space)])
            if variant == "metadata" { space.savesSucceed = false }
            if variant == "membership" { S.failMembershipWrite = true }
            if variant == "receipt" {
                space.onSave = { if space.lastUploadCloudTimestamp != nil { S.failStateWrite = true } }
            }
            expectFailure(await S.resumeUpload(space), .configurationUploadUnconfirmed)
            precondition(S.hasPendingUpload(space))
            S.failMembershipWrite = false; S.failStateWrite = false; space.onSave = nil
            let reopened = SpaceData(space.id)
            reopened.lastUploadCloudTimestamp = space.lastUploadCloudTimestamp
            request.result = .success(["data": remote(reopened)])
            if case .failure = await S.resumeUpload(reopened) { preconditionFailure("persistent receipt must retry after reopening") }
            try expectMembership(initialized(reopened))
            precondition(!S.hasPendingUpload(reopened) && reopened.lastUploadCloudTimestamp == 50)
        }
        let offline = try historical("offline")
        request.result = .failure(.noNetwork)
        expectFailure(await S.resumeUpload(offline), .noNetwork)
        try expectMembership(!initialized(offline))
        precondition(S.hasPendingUpload(offline))
        request.result = .success(["data": remote(offline)])
        if case .failure = await S.resumeUpload(offline) { preconditionFailure("offline retry must recover") }
        print("PASS: first-upload membership, historical empty/nonempty receipt recovery, strict identity/data/authority/lifecycle gates and persistence retries")
    }
}

private func expectMembership(_ value: @autoclosure () throws -> Bool) rethrows {
    let result = try value(); precondition(result)
}

extension SpaceRecoveryReceiptTests {
    @MainActor static func testLegacyUninitializedReceiptRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        typealias M = SpaceMembershipCoordinator
        let request = NetworkRequest.shared
        defer { S.failStateWrite = false; request.onRequest = nil }
        func seed(_ name: String, missing: Set<String>, markerOnly: Bool = false,
                  populated: Bool = false, verified: Bool = false) throws -> SpaceData {
            let space = SpaceData("legacy-uninitialized-" + name)
            if populated {
                space.nodes = try [1, 2].map(membershipNode).map { node in
                    var node = node; node.removeValue(forKey: "custProps"); return node
                }
            }
            let payload = space.payload
            precondition(S.recordSnapshot(space, payload: payload))
            _ = try M.preparedRecord(space, networkID: space.meshNetworkId)
            if markerOnly { S.block(space, reason: "uploadReadbackUnconfirmed") }
            else {
                // Write the historical shape directly; do not regenerate it with
                // prepareSubmission, which initializes membership and fills fields.
                var state = try S.recoveryState(space)
                state.submission = .init(id: UUID(), timestamp: space.lastUpdate,
                    configuration: SpaceConfigurationIntegrityPolicy.configurationData(payload)!,
                    phase: verified ? .verified : .accepted,
                    keyFingerprint: missing.contains("keys") ? nil : SpaceKeyIntegrity.pair(payload, networkID: space.meshNetworkId)?.fingerprint,
                    scheduleTargets: missing.contains("targets") ? nil : SpaceConfigurationIntegrityPolicy.scheduleTargetsData(payload),
                    timedConfiguration: missing.contains("timed") ? nil : TimedSchedulerPayloadPolicy.canonical(payload),
                    schedulerModelStates: missing.contains("models") ? nil : SchedulerModelSnapshot.spaceData(payload),
                    nodeIdentities: missing.contains("nodes") ? nil : SpaceCloudNodeRemovalPolicy.instances(payload))
                try S.testSaveState(state, space: space)
            }
            return space
        }
        func remote(_ space: SpaceData) -> [String: Any] {
            var payload = space.payload
            payload["role"] = "owner"; payload["owner"] = ["userId": UserData.currentUserId]
            return payload
        }
        func diagnostic(_ space: SpaceData) -> [String: Any] {
            S.debugSnapshotStatus(space)["lastReadbackDiagnostic"] as? [String: Any] ?? [:]
        }
        let all: Set<String> = ["keys", "targets", "timed", "models", "nodes"]
        for populated in [false, true] {
            for field in ["keys", "targets", "timed", "models", "nodes", "all", "marker", "verified"] {
                let space = try seed("\(populated)-\(field)", missing: field == "all" || field == "verified" ? all : [field],
                                     markerOnly: field == "marker", populated: populated, verified: field == "verified")
                precondition(!S.canAutomaticallyUpload(space) && S.canResumePendingUpload(space))
                let status = S.debugSnapshotStatus(space)
                precondition(status["pendingUpload"] as? Bool == true && status["membershipNetworkMatches"] as? Bool == true)
                precondition(status["hasCompleteExportSnapshot"] as? Bool == true && status["recoveryAuthority"] as? String == "writable")
                if field == "marker" { precondition(status["legacyUploadMarker"] as? Bool == true) }
                if field == "all" {
                    let fields = status["submissionFields"] as! [String: Bool]
                    precondition(fields.count == 5 && fields.values.allSatisfy { !$0 })
                }
                let receiptID = try S.recoveryState(space).submission?.id
                var server = remote(space)
                server["nodes"] = space.nodes.reversed().map { $0 }
                request.result = .success(["data": server])
                request.onRequest = {
                    let receipt = try! S.recoveryState(space).submission!
                    if let receiptID { precondition(receipt.id == receiptID) }
                    precondition(receipt.phase == .accepted && receipt.permitsCloudRemoval == false)
                    precondition(receipt.keyFingerprint != nil && receipt.nodeIdentities != nil)
                    precondition((try! M.store.read(M.scope(space)))?.initialized == false)
                }
                let calls = request.calls, uploads = request.uploads
                if case .failure = await S.resumeUpload(space) { preconditionFailure("legacy recovery must succeed: \(field)") }
                precondition(request.calls == calls + 1 && request.uploads == uploads)
                precondition(!S.hasPendingUpload(space) && S.canCleanSyncReferences(space) && S.canAutomaticallyUpload(space))
                precondition(space.lastUploadCloudTimestamp == 50 && diagnostic(space)["stage"] as? String == "confirmed")
            }
        }

        for variant in ["missing-snapshot", "snapshot-space", "snapshot-version", "snapshot-configuration", "snapshot-key",
                        "existing-fingerprint", "existing-targets", "membership-network", "recovery-authority", "remote-import",
                        "snapshot-save", "remote-owner", "remote-device-key", "local-device-key", "local-missing", "offline"] {
            let space = try seed(variant, missing: ["nodes"], populated: true)
            var snapshot = space.payload
            var server = remote(space)
            switch variant {
            case "missing-snapshot":
                try FileManager.default.removeItem(at: S.testDirectory(space).appendingPathComponent("last-complete-export.json"))
            case "snapshot-space": snapshot["uuid"] = "different"
            case "snapshot-version": snapshot["updateTimestamp"] = 49
            case "snapshot-configuration": snapshot["nodes"] = [[String: Any]]()
            case "snapshot-key": snapshot["netKey"] = ["key": "different"]
            case "existing-fingerprint", "existing-targets", "recovery-authority", "remote-import":
                var state = try S.recoveryState(space)
                if variant == "existing-fingerprint" { state.submission?.keyFingerprint = "different" }
                if variant == "existing-targets" { state.submission?.scheduleTargets = Data("different".utf8) }
                if variant == "recovery-authority" { state.authority = .waitingForAuthorization }
                if variant == "remote-import" { state.requiresRemoteImport = true }
                try S.testSaveState(state, space: space)
            case "membership-network":
                var membership = try M.store.read(M.scope(space))!; membership.networkID = "different"
                try M.store.write(membership)
            case "snapshot-save": S.failStateWrite = true
            case "remote-owner": server["owner"] = ["userId": "different"]
            case "remote-device-key":
                var nodes = space.nodes; nodes[0]["deviceKey"] = String(repeating: "B2", count: 16); server["nodes"] = nodes
            case "local-device-key": space.nodes[0]["deviceKey"] = String(repeating: "B2", count: 16)
            case "local-missing": space.nodes = []
            default: break
            }
            if variant.hasPrefix("snapshot-") && variant != "snapshot-save" {
                precondition(S.recordSnapshot(space, payload: snapshot))
            }
            request.result = variant == "offline" ? .failure(.noNetwork) : .success(["data": server])
            let calls = request.calls
            if case .success = await S.resumeUpload(space) { preconditionFailure("must preserve protection: \(variant)") }
            S.failStateWrite = false
            precondition(S.hasPendingUpload(space) && space.lastUploadCloudTimestamp == nil)
            try expectMembership(M.store.read(M.scope(space))?.initialized == false)
            let result = diagnostic(space)
            precondition(result["reason"] is String && result["error"] is Int)
            if !["remote-owner", "remote-device-key", "local-device-key", "local-missing", "offline"].contains(variant) {
                precondition(request.calls == calls, "invalid local evidence must fail before GET")
            }
            if variant == "remote-device-key" { precondition(result["reason"] as? String == "remoteNodeIdentitiesMismatch") }
            if variant == "local-device-key" { precondition(result["reason"] as? String == "localNodeIdentitiesMismatch") }
            // A cleanup failure must not replace the more specific readback result.
            S.recordSyncFailure(space, error: .configurationUnavailable, stage: "cleanupPreparation")
            precondition(diagnostic(space)["attemptId"] as? String == result["attemptId"] as? String)
            precondition(diagnostic(space)["reason"] as? String == result["reason"] as? String)
            if variant == "snapshot-save" || variant == "offline" {
                let reopened = SpaceData(space.id); reopened.nodes = space.nodes
                request.result = .success(["data": remote(reopened)])
                if case .failure = await S.resumeUpload(reopened) { preconditionFailure("migration/readback must retry after reopen") }
                precondition(S.canAutomaticallyUpload(reopened) && !S.hasPendingUpload(reopened))
            }
        }
        print("PASS: production legacy marker/partial receipt recovery, empty/nonempty identity, exact snapshots, failure/reopen and independent diagnostics")
    }
}
