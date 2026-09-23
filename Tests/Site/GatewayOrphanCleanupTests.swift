import Foundation
import SQLite

@main @MainActor struct GatewayOrphanCleanupTests {
    static func main() throws {
        try testRawCleanupAndScope()
        try testFailuresRollBack()
        testLifecycleAndResponses()
        try testProductionAdapter()
        print("GatewayOrphanCleanupTests passed: raw absence, scopes, pending/busy, rollback, stale writes/responses, re-add and production adapter")
    }

    private static func check(_ condition: Bool, _ message: String = "") {
        precondition(condition, message)
    }

    private static func fixture() throws -> (Connection, Connection) {
        let app = try Connection(.inMemory), mesh = try Connection(.inMemory)
        try app.run("CREATE TABLE gateways (id INTEGER PRIMARY KEY, siteUUID TEXT, macAddress TEXT, address INTEGER, lastUploadCloudTimestamp INTEGER, serverDeletionPendingLocalReset INTEGER)")
        try app.run("INSERT INTO gateways VALUES (2, 'site', 'CC9E27179B40', 47, NULL, 0), (3, 'site', 'E2F54FDEECEB', 53, NULL, 0), (4, 'site', 'F1ADFFA8B2C7', 38, NULL, 0)")
        try mesh.run("CREATE TABLE meshNetwork (meshUUID TEXT)")
        try mesh.run("INSERT INTO meshNetwork VALUES ('site')")
        try mesh.run("CREATE TABLE nodes (meshUUID TEXT, subnetworkId TEXT, unicastAddress INTEGER, macAddress TEXT)")
        try mesh.run("INSERT INTO nodes VALUES ('site', 'primary', 1, NULL)")
        return (app, mesh)
    }
    private static func remove(_ app: Connection, _ mesh: Connection, remote: Set<String> = [],
                               canRemove: (GatewayOrphanStore.Candidate) -> Bool = { _ in true },
                               isCurrent: () -> Bool = { true }) throws -> Set<String> {
        try GatewayOrphanStore.remove(app: app, mesh: mesh, siteID: "site", meshUUID: "site",
            remoteMACs: remote, canRemove: canRemove, isCurrent: isCurrent)
    }
    private static func count(_ app: Connection) throws -> Int64 {
        try app.scalar("SELECT count(*) FROM gateways WHERE siteUUID = 'site'") as! Int64
    }
    private static func testRawCleanupAndScope() throws {
        let (app, mesh) = try fixture()
        try app.run("INSERT INTO gateways VALUES (5, 'other', 'CC9E27179B40', 47, NULL, 0)")
        check(try remove(app, mesh).count == 3)
        check(try count(app) == 0)
        check(try app.scalar("SELECT count(*) FROM gateways") as! Int64 == 1)
        check(try remove(app, mesh).isEmpty)

        let (valid, nodes) = try fixture()
        try nodes.run("INSERT INTO nodes VALUES ('site', 'space', 47, 'another-mac'), ('site', 'primary', 99, 'e2f54fdeeceb'), ('other', 'primary', 38, 'F1ADFFA8B2C7')")
        check(try remove(valid, nodes) == ["F1ADFFA8B2C7"], "Preserve same-site address/MAC conflicts in every subnet")
        let (pending, primary) = try fixture()
        try pending.run("UPDATE gateways SET serverDeletionPendingLocalReset = 1 WHERE id = 2")
        check(try remove(pending, primary, remote: ["E2F54FDEECEB"], canRemove: { $0.id != 4 }).isEmpty)
        check(try count(pending) == 3)
    }
    private static func testFailuresRollBack() throws {
        for failure in ["missing-nodes", "malformed-node", "missing-network", "delete-error", "revision-change", "candidate-replaced"] {
            let (app, mesh) = try fixture()
            switch failure {
            case "missing-nodes": try mesh.run("DROP TABLE nodes")
            case "malformed-node": try mesh.run("INSERT INTO nodes VALUES ('site', 'primary', 'broken', NULL)")
            case "missing-network": try mesh.run("DELETE FROM meshNetwork")
            case "delete-error": try app.run("CREATE TRIGGER fail_delete BEFORE DELETE ON gateways WHEN OLD.id = 3 BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
            default: break
            }
            var checks = 0
            do {
                _ = try remove(app, mesh, canRemove: { candidate in
                    if failure == "candidate-replaced" && candidate.id == 2 {
                        try! app.run("UPDATE gateways SET lastUploadCloudTimestamp = 100 WHERE id = 2")
                    }
                    return true
                }, isCurrent: {
                    checks += 1
                    return failure != "revision-change" || checks < 3
                })
                preconditionFailure("Cleanup accepted \(failure)")
            } catch {}
            check(try count(app) == 3, "A partial cleanup must roll back: \(failure)")
        }
    }
    private static func testLifecycleAndResponses() {
        let scope = GatewayOrphanGuard.Scope(account: "owner", region: "region", siteID: "site")
        func payload(detail: String? = "site", role: String = "owner") -> [String: Any] {
            ["uuid": "site", "role": role, "gateways": [], GatewayOrphanGuard.payloadKey:
                GatewayOrphanGuard.capture(account: scope.account, region: scope.region, detailSiteID: detail)]
        }
        let oldRead = payload()
        let oldModel = GatewayOrphanGuard.token(scope: scope, mac: " aa ")
        check(GatewayOrphanGuard.canReconcile(oldRead, scope: scope))
        check(!GatewayOrphanGuard.canReconcile(payload(detail: nil), scope: scope))
        check(!GatewayOrphanGuard.canReconcile(payload(role: "editor"), scope: scope))
        GatewayOrphanGuard.beginImport(scope)
        check(!GatewayOrphanGuard.canReconcile(oldRead, scope: scope))
        GatewayOrphanGuard.endImport(scope)
        GatewayOrphanGuard.beginActivity(scope)
        check(!GatewayOrphanGuard.canReconcile(payload(), scope: scope))
        GatewayOrphanGuard.endActivity(scope)
        check(!GatewayOrphanGuard.canReconcile(oldRead, scope: scope), "Finished provisioning invalidates an earlier absence response")
        let fresh = payload()
        check(GatewayOrphanGuard.canReconcile(fresh, scope: scope))
        GatewayOrphanGuard.didRemove(scope: scope, macs: ["AA"])
        check(!GatewayOrphanGuard.isCurrent(oldModel), "A delayed save cannot resurrect the row")
        check(!GatewayOrphanGuard.allowsImport(fresh, scope: scope, mac: "aa"))
        check(!GatewayOrphanGuard.acceptsSnapshot(fresh, scope: scope), "Old Site responses cannot restore Space associations")
        check(!GatewayOrphanGuard.allowsImport([:], scope: scope, mac: "aa"))
        check(GatewayOrphanGuard.allowsImport([:], scope: scope, mac: "unrelated"))
        check(GatewayOrphanGuard.allowsImport(payload(), scope: scope, mac: "aa"))
        check(GatewayOrphanGuard.acceptsSnapshot(payload(), scope: scope))
        check(GatewayOrphanGuard.isCurrent(GatewayOrphanGuard.token(scope: scope, mac: "AA")), "A new provisioning has a fresh token")
        let other = GatewayOrphanGuard.Scope(account: "another", region: "region", siteID: "site")
        check(!GatewayOrphanGuard.canReconcile(payload(), scope: other))
        let annotated = GatewayOrphanGuard.annotate(["data": ["sites": [["uuid": "site"]]]],
            context: GatewayOrphanGuard.capture(account: "owner", region: "region", detailSiteID: nil))
        let item = ((annotated["data"] as! [String: Any])["sites"] as! [[String: Any]])[0]
        check(item[GatewayOrphanGuard.payloadKey] != nil && !GatewayOrphanGuard.canReconcile(item, scope: scope))
    }

    private static func testProductionAdapter() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for scenario in ["absent", "remote", "missing-field", "malformed-remote", "editor", "list", "rejected", "busy", "receipt", "active-import", "failed-delete"] {
            let (app, _) = try fixture()
            try app.run("UPDATE gateways SET siteUUID = 'adapter-site'")
            let mesh = try Connection(directory.appendingPathComponent(scenario + ".sqlite3").path)
            try mesh.run("CREATE TABLE meshNetwork (meshUUID TEXT)")
            try mesh.run("INSERT INTO meshNetwork VALUES ('site')")
            try mesh.run("CREATE TABLE nodes (meshUUID TEXT, unicastAddress INTEGER, macAddress TEXT)")
            try mesh.run("INSERT INTO nodes VALUES ('site', 1, NULL)")
            SunSmartDataManager.shared.db = app
            MeshDataManager.customDatabasePath = directory.appendingPathComponent(scenario + ".sqlite3").path
            MeshDataManager.shared.db = mesh
            let site = SiteData(), scope = GatewayOrphanGuard.Scope.current(siteID: "adapter-site")
            var payload: [String: Any] = ["uuid": site.id, "role": "owner", "gateways": [],
                GatewayOrphanGuard.payloadKey: GatewayOrphanGuard.capture(account: "owner", region: "region", detailSiteID: scenario == "list" ? nil : site.id)]
            if scenario == "remote" { payload["gateways"] = [["macAddress": "CC9E27179B40"]] }
            if scenario == "missing-field" { payload["gateways"] = nil }
            if scenario == "malformed-remote" { payload["gateways"] = [["macAddress": ""]] }
            if scenario == "editor" { site.permission = .editor; payload["role"] = "editor" }
            SpaceMembershipCoordinator.acceptsResponse = scenario != "rejected"
            GatewayDeletionContext.protectedMACs = scenario == "receipt" ? ["CC9E27179B40"] : []
            CloudSynchronizationManager.shared.busyMACs = scenario == "busy" ? ["CC9E27179B40"] : []
            if scenario == "active-import" { GatewayOrphanGuard.beginImport(scope) }
            if scenario == "failed-delete" { try app.run("CREATE TRIGGER fail BEFORE DELETE ON gateways BEGIN SELECT RAISE(ABORT, 'failure'); END") }
            let oldToken = GatewayOrphanGuard.token(scope: scope, mac: "CC9E27179B40")
            GatewayOrphanCleanup.reconcile(site: site, payload: payload)
            if scenario == "active-import" { GatewayOrphanGuard.endImport(scope) }
            let remaining = try app.scalar("SELECT count(*) FROM gateways") as! Int64
            let expected: Int64 = scenario == "absent" ? 0 : ["remote", "busy", "receipt"].contains(scenario) ? 1 : 3
            check(remaining == expected, "Production adapter: \(scenario)")
            check((site.spaces[0].relevanceGatewayId == nil) == (scenario == "absent"), "Publish Space metadata only after successful removal")
            check(GatewayOrphanGuard.isCurrent(oldToken) == (scenario != "absent"), "Invalidate old callbacks only for committed removals")
        }
    }
}
