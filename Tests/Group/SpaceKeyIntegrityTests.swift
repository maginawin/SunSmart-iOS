import Foundation
import CryptoKit

typealias KeyIndex = UInt16
extension Data {
    init(testHex value: String) {
        self.init()
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            append(UInt8(value[index..<next], radix: 16)!)
            index = next
        }
    }
    var hex: String { map { String(format: "%02X", $0) }.joined() }
}
enum TestPhase: Int { case normalOperation = 0, keyDistribution = 1 }
final class NetworkKey: Decodable {
    enum CodingKeys: String, CodingKey { case index, key, oldKey, phase }
    let index: KeyIndex, key: Data, oldKey: Data?, phase: TestPhase
    let networkId: Data
    var isPrimary: Bool { index == 0 }
    init(_ index: KeyIndex, _ key: Data, oldKey: Data? = nil, phase: TestPhase = .normalOperation) {
        self.index = index; self.key = key; self.oldKey = oldKey; self.phase = phase
        networkId = Data(SHA256.hash(data: key).prefix(8))
    }
    convenience init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try object.decode(KeyIndex.self, forKey: .index),
                  Data(testHex: try object.decode(String.self, forKey: .key)),
                  oldKey: try object.decodeIfPresent(String.self, forKey: .oldKey).map(Data.init(testHex:)),
                  phase: TestPhase(rawValue: try object.decode(Int.self, forKey: .phase))!)
    }
}
final class ApplicationKey: Decodable {
    enum CodingKeys: String, CodingKey { case index, key, oldKey, boundNetKey }
    let index: KeyIndex, boundNetworkKeyIndex: KeyIndex, key: Data, oldKey: Data?
    init(_ index: KeyIndex, bound: KeyIndex, key: Data, oldKey: Data? = nil) {
        self.index = index; boundNetworkKeyIndex = bound; self.key = key; self.oldKey = oldKey
    }
    convenience init(from decoder: Decoder) throws {
        let object = try decoder.container(keyedBy: CodingKeys.self)
        self.init(try object.decode(KeyIndex.self, forKey: .index),
                  bound: try object.decode(KeyIndex.self, forKey: .boundNetKey),
                  key: Data(testHex: try object.decode(String.self, forKey: .key)),
                  oldKey: try object.decodeIfPresent(String.self, forKey: .oldKey).map(Data.init(testHex:)))
    }
}
final class MeshNetwork {
    static var rows: [String: MeshNetwork] = [:]
    static var failSave = false
    static var corruptReadback = false, corruptNextLoad = false
    let uuid: UUID
    var networkKeys: [NetworkKey], applicationKeys: [ApplicationKey]
    init(_ uuid: UUID, net: [NetworkKey], app: [ApplicationKey]) {
        self.uuid = uuid; networkKeys = net; applicationKeys = app
    }
    func copy() -> MeshNetwork { .init(uuid, net: networkKeys, app: applicationKeys) }
    static func load(meshUUID: String, allData: Bool) -> MeshNetwork? {
        guard let copy = rows[meshUUID]?.copy() else { return nil }
        if corruptNextLoad { corruptNextLoad = false; copy.applicationKeys.removeLast() }
        return copy
    }
    func add(networkKey: NetworkKey) { networkKeys.append(networkKey) }
    func add(applicationKey: ApplicationKey) { applicationKeys.append(applicationKey) }
    func save() -> Bool {
        guard !Self.failSave else { return false }
        Self.rows[uuid.uuidString] = copy()
        if Self.corruptReadback { Self.corruptNextLoad = true }
        return true
    }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
}
struct SpaceData { let meshUUID: String, meshNetworkId: String }
enum SpaceConfigurationIntegrityPolicy {
    static func integer(_ value: Any?) -> Int64? { (value as? NSNumber)?.int64Value }
}

// PRODUCTION_KEY_CONTRACT

