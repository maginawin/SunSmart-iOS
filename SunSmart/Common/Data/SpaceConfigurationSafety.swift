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

    private static func directory(_ space: SpaceData) throws -> URL {
        var url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/SpaceConfigurationRecovery")
            .appendingPathComponent(key(space))
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try url.setResourceValues(values)
        return url
    }

    static func isBlocked(meshUUID: String, networkId: String) -> Bool {
        let identity = key(meshUUID: meshUUID, networkId: networkId)
        let pending = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Application Support/SpaceConfigurationRecovery")
            .appendingPathComponent(identity).appendingPathComponent("pending-import.json")
        return UserDefaults.standard.string(forKey: "spaceConfigurationBlocked." + identity) != nil
            || FileManager.default.fileExists(atPath: pending.path)
    }

    static func isBlocked(_ space: SpaceData) -> Bool {
        isBlocked(meshUUID: space.meshUUID, networkId: space.meshNetworkId)
    }

    static func block(_ space: SpaceData, reason: String) {
        block(meshUUID: space.meshUUID, networkId: space.meshNetworkId, reason: reason)
        print("[SpaceConfigurationSafety] blocked space=\(space.id) reason=\(reason)")
        MeshNetworkManager.instance.realNodes.filter { $0.subNetworkId == space.meshNetworkId }
            .forEach { $0.clearSyncStateCache() }
    }

    static func block(meshUUID: String, networkId: String, reason: String) {
        UserDefaults.standard.set(reason,
            forKey: "spaceConfigurationBlocked." + key(meshUUID: meshUUID, networkId: networkId))
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

    static func prepareUpload(_ space: SpaceData, payload: [String: Any]) async -> Bool {
        guard !isBlocked(space), !hasPendingImport(space), checkpoint(space),
              recordSnapshot(space, payload: payload) else { return false }
        if needsUpgradeBaseline(space) {
            let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
                spaceId: space.id, password: space.authorizationPassword))
            guard case .success(let response) = result,
                  let remote = response["data"] as? [String: Any],
                  remote["uuid"] as? String == space.id,
                  let configuration = SpaceConfigurationIntegrityPolicy.configurationData(remote),
                  configuration == SpaceConfigurationIntegrityPolicy.configurationData(payload) else {
                block(space, reason: "upgradeBaselineNeedsImport")
                return false
            }
            UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        }
        return !isBlocked(space) && !hasPendingImport(space)
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
    static func authorizeLocalRecovery(_ space: SpaceData, reviewed: [String: Any]) async -> Bool {
        guard space.permission == .owner || space.permission == .editor,
              !space.disableEditorPermission, !space.requiresPasswordVerification,
              isBlocked(space), !hasPendingImport(space),
              let current = await space.export(allowsProtectedInspection: true),
              SpaceConfigurationIntegrityPolicy.configurationData(current) == SpaceConfigurationIntegrityPolicy.configurationData(reviewed),
              SpaceConfigurationIntegrityPolicy.integer(current["updateTimestamp"]) == SpaceConfigurationIntegrityPolicy.integer(reviewed["updateTimestamp"]) else { return false }
        let result = await NetworkRequest.shared.request(.spaceInfo(siteId: space.siteId,
            spaceId: space.id, password: space.authorizationPassword))
        guard case .success(let response) = result, let remote = response["data"] as? [String: Any],
              remote["uuid"] as? String == space.id,
              let remoteTimestamp = SpaceConfigurationIntegrityPolicy.integer(remote["updateTimestamp"]),
              remoteTimestamp < Int64.max, space.lastUpdate < Int64.max,
              (space.lastUploadCloudTimestamp ?? 0) < Int64.max,
              isBlocked(space), !hasPendingImport(space),
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
        UserDefaults.standard.set(true, forKey: "spaceConfigurationMigrated." + key(space))
        UserDefaults.standard.removeObject(forKey: "spaceConfigurationBlocked." + key(space))
        MeshNetworkManager.instance.realNodes.filter { $0.subNetworkId == space.meshNetworkId }
            .forEach { $0.clearSyncStateCache() }
        return true
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
