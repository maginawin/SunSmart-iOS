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
        if let state = try SpaceRecoveryState.read(from: stateURL(space), identity: identity(space)) { return state }
        let state = SpaceRecoveryState(identity: identity(space))
        try saveState(state, space: space)
        return state
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
            if state.phase != .active || state.unbindRequested == true { return true }
            directoryName = state.directoryName ?? identity
        }
        let pending = recoveryRoot.appendingPathComponent(directoryName).appendingPathComponent("pending-import.json")
        return UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + identity) != nil
            || FileManager.default.fileExists(atPath: pending.path)
            || FileManager.default.fileExists(atPath: pending.deletingLastPathComponent().appendingPathComponent("pending-reference-cleanup.json").path)
            || deletionCleanupPending(at: pending.deletingLastPathComponent().appendingPathComponent("device-deletions.json"))
    }

    static func isBlocked(_ space: SpaceData) -> Bool {
        isBlocked(meshUUID: space.meshUUID, networkId: space.meshNetworkId)
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
    static func recordSyncFailure(_ space: SpaceData, error: NetworkApiError, stage: String) -> Bool {
        // The cloud operation persists its final error. Do not save a possibly
        // stale Space object merely to report a failed preparation/export.
        space.syncCloudError = error
        #if DEBUG
        let reason = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space)) ?? "none"
        print("[SpaceConfigurationSync] stage=\(stage) error=\(error.code) reason=\(reason)")
        #endif
        return false
    }

    /// Recheck only the known legacy comparison block. Never use this path to
    /// clear an import, deletion, changed configuration, or a different cause.
    @MainActor
    static func recoverUpgradeBaselineIfNeeded(_ space: SpaceData,
                                               readLocal: () async -> [String: Any]?) async -> Bool {
        let reasonKey = "spaceConfigurationBlocked." + key(space)
        guard UserDefaults.standard.string(forKey: reasonKey) == "upgradeBaselineNeedsImport" else { return true }
        func eligible() -> Bool {
            guard !_Concurrency.Task<Never, Never>.isCancelled,
                  UserDefaults.standard.string(forKey: reasonKey) == "upgradeBaselineNeedsImport",
                  canAutomaticallyUpload(space), !space.needUploadCloud,
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
              let expected = SpaceSyncCleanupPolicy.upgradeRecoveryConfiguration(local),
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
              let actual = SpaceSyncCleanupPolicy.upgradeRecoveryConfiguration(remote), expected == actual else { return false }
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
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
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
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
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

    /// A GET must not resurrect devices while their explicit deletion or local
    /// recovery is waiting for upload confirmation to finish.
    static func preservesLocalChanges(_ space: SpaceData) -> Bool {
        guard let state = try? recoveryState(space) else { return true }
        guard state.preservesUpload else { return false }
        guard let journal = try? deletionJournal(space) else { return true }
        return state.submission != nil || state.authority == .waitingForAuthorization || !journal.entries.isEmpty
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
            guard schedulesMatch, modelsMatch else { return .success(false) }
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
                  let configuration = SpaceConfigurationIntegrityPolicy.configurationData(payload),
                  let scheduleTargets = SpaceConfigurationIntegrityPolicy.scheduleTargetsData(payload),
                  let schedulerModelStates = SchedulerModelSnapshot.spaceData(payload),
                  let keys = SpaceKeyIntegrity.pair(payload, networkID: space.meshNetworkId),
                  let current = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                  let local = SpaceKeyIntegrity.pair(current, networkID: space.meshNetworkId,
                                                     applicationIndex: keys.application.index),
                  keys.fingerprint == local.fingerprint else { return nil }
            state.submission = .init(id: UUID(), timestamp: timestamp, configuration: configuration,
                                     keyFingerprint: keys.fingerprint, scheduleTargets: scheduleTargets,
                                     schedulerModelStates: schedulerModelStates,
                                     nodeIdentities: SpaceCloudNodeRemovalPolicy.instances(payload))
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
            state.submission?.permitsCloudRemoval = true
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
            // Establish the baseline on FIRST upload too; otherwise adding the next
            // device compares the changed local topology to the pre-add cloud copy.
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
            state.authorizationBaseline = readbackConfiguration(submission.configuration, timestamp: submission.timestamp, space: space)
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
            let blockedKey = "spaceConfigurationBlocked." + key(space)
            if ["uploadReadbackUnconfirmed", "uploadReadbackConflict"].contains(UserDefaults.standard.string(forKey: blockedKey) ?? "") {
                UserDefaults.standard.removeObject(forKey: blockedKey)
            }
            state.submission = nil
            try saveState(state, space: space)
            return true
        } catch { return false }
    }

    /// Accepted uploads only need local completion. Read back unknown outcomes.
    @MainActor
    static func resumeUpload(_ space: SpaceData) async -> Swift.Result<Void, NetworkApiError> {
        do {
            try migratePendingUpload(space)
            var context = try recoveryState(space)
            guard context.phase == .active else { return .failure(uploadUnconfirmed) }
            guard context.authority == .writable else { return .failure(authorityError(space)) }
            guard let submission = context.submission else {
                // An offline local edit must not resurrect nodes removed remotely
                // since our last confirmed version. Read only this Space.
                if space.needUploadCloud, context.nodeIdentitiesBaseline != nil || context.schedulerModelStatesBaseline != nil {
                    let response = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
                        spaceId: space.id, password: space.authorizationPassword))
                    guard !_Concurrency.Task<Never, Never>.isCancelled, isCurrent(context, space: space) else { return .failure(uploadUnconfirmed) }
                    switch response {
                    case .failure(let error): handleAuthorityError(error, space: space); return .failure(error)
                    case .success(let response):
                        guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id else { return .failure(uploadUnconfirmed) }
                        space.applyRemoteSpaceMetadata(remote)
                        guard space.save(), reconcileCloudMembership(space, remote: remote) else { return .failure(uploadUnconfirmed) }
                    }
                }
                return .success(())
            }
            if submission.phase == .verified {
                return finishSubmission(context, space: space) ? .success(()) : .failure(uploadUnconfirmed)
            }
            let expectedKeyFingerprint: String?
            if let fingerprint = submission.keyFingerprint {
                expectedKeyFingerprint = fingerprint
            } else if let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false) {
                expectedKeyFingerprint = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId)?.fingerprint
            } else {
                expectedKeyFingerprint = nil
            }
            guard let expectedKeyFingerprint else { return .failure(uploadUnconfirmed) }
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
                    #if DEBUG
                    print("[SpaceConfigurationReadback] space=\(space.id) submitted=\(submission.timestamp) result=unavailable code=\(error.code)")
                    #endif
                    return .failure(error)
                case .success(let response):
                    guard let remote = response["data"] as? [String: Any], remote["uuid"] as? String == space.id,
                          let configuration = SpaceConfigurationIntegrityPolicy.configurationData(remote),
                          remote["nodes"] is [[String: Any]] else { return .failure(uploadUnconfirmed) }
                    let remoteKeyFingerprint = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId)?.fingerprint
                    space.applyRemoteSpaceMetadata(remote)
                    guard space.save(), isCurrent(context, space: space), canAutomaticallyUpload(space) else {
                        return .failure(authorityError(space))
                    }
                    guard reconcileCloudMembership(space, remote: remote), isCurrent(context, space: space) else { return .failure(uploadUnconfirmed) }
                    let expected = readbackConfiguration(submission.configuration, timestamp: submission.timestamp, space: space)
                    let actual = readbackRemoteConfiguration(configuration, timestamp: submission.timestamp, space: space)
                    let schedulesMatch = submission.scheduleTargets.map {
                        SpaceConfigurationIntegrityPolicy.scheduleTargetsData(remote) == $0
                    } ?? true
                    let modelsMatch = submission.schedulerModelStates.map {
                        readbackModels($0, timestamp: submission.timestamp, space: space).map {
                            SchedulerModelSnapshot.spaceData(remote) == $0
                        } ?? false
                    } ?? true
                    if remoteKeyFingerprint != expectedKeyFingerprint,
                       space.permission == .owner, remote["role"] as? String == "owner",
                       let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
                       let localKeys = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId),
                       localKeys.fingerprint == expectedKeyFingerprint,
                       SpaceKeyIntegrity.presentServerKeysMatchLocal(remote, local: localKeys),
                       SpaceConfigurationIntegrityPolicy.configurationsMatch(actual, expected), schedulesMatch, modelsMatch {
                        // The submitted business configuration arrived, but one Key did not.
                        // Keep the Space dirty and send a new complete snapshot.
                        context = try recoveryState(space)
                        guard context.submission?.id == submission.id else { return .failure(uploadUnconfirmed) }
                        context.submission = nil
                        try saveState(context, space: space)
                        return .success(())
                    }
                    if remoteKeyFingerprint == expectedKeyFingerprint,
                       SpaceConfigurationIntegrityPolicy.configurationsMatch(actual, expected), schedulesMatch, modelsMatch {
                        context = try recoveryState(space)
                        guard context.submission?.id == submission.id else { return .failure(uploadUnconfirmed) }
                        context.submission?.phase = .verified
                        try saveState(context, space: space)
                        return finishSubmission(context, space: space) ? .success(()) : .failure(uploadUnconfirmed)
                    }
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
                        return .success(())
                    }
                }
                if attempt < 2 { try await _Concurrency.Task<Never, Never>.sleep(nanoseconds: 500_000_000) }
            }
            block(space, reason: "uploadReadbackConflict")
            return .failure(uploadUnconfirmed)
        } catch { return .failure(uploadUnconfirmed) }
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

    private static func readbackModels(_ data: Data, timestamp: Int64, space: SpaceData) -> Data? {
        SpaceCloudNodeRemovalPolicy.projectModels(data, removing: readbackRemovals(timestamp: timestamp, space: space))
    }

    /// Reconcile the current Space's authoritative membership before a pending
    /// submission or local edit prevents ordinary import. No destination lookup.
    @MainActor
    static func reconcileCloudMembership(_ space: SpaceData, remote: [String: Any]) -> Bool {
        guard canAutomaticallyUpload(space), !hasPendingImport(space),
              let state = try? recoveryState(space), remote["uuid"] as? String == space.id else { return true }
        let submission = state.submission
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
        guard let remoteTimestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              remoteTimestamp >= timestamp, remoteTimestamp < Int64.max,
              let remoteNodes = SpaceCloudNodeRemovalPolicy.instances(remote),
              remote["groups"] is [[String: Any]], remote["scenes"] is [[String: Any]], remote["schedules"] is [[String: Any]],
              let remoteConfiguration = SpaceConfigurationIntegrityPolicy.configurationData(remote),
              let remoteModels = SchedulerModelSnapshot.spaceData(remote),
              let localNetwork = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
              let localKeys = SpaceKeyIntegrity.pair(localNetwork, networkID: space.meshNetworkId),
              let remoteKeys = SpaceKeyIntegrity.pair(remote, networkID: space.meshNetworkId),
              localKeys.fingerprint == remoteKeys.fingerprint,
              submission?.keyFingerprint == nil || submission?.keyFingerprint == remoteKeys.fingerprint else { return false }
        guard let missing = SpaceCloudNodeRemovalPolicy.removed(from: source, remote: remoteNodes) else {
            return submission == nil && !space.needUploadCloud // Ordinary authoritative import may apply additions.
        }
        if missing.isEmpty, submission != nil { return true } // Keep ordinary readback retries for unchanged membership.
        if !missing.isEmpty {
            guard (try? SpaceSyncCleanupPolicy.normalize(remote)) != nil,
                  SpaceConfigurationIntegrityPolicy.scheduleTargetIssue(in: remote) == nil else { return false }
        }
        let completed = readbackRemovals(timestamp: timestamp, space: space)
        guard !remoteNodes.contains(where: { node in completed.contains { $0.uuid == node.uuid && $0.address == node.address } }) else { return false }
        let pending = missing.filter { node in !completed.contains { $0.uuid == node.uuid && $0.address == node.address } }
        guard let resolved = DevicePermanentDeletionContext.cloudRemovalInstances(space: space, expected: pending) else { return false }
        let removed = completed + resolved
        guard
              let expected = SpaceCloudNodeRemovalPolicy.projectConfiguration(configuration, removing: removed),
              let actual = SpaceCloudNodeRemovalPolicy.projectConfiguration(remoteConfiguration, removing: removed),
              SpaceConfigurationIntegrityPolicy.configurationsMatch(expected, actual) else { return false }
        let modelBaseline = submission?.schedulerModelStates ?? state.schedulerModelStatesBaseline
        if let modelBaseline {
            guard SpaceCloudNodeRemovalPolicy.projectModels(modelBaseline, removing: removed) == remoteModels else { return false }
        }
        if let targets = submission?.scheduleTargets {
            guard SpaceConfigurationIntegrityPolicy.scheduleTargetsData(remote) == targets else { return false }
        }
        guard !pending.isEmpty else { return true }
        guard DevicePermanentDeletionContext.removeCloudInstances(space: space, instances: resolved,
            baselineTimestamp: timestamp, remoteTimestamp: remoteTimestamp, submissionID: submission?.id) else {
            block(space, reason: "deletionCleanupPending")
            return false
        }
        // A baseline-only cleanup has no pending submission to finish later.
        // Retain the newer local cleanup generation for the next complete upload.
        if submission == nil {
            do {
                var current = try recoveryState(space)
                guard current.matches(state), current.submission == nil else { return false }
                current.authorizationBaseline = expected
                current.schedulerModelStatesBaseline = remoteModels
                current.nodeIdentitiesBaseline = remoteNodes
                try saveState(current, space: space)
            } catch { return false }
        }
        #if DEBUG
        print("[SpaceCloudMembership] space=\(space.id) removed=\(removed.count) remaining=\(remoteNodes.count) source=\(timestamp) remote=\(remoteTimestamp)")
        #endif
        return true
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
              let schedulerModelStates = SchedulerModelSnapshot.spaceData(payload),
              let configuration = SpaceConfigurationIntegrityPolicy.configurationData(payload) else { throw SafetyError.invalidCheckpoint }
        state.submission = .init(id: UUID(), timestamp: timestamp, configuration: configuration, phase: .accepted,
                                 scheduleTargets: SpaceConfigurationIntegrityPolicy.scheduleTargetsData(payload),
                                 schedulerModelStates: schedulerModelStates, permitsCloudRemoval: false)
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
                state.nodeIdentitiesBaseline = nil
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

    static func configurationAvailable(for node: Node, group: Group? = nil) -> Bool {
        if let value = NodeSyncReadContext.current?.configurationAvailable(for: node, group: group) { return value }
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
        var started = ProcessInfo.processInfo.systemUptime
        func mark(_ phase: String) {
            let now = ProcessInfo.processInfo.systemUptime
            #if DEBUG
            print("[SiteImportBaseline] space=\(space.id) phase=\(phase) seconds=\(now - started) main=\(Thread.isMainThread)")
            #endif
            started = now
        }
        guard !isBlocked(space), let expected = SpaceConfigurationIntegrityPolicy.upgradeConfigurationData(local),
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
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
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
              payload["uuid"] as? String == space.id else { return nil }
        return payload
    }

    static func hasPendingImport(_ space: SpaceData) -> Bool {
        guard let url = try? directory(space).appendingPathComponent("pending-import.json") else { return true }
        return FileManager.default.fileExists(atPath: url.path)
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
        }
        result["blockedReason"] = UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + key(space))
        do {
            let state = try SpaceRecoveryState.read(from: stateURL(space), identity: identity(space))
            result["recoveryPhase"] = state?.phase.rawValue
            let folder = state.map { storedDirectory(space, state: $0) }
                ?? recoveryRoot.appendingPathComponent(key(space))
            result["pendingImport"] = FileManager.default.fileExists(atPath: folder.appendingPathComponent("pending-import.json").path)
            result["pendingDeletionCleanup"] = deletionCleanupPending(at: folder.appendingPathComponent("device-deletions.json"))
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
                state.schedulerModelStatesBaseline = payload.flatMap(SchedulerModelSnapshot.spaceData)
                state.nodeIdentitiesBaseline = (original ?? payload).flatMap(SpaceCloudNodeRemovalPolicy.instances)
                if original != nil, space.permission != .visitor {
                    space.markLocalChangePendingCloudSync()
                    guard space.save() else { return false }
                    UserDefaults.standard.set(space.lastUpdate, forKey: "spaceConfigurationLocalRecoveryPending." + key(space))
                }
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
            let cleanup = try directory(space).appendingPathComponent("pending-import-reference-cleanup.json")
            if FileManager.default.fileExists(atPath: cleanup.path) { try FileManager.default.removeItem(at: cleanup) }
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
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
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
