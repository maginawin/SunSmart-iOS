import Foundation
import SQLite
import SQLite3

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
        // Retry on the same live connection must commit durably, even after a
        // nested failure. A read on that connection alone can hide an open savepoint.
        precondition(store.configurationTransaction { try app.run("UPDATE evidence SET value = 9") })
        let independent = try Connection(appURL.path, readonly: true)
        let retried = try independent.scalar("SELECT value FROM evidence") as? Int64
        precondition(retried == 9, "Failed savepoints must not trap subsequent successful retries")
        enum CommitFailure: Error { case injected }
        var expected: Int64 = 9
        for value: Int64 in [10, 20] {
            var hookCalls = 0
            app.commitHook { hookCalls += 1; throw CommitFailure.injected }
            let committed = store.configurationTransaction { try app.run("UPDATE evidence SET value = ?", value) }
            app.commitHook(nil)
            guard !committed, hookCalls == 1, sqlite3_get_autocommit(app.handle) == 1 else {
                print("FAIL: final commit failure leaked savepoint or reported success"); exit(1)
            }
            precondition(tryValue { try app.scalar("SELECT value FROM evidence") as? Int64 == expected })
            precondition(tryValue { try independent.scalar("SELECT value FROM evidence") as? Int64 == expected })
            expected = value + 1
            precondition(store.configurationTransaction { try app.run("UPDATE evidence SET value = ?", expected) })
            precondition(sqlite3_get_autocommit(app.handle) == 1)
            let reopened = try Connection(appURL.path, readonly: true)
            precondition(tryValue { try reopened.scalar("SELECT value FROM evidence") as? Int64 == expected })
        }
        // Failure inside our savepoint must preserve a caller-owned transaction.
        try app.transaction {
            try app.run("UPDATE evidence SET value = 31")
            let inner = store.configurationTransaction {
                try app.run("UPDATE evidence SET value = 32")
                throw CommitFailure.injected
            }
            precondition(!inner && sqlite3_get_autocommit(app.handle) == 0)
            precondition(tryValue { try app.scalar("SELECT value FROM evidence") as? Int64 == 31 })
            precondition(tryValue { try independent.scalar("SELECT value FROM evidence") as? Int64 == expected })
            precondition(store.configurationTransaction { try app.run("UPDATE evidence SET value = 33") })
            precondition(sqlite3_get_autocommit(app.handle) == 0)
        }
        precondition(sqlite3_get_autocommit(app.handle) == 1)
        precondition(tryValue { try independent.scalar("SELECT value FROM evidence") as? Int64 == 33 })
        try app.savepoint("caller_owned") {
            try app.run("UPDATE evidence SET value = 34")
            precondition(!store.configurationTransaction { throw CommitFailure.injected })
            precondition(sqlite3_get_autocommit(app.handle) == 0)
            precondition(tryValue { try app.scalar("SELECT value FROM evidence") as? Int64 == 34 })
        }
        var bodyCalls = 0
        precondition(!store.configurationTransaction {
            bodyCalls += 1
            throw SQLite.Result.error(message: "cannot start a transaction within a transaction", code: 1, statement: nil)
        })
        precondition(bodyCalls == 1 && sqlite3_get_autocommit(app.handle) == 1, "body errors must not trigger replay")
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let waiting = DispatchSemaphore(value: 0), bodyEntered = DispatchSemaphore(value: 0)
        let firstDone = DispatchSemaphore(value: 0), secondDone = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            defer { firstDone.signal() }
            try! app.transaction {
                precondition(store.configurationTransaction { try app.run("UPDATE evidence SET value = 41") })
                entered.signal()
                precondition(release.wait(timeout: .now() + 10) == .success)
            }
        }
        precondition(entered.wait(timeout: .now() + 10) == .success)
        DispatchQueue.global().async {
            defer { secondDone.signal() }
            waiting.signal()
            precondition(store.configurationTransaction {
                bodyEntered.signal()
                try app.run("UPDATE evidence SET value = 42")
            })
        }
        precondition(waiting.wait(timeout: .now() + 10) == .success)
        precondition(bodyEntered.wait(timeout: .now() + 0.05) == .timedOut, "concurrent body bypassed connection serialization")
        release.signal()
        precondition(firstDone.wait(timeout: .now() + 10) == .success)
        precondition(secondDone.wait(timeout: .now() + 10) == .success)
        precondition(sqlite3_get_autocommit(app.handle) == 1)
        precondition(tryValue { try independent.scalar("SELECT value FROM evidence") as? Int64 == 42 })
        print("PASS: final commit failure, repeated retry/reopen and caller-owned outer transaction isolation/concurrent serialization")
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

private func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
