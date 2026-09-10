import Foundation

// The test boundary models SDK serialization and a detached persisted network.
// Network ID derivation is deliberately outside this harness; the app build uses
// SDK NetworkKey and the forensic probe separately verified the actual IDs.
struct TestNetworkID { let hex: String }
struct NetworkKey: Codable {
    let index: UInt16
    let key: String
    var phase = 0
    var networkId: TestNetworkID { .init(hex: key) }
}
struct ApplicationKey: Codable {
    let index: UInt16
    let key: String
    let boundNetKey: UInt16
    var boundNetworkKeyIndex: UInt16 { boundNetKey }
}
final class MeshNetwork {
    static var database: [UUID: MeshNetwork] = [:]
    static var failSave = false
    static var saves = 0
    static var loads = 0
    static var beforeLoad: (() -> Void)?
    let uuid: UUID
    var networkKeys: [NetworkKey]
    var applicationKeys: [ApplicationKey]
    init(id: UUID = UUID(), networks: [NetworkKey], applications: [ApplicationKey]) {
        uuid = id; networkKeys = networks; applicationKeys = applications
    }
    func detached() -> MeshNetwork { .init(id: uuid, networks: networkKeys, applications: applicationKeys) }
    static func load(meshUUID: String, allData: Bool = true) -> MeshNetwork? {
        loads += 1
        beforeLoad?()
        return UUID(uuidString: meshUUID).flatMap { database[$0]?.detached() }
    }
    func add(networkKey: NetworkKey) { networkKeys.append(networkKey) }
    func add(applicationKey: ApplicationKey) { applicationKeys.append(applicationKey) }
    func save() -> Bool {
        Self.saves += 1
        guard !Self.failSave else { return false }
        Self.database[uuid] = detached()
        return true
    }
}

struct TestSpace {
    enum Purpose { case cloudSync }
    let id: String
    let network: MeshNetwork
    let networkId: String
    func export(purpose: Purpose) async -> [String: Any]? {
        guard case .success(var payload) = SpaceMeshKeyStore.export(network: network, networkId: networkId) else { return nil }
        payload["uuid"] = id
        return payload
    }
}
struct TestSite { let spaces: [TestSpace] }