@main struct SpaceKeyIntegrityTests {
    @MainActor static func main() {
        let uuid = UUID()
        func net(_ index: KeyIndex, _ byte: UInt8) -> NetworkKey {
            .init(index, Data(repeating: byte, count: 16))
        }
        func app(_ index: KeyIndex, _ byte: UInt8) -> ApplicationKey {
            .init(index, bound: index, key: Data(repeating: byte, count: 16))
        }
        func payload(_ net: NetworkKey, _ app: ApplicationKey) -> [String: Any] {
            ["netKey": ["index": Int(net.index), "key": net.key.hex, "phase": 0],
             "appKey": ["index": Int(app.index), "boundNetKey": Int(app.boundNetworkKeyIndex), "key": app.key.hex],
             "appKeyIndex": Int(app.index)]
        }
        let primary = net(0, 0x11), peer = net(2, 0x22), missing = net(1, 0x33)
        let primaryApp = app(0, 0x44), peerApp = app(2, 0x55), missingApp = app(1, 0x66)
        MeshNetwork.rows[uuid.uuidString] = .init(uuid, net: [primary, peer], app: [primaryApp, peerApp])
        MeshNetworkManager.instance.meshNetwork = MeshNetwork.rows[uuid.uuidString]!.copy()
        let space = SpaceData(meshUUID: uuid.uuidString, meshNetworkId: missing.networkId.hex)
        let remote = SpaceKeyIntegrity.pair(payload(missing, missingApp), networkID: space.meshNetworkId)!
        precondition(SpaceKeyIntegrity.replenish(space, from: remote))
        let saved = MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!
        precondition(saved.networkKeys.count == 3 && saved.applicationKeys.count == 3)
        precondition(saved.networkKeys.contains { $0.index == peer.index && $0.key == peer.key })
        precondition(MeshNetworkManager.instance.meshNetwork!.networkKeys.count == 3)
        precondition(SpaceKeyIntegrity.replenish(space, from: remote), "repeated GET must be idempotent")
        precondition(MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!.networkKeys.count == 3)

        // A second Space has its NetKey but lacks the bound AppKey.
        let onlyApp = app(3, 0x77), third = net(3, 0x88)
        MeshNetwork.rows[uuid.uuidString]!.networkKeys.append(third)
        MeshNetworkManager.instance.meshNetwork!.networkKeys.append(third)
        let second = SpaceData(meshUUID: uuid.uuidString, meshNetworkId: third.networkId.hex)
        let secondRemote = SpaceKeyIntegrity.pair(payload(third, onlyApp), networkID: second.meshNetworkId)!
        precondition(SpaceKeyIntegrity.replenish(second, from: secondRemote))
        precondition(MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!.applicationKeys.count == 4)
        let staleSite = MeshNetwork(uuid, net: [primary, peer], app: [primaryApp, peerApp])
        precondition(SpaceKeyIntegrity.saveSiteNetworkPreservingKeys(staleSite, meshUUID: uuid.uuidString))
        precondition(MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!.networkKeys.count == 4)
        precondition(MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!.applicationKeys.count == 4)
        let conflictingSite = MeshNetwork(uuid, net: [primary, net(2, 0x99)], app: [primaryApp])
        precondition(!SpaceKeyIntegrity.saveSiteNetworkPreservingKeys(conflictingSite, meshUUID: uuid.uuidString))

        let conflict = net(1, 0x99)
        let conflictingPair = SpaceKeyIntegrity.pair(payload(conflict, missingApp), networkID: conflict.networkId.hex)!
        let conflictingSpace = SpaceData(meshUUID: uuid.uuidString, meshNetworkId: conflict.networkId.hex)
        precondition(!SpaceKeyIntegrity.replenish(conflictingSpace, from: conflictingPair))
        precondition(MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!.networkKeys.count == 4)

        let saveFailure = net(4, 0xAA), saveFailureApp = app(4, 0xBB)
        let failedSpace = SpaceData(meshUUID: uuid.uuidString, meshNetworkId: saveFailure.networkId.hex)
        let failedPair = SpaceKeyIntegrity.pair(payload(saveFailure, saveFailureApp), networkID: failedSpace.meshNetworkId)!
        MeshNetwork.failSave = true
        precondition(!SpaceKeyIntegrity.replenish(failedSpace, from: failedPair))
        MeshNetwork.failSave = false
        precondition(MeshNetwork.load(meshUUID: uuid.uuidString, allData: false)!.networkKeys.count == 4)
        MeshNetwork.corruptReadback = true
        let unreadable = net(5, 0xAB), unreadableApp = app(5, 0xBC)
        let unreadableSpace = SpaceData(meshUUID: uuid.uuidString, meshNetworkId: unreadable.networkId.hex)
        let unreadablePair = SpaceKeyIntegrity.pair(payload(unreadable, unreadableApp), networkID: unreadableSpace.meshNetworkId)!
        precondition(!SpaceKeyIntegrity.replenish(unreadableSpace, from: unreadablePair))
        MeshNetwork.corruptReadback = false

        var invalid = payload(missing, missingApp)
        invalid["appKeyIndex"] = 7
        precondition(SpaceKeyIntegrity.pair(invalid, networkID: space.meshNetworkId) == nil)
        invalid = payload(missing, missingApp)
        invalid["netKey"] = ["index": 1, "key": "XX", "phase": 0]
        precondition(SpaceKeyIntegrity.pair(invalid, networkID: space.meshNetworkId) == nil)
        invalid = payload(missing, missingApp)
        var nullable = invalid["netKey"] as! [String: Any]
        nullable["oldKey"] = NSNull()
        invalid["netKey"] = nullable
        precondition(SpaceKeyIntegrity.pair(invalid, networkID: space.meshNetworkId) != nil)
        invalid = payload(missing, app(1, 0xAA))
        precondition(SpaceKeyIntegrity.pair(invalid, networkID: space.meshNetworkId)!.fingerprint != remote.fingerprint)
        precondition(SpaceKeyIntegrity.pair(payload(missing, missingApp), networkID: peer.networkId.hex) == nil)
        let local = SpaceKeyIntegrity.pair(saved, networkID: space.meshNetworkId,
                                           applicationIndex: missingApp.index)!
        var serverMissingNet = payload(missing, missingApp)
        serverMissingNet.removeValue(forKey: "netKey")
        precondition(SpaceKeyIntegrity.presentServerKeysMatchLocal(serverMissingNet, local: local))
        var serverMissingApp = payload(missing, missingApp)
        serverMissingApp.removeValue(forKey: "appKey")
        precondition(SpaceKeyIntegrity.presentServerKeysMatchLocal(serverMissingApp, local: local))
        serverMissingApp.removeValue(forKey: "netKey")
        precondition(!SpaceKeyIntegrity.presentServerKeysMatchLocal(serverMissingApp, local: local))
        serverMissingNet["appKey"] = ["index": 1, "boundNetKey": 1, "key": app(1, 0xAA).key.hex]
        precondition(!SpaceKeyIntegrity.presentServerKeysMatchLocal(serverMissingNet, local: local))
        print("PASS: production Key contract, two Space merge, Site stale snapshot, active network, conflicts, save failure and invalid identity")
    }
}
