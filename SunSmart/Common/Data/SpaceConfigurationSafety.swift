import Foundation
import NordicSigMeshSDK
import SQLite
import CryptoKit

/// The Mesh identity required by a complete Space upload. Never log the key material.
enum SpaceKeyIntegrity {
    struct Pair {
        let network: NetworkKey
        let application: ApplicationKey

        var fingerprint: String {
            var bytes = Data()
            for value in [network.index, application.index, application.boundNetworkKeyIndex] {
                bytes.append(UInt8(value >> 8)); bytes.append(UInt8(value & 0xff))
            }
            bytes.append(network.oldKey == nil ? 0 : 1)
            bytes.append(application.oldKey == nil ? 0 : 1)
            bytes.append(network.key)
            bytes.append(network.oldKey ?? Data())
            bytes.append(application.key)
            bytes.append(application.oldKey ?? Data())
            bytes.append(UInt8(network.phase.rawValue))
            return Data(SHA256.hash(data: bytes)).hex
        }
    }

    static func valid(_ key: NetworkKey) -> Bool {
        key.index < 4096 && key.key.count == 16 && (key.oldKey == nil || key.oldKey?.count == 16)
            && key.networkId.count == 8
    }

    static func valid(_ key: ApplicationKey) -> Bool {
        key.index < 4096 && key.boundNetworkKeyIndex < 4096 && key.key.count == 16
            && (key.oldKey == nil || key.oldKey?.count == 16)
    }

    static func same(_ lhs: NetworkKey, _ rhs: NetworkKey) -> Bool {
        lhs.index == rhs.index && lhs.key == rhs.key && lhs.oldKey == rhs.oldKey && lhs.phase == rhs.phase
    }

    static func same(_ lhs: ApplicationKey, _ rhs: ApplicationKey) -> Bool {
        lhs.index == rhs.index && lhs.boundNetworkKeyIndex == rhs.boundNetworkKeyIndex
            && lhs.key == rhs.key && lhs.oldKey == rhs.oldKey
    }

