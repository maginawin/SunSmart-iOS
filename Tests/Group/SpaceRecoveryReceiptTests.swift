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
    var payload: [String: Any] { ["uuid": id, "groups": [], "nodes": nodes, "updateTimestamp": lastUpdate] }
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
        if case .failure = offline { preconditionFailure("accepted upload must finish locally even while offline") }
        precondition(request.calls == callsBeforeAccepted)
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
        try await testEmptyGroupAddressRecovery()
        try await testSiteHandoffReadback()
        try await testImportPreparation()
        try await testParseRejectionRecovery()
        try testReferenceCleanupReceipts()

        // Account changes invalidate pending callbacks before looking up another store.
        let accountContext = try SpaceConfigurationSafety.recoveryState(b)
        UserData.currentUserId = "another-account"
        precondition(!SpaceConfigurationSafety.isCurrent(accountContext, space: b))
        UserData.currentUserId = "test-account"
        print("PASS: production direct acceptance, unknown-outcome recovery, first-upload baseline, persistence failures, versions, authority and lifecycle isolation")
    }

    @MainActor static func testDirectUploadConfirmation() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for reason in ["uploadReadbackConflict", "uploadReadbackUnconfirmed", "invalidRemoteTopology"] {
            let space = SpaceData("accepted-" + reason)
            let context = S.prepareSubmission(space, payload: space.payload)!
            precondition(S.markSubmissionAccepted(context, space: space))
            S.block(space, reason: reason)
            request.result = .success(["data": ["uuid": "wrong-space", "nodes": []]])
            let calls = request.calls
            precondition(S.finishAcceptedSubmission(context, space: space))
            precondition(request.calls == calls && space.lastUploadCloudTimestamp == 50)
            precondition(S.isBlocked(space) == (reason == "invalidRemoteTopology"))
            precondition(!S.hasPendingUpload(space))
            let newer = S.prepareSubmission(space, payload: space.payload)!
            precondition(!S.finishAcceptedSubmission(context, space: space), "old completion must not consume a newer receipt")
            S.discardUnsentSubmission(newer, space: space)
        }
        for succeeds in [false, true] {
            let space = SpaceData("unbind-direct-\(succeeds)")
            request.result = succeeds ? .success([:]) : .failure(.requestTimeout)
            let calls = request.calls, uploads = request.uploads
            // A new edit arrives while the submitted version is in flight.
            request.onRequest = { space.lastUpdate = 60 }
            let result = await S.uploadBeforeUnbind(space)
            if succeeds {
                if case .failure = result { preconditionFailure("successful upload must confirm without GET") }
                precondition(space.lastUploadCloudTimestamp == 50 && !S.hasPendingUpload(space))
            } else {
                if case .success = result { preconditionFailure("timeout must not confirm") }
                precondition(space.lastUploadCloudTimestamp == nil && S.hasPendingUpload(space))
            }
            precondition(space.needUploadCloud)
            precondition(request.calls == calls + 1 && request.uploads == uploads + 1)
        }
        // Older accepted snapshots never move the confirmed version backwards.
        let monotonic = SpaceData("accepted-monotonic")
        let context = S.prepareSubmission(monotonic, payload: monotonic.payload)!
        precondition(S.markSubmissionAccepted(context, space: monotonic))
        monotonic.lastUploadCloudTimestamp = 80
        precondition(S.finishAcceptedSubmission(context, space: monotonic))
        precondition(monotonic.lastUploadCloudTimestamp == 80)

        // One failed local confirmation must not undo another accepted Space.
        let first = SpaceData("partial-first"), second = SpaceData("partial-second")
        let firstContext = S.prepareSubmission(first, payload: first.payload)!
        let secondContext = S.prepareSubmission(second, payload: second.payload)!
        precondition(S.markSubmissionAccepted(firstContext, space: first))
        precondition(S.markSubmissionAccepted(secondContext, space: second))
        let calls = request.calls
        precondition(S.finishAcceptedSubmission(firstContext, space: first))
        second.savesSucceed = false
        precondition(!S.finishAcceptedSubmission(secondContext, space: second))
        precondition(!S.hasPendingUpload(first) && S.hasPendingUpload(second))
        second.savesSucceed = true
        S.failStateWrite = true
        precondition(!S.finishAcceptedSubmission(secondContext, space: second))
        S.failStateWrite = false
        let persisted = try S.recoveryState(second)
        precondition(persisted.submission?.phase == .accepted)
        if case .failure = await S.resumeUpload(second) { preconditionFailure("state persistence retry must finish locally") }
        precondition(!S.hasPendingUpload(second) && request.calls == calls)
        print("PASS: direct success uses submitted timestamps, makes no GET, preserves newer edits and unrelated blocks")
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
            precondition(request.calls == calls && request.uploads == uploads)
            precondition(!S.isBlocked(space) && !S.hasPendingUpload(space))
            precondition(space.lastUploadCloudTimestamp == 50 && space.lastUpdate == 60 && space.needUploadCloud)
            let remaining = try S.deletionJournal(space)
            precondition(remaining.entries.count == 1 && remaining.entries[0].completedTimestamp == 60)

            // The shared production upload path can now export and confirm the
            // newer two-node payload; it must not mark that version done early.
            request.responses = [.success([:])]
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
