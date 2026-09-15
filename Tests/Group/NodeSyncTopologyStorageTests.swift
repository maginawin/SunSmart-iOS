// Included inside SyncTopologyStorageTests by the assembly script. Production
// reader/DTO/policies, SDK Model decoding and SQLite run unchanged. UI services,
// account selection and the already separately tested GroupInfo decoder are scoped fixtures.
enum Permission: Int { case owner = 0, editor = 1, visitor = 2 }
enum UserData { enum Region: Int { case test = 0 }; static let currentServerRegion = Region.test }
final class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: Connection? }
struct SpaceTriggerZone: Codable {
    struct Item: Codable { let groupAddress: UInt16; let deviceAddress: UInt16 }
    var items: [Item]
}
struct GroupInfo {
    struct Profile { enum Kind { case proximityLighting, proximityLightingWithPhotocell }; var type = Kind.proximityLighting; var proximityLightingNumber: UInt8 = 2 }
    struct Path { struct Item { let address: UInt16? }; struct Line { let items: [Item] }; struct Zone { let addresses: [UInt16] }; var paths: [Line] = []; var zones: [Zone] = [] }
    var profile = Profile(), profileLoadFailed = false, topologyLoadFailed = false
    var proximityLightingPath: Path? = nil
    static func load(meshUUID: String, address: UInt16, subnetworkId: String?, database: Connection?, includeTemplates: Bool) -> Self? {
        precondition(!includeTemplates && database != nil)
        return .init()
    }
}

