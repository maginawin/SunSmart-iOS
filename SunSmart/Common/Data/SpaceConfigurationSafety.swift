import Foundation
import NordicSigMeshSDK
import SQLite
import CryptoKit

/// Recovery data stays on this device. It is not a new server schema or a cloud
/// conflict token. Interrupted imports are replayed, never restored by replacing
/// the live Mesh database (which could roll back sequence numbers).
enum SpaceConfigurationSafety {
    private static let lock = NSRecursiveLock()

    private static func key(meshUUID: String, networkId: String) -> String {
        let scope = "\(UserData.currentUserId)|\(UserData.currentServerRegion)|\(meshUUID)|\(networkId)"
        return SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func key(_ space: SpaceData) -> String {
        key(meshUUID: space.meshUUID, networkId: space.meshNetworkId)
    }

    private static var recoveryRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/SpaceConfigurationRecovery")
    }

    private static func identity(_ space: SpaceData) -> SpaceRecoveryState.Identity {
        .init(account: UserData.currentUserId, region: String(describing: UserData.currentServerRegion),
              space: deletionScope(space))
    }

    private static func stateURL(_ space: SpaceData) -> URL {
        recoveryRoot.appendingPathComponent(key(space) + ".json")
    }

    static func recoveryState(_ space: SpaceData) throws -> SpaceRecoveryState {
        lock.lock(); defer { lock.unlock() }
        if let state = try SpaceRecoveryState.read(from: stateURL(space), identity: identity(space)) { return state }
        let state = SpaceRecoveryState(identity: identity(space))
        try saveState(state, space: space)
        return state
    }

    private static func saveState(_ state: SpaceRecoveryState, space: SpaceData) throws {
        guard state.identity == identity(space) else { throw SafetyError.invalidCheckpoint }
        try FileManager.default.createDirectory(at: recoveryRoot, withIntermediateDirectories: true)
        try state.write(to: stateURL(space))
#if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                              ofItemAtPath: stateURL(space).path)
#endif
        var root = recoveryRoot
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
    }

    static func isCurrent(_ context: SpaceRecoveryState, space: SpaceData) -> Bool {
        guard context.identity == identity(space), let state = try? recoveryState(space) else { return false }
        return state.matches(context)
    }

    private static func storedDirectory(_ space: SpaceData, state: SpaceRecoveryState) -> URL {
        recoveryRoot.appendingPathComponent(state.directoryName ?? key(space))
    }

    private static func directory(_ space: SpaceData) throws -> URL {
        let state = try recoveryState(space)
        guard state.phase == .active else { throw SafetyError.invalidCheckpoint }
        var url = storedDirectory(space, state: state)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    static func isBlocked(meshUUID: String, networkId: String) -> Bool {
        let identity = key(meshUUID: meshUUID, networkId: networkId)
        let stateURL = recoveryRoot.appendingPathComponent(identity + ".json")
        var directoryName = identity
        if FileManager.default.fileExists(atPath: stateURL.path) {
            guard let data = try? Data(contentsOf: stateURL),
                  let state = try? JSONDecoder().decode(SpaceRecoveryState.self, from: data) else { return true }
            if state.phase != .active { return true }
            directoryName = state.directoryName ?? identity
        }
        let pending = recoveryRoot.appendingPathComponent(directoryName).appendingPathComponent("pending-import.json")
        return UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + identity) != nil
            || FileManager.default.fileExists(atPath: pending.path)
            || deletionCleanupPending(at: pending.deletingLastPathComponent().appendingPathComponent("device-deletions.json"))
    }

    static func isBlocked(_ space: SpaceData) -> Bool {
        isBlocked(meshUUID: space.meshUUID, networkId: space.meshNetworkId)
    }

    static func block(_ space: SpaceData, reason: String) {
        block(meshUUID: space.meshUUID, networkId: space.meshNetworkId, reason: reason)
        print("[SpaceConfigurationSafety] blocked space=\(space.id) reason=\(reason)")
        MeshNetworkManager.instance.realNodes.filter {
            $0.network?.uuid.uuidString == space.meshUUID && $0.subNetworkId == space.meshNetworkId
        }
            .forEach { $0.clearSyncStateCache() }
    }

    static func block(meshUUID: String, networkId: String, reason: String) {
        let identity = "spaceConfigurationBlocked." + key(meshUUID: meshUUID, networkId: networkId)
        // Keep the first cause; subsequent entry checks are consequences.
        if UserDefaults.standard.string(forKey: identity) == nil {
            UserDefaults.standard.set(reason, forKey: identity)
        }
    }

    static func deletionScope(_ space: SpaceData) -> SpaceDeletionJournal.Scope {
        .init(siteId: space.siteId, spaceId: space.id, meshUUID: space.meshUUID, networkId: space.meshNetworkId)
    }

