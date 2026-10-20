import Foundation
import SQLite

// Unrelated application/SDK boundaries. SQL methods and extension state are production code.
typealias Address = UInt16
extension UInt16 { static let minUnicastAddress: UInt16 = 1 }
extension String { var hex: String { self } }
enum ServerRegion: Int { case first = 1, second = 2 }
enum UserData { static var currentServerRegion = ServerRegion.first }
enum Permission: Int { case owner = 1, editor, visitor }
enum DataSourceType: Int { case create = 1, clone, share }
struct SitePropsFieldMask: OptionSet { let rawValue: Int; static let timezone = Self(rawValue: 1) }
struct NetworkApiError { let code: Int; init(code: Int) { self.code = code } }
struct RecycleAddressData: Codable {}
let jsonEncoder = JSONEncoder(), jsonDecoder = JSONDecoder()
enum SiteTimeZoneCatalog {
    struct Value { let storageValue = "Asia/Singapore (UTC+08:00)" }
    static func phoneDefaultValue() -> Value { Value() }
}
final class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: Connection? }
final class SpaceData {
    var siteId = ""
    static func initDatabase() {}
    static func load(siteId: String) -> [SpaceData] { [] }
    func copy() -> SpaceData { SpaceData() }
    func cloneData() -> SpaceData { SpaceData() }
    @discardableResult func save() -> Bool { true }
}
enum NodeSyncStatusGeneration { static func invalidate() {} }
final class TestNode { func clearSyncStateCache() {} }
final class TestNetwork { var uuid = UUID(); var nodes: [TestNode] = [] }
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: TestNetwork?
    struct Key { let networkId = "network" }
    var mainNetworkKey = Key()
    static var allocated: Set<String> = []
    static func createMeshNetwork(meshUUID: String, meshNetworkName: String, localAddress: Address) -> MeshNetworkManager {
        allocated.insert(meshUUID); return MeshNetworkManager()
    }
    static func removeMeshNetwork(meshUUID: String) -> Bool { allocated.remove(meshUUID) != nil }
}
final class SiteData {
    enum SiteType: Int { case office = 1 }
    enum State: Int { case normal = 1 }
    var siteExtensionData = SiteExtensionData()
    var gatewayPresence = false
    let region: ServerRegion
    var id: String, meshUUID: String, meshNetworkId: String, name: String
    var imageId: Int, type: SiteType, permission: Permission, sourceType: DataSourceType
    var create: Int64, lastUpdate: Int64
    var isFavourite: Bool, timezone: String?
    var pendingSitePropsMask: SitePropsFieldMask = []
    var pendingSitePropsTimestamp: Int64?, lastUploadCloudTimestamp: Int64?
    var state = State.normal
    var spaceCount: Int?, syncCloudError: NetworkApiError?
    var transferCode: String?, transferPassword: String?, localAddress: Address?
    var recycleAddressData: RecycleAddressData?, spaces: [SpaceData] = []
    init(region: ServerRegion, id: String, meshUUID: String, meshNetworkId: String, name: String,
         imageId: Int = 0, type: SiteType, permission: Permission, create: Int64, lastUpdate: Int64? = nil,
         isFavourite: Bool, sourceType: DataSourceType) {
        self.region = region; self.id = id; self.meshUUID = meshUUID; self.meshNetworkId = meshNetworkId
        self.name = name; self.imageId = imageId; self.type = type; self.permission = permission
        self.create = create; self.lastUpdate = lastUpdate ?? create; self.isFavourite = isFavourite; self.sourceType = sourceType
    }
}

@main enum SiteHDBPersistenceTests {
    static func main() throws {
        let path = CommandLine.arguments[1]
        SunSmartDataManager.shared.db = try Connection(path)
        SiteData.initDatabase()
        let db = SunSmartDataManager.shared.db!
        // Force failure inside the production Site + extension transaction.
        try db.execute("CREATE TRIGGER fail_extension BEFORE INSERT ON site_extensions BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        var rejected = false
        do { _ = try SiteData.add(name: "Failure") } catch { rejected = true }
        precondition(rejected, "Site creation must report a failed extension save")
        let count = try db.scalar("SELECT count(*) FROM sites") as! Int64
        precondition(count == 0)
        precondition(MeshNetworkManager.allocated.isEmpty, "Failed creation must remove only its newly allocated network")
        try db.execute("DROP TRIGGER fail_extension")
        let standard = try SiteData.add(name: "Standard")
        precondition(!standard.isHdbSite)
        let hdb = try SiteData.add(name: "HDB", isHdbSite: true)
        precondition(hdb.isHdbSite && !standard.isHdbSite, "Chosen type must be durable from the first save")
        SunSmartDataManager.shared.db = try Connection(path)
        let reloaded = SiteData.load(siteId: hdb.id)!
        precondition(!reloaded.siteExtensionData.isHdbSite && reloaded.isHdbSite,
                     "Durable type must win over a reloaded Site object's default extension")
        precondition(SiteData.loadAll().first(where: { $0.id == hdb.id })!.isHdbSite)
        precondition(reloaded.save() && reloaded.isHdbSite, "A legacy Site save cannot overwrite its extension")
        let copy = reloaded.copy(), clone = reloaded.cloneData()
        precondition(copy.isHdbSite && clone.save() && clone.isHdbSite)
        try SiteExtensionStore.receive(reloaded, object: ["extensionData": "{}"], timestamp: 1)
        precondition(reloaded.isHdbSite)
        try SiteExtensionStore.receive(reloaded, object: ["extensionData": ["isHdbSite": NSNull()]], timestamp: 2)
        precondition(!reloaded.isHdbSite && clone.isHdbSite)
        UserData.currentServerRegion = .second
        precondition(SiteData.load(siteId: standard.id) == nil, "Site extension must remain region scoped")
        UserData.currentServerRegion = .first
        SunSmartDataManager.shared.db = nil
        precondition(!reloaded.isHdbSite)
        do { _ = try reloaded.loadIsHdbSite(); fatalError("Database failure must not become a Standard mutation") }
        catch SiteExtensionStore.StoreError.databaseUnavailable {}
        print("PASS: real SQLite Site save rollback, restart, durable type reads, copy/clone, partial import and region scope")
    }
}