@MainActor static func run() async throws -> String {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("topology-storage-" + UUID().uuidString)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let app = try Connection(root.appendingPathComponent("app.sqlite3").path)
    let mesh = try Connection(root.appendingPathComponent("mesh.sqlite3").path)
    let account = "fixture", meshID = UUID().uuidString
    try app.execute("CREATE TABLE spaces (uuid TEXT, siteUUID TEXT, subNetworkKey TEXT, createTimestamp INTEGER, permission INTEGER, state INTEGER, requiresPasswordVerification INTEGER, triggerZones BLOB)")
    try app.execute("CREATE TABLE sites (uuid TEXT, regionType INTEGER, state INTEGER)")
    try app.execute("CREATE TABLE site_extensions (siteId TEXT, region INTEGER, payload BLOB)")
    try mesh.execute("CREATE TABLE meshNetwork (meshUUID TEXT, netKeys BLOB, appKeys BLOB, provisioners BLOB)")
    try mesh.execute("CREATE TABLE groups (meshUUID TEXT, subnetworkId TEXT, name TEXT, groupAddress INTEGER, isVirtual INTEGER)")
    try mesh.execute("CREATE TABLE nodes (meshUUID TEXT, subnetworkId TEXT, UUID TEXT, configComplete INTEGER, unicastAddress INTEGER, elements BLOB, netKeys BLOB, appKeys BLOB, groupState INTEGER)")
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    let netData = try JSONSerialization.data(withJSONObject: (0..<3).map { index in
        ["name": "Fixture", "index": index, "key": UUID().uuidString.replacingOccurrences(of: "-", with: ""),
         "phase": 0, "minSecurity": "secure", "timestamp": "2026-09-15T00:00:00Z"] as [String: Any]
    })
    let appData = try JSONSerialization.data(withJSONObject: (0..<3).map { index in
        ["name": "Fixture", "index": index, "key": UUID().uuidString.replacingOccurrences(of: "-", with: ""), "boundNetKey": index] as [String: Any]
    })
    let networkKeys = try decoder.decode([NetworkKey].self, from: netData)
    let applicationKeys = try decoder.decode([ApplicationKey].self, from: appData)
    try mesh.run("INSERT INTO meshNetwork VALUES (?,?,?,?)", meshID, Blob(bytes: Array(netData)), Blob(bytes: Array(appData)), Blob(bytes: Array("[]".utf8)))
    let networkA = networkKeys[1].networkId.hex, networkB = networkKeys[2].networkId.hex
    let empty = Blob(bytes: Array("[]".utf8))
    try app.run("INSERT INTO spaces VALUES (?,?,?,?,?,?,?,?)", "A", meshID, networkA, 1, 0, 1, 0, empty)
    try app.run("INSERT INTO spaces VALUES (?,?,?,?,?,?,?,?)", "B", meshID, networkB, 2, 0, 1, 0, empty)
    try app.run("INSERT INTO sites VALUES (?,?,?)", meshID, 0, 1)
    let idA = UUID(), idB = UUID()
    let scope = SpaceProtectionReadRequest.Scope(account: account, region: "fixture", meshUUID: meshID, networkID: networkA)
    let protection = SpaceProtectionReadRequest(scope: scope, root: root.appendingPathComponent("protection"), defaults: UserDefaults(suiteName: UUID().uuidString)!)
    SunSmartDataManager.shared.db = app
    let priorPath = MeshDataManager.customDatabasePath
    MeshDataManager.customDatabasePath = mesh.description
    defer { MeshDataManager.customDatabasePath = priorPath }
    let request = NodeSyncTopologyStorage.Request(protection: protection)
    let keys = NodeSyncTopologyStorage.Request.keys(networkKeys: networkKeys, applicationKeys: applicationKeys, networkID: networkA)
    let input = NodeSyncTopologySnapshot(meshUUID: meshID, networkID: networkA,
        groups: [.init(address: 0xC001, eligible: true, relay: 2, paths: [[1]], zones: [])],
        devices: [.init(id: idA, primaryAddress: 1, address: 1, elementCount: 1, groupAddress: 0xC001, subscriptions: [0xC001], exited: false,
                        evidence: .init(networkKeys: [0,1], applicationKeys: [0,1], vendorBindings: [0,1]))], isAvailable: true, keys: keys)
    func read() async -> NodeSyncPreparedTopology { await Task.detached { request.read(input) }.value }
    func expectLocalOnly(_ reason: String) async {
        let ordinary = NodeSyncTopologySnapshot(meshUUID: meshID, networkID: networkA, groups: [],
            devices: [.init(id: idA, primaryAddress: 1, address: 1, elementCount: 1, groupAddress: nil, subscriptions: [], exited: false,
                            evidence: .init(networkKeys: [1], applicationKeys: [1], vendorBindings: nil))], isAvailable: true, keys: keys)
        for snapshot in [input, ordinary] {
            let result = await Task.detached { request.read(snapshot) }.value
            #if DEBUG
            if !result.isAvailable { FileHandle.standardError.write(Data(("STORAGE FAIL: " + reason + "\n").utf8)) }
            #endif
            precondition(result.isAvailable, reason)
            guard case .localOnly = result.site else { preconditionFailure(reason) }
        }
    }
    func expectAvailable(_ available: Bool, _ reason: String) async {
        let result = await read(); precondition(result.isAvailable == available, reason)
    }
    await expectAvailable(true, "local-only read failed")
    let corruptZones = Blob(bytes: Array("broken".utf8))
    try app.run("UPDATE spaces SET triggerZones=? WHERE uuid='B'", corruptZones)
    await expectLocalOnly("unrelated corrupt Space zones blocked a Site without extension data")
    try app.run("UPDATE spaces SET triggerZones=? WHERE uuid='B'", empty)
    // The request owns paths captured before the global account connection changes.
    SunSmartDataManager.shared.db = try Connection(.inMemory)
    await expectAvailable(true, "reader followed a changed global database")
    SunSmartDataManager.shared.db = app
    try app.run("UPDATE spaces SET triggerZones=? WHERE uuid='A'", Blob(bytes: Array("broken".utf8)))
    await expectAvailable(false, "corrupt Space zones became synchronized")
    try app.run("UPDATE spaces SET triggerZones=? WHERE uuid='A'", empty)
    let model: [String: Any] = ["modelId": String(format: "%08X", UInt32.vensorServerModelId), "subscribe": ["C002"], "bind": [0,2]]
    let elements = try JSONSerialization.data(withJSONObject: [
        ["name": "Primary", "index": 0, "location": "0000", "models": []] as [String: Any],
        ["name": "Vendor", "index": 1, "location": "0000", "models": [model]]
    ])
    let nodeKeys = Blob(bytes: Array("[{\"index\":0,\"updated\":false},{\"index\":2,\"updated\":false}]".utf8))
    try mesh.run("INSERT INTO groups VALUES (?,?,?,?,?)", meshID, networkB, "B", 0xC002, 0)
    try mesh.run("INSERT INTO nodes VALUES (?,?,?,?,?,?,?,?,?)", meshID, networkB, idB.uuidString, 0, 10, Blob(bytes: Array(elements)), nodeKeys, nodeKeys, 1)
    var zone = SiteTriggerZone()
    zone.replaceMembers([
        .init(identity: .init(spaceID: "A", nodeUUID: idA), groupAddress: 0xC001, primaryAddress: 1, deviceAddress: 1),
        .init(identity: .init(spaceID: "B", nodeUUID: idB), groupAddress: 0xC002, primaryAddress: 10, deviceAddress: 11)
    ])
    var state = SiteTriggerZoneState()
    state.data.fields = ["schemaVersion": .integer(2), "triggerZones": .array([.object(zone.fields)])]
    state.serverData = state.data
    try app.run("INSERT INTO site_extensions VALUES (?,?,?)", meshID, 0, Blob(bytes: Array(try JSONEncoder().encode(state))))
    let siteResult = await read()
    precondition(siteResult.isAvailable, "cross-Space input did not prepare")
    guard case .site(let spaceID, let sitePlan) = siteResult.site else { preconditionFailure("Site result was dropped") }
    precondition(spaceID == "A" && sitePlan.targets[.init(spaceID: "A", nodeUUID: idA)]?.neighborAddresses == [11], "cross-Space normalized Vendor address missing")
    func saveState() throws {
        try app.run("UPDATE site_extensions SET payload=?", Blob(bytes: Array(try JSONEncoder().encode(state))))
    }
    let confirmedState = state
    // A Site extension may exist without involving the current Space. Its
    // current and historical membership must be checked before decoding B.
    try app.run("UPDATE spaces SET triggerZones=? WHERE uuid='B'", corruptZones)
    await expectAvailable(false, "corrupt Site dependency became available")
    state.data.fields["triggerZones"] = .array([])
    state.serverData = state.data
    try saveState()
    await expectLocalOnly("unrelated corrupt Space zones blocked an empty Site")
    var unrelatedZone = zone
    unrelatedZone.replaceMembers(zone.members!.filter { $0.identity.spaceID == "B" })
    state.data.fields["triggerZones"] = .array([.object(unrelatedZone.fields)])
    state.serverData = state.data
    try saveState()
    await expectLocalOnly("unrelated corrupt Space zones blocked a nonparticipating Space")
    state.data.fields["triggerZones"] = .array([])
    state.serverData = state.data
    state.deviceSyncChanges = [.init(zoneID: zone.zoneId, previousMembers: unrelatedZone.fields["members"]!, targetMembers: .array([]))]
    try saveState()
    await expectLocalOnly("unrelated historical members caused cross-Space decoding")
    state.deviceSyncChanges = [.init(zoneID: zone.zoneId, previousMembers: zone.fields["members"]!, targetMembers: .array([]))]
    try saveState()
    await expectAvailable(false, "historical Site dependency ignored corrupt Space zones")
    try app.run("UPDATE spaces SET triggerZones=? WHERE uuid='B'", empty)
    state = confirmedState
    state.serverData = nil
    try saveState()
    await expectAvailable(false, "unconfirmed Site data became a local-only target")
    state = confirmedState
    var legacyZone = zone
    if case .array(let members) = zone.fields["members"] {
        legacyZone.fields["members"] = .array(members.map { member in
            guard case .object(var fields) = member else { preconditionFailure() }
            fields["triggerElementAddress"] = fields.removeValue(forKey: "deviceAddress")
            return .object(fields)
        })
    }
    state.data.fields["triggerZones"] = .array([.object(legacyZone.fields)])
    state.serverData = state.data
    try saveState()
    await expectAvailable(true, "valid legacy element addresses were not resolved")
    if case .array(var members) = legacyZone.fields["members"], case .object(var first) = members[0] {
        first["triggerElementAddress"] = .integer(100)
        members[0] = .object(first); legacyZone.fields["members"] = .array(members)
    }
    state.data.fields["triggerZones"] = .array([.object(legacyZone.fields)])
    state.serverData = state.data
    try saveState()
    await expectAvailable(false, "legacy address outside the node was accepted")
    state = confirmedState
    state.data.fields["triggerZones"] = .array([])
    state.serverData = state.data
    state.deviceSyncChanges = [.init(zoneID: zone.zoneId, previousMembers: zone.fields["members"]!, targetMembers: .array([]))]
    try saveState()
    let previousOnly = await read()
    guard case .site = previousOnly.site else { preconditionFailure("previous members lost Site participation") }
    precondition(previousOnly.isAvailable)
    state = confirmedState
    try saveState()
    var changedKeys = try JSONSerialization.jsonObject(with: netData) as! [[String: Any]]
    changedKeys[0]["key"] = UUID().uuidString.replacingOccurrences(of: "-", with: "")
    try mesh.run("UPDATE meshNetwork SET netKeys=?", Blob(bytes: Array(try JSONSerialization.data(withJSONObject: changedKeys))))
    await expectAvailable(false, "different persisted primary key was accepted")
    try mesh.run("UPDATE meshNetwork SET netKeys=?", Blob(bytes: Array(netData)))
    // Input validation remains conservative and never writes to either database.
    let changes = (app.totalChanges, mesh.totalChanges)
    _ = await read()
    precondition(changes == (app.totalChanges, mesh.totalChanges))
    try mesh.run("UPDATE nodes SET elements=?", Blob(bytes: Array("broken".utf8)))
    await expectAvailable(false, "unreadable dependency became empty/local-only")
    try mesh.run("UPDATE nodes SET elements=?", Blob(bytes: Array(elements)))
    let otherScope = SpaceProtectionReadRequest.Scope(account: account, region: "fixture", meshUUID: meshID, networkID: networkB)
    let marker = protection.root.appendingPathComponent(otherScope.storageKey).appendingPathComponent("pending-import.json")
    try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("pending".utf8).write(to: marker)
    await expectAvailable(false, "protected dependency was used")
    return "STORAGE PASS: captured paths, real SQLite/SDK decoding, local-only corruption isolation including non-Vendor nodes, corrupt current/historical dependencies, corrupt Space/remote Mesh, Site merge/confirmation/legacy/previous members/keys, dependency protection, zero writes"
}
