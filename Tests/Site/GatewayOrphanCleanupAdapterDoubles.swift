import Foundation
import SQLite

// Only platform services are doubled. Tests execute the production reconciliation
// adapter and its SQL against SQLite; no device or server calls are made.
enum UserData {
    static var currentUserId = "owner"
    static var currentServerRegion = "region"
}
enum SpaceMembershipCoordinator {
    static var acceptsResponse = true
    static func accepts(_ payload: [String: Any]) -> Bool { acceptsResponse }
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
}
final class MeshDataManager {
    static let shared = MeshDataManager()
    static var customDatabasePath: String?
    var db: Connection?
    func databaseReadRevision() -> String? {
        guard let db, let version = try? db.scalar("PRAGMA data_version") as? Int64 else { return nil }
        return "\(ObjectIdentifier(db)):\(db.totalChanges):\(version)"
    }
}
final class SiteData {
    enum Permission { case owner, editor, visitor }
    let id = "adapter-site"
    let meshUUID = "site"
    let meshNetworkId = "primary"
    var permission = Permission.owner
    var spaces = [SpaceData()]
}
final class SpaceData {
    enum Status { case notBound, online }
    var relevanceGatewayId: String? = "CC9E27179B40"
    var gatewayStatus = Status.online
    var gatewayLastOnline: Int64? = 100
}
enum GatewayDeletionContext {
    static var protectedMACs = Set<String>()
    static func lockImport() {}
    static func unlockImport() {}
    static func hasPendingDeletion(siteId: String, mac: String) -> Bool { protectedMACs.contains(mac) }
}
final class GatewayModel {
    let mac: String
    let address: UInt16
    let serverDeletionPendingLocalReset: Bool
    init(mac: String, address: UInt16, pending: Bool) {
        self.mac = mac; self.address = address; serverDeletionPendingLocalReset = pending
    }
    static func load(siteId: String, macAddress: String) -> [GatewayModel] {
        guard let rows = try? SunSmartDataManager.shared.db?.prepare(
            "SELECT macAddress, address, serverDeletionPendingLocalReset FROM gateways WHERE siteUUID = ? AND macAddress = ?", siteId, macAddress) else { return [] }
        return rows.map { .init(mac: $0[0] as! String, address: UInt16($0[1] as! Int64), pending: $0[2] as! Int64 == 1) }
    }
}
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    var busyMACs = Set<String>()
    func getGatewayCurrentSyncState(_ gateway: GatewayModel) -> Bool? { busyMACs.contains(gateway.mac) ? true : nil }
}
