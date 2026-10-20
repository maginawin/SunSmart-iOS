import Foundation
extension String { var localizedString: String { self }; var hex: String { self } }
enum UserData { static var currentUserId = "user", currentServerRegion = "region" }
final class SpaceData {
    var siteId = "site", id = "space", meshUUID = "11111111-1111-4111-8111-111111111111", meshNetworkId = "network"
    var canEditing = true, hdbLoadFailed = false
    enum Operation { case edit }
    var groupOperates: [Operation] { canEditing ? [.edit] : [] }
    static var persisted = SpaceData()
    static func load(siteId: String, spaceId: String? = nil) -> [SpaceData] { [persisted] }
}
final class SiteData {
    var id = "site"
    static var hdb = true
    func loadIsHdbSite() throws -> Bool { Self.hdb }
    static func load(siteId: String) -> SiteData? { SiteData() }
}
enum SpaceConfigurationSafety { static var blocked = false; static func isBlocked(_ space: SpaceData) -> Bool { blocked } }
enum HDBConfigurationStore {
    static var config = HDBConfiguration(), version: Int64 = 1
    static func load(space: SpaceData) throws -> HDBConfiguration { config }
    static func revision(space: SpaceData) throws -> Int64 { version }
}
final class NodeSyncReadContext {
    static var current: NodeSyncReadContext?
    var networkID: String? = "network"
    func memoized<T>(_ key: String, read: () -> T) -> T { read() }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = TestNetworkKey()
    func send(_ message: AcknowledgedConfigMessage, to address: UInt16) async throws -> ConfigResponse { fatalError("inject transport") }
}
final class MeshProxyMessageCommand { static let shared = MeshProxyMessageCommand(); var isBusy = false }
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
    var subElementGroupSubscriptionModelIDs: [UInt16] = [0x1306, 0x130F]
}
enum HDBZoneControlError: Error { case disconnected }
enum HDBDeviceSyncService {
    // Inject production sensorPublicationRetransmit here.
}
// Inject SensorPublicationPolicy here.
