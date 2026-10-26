import Foundation

// The script supplies the existing Mesh doubles and the production key contract.
// Site.update/address allocation is a boundary; the production import wrapper
// decides initialization, checks identities and verifies preserved keys here.
enum Permission { case owner, editor, visitor }
enum UserData { static let currentServerRegion = 0 }
enum SpaceMembershipCoordinator {
    static var accepted = true
    static func accepts(_ payload: [String: Any]) -> Bool { accepted }
}
final class SiteData {
    enum State { case normal, waitDeleted }
    enum SiteType: Int { case office = 1 }
    enum Source { case create }
    static var stored: SiteData?
    static var updates: [(initialize: Bool, changeAddress: Bool)] = []
    static var updateSucceeds = true, saveSucceeds = true
    static var duringUpdate: () -> Void = {}
    let id: String, meshUUID: String, meshNetworkId: String
    var state = State.normal
    init(region: Int, id: String, meshUUID: String, meshNetworkId: String, name: String,
         type: SiteType, permission: Permission, create: Int64, lastUpdate: Int64,
         isFavourite: Bool, sourceType: Source) {
        self.id = id; self.meshUUID = meshUUID; self.meshNetworkId = meshNetworkId
    }
    static func load(siteId: String) -> SiteData? { stored?.id == siteId ? stored : nil }
    func update(siteJsonData: [String: Any], changeAddress: Bool, initialize: Bool) async -> Bool {
        Self.updates.append((initialize, changeAddress))
        Self.duringUpdate()
        if Self.updateSucceeds { Self.stored = self }
        return Self.updateSucceeds
    }
    func save() -> Bool { Self.saveSucceeds }
}

// PRODUCTION_SITE_IMPORT

@main struct SiteTransferImportTests {
    static func main() async {
        let uuid = UUID()
        let net = NetworkKey(0, Data(repeating: 0x11, count: 16))
        let app = ApplicationKey(0, bound: 0, key: Data(repeating: 0x22, count: 16))
        let childNet = NetworkKey(1, Data(repeating: 0x33, count: 16))
        let childApp = ApplicationKey(1, bound: 1, key: Data(repeating: 0x44, count: 16))
        let payload: [String: Any] = ["uuid": uuid.uuidString, "siteName": "Returning site",
            "updateTimestamp": 1, "createTimestamp": 1,
            "netKey": ["index": 0, "key": net.key.hex, "phase": 0],
            "appKey": ["index": 0, "boundNetKey": 0, "key": app.key.hex]]
        func reset(_ state: SiteData.State = .normal) {
            SiteData.stored = SiteData(region: 0, id: uuid.uuidString, meshUUID: uuid.uuidString,
                meshNetworkId: net.networkId.hex, name: "Returning site", type: .office,
                permission: .owner, create: 1, lastUpdate: 1, isFavourite: false, sourceType: .create)
            SiteData.stored!.state = state
            SiteData.updates = []; SiteData.updateSucceeds = true; SiteData.saveSucceeds = true
            SiteData.duringUpdate = {}; SpaceMembershipCoordinator.accepted = true
            MeshNetwork.rows[uuid.uuidString] = .init(uuid, net: [net, childNet], app: [app, childApp])
            MeshNetworkManager.instance.meshNetwork = MeshNetwork.rows[uuid.uuidString]!.copy()
        }
        reset()
        var result = await SiteData.import(siteJsonData: payload, changeAddress: true, receivingOwnership: true)
        precondition(result != nil && SiteData.updates.count == 1)
        precondition(SiteData.updates[0].initialize && SiteData.updates[0].changeAddress,
                     "Receipt must initialize a stale normal Site even when timestamps are equal")
        precondition(MeshNetwork.rows[uuid.uuidString]!.networkKeys.count == 2)
        reset()
        result = await SiteData.import(siteJsonData: payload)
        precondition(result != nil && !SiteData.updates[0].initialize && !SiteData.updates[0].changeAddress,
                     "Ordinary refresh must not reallocate addresses")
        reset(.waitDeleted)
        result = await SiteData.import(siteJsonData: payload)
        precondition(result?.state == .normal && SiteData.updates[0].initialize && SiteData.updates[0].changeAddress)
        reset()
        var mismatch = payload
        mismatch["netKey"] = ["index": 0, "key": Data(repeating: 0x55, count: 16).hex, "phase": 0]
        result = await SiteData.import(siteJsonData: mismatch, receivingOwnership: true)
        precondition(result == nil && SiteData.updates.isEmpty, "A receipt must not replace the original network identity")
        reset()
        MeshNetworkManager.instance.meshNetwork!.applicationKeys.removeLast()
        result = await SiteData.import(siteJsonData: payload, receivingOwnership: true)
        precondition(result == nil && SiteData.updates.isEmpty, "Missing active Space keys must fail before update")
        reset()
        SiteData.duringUpdate = { MeshNetwork.rows[uuid.uuidString]!.applicationKeys.removeLast() }
        result = await SiteData.import(siteJsonData: payload, receivingOwnership: true)
        precondition(result == nil, "Readback must detect a lost Space key")
        reset()
        SiteData.updateSucceeds = false
        result = await SiteData.import(siteJsonData: payload, receivingOwnership: true)
        precondition(result == nil)
        reset()
        SiteData.saveSucceeds = false
        result = await SiteData.import(siteJsonData: payload, receivingOwnership: true)
        precondition(result == nil)
        reset()
        SiteData.duringUpdate = { SpaceMembershipCoordinator.accepted = false }
        result = await SiteData.import(siteJsonData: payload, receivingOwnership: true)
        precondition(result == nil, "A revoked response must not complete import")
        reset()
        SiteData.stored = nil
        result = await SiteData.import(siteJsonData: payload, changeAddress: true, receivingOwnership: true)
        precondition(result != nil && SiteData.updates[0].initialize && SiteData.updates[0].changeAddress)
        print("PASS: production Site receipt initialization, unchanged refresh, identity/key preservation, failure and stale context")
    }
}
