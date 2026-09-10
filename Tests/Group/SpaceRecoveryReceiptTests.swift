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
    var failCloudCommit = false
    var uploadCloud: Bool { lastUploadCloudTimestamp != nil }
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) && permission != .visitor }
    var canDeleteEmptySpaceRecords: Bool { nodes.isEmpty }
    // Persistence/primary-key scope is covered by SpaceRecordRemovalTests.
    var canDeleteSpaceRecords: Bool { permission == .owner && (nodes.isEmpty || hasSyncFailureForRemoval) }
    var hasSyncFailureForRemoval: Bool {
        (needUploadCloud && syncCloudError != nil) || SpaceConfigurationSafety.isBlocked(self)
    }
    var nodes: [[String: Any]] = []
    var payload: [String: Any] { ["uuid": id, "groups": [], "nodes": nodes, "updateTimestamp": lastUpdate,
        "netKey": ["index": 1, "key": String(repeating: "11", count: 16), "phase": 0],
        "appKey": ["index": 1, "boundNetKey": 1, "key": String(repeating: "22", count: 16)]] }
    init(_ id: String = UUID().uuidString) { self.id = id }
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
enum API { case spaceInfo(siteId: String, spaceId: String, password: String?)
    case spaceDelete(siteId: String, spaceId: String)
    case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any]) }
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    func cancelSynchronizationHandle(space: SpaceData) {}
}
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
        precondition(NetworkApiError(code: -2002) == .configurationUploadUnconfirmed)
        precondition(NetworkApiError(code: -2003) == .configurationExportInvalid)
        precondition(NetworkApiError.configurationUploadUnconfirmed.localizedDescription == "configuration_upload_unconfirmed")
        let staleKeys = SpaceData("stale-keys")
        SpaceConfigurationSafety.meshKeyFailure(staleKeys, issue: .staleSnapshot)
        precondition(!SpaceConfigurationSafety.isBlocked(staleKeys) && staleKeys.syncCloudError == nil)
        SpaceConfigurationSafety.meshKeyFailure(staleKeys, issue: .netKeyIndexConflict)
        precondition(SpaceConfigurationSafety.isBlocked(staleKeys) && staleKeys.syncCloudError == .meshKeyConflict)
        SpaceConfigurationSafety.meshKeysRestored(staleKeys)
        precondition(!SpaceConfigurationSafety.isBlocked(staleKeys) && staleKeys.syncCloudError == nil)
        let maintenance = SpaceData("virtual-group-maintenance")
        precondition(SpaceConfigurationSafety.updateDeletionJournal(maintenance) { $0.pendingVirtualGroupAddresses = [0xC001] })
        precondition(!SpaceConfigurationSafety.isBlocked(maintenance) && !SpaceConfigurationSafety.preservesLocalChanges(maintenance))
        let switchSpace = SpaceData("switch-receipt")
        precondition(SpaceConfigurationSafety.updateDeletionJournal(switchSpace) {
            $0.switches = [.init(id: UUID(), switchId: "switch", fingerprint: "snapshot", completedTimestamp: 50)]
        })
        precondition(SpaceConfigurationSafety.preservesLocalChanges(switchSpace))
        var olderPayload = switchSpace.payload
        olderPayload["updateTimestamp"] = 49
        precondition(SpaceConfigurationSafety.confirmLocalChanges(switchSpace, payload: olderPayload))
        precondition(SpaceConfigurationSafety.preservesLocalChanges(switchSpace))
        olderPayload["updateTimestamp"] = 50
        precondition(SpaceConfigurationSafety.confirmLocalChanges(switchSpace, payload: olderPayload))
        precondition(!SpaceConfigurationSafety.preservesLocalChanges(switchSpace))
        print("PASS: pending Switch deletion survives old cloud receipts and clears only at its confirmed timestamp")
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
        let offline = await SpaceConfigurationSafety.resumeUpload(a)
        if case .success = offline { preconditionFailure("offline readback cannot confirm") }
        precondition(SpaceConfigurationSafety.hasPendingUpload(a) && !SpaceConfigurationSafety.isBlocked(a))
        // No extra edit or upload: the persisted pending task finishes on reconnect.
        remote(a)
        var remapped = a.payload
        remapped["provisioners"] = [["allocatedUnicastRange": [["lowAddress": "0001", "highAddress": "1000"]]]]
        request.result = .success(["data": remapped])
        let resumed = await SpaceConfigurationSafety.resumeUpload(a)
        if case .failure = resumed { preconditionFailure("reconnected readback must finish") }
        precondition(!SpaceConfigurationSafety.hasPendingUpload(a) && !SpaceConfigurationSafety.preservesLocalChanges(a))
        precondition(SpaceConfigurationSafety.testMigrated(a) && request.uploads == 0)
        a.lastUpdate = 51
        let nextAdd = await SpaceConfigurationSafety.prepareUpload(a, payload: a.payload)
        precondition(nextAdd, "first upload must establish a baseline before the next addition")

        // Failed receipt write must retain a durable verified submission.
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
        precondition(SpaceConfigurationSafety.markSubmissionAccepted(gContext, space: g))
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

        try await testEmptyGroupAddressRecovery()
        try await testSiteHandoffReadback()
        try await testImportPreparation()
        try await testNewerCloudReplacement()
        try await testMeshKeyReceipts()
        try await testSpaceRecordRemoval()
        try await testParseRejectionRecovery()

        // Account changes invalidate pending callbacks before looking up another store.
        let accountContext = try SpaceConfigurationSafety.recoveryState(b)
        UserData.currentUserId = "another-account"
        precondition(!SpaceConfigurationSafety.isCurrent(accountContext, space: b))
        UserData.currentUserId = "test-account"
        print("PASS: production durable readback/reconnect, first-upload baseline, persistence failures, versions, authority and lifecycle isolation")
    }

    @MainActor static func testSpaceRecordRemoval() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        defer { ProximityLightingImportPreflight.storedSpace = nil; request.onRequest = nil }
        for rejection: NetworkApiError in [.editorBeingUsedSpace, .visitorBeingUsedSpace,
            .apiError(code: 403, message: nil, httpStatusCode: 403, responseBody: nil, underlyingDomain: nil, underlyingCode: nil)] {
            let rejected = SpaceData(); rejected.lastUploadCloudTimestamp = rejected.lastUpdate
            let before = try S.recoveryState(rejected)
            var during: SpaceRecoveryState?
            request.onRequest = { during = try! S.recoveryState(rejected) }
            request.result = .failure(rejection)
            let result = await S.requestSpaceRemoval(rejected)
            if case .failure(let error) = result { precondition(error == rejection) } else { fatalError("expected rejection") }
            let after = try S.recoveryState(rejected)
            precondition(after.phase == .active && after.discardRequested != true && !S.isBlocked(rejected))
            precondition(!S.isCurrent(before, space: rejected) && !S.isCurrent(during!, space: rejected))
            precondition(S.canAutomaticallyUpload(rejected) && S.canDeleteDeviceRecords(rejected))
            ProximityLightingImportPreflight.storedSpace = rejected
            let imported = await rejected.update(spaceJsonData: rejected.payload)
            precondition(imported == .prepared, "explicit rejection must allow cloud import preparation again")
        }
        let rejectedPending = SpaceData()
        let pending = S.prepareSubmission(rejectedPending, payload: rejectedPending.payload)!
        S.block(rejectedPending, reason: "unrelatedFailure")
        request.result = .failure(.editorBeingUsedSpace)
        _ = await S.requestSpaceRemoval(rejectedPending)
        let retained = try S.recoveryState(rejectedPending)
        precondition(retained.discardRequested != true && retained.submission == pending.submission)
        precondition(S.isBlocked(rejectedPending), "rejection must not erase unrelated recovery protection")

        for uncertain: NetworkApiError in [.noNetwork, .requestTimeout, .serverNotRespond, .unknown,
            .apiError(code: 408, message: nil, httpStatusCode: 408, responseBody: nil, underlyingDomain: nil, underlyingCode: nil),
            .apiError(code: 500, message: nil, httpStatusCode: 500, responseBody: nil, underlyingDomain: nil, underlyingCode: nil),
            .apiError(code: 403, message: nil, httpStatusCode: 403, responseBody: nil, underlyingDomain: "transport", underlyingCode: -1)] {
            let unresolved = SpaceData(); unresolved.lastUploadCloudTimestamp = 1
            request.result = .failure(uncertain)
            _ = await S.requestSpaceRemoval(unresolved)
            let unresolvedState = try S.recoveryState(unresolved)
            precondition(unresolvedState.discardRequested == true && S.isBlocked(unresolved))
            let imported = await unresolved.update(spaceJsonData: unresolved.payload)
            precondition(imported == .preserved("spaceDiscardPending"))
        }
        let staleRejection = SpaceData(); staleRejection.lastUploadCloudTimestamp = 1
        var newer: SpaceRecoveryState?
        request.result = .failure(.editorBeingUsedSpace)
        request.onRequest = {
            var state = try! S.recoveryState(staleRejection)
            state.generation = UUID()
            try! S.testSaveState(state, space: staleRejection)
            newer = state
        }
        _ = await S.requestSpaceRemoval(staleRejection)
        precondition(try! S.recoveryState(staleRejection) == newer, "stale rejection cannot clear a newer removal intent")
        let authorityRejected = SpaceData(); authorityRejected.lastUploadCloudTimestamp = 1
        request.result = .failure(.spacePasswordOverdue)
        _ = await S.requestSpaceRemoval(authorityRejected)
        let authorityState = try S.recoveryState(authorityRejected)
        precondition(authorityState.discardRequested != true && authorityState.authority == .waitingForAuthorization)
        precondition(authorityRejected.requiresPasswordVerification && !S.canAutomaticallyUpload(authorityRejected))
        print("PASS: rejected deletion releases discard, retains recovery/authority, permits import; uncertain results and stale callbacks remain protected")

        let space = SpaceData()
        space.lastUploadCloudTimestamp = 1
        precondition(S.prepareSubmission(space, payload: space.payload) != nil)
        let old = try S.recoveryState(space)
        let uploads = request.uploads
        request.result = .failure(.noNetwork)
        if case .failure(.noNetwork) = await S.requestSpaceRemoval(space) {} else { fatalError("network error must retain local data") }
        var state = try S.recoveryState(space)
        precondition(state.phase == .active && state.discardRequested == true && state.submission != nil)
        precondition(!S.isCurrent(old, space: space) && !S.canAutomaticallyUpload(space))
        let calls = request.calls
        _ = await S.resumeUpload(space)
        precondition(request.calls == calls, "discard intent must not resume old uploads")
        request.result = .failure(.resourceNotFound)
        if case .success = await S.requestSpaceRemoval(space) {} else { fatalError("lost response must be replayable") }
        state = try S.recoveryState(space)
        precondition(state.phase == .removing && request.uploads == uploads)
        let replayCalls = request.calls
        if case .success = await S.requestSpaceRemoval(space) {} else { fatalError("local cleanup retry") }
        precondition(request.calls == replayCalls)
        let denied = SpaceData(); denied.permission = .visitor
        if case .failure(.noSpacePermission) = await S.requestSpaceRemoval(denied) {} else { fatalError("owner only") }
        precondition(request.calls == replayCalls)
        let switched = SpaceData(); switched.lastUploadCloudTimestamp = 1
        request.result = .success([:])
        request.onRequest = { UserData.currentUserId = "switched-account" }
        if case .failure = await S.requestSpaceRemoval(switched) {} else { fatalError("stale response must not remove") }
        UserData.currentUserId = "test-account"
        let switchedState = try S.recoveryState(switched)
        precondition(switchedState.phase == .active)
        let local = SpaceData()
        let localCalls = request.calls
        if case .success = await S.requestSpaceRemoval(local) {} else { fatalError("local-only deletion") }
        let localState = try S.recoveryState(local)
        precondition(request.calls == localCalls && localState.phase == .removing)
        let rejectedImport = SpaceData()
        let remoteCalls = request.calls
        if case .success = await S.requestSpaceRemoval(rejectedImport, requireCloudDeletion: true) {} else { fatalError("broken imported Space must delete remotely even without upload timestamp") }
        precondition(request.calls == remoteCalls + 1 && request.uploads == uploads)
        let failedOwner = SpaceData(); failedOwner.nodes = [["uuid": "remaining"]]
        S.block(failedOwner, reason: "missingMeshKeys")
        let failedOwnerCalls = request.calls
        request.result = .failure(.noNetwork)
        if case .failure(.noNetwork) = await S.requestSpaceRemoval(failedOwner) {} else { fatalError("abnormal Owner must try cloud even without an upload timestamp") }
        precondition(request.calls == failedOwnerCalls + 1 && failedOwner.nodes.count == 1)
        let retainedOwner = try S.recoveryState(failedOwner)
        precondition(retainedOwner.phase == .active)
        request.result = .success([:])
        if case .success = await S.requestSpaceRemoval(failedOwner) {} else { fatalError("abnormal nonempty Owner deletion is allowed") }
        let removedOwner = try S.recoveryState(failedOwner)
        precondition(removedOwner.phase == .removing && request.uploads == uploads)
        let editor = SpaceData(); editor.nodes = [["uuid": "remaining"]]; editor.permission = .editor
        S.block(editor, reason: "missingMeshKeys")
        let editorCalls = request.calls
        if case .failure(.noSpacePermission) = await S.requestSpaceRemoval(editor) {} else { fatalError("Editor must not delete abnormal Space") }
        precondition(request.calls == editorCalls)
        let downgraded = SpaceData(); downgraded.nodes = [["uuid": "remaining"]]
        S.block(downgraded, reason: "missingMeshKeys")
        request.onRequest = { downgraded.permission = .editor }
        if case .failure = await S.requestSpaceRemoval(downgraded) {} else { fatalError("Owner downgraded while awaiting deletion cannot retire local records") }
        let downgradedState = try S.recoveryState(downgraded)
        precondition(downgradedState.phase == .active && downgraded.nodes.count == 1)
        let nonempty = SpaceData(); nonempty.nodes = [["uuid": "remaining"]]
        let beforeNonempty = request.calls
        if case .failure = await S.requestSpaceRemoval(nonempty, requireCloudDeletion: true) {} else {
            fatalError("healthy nonempty Space must still be protected")
        }
        precondition(request.calls == beforeNonempty)

        // A prior version's unconfirmed nonempty discard is checked by GET only.
        var legacy = try S.recoveryState(nonempty)
        legacy.discardRequested = true
        try S.testSaveState(legacy, space: nonempty)
        request.result = .success(["data": nonempty.payload])
        let legacyPrepared = await S.prepareForDeviceDeletion(nonempty)
        precondition(legacyPrepared && request.calls == beforeNonempty + 1)
        precondition(!S.isCurrent(legacy, space: nonempty))
        let legacyAfter = try S.recoveryState(nonempty)
        precondition(legacyAfter.discardRequested != true && legacyAfter.phase == .active)
        precondition(nonempty.nodes.count == 1)

        // Pending import bytes survive suspension; a late importer loses its generation.
        let importing = SpaceData()
        let importState = try S.recoveryState(importing)
        let root = try S.testDirectory(importing)
        let pendingURL = root.appendingPathComponent("pending-import.json")
        try JSONSerialization.data(withJSONObject: importing.payload).write(to: pendingURL)
        let prepared = await S.prepareForDeviceDeletion(importing)
        precondition(prepared && !S.hasPendingImport(importing) && !S.isCurrent(importState, space: importing))
        let archives = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
        precondition(archives.contains { $0.lastPathComponent.hasPrefix("suspended-import-") })
        precondition(!S.canAutomaticallyUpload(importing), "suspended partial import is not a complete upload baseline")
        print("PASS: record deletion bypasses upload, retains data on server failure, retries lost responses and rejects stale/unauthorized callbacks")
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
            precondition(accepted.submission?.phase == .accepted, "accepted receipts still need readback")
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
            precondition(S.markSubmissionAccepted(context, space: space))
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

    @MainActor static func testMeshKeyReceipts() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        let incomplete = SpaceData("missing-payload-keys")
        precondition(S.recordSnapshot(incomplete, payload: incomplete.payload))
        let file = try S.testDirectory(incomplete).appendingPathComponent("last-complete-export.json")
        let original = try Data(contentsOf: file)
        var missing = incomplete.payload
        missing.removeValue(forKey: "appKey")
        precondition(!S.recordSnapshot(incomplete, payload: missing))
        precondition((try? Data(contentsOf: file)) == original)
        precondition(S.prepareSubmission(incomplete, payload: missing) == nil)
        precondition(incomplete.syncCloudError == .meshKeysUnavailable)
        precondition((try? S.recoveryState(incomplete))?.submission == nil)

        let changed = SpaceData("changed-remote-keys")
        let context = S.prepareSubmission(changed, payload: changed.payload)!
        precondition(S.markSubmissionAccepted(context, space: changed))
        var remote = changed.payload
        var app = remote["appKey"] as! [String: Any]
        app["key"] = String(repeating: "33", count: 16)
        remote["appKey"] = app
        request.result = .success(["data": remote])
        let mismatch = await S.resumeUpload(changed)
        if case .success = mismatch { fatalError("equal topology cannot confirm different keys") }
        precondition(changed.lastUploadCloudTimestamp == nil)
        precondition((try? S.recoveryState(changed))?.submission != nil)
        request.result = .success(["data": changed.payload])
        let confirmed = await S.resumeUpload(changed)
        if case .failure = confirmed { fatalError("matching keys and configuration should confirm") }

        let legacy = SpaceData("legacy-missing-keys")
        var state = try S.recoveryState(legacy)
        state.submission = .init(id: UUID(), timestamp: legacy.lastUpdate,
            configuration: SpaceConfigurationIntegrityPolicy.configurationData(legacy.payload)!, phase: .accepted)
        try S.testSaveState(state, space: legacy)
        let calls = request.calls
        request.result = .success(["data": legacy.payload])
        let unproven = await S.resumeUpload(legacy)
        if case .failure(.meshKeysUnavailable) = unproven {} else { fatalError("legacy missing snapshot must stay unconfirmed") }
        precondition(request.calls == calls + 1 && legacy.lastUploadCloudTimestamp == nil)
        precondition((try? S.recoveryState(legacy))?.submission != nil)
        print("PASS: missing keys cannot overwrite complete backup or submit; readback proves keys; unproven legacy receipt is retained")
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
            var savedPayload = space.payload
            savedPayload["nodes"] = [storedNode]
            precondition(S.recordSnapshot(space, payload: savedPayload))
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
