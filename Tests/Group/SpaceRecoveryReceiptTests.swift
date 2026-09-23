import Foundation
import CryptoKit

enum Permission { case owner, editor, visitor }
struct UserData {
    let name: String; let uuid: String
    static var currentUserId = "test-account", currentServerRegion = "test-region"
}
extension String { var localizedString: String { self } }
// NETWORK_ERROR_TYPE
final class SpaceData {
    enum State { case normal, waitDeleted }
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
    var uploadCloud: Bool { lastUploadCloudTimestamp != nil }
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) && permission != .visitor }
    var nodes: [[String: Any]] = []
    var payload: [String: Any] {
        ["uuid": id, "groups": [], "scenes": [], "schedules": [], "nodes": nodes, "updateTimestamp": lastUpdate,
         "netKey": ["key": id], "appKey": ["key": "app"]]
    }
    init(_ id: String = UUID().uuidString) { self.id = id }
    func markLocalChangePendingCloudSync() { lastUpdate += 1 }
    @discardableResult func save() -> Bool { savesSucceed }
    @discardableResult func delete() -> Bool {
        SpaceConfigurationSafety.beginRemoval(self) && SpaceConfigurationSafety.archiveDeletedSpace(self)
    }
    enum Purpose { case cloudSync, localBackup }
    @MainActor func export(purpose: Purpose) async -> [String: Any]? {
        await SpaceConfigurationSafety.prepareUpload(self, payload: payload) ? payload : nil
    }
    // METADATA_METHOD
    // IMPORT_PREPARATION_METHOD
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
    var responses: [Swift.Result<[String: Any], NetworkApiError>] = []
    var onRequest: (() -> Void)?
    func request(_ api: API) async -> Swift.Result<[String: Any], NetworkApiError> {
        calls += 1
        if case .spaceUpload = api { uploads += 1 }
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
        try await testLegacyUpgradeRetry()
        try await testLegacyUpgradeRecovery()
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
        try await testSchedulerModelReadback()
        try await testEmptyGroupAddressRecovery()
        try await testSiteHandoffReadback()
        try await testImportPreparation()
        try await testParseRejectionRecovery()
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
             "elements": [["models": [["modelId": "0A780001", "subscribe": ["C008"]]]]]]
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
        func blocked() -> SpaceData {
            let space = SpaceData()
            space.lastUploadCloudTimestamp = space.lastUpdate
            S.block(space, reason: "upgradeBaselineNeedsImport")
            space.syncCloudError = .configurationExportInvalid
            return space
        }
        for role in [Permission.owner, .editor] {
            let space = blocked(); space.permission = role
            let local = legacyUpgradePayload(space, modern: true)
            request.result = .success(["data": legacyUpgradePayload(space, modern: false)])
            var reads = 0
            let result = await S.recoverUpgradeBaselineIfNeeded(space) { reads += 1; return local }
            precondition(result && reads == 2 && !S.isBlocked(space) && S.testMigrated(space) && space.syncCloudError == nil)
            let calls = request.calls
            let repeated = await S.recoverUpgradeBaselineIfNeeded(space) { preconditionFailure("already recovered") }
            precondition(repeated && request.calls == calls)
            precondition(!S.needsUpgradeBaseline(space), "migration receipt survives a new recovery-state read")
        }
        // Even if timestamps match, real configuration/identity differences stay protected.
        for field in ["profile", "members", "path", "zone", "netKey", "scene", "schedule", "version", "invalid"] {
            let space = blocked(), local = legacyUpgradePayload(space, modern: true)
            var remote = legacyUpgradePayload(space, modern: false)
            var groups = remote["groups"] as! [[String: Any]]
            switch field {
            case "profile":
                var profile = groups[0]["profile"] as! [String: Any]; profile["timeT2"] = 1201; groups[0]["profile"] = profile
            case "members": remote["nodes"] = Array((remote["nodes"] as! [[String: Any]]).prefix(1))
            case "path": groups[0]["proximityLightingPath"] = ["paths": [["items": [557, 554]]], "zones": [["addresses": [554, 557]]]]
            case "zone": remote["spaceData"] = ["triggerZones": [["items": [["groupAddress": 49160, "deviceAddress": 554]]]]]
            case "netKey": remote["netKey"] = ["index": 1, "key": String(repeating: "2", count: 32)]
            case "scene": remote["scenes"] = [["number": "0001", "name": "changed", "addresses": [554]]]
            case "schedule": remote["schedules"] = [["id": 1, "hour": 12]]
            case "version": remote["updateTimestamp"] = space.lastUpdate + 1
            default: remote["spaceData"] = "invalid"
            }
            remote["groups"] = groups
            request.result = .success(["data": remote])
            let result = await S.recoverUpgradeBaselineIfNeeded(space) { local }
            precondition(!result && S.isBlocked(space) && !S.testMigrated(space), "must preserve \(field) difference")
        }
        for condition in ["visitor", "password", "localWrite", "import", "cleanup", "deletion", "submission", "authority", "otherReason"] {
            let space = SpaceData(); space.lastUploadCloudTimestamp = space.lastUpdate
            let local = legacyUpgradePayload(space, modern: true)
            if condition == "submission" { precondition(S.prepareSubmission(space, payload: local) != nil) }
            S.block(space, reason: condition == "otherReason" ? "invalidRemoteTopology" : "upgradeBaselineNeedsImport")
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
            default: break
            }
            let calls = request.calls
            let result = await S.recoverUpgradeBaselineIfNeeded(space) { preconditionFailure("ineligible local read") }
            precondition(result == (condition == "otherReason") && S.isBlocked(space) && !S.testMigrated(space) && request.calls == calls)
        }
        for failure in ["network", "stateSave", "spaceSave", "firstRead", "secondRead", "sameSecondEdit", "versionChange", "accountChange", "permissionChange", "cancel"] {
            let space = blocked(); var local = legacyUpgradePayload(space, modern: true)
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
        for (error, key) in [(NetworkApiError.configurationUnavailable, "configuration_sync_unavailable"),
                             (.configurationReviewRequired, "configuration_review_message"),
                             (.configurationExportInvalid, "proximity_lighting_export_invalid")] {
            precondition(NetworkApiError(code: error.code) == error && error.localizedDescription == key)
        }
        print("PASS: legacy block recovery; full valid inputs, roles, strict conflicts, pending operations, repeated reads, persistence, cancellation and error round-trip")
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

    @MainActor static func testSceneTargetReadback() async throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData("scene-target-readback")
        var submitted = space.payload
        submitted["scenes"] = [["number": "0006", "name": "All off"]]
        submitted["schedules"] = [["id": 0, "selectTarget": 2, "sceneAddress": "0006"]]
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
        missingTarget["schedules"] = [["id": 0, "selectTarget": 2, "sceneAddress": NSNull()]]
        NetworkRequest.shared.result = .success(["data": missingTarget])
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
        print("PASS: Model snapshot readback rejects stripping/partial loss, retries, preserves old receipts and visitor write restrictions")
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
            request.responses = [.success([:]), .success(["data": space.payload])]
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
