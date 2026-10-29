import Foundation
import SQLite

typealias Expression<T> = SQLite.Expression<T>
typealias Address = UInt16
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    var isUnicast: Bool { self > 0 && self < 0x8000 }
    init?(hex: String) { self.init(hex, radix: 16) }
}
struct IvIndex { var index: UInt32 }
struct Element { var unicastAddress: Address }
struct Node {
    var isLocalProvisioner = false
    var elements: [Element]
}
struct Key {
    var networkId: Identifier
    var isPrimary = false
    struct Identifier { var hex: String }
}
final class MeshDataManager {
    static let shared = MeshDataManager()
    var db: Connection?
}
final class MeshNetwork {
    struct Stored { var nodes: [Node]; var keys: [Key] }
    static var stored: [String: Stored] = [:]
    let uuid: UUID
    var currentIVIndex: UInt32 = 7
    var networkExclusions: [ExclusionList]?
    var nodes: [Node]
    var networkKeys: [Key]
    var applicationKeys: [ApplicationKey] = []
    struct ApplicationKey { var boundNetworkKey: IndexedKey }
    struct IndexedKey { var index: Int }
    var failRemoval = false
    init(uuid: UUID, stored: Stored) {
        self.uuid = uuid; nodes = stored.nodes; networkKeys = stored.keys
        networkExclusions = ExclusionList.load(meshUUID: uuid.uuidString)
    }
    static func load(meshUUID: String, subnetworkId: String? = nil, allData: Bool = true) -> MeshNetwork? {
        guard let value = stored[meshUUID] else { return nil }
        return MeshNetwork(uuid: UUID(uuidString: meshUUID)!, stored: value)
    }
    static func delete(meshUUID: String, subnetworkId: String) { stored[meshUUID]?.nodes = [] }
    func remove(applicationKey: ApplicationKey, force: Bool) throws {}
    func remove(networkKey: Key, force: Bool) throws {
        if failRemoval { throw CocoaError(.fileWriteNoPermission) }
        networkKeys.removeAll { $0.networkId.hex == networkKey.networkId.hex }
        nodes = []
    }
    @discardableResult func save() -> Bool {
        Self.stored[uuid.uuidString] = Stored(nodes: nodes, keys: networkKeys)
        let meshUUID = uuid.uuidString
        // SDK_SAVE_EXCLUSIONS
        return true
    }
    // SDK_INSERT_EXCLUSION
    // SDK_NETWORK_REMOVE
}
extension Key { var index: Int { 1 } }
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
    var currentNetworkKey = Key(networkId: .init(hex: "other-space"))
    // SDK_MANAGER_REMOVE
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Bool? = true
}
enum SpaceConfigurationSafety { static func beginRemoval(_ space: SpaceData) -> Bool { true } }
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    func cancelSynchronizationHandle(space: SpaceData) {}
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    func meshNetworkDisconnect() {}
}
enum Records {
    static var succeeds = true
    static func delete(meshUUID: String, networkId: String) -> Bool { succeeds }
    static func deleteAll(meshUUID: String, meshNetworkId: String) -> Bool { succeeds }
    static func deleteAll(meshUUID: String, networkId: String) -> Bool { succeeds }
    static func deleteProfiles(meshUUID: String, meshNetworkId: String) -> Bool { succeeds }
    static func deleteSwitchs(meshUUID: String, networkId: String) -> Bool { succeeds }
}
typealias GroupInfo = Records
typealias SceneInfo = Records
typealias Schedule = Records
typealias Profile = Records
typealias DeviceSwitchData = Records
typealias DeviceEmerFireData = Records
final class SpaceData {
    let meshUUID: String
    let meshNetworkId = "target-space"
    init(_ uuid: UUID) { meshUUID = uuid.uuidString }
    func deleteData() -> Bool { true }
    // APP_DELETE
}

@main enum SpaceDeletionExclusionTests {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("mesh.sqlite").path
        for mode in ["loaded-target", "loaded-other-space", "unloaded", "other-site", "empty-exclusions", "remove-failure", "cleanup-failure"] {
            MeshDataManager.shared.db = try Connection(path)
            ExclusionList.initDatabase()
            try MeshDataManager.shared.db!.run("DELETE FROM exclusions")
            MeshNetwork.stored = [:]; MeshNetworkManager.instance.meshNetwork = nil
            Records.succeeds = true
            let space = SpaceData(UUID())
            MeshNetwork.stored[space.meshUUID] = .init(nodes: [
                .init(isLocalProvisioner: true, elements: [.init(unicastAddress: 1)]),
                .init(elements: [.init(unicastAddress: 0x10), .init(unicastAddress: 0x11)])
            ], keys: [Key(networkId: .init(hex: space.meshNetworkId))])
            let initial = MeshNetwork.load(meshUUID: space.meshUUID)!
            if mode != "empty-exclusions" { initial.insetExclusionAddress(ivIndex: 6, address: 0x30) }
            var other: MeshNetwork?
            if mode == "other-site" {
                let uuid = UUID()
                MeshNetwork.stored[uuid.uuidString] = .init(nodes: [], keys: [])
                other = MeshNetwork.load(meshUUID: uuid.uuidString)!
                other!.insetExclusionAddress(ivIndex: 7, address: 0x40)
            }
            let active = mode == "unloaded" ? nil : (other ?? MeshNetwork.load(meshUUID: space.meshUUID)!)
            MeshNetworkManager.instance.meshNetwork = active
            MeshNetworkManager.instance.currentNetworkKey = Key(networkId: .init(hex: mode == "loaded-target" ? space.meshNetworkId : "other-space"))
            if mode == "remove-failure" {
                active!.failRemoval = true
                precondition(!space.delete())
                active!.save()
                active!.failRemoval = false
            }
            if mode == "cleanup-failure" {
                Records.succeeds = false
                precondition(!space.delete())
                active!.save()
                Records.succeeds = true
            }
            precondition(space.delete(), mode)
            active?.save() // Later saves must not overwrite the new protection.
            MeshNetworkManager.instance.meshNetwork = nil
            MeshDataManager.shared.db = nil
            MeshDataManager.shared.db = try Connection(path)
            let reloaded = MeshNetwork.load(meshUUID: space.meshUUID)!
            let addresses = Set(reloaded.networkExclusions?.flatMap(\.addresses) ?? [])
            let expected: Set<Address> = mode == "empty-exclusions" ? [0x10, 0x11] : [0x10, 0x11, 0x30]
            precondition(addresses == expected, "\(mode): deleted Elements and previous exclusions must survive save/reload")
            precondition(reloaded.networkExclusions?.first { $0.ivIndex == 7 }?.addresses.contains(0x11) == true)
            if let other {
                precondition(ExclusionList.load(meshUUID: other.uuid.uuidString).flatMap(\.addresses) == [0x40])
            }
        }
        print("PASS: Space deletion preserves all retired Elements and prior exclusions through loaded/unloaded Mesh, SQLite reopen, later saves and removal/cleanup retries")
    }
}
