import Foundation
import SQLite
struct NetworkApiError { let code: Int }
final class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: Connection? }
final class SpaceData {
    var id = "space", siteId = "site", meshNetworkId = "network"
    var lastUpdate: Int64 = 100, lastUploadCloudTimestamp: Int64? = 90
    var syncCloudError: NetworkApiError?
    static func load(siteId: String, spaceId: String) -> [SpaceData] {
        guard let db = SunSmartDataManager.shared.db,
              let value = try? db.scalar("SELECT lastUpdateTimestamp FROM spaces WHERE uuid = ?", spaceId) as? Int64 else { return [] }
        let space = SpaceData(); space.lastUpdate = value; return [space]
    }
    // PRODUCTION
}
@main struct SpaceUploadPersistenceTests {
    static func main() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sqlite")
        defer { try? FileManager.default.removeItem(at: path) }
        let db = try Connection(path.path); SunSmartDataManager.shared.db = db
        try db.run("CREATE TABLE spaces (uuid TEXT, siteUUID TEXT, subNetworkKey TEXT, name TEXT, lastUpdateTimestamp INTEGER, lastUploadCloudTimestamp INTEGER, syncCloudError INTEGER)")
        try db.run("INSERT INTO spaces VALUES ('space', 'site', 'network', 'new edit', 101, 90, NULL)")
        let old = SpaceData()
        precondition(old.saveCloudSyncOutcome(confirmedTimestamp: 100, error: nil))
        precondition(old.lastUpdate == 101 && old.lastUploadCloudTimestamp == 100)
        precondition(try! db.scalar("SELECT name FROM spaces") as? String == "new edit")
        precondition(try! db.scalar("SELECT lastUpdateTimestamp FROM spaces") as? Int64 == 101)
        precondition(old.saveCloudSyncOutcome(confirmedTimestamp: 99, error: nil))
        precondition(try! db.scalar("SELECT lastUploadCloudTimestamp FROM spaces") as? Int64 == 100)
        precondition(old.saveCloudSyncOutcome(error: .init(code: -1001)))
        precondition(try! db.scalar("SELECT syncCloudError FROM spaces") as? Int64 == -1001)
        let stranger = SpaceData(); stranger.meshNetworkId = "other"
        precondition(!stranger.saveCloudSyncOutcome(confirmedTimestamp: 999, error: nil))
        try db.run("PRAGMA query_only = ON")
        precondition(!old.saveCloudSyncOutcome(confirmedTimestamp: 101, error: nil))
        precondition(old.lastUploadCloudTimestamp == 100)
        let reopened = try Connection(path.path)
        precondition(try! reopened.scalar("SELECT lastUploadCloudTimestamp FROM spaces") as? Int64 == 100)
        print("PASS: production SQLite upload finalization preserves concurrent fields/version, monotonic confirmation, scoped errors and failed-write recovery")
    }
}
