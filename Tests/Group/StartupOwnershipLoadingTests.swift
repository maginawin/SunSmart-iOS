import Foundation
import SQLite

// Only storage configuration and recovery dependencies are doubled. The runner
// compiles the actual SQL projection, task gate and resume method from the App.
enum MeshDataManager { static var customDatabasePath: String? }
enum UserData { static var currentUserId = "account", currentServerRegion = "region" }
final class NetworkRequest {
    static let shared = NetworkRequest()
    var networkable = true
}
final class SpaceData {
    static var stored: [SpaceData] = []
    static func load(siteId: String) -> [SpaceData] { stored }
    var needUploadCloud = true
    var pendingUpload = false
    var blocked = false
    var synchronizing = false
}
final class SiteData {
    enum State { case normal }
    var state = State.normal
    let id: String
    var spaces: [SpaceData] = []
    var canManageSiteTriggerZones = false
    init(_ id: String) { self.id = id }
    static var stored: [SiteData] = []
    static func loadAll() -> [SiteData] { stored }
    static func load(siteId: String) -> SiteData? { stored.first { $0.id == siteId } }
}
enum SiteDeviceOwnershipReconciler {
    static var calls = 0
    static var onReconcile: (() -> Void)?
    static func reconcile(siteId: String) { calls += 1; onReconcile?() }
}
enum SpaceConfigurationSafety {
    struct Recovery { var unbindRequested = false }
    static var needsUnbind = false
    static var suspended: CheckedContinuation<Bool, Never>?
    static func resumeLocalRemovals() {}
    static func recoveryState(_ space: SpaceData) throws -> Recovery { .init(unbindRequested: needsUnbind) }
    static func resumeUnbind(_ space: SpaceData) async -> Bool {
        await withCheckedContinuation { suspended = $0 }
    }
    static func canAutomaticallyUpload(_ space: SpaceData) -> Bool { true }
    static func hasPendingUpload(_ space: SpaceData) -> Bool { space.pendingUpload }
    static func isBlocked(_ space: SpaceData) -> Bool { space.blocked }
}
enum SiteTriggerZoneStore {
    struct State { var pending: Int? }
    static func load(_ site: SiteData) throws -> State { .init() }
}
struct SiteTriggerZoneCoordinator {
    let site: SiteData
    func synchronize() async -> Bool { true }
}
enum SpaceSyncCleanupCoordinator {
    static var prepared: [SpaceData] = []
    static var onPrepare: ((SpaceData) -> Void)?
    static func prepare(_ space: SpaceData) async -> Bool {
        prepared.append(space)
        onPrepare?(space)
        return true
    }
}
final class CloudSynchronizationManager {
    let recoveryGate = PendingSynchronizationRecoveryGate()
    enum Operation { case syncSite(site: SiteData, syncSpaces: [SpaceData]) }
    enum Level { case promptly }
    var uploads = 0
    func getSpaceCurrentSyncState(_ space: SpaceData) -> Int? { space.synchronizing ? 1 : nil }
    func addSynchronizationHandle(operation: Operation, level: Level) { uploads += 1 }
}

