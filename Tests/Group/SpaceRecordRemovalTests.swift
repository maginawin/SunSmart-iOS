import Foundation

// Isolated SDK/App persistence boundaries. The production deletion method is
// appended by the runner; no production database or credentials are accessed.
enum Records {
    static var rows: [String: Set<String>] = [:]
    static var failure: String?
    static func remove(_ table: String, _ site: String, _ subnet: String?) -> Bool {
        guard let subnet, !subnet.isEmpty, failure != table else { return false }
        rows[table]?.remove(site + ":" + subnet)
        return true
    }
}
final class SpaceData {
    enum Permission { case owner, editor, visitor }
    static var spaces: [SpaceData] = []
    let id: String, siteId: String, meshUUID: String, meshNetworkId: String
    var needUploadCloud = true
    var syncCloudError: Int?
    var retired = false, removing = false
    var permission = Permission.owner, blocked = false
    init(_ id: String, site: String, subnet: String) {
        self.id = id; siteId = site; meshUUID = site; meshNetworkId = subnet
    }
    static func load(siteId: String) -> [SpaceData] { spaces.filter { $0.siteId == siteId && !$0.retired } }
    func deleteData() -> Bool { retired = true; return true }
}
final class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: Int? = 1 }
final class MeshDataManager {
    static let shared = MeshDataManager()
    var available = true
    func databaseReadRevision() -> String? { available ? "revision" : nil }
}
enum SpaceConfigurationSafety {
    static var cleanupPending = false
    static func hasPendingDeletionCleanup(_ space: SpaceData) -> Bool { cleanupPending }
    static func hasPendingImport(_ space: SpaceData) -> Bool { false }
    static func isBlocked(_ space: SpaceData) -> Bool { space.blocked }
    static func beginRemoval(_ space: SpaceData) -> Bool { space.removing = true; return true }
}
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    func cancelSynchronizationHandle(space: SpaceData) {}
}
struct NetworkID { let hex: String }
struct Key { let index: Int; let networkId: NetworkID; var isPrimary: Bool { index == 0 } }
enum SpaceMeshKeyStore {
    enum Issue: Error { case missing }
    static func export(network: MeshNetwork, networkId: String) -> Result<Void, Issue> {
        network.networkKeys.contains { $0.networkId.hex == networkId } ? .success(()) : .failure(.missing)
    }
}
final class MeshNetwork {
    static var networks: [String: MeshNetwork] = [:]
    let uuid: UUID
    var networkKeys: [Key]
    var nodes: [Node] = []
    init(_ id: UUID, keys: [Key]) { uuid = id; networkKeys = keys }
    static func load(meshUUID: String, subnetworkId: String) -> MeshNetwork? { networks[meshUUID] }
    static func load(meshUUID: String, allData: Bool) -> MeshNetwork? { networks[meshUUID] }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    static var keyRemovals = 0
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = Key(index: 1, networkId: .init(hex: "peer"))
    static func removeSubnetwork(meshUUID: String, networkId: String) -> Bool {
        keyRemovals += 1
        MeshNetwork.networks[meshUUID]?.networkKeys.removeAll { $0.networkId.hex == networkId }
        return true
    }
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var disconnects = 0
    func meshNetworkDisconnect() { disconnects += 1 }
}
struct Node {
    var isProvisioner = false, isLocalProvisioner = false
    static func deleteAllPropertys(meshUUID: String, subnetworkId: String?) -> Bool { Records.remove("properties", meshUUID, subnetworkId) }
    static func deleteAll(meshUUID: String, subnetworkId: String?) -> Bool { Records.remove("nodes", meshUUID, subnetworkId) }
}
enum Group { static func deleteAll(meshUUID: String, subnetworkId: String?) -> Bool { Records.remove("groups", meshUUID, subnetworkId) } }
enum Scene { static func deleteAll(meshUUID: String, subnetworkId: String?) -> Bool { Records.remove("scenes", meshUUID, subnetworkId) } }
enum GroupInfo { static func delete(meshUUID: String, networkId: String) -> Bool { Records.remove("groupInfo", meshUUID, networkId) } }
enum SceneInfo { static func delete(meshUUID: String, networkId: String) -> Bool { Records.remove("sceneInfo", meshUUID, networkId) } }
enum Schedule { static func deleteAll(meshUUID: String, meshNetworkId: String) -> Bool { Records.remove("schedules", meshUUID, meshNetworkId) } }
enum Profile { static func deleteProfiles(meshUUID: String, meshNetworkId: String) -> Bool { Records.remove("profiles", meshUUID, meshNetworkId) } }
enum DeviceSwitchData {
    static var records: [Int] = []
    static func load(meshUUID: String, meshNetworkId: String) -> [Int] { records }
    static func deleteSwitchs(meshUUID: String, networkId: String) -> Bool { Records.remove("switches", meshUUID, networkId) } }

