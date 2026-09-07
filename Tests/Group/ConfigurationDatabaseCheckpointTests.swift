import Foundation
import SQLite

@main
struct ConfigurationDatabaseCheckpointTests {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let output = root.appendingPathComponent("snapshot")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("app.sqlite3")
        let meshURL = root.appendingPathComponent("mesh.sqlite3")
        let app = try Connection(appURL.path)
        let mesh = try Connection(meshURL.path)
        for db in [app, mesh] {
            try db.execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; CREATE TABLE evidence (value INTEGER NOT NULL)")
        }
        try app.run("INSERT INTO evidence VALUES (7)")
        try mesh.run("INSERT INTO evidence VALUES (184)")
        try ConfigurationDatabaseCheckpoint.save(appDatabase: appURL, meshDatabase: meshURL, destination: output)
        let savedApp = try Connection(output.appendingPathComponent("sunsmart.sqlite3").path)
        let savedMesh = try Connection(output.appendingPathComponent("mesh.sqlite3").path)
        let appValue = try savedApp.scalar("SELECT value FROM evidence") as? Int64
        let meshValue = try savedMesh.scalar("SELECT value FROM evidence") as? Int64
        precondition(appValue == 7 && meshValue == 184)
        try app.run("UPDATE evidence SET value = 1")
        let snapshotValue = try savedApp.scalar("SELECT value FROM evidence") as? Int64
        precondition(snapshotValue == 7)
        do {
            try ConfigurationDatabaseCheckpoint.save(appDatabase: root.appendingPathComponent("missing"),
                meshDatabase: meshURL, destination: output)
            fatalError("Missing source must fail")
        } catch {}

        // Execute the App's actual savepoint wrapper with a failing second write.
        let store = SunSmartDataManager(db: app)
        let succeeded = store.configurationTransaction {
            try app.run("UPDATE evidence SET value = 8")
            try app.run("INSERT INTO evidence VALUES (NULL)")
        }
        precondition(!succeeded)
        let rolledBack = try app.scalar("SELECT value FROM evidence") as? Int64
        precondition(rolledBack == 1)
        let nested = store.configurationTransaction {
            let inner = store.configurationTransaction { try app.run("UPDATE evidence SET value = 8") }
            precondition(inner)
            try app.run("INSERT INTO evidence VALUES (NULL)")
        }
        let outerRolledBack = try app.scalar("SELECT value FROM evidence") as? Int64
        precondition(!nested && outerRolledBack == 1)
        precondition(!SunSmartDataManager(db: nil).configurationTransaction {})
        // Reproduce the historical NOT NULL schema using the same production
        // compatibility setter called by Profile.save().
        let profiles = Table("profiles")
        let id = SQLite.Expression<String>("id")
        let type = SQLite.Expression<Int>("type")
        try app.run("CREATE TABLE profiles (id TEXT PRIMARY KEY, type INTEGER NOT NULL, regulatorAccuracy INTEGER NOT NULL)")
        func saveProfile(_ name: String, type value: Int) throws {
            let legacy = try ProfileStorageCompatibility.preservedColumns(db: app,
                table: profiles, tableName: "profiles", identity: id == name)
            try app.run(profiles.insert(or: .replace, [id <- name, type <- value] + legacy))
        }
        try saveProfile("original", type: 7)
        let seeded = try app.scalar("SELECT regulatorAccuracy FROM profiles") as? Int64
        precondition(seeded == 0x14)
        try app.run("UPDATE profiles SET regulatorAccuracy = 33")
        try saveProfile("original", type: 1)
        let preserved = try app.scalar("SELECT regulatorAccuracy FROM profiles") as? Int64
        let switched = try app.scalar("SELECT type FROM profiles") as? Int64
        precondition(preserved == 33 && switched == 1)
        try app.run("CREATE TABLE current_profiles (id TEXT PRIMARY KEY, type INTEGER NOT NULL)")
        let unchanged = try ProfileStorageCompatibility.preservedColumns(db: app,
            table: Table("current_profiles"), tableName: "current_profiles", identity: id == "new")
        precondition(unchanged.isEmpty)
        print("PASS: real SQLite WAL snapshots, isolation, failed checkpoint, transaction rollback and unavailable connection")
        print("PASS: legacy NOT NULL profile schema, preservation and complete type 7 -> 1 save")
    }
}