    private static func hasValidHexKey(_ object: [String: Any]) -> Bool {
        func valid(_ value: Any?) -> Bool {
            guard let value = value as? String, value.utf8.count == 32 else { return false }
            return value.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }
        }
        let old = object["oldKey"]
        return valid(object["key"]) && (old == nil || old is NSNull || valid(old))
    }

    static func decodeNetwork(_ payload: [String: Any]) -> NetworkKey? {
        guard let object = payload["netKey"] as? [String: Any], hasValidHexKey(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(NetworkKey.self, from: data)).flatMap { valid($0) ? $0 : nil }
    }

    static func decodeApplication(_ payload: [String: Any]) -> ApplicationKey? {
        guard let object = payload["appKey"] as? [String: Any], hasValidHexKey(object),
              let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
        return (try? JSONDecoder().decode(ApplicationKey.self, from: data)).flatMap { valid($0) ? $0 : nil }
    }

    static func pair(_ payload: [String: Any], networkID: String) -> Pair? {
        guard let network = decodeNetwork(payload), let application = decodeApplication(payload),
              network.networkId.hex == networkID, application.boundNetworkKeyIndex == network.index,
              (payload["appKeyIndex"] == nil || SpaceConfigurationIntegrityPolicy.integer(payload["appKeyIndex"]) == Int64(application.index))
        else { return nil }
        return Pair(network: network, application: application)
    }

    static func pair(_ network: MeshNetwork, networkID: String, applicationIndex: KeyIndex? = nil) -> Pair? {
        guard let key = network.networkKeys.first(where: { $0.networkId.hex == networkID && valid($0) }),
              let app = network.applicationKeys.first(where: {
                  $0.boundNetworkKeyIndex == key.index && valid($0)
                      && (applicationIndex == nil || $0.index == applicationIndex)
              })
        else { return nil }
        return Pair(network: key, application: app)
    }

    static func presentServerKeysMatchLocal(_ payload: [String: Any], local: Pair) -> Bool {
        let hasNetwork = payload["netKey"] != nil
        let hasApplication = payload["appKey"] != nil
        guard hasNetwork != hasApplication,
              (payload["appKeyIndex"] == nil ||
                  SpaceConfigurationIntegrityPolicy.integer(payload["appKeyIndex"]) == Int64(local.application.index)) else { return false }
        if hasNetwork {
            guard let key = decodeNetwork(payload), same(key, local.network) else { return false }
        }
        if hasApplication {
            guard let key = decodeApplication(payload), same(key, local.application) else { return false }
        }
        return true
    }

    /// Site metadata may be held while child Space imports persist new keys.
    @MainActor
    static func saveSiteNetworkPreservingKeys(_ network: MeshNetwork, meshUUID: String) -> Bool {
        guard let latest = MeshNetwork.load(meshUUID: meshUUID, allData: false) else { return false }
        for key in latest.networkKeys {
            if let existing = network.networkKeys.first(where: { $0.index == key.index }) {
                guard same(existing, key) else { return false }
            } else {
                network.add(networkKey: key)
            }
        }
        for key in latest.applicationKeys {
            if let existing = network.applicationKeys.first(where: { $0.index == key.index }) {
                guard same(existing, key) else { return false }
            } else {
                network.add(applicationKey: key)
            }
        }
        return network.save()
    }

    /// Runs synchronously on the main actor so two Space imports cannot save stale key arrays.
    @MainActor
    static func replenish(_ space: SpaceData, from remote: Pair) -> Bool {
        guard let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              remote.network.networkId.hex == space.meshNetworkId else { return false }
        let manager = MeshNetworkManager.instance
        let active = manager.meshNetwork?.uuid.uuidString == space.meshUUID ? manager.meshNetwork : nil
        for snapshot in [network, active].compactMap({ $0 }) {
            if let old = snapshot.networkKeys.first(where: { $0.index == remote.network.index }),
               !same(old, remote.network) { return false }
            if let old = snapshot.applicationKeys.first(where: { $0.index == remote.application.index }),
               !same(old, remote.application) { return false }
            if snapshot.networkKeys.contains(where: { $0.networkId.hex == space.meshNetworkId && $0.index != remote.network.index }) {
                return false
            }
        }
        let hasNetwork = network.networkKeys.contains(where: { $0.index == remote.network.index })
        let hasApplication = network.applicationKeys.contains(where: { $0.index == remote.application.index })
        if !hasNetwork { network.add(networkKey: remote.network) }
        if !hasApplication { network.add(applicationKey: remote.application) }
        if !hasNetwork || !hasApplication {
            guard network.save(), let reloaded = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                  let confirmed = pair(reloaded, networkID: space.meshNetworkId,
                                       applicationIndex: remote.application.index),
                  confirmed.fingerprint == remote.fingerprint else { return false }
        }
        if let active {
            if !active.networkKeys.contains(where: { $0.index == remote.network.index }) { active.add(networkKey: remote.network) }
            if !active.applicationKeys.contains(where: { $0.index == remote.application.index }) { active.add(applicationKey: remote.application) }
        }
        return true
    }
}

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
        if var state = try SpaceRecoveryState.read(from: stateURL(space), identity: identity(space)) {
            let previous = state
            upgradeSceneComparison(&state, space: space)
            if state != previous { try saveState(state, space: space) }
            return state
        }
        let state = SpaceRecoveryState(identity: identity(space))
        try saveState(state, space: space)
        return state
    }

    private static func upgradeSceneComparison(_ state: inout SpaceRecoveryState, space: SpaceData) {
        guard state.phase == .active,
              SpaceConfigurationIntegrityPolicy.needsSceneComparisonUpgrade(state.authorizationBaseline)
                || SpaceConfigurationIntegrityPolicy.needsSceneComparisonUpgrade(state.submission?.configuration),
              let data = try? Data(contentsOf: storedDirectory(space, state: state).appendingPathComponent("last-complete-export.json")),
              let snapshot = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              snapshot["uuid"] as? String == space.id,
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(snapshot["updateTimestamp"]),
              let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let local = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId),
              SpaceKeyIntegrity.pair(snapshot, networkID: space.meshNetworkId)?.fingerprint == local.fingerprint else { return }
        if timestamp == space.lastUploadCloudTimestamp, let old = state.authorizationBaseline,
           let upgraded = SpaceConfigurationIntegrityPolicy.upgradingSceneComparison(old, snapshot: snapshot) {
            state.authorizationBaseline = upgraded
        }
        if var submission = state.submission, submission.timestamp == timestamp,
           submission.keyFingerprint.map({ $0 == local.fingerprint }) ?? true,
           let upgraded = SpaceConfigurationIntegrityPolicy.upgradingSceneComparison(submission.configuration, snapshot: snapshot) {
            submission.configuration = upgraded
            state.submission = submission
        }
    }

    private static func saveState(_ state: SpaceRecoveryState, space: SpaceData) throws {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
        guard !SpaceMembershipCoordinator.isLeaving(space),
              context.identity == identity(space), let state = try? recoveryState(space) else { return false }
        return state.matches(context)
    }

    static func saveSceneRestoreReceipts(_ data: Data, context: SpaceRecoveryState, space: SpaceData) throws {
        lock.lock(); defer { lock.unlock() }
        guard isCurrent(context, space: space) else { throw SafetyError.invalidCheckpoint }
        var state = try recoveryState(space)
        state.sceneRestoreReceipts = data
        try saveState(state, space: space)
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

    static func isBlocked(meshUUID: String, networkId: String, excludingDeletionEntries: Set<UUID> = []) -> Bool {
        let identity = key(meshUUID: meshUUID, networkId: networkId)
        let stateURL = recoveryRoot.appendingPathComponent(identity + ".json")
        var directoryName = identity
        if FileManager.default.fileExists(atPath: stateURL.path) {
            guard let data = try? Data(contentsOf: stateURL),
                  let state = try? JSONDecoder().decode(SpaceRecoveryState.self, from: data) else { return true }
            if state.phase != .active || state.unbindRequested == true { return true }
            directoryName = state.directoryName ?? identity
        }
        let pending = recoveryRoot.appendingPathComponent(directoryName).appendingPathComponent("pending-import.json")
        return UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + identity) != nil
            || FileManager.default.fileExists(atPath: pending.path)
            || FileManager.default.fileExists(atPath: pending.deletingLastPathComponent().appendingPathComponent("reviewed-cloud-import.json").path)
            || FileManager.default.fileExists(atPath: pending.deletingLastPathComponent().appendingPathComponent("pending-reference-cleanup.json").path)
            || deletionCleanupPending(at: pending.deletingLastPathComponent().appendingPathComponent("device-deletions.json"),
                                      excludingEntries: excludingDeletionEntries)
    }

    static func isBlocked(_ space: SpaceData, excludingDeletionEntries: Set<UUID> = []) -> Bool {
        isBlocked(meshUUID: space.meshUUID, networkId: space.meshNetworkId, excludingDeletionEntries: excludingDeletionEntries)
    }

    static func block(_ space: SpaceData, reason: String) {
        block(meshUUID: space.meshUUID, networkId: space.meshNetworkId, reason: reason)
        #if DEBUG
        print("[SpaceConfigurationSafety] blocked space=\(space.id) reason=\(reason)")
        #endif
        MeshNetworkManager.instance.realNodes.filter {
            $0.network?.uuid.uuidString == space.meshUUID && $0.subNetworkId == space.meshNetworkId
        }
            .forEach { $0.clearSyncStateCache() }
    }

    static func block(meshUUID: String, networkId: String, reason: String) {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        let identity = "spaceConfigurationBlocked." + key(meshUUID: meshUUID, networkId: networkId)
        // Keep the first cause; subsequent entry checks are consequences.
        if UserDefaults.standard.string(forKey: identity) == nil {
            UserDefaults.standard.set(reason, forKey: identity)
        }
    }

    static func deletionScope(_ space: SpaceData) -> SpaceDeletionJournal.Scope {
        .init(siteId: space.siteId, spaceId: space.id, meshUUID: space.meshUUID, networkId: space.meshNetworkId)
    }

    private static func deletionCleanupPending(at url: URL, excludingEntries: Set<UUID> = []) -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard let data = try? Data(contentsOf: url),
              let journal = try? JSONDecoder().decode(SpaceDeletionJournal.self, from: data) else { return true }
        return journal.entries.contains { $0.stage != .cleaned && !excludingEntries.contains($0.id) }
    }

    static func deletionJournal(_ space: SpaceData) throws -> SpaceDeletionJournal {
        lock.lock(); defer { lock.unlock() }
        return try .read(from: directory(space).appendingPathComponent("device-deletions.json"),
                         scope: deletionScope(space))
    }

    @discardableResult
    static func updateDeletionJournal(_ space: SpaceData, _ update: (inout SpaceDeletionJournal) -> Void) -> Bool {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
            #if DEBUG
            print("[DevicePermanentDeletion] journal failed space=\(space.id) error=\(error)")
            #endif
            return false
        }
    }

    static func hasPendingDeletionCleanup(_ space: SpaceData) -> Bool {
        (try? deletionJournal(space).needsCleanup) ?? true
    }

    private static let referenceCleanupReasons: Set<String> = [
        "invalidRemoteTopology", "entryTopologyNeedsReview", "incompleteImportedTopology",
        "deletionCleanupPending", "referenceCleanupPending"
    ]

    static func canCleanSyncReferences(_ space: SpaceData) -> Bool {
        guard space.state == .normal, space.permission != .visitor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              !hasPendingImport(space), let state = try? recoveryState(space),
              state.phase == .active, state.authority == .writable,
              state.requiresRemoteImport != true, state.unbindRequested != true,
              state.submission == nil else { return false }
        let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space))
        return reason == nil || referenceCleanupReasons.contains(reason!)
    }

    static func configurationSyncError(_ space: SpaceData) -> NetworkApiError {
        if space.requiresPasswordVerification { return .spacePasswordOverdue }
        if space.permission == .visitor || space.disableEditorPermission { return .noSpacePermission }
        let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space))
        if reason == "invalidStoredGroupConfiguration" || hasPendingImport(space) { return .configurationUnavailable }
        if requiresConfigurationReview(space) { return .configurationReviewRequired }
        return .configurationUnavailable
    }

    @discardableResult
    static func recordSyncFailure(_ space: SpaceData, error: NetworkApiError, stage: String,
                                  remoteTimestamp: Int64? = nil) -> Bool {
        // The cloud operation persists its final error. Do not save a possibly
        // stale Space object merely to report a failed preparation/export.
        space.syncCloudError = error
        #if DEBUG
        let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) ?? "none"
        var diagnostic: [String: Any] = ["stage": stage, "error": error.code, "localTimestamp": space.lastUpdate,
            "recordedAt": Int64(Date().timeIntervalSince1970)]
        diagnostic["remoteTimestamp"] = remoteTimestamp
        UserDefaults.standard.set(diagnostic, forKey: "spaceConfigurationLastSyncDiagnostic." + key(space))
        print("[SpaceConfigurationSync] stage=\(stage) error=\(error.code) reason=\(reason)")
        #endif
        return false
    }

    /// Entry cleanup must be able to resolve an old membership conflict before
    /// its ordinary protection gate. Reuse the same GET/readback as uploads.
    @MainActor
    static func recoverCloudMembershipIfNeeded(_ space: SpaceData) async -> Bool {
        let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space))
        guard reason == "cloudConfigurationConflict" || reason == "cloudBaselineNeedsReview" else { return true }
        guard canAutomaticallyUpload(space), !hasPendingImport(space), !hasPendingUpload(space),
              !_Concurrency.Task<Never, Never>.isCancelled else { return false }
        if case .failure(let error) = await resumeUpload(space) {
            space.syncCloudError = error
            return false
        }
        return !isBlocked(space) && canAutomaticallyUpload(space)
            && !_Concurrency.Task<Never, Never>.isCancelled
    }

    /// Recheck only known legacy comparison/empty-Zone blocks. Never use this path to
    /// clear an import, deletion, changed configuration, or a different cause.
    @MainActor
    static func recoverUpgradeBaselineIfNeeded(_ space: SpaceData,
                                               readLocal: () async -> [String: Any]?) async -> Bool {
        let reasonKey = "spaceConfigurationBlocked." + key(space)
        guard let reason = UserDefaults.standard.string(forKey: reasonKey),
              reason == "upgradeBaselineNeedsImport" || reason == "legacySpaceZoneDeletionNeedsReview" else { return true }
        func eligible() -> Bool {
            guard !_Concurrency.Task<Never, Never>.isCancelled,
                  UserDefaults.standard.string(forKey: reasonKey) == reason,
                  canAutomaticallyUpload(space), !space.needUploadCloud,
                  !space.triggerZonesLoadFailed,
                  space.lastUploadCloudTimestamp == space.lastUpdate,
                  !hasPendingImport(space), !hasPendingReferenceCleanup(space),
                  let journal = try? deletionJournal(space), journal.entries.isEmpty,
                  let state = try? recoveryState(space), state.submission == nil,
                  UserDefaults.standard.object(forKey: "spaceConfigurationLocalRecoveryPending." + key(space)) == nil
            else { return false }
            return true
        }
        guard eligible(), let context = try? recoveryState(space) else { return false }
        let revision = space.lastUpdate
        guard let local = await readLocal(), eligible(), isCurrent(context, space: space),
              space.lastUpdate == revision, local["uuid"] as? String == space.id,
              SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"]) == revision,
              reason != "legacySpaceZoneDeletionNeedsReview"
                || SpaceConfigurationIntegrityPolicy.hasOnlyEmptySpaceZones(local),
              let expected = SpaceSyncCleanupPolicy.upgradeRecoveryConfiguration(local),
              let expectedNodes = SpaceCloudNodeRemovalPolicy.instances(local),
              let captured = try? JSONSerialization.data(withJSONObject: local, options: [.sortedKeys]) else { return false }
        let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard eligible(), isCurrent(context, space: space), space.lastUpdate == revision else { return false }
        if case .failure(let error) = response {
            handleAuthorityError(error, space: space)
            return recordSyncFailure(space, error: error, stage: "upgradeRecoveryRequest")
        }
        guard case .success(let response) = response,
              let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id else { return false }
        guard SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]) == space.lastUploadCloudTimestamp,
              let actual = SpaceSyncCleanupPolicy.upgradeRecoveryConfiguration(remote), expected == actual,
              let actualNodes = SpaceCloudNodeRemovalPolicy.instances(remote),
              expectedNodes.sorted(by: { $0.uuid < $1.uuid }) == actualNodes.sorted(by: { $0.uuid < $1.uuid }) else { return false }
        // Timestamp alone cannot detect same-second edits or changed persisted data.
        guard let current = await readLocal(), eligible(), isCurrent(context, space: space),
              space.lastUpdate == revision,
              captured == (try? JSONSerialization.data(withJSONObject: current, options: [.sortedKeys])),
              checkpoint(space), recordSnapshot(space, payload: current) else { return false }
        space.applyRemoteSpaceMetadata(remote)
        guard space.save(), eligible(), isCurrent(context, space: space) else { return false }
        do {
            var state = try recoveryState(space)
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
            state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(remote)
            state.nodeIdentitiesBaseline = actualNodes
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(remote)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
            try saveState(state, space: space)
            let previousError = space.syncCloudError
            space.syncCloudError = nil
            guard space.save() else { space.syncCloudError = previousError; return false }
            SpaceProtectionReadGeneration.beginMutation()
            defer { SpaceProtectionReadGeneration.endMutation() }
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            UserDefaults.standard.removeObject(forKey: reasonKey)
            MeshNetworkManager.instance.realNodes.filter {
                $0.network?.uuid.uuidString == space.meshUUID && $0.subNetworkId == space.meshNetworkId
            }.forEach { $0.clearSyncStateCache() }
            #if DEBUG
            print("[SpaceConfigurationSync] stage=upgradeRecovery result=equivalentLegacyConfiguration")
            #endif
            return true
        } catch { return false }
    }

    /// Establish the pre-cleanup version before changing anything. A deletion
    /// receipt proves only that specific absent instance, never arbitrary loss.
    @MainActor
    static func verifySyncCleanupBaseline(_ space: SpaceData, local: [String: Any]) async -> Bool {
        guard canCleanSyncReferences(space) else { return false }
        guard needsUpgradeBaseline(space) else { return true }
        guard let context = try? recoveryState(space), let journal = try? deletionJournal(space),
              let localNodes = local["nodes"] as? [[String: Any]] else { return false }
        let present = Set(localNodes.compactMap { ($0["uuid"] as? String)?.uppercased() })
        let elements = Set(localNodes.flatMap { node -> [UInt16] in
            guard let primary = SpaceSyncCleanupPolicy.address(node["unicastAddress"]),
                  let elements = node["elements"] as? [Any] else { return [] }
            return elements.indices.compactMap { UInt16(exactly: Int(primary) + $0) }
        })
        let deleted = Set(journal.entries.filter {
            !present.contains($0.nodeUUID.uppercased()) && elements.isDisjoint(with: $0.elementAddresses)
        }.map { $0.nodeUUID.uppercased() })
        var baseline = local
        if let data = try? Data(contentsOf: directory(space).appendingPathComponent("last-complete-export.json")),
           let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           saved["uuid"] as? String == space.id,
           SpaceConfigurationIntegrityPolicy.integer(saved["updateTimestamp"]) == space.lastUploadCloudTimestamp {
            baseline = saved
        }
        let revision = space.lastUpdate
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id,
                                                                   password: space.authorizationPassword))
        guard !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(context, space: space),
              space.lastUpdate == revision else { return false }
        if case .failure(let error) = result {
            handleAuthorityError(error, space: space)
            return recordSyncFailure(space, error: error, stage: "cleanupBaselineRequest")
        }
        guard case .success(let response) = result, let remote = response["data"] as? [String: Any],
              remote["uuid"] as? String == space.id else { return false }
        space.applyRemoteSpaceMetadata(remote)
        guard space.save(), canCleanSyncReferences(space) else { return false }
        guard let expected = SpaceSyncCleanupPolicy.baseline(baseline, excludingDeletedUUIDs: deleted),
              let actual = SpaceSyncCleanupPolicy.baseline(remote, excludingDeletedUUIDs: deleted) else {
            return recordSyncFailure(space, error: .configurationExportInvalid, stage: "cleanupBaselineValidation")
        }
        guard expected == actual else {
            block(space, reason: "upgradeBaselineNeedsImport")
            return recordSyncFailure(space, error: .configurationReviewRequired, stage: "cleanupBaselineConflict")
        }
        do {
            var state = try recoveryState(space)
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
            state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(remote)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(remote)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
            try saveState(state, space: space)
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            return true
        } catch { return false }
    }

    static func preserveRemoteReferenceCleanup(_ space: SpaceData, payload: [String: Any], candidate: [String: Any]) -> Bool {
        guard payload["uuid"] as? String == space.id else { return false }
        do {
            let raw = try JSONSerialization.data(withJSONObject: payload, options: .sortedKeys)
            try raw.write(to: directory(space).appendingPathComponent("before-remote-reference-cleanup.json"),
                          options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            let receipt = try JSONSerialization.data(withJSONObject: ["original": payload, "candidate": candidate], options: .sortedKeys)
            try receipt.write(to: directory(space).appendingPathComponent("pending-import-reference-cleanup.json"),
                              options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    static func originalReferenceCleanupImport(_ space: SpaceData, candidate: [String: Any]) -> [String: Any]? {
        guard let root = try? directory(space),
              let raw = try? Data(contentsOf: root.appendingPathComponent("pending-import-reference-cleanup.json")),
              let receipt = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any],
              let expected = receipt["candidate"] as? [String: Any],
              let original = receipt["original"] as? [String: Any], original["uuid"] as? String == space.id,
              let actualData = try? JSONSerialization.data(withJSONObject: candidate, options: .sortedKeys),
              let expectedData = try? JSONSerialization.data(withJSONObject: expected, options: .sortedKeys),
              actualData == expectedData else { return nil }
        return original
    }

    static func beginSyncReferenceCleanup(_ space: SpaceData, payload: [String: Any]) -> Bool {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        guard canCleanSyncReferences(space), checkpoint(space, refresh: true) else { return false }
        do {
            let url = try directory(space).appendingPathComponent("pending-reference-cleanup.json")
            if !FileManager.default.fileExists(atPath: url.path) {
                try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]).write(
                    to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            return true
        } catch { return false }
    }

    static func hasPendingReferenceCleanup(_ space: SpaceData) -> Bool {
        guard let root = try? directory(space) else { return true }
        return FileManager.default.fileExists(atPath: root.appendingPathComponent("pending-reference-cleanup.json").path)
    }

    static func finishSyncReferenceCleanup(_ space: SpaceData, changed: Bool) -> Bool {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        guard canCleanSyncReferences(space), !hasPendingDeletionCleanup(space) else { return false }
        do {
            let root = try directory(space)
            let pending = root.appendingPathComponent("pending-reference-cleanup.json")
            if changed || FileManager.default.fileExists(atPath: pending.path) {
                // Keep cleaned local configuration authoritative until its upload
                // is confirmed, including after a crash between the two writes.
                UserDefaults.standard.set(space.lastUpdate, forKey: "spaceConfigurationLocalRecoveryPending." + key(space))
            }
            if space.syncCloudError?.code == -2003 {
                let previous = space.syncCloudError
                space.syncCloudError = nil
                guard space.save() else { space.syncCloudError = previous; return false }
            }
            if FileManager.default.fileExists(atPath: pending.path) {
                try Data(contentsOf: pending).write(to: root.appendingPathComponent("before-reference-cleanup.json"), options: .atomic)
                try FileManager.default.removeItem(at: pending)
            }
            let blockedKey = "spaceConfigurationBlocked." + key(space)
            if let reason = UserDefaults.standard.string(forKey: blockedKey), referenceCleanupReasons.contains(reason) {
                UserDefaults.standard.removeObject(forKey: blockedKey)
            }
            return true
        } catch { return false }
    }

    /// A local Timed migration can precede its cloud upload. Only the exact
    /// confirmed legacy baseline may be ignored; it must never be imported.
    static func isConfirmedTimedBaseline(_ space: SpaceData, remote: [String: Any]) -> Bool {
        guard remote["uuid"] as? String == space.id,
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              timestamp == space.lastUploadCloudTimestamp, timestamp <= space.lastUpdate,
              let state = try? recoveryState(space), state.preservesUpload,
              state.requiresRemoteImport != true, !hasPendingImport(space),
              let timed = state.timedConfigurationBaseline,
              timed == TimedSchedulerPayloadPolicy.canonical(remote),
              SpaceConfigurationIntegrityPolicy.configurationsMatch(
                state.authorizationBaseline, SpaceConfigurationIntegrityPolicy.configurationData(remote)),
              let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let localKeys = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              localKeys.fingerprint == remoteKeys.fingerprint else { return false }
        if let models = state.schedulerModelStatesBaseline {
            guard models == SchedulerModelSnapshot.spaceData(remote) else { return false }
        }
        return true
    }

    /// Backfill old receipts before a pending local cleanup skips import. Local
    /// topology may already differ, so compare against its confirmed receipt.
    static func backfillTimedUpgradeBaseline(_ space: SpaceData, remote: [String: Any]) {
        guard needsTimedUpgradeBaseline(space), remote["uuid"] as? String == space.id,
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              timestamp == space.lastUploadCloudTimestamp, timestamp <= space.lastUpdate,
              var state = try? recoveryState(space), state.preservesUpload,
              state.requiresRemoteImport != true, !hasPendingImport(space),
              SpaceConfigurationIntegrityPolicy.configurationsMatch(
                state.authorizationBaseline, SpaceConfigurationIntegrityPolicy.configurationData(remote)),
              let timed = TimedSchedulerPayloadPolicy.canonical(remote),
              let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let localKeys = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              localKeys.fingerprint == remoteKeys.fingerprint else { return }
        if let models = state.schedulerModelStatesBaseline {
            guard models == SchedulerModelSnapshot.spaceData(remote) else { return }
        }
        if let nodes = state.nodeIdentitiesBaseline {
            guard nodes == SpaceCloudNodeRemovalPolicy.instances(remote) else { return }
        }
        state.timedConfigurationBaseline = timed
        try? saveState(state, space: space)
    }

    /// A GET must not resurrect devices while their explicit deletion or local
    /// recovery is waiting for upload confirmation to finish.
    static func preservesLocalChanges(_ space: SpaceData) -> Bool {
        guard let state = try? recoveryState(space) else { return true }
        guard state.preservesUpload else { return false }
        // Explicit cloud review is durable before import starts. Keep deletion
        // receipts until that import succeeds, but do not let them veto it.
        if reviewedCloudImport(space) != nil { return false }
        guard let journal = try? deletionJournal(space) else { return true }
        return state.prefersLocalMembership == true || state.submission != nil || state.authority == .waitingForAuthorization || !journal.entries.isEmpty
            || hasPendingReferenceCleanup(space)
            || UserDefaults.standard.object(forKey: "spaceConfigurationLocalRecoveryPending." + key(space)) != nil
    }

    @discardableResult
    static func confirmLocalChanges(_ space: SpaceData, payload: [String: Any]) -> Bool {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
            #if DEBUG
            print("[SpaceConfigurationSafety] archive failed space=\(space.id) error=\(error)")
            #endif
            return false
        }
    }

    static func retryArchiveMoves(_ space: SpaceData) {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        lock.lock(); defer { lock.unlock() }
        guard var state = try? recoveryState(space) else { return }
        for name in state.pendingArchives ?? [] {
            guard name == key(space) || name.hasPrefix(key(space) + "-"), !name.contains("/") else { continue }
            let root = recoveryRoot.appendingPathComponent(name)
            let archive = recoveryRoot.appendingPathComponent("archived-" + key(space) + "-" + UUID().uuidString)
            do {
                if FileManager.default.fileExists(atPath: root.path) { try FileManager.default.moveItem(at: root, to: archive) }
                state.pendingArchives?.removeAll { $0 == name }
            } catch {
                #if DEBUG
                print("[SpaceConfigurationSafety] retired archive move pending space=\(space.id) error=\(error)")
                #endif
            }
        }
        try? saveState(state, space: space)
    }

    private static func clearActiveMarkers(_ space: SpaceData) {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
            SpaceMembershipResponseContext.invalidate()
            return true
        } catch { return false }
    }

    static func beginUnbind(_ space: SpaceData) -> SpaceRecoveryState? {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard state.phase == .active else { return nil }
            state.unbindRequested = true
            state.generation = UUID()
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
    private static func readUploadedConfiguration(_ space: SpaceData, payload: [String: Any],
                                                  upgrading: Bool = false) async -> Swift.Result<Bool, NetworkApiError> {
        guard let context = try? recoveryState(space) else { return .failure(uploadUnconfirmed) }
        let revision = space.lastUpdate
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(context, space: space),
              !upgrading || space.lastUpdate == revision else { return .failure(uploadUnconfirmed) }
        switch result {
        case .failure(let error):
            handleAuthorityError(error, space: space)
            return .failure(error)
        case .success(let response):
            let compare = upgrading ? SpaceConfigurationIntegrityPolicy.upgradeConfigurationData
                : SpaceConfigurationIntegrityPolicy.configurationData
            guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id,
                  let expected = compare(payload), let actual = compare(remote),
                  let submittedKeys = SpaceKeyIntegrity.pair(payload, networkID: space.meshNetworkId),
                  let serverKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
                  submittedKeys.fingerprint == serverKeys.fingerprint else { return .failure(uploadUnconfirmed) }
            let schedulesMatch: Bool
            if upgrading {
                schedulesMatch = true
            } else if let targets = SpaceConfigurationIntegrityPolicy.scheduleTargetsData(payload) {
                schedulesMatch = SpaceConfigurationIntegrityPolicy.scheduleTargetsData(remote) == targets
            } else {
                schedulesMatch = false
            }
            let modelsMatch = upgrading || (SchedulerModelSnapshot.spaceData(payload).map {
                SchedulerModelSnapshot.spaceData(remote) == $0
            } ?? false)
            let timedMatch = upgrading || (TimedSchedulerPayloadPolicy.canonical(payload).map {
                TimedSchedulerPayloadPolicy.canonical(remote) == $0
            } ?? false)
            guard schedulesMatch, modelsMatch, timedMatch else { return .success(false) }
            space.applyRemoteSpaceMetadata(remote)
            guard space.save(), isCurrent(context, space: space),
                  !upgrading || canAutomaticallyUpload(space) else { return .failure(uploadUnconfirmed) }
            if expected != actual {
                #if DEBUG
                print("[SpaceConfigurationReadback] source=direct site=\(space.siteId) space=\(space.id) "
                    + "localTimestamp=\(space.lastUpdate) result=mismatch "
                    + SpaceConfigurationIntegrityPolicy.readbackDiagnostic(submitted: payload, remote: remote))
                #endif
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
        guard SpaceMembershipCoordinator.allowsConfiguration(space),
              space.permission != .visitor, !space.requiresPasswordVerification, !space.disableEditorPermission,
              space.state == .normal, let state = try? recoveryState(space), state.phase == .active else { return false }
        return state.authority == .writable && state.unbindRequested != true && state.requiresRemoteImport != true
    }

    /// Readback is not a new write authorization. Old first-upload receipts can
    /// outlive a GET that created an uninitialized membership record.
    static func canResumePendingUpload(_ space: SpaceData) -> Bool {
        pendingUploadResumeIssue(space) == nil
    }

    /// Eligibility schedules an attempt; receipt migration and exact identity
    /// checks happen inside resumeUpload before any readback can be confirmed.
    private static func pendingUploadResumeIssue(_ space: SpaceData) -> String? {
        guard space.state == .normal else { return "spaceState" }
        guard space.permission != .visitor, !space.disableEditorPermission else { return "permission" }
        guard !space.requiresPasswordVerification else { return "password" }
        guard !SpaceMembershipCoordinator.isLeaving(space) else { return "membershipLeavingOrUnreadable" }
        guard !hasPendingImport(space) else { return "pendingImport" }
        guard let state = try? recoveryState(space) else { return "recoveryUnreadable" }
        guard state.phase == .active else { return "recoveryPhase" }
        guard state.authority == .writable else { return "recoveryAuthority" }
        guard state.unbindRequested != true else { return "unbindRequested" }
        guard state.requiresRemoteImport != true else { return "requiresRemoteImport" }
        guard hasPendingUpload(space) else { return "noPendingUpload" }
        if SpaceMembershipCoordinator.allowsConfiguration(space) { return nil }
        guard space.permission == .owner else { return "uninitializedNonOwner" }
        guard let membership = try? SpaceMembershipCoordinator.store.read(SpaceMembershipCoordinator.scope(space)),
              membership.phase == .joined else { return "membershipMissingOrNotJoined" }
        guard membership.networkID == space.meshNetworkId else { return "membershipNetworkMismatch" }
        return nil
    }

    private struct PendingUploadValidationError: Error {
        let reason: String
    }

    private static func sameNodeIdentities(_ lhs: [SpaceCloudNodeRemovalPolicy.Instance]?,
                                           _ rhs: [SpaceCloudNodeRemovalPolicy.Instance]?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.sorted { $0.uuid < $1.uuid } == rhs.sorted { $0.uuid < $1.uuid }
    }

    private static func pendingInitializationIssue(_ space: SpaceData,
                                                   submission: SpaceRecoveryState.Submission) -> String? {
        guard submission.scheduleTargets != nil else { return "missingScheduleTargets" }
        guard submission.timedConfiguration != nil else { return "missingTimedConfiguration" }
        guard submission.schedulerModelStates != nil else { return "missingSchedulerModels" }
        guard submission.nodeIdentities != nil else { return "missingNodeIdentities" }
        guard let fingerprint = submission.keyFingerprint else { return "missingKeyFingerprint" }
        guard let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let keys = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId) else { return "localKeysUnavailable" }
        guard keys.fingerprint == fingerprint else { return "receiptLocalKeyMismatch" }
        return nil
    }

    /// Kept separately from cleanup diagnostics. An older suspended attempt may
    /// not replace a newer attempt's result, and no key material is recorded.
    private static func recordReadbackDiagnostic(_ space: SpaceData, attempt: UUID, stage: String,
                                                 reason: String? = nil, error: NetworkApiError? = nil,
                                                 remoteTimestamp: Int64? = nil) {
        #if DEBUG
        let storageKey = "spaceConfigurationLastReadbackDiagnostic." + key(space)
        let previous = UserDefaults.standard.dictionary(forKey: storageKey)
        guard stage == "started" || previous?["attemptId"] as? String == attempt.uuidString else { return }
        var diagnostic: [String: Any] = ["attemptId": attempt.uuidString, "stage": stage,
            "localTimestamp": space.lastUpdate, "recordedAt": Int64(Date().timeIntervalSince1970)]
        diagnostic["reason"] = reason
        diagnostic["error"] = error?.code
        diagnostic["remoteTimestamp"] = remoteTimestamp
        diagnostic["lastConfirmedTimestamp"] = space.lastUploadCloudTimestamp
        UserDefaults.standard.set(diagnostic, forKey: storageKey)
        print("[SpaceConfigurationReadback] attempt=\(attempt.uuidString) stage=\(stage) reason=\(reason ?? "none") error=\(error?.code ?? 0)")
        #endif
    }

    @MainActor
    private static func validatePendingInitialization(_ space: SpaceData,
                                                      submission: SpaceRecoveryState.Submission) async -> String? {
        let revision = space.lastUpdate
        guard let local = await space.export(purpose: .cleanupInspection) else { return "localExportUnavailable" }
        guard !_Concurrency.Task<Never, Never>.isCancelled else { return "cancelled" }
        if let issue = pendingUploadResumeIssue(space) { return issue }
        guard space.lastUpdate == revision,
              SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"]) == revision else { return "localRevisionChanged" }
        guard local["uuid"] as? String == space.id else { return "localSpaceMismatch" }
        guard let keys = SpaceKeyIntegrity.pair(local, networkID: space.meshNetworkId),
              keys.fingerprint == submission.keyFingerprint else { return "localKeyMismatch" }
        guard SpaceConfigurationIntegrityPolicy.configurationsMatch(
            SpaceConfigurationIntegrityPolicy.configurationData(local), submission.configuration) else { return "localConfigurationMismatch" }
        guard SpaceConfigurationIntegrityPolicy.scheduleTargetsData(local) == submission.scheduleTargets else { return "localScheduleTargetsMismatch" }
        guard TimedSchedulerPayloadPolicy.canonical(local) == submission.timedConfiguration else { return "localTimedMismatch" }
        guard SchedulerModelSnapshot.spaceData(local) == submission.schedulerModelStates else { return "localSchedulerModelsMismatch" }
        guard sameNodeIdentities(SpaceCloudNodeRemovalPolicy.instances(local), submission.nodeIdentities) else { return "localNodeIdentitiesMismatch" }
        return nil
    }

    static func requiresAuthorityImport(_ space: SpaceData) -> Bool {
        (try? recoveryState(space).requiresRemoteImport) == true
    }

    /// Persist the exact submitted generation before making the request.
    static func prepareSubmission(_ space: SpaceData, payload: [String: Any], siteCreationTimestamp: Int64? = nil) -> SpaceRecoveryState? {
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard canAutomaticallyUpload(space), !hasPendingImport(space),
                  state.phase == .active, state.authority == .writable, state.submission == nil,
                  let timestamp = SpaceConfigurationIntegrityPolicy.integer(payload["updateTimestamp"]),
                  payload["uuid"] as? String == space.id, payload["nodes"] is [[String: Any]],
                  let configuration = SpaceConfigurationIntegrityPolicy.configurationData(payload),
                  let scheduleTargets = SpaceConfigurationIntegrityPolicy.scheduleTargetsData(payload),
                  let timedConfiguration = TimedSchedulerPayloadPolicy.canonical(payload),
                  let schedulerModelStates = SchedulerModelSnapshot.spaceData(payload),
                  let keys = SpaceKeyIntegrity.pair(payload, networkID: space.meshNetworkId),
                  let current = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                  let local = SpaceKeyIntegrity.pair(current, networkID: space.meshNetworkId,
                                                     applicationIndex: keys.application.index),
                  keys.fingerprint == local.fingerprint else { return nil }
            // Full local configuration already exists before the first POST.
            // A concurrent ordinary GET must not turn it into an import placeholder.
            try SpaceMembershipCoordinator.confirmConfiguration(space)
            state.submission = .init(id: UUID(), timestamp: timestamp, configuration: configuration,
                                     keyFingerprint: keys.fingerprint, scheduleTargets: scheduleTargets,
                                     timedConfiguration: timedConfiguration, schedulerModelStates: schedulerModelStates,
                                     nodeIdentities: SpaceCloudNodeRemovalPolicy.instances(payload),
                                     removalSnapshot: SpaceCloudNodeRemovalPolicy.Snapshot.make(payload))
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
            state.submission?.permitsCloudRemoval = state.prefersLocalMembership != true
            try saveState(state, space: space)
            return true
        } catch { return false }
    }

    /// A definite server rejection must not leave an unknown-outcome receipt.
    static func rejectSubmission(_ context: SpaceRecoveryState, space: SpaceData, error: NetworkApiError) {
        guard isCurrent(context, space: space) else { return }
        if error.isRequestParseRejection {
            // Only the matching prepared attempt was rejected. Preserve local
            // edits, deletion journals, baselines and any newer/accepted receipt.
            discardUnsentSubmission(context, space: space)
            return
        }
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

    /// Only a verified readback may clear the submitted version.
    static func finishAcceptedSubmission(_ context: SpaceRecoveryState, space: SpaceData) -> Bool {
        guard (try? recoveryState(space).submission?.phase) == .verified else { return false }
        return finishSubmission(context, space: space)
    }

    private static func finishSubmission(_ context: SpaceRecoveryState, space: SpaceData) -> Bool {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        lock.lock(); defer { lock.unlock() }
        do {
            var state = try recoveryState(space)
            guard isCurrent(context, space: space), let submission = state.submission,
                  state.authority == .writable, space.permission != .visitor,
                  !space.requiresPasswordVerification, !space.disableEditorPermission,
                  submission.id == context.submission?.id,
                  submission.phase == .verified else { return false }
            guard confirmLocalChanges(space, payload: ["updateTimestamp": submission.timestamp,
                                                       "nodes": [[String: Any]]()]) else { return false }
            let previous = space.lastUploadCloudTimestamp
            let previousError = space.syncCloudError
            space.lastUploadCloudTimestamp = SpaceConfigurationIntegrityPolicy.confirmedTimestamp(
                previous: previous, submitted: submission.timestamp)
            space.syncCloudError = nil
            guard space.save() else {
                space.lastUploadCloudTimestamp = previous
                space.syncCloudError = previousError
                return false
            }
            try SpaceMembershipCoordinator.confirmConfiguration(space)
            // Establish the baseline on FIRST upload too; otherwise adding the next
            // device compares the changed local topology to the pre-add cloud copy.
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            state.authorizationBaseline = readbackConfiguration(submission.configuration, timestamp: submission.timestamp, space: space)
            state.timedConfigurationBaseline = submission.timedConfiguration.flatMap {
                readbackTimed($0, timestamp: submission.timestamp, space: space)
            }
            state.schedulerModelStatesBaseline = submission.schedulerModelStates.flatMap {
                readbackModels($0, timestamp: submission.timestamp, space: space)
            }
            state.nodeIdentitiesBaseline = submission.nodeIdentities.map { identities in
                let removed = readbackRemovals(timestamp: submission.timestamp, space: space)
                return identities.filter { identity in !removed.contains {
                    $0.uuid == identity.uuid && $0.address == identity.address
                        && ($0.keyFingerprint.isEmpty || $0.keyFingerprint == identity.keyFingerprint)
                } }
            }
            state.removalSnapshot = submission.removalSnapshot.map { snapshot in
                var result = snapshot
                let removed = readbackRemovals(timestamp: submission.timestamp, space: space)
                result.identities.removeAll { identity in removed.contains { $0.matches(identity) } }
                for identity in removed { result.nodes.removeValue(forKey: identity.uuid) }
                return result
            }
            let blockedKey = "spaceConfigurationBlocked." + key(space)
            if ["uploadReadbackUnconfirmed", "uploadReadbackConflict"].contains(UserDefaults.standard.string(forKey: blockedKey) ?? "") {
                UserDefaults.standard.removeObject(forKey: blockedKey)
            }
            state.submission = nil
            state.localReplacementVersion = nil
            // Keep the selected phone authoritative after confirmation too.
            // Otherwise the next partial GET would dirty it or remove Nodes again.
            state.defaultRecoverySource = nil
            state.olderCloudBaselineFailure = nil
            try saveState(state, space: space)
            return true
        } catch { return false }
    }

    /// Verify accepted/unknown outcomes before completing local state.
    @MainActor
    static func resumeUpload(_ space: SpaceData) async -> Swift.Result<Void, NetworkApiError> {
        let attempt = UUID()
        let diagnosticIdentity = identity(space)
        var diagnosticRemoteTimestamp: Int64?
        func report(_ stage: String, _ reason: String? = nil, error: NetworkApiError? = nil) {
            guard diagnosticIdentity == identity(space) else { return }
            recordReadbackDiagnostic(space, attempt: attempt, stage: stage, reason: reason, error: error,
                                     remoteTimestamp: diagnosticRemoteTimestamp)
        }
        func failure(_ error: NetworkApiError, _ stage: String, _ reason: String) -> Swift.Result<Void, NetworkApiError> {
            report(stage, reason, error: error)
            return .failure(error)
        }
        report("started")
        do {
            if hasPendingUpload(space), let issue = pendingUploadResumeIssue(space) {
                return failure(authorityError(space), "eligibility", issue)
            }
            try migratePendingUpload(space)
            var context = try recoveryState(space)
            let membershipContext = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
                region: String(describing: UserData.currentServerRegion))
            func current() -> Bool {
                isCurrent(context, space: space) && SpaceMembershipResponseContext.matches(membershipContext,
                    account: UserData.currentUserId, region: String(describing: UserData.currentServerRegion))
            }
            guard context.phase == .active else { return failure(uploadUnconfirmed, "eligibility", "recoveryPhase") }
            guard context.authority == .writable else { return failure(authorityError(space), "eligibility", "recoveryAuthority") }
            guard let submission = context.submission else {
                // An offline local edit must not resurrect nodes removed remotely
                // since our last confirmed version. Read only this Space.
                if space.needUploadCloud || requiresConfigurationReview(space), space.lastUploadCloudTimestamp != nil
                    || context.nodeIdentitiesBaseline != nil || context.schedulerModelStatesBaseline != nil {
                    report("baselineRequest")
                    let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
                        spaceId: space.id, password: space.authorizationPassword))
                    guard !_Concurrency.Task<Never, Never>.isCancelled, current() else {
                        return failure(uploadUnconfirmed, "baselineResponse", "cancelledOrContextChanged")
                    }
                    switch response {
                    case .failure(let error):
                        handleAuthorityError(error, space: space)
                        return failure(error, "baselineRequest", "requestFailed")
                    case .success(let response):
                        guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id else {
                            return failure(uploadUnconfirmed, "baselineResponse", "invalidRemoteSpace")
                        }
                        diagnosticRemoteTimestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"])
                        space.applyRemoteSpaceMetadata(remote)
                        guard space.save() else { return failure(uploadUnconfirmed, "persistence", "remoteMetadata") }
                        guard canAutomaticallyUpload(space) else { return failure(authorityError(space), "baselineAuthority", "writeUnavailable") }
                        if context.defaultRecoverySource != nil {
                            if defaultRecoverySourceData(remote) == context.defaultRecoverySource {
                                // The user selected this server snapshot. Its repaired
                                // HDB may not decode until POST, so ordinary baseline
                                // comparison cannot authorize that first replacement.
                                report("defaultRecoveryReady")
                                return .success(())
                            }
                            // A changed cloud snapshot, including empty/replaced Nodes,
                            // supersedes the repair waiting on this phone.
                            let outcome = await space.restoreConfiguration(spaceJsonData: remote,
                                authoritativeGET: true, fixWithDefaults: true)
                            guard outcome.status == .applied else {
                                return failure(uploadUnconfirmed, "defaultRecoveryRefresh", "importFailed")
                            }
                            return .success(())
                        }
                        switch await reconcileSameVersionNodeRemoval(space, remote: remote) {
                        case .preserveLocal: return .success(())
                        case .failed(let reason): return failure(space.syncCloudError ?? uploadUnconfirmed, "baselineReconciliation", reason)
                        case .notApplicable: break
                        }
                        switch await preserveLocalMembershipIfNeeded(space, remote: remote) {
                        case .preserveLocal: return .success(())
                        case .failed(let reason): return failure(space.syncCloudError ?? uploadUnconfirmed, "baselineReconciliation", reason)
                        case .notApplicable: break
                        }
                        switch await reconcileOlderCloudBaseline(space, remote: remote) {
                        case .preserveLocal: break
                        case .failed(let reason):
                            return failure(space.syncCloudError ?? uploadUnconfirmed, "baselineReconciliation", reason)
                        case .notApplicable:
                            guard await reconcileCloudProfiles(space, remote: remote) else {
                                return failure(space.syncCloudError ?? uploadUnconfirmed, "baselineReconciliation", "profiles")
                            }
                            guard reconcileCloudMembership(space, remote: remote) else {
                                return failure(space.syncCloudError ?? uploadUnconfirmed, "baselineReconciliation", "membership")
                            }
                        }
                    }
                }
                report("noPendingReceipt")
                return .success(())
            }
            if let issue = pendingUploadResumeIssue(space) {
                return failure(authorityError(space), "eligibility", issue)
            }
            let needsInitialization = !SpaceMembershipCoordinator.allowsConfiguration(space)
            if needsInitialization, let issue = pendingInitializationIssue(space, submission: submission) {
                return failure(.configurationUnavailable, "initializationReceipt", issue)
            }
            if submission.phase == .verified {
                if needsInitialization {
                    if let issue = await validatePendingInitialization(space, submission: submission) {
                        return failure(.configurationUnavailable, "localValidation", issue)
                    }
                    guard current() else { return failure(uploadUnconfirmed, "localValidation", "contextChanged") }
                }
                guard finishSubmission(context, space: space) else { return failure(uploadUnconfirmed, "persistence", "finishSubmission") }
                report("confirmed")
                return .success(())
            }
            let expectedKeyFingerprint: String?
            if let fingerprint = submission.keyFingerprint {
                expectedKeyFingerprint = fingerprint
            } else if let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false) {
                expectedKeyFingerprint = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId)?.fingerprint
            } else {
                expectedKeyFingerprint = nil
            }
            guard let expectedKeyFingerprint else { return failure(uploadUnconfirmed, "initializationReceipt", "localKeysUnavailable") }
            var mismatchReason = "remoteConfigurationMismatch"
            for attempt in 0..<3 {
                guard !_Concurrency.Task<Never, Never>.isCancelled, current() else {
                    return failure(uploadUnconfirmed, "request", "cancelledOrContextChanged")
                }
                report("request")
                let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
                    spaceId: space.id, password: space.authorizationPassword))
                guard !_Concurrency.Task<Never, Never>.isCancelled, current() else {
                    return failure(uploadUnconfirmed, "response", "cancelledOrContextChanged")
                }
                switch response {
                case .failure(let error):
                    handleAuthorityError(error, space: space)
                    #if DEBUG
                    print("[SpaceConfigurationReadback] space=\(space.id) submitted=\(submission.timestamp) result=unavailable code=\(error.code)")
                    #endif
                    return failure(error, "request", "requestFailed")
                case .success(let response):
                    guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id else {
                        return failure(uploadUnconfirmed, "response", "invalidRemoteSpace")
                    }
                    if SpaceData.sceneConfigurationImportFailure(remote) != nil {
                        guard space.applyRemoteSpaceAuthorityRestrictions(remote), current() else {
                            return failure(authorityError(space), "remoteAuthority", "restrictionOrContextChanged")
                        }
                    }
                    if defaultRecoveryNodesChanged(space, remote: remote) {
                        let outcome = await space.restoreConfiguration(spaceJsonData: remote,
                            authoritativeGET: true, fixWithDefaults: true)
                        return outcome.status == .applied ? .success(())
                            : failure(uploadUnconfirmed, "defaultRecoveryRefresh", "importFailed")
                    }
                    guard
                          let configuration = SpaceConfigurationIntegrityPolicy.configurationData(remote),
                          remote["nodes"] is [[String: Any]] else { return failure(uploadUnconfirmed, "response", "invalidRemoteConfiguration") }
                    let remoteKeyFingerprint = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId)?.fingerprint
                    space.applyRemoteSpaceMetadata(remote)
                    guard space.save() else { return failure(uploadUnconfirmed, "persistence", "remoteMetadata") }
                    guard current() else { return failure(authorityError(space), "remoteAuthority", "contextChanged") }
                    if let issue = pendingUploadResumeIssue(space) {
                        return failure(authorityError(space), "remoteAuthority", issue)
                    }
                    if needsInitialization {
                        guard remote["role"] as? String == "owner",
                              (remote["owner"] as? [String: Any])?["userId"] as? String == UserData.currentUserId else {
                            return failure(.noSpacePermission, "remoteAuthority", "ownerMismatch")
                        }
                    }
                    let sameVersionRemoval: Bool
                    switch await reconcileSameVersionNodeRemoval(space, remote: remote) {
                    case .preserveLocal: sameVersionRemoval = true
                    case .failed(let reason): return failure(space.syncCloudError ?? uploadUnconfirmed, "membershipReconciliation", reason)
                    case .notApplicable: sameVersionRemoval = false
                    }
                    context = try recoveryState(space)
                    guard current(), context.submission?.id == submission.id else {
                        return failure(uploadUnconfirmed, "membershipReconciliation", "contextChanged")
                    }
                    let profilesReconciled = sameVersionRemoval ? true : await reconcileCloudProfiles(space, remote: remote)
                    guard profilesReconciled, current() else {
                        return failure(space.syncCloudError ?? uploadUnconfirmed, "profileReconciliation", "failedOrContextChanged")
                    }
                    if (try? recoveryState(space).submission) == nil {
                        report("replacementUploadRequired", "profilesReconciled")
                        return .success(())
                    }
                    guard sameVersionRemoval || reconcileCloudMembership(space, remote: remote), current() else {
                        return failure(space.syncCloudError ?? uploadUnconfirmed, "membershipReconciliation", "failedOrContextChanged")
                    }
                    let expected = readbackConfiguration(submission.configuration, timestamp: submission.timestamp, space: space)
                    let actual = readbackRemoteConfiguration(configuration, timestamp: submission.timestamp, space: space)
                    let schedulesMatch = submission.scheduleTargets.map {
                        SpaceConfigurationIntegrityPolicy.scheduleTargetsData(remote) == $0
                    } ?? true
                    let timedMatch = submission.timedConfiguration.map {
                        readbackTimed($0, timestamp: submission.timestamp, space: space).map {
                            TimedSchedulerPayloadPolicy.canonical(remote).flatMap {
                                readbackTimed($0, timestamp: submission.timestamp, space: space)
                            } == $0
                        } ?? false
                    } ?? true
                    let modelsMatch = submission.schedulerModelStates.map {
                        readbackModels($0, timestamp: submission.timestamp, space: space).map {
                            SchedulerModelSnapshot.spaceData(remote) == $0
                        } ?? false
                    } ?? true
                    let identitiesMatch = (!needsInitialization && context.prefersLocalMembership != true)
                        || sameNodeIdentities(SpaceCloudNodeRemovalPolicy.instances(remote), submission.nodeIdentities)
                    if !needsInitialization, remoteKeyFingerprint != expectedKeyFingerprint,
                       space.permission == .owner, remote["role"] as? String == "owner",
                       let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                       let localKeys = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId),
                       localKeys.fingerprint == expectedKeyFingerprint,
                       SpaceKeyIntegrity.presentServerKeysMatchLocal(remote, local: localKeys),
                       SpaceConfigurationIntegrityPolicy.configurationsMatch(actual, expected), schedulesMatch, modelsMatch, timedMatch {
                        // The submitted business configuration arrived, but one Key did not.
                        // Keep the Space dirty and send a new complete snapshot.
                        context = try recoveryState(space)
                        guard context.submission?.id == submission.id else { return failure(uploadUnconfirmed, "persistence", "receiptChanged") }
                        context.submission = nil
                        try saveState(context, space: space)
                        report("replacementUploadRequired", "missingRemoteKey")
                        return .success(())
                    }
                    if remoteKeyFingerprint == expectedKeyFingerprint,
                       SpaceConfigurationIntegrityPolicy.configurationsMatch(actual, expected),
                       schedulesMatch, modelsMatch, timedMatch, identitiesMatch {
                        if needsInitialization {
                            // Check the live local snapshot after the GET, before
                            // initializing a historical receipt's membership.
                            if let issue = await validatePendingInitialization(space, submission: submission) {
                                return failure(.configurationUnavailable, "localValidation", issue)
                            }
                            guard current() else { return failure(uploadUnconfirmed, "localValidation", "contextChanged") }
                        }
                        context = try recoveryState(space)
                        guard context.submission?.id == submission.id else { return failure(uploadUnconfirmed, "persistence", "receiptChanged") }
                        context.submission?.phase = .verified
                        try saveState(context, space: space)
                        guard finishSubmission(context, space: space) else { return failure(uploadUnconfirmed, "persistence", "finishSubmission") }
                        report("confirmed")
                        return .success(())
                    }
                    if remoteKeyFingerprint != expectedKeyFingerprint { mismatchReason = "remoteKeyMismatch" }
                    else if !SpaceConfigurationIntegrityPolicy.configurationsMatch(actual, expected) { mismatchReason = "remoteConfigurationMismatch" }
                    else if !schedulesMatch { mismatchReason = "remoteScheduleTargetsMismatch" }
                    else if !timedMatch { mismatchReason = "remoteTimedMismatch" }
                    else if !modelsMatch { mismatchReason = "remoteSchedulerModelsMismatch" }
                    else { mismatchReason = "remoteNodeIdentitiesMismatch" }
                    report("remoteValidation", mismatchReason)
                    #if DEBUG
                    print("[SpaceConfigurationReadback] source=resume site=\(space.siteId) space=\(space.id) "
                        + "submissionId=\(submission.id.uuidString) phase=\(submission.phase.rawValue) "
                        + "submitted=\(submission.timestamp) localTimestamp=\(space.lastUpdate) "
                        + "attempt=\(attempt + 1) result=mismatch scheduleTargetsMatch=\(schedulesMatch) schedulerModelsMatch=\(modelsMatch) "
                        + SpaceConfigurationIntegrityPolicy.readbackDiagnostic(
                            submittedConfiguration: expected, remote: remote))
                    #endif
                    // A cancelled pre-send operation can be replaced only if the
                    // cloud still matches the last confirmed baseline.
                    if attempt == 2, submission.phase == .prepared,
                       remoteKeyFingerprint == expectedKeyFingerprint,
                       SpaceConfigurationIntegrityPolicy.configurationsMatch(configuration, context.authorizationBaseline.map {
                           readbackConfiguration($0, timestamp: space.lastUploadCloudTimestamp ?? 0, space: space)
                       }) {
                        context.submission = nil
                        try saveState(context, space: space)
                        report("replacementUploadRequired", "unsentSubmission")
                        return .success(())
                    }
                }
                if attempt < 2 { try await _Concurrency.Task<Never, Never>.sleep(nanoseconds: 500_000_000) }
            }
            block(space, reason: "uploadReadbackConflict")
            return failure(uploadUnconfirmed, "remoteValidation", mismatchReason)
        } catch let error as PendingUploadValidationError {
            return failure(.configurationUnavailable, "legacyReceipt", error.reason)
        } catch {
            return failure(uploadUnconfirmed, "recovery", "storageOrCancellation")
        }
    }

    /// A completed, version-scoped removal supersedes only its old instances.
    /// The newer reference cleanup must still receive its own verified upload.
    private static func readbackRemovals(timestamp: Int64, space: SpaceData) -> [SpaceCloudNodeRemovalPolicy.Instance] {
        guard let journal = try? deletionJournal(space) else { return [] }
        return journal.entries.compactMap { entry in
            guard entry.stage == .cleaned, (entry.completedTimestamp ?? 0) > timestamp else { return nil }
            if let removal = entry.cloudRemoval, removal.baselineTimestamp >= timestamp { return removal.instance }
            guard entry.replacement != nil else { return nil }
            return .init(uuid: entry.nodeUUID.uppercased(), address: entry.primaryAddress, keyFingerprint: "",
                         elementAddresses: entry.elementAddresses)
        }
    }

    private static func readbackConfiguration(_ data: Data, timestamp: Int64, space: SpaceData) -> Data {
        let removed = readbackRemovals(timestamp: timestamp, space: space)
        return removed.isEmpty ? data : SpaceCloudNodeRemovalPolicy.projectConfiguration(data, removing: removed) ?? data
    }

    private static func readbackRemoteConfiguration(_ data: Data, timestamp: Int64, space: SpaceData) -> Data? {
        let removed = readbackRemovals(timestamp: timestamp, space: space)
        guard !removed.isEmpty else { return data }
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let members = value["memberships"] as? [[String: Any]],
              !members.contains(where: { member in removed.contains { $0.matches(member) } }) else { return nil }
        return SpaceCloudNodeRemovalPolicy.projectConfiguration(data, removing: removed)
    }

    private static func readbackTimed(_ data: Data, timestamp: Int64, space: SpaceData) -> Data? {
        let removed = readbackRemovals(timestamp: timestamp, space: space)
        return TimedSchedulerPayloadPolicy.removingNodes(from: data, uuids: Set(removed.map(\.uuid)),
            addresses: Set(removed.flatMap { $0.elementAddresses.union([$0.address]) }.map { String(format: "%04X", $0) }))
    }

    private static func readbackModels(_ data: Data, timestamp: Int64, space: SpaceData) -> Data? {
        SpaceCloudNodeRemovalPolicy.projectModels(data, removing: readbackRemovals(timestamp: timestamp, space: space))
    }

    enum OlderCloudBaselineResult {
        case notApplicable, preserveLocal, failed(String)
    }

    static func needsOlderCloudBaselineReview(_ space: SpaceData) -> Bool {
        UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) == "cloudBaselineNeedsReview"
    }

    struct CloudBaselineReview {
        let local: [String: Any]
        let remote: [String: Any]
        let message: String
    }

    /// Compare the editable configuration reviewed by the user, excluding device
    /// observation caches that can change without a new local edit.
    private static func recoveryPayloadsMatch(_ lhs: [String: Any], _ rhs: [String: Any], space: SpaceData) -> Bool {
        typealias P = SpaceConfigurationIntegrityPolicy
        guard lhs["uuid"] as? String == space.id, rhs["uuid"] as? String == space.id,
              P.integer(lhs["updateTimestamp"]) == P.integer(rhs["updateTimestamp"]),
              P.configurationsMatch(P.configurationData(lhs), P.configurationData(rhs)),
              sameNodeIdentities(SpaceCloudNodeRemovalPolicy.instances(lhs), SpaceCloudNodeRemovalPolicy.instances(rhs)),
              let keys = SpaceKeyIntegrity.pair(lhs, networkID: space.meshNetworkId),
              keys.fingerprint == SpaceKeyIntegrity.pair(rhs, networkID: space.meshNetworkId)?.fingerprint,
              let timed = TimedSchedulerPayloadPolicy.canonical(lhs), timed == TimedSchedulerPayloadPolicy.canonical(rhs),
              let models = SchedulerModelSnapshot.spaceData(lhs), models == SchedulerModelSnapshot.spaceData(rhs) else { return false }
        let fields: Set<String> = ["spaceName", "imageId", "controlType", "deviceBlinkMode", "displayDeviceNamePrefix",
            "showCCTQuickButtons", "scenes", "switches", "emergencyFireControllers", "spaceData"]
        guard let left = try? JSONSerialization.data(withJSONObject: lhs.filter { fields.contains($0.key) }, options: .sortedKeys),
              let right = try? JSONSerialization.data(withJSONObject: rhs.filter { fields.contains($0.key) }, options: .sortedKeys) else { return false }
        return left == right
    }

    @MainActor
    static func cloudBaselineReview(_ space: SpaceData, local: [String: Any]) async -> CloudBaselineReview? {
        guard needsOlderCloudBaselineReview(space), let context = try? recoveryState(space),
              !hasPendingImport(space), !hasPendingDeletionCleanup(space), canAutomaticallyUpload(space),
              let localNodes = SpaceCloudNodeRemovalPolicy.instances(local) else { return nil }
        let membership = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId, spaceId: space.id,
                                                                   password: space.authorizationPassword))
        guard !Task.isCancelled, isCurrent(context, space: space),
              SpaceMembershipResponseContext.matches(membership, account: UserData.currentUserId,
                  region: String(describing: UserData.currentServerRegion)),
              space.lastUpdate == SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"]) else { return nil }
        if case .failure(let error) = result { handleAuthorityError(error, space: space) }
        guard case .success(let response) = result, let remote = response["data"] as? [String: Any],
              remote["uuid"] as? String == space.id,
              recoveryPayloadsMatch(remote, remote, space: space),
              SpaceKeyIntegrity.pair(local, networkID: space.meshNetworkId)?.fingerprint
                == SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId)?.fingerprint,
              SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == space.lastUpdate,
              let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote) else { return nil }
        space.applyRemoteSpaceMetadata(remote)
        guard space.save(), canAutomaticallyUpload(space), needsOlderCloudBaselineReview(space) else { return nil }
        func list(_ payload: [String: Any], excluding identities: [SpaceCloudNodeRemovalPolicy.Instance]) -> String {
            let nodes = (payload["nodes"] as? [[String: Any]] ?? []).filter { raw in
                guard let instance = SpaceCloudNodeRemovalPolicy.instances(["nodes": [raw]])?.first else { return true }
                return !identities.contains(instance)
            }
                .sorted { ($0["unicastAddress"] as? String ?? "") < ($1["unicastAddress"] as? String ?? "") }
            let names = nodes.prefix(12).map { "\($0["name"] as? String ?? "") (\($0["unicastAddress"] as? String ?? ""))" }.joined(separator: ", ")
            return names + (nodes.count > 12 ? " … (+\(nodes.count - 12))" : "")
        }
        var lines = [String(format: "configuration_baseline_devices".localizedString, localNodes.count, remoteNodes.count)]
        let localOnly = list(local, excluding: remoteNodes), remoteOnly = list(remote, excluding: localNodes)
        if !localOnly.isEmpty { lines.append(String(format: "configuration_baseline_local_only".localizedString, localOnly)) }
        if !remoteOnly.isEmpty { lines.append(String(format: "configuration_baseline_cloud_only".localizedString, remoteOnly)) }
        let localSwitches = local["switches"] as? [[String: Any]] ?? []
        let proxyChanges = (remote["switches"] as? [[String: Any]] ?? []).compactMap { item -> String? in
            let localSwitch = localSwitches.first { $0["id"] as? String == item["id"] as? String }
            let old = item["proxyNodeAddress"] as? String, current = localSwitch?["proxyNodeAddress"] as? String
            guard old != current else { return nil }
            return "\(item["name"] as? String ?? "") (\(old ?? "—") → \(current ?? "—"))"
        }
        if !proxyChanges.isEmpty { lines.append(String(format: "configuration_baseline_proxy".localizedString, proxyChanges.joined(separator: ", "))) }
        return .init(local: local, remote: remote, message: lines.joined(separator: "\n\n"))
    }

    private static func reviewedCloudImport(_ space: SpaceData) -> (timestamp: Int64, payload: [String: Any], defaultSource: Data?, needsUpload: Bool)? {
        guard let url = try? directory(space).appendingPathComponent("reviewed-cloud-import.json"),
              let data = try? Data(contentsOf: url),
              let receipt = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(receipt["localTimestamp"]),
              let payload = receipt["payload"] as? [String: Any], payload["uuid"] as? String == space.id else { return nil }
        return (timestamp, payload, (receipt["defaultSource"] as? String).flatMap { Data(base64Encoded: $0) },
                receipt["needsUpload"] as? Bool ?? false)
    }

    static func hasReviewedCloudImport(_ space: SpaceData) -> Bool { reviewedCloudImport(space) != nil }

    private static func defaultRecoverySourceData(_ payload: [String: Any]) -> Data? {
        let fields: Set<String> = ["uuid", "updateTimestamp", "netKey", "appKey", "nodes", "groups", "scenes",
            "schedules", "switches", "emergencyFireControllers", "spaceData", "spaceName", "imageId",
            "controlType", "deviceBlinkMode", "displayDeviceNamePrefix", "showCCTQuickButtons"]
        return try? JSONSerialization.data(withJSONObject: payload.filter { fields.contains($0.key) }, options: .sortedKeys)
    }

    /// The repaired configuration is already committed to both databases. An
    /// unchanged pre-repair GET is an upload baseline, not another import or
    /// Profile conflict. This decision survives leaving the page and restarting.
    @MainActor
    static func preserveDefaultConfiguration(_ space: SpaceData, remote: [String: Any]) -> SpaceImportOutcome? {
        guard canAutomaticallyUpload(space), !hasPendingImport(space),
              !hasPendingDeletionCleanup(space), !hasPendingReferenceCleanup(space),
              var state = try? recoveryState(space), let source = state.defaultRecoverySource,
              let version = state.localReplacementVersion,
              defaultRecoverySourceData(remote) == source else { return nil }
        let blockedKey = "spaceConfigurationBlocked." + key(space)
        let reason = UserDefaults.standard.string(forKey: blockedKey)
        // Only conflicts caused by comparing this known old cloud copy may be
        // retired. Storage, topology, authority and unrelated blocks still apply.
        guard reason == nil || ["cloudBaselineNeedsReview", "cloudConfigurationConflict",
            "cloudMembershipConflict", "profileTimestampConflict", "uploadReadbackConflict",
            "uploadReadbackUnconfirmed"].contains(reason!) else { return nil }
        guard let stored = SpaceData.load(siteId: space.siteId, spaceId: space.id).first,
              stored.lastUpdate >= version, !stored.hdbLoadFailed, !stored.triggerZonesLoadFailed,
              !space.hdbLoadFailed, !space.triggerZonesLoadFailed else {
            return .rejected("configurationPersistenceFailed")
        }
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        space.syncCloudError = nil
        guard space.save() else { return .rejected("configurationPersistenceFailed") }
        if state.olderCloudBaselineFailure != nil {
            state.olderCloudBaselineFailure = nil
            do { try saveState(state, space: space) }
            catch { return .rejected("configurationFinalizationFailed") }
        }
        if reason != nil { UserDefaults.standard.removeObject(forKey: blockedKey) }
        return .preserved("localDefaultRecoveryPendingUpload")
    }

    static func shouldRefreshDefaultRecovery(_ space: SpaceData, remote: [String: Any]) -> Bool {
        guard !hasPendingImport(space), let state = try? recoveryState(space),
              let source = state.defaultRecoverySource else { return false }
        if state.submission != nil { return defaultRecoveryNodesChanged(space, remote: remote) }
        return defaultRecoverySourceData(remote) != source
    }

    private static func defaultRecoveryNodesChanged(_ space: SpaceData, remote: [String: Any]) -> Bool {
        guard let data = try? recoveryState(space).defaultRecoverySource,
              let source = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let before = SpaceCloudNodeRemovalPolicy.instances(source),
              let after = SpaceCloudNodeRemovalPolicy.instances(remote) else { return false }
        return !sameNodeIdentities(before, after)
    }

    /// Explicitly choose the latest cloud configuration even when the local HDB
    /// cannot be exported. The checkpoint preserves the old databases, not authority.
    @MainActor
    static func prepareDefaultConfigurationImport(_ space: SpaceData, remote: [String: Any]) -> Bool {
        var stage = "authorityAndIdentity"
        var prepared = false
        defer {
            if !prepared { recordSyncFailure(space, error: .configurationUnavailable, stage: "defaultRecovery." + stage) }
        }
        guard SpaceMembershipCoordinator.accepts(remote), remote["uuid"] as? String == space.id,
              canAutomaticallyUpload(space), !hasPendingImport(space), !hasPendingDeletionCleanup(space),
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              timestamp >= 0, timestamp < Int64.max, space.lastUpdate < Int64.max,
              let source = defaultRecoverySourceData(remote),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              remoteKeys.fingerprint == SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId)?.fingerprint else { return false }
        do {
            var selected = remote
            selected.removeValue(forKey: SpaceMembershipResponseContext.payloadKey)
            stage = "hdb"
            selected = try HDBLightingZonePolicy.repairingDefaults(in: selected, deviceConfiguration: { dictionary, mac in
                let node = try CloudNodeImport.decode(dictionary)
                node.macAddress = mac
                return try HDBConfigurationStore.deviceConfiguration(node: node, sensorTypes: dictionary["sensorTypes"] as? [String] ?? [])
            }) {
                String(format: "hdb_default_zone_name".localizedString, $0)
            }
            stage = "timedAndReferences"
            guard let timed = TimedSchedulerPayloadPolicy.repairingStaleBindings(selected) else { return false }
            selected = try SpaceSyncCleanupPolicy.normalize(timed).payload
            stage = "decode"
            guard SpaceData.canDecodeConfigurationImport(selected),
                  SpaceConfigurationIntegrityPolicy.configurationData(selected) != nil,
                  let version = TimedSchedulerPayloadPolicy.schema(selected), version >= space.timedSchemaVersion else { return false }
            stage = "checkpoint"
            guard checkpoint(space, refresh: true) else { return false }
            stage = "staging"
            let changed = defaultRecoverySourceData(selected) != source
            let receipt: [String: Any] = ["localTimestamp": space.lastUpdate, "payload": selected,
                "defaultSource": source.base64EncodedString(), "needsUpload": changed]
            try JSONSerialization.data(withJSONObject: receipt, options: .sortedKeys).write(
                to: directory(space).appendingPathComponent("reviewed-cloud-import.json"),
                options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            var state = try recoveryState(space)
            state.generation = UUID() // Late callbacks from the discarded local upload cannot finish it.
            state.submission = nil
            try saveState(state, space: space)
            prepared = true
            return true
        } catch { return false }
    }

    /// Persist the reviewed choice atomically. Ordinary import/restart then uses
    /// the existing pending-import path without discarding local receipts early.
    @MainActor
    static func prepareReviewedCloudImport(_ space: SpaceData, review: CloudBaselineReview,
                                          remote: [String: Any]) async -> Bool {
        let membership = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        guard needsOlderCloudBaselineReview(space), canAutomaticallyUpload(space),
              !hasPendingImport(space), !hasPendingDeletionCleanup(space), !hasPendingReferenceCleanup(space),
              let context = try? recoveryState(space), context.submission == nil,
              SpaceMembershipCoordinator.accepts(remote),
              recoveryPayloadsMatch(remote, review.remote, space: space),
              let version = TimedSchedulerPayloadPolicy.schema(remote), version >= space.timedSchemaVersion,
              let normalized = try? SpaceSyncCleanupPolicy.normalize(remote),
              SpaceData.canDecodeConfigurationImport(normalized.payload),
              let current = await space.export(purpose: .cleanupInspection),
              recoveryPayloadsMatch(current, review.local, space: space),
              !Task.isCancelled, isCurrent(context, space: space),
              SpaceMembershipResponseContext.matches(membership, account: UserData.currentUserId,
                  region: String(describing: UserData.currentServerRegion)),
              SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == space.lastUpdate,
              space.lastUpdate == SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]) else { return false }
        space.applyRemoteSpaceMetadata(remote)
        guard space.save(), canAutomaticallyUpload(space), (try? recoveryState(space)) == context,
              checkpoint(space, refresh: true), recordSnapshot(space, payload: current) else { return false }
        do {
            SpaceProtectionReadGeneration.beginMutation()
            defer { SpaceProtectionReadGeneration.endMutation() }
            let receipt: [String: Any] = ["localTimestamp": space.lastUpdate, "payload": remote]
            let data = try JSONSerialization.data(withJSONObject: receipt, options: .sortedKeys)
            try data.write(to: directory(space).appendingPathComponent("reviewed-cloud-import.json"),
                           options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return true
        } catch { return false }
    }

    /// A legacy local acknowledgement can be newer than an unchanged cloud copy.
    /// This authorizes only preparation of a NEW upload, never import, removal or
    /// confirmation of an existing receipt. Both callers must preserve local data.
    @MainActor
    static func reconcileOlderCloudBaseline(_ space: SpaceData, remote: [String: Any]) async -> OlderCloudBaselineResult {
        typealias P = SpaceConfigurationIntegrityPolicy
        // Authority recovery must reach the full importer, which alone clears
        // requiresRemoteImport. This upload-only check cannot authorize that path.
        guard !requiresAuthorityImport(space), !hasPendingUpload(space), !hasPendingImport(space),
              let confirmed = space.lastUploadCloudTimestamp,
              let remoteTimestamp = P.integer(remote["updateTimestamp"]), remoteTimestamp >= 0,
              remoteTimestamp < Int64.max,
              space.needUploadCloud || preservesLocalChanges(space) else { return .notApplicable }
        guard let context = try? recoveryState(space) else { return .failed("baselineStorageUnavailable") }
        if remoteTimestamp >= confirmed {
            // A recovered cloud version must return to normal arbitration even
            // when repeated stale reads previously required baseline review.
            if context.olderCloudBaselineFailure != nil {
                var state = context
                state.olderCloudBaselineFailure = nil
                do { try saveState(state, space: space) }
                catch { return .failed("baselinePersistence") }
            }
            if needsOlderCloudBaselineReview(space) {
                SpaceProtectionReadGeneration.beginMutation()
                defer { SpaceProtectionReadGeneration.endMutation() }
                UserDefaults.standard.removeObject(forKey: "spaceConfigurationBlocked." + key(space))
            }
            return .notApplicable
        }
        let revision = space.lastUpdate
        let membership = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        func current() -> Bool {
            !Task.isCancelled && isCurrent(context, space: space)
                && SpaceMembershipResponseContext.matches(membership, account: UserData.currentUserId,
                    region: String(describing: UserData.currentServerRegion))
                && (try? recoveryState(space)) == context && space.lastUpdate == revision
                && space.lastUploadCloudTimestamp == confirmed
        }
        var diagnostic: [String: Any] = ["remoteTimestamp": remoteTimestamp, "localTimestamp": revision,
            "lastConfirmedTimestamp": confirmed]
        func report(_ reason: String) {
            #if DEBUG
            guard identity(space) == context.identity else { return }
            diagnostic["reason"] = reason
            diagnostic["recordedAt"] = Int64(Date().timeIntervalSince1970)
            UserDefaults.standard.set(diagnostic, forKey: "spaceConfigurationLastBaselineDiagnostic." + key(space))
            print("[SpaceCloudBaseline] reason=\(reason) remote=\(remoteTimestamp) confirmed=\(confirmed) local=\(revision)")
            #endif
        }
        func failure(_ reason: String, reviewable: Bool = false) -> OlderCloudBaselineResult {
            guard current() else { return .failed("baselineContextChanged") }
            var error = uploadUnconfirmed
            if reviewable {
                // Require a repeated observation of the same data and local generation.
                // Keep only its hash; this is a retry marker, not cloud authority.
                let value: [String: Any] = ["remoteTimestamp": remoteTimestamp, "reason": reason, "local": revision,
                    "configuration": P.configurationData(remote)?.base64EncodedString() ?? "",
                    "models": SchedulerModelSnapshot.spaceData(remote)?.base64EncodedString() ?? "",
                    "timed": TimedSchedulerPayloadPolicy.canonical(remote)?.base64EncodedString() ?? "",
                    "confirmed": confirmed, "baseline": context.authorizationBaseline?.base64EncodedString() ?? "",
                    "baselineModels": context.schedulerModelStatesBaseline?.base64EncodedString() ?? "",
                    "baselineTimed": context.timedConfigurationBaseline?.base64EncodedString() ?? ""]
                if let data = try? JSONSerialization.data(withJSONObject: value, options: .sortedKeys) {
                    let signature = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                    var state = context
                    let repeated = state.olderCloudBaselineFailure == signature
                    state.olderCloudBaselineFailure = signature
                    do { try saveState(state, space: space) }
                    catch { report("baselinePersistence"); return .failed("baselinePersistence") }
                    if repeated {
                        block(space, reason: "cloudBaselineNeedsReview")
                        error = .configurationReviewRequired
                    }
                }
            }
            report(reason)
            recordSyncFailure(space, error: error, stage: reason, remoteTimestamp: remoteTimestamp)
            return .failed(reason)
        }
        guard current(), canAutomaticallyUpload(space), !hasPendingImport(space),
              !hasPendingDeletionCleanup(space), !hasPendingReferenceCleanup(space),
              let journal = try? deletionJournal(space) else { return failure("baselineUnavailable") }
        if let record = try? SpaceMembershipCoordinator.store.read(SpaceMembershipCoordinator.scope(space)),
           record.networkID != space.meshNetworkId { return failure("baselineMembershipNetworkMismatch") }
        let blockedKey = "spaceConfigurationBlocked." + key(space)
        if let reason = UserDefaults.standard.string(forKey: blockedKey), reason != "cloudBaselineNeedsReview" {
            return failure("baselineProtectedConfiguration")
        }
        guard remote["uuid"] as? String == space.id,
              remote["groups"] is [[String: Any]], remote["scenes"] is [[String: Any]],
              remote["schedules"] is [[String: Any]],
              let actual = P.configurationData(remote),
              let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote),
              let remoteModels = SchedulerModelSnapshot.spaceData(remote),
              let remoteTimed = TimedSchedulerPayloadPolicy.canonical(remote),
              P.scheduleTargetIssue(in: remote) == nil,
              (try? SpaceSyncCleanupPolicy.normalize(remote)) != nil else { return failure("baselineInvalidRemote") }
        guard let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let keys = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              keys.fingerprint == remoteKeys.fingerprint else { return failure("baselineNetworkKeyMismatch") }
        guard let reference = context.authorizationBaseline else { return failure("baselineConfigurationMissing", reviewable: true) }
        diagnostic["configurationMatches"] = P.configurationsMatch(reference, actual)
        guard P.configurationsMatch(reference, actual) else { return failure("baselineConfigurationMismatch", reviewable: true) }

        // A saved snapshot supplies missing evidence only if it is the confirmed
        // generation with the same business configuration and network identity.
        var snapshot: [String: Any]?
        if let url = try? directory(space).appendingPathComponent("last-complete-export.json"),
           let data = try? Data(contentsOf: url),
           let saved = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           saved["uuid"] as? String == space.id, P.integer(saved["updateTimestamp"]) == confirmed,
           P.configurationsMatch(P.configurationData(saved), reference),
           SpaceKeyIntegrity.pair(saved, networkID: space.meshNetworkId)?.fingerprint == keys.fingerprint {
            snapshot = saved
        }
        let models = context.schedulerModelStatesBaseline ?? snapshot.flatMap(SchedulerModelSnapshot.spaceData)
        let nodes = context.nodeIdentitiesBaseline ?? snapshot.flatMap(SpaceCloudNodeRemovalPolicy.instances)
            ?? SpaceCloudNodeRemovalPolicy.legacyInstances(configuration: reference, models: models)
        diagnostic["nodeIdentitiesMatch"] = sameNodeIdentities(nodes, remoteNodes)
        diagnostic["schedulerModelsMatch"] = models == remoteModels
        guard sameNodeIdentities(nodes, remoteNodes) else { return failure("baselineNodeIdentitiesMismatchOrMissing", reviewable: true) }
        guard models == remoteModels else { return failure("baselineSchedulerModelsMismatchOrMissing", reviewable: true) }

        guard let local = await space.export(purpose: .cleanupInspection), current(),
              SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == revision,
              local["uuid"] as? String == space.id, P.integer(local["updateTimestamp"]) == revision,
              P.configurationData(local) != nil,
              let localNodes = SpaceCloudNodeRemovalPolicy.instances(local),
              let localTimed = TimedSchedulerPayloadPolicy.canonical(local),
              SpaceKeyIntegrity.pair(local, networkID: space.meshNetworkId)?.fingerprint == keys.fingerprint else {
            return failure("baselineLocalSnapshotUnavailable")
        }
        var timed = context.timedConfigurationBaseline ?? snapshot.flatMap(TimedSchedulerPayloadPolicy.canonical)
        if timed == nil,
           let schedules = local["schedules"] as? [[String: Any]], schedules.isEmpty,
           let remoteSchedules = remote["schedules"] as? [[String: Any]], remoteSchedules.isEmpty,
           localTimed == remoteTimed,
           [local, remote].allSatisfy({ payload in
               (payload["nodes"] as? [[String: Any]])?.allSatisfy {
                   ($0["schedules"] as? [Any])?.isEmpty == true
               } == true
           }) { timed = remoteTimed }
        diagnostic["timedMatches"] = timed == remoteTimed
        guard timed == remoteTimed else { return failure("baselineTimedMismatchOrMissing", reviewable: true) }
        guard let nodes else { return failure("baselineNodeIdentitiesMissing", reviewable: true) }
        // Only explicit review of this local version permits replacing a
        // provisioning instance. Automatic reconciliation stays strict.
        let reviewedReplacement = context.localReplacementVersion == revision
        guard reviewedReplacement || localNodes.allSatisfy({ local in
            nodes.first(where: { $0.uuid == local.uuid }).map { $0 == local } ?? true
        }) else { return failure("baselineLocalNodeIdentityChanged", reviewable: true) }
        let missing = nodes.filter { old in !localNodes.contains(where: { old.matches($0) }) }
        diagnostic["localRemovalCount"] = missing.count
        guard reviewedReplacement || missing.allSatisfy({ old in journal.entries.contains {
            $0.stage == .cleaned && $0.nodeUUID.uppercased() == old.uuid
                && $0.primaryAddress == old.address && $0.elementAddresses == old.elementAddresses
                && ($0.completedTimestamp ?? 0) > confirmed && ($0.completedTimestamp ?? Int64.max) <= revision
        } }) else { return failure("baselineLocalRemovalUnproven", reviewable: true) }
        guard current() else { return .failed("baselineContextChanged") }
        var state = context
        state.nodeIdentitiesBaseline = nodes
        state.schedulerModelStatesBaseline = models
        state.timedConfigurationBaseline = timed
        state.olderCloudBaselineFailure = nil
        do { try saveState(state, space: space) }
        catch { return failure("baselinePersistence") }
        UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        if UserDefaults.standard.string(forKey: blockedKey) == "cloudBaselineNeedsReview" {
            UserDefaults.standard.removeObject(forKey: blockedKey)
        }
        report("unchangedOlderCloudBaseline")
        return .preserveLocal
    }

    /// Resolve only Profile differences. Space timestamps are the agreed version
    /// contract; membership, topology, schedules and network identity remain strict.
    @MainActor
    static func reconcileCloudProfiles(_ space: SpaceData, remote: [String: Any]) async -> Bool {
        if let state = try? recoveryState(space), state.prefersLocalMembership == true, state.submission != nil { return true }
        typealias P = SpaceConfigurationIntegrityPolicy
        guard canAutomaticallyUpload(space), !hasPendingImport(space),
              let context = try? recoveryState(space),
              context.submission != nil || space.needUploadCloud || preservesLocalChanges(space),
              let reference = context.submission?.configuration ?? context.authorizationBaseline,
              let identities = context.submission?.nodeIdentities ?? (context.submission == nil ? context.nodeIdentitiesBaseline : nil),
              let timed = context.submission?.timedConfiguration ?? (context.submission == nil ? context.timedConfigurationBaseline : nil),
              let models = context.submission?.schedulerModelStates ?? (context.submission == nil ? context.schedulerModelStatesBaseline : nil)
        else { return true }
        if let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)),
           !["uploadReadbackConflict", "uploadReadbackUnconfirmed", "profileTimestampConflict", "cloudConfigurationConflict"].contains(reason) {
            return true
        }
        // Leave unrelated readback retries and removal handling on their original path.
        if let actual = P.configurationData(remote),
           P.sharedProfilesMatch(reference, actual) == true,
           context.submission != nil { return true }
        if let groups = remote["groups"] as? [[String: Any]], groups.isEmpty { return true }
        func failure(_ stage: String, review: Bool = false) -> Bool {
            if review { block(space, reason: stage) }
            return recordSyncFailure(space, error: review ? .configurationReviewRequired : uploadUnconfirmed,
                                     stage: stage, remoteTimestamp: P.integer(remote["updateTimestamp"]))
        }
        guard remote["uuid"] as? String == space.id,
              let remoteTimestamp = P.integer(remote["updateTimestamp"]), remoteTimestamp >= 0, remoteTimestamp < Int64.max,
              let actual = P.configurationData(remote),
              let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote),
              let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let keys = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              keys.fingerprint == remoteKeys.fingerprint,
              context.submission?.keyFingerprint == nil || context.submission?.keyFingerprint == keys.fingerprint
        else { return failure("profilePreflightInvalid") }
        // A stale read is not proof of a business conflict or permission to roll back.
        guard remoteTimestamp >= (space.lastUploadCloudTimestamp ?? 0) else { return failure("profileCloudVersionBehind") }
        // Actual additions/removals are owned by the existing membership lifecycle.
        guard let removed = SpaceCloudNodeRemovalPolicy.removed(from: identities, remote: remoteNodes), removed.isEmpty else { return true }
        let referenceMatches = P.configurationsMatch(reference, actual)
        let profilesOnly = P.configurationsMatchExceptProfiles(reference, actual)
        guard profilesOnly, TimedSchedulerPayloadPolicy.canonical(remote) == timed,
              SchedulerModelSnapshot.spaceData(remote) == models,
              context.submission?.scheduleTargets.map({ P.scheduleTargetsData(remote) == $0 }) ?? true else {
            return failure("cloudConfigurationConflict", review: true)
        }
        // Ordinary local-newer edits with an unchanged cloud baseline need no merge.
        if referenceMatches, context.submission == nil, remoteTimestamp < space.lastUpdate { return true }
        if referenceMatches, context.submission != nil { return true }
        let revision = space.lastUpdate
        guard let local = await space.export(purpose: .cleanupInspection),
              !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(context, space: space),
              (try? recoveryState(space)) == context, space.lastUpdate == revision,
              SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == revision,
              P.integer(local["updateTimestamp"]) == revision,
              let localConfiguration = P.configurationData(local),
              let profilesMatch = P.sharedProfilesMatch(localConfiguration, actual) else {
            return failure("profileLocalSnapshotUnavailable")
        }
        if revision == remoteTimestamp, !profilesMatch { return failure("profileTimestampConflict", review: true) }
        guard revision >= 0, revision < Int64.max else { return failure("profileLocalVersionInvalid") }
        if remoteTimestamp > revision {
            guard space.applyNewerCloudProfiles(remote, expectedRevision: revision) else {
                return failure("profileMergePersistence")
            }
        }
        // Rebase the cloud reference, not the confirmation timestamp. The next
        // complete upload must still be accepted and read back before becoming clean.
        do {
            var state = try recoveryState(space)
            guard state == context else { return failure("profileMergeSuperseded") }
            state.authorizationBaseline = actual
            state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(remote)
            state.nodeIdentitiesBaseline = remoteNodes
            state.timedConfigurationBaseline = timed
            state.schedulerModelStatesBaseline = models
            state.submission = nil
            try saveState(state, space: space)
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            let blockedKey = "spaceConfigurationBlocked." + key(space)
            let reason = UserDefaults.standard.string(forKey: blockedKey) ?? ""
            if ["uploadReadbackConflict", "uploadReadbackUnconfirmed", "profileTimestampConflict", "cloudConfigurationConflict"].contains(reason) {
                UserDefaults.standard.removeObject(forKey: blockedKey)
            }
            space.syncCloudError = nil
            #if DEBUG
            print("[SpaceProfileResolution] space=\(space.id) local=\(revision) remote=\(remoteTimestamp) "
                + "winner=\(remoteTimestamp > revision ? "cloud" : "local") pendingReplaced=\(context.submission != nil)")
            #endif
            return true
        } catch { return failure("profileMergeReceiptPersistence") }
    }

    /// Accept cloud membership removals even when its revision/count was not updated. The
    /// comparison uses a confirmed snapshot, never unsent local additions.
    @MainActor
    static func reconcileSameVersionNodeRemoval(_ space: SpaceData, remote: [String: Any]) async -> OlderCloudBaselineResult {
        typealias P = SpaceConfigurationIntegrityPolicy
        typealias Snapshot = SpaceCloudNodeRemovalPolicy.Snapshot
        // Visitors use the ordinary authoritative importer and never repair local references.
        guard space.permission != .visitor else { return .notApplicable }
        guard !hasPendingImport(space), !requiresAuthorityImport(space),
              SpaceMembershipCoordinator.accepts(remote),
              let state = try? recoveryState(space), state.phase == .active,
              remote["uuid"] as? String == space.id,
              let timestamp = state.submission?.timestamp ?? space.lastUploadCloudTimestamp,
              let remoteTimestamp = P.integer(remote["updateTimestamp"]),
              remoteTimestamp >= timestamp, remoteTimestamp < Int64.max,
              let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote) else { return .notApplicable }
        var snapshot = state.submission?.removalSnapshot ?? (state.submission == nil ? state.removalSnapshot : nil)
        let source = state.submission?.nodeIdentities
            ?? (state.submission == nil ? state.nodeIdentitiesBaseline : nil) ?? snapshot?.identities
        if snapshot?.comparisonVersion != 3 { snapshot = nil }
        if source == nil && snapshot == nil { return .notApplicable }
        if let source, remoteNodes.count >= source.count { return .notApplicable }
        func failure(_ reason: String) -> OlderCloudBaselineResult {
            let needsReview = reason == "completeBaselineUnavailable" || reason == "notOnlyNodeRemoval"
            if needsReview {
                block(space, reason: reason == "completeBaselineUnavailable" ? "cloudBaselineNeedsReview" : "cloudConfigurationConflict")
            }
            recordSyncFailure(space, error: needsReview ? .configurationReviewRequired : uploadUnconfirmed,
                              stage: "sameVersionRemoval." + reason, remoteTimestamp: timestamp)
            return .failed(reason)
        }
        if let submission = state.submission, submission.phase != .accepted { return failure("unacceptedSubmission") }
        if state.submission?.permitsCloudRemoval == false,
           state.prefersLocalMembership != true, state.localReplacementVersion == nil {
            return failure("unknownSubmissionOutcome")
        }
        // Old recovery files lack full-field hashes. Only an exact confirmed or
        // accepted generation may supply them; an arbitrary export is not proof.
        if snapshot == nil,
           let data = try? Data(contentsOf: storedDirectory(space, state: state).appendingPathComponent("last-complete-export.json")),
           let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
           P.integer(payload["updateTimestamp"]) == timestamp, payload["uuid"] as? String == space.id,
           sameNodeIdentities(SpaceCloudNodeRemovalPolicy.instances(payload), source) {
            snapshot = Snapshot.make(payload)
        }
        let revision = space.lastUpdate
        let membership = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        if snapshot == nil, state.submission == nil, revision == timestamp, !space.needUploadCloud {
            let local = await space.export(purpose: .cleanupInspection)
            guard !Task.isCancelled, isCurrent(state, space: space), (try? recoveryState(space)) == state,
                  space.lastUpdate == revision else { return failure("superseded") }
            guard let persisted = SpaceData.load(siteId: space.siteId, spaceId: space.id).first else {
                return failure("superseded")
            }
            guard persisted.lastUpdate == revision else {
                space.applyConfigurationState(from: persisted)
                return failure("superseded")
            }
            if var local, source == nil || sameNodeIdentities(SpaceCloudNodeRemovalPolicy.instances(local), source) {
                // A pre-scene receipt never submitted the new empty extension. Normalize
                // only this legacy fallback, never a new POST or its GET readback.
                if P.needsSceneComparisonUpgrade(state.authorizationBaseline),
                   (remote["spaceData"] as? [String: Any])?["sceneConfigurations"] == nil,
                   var extensionData = local["spaceData"] as? [String: Any],
                   (extensionData["sceneConfigurations"] as? [Any])?.isEmpty == true {
                    extensionData.removeValue(forKey: "sceneConfigurations")
                    local["spaceData"] = extensionData.isEmpty && remote["spaceData"] == nil ? nil : extensionData
                }
                snapshot = Snapshot.make(local)
            }
        }
        guard let identities = source ?? snapshot?.identities else { return failure("completeBaselineUnavailable") }
        guard remoteNodes.count < identities.count else { return .notApplicable }
        guard let missing = SpaceCloudNodeRemovalPolicy.removed(from: identities, remote: remoteNodes),
              !missing.isEmpty, let incoming = Snapshot.make(remote) else { return failure("notOnlyNodeRemoval") }
        // Old receipts may retain only identities plus logical configuration.
        // Raw full-node hashes from older Apps are not membership evidence.
        if let snapshot, snapshot.removals(in: incoming) == nil { return failure("notOnlyNodeRemoval") }
        if snapshot == nil {
            guard let baseline = state.submission?.configuration ?? state.authorizationBaseline,
                  let expected = SpaceCloudNodeRemovalPolicy.projectConfiguration(baseline, removing: missing),
                  let actual = P.configurationData(remote).flatMap({ SpaceCloudNodeRemovalPolicy.projectConfiguration($0, removing: missing) }),
                  P.configurationsMatch(expected, actual),
                  let timed = state.submission?.timedConfiguration ?? state.timedConfigurationBaseline,
                  let expectedTimed = TimedSchedulerPayloadPolicy.removingNodes(from: timed,
                    uuids: Set(missing.map(\.uuid)),
                    addresses: Set(missing.flatMap { $0.elementAddresses }.map { String(format: "%04X", $0) })),
                  let actualTimed = TimedSchedulerPayloadPolicy.canonical(remote).flatMap({
                    TimedSchedulerPayloadPolicy.removingNodes(from: $0, uuids: Set(missing.map(\.uuid)),
                        addresses: Set(missing.flatMap { $0.elementAddresses }.map { String(format: "%04X", $0) }))
                  }), expectedTimed == actualTimed,
                  let models = state.submission?.schedulerModelStates ?? state.schedulerModelStatesBaseline,
                  SpaceCloudNodeRemovalPolicy.projectModels(models, removing: missing) == SchedulerModelSnapshot.spaceData(remote)
            else { return failure("notOnlyNodeRemoval") }
        }
        let removed = missing + readbackRemovals(timestamp: timestamp, space: space).filter { old in
            !missing.contains { $0.uuid == old.uuid && $0.address == old.address }
                && !remoteNodes.contains { $0.uuid == old.uuid && $0.address == old.address }
        }
        guard canAutomaticallyUpload(space), !Task.isCancelled, isCurrent(state, space: space),
              SpaceMembershipResponseContext.matches(membership, account: UserData.currentUserId,
                region: String(describing: UserData.currentServerRegion)),
              (try? recoveryState(space)) == state, space.lastUpdate == revision,
              let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let keys = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId),
              keys.fingerprint == SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId)?.fingerprint,
              let configuration = P.configurationData(remote),
              let projected = SpaceCloudNodeRemovalPolicy.projectConfiguration(configuration, removing: removed),
              let timed = TimedSchedulerPayloadPolicy.canonical(remote),
              let cleanedTimed = TimedSchedulerPayloadPolicy.removingNodes(from: timed, uuids: Set(removed.map(\.uuid)),
                addresses: Set(removed.flatMap { $0.elementAddresses }.map { String(format: "%04X", $0) })),
              let models = SchedulerModelSnapshot.spaceData(remote),
              P.scheduleTargetIssue(in: remote) == nil,
              let resolved = DevicePermanentDeletionContext.cloudRemovalInstances(space: space, expected: missing) else {
            return failure("identityOrAuthority")
        }
        guard checkpoint(space, refresh: !hasPendingDeletionCleanup(space)) else { return failure("checkpoint") }
        do {
            var updated = state
            // Persist the proof before clearing the old phone-first veto. If
            // cleanup fails, the same proof and journal remain retryable.
            if updated.submission != nil {
                updated.submission?.removalSnapshot = snapshot
                updated.submission?.permitsCloudRemoval = true
            } else { updated.removalSnapshot = snapshot }
            updated.prefersLocalMembership = nil
            updated.localReplacementVersion = nil
            try saveState(updated, space: space)
            guard DevicePermanentDeletionContext.removeCloudInstances(space: space, instances: resolved,
                baselineTimestamp: timestamp, remoteTimestamp: remoteTimestamp, submissionID: state.submission?.id) else {
                return failure("cleanupPersistence")
            }
            var current = try recoveryState(space)
            guard current.matches(state), current.submission?.id == state.submission?.id else { return failure("superseded") }
            if current.submission == nil {
                current.authorizationBaseline = projected
                current.nodeIdentitiesBaseline = remoteNodes
                current.timedConfigurationBaseline = cleanedTimed
                current.schedulerModelStatesBaseline = models
                current.removalSnapshot = incoming
            }
            try saveState(current, space: space)
            let blockedKey = "spaceConfigurationBlocked." + key(space)
            if ["cloudBaselineNeedsReview", "cloudConfigurationConflict"].contains(UserDefaults.standard.string(forKey: blockedKey) ?? "") {
                SpaceProtectionReadGeneration.beginMutation()
                UserDefaults.standard.removeObject(forKey: blockedKey)
                SpaceProtectionReadGeneration.endMutation()
            }
            space.syncCloudError = nil
            #if DEBUG
            print("[SpaceCloudMembership] space=\(space.id) sameVersionRemoval=\(missing.count) remote=\(remoteTimestamp)")
            #endif
            return .preserveLocal
        } catch { return failure("receiptPersistence") }
    }

    /// A retained explicit recovery choice is clean only when all Nodes and
    /// configuration are present. Pure removals are handled before this check.
    static func localMembershipReadbackMatches(configuration: Data?, identities: [SpaceCloudNodeRemovalPolicy.Instance]?,
                                               timed: Data?, models: Data?, targets: Data?, remote: [String: Any]) -> Bool {
        typealias P = SpaceConfigurationIntegrityPolicy
        guard let configuration, let identities, let timed, let models, let targets,
              sameNodeIdentities(identities, SpaceCloudNodeRemovalPolicy.instances(remote)),
              P.configurationsMatch(configuration, P.configurationData(remote)), P.scheduleTargetsData(remote) == targets,
              models == SchedulerModelSnapshot.spaceData(remote), timed == TimedSchedulerPayloadPolicy.canonical(remote) else { return false }
        return true
    }

    /// Honor an existing explicit phone-first recovery outside the proven
    /// same-version removal path. A smaller GET no longer creates this choice.
    @MainActor
    static func preserveLocalMembershipIfNeeded(_ space: SpaceData, remote: [String: Any]) async -> OlderCloudBaselineResult {
        typealias P = SpaceConfigurationIntegrityPolicy
        guard canAutomaticallyUpload(space), !requiresAuthorityImport(space), !hasPendingImport(space),
              !isBlocked(space), let state = try? recoveryState(space), state.submission == nil,
              let confirmed = space.lastUploadCloudTimestamp,
              let remoteTimestamp = P.integer(remote["updateTimestamp"]), remoteTimestamp >= 0, remoteTimestamp < Int64.max,
              remote["uuid"] as? String == space.id,
              let journal = try? deletionJournal(space) else { return .notApplicable }
        let prefersLocal = state.prefersLocalMembership == true || state.localReplacementVersion != nil
        let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote) ?? []
        let reappeared = journal.entries.contains { entry in
            entry.stage == .cleaned && entry.cloudRemoval != nil
                && (entry.completedTimestamp ?? 0) > confirmed
                && remoteNodes.contains { entry.cloudRemoval!.instance.matches($0) }
        }
        guard prefersLocal else { return .notApplicable }
        func failure(_ reason: String) -> OlderCloudBaselineResult {
            recordSyncFailure(space, error: uploadUnconfirmed, stage: "localMembership." + reason,
                              remoteTimestamp: confirmed)
            return .failed(reason)
        }
        guard !hasPendingDeletionCleanup(space), !hasPendingReferenceCleanup(space) else { return failure("cleanupPending") }
        let revision = space.lastUpdate
        guard let local = await space.export(purpose: .cleanupInspection),
              !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(state, space: space),
              (try? recoveryState(space)) == state, space.lastUpdate == revision,
              SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == revision,
              canAutomaticallyUpload(space), !hasPendingImport(space),
              let localKeys = SpaceKeyIntegrity.pair(local, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              localKeys.fingerprint == remoteKeys.fingerprint,
              SpaceCloudNodeRemovalPolicy.instances(local) != nil,
              P.configurationData(local) != nil, P.scheduleTargetIssue(in: local) == nil,
              TimedSchedulerPayloadPolicy.canonical(local) != nil, SchedulerModelSnapshot.spaceData(local) != nil,
              revision < Int64.max, confirmed < Int64.max else { return failure("localSnapshotOrAuthority") }
        // Preserve the first conflicting pair for diagnosis, not each retry.
        if state.prefersLocalMembership != true {
            guard checkpoint(space, refresh: true),
                  saveRecoveryPayload(space, name: "before-local-membership-local.json", payload: local),
                  saveRecoveryPayload(space, name: "before-local-membership-remote.json", payload: remote) else { return failure("backup") }
        }
        let alreadyConfirmed = prefersLocal && !space.needUploadCloud && (remoteTimestamp < confirmed || localMembershipReadbackMatches(
            configuration: P.configurationData(local), identities: SpaceCloudNodeRemovalPolicy.instances(local),
            timed: TimedSchedulerPayloadPolicy.canonical(local), models: SchedulerModelSnapshot.spaceData(local),
            targets: P.scheduleTargetsData(local), remote: remote))
        do {
            var updated = state
            updated.prefersLocalMembership = true
            try saveState(updated, space: space)
        } catch { return failure("receiptPersistence") }
        if !alreadyConfirmed && (!space.needUploadCloud || revision <= remoteTimestamp) {
            space.lastUpdate = max(revision, remoteTimestamp)
            space.markLocalChangePendingCloudSync()
            guard space.save() else { space.lastUpdate = revision; return failure("localPersistence") }
        }
        UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        space.syncCloudError = nil
        #if DEBUG
        print("[SpaceLocalMembership] preserved localNodes=\((local["nodes"] as? [Any])?.count ?? -1) remoteNodes=\(remoteNodes.count) baselineNodes=\(state.nodeIdentitiesBaseline?.count ?? 0) reappeared=\(reappeared)")
        #endif
        return .preserveLocal
    }

    /// Reconcile the current Space's authoritative membership before a pending
    /// submission or local edit prevents ordinary import. No destination lookup.
    @MainActor
    static func reconcileCloudMembership(_ space: SpaceData, remote: [String: Any]) -> Bool {
        guard canAutomaticallyUpload(space), !hasPendingImport(space),
              let state = try? recoveryState(space), remote["uuid"] as? String == space.id else { return true }
        let submission = state.submission
        if state.prefersLocalMembership == true { return true }
        if let submission, submission.phase != .accepted || submission.permitsCloudRemoval == false { return true }
        // With no protected local work, the existing full import applies remote
        // additions and other configuration edits together with the removals.
        guard submission != nil || space.needUploadCloud || preservesLocalChanges(space) else { return true }
        guard let timestamp = submission?.timestamp ?? space.lastUploadCloudTimestamp,
              let configuration = submission?.configuration ?? state.authorizationBaseline,
              let source = submission?.nodeIdentities ?? (submission == nil ? state.nodeIdentitiesBaseline : nil)
                ?? SpaceCloudNodeRemovalPolicy.legacyInstances(configuration: configuration,
                    models: submission?.schedulerModelStates ?? state.schedulerModelStatesBaseline) else { return true }
        guard !source.isEmpty else { return true }
        func failure(_ reason: String) -> Bool {
            #if DEBUG
            print("[SpaceCloudMembership] reason=\(reason) baselineNodes=\(source.count) remoteNodes=\((remote["nodes"] as? [Any])?.count ?? -1) pendingSubmission=\(submission != nil)")
            #endif
            return recordSyncFailure(space, error: uploadUnconfirmed, stage: "cloudMembership." + reason,
                                     remoteTimestamp: SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]))
        }
        guard let remoteTimestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              remoteTimestamp >= timestamp, remoteTimestamp < Int64.max else { return failure("remoteVersion") }
        guard let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote) else { return failure("remoteNodeIdentities") }
        guard remote["groups"] is [[String: Any]], remote["scenes"] is [[String: Any]], remote["schedules"] is [[String: Any]],
              let remoteConfiguration = SpaceConfigurationIntegrityPolicy.configurationData(remote) else { return failure("remoteConfiguration") }
        guard let remoteModels = SchedulerModelSnapshot.spaceData(remote) else { return failure("remoteSchedulerModels") }
        guard let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let localKeys = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId) else { return failure("localNetworkKeys") }
        guard let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              localKeys.fingerprint == remoteKeys.fingerprint,
              submission?.keyFingerprint == nil || submission?.keyFingerprint == remoteKeys.fingerprint else { return failure("networkIdentityMismatch") }
        guard let missing = SpaceCloudNodeRemovalPolicy.removed(from: source, remote: remoteNodes) else {
            if submission == nil && !space.needUploadCloud { return true }
            block(space, reason: "cloudMembershipConflict")
            return recordSyncFailure(space, error: .configurationReviewRequired, stage: "cloudMembershipConflict",
                                     remoteTimestamp: remoteTimestamp)
        }
        if missing.isEmpty, submission != nil { return true } // Keep ordinary readback retries for unchanged membership.
        if !missing.isEmpty {
            guard (try? SpaceSyncCleanupPolicy.normalize(remote)) != nil,
                  SpaceConfigurationIntegrityPolicy.scheduleTargetIssue(in: remote) == nil else { return failure("invalidRemovalReferences") }
        }
        let completed = readbackRemovals(timestamp: timestamp, space: space)
        let stillOnCloud = completed.filter { old in
            remoteNodes.contains { $0.uuid == old.uuid && $0.address == old.address }
        }
        if !stillOnCloud.isEmpty {
            // A local cross-Space handoff must be uploaded BEFORE GET can omit
            // its old instance. Accepted receipts and authoritative cloud removals
            // still require absence; neither may use this pre-upload exception.
            guard submission == nil, let journal = try? deletionJournal(space),
                  stillOnCloud.allSatisfy({ old in
                      journal.entries.contains { entry in
                          entry.stage == .cleaned && entry.cloudRemoval == nil && entry.replacement != nil
                              && entry.nodeUUID.uppercased() == old.uuid && entry.primaryAddress == old.address
                              && entry.elementAddresses == old.elementAddresses
                              && (entry.completedTimestamp ?? 0) > timestamp
                              && (entry.completedTimestamp ?? Int64.max) <= space.lastUpdate
                      }
                  }) else { return failure("completedRemovalStillOnCloud") }
        }
        // Compare the cloud against only removals already reflected by its GET.
        // Local handoffs still on the cloud stay in the baseline until POST/GET
        // confirms the newer local version, including its Timed/Model cleanup.
        let cloudCompleted = completed.filter { old in
            !stillOnCloud.contains { $0.uuid == old.uuid && $0.address == old.address }
        }
        let pending = missing.filter { node in !completed.contains { $0.uuid == node.uuid && $0.address == node.address } }
        guard let resolved = DevicePermanentDeletionContext.cloudRemovalInstances(space: space, expected: pending) else { return failure("localRemovalIdentity") }
        let removed = cloudCompleted + resolved
        guard
              let expected = SpaceCloudNodeRemovalPolicy.projectConfiguration(configuration, removing: removed),
              let actual = SpaceCloudNodeRemovalPolicy.projectConfiguration(remoteConfiguration, removing: removed) else { return failure("configurationProjection") }
        guard SpaceConfigurationIntegrityPolicy.configurationsMatch(expected, actual) else {
            block(space, reason: "cloudConfigurationConflict")
            return recordSyncFailure(space, error: .configurationReviewRequired, stage: "cloudConfigurationConflict",
                                     remoteTimestamp: remoteTimestamp)
        }
        let modelBaseline = submission?.schedulerModelStates ?? state.schedulerModelStatesBaseline
        if let modelBaseline {
            guard SpaceCloudNodeRemovalPolicy.projectModels(modelBaseline, removing: removed) == remoteModels else { return failure("schedulerModelsChanged") }
        }
        if let timed = submission?.timedConfiguration ?? state.timedConfigurationBaseline {
            guard TimedSchedulerPayloadPolicy.removingNodes(from: timed,
                uuids: Set(removed.map(\.uuid)), addresses: Set(removed.flatMap { $0.elementAddresses.union([$0.address]) }.map { String(format: "%04X", $0) }))
                == TimedSchedulerPayloadPolicy.canonical(remote).flatMap({
                    TimedSchedulerPayloadPolicy.removingNodes(from: $0, uuids: Set(removed.map(\.uuid)),
                        addresses: Set(removed.flatMap { $0.elementAddresses.union([$0.address]) }.map { String(format: "%04X", $0) }))
                }) else { return failure("timedConfigurationChanged") }
        }
        if let targets = submission?.scheduleTargets {
            guard SpaceConfigurationIntegrityPolicy.scheduleTargetsData(remote) == targets else { return failure("scheduleTargetsChanged") }
        }
        guard !pending.isEmpty else { return true }
        guard DevicePermanentDeletionContext.removeCloudInstances(space: space, instances: resolved,
            baselineTimestamp: timestamp, remoteTimestamp: remoteTimestamp, submissionID: submission?.id) else {
            block(space, reason: "deletionCleanupPending")
            return failure("cleanupPersistence")
        }
        // A baseline-only cleanup has no pending submission to finish later.
        // Retain the newer local cleanup generation for the next complete upload.
        if submission == nil {
            do {
                var current = try recoveryState(space)
                guard current.matches(state), current.submission == nil else { return failure("superseded") }
                current.authorizationBaseline = expected
                current.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(remote)
                current.schedulerModelStatesBaseline = remoteModels
                current.nodeIdentitiesBaseline = remoteNodes
                try saveState(current, space: space)
            } catch { return failure("baselinePersistence") }
        }
        #if DEBUG
        print("[SpaceCloudMembership] space=\(space.id) removed=\(removed.count) remaining=\(remoteNodes.count) source=\(timestamp) remote=\(remoteTimestamp)")
        #endif
        return true
    }

    private static func migratePendingUpload(_ space: SpaceData) throws {
        lock.lock(); defer { lock.unlock() }
        var state = try recoveryState(space)
        guard state.phase == .active else { return }
        let needsInitialization = !SpaceMembershipCoordinator.allowsConfiguration(space)
        let missingFields = state.submission.map {
            $0.keyFingerprint == nil || $0.nodeIdentities == nil || $0.scheduleTargets == nil
                || $0.timedConfiguration == nil || $0.schedulerModelStates == nil
        } ?? false
        let hasLegacyMarker = state.submission == nil
            && UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) == "uploadReadbackUnconfirmed"
        guard hasLegacyMarker || (needsInitialization && missingFields) else { return }

        // A missing field is not an empty configuration. Only the saved export
        // of this exact submitted generation can supply historical evidence.
        let url = storedDirectory(space, state: state).appendingPathComponent("last-complete-export.json")
        guard let data = try? Data(contentsOf: url),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw PendingUploadValidationError(reason: "legacySnapshotUnavailable")
        }
        guard payload["uuid"] as? String == space.id,
              let timestamp = SpaceConfigurationIntegrityPolicy.integer(payload["updateTimestamp"]),
              let configuration = SpaceConfigurationIntegrityPolicy.configurationData(payload),
              payload["nodes"] is [[String: Any]],
              let models = SchedulerModelSnapshot.spaceData(payload) else {
            throw PendingUploadValidationError(reason: "legacySnapshotInvalid")
        }
        let keys = SpaceKeyIntegrity.pair(payload, networkID: space.meshNetworkId)
        let targets = SpaceConfigurationIntegrityPolicy.scheduleTargetsData(payload)
        let timed = TimedSchedulerPayloadPolicy.canonical(payload)
        let identities = SpaceCloudNodeRemovalPolicy.instances(payload)
        var submission = state.submission ?? .init(id: UUID(), timestamp: timestamp,
            configuration: configuration, phase: .accepted, keyFingerprint: keys?.fingerprint,
            scheduleTargets: targets, timedConfiguration: timed, schedulerModelStates: models,
            nodeIdentities: identities, permitsCloudRemoval: false)
        if needsInitialization {
            guard submission.timestamp == timestamp,
                  SpaceConfigurationIntegrityPolicy.configurationsMatch(configuration, submission.configuration) else {
                throw PendingUploadValidationError(reason: "legacySnapshotGenerationMismatch")
            }
            guard let keys, let targets, let timed, let identities,
                  let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                  let localKeys = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId),
                  localKeys.fingerprint == keys.fingerprint else {
                throw PendingUploadValidationError(reason: "legacySnapshotIdentityOrFieldsInvalid")
            }
            guard submission.keyFingerprint.map({ $0 == keys.fingerprint }) ?? true,
                  submission.scheduleTargets.map({ $0 == targets }) ?? true,
                  submission.timedConfiguration.map({ $0 == timed }) ?? true,
                  submission.schedulerModelStates.map({ $0 == models }) ?? true,
                  submission.nodeIdentities.map({ sameNodeIdentities($0, identities) }) ?? true else {
                throw PendingUploadValidationError(reason: "legacySnapshotReceiptMismatch")
            }
            submission.keyFingerprint = keys.fingerprint
            submission.scheduleTargets = targets
            submission.timedConfiguration = timed
            submission.schedulerModelStates = models
            submission.nodeIdentities = identities
            // Newly reconstructed fields have not been verified by the old GET.
            submission.phase = .accepted
            submission.permitsCloudRemoval = false
        }
        state.submission = submission
        try saveState(state, space: space)
    }

    @MainActor
    static func finishCloudRemovalUpload(_ space: SpaceData) async -> Swift.Result<Void, NetworkApiError> {
        // A removal first discovered in the POST readback creates a newer
        // cleanup generation. Do not finish that sync handle before it is verified.
        while !_Concurrency.Task<Never, Never>.isCancelled {
            guard let journal = try? deletionJournal(space) else { return .failure(uploadUnconfirmed) }
            let pending = journal.entries.contains {
                $0.cloudRemoval != nil && $0.stage == .cleaned
                    && ($0.completedTimestamp ?? 0) > (space.lastUploadCloudTimestamp ?? 0)
            }
            guard pending else { return .success(()) }
            guard space.needUploadCloud else { return .failure(uploadUnconfirmed) }
            let result = await uploadBeforeUnbind(space)
            if case .failure = result { return result }
        }
        return .failure(uploadUnconfirmed)
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
        if space.requiresPasswordVerification { return .spacePasswordOverdue }
        if space.permission == .visitor || space.disableEditorPermission { return .noSpacePermission }
        if let state = try? recoveryState(space) {
            if state.authority == .readOnly || state.authority == .revoked { return .noSpacePermission }
            if state.authority == .waitingForAuthorization { return .userUnauthorized }
        }
        return .configurationUnavailable
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
                state.removalSnapshot = nil
                state.nodeIdentitiesBaseline = nil
                state.olderCloudBaselineFailure = nil
                state.localReplacementVersion = nil
                state.prefersLocalMembership = nil
                state.defaultRecoverySource = nil
                state.timedConfigurationBaseline = nil
                state.schedulerModelStatesBaseline = nil
                state.requiresRemoteImport = true
            }
            state.authority = authority
            try saveState(state, space: space)
            if authority == .readOnly || authority == .revoked { clearActiveMarkers(space) }
        } catch { block(space, reason: "authorityPersistenceFailed") }
    }

    static func syncReadRequest(meshUUID: String, networkId: String) -> SpaceProtectionReadRequest {
        .init(scope: .init(account: UserData.currentUserId, region: String(describing: UserData.currentServerRegion),
                           meshUUID: meshUUID, networkID: networkId), root: recoveryRoot, defaults: .standard)
    }

    static func configurationAvailable(for node: Node, group: Group? = nil,
                                       protectionSnapshot: SpaceProtectionReadSnapshot? = nil) -> Bool {
        if protectionSnapshot == nil,
           let value = NodeSyncReadContext.current?.configurationAvailable(for: node, group: group) { return value }
        let group = group ?? node.group
        if let group, !group.isVirtual, group.info.profileLoadFailed || group.info.topologyLoadFailed { return false }
        guard let uuid = node.network?.uuid.uuidString,
              let networkId = node.subNetworkId else { return protectionSnapshot == nil }
        if node.network?.groups.contains(where: {
            !$0.isVirtual && $0.subNetworkId == networkId
                && ($0.info.profileLoadFailed || $0.info.topologyLoadFailed)
        }) == true { return false }
        if let protectionSnapshot {
            // This is a pure read optimization, never deletion authorization.
            // A changed generation/account/network fails closed.
            guard protectionSnapshot.scope.account == UserData.currentUserId,
                  protectionSnapshot.scope.region == String(describing: UserData.currentServerRegion),
                  protectionSnapshot.scope.meshUUID == uuid,
                  protectionSnapshot.scope.networkID == networkId else { return false }
            return !protectionSnapshot.isBlocked
        }
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

    /// Older recovery receipts predate the Timed baseline field. The generic
    /// migration marker cannot authorize the first Timed schema migration.
    static func needsTimedUpgradeBaseline(_ space: SpaceData) -> Bool {
        space.uploadCloud && space.timedSchemaVersion < 2
            && (try? recoveryState(space).timedConfigurationBaseline) == nil
    }

    static func verifyUpgradeBaseline(_ space: SpaceData, local: [String: Any], remote: [String: Any]) {
        var started = ProcessInfo.processInfo.systemUptime
        func mark(_ phase: String) {
            let now = ProcessInfo.processInfo.systemUptime
            #if DEBUG
            print("[SiteImportBaseline] space=\(space.id) phase=\(phase) seconds=\(now - started) main=\(Thread.isMainThread)")
            #endif
            started = now
        }
        guard !isBlocked(space), remote["uuid"] as? String == space.id,
              let localKeys = SpaceKeyIntegrity.pair(local, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              localKeys.fingerprint == remoteKeys.fingerprint,
              let expected = SpaceConfigurationIntegrityPolicy.upgradeConfigurationData(local),
              expected == SpaceConfigurationIntegrityPolicy.upgradeConfigurationData(remote) else {
            mark("comparisonRejected")
            return
        }
        mark("comparisonMatched")
        guard checkpoint(space) else { mark("checkpointFailed"); return }
        mark("checkpointCompleted")
        guard recordSnapshot(space, payload: local) else { mark("snapshotFailed"); return }
        mark("snapshotCompleted")
        if var state = try? recoveryState(space) {
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
            state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(remote)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(remote)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
            do {
                try saveState(state, space: space)
                UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            } catch { mark("statePersistenceFailed") }
        }
    }

    static func pendingImport(_ space: SpaceData) -> [String: Any]? {
        guard let url = try? directory(space).appendingPathComponent("pending-import.json"),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["uuid"] as? String == space.id else { return reviewedCloudImport(space)?.payload }
        return payload
    }

    static func hasPendingImport(_ space: SpaceData) -> Bool {
        guard let url = try? directory(space).appendingPathComponent("pending-import.json") else { return true }
        return FileManager.default.fileExists(atPath: url.path)
            || FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent("reviewed-cloud-import.json").path)
    }

    #if DEBUG
    /// Unlike directory()/recoveryState(), this inspection never creates a journal.
    static func canReadDebugSnapshot(_ space: SpaceData) -> Bool {
        // A pending import or recovery journal is evidence to export, not an
        // access restriction. Snapshot revision checks handle concurrent writes.
        space.state == .normal
    }

    static func debugSnapshotStatus(_ space: SpaceData) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        var result: [String: Any] = ["state": space.state.rawValue]
        if let membership = try? SpaceMembershipCoordinator.store.read(SpaceMembershipCoordinator.scope(space)) {
            result["membershipPhase"] = membership.phase.rawValue
            result["configurationInitialized"] = membership.initialized
            result["membershipNetworkMatches"] = membership.networkID == space.meshNetworkId
        }
        result["blockedReason"] = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space))
        do {
            let state = try SpaceRecoveryState.read(from: stateURL(space), identity: identity(space))
            result["recoveryPhase"] = state?.phase.rawValue
            result["recoveryAuthority"] = state?.authority.rawValue
            result["requiresRemoteImport"] = state?.requiresRemoteImport == true
            result["unbindRequested"] = state?.unbindRequested == true
            let legacyMarker = result["blockedReason"] as? String == "uploadReadbackUnconfirmed"
            result["legacyUploadMarker"] = legacyMarker
            result["pendingUpload"] = state?.submission != nil || legacyMarker
            result["submissionPhase"] = state?.submission?.phase.rawValue
            result["submittedTimestamp"] = state?.submission?.timestamp
            result["lastConfirmedTimestamp"] = space.lastUploadCloudTimestamp
            result["localTimestamp"] = space.lastUpdate
            result["baselineSHA256"] = SpaceConfigurationIntegrityPolicy.configurationFingerprint(state?.authorizationBaseline)
            result["baselineFields"] = ["configuration": state?.authorizationBaseline != nil,
                "nodeIdentities": state?.nodeIdentitiesBaseline != nil,
                "schedulerModels": state?.schedulerModelStatesBaseline != nil,
                "timed": state?.timedConfigurationBaseline != nil]
            result["submissionSHA256"] = SpaceConfigurationIntegrityPolicy.configurationFingerprint(state?.submission?.configuration)
            result["lastSyncDiagnostic"] = UserDefaults.standard.dictionary(forKey: "spaceConfigurationLastSyncDiagnostic." + key(space))
            result["lastReadbackDiagnostic"] = UserDefaults.standard.dictionary(forKey: "spaceConfigurationLastReadbackDiagnostic." + key(space))
            result["lastBaselineDiagnostic"] = UserDefaults.standard.dictionary(forKey: "spaceConfigurationLastBaselineDiagnostic." + key(space))
            if let submission = state?.submission {
                result["submissionFields"] = [
                    "keyFingerprint": submission.keyFingerprint != nil,
                    "nodeIdentities": submission.nodeIdentities != nil,
                    "scheduleTargets": submission.scheduleTargets != nil,
                    "timedConfiguration": submission.timedConfiguration != nil,
                    "schedulerModelStates": submission.schedulerModelStates != nil
                ]
                if let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                   let keys = SpaceKeyIntegrity.pair(network, networkID: space.meshNetworkId),
                   let fingerprint = submission.keyFingerprint {
                    result["submissionLocalKeysMatch"] = keys.fingerprint == fingerprint
                }
            }
            let folder = state.map { storedDirectory(space, state: $0) }
                ?? recoveryRoot.appendingPathComponent(key(space))
            result["hasCompleteExportSnapshot"] = FileManager.default.fileExists(atPath: folder.appendingPathComponent("last-complete-export.json").path)
            result["pendingImport"] = FileManager.default.fileExists(atPath: folder.appendingPathComponent("pending-import.json").path)
                || FileManager.default.fileExists(atPath: folder.appendingPathComponent("reviewed-cloud-import.json").path)
            result["pendingDeletionCleanup"] = deletionCleanupPending(at: folder.appendingPathComponent("device-deletions.json"))
            if let journal = try? deletionJournal(space) {
                result["deletionSummary"] = journal.entries.map { entry -> [String: Any] in
                    var value: [String: Any] = ["uuid": entry.nodeUUID, "address": Int(entry.primaryAddress),
                        "elementCount": entry.elementAddresses.count, "stage": entry.stage.rawValue,
                        "kind": entry.cloudRemoval != nil ? "cloudRemoval" : (entry.replacement != nil ? "replacement" : "localDeletion")]
                    value["completedTimestamp"] = entry.completedTimestamp
                    value["cloudBaselineTimestamp"] = entry.cloudRemoval?.baselineTimestamp
                    return value
                }
            }
            result["baselineNodeCount"] = state?.nodeIdentitiesBaseline?.count
            result["prefersLocalMembership"] = state?.prefersLocalMembership == true
        } catch {
            result["recoveryReadError"] = String(describing: error)
        }
        return result
    }
    #endif

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
            #if DEBUG
            print("[SpaceConfigurationSafety] checkpoint failed space=\(space.id) error=\(error)")
            #endif
            return false
        }
    }

    static func beginImport(_ space: SpaceData, payload: [String: Any]) -> Bool {
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
        do {
            let url = try directory(space).appendingPathComponent("pending-import.json")
            if validatedTopology {
                var state = try recoveryState(space)
                let payload = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
                let original = payload.flatMap { originalReferenceCleanupImport(space, candidate: $0) }
                state.authorizationBaseline = (original ?? payload).flatMap(SpaceConfigurationIntegrityPolicy.configurationData)
                state.removalSnapshot = (original ?? payload).flatMap(SpaceCloudNodeRemovalPolicy.Snapshot.make)
                state.timedConfigurationBaseline = payload.flatMap(TimedSchedulerPayloadPolicy.canonical)
                state.schedulerModelStatesBaseline = payload.flatMap(SchedulerModelSnapshot.spaceData)
                state.nodeIdentitiesBaseline = (original ?? payload).flatMap(SpaceCloudNodeRemovalPolicy.instances)
                state.olderCloudBaselineFailure = nil
                state.localReplacementVersion = nil
                state.prefersLocalMembership = nil
                let reviewed = reviewedCloudImport(space)
                if let reviewed, let source = reviewed.defaultSource {
                    // The selected server Nodes are now installed. This phone's old
                    // submission is superseded, never merged back into that snapshot.
                    state.submission = nil
                    state.defaultRecoverySource = reviewed.needsUpload ? source : nil
                    if reviewed.needsUpload {
                        space.lastUpdate = max(space.lastUpdate, reviewed.timestamp)
                        space.markLocalChangePendingCloudSync()
                        guard space.save() else { return false }
                        state.localReplacementVersion = space.lastUpdate
                    }
                }
                if original != nil, space.permission != .visitor {
                    space.markLocalChangePendingCloudSync()
                    guard space.save() else { return false }
                }
                state.requiresRemoteImport = false
                try saveState(state, space: space)
                if let reviewed {
                    // The user discarded these local edits; this is import
                    // completion, not confirmation of a cloud upload.
                    guard confirmLocalChanges(space, payload: ["updateTimestamp": reviewed.timestamp, "nodes": [[String: Any]]()]) else { return false }
                }
                if (original != nil || reviewed?.needsUpload == true), space.permission != .visitor {
                    // Cleanup created a new upload intent. The discarded local
                    // version may be later than this imported cloud generation.
                    UserDefaults.standard.set(space.lastUpdate, forKey: "spaceConfigurationLocalRecoveryPending." + key(space))
                }
            }
            if !validatedTopology {
                // Keep the original input for diagnosis without replaying an invalid
                // extension on every launch or treating it as a confirmed baseline.
                try Data(contentsOf: url).write(
                    to: directory(space).appendingPathComponent("unvalidated-import.json"),
                    options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            }
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
            let cleanup = try directory(space).appendingPathComponent("pending-import-reference-cleanup.json")
            if FileManager.default.fileExists(atPath: cleanup.path) { try FileManager.default.removeItem(at: cleanup) }
            // Invalid topology is retained above as unvalidated-import.json;
            // the reviewed choice must not replay that invalid input forever.
            let reviewed = try directory(space).appendingPathComponent("reviewed-cloud-import.json")
            if FileManager.default.fileExists(atPath: reviewed.path) { try FileManager.default.removeItem(at: reviewed) }
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
            switch await readUploadedConfiguration(space, payload: baseline, upgrading: true) {
            case .success(true): break
            case .success(false):
                block(space, reason: "upgradeBaselineNeedsImport")
                return recordSyncFailure(space, error: .configurationReviewRequired, stage: "uploadUpgradeBaseline")
            case .failure(let error):
                return recordSyncFailure(space, error: error, stage: "uploadUpgradeBaselineRequest")
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
                                       expectedRemote: Data? = nil, expectedRemoteTimestamp: Int64? = nil,
                                       reviewedRemote: [String: Any]? = nil) async -> Bool {
        let baselineReview = needsOlderCloudBaselineReview(space)
        guard !baselineReview || reviewedRemote != nil else { return false }
        let membership = SpaceMembershipResponseContext.capture(account: UserData.currentUserId,
            region: String(describing: UserData.currentServerRegion))
        guard let context = try? recoveryState(space), context.phase == .active,
              space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              isBlocked(space), !hasPendingImport(space), !hasPendingDeletionCleanup(space),
              let current = await space.export(allowsProtectedInspection: true),
              !baselineReview || recoveryPayloadsMatch(current, reviewed, space: space),
              SpaceConfigurationIntegrityPolicy.configurationData(current) == SpaceConfigurationIntegrityPolicy.configurationData(reviewed),
              SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]) == SpaceConfigurationIntegrityPolicy.integer(reviewed["updateTimestamp"]) else { return false }
        guard !Task.isCancelled, isCurrent(context, space: space) else { return false }
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard !Task.isCancelled, isCurrent(context, space: space),
              SpaceMembershipResponseContext.matches(membership, account: UserData.currentUserId,
                  region: String(describing: UserData.currentServerRegion)) else { return false }
        if case .failure(let error) = result { handleAuthorityError(error, space: space) }
        guard case .success(let response) = result, let remote = response["data"] as? [String: Any],
              remote["uuid"] as? String == space.id else { return false }
        guard space.lastUpdate == SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]),
              SpaceData.load(siteId: space.siteId, spaceId: space.id).first?.lastUpdate == space.lastUpdate,
              !baselineReview || SpaceKeyIntegrity.pair(current, networkID: space.meshNetworkId)?.fingerprint
                == SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId)?.fingerprint else { return false }
        space.applyRemoteSpaceMetadata(remote)
        guard space.save() else { return false }
        guard let remoteTimestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              reviewedRemote.map({ recoveryPayloadsMatch(remote, $0, space: space) }) ?? true,
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
            state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(remote)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(remote)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
            state.localReplacementVersion = space.lastUpdate
            state.prefersLocalMembership = true
            state.olderCloudBaselineFailure = nil
            try saveState(state, space: space)
        } catch { return false }
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
        SpaceProtectionReadGeneration.beginMutation()
        defer { SpaceProtectionReadGeneration.endMutation() }
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
