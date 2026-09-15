import Foundation
import CryptoKit

/// A conservative process-wide generation. Mutations invalidate before the first
/// write and after completion (including failure). No lock is held across I/O.
enum SpaceProtectionReadGeneration {
    private static let lock = NSLock()
    private static var generation: UInt64 = 0
    private static var writers = 0
    static var current: UInt64? {
        lock.lock(); defer { lock.unlock() }
        return writers == 0 ? generation : nil
    }
    static func beginMutation() {
        lock.lock(); generation &+= 1; writers += 1; lock.unlock()
    }
    static func endMutation() {
        lock.lock(); precondition(writers > 0); writers -= 1; generation &+= 1; lock.unlock()
    }
    static func invalidate() {
        lock.lock(); generation &+= 1; lock.unlock()
    }
    /// Linearize the in-memory cache commit against writer start. The closure
    /// must not perform I/O, call clients, or re-enter the generation API.
    static func commit(ifCurrent version: UInt64?, _ body: () -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard writers == 0, version == generation else { return false }
        body()
        return true
    }
}

/// Contains values only. It can be read on a worker without accessing live Mesh
/// objects, the active database, or switching the current account/network.
struct SpaceProtectionReadRequest {
    struct Scope: Equatable {
        let account: String
        let region: String
        let meshUUID: String
        let networkID: String
        var storageKey: String {
            let text = "\(account)|\(region)|\(meshUUID)|\(networkID)"
            return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        }
    }
    let scope: Scope
    let root: URL
    let defaults: UserDefaults

    func read() -> SpaceProtectionReadSnapshot {
        let interval = AppPerformance.begin("ProtectionRead")
        defer { interval.end() }
        let version = SpaceProtectionReadGeneration.current
        guard version != nil else { return .init(scope: scope, version: nil, failure: .mutation) }
        var result = SpaceProtectionReadSnapshot(scope: scope, version: version)
        do {
            let key = scope.storageKey
            result.blockedReason = defaults.string(forKey: "spaceConfigurationBlocked." + key)
            var directory = key
            if let data = try readIfPresent(root.appendingPathComponent(key + ".json")) {
                let state = try JSONDecoder().decode(SpaceRecoveryState.self, from: data)
                guard state.identity.account == scope.account, state.identity.region == scope.region,
                      state.identity.space.meshUUID == scope.meshUUID,
                      state.identity.space.networkId == scope.networkID else { throw CocoaError(.fileReadCorruptFile) }
                result.phase = state.phase
                result.authority = state.authority
                result.recoveryGeneration = state.generation
                result.persistedSpace = state.identity.space
                directory = state.directoryName ?? key
                // Recovery directories are direct children; never follow a corrupt path.
                guard !directory.isEmpty, directory != ".", directory != "..",
                      !directory.contains("/"), !directory.contains("\\") else { throw CocoaError(.fileReadCorruptFile) }
            }
            let folder = root.appendingPathComponent(directory, isDirectory: true)
            result.pendingImport = try exists(folder.appendingPathComponent("pending-import.json"))
            result.pendingReferences = try exists(folder.appendingPathComponent("pending-reference-cleanup.json"))
            if let data = try readIfPresent(folder.appendingPathComponent("device-deletions.json")) {
                let journal = try JSONDecoder().decode(SpaceDeletionJournal.self, from: data)
                guard journal.scope.meshUUID == scope.meshUUID, journal.scope.networkId == scope.networkID else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                if let identity = result.persistedSpace, journal.scope != identity { throw CocoaError(.fileReadCorruptFile) }
                result.pendingDeletion = journal.needsCleanup
            }
        } catch {
            result.failure = .unreadable
        }
        if version != SpaceProtectionReadGeneration.current { result.failure = .mutation }
        return result
    }

    private func readIfPresent(_ url: URL) throws -> Data? {
        AppPerformance.event("ProtectionFileRead")
        do { return try Data(contentsOf: url) }
        catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return nil }
            throw error
        }
    }
    private func exists(_ url: URL) throws -> Bool {
        AppPerformance.event("ProtectionFileProbe")
        // resourceValues throws for permission/corruption; fileExists would turn
        // some failures into 'absent' and could incorrectly permit synchronization.
        do { _ = try url.resourceValues(forKeys: [.isRegularFileKey]); return true }
        catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError { return false }
            throw error
        }
    }
}

struct SpaceProtectionReadSnapshot {
    enum Failure { case mutation, unreadable }
    let scope: SpaceProtectionReadRequest.Scope
    let version: UInt64?
    var failure: Failure?
    var phase: SpaceRecoveryState.Phase?
    var authority: SpaceRecoveryState.Authority?
    var recoveryGeneration: UUID?
    var persistedSpace: SpaceDeletionJournal.Scope?
    var blockedReason: String?
    var pendingImport = false
    var pendingReferences = false
    var pendingDeletion = false
    var isCurrent: Bool { version != nil && version == SpaceProtectionReadGeneration.current }
    func commit(_ body: () -> Void) -> Bool { SpaceProtectionReadGeneration.commit(ifCurrent: version, body) }
    var isBlocked: Bool {
        failure != nil || !isCurrent || phase.map { $0 != .active } == true
            || blockedReason != nil || pendingImport || pendingReferences || pendingDeletion
    }
}