    private static func deletionCleanupPending(at url: URL) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(SpaceDeletionJournal.self, from: data) else { return true }
        return journal.needsCleanup
    }

    static func deletionJournal(_ space: SpaceData) throws -> SpaceDeletionJournal {
        lock.lock(); defer { lock.unlock() }
        return try .read(from: directory(space).appendingPathComponent("device-deletions.json"),
                         scope: deletionScope(space))
    }

    @discardableResult
    static func updateDeletionJournal(_ space: SpaceData, _ update: (inout SpaceDeletionJournal) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            var journal = try deletionJournal(space)
            update(&journal)
            let url = try directory(space).appendingPathComponent("device-deletions.json")
            try journal.write(to: url)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                                                   ofItemAtPath: url.path)
            if !journal.needsCleanup,
               UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) == "deletionCleanupPending" {
                UserDefaults.standard.removeObject(forKey: "spaceConfigurationBlocked." + key(space))
            }
            return true
        } catch {
            block(space, reason: "deletionCleanupPending")
            print("[DevicePermanentDeletion] journal failed space=\(space.id) error=\(error)")
            return false
        }
    }

    static func hasPendingDeletionCleanup(_ space: SpaceData) -> Bool {
        (try? deletionJournal(space).needsCleanup) ?? true
    }

    /// A GET must not resurrect devices while their explicit deletion or local
    /// recovery is waiting for the existing upload/readback flow to finish.
    static func preservesLocalChanges(_ space: SpaceData) -> Bool {
        guard let state = try? recoveryState(space) else { return true }
        guard state.preservesUpload else { return false }
        guard let journal = try? deletionJournal(space) else { return true }
        return state.submission != nil || state.authority == .waitingForAuthorization || !journal.entries.isEmpty
            || UserDefaults.standard.object(forKey: "spaceConfigurationLocalRecoveryPending." + key(space)) != nil
    }

    @discardableResult
    static func confirmLocalChanges(_ space: SpaceData, payload: [String: Any]) -> Bool {
        guard let timestamp = SpaceConfigurationIntegrityPolicy.integer(payload["updateTimestamp"]),
              payload["nodes"] is [[String: Any]] else { return false }
        guard updateDeletionJournal(space, { journal in
            journal.confirmUpload(timestamp: timestamp)
        }) else { return false }
        let receiptKey = "spaceConfigurationLocalRecoveryPending." + key(space)
        if let receipt = UserDefaults.standard.object(forKey: receiptKey) as? NSNumber,
           receipt.int64Value <= timestamp {
            UserDefaults.standard.removeObject(forKey: receiptKey)
        }
        return true
    }

    /// Called only after successful local Space removal.
    /// Preserve diagnostic files outside the active identity directory.
    @discardableResult
    static func archiveDeletedSpace(_ space: SpaceData) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            let root = storedDirectory(space, state: state)
            if state.phase != .retired {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try state.write(to: root.appendingPathComponent("recovery-state.json"))
            }
            state.phase = .retired
            state.submission = nil
            if !(state.pendingArchives ?? []).contains(root.lastPathComponent) {
                state.pendingArchives = (state.pendingArchives ?? []) + [root.lastPathComponent]
            }
            // Invalidate callbacks and active recovery before the fallible move.
            try saveState(state, space: space)
            clearActiveMarkers(space)
            retryArchiveMoves(space)
            return true
        } catch {
            print("[SpaceConfigurationSafety] archive failed space=\(space.id) error=\(error)")
            return false
        }
    }

    static func retryArchiveMoves(_ space: SpaceData) {
        lock.lock(); defer { lock.unlock() }
        guard var state = try? recoveryState(space) else { return }
        for name in state.pendingArchives ?? [] {
            guard name == key(space) || name.hasPrefix(key(space) + "-"), !name.contains("/") else { continue }
            let root = recoveryRoot.appendingPathComponent(name)
            let archive = recoveryRoot.appendingPathComponent("archived-" + key(space) + "-" + UUID().uuidString)
            do {
                if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.moveItem(at: root, to: archive) }
                state.pendingArchives?.removeAll { $0 == name }
            } catch { print("[SpaceConfigurationSafety] retired archive move pending space=\(space.id) error=\(error)") }
        }
        try? saveState(state, space: space)
    }

    private static func clearActiveMarkers(_ space: SpaceData) {
        for prefix in ["spaceConfigurationBlocked.", "spaceConfigurationMigrated.",
                       "spaceConfigurationLocalRecoveryPending."] {
            UserDefaults.standard.removeObject(forKey: prefix + key(space))
        }
    }

    static func beginRemoval(_ space: SpaceData) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard state.phase != .retired else { return true }
            state.phase = .removing
            try saveState(state, space: space)
            return true
        } catch { return false }
    }

    static func beginUnbind(_ space: SpaceData) -> SpaceRecoveryState? {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard state.phase == .active else { return nil }
            state.unbindRequested = true
            try saveState(state, space: space)
            return state
        } catch { return nil }
    }

    @MainActor
    static func resumeUnbind(_ space: SpaceData) async -> Bool {
        guard let context = try? recoveryState(space), context.unbindRequested == true else { return false }
        if context.phase == .removing { return space.delete() }
        guard context.phase == .active else { return false }
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard isCurrent(context, space: space) else { return false }
        switch result {
        case .success(let response):
            guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id else { return false }
            var state = context
            state.unbindRequested = nil
            try? saveState(state, space: space)
        case .failure(let error):
            switch error {
            case .resourceNotFound, .noSitePermission, .noSpacePermission: return space.delete()
            default: handleAuthorityError(error, space: space)
            }
        }
        return false
    }

    /// Also covers a crash after deleting the DB row but before retiring its receipt.
    static func resumeLocalRemovals() {
        guard SunSmartDataManager.shared.db != nil,
              let urls = try? FileManager.default.contentsOfDirectory(at: recoveryRoot, includingPropertiesForKeys: nil) else { return }
        for url in urls where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url), let state = try? JSONDecoder().decode(SpaceRecoveryState.self, from: data),
                  (state.phase == .removing || !(state.pendingArchives ?? []).isEmpty), state.identity.account == UserData.currentUserId,
                  state.identity.region == String(describing: UserData.currentServerRegion) else { continue }
            let scope = state.identity.space
            let space = SpaceData.load(siteId: scope.siteId, spaceId: scope.spaceId).first
                ?? SpaceData(name: "", id: scope.spaceId, siteId: scope.siteId, imageId: 0, create: 0, lastUpdate: 0,
                             isFavourite: false, permission: .visitor, sourceType: .share,
                             meshUUID: scope.meshUUID, meshNetworkId: scope.networkId)
            if state.phase == .removing { _ = space.delete() } else { retryArchiveMoves(space) }
        }
    }

    static func activateImport(_ space: SpaceData) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            let previous = try recoveryState(space)
            guard previous.phase != .removing else { return false }
            if previous.phase == .retired {
                // Retry a deferred archive, then isolate the new import even if the move fails.
                guard archiveDeletedSpace(space) else { return false }
                var state = SpaceRecoveryState(identity: identity(space))
                state.pendingArchives = try recoveryState(space).pendingArchives
                state.directoryName = key(space) + "-" + state.generation.uuidString
                try saveState(state, space: space)
                clearActiveMarkers(space)
            }
            return true
        } catch { return false }
    }

    @MainActor
    static func verifyUploadedConfiguration(_ space: SpaceData, payload: [String: Any]) async -> Bool {
        if case .success(let matches) = await readUploadedConfiguration(space, payload: payload) { return matches }
        return false
    }

    @MainActor
    private static func readUploadedConfiguration(_ space: SpaceData, payload: [String: Any]) async -> Swift.Result<Bool, NetworkApiError> {
        guard let context = try? recoveryState(space) else { return .failure(uploadUnconfirmed) }
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard isCurrent(context, space: space) else { return .failure(uploadUnconfirmed) }
        switch result {
        case .failure(let error):
            handleAuthorityError(error, space: space)
            return .failure(error)
        case .success(let response):
            guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id,
                  let expected = SpaceConfigurationIntegrityPolicy.configurationData(payload),
                  let actual = SpaceConfigurationIntegrityPolicy.configurationData(remote) else { return .failure(uploadUnconfirmed) }
            space.applyRemoteSpaceMetadata(remote)
            guard space.save() else { return .failure(uploadUnconfirmed) }
            if expected != actual {
                print("[SpaceConfigurationReadback] source=direct site=\(space.siteId) space=\(space.id) "
                    + "localTimestamp=\(space.lastUpdate) result=mismatch "
                    + SpaceConfigurationIntegrityPolicy.readbackDiagnostic(submitted: payload, remote: remote))
            }
            return .success(expected == actual)
        }
    }

    static var uploadUnconfirmed: NetworkApiError {
        .configurationUploadUnconfirmed
    }

    static func hasPendingUpload(_ space: SpaceData) -> Bool {
        (try? recoveryState(space).submission) != nil
            || UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) == "uploadReadbackUnconfirmed"
    }

    static func requiresConfigurationReview(_ space: SpaceData) -> Bool {
        let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space))
        return reason != nil && reason != "uploadReadbackUnconfirmed"
    }

    static func canAutomaticallyUpload(_ space: SpaceData) -> Bool {
        guard space.permission != .visitor, !space.requiresPasswordVerification, !space.disableEditorPermission,
              space.state == .normal, let state = try? recoveryState(space), state.phase == .active else { return false }
        return state.authority == .writable && state.unbindRequested != true && state.requiresRemoteImport != true
    }

    static func requiresAuthorityImport(_ space: SpaceData) -> Bool {
        (try? recoveryState(space).requiresRemoteImport) == true
    }

    /// Persist the exact submitted generation before making the request.
    static func prepareSubmission(_ space: SpaceData, payload: [String: Any], siteCreationTimestamp: Int64? = nil) -> SpaceRecoveryState? {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard state.phase == .active, state.authority == .writable, state.submission == nil,
                  let timestamp = SpaceConfigurationIntegrityPolicy.integer(payload["updateTimestamp"]),
                  payload["uuid"] as? String == space.id, payload["nodes"] is [[String: Any]],
                  let configuration = SpaceConfigurationIntegrityPolicy.configurationData(payload) else { return nil }
            state.submission = .init(id: UUID(), timestamp: timestamp, configuration: configuration)
            state.siteCreationTimestamp = siteCreationTimestamp
            try saveState(state, space: space)
            return state
        } catch { return nil }
    }

    static func discardUnsentSubmission(_ context: SpaceRecoveryState, space: SpaceData) {
        lock.lock(); defer { lock.unlock() }
        guard var state = try? recoveryState(space), state.matches(context),
              state.submission?.id == context.submission?.id, state.submission?.phase == .prepared else { return }
        state.submission = nil
        state.siteCreationTimestamp = nil
        try? saveState(state, space: space)
    }

    static func markSubmissionAccepted(_ context: SpaceRecoveryState, space: SpaceData) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard isCurrent(context, space: space), state.submission?.id == context.submission?.id else { return false }
            state.submission?.phase = .accepted
            try saveState(state, space: space)
            return true
        } catch { return false }
    }

    /// A definite server rejection must not leave an unknown-outcome receipt.
    static func rejectSubmission(_ context: SpaceRecoveryState, space: SpaceData, error: NetworkApiError) {
        guard isCurrent(context, space: space) else { return }
        handleAuthorityError(error, space: space)
        switch error {
        case .noSitePermission, .noSpacePermission, .userUnauthorized, .incorrectPassword, .spacePasswordOverdue,
             .resourceNotFound: break
        default: return
        }
        lock.lock(); defer { lock.unlock() }
        guard var state = try? recoveryState(space), state.matches(context),
              state.submission?.id == context.submission?.id else { return }
        state.submission = nil
        try? saveState(state, space: space)
    }

    private static func finishSubmission(_ context: SpaceRecoveryState, space: SpaceData) -> Bool {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard isCurrent(context, space: space), let submission = state.submission,
                  submission.id == context.submission?.id, submission.phase == .verified else { return false }
            guard confirmLocalChanges(space, payload: ["updateTimestamp": submission.timestamp,
                                                       "nodes": [[String: Any]]()]) else { return false }
            let previous = space.lastUploadCloudTimestamp
            space.lastUploadCloudTimestamp = SpaceConfigurationIntegrityPolicy.confirmedTimestamp(
                previous: previous, submitted: submission.timestamp)
            space.syncCloudError = nil
            guard space.save() else { space.lastUploadCloudTimestamp = previous; return false }
            // Establish the baseline on FIRST upload too; otherwise adding the next
            // device compares the changed local topology to the pre-add cloud copy.
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            state.authorizationBaseline = readbackConfiguration(submission.configuration, timestamp: submission.timestamp, space: space)
            state.submission = nil
            try saveState(state, space: space)
            let blockedKey = "spaceConfigurationBlocked." + key(space)
            if ["uploadReadbackUnconfirmed", "uploadReadbackConflict"].contains(UserDefaults.standard.string(forKey: blockedKey) ?? "") {
                UserDefaults.standard.removeObject(forKey: blockedKey)
            }
            return true
        } catch { return false }
    }

    /// Reconcile the saved submission without exporting or writing to the server.
    @MainActor
    static func resumeUpload(_ space: SpaceData) async -> Swift.Result<Void, NetworkApiError> {
        do {
            try migratePendingUpload(space)
            var context = try recoveryState(space)
            guard context.phase == .active else { return .failure(uploadUnconfirmed) }
            guard context.authority == .writable else { return .failure(authorityError(space)) }
            guard let submission = context.submission else { return .success(()) }
            if submission.phase == .verified {
                return finishSubmission(context, space: space) ? .success(()) : .failure(uploadUnconfirmed)
            }
            for attempt in 0..<3 {
                guard !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(context, space: space) else {
                    return .failure(uploadUnconfirmed)
                }
                let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
                    spaceId: space.id, password: space.authorizationPassword))
                guard !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(context, space: space) else {
                    return .failure(uploadUnconfirmed)
                }
                switch response {
                case .failure(let error):
                    handleAuthorityError(error, space: space)
                    print("[SpaceConfigurationReadback] space=\(space.id) submitted=\(submission.timestamp) result=unavailable code=\(error.code)")
                    return .failure(error)
                case .success(let response):
                    guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id,
                          let configuration = SpaceConfigurationIntegrityPolicy.configurationData(remote),
                          remote["nodes"] is [[String: Any]] else { return .failure(uploadUnconfirmed) }
                    space.applyRemoteSpaceMetadata(remote)
                    guard space.save(), isCurrent(context, space: space), canAutomaticallyUpload(space) else {
                        return .failure(authorityError(space))
                    }
                    let expected = readbackConfiguration(submission.configuration, timestamp: submission.timestamp, space: space)
                    if SpaceConfigurationIntegrityPolicy.configurationsMatch(configuration, expected) {
                        context = try recoveryState(space)
                        guard context.submission?.id == submission.id else { return .failure(uploadUnconfirmed) }
                        context.submission?.phase = .verified
                        try saveState(context, space: space)
                        return finishSubmission(context, space: space) ? .success(()) : .failure(uploadUnconfirmed)
                    }
                    print("[SpaceConfigurationReadback] source=resume site=\(space.siteId) space=\(space.id) "
                        + "submissionId=\(submission.id.uuidString) phase=\(submission.phase.rawValue) "
                        + "submitted=\(submission.timestamp) localTimestamp=\(space.lastUpdate) "
                        + "attempt=\(attempt + 1) result=mismatch "
                        + SpaceConfigurationIntegrityPolicy.readbackDiagnostic(
                            submittedConfiguration: expected, remote: remote))
                    // A cancelled pre-send operation can be replaced only if the
                    // cloud still matches the last confirmed baseline.
                    if attempt == 2, submission.phase == .prepared,
                       SpaceConfigurationIntegrityPolicy.configurationsMatch(configuration, context.authorizationBaseline.map {
                           readbackConfiguration($0, timestamp: space.lastUploadCloudTimestamp ?? 0, space: space)
                       }) {
                        context.submission = nil
                        try saveState(context, space: space)
                        return .success(())
                    }
                }
                if attempt < 2 { try await _Concurrency.Task<Never, Never>.sleep(nanoseconds: 500_000_000) }
            }
            block(space, reason: "uploadReadbackConflict")
            return .failure(uploadUnconfirmed)
        } catch { return .failure(uploadUnconfirmed) }
    }

    /// A later proven handoff supersedes only the old device membership in an
    /// earlier submission. Its newer cleanup receipt still requires a new upload.
    private static func readbackConfiguration(_ data: Data, timestamp: Int64, space: SpaceData) -> Data {
        guard let journal = try? deletionJournal(space),
              var configuration = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let memberships = configuration["memberships"] as? [[String: Any]] else { return data }
        let moved = journal.entries.filter {
            $0.replacement != nil && $0.stage == .cleaned && ($0.completedTimestamp ?? 0) > timestamp
        }
        guard !moved.isEmpty else { return data }
        configuration["memberships"] = memberships.filter { member in
            !moved.contains(where: {
                $0.nodeUUID == member["uuid"] as? String && String(format: "%04X", $0.primaryAddress) == member["unicastAddress"] as? String
            })
        }
        return (try? JSONSerialization.data(withJSONObject: configuration, options: [.sortedKeys])) ?? data
    }

    private static func migratePendingUpload(_ space: SpaceData) throws {
        lock.lock(); defer { lock.unlock() }
        var state = try recoveryState(space)
        guard state.phase == .active, state.submission == nil,
              UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) == "uploadReadbackUnconfirmed" else { return }
        let url = try directory(space).appendingPathComponent("last-complete-export.json")
        guard let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
              payload["uuid"] as? String == space.id, payload["nodes"] is [[String: Any]],
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(payload["updateTimestamp"]),
              let configuration = SpaceConfigurationIntegrityPolicy.configurationData(payload) else { throw SafetyError.invalidCheckpoint }
        state.submission = .init(id: UUID(), timestamp: timestamp, configuration: configuration, phase: .accepted)
        try saveState(state, space: space)
    }

    @MainActor
    static func uploadBeforeUnbind(_ space: SpaceData) async -> Swift.Result<Void, NetworkApiError> {
        let resumed = await resumeUpload(space)
        if case .failure = resumed { return resumed }
        guard space.needUploadCloud else { return .success(()) }
        guard canAutomaticallyUpload(space), let payload = await space.export(purpose: .cloudSync),
              let context = prepareSubmission(space, payload: payload) else { return .failure(uploadUnconfirmed) }
        let response = await NetworkRequest.shared.request(.spaceUpload(siteId: space.siteId, spaceId: space.id, spaceData: payload))
        guard isCurrent(context, space: space) else { return .failure(uploadUnconfirmed) }
        switch response {
        case .failure(let error):
            rejectSubmission(context, space: space, error: error)
            return .failure(error)
        case .success:
            guard markSubmissionAccepted(context, space: space) else { return .failure(uploadUnconfirmed) }
            return await resumeUpload(space)
        }
    }

    static func authorityError(_ space: SpaceData) -> NetworkApiError {
        space.requiresPasswordVerification ? .spacePasswordOverdue : .noSpacePermission
    }

    static func handleAuthorityError(_ error: NetworkApiError, space: SpaceData) {
        switch error {
        case .incorrectPassword, .spacePasswordOverdue:
            space.requiresPasswordVerification = true
            updateAuthority(space, authority: .waitingForAuthorization)
        case .userUnauthorized:
            updateAuthority(space, authority: .waitingForAuthorization)
        case .noSitePermission, .noSpacePermission:
            space.state = .waitDeleted
            updateAuthority(space, authority: .revoked)
        default: return
        }
        space.save()
    }

    /// Metadata is processed even while topology import is protected.
    static func reconcileAuthority(_ space: SpaceData, remote: [String: Any]) {
        guard remote["uuid"] as? String == space.id else { return }
        if space.permission == .visitor { updateAuthority(space, authority: .readOnly); return }
        if space.requiresPasswordVerification || space.disableEditorPermission {
            updateAuthority(space, authority: .waitingForAuthorization)
            return
        }
        guard var state = try? recoveryState(space), state.phase == .active else { return }
        if state.authority == .waitingForAuthorization {
            let remoteConfiguration = SpaceConfigurationIntegrityPolicy.configurationData(remote)
            let baseline = state.authorizationBaseline.map {
                readbackConfiguration($0, timestamp: space.lastUploadCloudTimestamp ?? 0, space: space)
            }
            let pending = state.submission.map {
                readbackConfiguration($0.configuration, timestamp: $0.timestamp, space: space)
            }
            let hasLocalWrites = space.needUploadCloud || state.submission != nil
                || (try? deletionJournal(space).entries.isEmpty) != true
                || UserDefaults.standard.object(forKey: "spaceConfigurationLocalRecoveryPending." + key(space)) != nil
            if remoteConfiguration == nil || (hasLocalWrites
                && !SpaceConfigurationIntegrityPolicy.configurationsMatch(remoteConfiguration, baseline)
                && !SpaceConfigurationIntegrityPolicy.configurationsMatch(remoteConfiguration, pending)) {
                block(space, reason: "authorizationConfigurationChanged")
                return
            }
            if !hasLocalWrites { state.requiresRemoteImport = true }
        }
        state.authority = .writable
        try? saveState(state, space: space)
    }

    private static func updateAuthority(_ space: SpaceData, authority: SpaceRecoveryState.Authority) {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard state.phase == .active, state.authority != authority else { return }
            if authority == .readOnly || authority == .revoked {
                let root = storedDirectory(space, state: state)
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try state.write(to: root.appendingPathComponent("recovery-state.json"))
                // Retain prepared/removed journals as evidence, never mark them cleaned.
                if FileManager.default.fileExists(atPath: root.path) {
                    let archive = recoveryRoot.appendingPathComponent("authority-" + key(space) + "-" + UUID().uuidString)
                    try FileManager.default.copyItem(at: root, to: archive)
                }
                state.generation = UUID()
                state.directoryName = key(space) + "-" + state.generation.uuidString
                state.submission = nil
                state.authorizationBaseline = nil
                state.requiresRemoteImport = true
            }
            state.authority = authority
            try saveState(state, space: space)
            if authority == .readOnly || authority == .revoked { clearActiveMarkers(space) }
        } catch { block(space, reason: "authorityPersistenceFailed") }
    }

    static func configurationAvailable(for node: Node, group: Group? = nil) -> Bool {
        let group = group ?? node.group
        if let group, !group.isVirtual, group.info.profileLoadFailed || group.info.topologyLoadFailed { return false }
        guard let uuid = node.network?.uuid.uuidString,
              let networkId = node.subNetworkId else { return true }
        if node.network?.groups.contains(where: {
            !$0.isVirtual && $0.subNetworkId == networkId
                && ($0.info.profileLoadFailed || $0.info.topologyLoadFailed)
        }) == true { return false }
        return !isBlocked(meshUUID: uuid, networkId: networkId)
    }

    static var currentConfigurationAvailable: Bool {
        let manager = MeshNetworkManager.instance
        guard let uuid = manager.meshNetwork?.uuid.uuidString else { return false }
        let networkId = manager.currentNetworkKey.networkId.hex
        return !isBlocked(meshUUID: uuid, networkId: networkId)
            && manager.groups.filter { !$0.isVirtual && $0.subNetworkId == networkId }
                .allSatisfy { !$0.info.profileLoadFailed && !$0.info.topologyLoadFailed }
    }

    static func needsUpgradeBaseline(_ space: SpaceData) -> Bool {
        space.uploadCloud && !UserDefaults.standard.bool(forKey: "spaceConfigurationMigrated." + key(space))
    }

    static func verifyUpgradeBaseline(_ space: SpaceData, local: [String: Any], remote: [String: Any]) {
        guard !isBlocked(space), let expected = SpaceConfigurationIntegrityPolicy.configurationData(local),
              expected == SpaceConfigurationIntegrityPolicy.configurationData(remote),
              checkpoint(space), recordSnapshot(space, payload: local) else { return }
        UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        if var state = try? recoveryState(space) {
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
            try? saveState(state, space: space)
        }
    }

    static func pendingImport(_ space: SpaceData) -> [String: Any]? {
        guard let url = try? directory(space).appendingPathComponent("pending-import.json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["uuid"] as? String == space.id else { return nil }
        return payload
    }

    static func hasPendingImport(_ space: SpaceData) -> Bool {
        guard let url = try? directory(space).appendingPathComponent("pending-import.json") else { return true }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Preserve both side stores using SQLite's backup API, not a copy of the
    /// main file without its WAL. A read transaction pins each source snapshot.
    static func checkpoint(_ space: SpaceData, refresh: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        do {
            let recoveryRoot = try directory(space)
            let root = refresh ? recoveryRoot.appendingPathComponent("checkpoint-" + UUID().uuidString) : recoveryRoot
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let marker = root.appendingPathComponent("checkpoint-ready")
            if FileManager.default.fileExists(atPath: marker.path) { return true }
            let userDirectory = URL(fileURLWithPath: NSHomeDirectory())
                .appendingPathComponent("Documents").appendingPathComponent(UserData.currentUserId)
            try ConfigurationDatabaseCheckpoint.save(
                appDatabase: userDirectory.appendingPathComponent("sunsmart.sqlite3"),
                meshDatabase: userDirectory.appendingPathComponent("mesh.sqlite3"),
                destination: root
            )
            try Data("1".utf8).write(to: marker, options: .atomic)
            if refresh {
                try Data(root.lastPathComponent.utf8).write(to: recoveryRoot.appendingPathComponent("latest-checkpoint"), options: .atomic)
                let snapshots = try FileManager.default.contentsOfDirectory(at: recoveryRoot,
                    includingPropertiesForKeys: [.creationDateKey, .isDirectoryKey]).filter {
                        $0.lastPathComponent.hasPrefix("checkpoint-")
                            && (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                            && FileManager.default.fileExists(atPath: $0.appendingPathComponent("checkpoint-ready").path)
                    }.sorted {
                        ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                            > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
                    }
                for obsolete in snapshots.filter({ $0 != root }).dropFirst() {
                    try? FileManager.default.removeItem(at: obsolete)
                }
            }
            return true
        } catch {
            print("[SpaceConfigurationSafety] checkpoint failed space=\(space.id) error=\(error)")
            return false
        }
    }

    static func beginImport(_ space: SpaceData, payload: [String: Any]) -> Bool {
        guard checkpoint(space), hasPendingImport(space) || checkpoint(space, refresh: true) else { return false }
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: directory(space).appendingPathComponent("pending-import.json"),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            block(space, reason: "importInProgress")
            return true
        } catch {
            block(space, reason: "importCheckpointFailed")
            return false
        }
    }

    static func finishImport(_ space: SpaceData, validatedTopology: Bool = true) -> Bool {
        do {
            let url = try directory(space).appendingPathComponent("pending-import.json")
            if validatedTopology {
                var state = try recoveryState(space)
                let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
                state.authorizationBaseline = payload.flatMap(SpaceConfigurationIntegrityPolicy.configurationData)
                state.requiresRemoteImport = false
                try saveState(state, space: space)
            }
            if !validatedTopology {
                // Keep the original input for diagnosis without replaying an invalid
                // extension on every launch or treating it as a confirmed baseline.
                try Data(contentsOf: url).write(
                    to: directory(space).appendingPathComponent("unvalidated-import.json"),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            if validatedTopology {
                UserDefaults.standard.removeObject(forKey: "spaceConfigurationBlocked." + key(space))
                UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            } else {
                block(space, reason: "incompleteImportedTopology")
            }
            return true
        } catch { return false }
    }

    @MainActor
    static func prepareUpload(_ space: SpaceData, payload: [String: Any]) async -> Bool {
        guard canAutomaticallyUpload(space), space.permission != .visitor, !space.disableEditorPermission,
              !space.requiresPasswordVerification, !isBlocked(space), !hasPendingImport(space), checkpoint(space),
              (try? recoveryState(space).submission) == nil else { return false }
        if needsUpgradeBaseline(space) {
            // Check the saved pre-edit baseline before overwriting it with the new
            // export. A local addition is expected to differ from the old cloud.
            var baseline = payload
            if let url = try? directory(space).appendingPathComponent("last-complete-export.json"),
               let data = try? Data(contentsOf: url),
               let saved = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               saved["uuid"] as? String == space.id,
               let timestamp = SpaceConfigurationIntegrityPolicy.integer(saved["updateTimestamp"]),
               timestamp == space.lastUploadCloudTimestamp {
                baseline = saved
            }
            switch await readUploadedConfiguration(space, payload: baseline) {
            case .success(true): break
            case .success(false):
                block(space, reason: "upgradeBaselineNeedsImport")
                return false
            case .failure(let error):
                space.syncCloudError = error
                space.save()
                return false
            }
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        }
        return space.permission != .visitor && !space.disableEditorPermission
            && !space.requiresPasswordVerification && !isBlocked(space) && !hasPendingImport(space)
            && recordSnapshot(space, payload: payload)
    }

    static func recordSnapshot(_ space: SpaceData, payload: [String: Any]) -> Bool {
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            try data.write(to: directory(space).appendingPathComponent("last-complete-export.json"),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    /// Called only after the user explicitly chooses this phone's complete
    /// Space as the replacement for the cloud copy. Never bypass a pending import.
    @MainActor
    static func authorizeLocalRecovery(_ space: SpaceData, reviewed: [String: Any],
                                       expectedRemote: Data? = nil, expectedRemoteTimestamp: Int64? = nil) async -> Bool {
        guard let context = try? recoveryState(space), context.phase == .active,
              space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              isBlocked(space), !hasPendingImport(space), !hasPendingDeletionCleanup(space),
              let current = await space.export(allowsProtectedInspection: true),
              SpaceConfigurationIntegrityPolicy.configurationData(current) == SpaceConfigurationIntegrityPolicy.configurationData(reviewed),
              SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]) == SpaceConfigurationIntegrityPolicy.integer(reviewed["updateTimestamp"]) else { return false }
        guard isCurrent(context, space: space) else { return false }
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard isCurrent(context, space: space) else { return false }
        if case .failure(let error) = result { handleAuthorityError(error, space: space) }
        guard case .success(let response) = result, let remote = response["data"] as? [String: Any],
              remote["uuid"] as? String == space.id else { return false }
        space.applyRemoteSpaceMetadata(remote)
        space.save()
        guard let remoteTimestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              expectedRemote == nil || (SpaceConfigurationIntegrityPolicy.configurationData(remote) == expectedRemote
                && remoteTimestamp == expectedRemoteTimestamp),
              remoteTimestamp < Int64.max, space.lastUpdate < Int64.max,
              (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              isBlocked(space), !hasPendingImport(space), !hasPendingDeletionCleanup(space),
              space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              space.lastUpdate == SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]),
              checkpoint(space),
              recordSnapshot(space, payload: current) else { return false }
        do {
            let data = try JSONSerialization.data(withJSONObject: remote, options: [.sortedKeys])
            try data.write(to: directory(space).appendingPathComponent("before-local-recovery-remote.json"),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch { return false }
        let timestamp = space.lastUpdate
        let saved = SunSmartDataManager.shared.configurationTransaction {
            space.lastUpdate = max(space.lastUpdate, remoteTimestamp)
            space.markLocalChangePendingCloudSync()
            guard space.save() else { throw SafetyError.persistenceFailed }
        }
        guard saved else { space.lastUpdate = timestamp; return false }
        // Explicit review supersedes a conflicting submission, not an unrelated
        // topology error. The replacement receives a fresh submission on upload.
        do {
            var state = try recoveryState(space)
            state.submission = nil
            state.authority = .writable
            state.requiresRemoteImport = false
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
            try saveState(state, space: space)
        } catch { return false }
        UserDefaults.standard.set(space.lastUpdate,
            forKey: "spaceConfigurationLocalRecoveryPending." + key(space))
        UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        UserDefaults.standard.removeObject(forKey: "spaceConfigurationBlocked." + key(space))
        MeshNetworkManager.instance.realNodes.filter {
            $0.network?.uuid.uuidString == space.meshUUID && $0.subNetworkId == space.meshNetworkId
        }
            .forEach { $0.clearSyncStateCache() }
        return true
    }

    struct ReferenceRepairReview {
        let original: [String: Any]
        let remote: [String: Any]
        let snapshot: ProximityLightingTopologyReconciler.Snapshot
        let repairCount: Int

        var message: String {
            String(format: "configuration_repair_preview".localizedString,
                (original["nodes"] as? [Any])?.count ?? 0,
                (remote["nodes"] as? [Any])?.count ?? 0, repairCount)
        }
    }

    @MainActor
    static func referenceRepairReview(_ space: SpaceData) async -> ReferenceRepairReview? {
        guard let context = try? recoveryState(space), context.phase == .active,
              isBlocked(space), !hasPendingImport(space),
              space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              let local = await space.export(allowsProtectedInspection: true, reviewingReferenceRepairs: true) else { return nil }
        let preparation = ProximityLightingLifecycleCoordinator.begin(space: space).prepare()
        guard isCurrent(context, space: space), preparation.isValid, preparation.normalized.canReviewReferenceRepair else { return nil }
        let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard isCurrent(context, space: space) else { return nil }
        if case .failure(let error) = response { handleAuthorityError(error, space: space) }
        guard case .success(let result) = response, let remote = result["data"] as? [String: Any],
              remote["uuid"] as? String == space.id else { return nil }
        space.applyRemoteSpaceMetadata(remote)
        space.save()
        guard space.permission != .visitor, !space.disableEditorPermission, !space.requiresPasswordVerification,
              remote["nodes"] is [[String: Any]],
              SpaceConfigurationIntegrityPolicy.configurationData(remote) != nil,
              SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]) != nil,
              checkpoint(space, refresh: true),
              saveRecoveryPayload(space, name: "before-reference-repair-local.json", payload: local),
              saveRecoveryPayload(space, name: "before-reference-repair-remote.json", payload: remote) else { return nil }
        return .init(original: local, remote: remote, snapshot: preparation.sourceSnapshot,
                     repairCount: preparation.normalized.repairs.count)
    }

    private static func saveRecoveryPayload(_ space: SpaceData, name: String, payload: [String: Any]) -> Bool {
        do {
            try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(
                to: directory(space).appendingPathComponent(name),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    @MainActor
    static func applyReferenceRepair(_ space: SpaceData, review: ReferenceRepairReview) async -> Bool {
        guard isBlocked(space), !hasPendingImport(space),
              space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              let current = await space.export(allowsProtectedInspection: true, reviewingReferenceRepairs: true),
              SpaceConfigurationIntegrityPolicy.configurationData(current) == SpaceConfigurationIntegrityPolicy.configurationData(review.original),
              SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]) == SpaceConfigurationIntegrityPolicy.integer(review.original["updateTimestamp"]),
              let expectedRemote = SpaceConfigurationIntegrityPolicy.configurationData(review.remote),
              let expectedTimestamp = SpaceConfigurationIntegrityPolicy.integer(review.remote["updateTimestamp"]) else { return false }
        let preparation = ProximityLightingLifecycleCoordinator.begin(space: space).prepare()
        guard preparation.sourceSnapshot == review.snapshot, preparation.isValid,
              space.lastUpdate < Int64.max, (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              expectedTimestamp < Int64.max,
              space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              preparation.normalized.canReviewReferenceRepair,
              checkpoint(space, refresh: true) else { return false }
        // Retain the user's chosen source across interruption and cloud retries.
        UserDefaults.standard.set(Int64.max, forKey: "spaceConfigurationLocalRecoveryPending." + key(space))
        guard ProximityLightingLifecycleCoordinator.commit(preparation,
            reviewedReferenceSnapshot: review.snapshot) != nil else { return false }
        DevicePermanentDeletionContext.resume(space: space)
        guard !hasPendingDeletionCleanup(space),
              let persisted = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              let repaired = await persisted.export(allowsProtectedInspection: true),
              recordSnapshot(space, payload: repaired) else { return false }
        space.lastUpdate = persisted.lastUpdate
        let accepted = await authorizeLocalRecovery(space, reviewed: repaired,
            expectedRemote: expectedRemote, expectedRemoteTimestamp: expectedTimestamp)
        if accepted {
            NotificationCenter.default.post(name: .init(proximityLightingImportSyncNotificationName),
                object: ProximityLightingImportSyncRequest(spaceId: space.id, meshUUID: space.meshUUID, networkId: space.meshNetworkId))
        }
        return accepted
    }

    enum SafetyError: Error { case invalidCheckpoint, persistenceFailed }
}

/// Kept independent of App state so WAL, rollback and failed checkpoints can be
/// exercised against real temporary databases without a device or server.
struct ConfigurationDatabaseCheckpoint {
    enum Failure: Error { case invalidDatabase }

    static func save(appDatabase: URL, meshDatabase: URL, destination: URL) throws {
        let app = try Connection(appDatabase.path, readonly: true)
        let mesh = try Connection(meshDatabase.path, readonly: true)
        try app.transaction {
            _ = try app.scalar("SELECT COUNT(*) FROM sqlite_master")
            try mesh.transaction {
                _ = try mesh.scalar("SELECT COUNT(*) FROM sqlite_master")
                for (source, name) in [(app, "sunsmart.sqlite3"), (mesh, "mesh.sqlite3")] {
                    let url = destination.appendingPathComponent(name)
                    let target = try Connection(url.path)
                    try Backup(sourceConnection: source, targetConnection: target).step()
                    guard try target.scalar("PRAGMA integrity_check") as? String == "ok" else {
                        throw Failure.invalidDatabase
                    }
#if os(iOS)
                    try FileManager.default.setAttributes(
                        [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                        ofItemAtPath: url.path)
#endif
                }
            }
        }
    }
}

enum ProfileStorageCompatibility {
    static func preservedColumns(db: Connection, table: Table, tableName: String,
                                 identity: SQLite.Expression<Bool>) throws -> [Setter] {
        guard try db.schema.columnDefinitions(table: tableName).contains(where: { $0.name == "regulatorAccuracy" }) else { return [] }
        let legacy = SQLite.Expression<Int>("regulatorAccuracy")
        let previous = try db.pluck(table.filter(identity))
        return [legacy <- (previous?[legacy] ?? 0x14)]
    }
}