@main struct SpaceMeshKeyStoreTests {
    static func object<T: Encodable>(_ value: T) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(value)) as! [String: Any]
    }
    static func main() async throws {
        typealias S = SpaceMeshKeyStore
        let net = NetworkKey(index: 1, key: String(repeating: "11", count: 16))
        let app = ApplicationKey(index: 1, key: String(repeating: "22", count: 16), boundNetKey: 1)
        let payload: [String: Any] = ["netKey": try object(net), "appKey": try object(app)]
        let existing = MeshNetwork(networks: [net], applications: [])
        MeshNetwork.database[existing.uuid] = existing.detached()
        if case .failure(.missingAppKey) = S.export(network: existing, networkId: net.networkId.hex) {} else { fatalError("missing AppKey must fail export") }
        precondition(S.reconcile(payload, network: existing, networkId: net.networkId.hex) == nil)
        let exported = try S.export(network: existing, networkId: net.networkId.hex).get()
        precondition(SpaceMeshKeyPolicy.fingerprint(exported) == SpaceMeshKeyPolicy.fingerprint(payload))
        precondition(MeshNetwork.database[existing.uuid]!.applicationKeys.count == 1)
        let saves = MeshNetwork.saves
        precondition(S.reconcile(payload, network: existing, networkId: net.networkId.hex) == nil)
        precondition(MeshNetwork.saves == saves, "idempotent validation must not save")

        let other = NetworkKey(index: 1, key: String(repeating: "33", count: 16))
        let collision = MeshNetwork(networks: [other], applications: [app])
        MeshNetwork.database[collision.uuid] = collision.detached()
        precondition(S.reconcile(payload, network: collision, networkId: net.networkId.hex) == .netKeyIndexConflict)
        precondition(collision.networkKeys[0].key == other.key && MeshNetwork.saves == saves)
        if case .failure(.missingNetKey) = S.export(network: collision, networkId: net.networkId.hex) {} else { fatalError("do not select another Space's same-index key") }

        let fresh = MeshNetwork(networks: [], applications: [])
        MeshNetwork.database[fresh.uuid] = fresh.detached()
        // A collision appearing after the caller loaded must also be rejected.
        MeshNetwork.database[fresh.uuid]!.networkKeys = [other]
        precondition(S.reconcile(payload, network: fresh, networkId: net.networkId.hex) == .netKeyIndexConflict)
        precondition(fresh.networkKeys.isEmpty && MeshNetwork.saves == saves)
        // Even a nonconflicting peer must not be lost by a later caller save.
        let peer = NetworkKey(index: 3, key: String(repeating: "44", count: 16))
        let stale = MeshNetwork(networks: [], applications: [])
        MeshNetwork.database[stale.uuid] = MeshNetwork(id: stale.uuid, networks: [peer], applications: [])
        precondition(S.reconcile(payload, network: stale, networkId: net.networkId.hex) == nil)
        precondition(stale.networkKeys.count == 2 && stale.applicationKeys.count == 1)
        precondition(stale.save(), "a later caller save must retain the peer key")
        precondition(MeshNetwork.database[stale.uuid]!.networkKeys.first { $0.index == peer.index }?.key == peer.key)
        MeshNetwork.database[fresh.uuid]!.networkKeys = []
        MeshNetwork.failSave = true
        precondition(S.reconcile(payload, network: fresh, networkId: net.networkId.hex) == .persistenceFailed)
        precondition(fresh.networkKeys.isEmpty && MeshNetwork.database[fresh.uuid]!.networkKeys.isEmpty)
        MeshNetwork.failSave = false
        precondition(S.reconcile(payload, network: fresh, networkId: net.networkId.hex) == nil)
        precondition(fresh.networkKeys.count == 1 && fresh.applicationKeys.count == 1)
        precondition(S.preflight(payload, network: fresh, networkId: "wrong") == .networkIdentityMismatch)
        let peerApp = ApplicationKey(index: 3, key: String(repeating: "55", count: 16), boundNetKey: 3)
        // Active A predates a detached import of B into the same Site. The same
        // active object must recover and remain idempotent without a reload.
        let activeA = existing.detached()
        let importB = existing.detached()
        let peerPayload: [String: Any] = ["netKey": try object(peer), "appKey": try object(peerApp)]
        precondition(S.reconcile(peerPayload, network: importB, networkId: peer.networkId.hex) == nil)
        let beforeRefresh = MeshNetwork.saves
        for _ in 0..<3 { precondition(S.reconcile(payload, network: activeA, networkId: net.networkId.hex) == nil) }
        precondition(MeshNetwork.saves == beforeRefresh, "cache refresh must not persist stale caller metadata")
        precondition(activeA.networkKeys.count == 2 && activeA.applicationKeys.count == 2)
        precondition(activeA.save())
        let peerExport = try S.export(network: MeshNetwork.database[existing.uuid]!, networkId: peer.networkId.hex).get()
        precondition(peerExport.count == 3)

        // Existing material removed or refreshed is not an additive cache miss.
        let changedInventory = activeA.detached()
        MeshNetwork.database[changedInventory.uuid]!.networkKeys.removeAll { $0.index == peer.index }
        precondition(S.reconcile(payload, network: changedInventory, networkId: net.networkId.hex) == .keyRefreshNeedsReview)
        precondition(changedInventory.networkKeys.count == 2)
        MeshNetwork.database[changedInventory.uuid] = activeA.detached()

        let racing = MeshNetwork(networks: [net], applications: [app])
        MeshNetwork.database[racing.uuid] = MeshNetwork(id: racing.uuid, networks: [net, peer], applications: [app, peerApp])
        MeshNetwork.loads = 0
        MeshNetwork.beforeLoad = {
            if MeshNetwork.loads == 3 {
                MeshNetwork.database[racing.uuid]!.networkKeys.append(NetworkKey(index: 4, key: String(repeating: "66", count: 16)))
            }
        }
        let beforeRace = MeshNetwork.saves
        precondition(S.reconcile(payload, network: racing, networkId: net.networkId.hex) == .staleSnapshot)
        precondition(MeshNetwork.loads == 3 && MeshNetwork.saves == beforeRace, "only one refresh/retry is allowed")
        MeshNetwork.beforeLoad = nil
        precondition(S.reconcile(payload, network: racing, networkId: net.networkId.hex) == nil)

        let withPeer = MeshNetwork(networks: [peer], applications: [peerApp])
        MeshNetwork.database[withPeer.uuid] = withPeer.detached()
        precondition(S.reconcile(payload, network: withPeer, networkId: net.networkId.hex) == nil)
        let preservedPeer = MeshNetwork.database[withPeer.uuid]!
        precondition(preservedPeer.networkKeys.count == 2 && preservedPeer.applicationKeys.count == 2)
        precondition(preservedPeer.networkKeys.first { $0.index == 3 }?.key == peer.key)
        precondition(preservedPeer.applicationKeys.first { $0.index == 3 }?.key == peerApp.key)
        // The same index with different material in another Site is independent.
        let otherSitePayload: [String: Any] = ["netKey": try object(other), "appKey": try object(app)]
        precondition(S.reconcile(otherSitePayload, network: collision, networkId: other.networkId.hex) == nil)
        precondition(MeshNetwork.database[existing.uuid]!.networkKeys[0].key == net.key)
        let validSpace = TestSpace(id: "valid", network: existing, networkId: net.networkId.hex)
        let invalidSpace = TestSpace(id: "invalid", network: collision, networkId: net.networkId.hex)
        let site = TestSite(spaces: [validSpace, invalidSpace])
        let rejected = await site.export(spaceIds: ["valid", "invalid"])
        precondition(rejected == nil, "production Site aggregation must not drop the invalid Space and submit partial state")
        let validSite = await site.export(spaceIds: ["valid"])
        let nested = validSite?["spaces"] as? [[String: Any]]
        precondition(nested?.count == 1 && SpaceMeshKeyPolicy.issue(in: nested![0]) == nil)
        let metadataOnly = await site.export(spaceIds: [])
        precondition((metadataOnly?["spaces"] as? [[String: Any]])?.isEmpty == true)
        print("PASS: production export rejects missing keys; repair persists, rechecks collisions, preserves peers and handles save failure")
        print("PASS: production Site aggregation rejects a partial upload and preserves metadata-only sync")
    }
}