@main
enum StartupOwnershipLoadingTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() { fatalError(message) }
    }
    static func pump(until condition: () -> Bool) {
        let end = Date().addingTimeInterval(3)
        while !condition() && Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.005)) }
        require(condition(), "main queue recovery did not complete")
    }
    static func main() throws {
        try testProjection()
        testScheduling()
        testRecoveryCandidates()
        print("PASS: real SQLite identity projection, recovery candidates, coalescing, main queue handoff and stale recovery")
    }

    static func testProjection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("mesh.sqlite3").path
        let db = try Connection(path)
        try db.run("CREATE TABLE nodes (meshUUID TEXT, subnetworkId TEXT, macAddress TEXT, elements BLOB)")
        let insert = try db.prepare("INSERT INTO nodes VALUES (?, ?, ?, ?)")
        try db.transaction {
            for index in 0..<5000 {
                // Invalid model JSON must never enter a decoder during preflight.
                try insert.run("site", "subnet", String(format: "%012X", index + 1), "invalid-model-json")
            }
            try insert.run("other-site", "subnet", "AABBCCDDEEFF", "invalid")
            try insert.run("site", nil, "AABBCCDDEEFF", "invalid")
            try insert.run("site", "peer", nil, "invalid")
        }
        MeshDataManager.customDatabasePath = path
        var queries: [String] = []
        db.trace { queries.append($0) }
        let rows = try SiteDeviceOwnershipStore.loadMACs(meshUUID: "site", database: db)
        require(rows.count == 5001, "projection filters Site and ignores missing subnet")
        require(rows.last?.networkId == "peer" && rows.last?.mac == nil, "nil MAC is preserved for conservative policy")
        require(queries.allSatisfy { !$0.contains("elements") && !$0.contains("SELECT *") }, "preflight must not select model payload")
        let started = Date()
        let readonlyRows = try SiteDeviceOwnershipStore.loadMACs(meshUUID: "site")
        require(readonlyRows.count == rows.count, "separate read-only connection reads persisted identities")
        print("SQLite preflight: \(readonlyRows.count) rows, \(Date().timeIntervalSince(started)) seconds")
        let otherRows = try SiteDeviceOwnershipStore.loadMACs(meshUUID: "other-site")
        require(otherRows.count == 1, "same subnet in another Site stays isolated")
        MeshDataManager.customDatabasePath = directory.appendingPathComponent("missing.sqlite3").path
        do {
            _ = try SiteDeviceOwnershipStore.loadMACs(meshUUID: "site")
            fatalError("read-only preflight must report a missing database")
        } catch { }
        require(!FileManager.default.fileExists(atPath: MeshDataManager.customDatabasePath!), "preflight must not create databases")
        MeshDataManager.customDatabasePath = path
    }

    static func testScheduling() {
        let manager = CloudSynchronizationManager()
        SiteData.stored = [SiteData("site")]
        SpaceData.stored = [SpaceData()]
        var httpCompletionRan = false
        SiteDeviceOwnershipReconciler.onReconcile = { require(httpCompletionRan, "recovery must hand back the main queue") }
        manager.resumePendingSynchronizations()
        manager.resumePendingSynchronizations()
        DispatchQueue.main.async { httpCompletionRan = true }
        pump { manager.uploads == 1 }
        require(SiteDeviceOwnershipReconciler.calls == 1, "network and foreground triggers must coalesce")
        manager.resumePendingSynchronizations()
        pump { manager.uploads == 2 }
        require(SiteDeviceOwnershipReconciler.calls == 2, "completed recovery must allow a later pass")

        SiteData.stored[0].spaces = SpaceData.stored
        SpaceConfigurationSafety.needsUnbind = true
        manager.resumePendingSynchronizations()
        pump { SpaceConfigurationSafety.suspended != nil }
        let oldContinuation = SpaceConfigurationSafety.suspended!
        SpaceConfigurationSafety.suspended = nil
        UserData.currentServerRegion = "new-region"
        manager.resumePendingSynchronizations()
        pump { SpaceConfigurationSafety.suspended != nil }
        let calls = SiteDeviceOwnershipReconciler.calls
        oldContinuation.resume(returning: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        require(manager.uploads == 2, "old region must not upload after its await")
        manager.resumePendingSynchronizations()
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        require(SiteDeviceOwnershipReconciler.calls == calls, "old completion must not release the new region's task gate")
        SpaceConfigurationSafety.needsUnbind = false
        SpaceConfigurationSafety.suspended?.resume(returning: true)
        SpaceConfigurationSafety.suspended = nil
        pump { manager.uploads == 3 }

        manager.resumePendingSynchronizations()
        UserData.currentUserId = "changed-before-task-start"
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        require(manager.uploads == 3, "account changes before execution must invalidate queued recovery")
    }

    static func testRecoveryCandidates() {
        let manager = CloudSynchronizationManager()
        let idleSpaces = (0..<300).map { _ in
            let space = SpaceData()
            space.needUploadCloud = false
            return space
        }
        let dirty = SpaceData()
        let pending = SpaceData(); pending.needUploadCloud = false; pending.pendingUpload = true
        let cleanup = SpaceData(); cleanup.needUploadCloud = false; cleanup.blocked = true
        let syncing = SpaceData(); syncing.synchronizing = true
        SpaceData.stored = idleSpaces + [dirty, pending, cleanup, syncing]
        SiteData.stored = [SiteData("site")]
        SpaceSyncCleanupCoordinator.prepared = []
        SiteDeviceOwnershipReconciler.onReconcile = nil
        var mainQueueTurns = 0
        SpaceSyncCleanupCoordinator.onPrepare = { _ in
            let count = SpaceSyncCleanupCoordinator.prepared.count
            require(mainQueueTurns == count - 1, "each cleanup must allow main queue events before the next Space")
            DispatchQueue.main.async { mainQueueTurns += 1 }
        }
        manager.resumePendingSynchronizations()
        pump { manager.uploads == 1 }
        let prepared = SpaceSyncCleanupCoordinator.prepared
        require(prepared.count == 3 && prepared[0] === dirty && prepared[1] === pending && prepared[2] === cleanup,
                "startup must skip 300 synchronized Spaces and an active upload, retaining dirty/pending/blocked recovery")

        SpaceData.stored = idleSpaces
        SpaceSyncCleanupCoordinator.prepared = []
        SpaceSyncCleanupCoordinator.onPrepare = nil
        manager.resumePendingSynchronizations()
        var completionToken: UUID?
        pump {
            if completionToken == nil {
                completionToken = manager.recoveryGate.begin(scope: .init(account: UserData.currentUserId, region: UserData.currentServerRegion))
            }
            return completionToken != nil
        }
        manager.recoveryGate.finish(token: completionToken!)
        require(SpaceSyncCleanupCoordinator.prepared.isEmpty && manager.uploads == 1,
                "a later foreground pass must not export or upload unchanged Spaces")
    }
}