enum GroupSwitch {
    static func deleteSwitchs(meshUUID: String, networkId: String) -> Bool { Records.remove("groupSwitches", meshUUID, networkId) }
}
enum DeviceDongleData {
    static func deleteDongles(meshUUID: String, networkId: String) -> Bool { Records.remove("dongles", meshUUID, networkId) }
    static var records: [Int] = []
    static func load(meshUUID: String, meshNetworkId: String) -> [Int] { records }
}
enum DeviceEmerFireData {
    static func deleteAll(meshUUID: String, networkId: String) -> Bool { Records.remove("efc", meshUUID, networkId) }
    static var records: [Int] = []
    static func load(meshUUID: String, meshNetworkId: String, spaceId: String) -> [Int] { records }
}

@main struct SpaceRecordRemovalTests {
    static func main() {
        let site = UUID(), otherSite = UUID()
        let target = SpaceData("target", site: site.uuidString, subnet: "missing-key")
        let peer = SpaceData("peer", site: site.uuidString, subnet: "peer")
        let elsewhere = SpaceData("elsewhere", site: otherSite.uuidString, subnet: "missing-key")
        SpaceData.spaces = [target, peer, elsewhere]
        let network = MeshNetwork(site, keys: [Key(index: 1, networkId: .init(hex: "peer"))])
        MeshNetwork.networks[site.uuidString] = network
        MeshNetworkManager.instance.meshNetwork = network
        network.nodes = [Node()]
        target.blocked = true
        precondition(!target.canDeleteEmptySpaceRecords, "broken Space still has a device")
        precondition(target.canDeleteSpaceRecords, "Owner can delete a blocked nonempty Space")
        target.permission = .editor
        precondition(!target.canDeleteSpaceRecords, "Editor cannot use the exception")
        target.permission = .visitor
        precondition(!target.canDeleteSpaceRecords)
        target.permission = .owner
        target.blocked = false
        precondition(!target.canDeleteSpaceRecords, "ordinary pending upload is not a failure")
        target.syncCloudError = 9999
        precondition(target.canDeleteSpaceRecords)
        target.needUploadCloud = false
        precondition(!target.canDeleteSpaceRecords, "stale error after successful upload is not an exception")
        target.needUploadCloud = true; target.syncCloudError = nil; target.blocked = true
        network.nodes = []
        precondition(target.canDeleteEmptySpaceRecords)
        DeviceSwitchData.records = [1]
        precondition(!target.canDeleteEmptySpaceRecords, "non-Mesh switches also prevent deletion")
        DeviceSwitchData.records = []
        DeviceDongleData.records = [1]
        precondition(!target.canDeleteEmptySpaceRecords, "Dongle records also prevent deletion")
        DeviceDongleData.records = []
        DeviceEmerFireData.records = [1]
        precondition(!target.canDeleteEmptySpaceRecords, "emergency/fire devices also prevent deletion")
        DeviceEmerFireData.records = []
        SpaceConfigurationSafety.cleanupPending = true
        precondition(!target.canDeleteEmptySpaceRecords, "unfinished deletion cannot masquerade as empty")
        precondition(target.canDeleteSpaceRecords, "blocked Owner may remove the whole Space without finishing per-device cleanup")
        SpaceConfigurationSafety.cleanupPending = false
        target.permission = .visitor
        precondition(!target.canDeleteEmptySpaceRecords)
        target.permission = .owner
        for table in ["properties", "nodes", "groups", "scenes", "groupInfo", "sceneInfo", "schedules", "profiles", "switches", "groupSwitches", "dongles", "efc"] {
            Records.rows[table] = Set(SpaceData.spaces.map { $0.siteId + ":" + $0.meshNetworkId })
        }
        Records.failure = "nodes"
        precondition(!target.delete() && !target.retired && target.removing)
        Records.failure = "efc"
        precondition(!target.delete() && !target.retired, "side-store failure retains Space for retry")
        Records.failure = nil
        precondition(target.delete() && target.retired)
        for rows in Records.rows.values {
            precondition(!rows.contains(site.uuidString + ":missing-key"))
            precondition(rows.contains(site.uuidString + ":peer"))
            precondition(rows.contains(otherSite.uuidString + ":missing-key"))
        }
        precondition(network.networkKeys.count == 1 && network.networkKeys[0].networkId.hex == "peer")
        precondition(MeshNetworkManager.keyRemovals == 0 && MeshLibManager.manager.disconnects == 0)
        let duplicate = SpaceData("duplicate", site: peer.siteId, subnet: peer.meshNetworkId)
        SpaceData.spaces.append(duplicate)
        peer.blocked = true
        precondition(!peer.canDeleteEmptySpaceRecords)
        precondition(!peer.canDeleteSpaceRecords, "exception cannot erase a shared subnet")
        precondition(!peer.delete() && !peer.removing, "shared Network ID must not erase another Space")
        SpaceData.spaces.removeAll { $0 === duplicate }
        network.networkKeys = [Key(index: 0, networkId: .init(hex: "peer"))]
        precondition(!peer.canDeleteSpaceRecords, "primary network is never a Space removal target")
        MeshDataManager.shared.available = false
        precondition(!elsewhere.canDeleteSpaceRecords)
        precondition(!elsewhere.delete() && !elsewhere.retired)
        print("PASS: production local removal cleans missing-key subnet, preserves peer Site/Space and keys, retains failed work and rejects unavailable stores")
    }
}
