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
enum NodeSyncStatusGeneration { static var invalidations = 0; static func invalidate() { invalidations += 1 } }
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
        let standardObject = try SiteExtensionStore.load(standard).data.jsonObject()
        precondition(standardObject["siteType"] as? String == "Standard" && standardObject["isHdbSite"] == nil)
        let hdb = try SiteData.add(name: "HDB", siteType: .hdb)
        precondition(hdb.isHdbSite && !standard.isHdbSite, "Chosen type must be durable from the first save")
        var metadata = SiteExtensionData()
        metadata.fields["countryRegion"] = .string("CN")
        metadata.fields["city"] = .string("geonames:1796236")
        metadata.fields["description"] = .string("Lobby")
        metadata.fields["postalCode"] = .string("018983")
        metadata.fields["latitude"] = .string("0")
        metadata.fields["longitude"] = .string("121.45806")
        let formSite = try SiteData.add(name: "Form", siteType: .hdb, imageId: 28,
                                        timezone: nil, extensionData: metadata)
        precondition(formSite.timezone == nil && formSite.pendingSitePropsMask.isEmpty)
        precondition(formSite.pendingSitePropsTimestamp == nil)
        let configured = try SiteData.add(name: "Configured", imageId: 3,
                                          timezone: "Asia/Shanghai (UTC+08:00)", extensionData: metadata)
        precondition(configured.pendingSitePropsMask.contains(.timezone))
        try db.execute("CREATE TRIGGER fail_extension BEFORE INSERT ON site_extensions BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let beforeFailure = MeshNetworkManager.allocated
        rejected = false
        do { _ = try SiteData.add(name: "Failed form", siteType: .hdb, imageId: 28,
                                  timezone: nil, extensionData: metadata) } catch { rejected = true }
        precondition(rejected && MeshNetworkManager.allocated == beforeFailure)
        let failedRows = try db.scalar("SELECT count(*) FROM sites WHERE name = 'Failed form'") as! Int64
        precondition(failedRows == 0)
        try db.execute("DROP TRIGGER fail_extension")
        let retry = try SiteData.add(name: "Retried country form", timezone: nil, extensionData: metadata)
        let retriedMetadata = try SiteExtensionStore.load(retry).data
        precondition(retriedMetadata.fields["countryRegion"] == .string("CN"))
        precondition(retriedMetadata.fields["city"] == .string("geonames:1796236"))
        SunSmartDataManager.shared.db = try Connection(path)
        let restoredForm = SiteData.load(siteId: formSite.id)!
        precondition(restoredForm.imageId == 28 && restoredForm.timezone == nil && restoredForm.isHdbSite)
        let restoredMetadata = try SiteExtensionStore.load(restoredForm).data
        precondition(restoredMetadata.fields["countryRegion"] == .string("CN"))
        precondition(restoredMetadata.fields["description"] == .string("Lobby"))
        precondition(restoredMetadata.fields["postalCode"] == .string("018983"))
        precondition(restoredMetadata.fields["latitude"] == .string("0"))
        precondition(restoredMetadata.fields["city"] == .string("geonames:1796236"))
        precondition(restoredMetadata.fields["longitude"] == .string("121.45806"))
        let restoredConfigured = SiteData.load(siteId: configured.id)!
        precondition(restoredConfigured.timezone == "Asia/Shanghai (UTC+08:00)")
        let configuredMetadata = try SiteExtensionStore.load(restoredConfigured).data
        precondition(configuredMetadata.fields["city"] == .string("geonames:1796236"))
        precondition(restoredConfigured.copy().siteExtensionData == configuredMetadata)
        precondition(restoredForm.save())
        let afterSave = try SiteExtensionStore.load(restoredForm).data
        precondition(afterSave == restoredMetadata)
        let formClone = restoredForm.cloneData()
        precondition(formClone.save())
        let clonedMetadata = try SiteExtensionStore.load(formClone).data
        precondition(clonedMetadata == restoredMetadata)
        let reloaded = SiteData.load(siteId: hdb.id)!
        precondition(!reloaded.siteExtensionData.isHdbSite && reloaded.isHdbSite,
                     "Durable type must win over a reloaded Site object's default extension")
        precondition(SiteData.loadAll().first(where: { $0.id == hdb.id })!.isHdbSite)
        precondition(reloaded.save() && reloaded.isHdbSite, "A legacy Site save cannot overwrite its extension")
        let copy = reloaded.copy(), clone = reloaded.cloneData()
        precondition(copy.isHdbSite && clone.save() && clone.isHdbSite)
        try SiteExtensionStore.receive(reloaded, object: ["extensionData": "{}"], timestamp: 1)
        precondition(reloaded.isHdbSite)
        try SiteExtensionStore.receive(reloaded, object: ["extensionData": ["siteType": NSNull()]], timestamp: 2)
        precondition(!reloaded.isHdbSite && clone.isHdbSite)
        try legacySnapshots(path: path)
        UserData.currentServerRegion = .second
        precondition(SiteData.load(siteId: standard.id) == nil, "Site extension must remain region scoped")
        UserData.currentServerRegion = .first
        SunSmartDataManager.shared.db = nil
        precondition(!reloaded.isHdbSite)
        do { _ = try reloaded.loadIsHdbSite(); fatalError("Database failure must not become a Standard mutation") }
        catch SiteExtensionStore.StoreError.databaseUnavailable {}
        print("PASS: real SQLite Site save rollback, restart, durable type reads, copy/clone, partial import and region scope")
    }

    static func legacySnapshots(path: String) throws {
        let legacy = try SiteData.add(name: "Legacy true")
        var base = try SiteExtensionData().jsonObject()
        base.removeValue(forKey: "siteType")
        base["isHdbSite"] = true
        base["future"] = ["keep": 7]
        var target = base
        target["triggerZones"] = try SiteExtensionData().replacingZone(SiteTriggerZone())!.jsonObject()["triggerZones"]
        let operation = UUID()
        let pending: [String: Any] = ["operationId": operation.uuidString, "timestamp": 11, "base": base, "target": target]
        let oldPayload: [String: Any] = ["data": target, "serverData": base, "serverTimestamp": 10,
                                         "pending": pending, "submitted": pending, "archivedPendings": [pending],
                                         "archivedReviewNeeded": true, "conflict": false]
        let bytes = try JSONSerialization.data(withJSONObject: oldPayload)
        try SunSmartDataManager.shared.db!.run(Table("site_extensions").filter(Expression<String>("siteId") == legacy.id)
            .update(Expression<Data>("payload") <- bytes))
        SunSmartDataManager.shared.db = try Connection(path)
        let restored = SiteData.load(siteId: legacy.id)!
        let state = try SiteExtensionStore.load(restored)
        precondition(!restored.isHdbSite && state.pending?.operationId == operation && state.needsArchivedReview)
        let snapshots = [state.data, state.serverData, state.pending?.base, state.pending?.target,
                         state.submitted?.base, state.submitted?.target,
                         state.archivedPendings?.first?.base, state.archivedPendings?.first?.target].compactMap { $0 }
        precondition(snapshots.count == 8)
        for snapshot in snapshots {
            let object = try snapshot.jsonObject()
            precondition(!snapshot.isHdbSite && object["siteType"] is NSNull && object["isHdbSite"] == nil)
            precondition(snapshot.fields["future"] == .object(["keep": .integer(7)]))
        }
        let clone = restored.cloneData()
        precondition(!restored.copy().isHdbSite && clone.save() && !clone.isHdbSite)
        try SiteExtensionStore.update(restored) { _ in }
        let row = try SunSmartDataManager.shared.db!.pluck(Table("site_extensions").filter(Expression<String>("siteId") == restored.id))!
        let rewritten = row[Expression<Data>("payload")]
        precondition(!String(decoding: rewritten, as: UTF8.self).contains("isHdbSite"))
        let afterWrite = try JSONDecoder().decode(SiteExtensionState.self, from: rewritten)
        precondition(afterWrite.pending?.operationId == operation && afterWrite.submitted?.operationId == operation)
        // An old-format receipt still confirms the pending Zone change without enabling HDB.
        try SiteExtensionStore.receive(restored, object: ["extensionData": target], timestamp: 12)
        let confirmed = try SiteExtensionStore.load(restored)
        precondition(confirmed.pending == nil && !confirmed.data.isHdbSite && confirmed.data.zones?.count == 1)

        let before = NodeSyncStatusGeneration.invalidations
        try SiteExtensionStore.update(restored) { $0.data.siteType = .standard }
        precondition(NodeSyncStatusGeneration.invalidations == before, "null/Standard must not invalidate HDB status")
        try SiteExtensionStore.update(restored) { $0.data.siteType = .hdb }
        precondition(NodeSyncStatusGeneration.invalidations == before + 1 && restored.isHdbSite)
        try SiteExtensionStore.update(restored) { $0.data.siteType = nil }
        precondition(NodeSyncStatusGeneration.invalidations == before + 2 && !restored.isHdbSite)
        print("PASS: legacy true SQLite snapshots, pending identities, lossless Zones, new-key-only rewrite and effective-type cache invalidation")
    }
}
