import Foundation
import SQLite

@main struct DebugCloudJSONRecordsTests {
    static func main() throws {
        let app = try Connection(.inMemory), mesh = try Connection(.inMemory)
        try app.run("CREATE TABLE spaces (uuid TEXT, siteUUID TEXT, triggerZones BLOB, authorizationPassword TEXT, editorPassword TEXT, lastUpdateTimestamp INTEGER)")
        let invalid = Data("{broken triggerZones".utf8)
        try app.run("INSERT INTO spaces VALUES (?, ?, ?, ?, ?, ?)", "space-a", "site", Blob(bytes: Array(invalid)), "auth-secret", "editor-secret", Int64(9007199254740991))
        try app.run("INSERT INTO spaces VALUES ('space-b', 'site', NULL, NULL, NULL, 1)")
        try app.run("CREATE TABLE groupInfos (meshUUID TEXT, subNetworkKey TEXT, groupAddress INTEGER, profileId TEXT, proximityLightingPath BLOB)")
        let topology = Data("{\"paths\":[{\"items\":[999,999]}],\"zones\":[]}".utf8)
        try app.run("INSERT INTO groupInfos VALUES (?, ?, ?, ?, ?)", "mesh", "network-a", 49153, "legacy", Blob(bytes: Array(topology)))
        try app.run("INSERT INTO groupInfos VALUES ('mesh', 'network-b', 49154, 'other', NULL)")
        try app.run("CREATE TABLE profiles (meshUUID TEXT, subNetworkKey TEXT, uuid TEXT, type INTEGER)")
        try app.run("INSERT INTO profiles VALUES ('mesh', NULL, 'legacy', 999), ('mesh', 'network-a', 'owned', 3), ('mesh', NULL, 'unrelated', 2), ('mesh', 'network-b', 'other', 4)")
        try app.run("CREATE TABLE profileLightSensorTemplate (profileId TEXT, name TEXT)")
        try app.run("INSERT INTO profileLightSensorTemplate VALUES ('legacy', 'kept'), ('other', 'excluded')")
        try app.run("CREATE TABLE node_preConfiguration (meshUUID TEXT, nodeAddress INTEGER, upRatio INTEGER)")
        try app.run("INSERT INTO node_preConfiguration VALUES ('mesh', 12, 10), ('mesh', 13, 20), ('another', 12, 30)")
        try mesh.run("CREATE TABLE nodes (meshUUID TEXT, subnetworkId TEXT, unicastAddress INTEGER, data BLOB)")
        try mesh.run("INSERT INTO nodes VALUES (?, ?, ?, ?)", "mesh", "network-a", 12, Blob(bytes: [0, 255, 128]))
        try mesh.run("INSERT INTO nodes VALUES ('mesh', 'network-b', 13, NULL), ('another', 'network-a', 14, NULL)")
        let appChanges = app.totalChanges, meshChanges = mesh.totalChanges
        let scope = DebugCloudJSONRecords.Scope(siteID: "site", spaceID: "space-a", meshUUID: "mesh", networkID: "network-a")
        let raw = try DebugCloudJSONRecords.read(app: app, mesh: mesh, scope: scope)
        let appRecords = raw["app"] as! [String: Any], meshRecords = raw["mesh"] as! [String: Any]
        let space = (appRecords["spaces"] as! [[String: Any]]).only
        precondition(space["authorizationPassword"] == nil && space["editorPassword"] == nil)
        precondition(space["lastUpdateTimestamp"] as? Int64 == 9007199254740991)
        let blob = space["triggerZones"] as! [String: Any]
        precondition(Data(base64Encoded: blob["base64"] as! String) == invalid)
        precondition(blob["json"] == nil && blob["utf8"] as? String == String(data: invalid, encoding: .utf8))
        let group = (appRecords["groupInfos"] as! [[String: Any]]).only
        let path = group["proximityLightingPath"] as! [String: Any]
        precondition(Data(base64Encoded: path["base64"] as! String) == topology)
        precondition((path["json"] as? [String: Any])?["paths"] != nil)
        let profiles = appRecords["profiles"] as! [[String: Any]]
        precondition(Set(profiles.compactMap { $0["uuid"] as? String }) == ["legacy", "owned"])
        precondition((appRecords["profileLightSensorTemplate"] as! [[String: Any]]).only["name"] as? String == "kept")
        precondition((appRecords["node_preConfiguration"] as! [[String: Any]]).only["nodeAddress"] as? Int64 == 12)
        let node = (meshRecords["nodes"] as! [[String: Any]]).only
        precondition(Data(base64Encoded: (node["data"] as! [String: Any])["base64"] as! String) == Data([0, 255, 128]))
        precondition(app.totalChanges == appChanges && mesh.totalChanges == meshChanges)
        let encoded = try JSONSerialization.data(withJSONObject: raw)
        precondition(!(String(data: encoded, encoding: .utf8)!.contains("secret")))
        try app.run("CREATE TABLE schedules (wrongColumn TEXT)")
        do {
            _ = try DebugCloudJSONRecords.read(app: app, mesh: mesh, scope: scope)
            preconditionFailure("A read error was presented as an empty collection")
        } catch {}
        print("PASS: raw invalid JSON/binary preservation, scoped joins, legacy profiles, no Auth, no database writes, read failures")
        try testSiteGatewayInspection()
    }

    private static func testSiteGatewayInspection() throws {
        let app = try Connection(.inMemory), mesh = try Connection(.inMemory)
        try app.run("CREATE TABLE sites (uuid TEXT, regionType INTEGER, name TEXT)")
        try app.run("INSERT INTO sites VALUES ('site', 1, 'selected'), ('site', 2, 'other region'), ('other', 1, 'other site')")
        try app.run("CREATE TABLE gateways (siteUUID TEXT, name TEXT, macAddress TEXT, address INTEGER, lastUploadCloudTimestamp INTEGER, serverDeletionPendingLocalReset INTEGER, associatedSpaces BLOB, mqttServerInfo BLOB, registrationProtectionSnapshot BLOB)")
        let invalidAssociation = Data("{broken association".utf8)
        let credential = Blob(bytes: Array("secret fixture".utf8))
        try app.run("INSERT INTO gateways VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                    "site", "orphan", "AA0000000001", 11, nil, 1,
                    Blob(bytes: Array(invalidAssociation)), credential, credential)
        try app.run("INSERT INTO gateways VALUES ('site', 'active', 'AA0000000002', 12, 123, 0, NULL, NULL, NULL), ('other', 'excluded', 'AA0000000003', 13, 123, 0, NULL, NULL, NULL)")
        try mesh.run("CREATE TABLE nodes (meshUUID TEXT, subnetworkId TEXT, unicastAddress INTEGER, UUID TEXT, deviceKey TEXT)")
        try mesh.run("INSERT INTO nodes VALUES ('mesh', 'primary', 12, 'gateway-node', 'secret fixture'), ('mesh', 'space-network', 13, 'space-node', NULL), ('other', 'primary', 14, 'other-node', NULL)")
        try mesh.run("CREATE TABLE nodePropertys (meshUUID TEXT, subnetworkId TEXT, unicastAddress INTEGER, timezoneOffset INTEGER, timestamp INTEGER, gatewayInfo BLOB, enOceanProxySwitchKeys BLOB)")
        try mesh.run("INSERT INTO nodePropertys VALUES (?, ?, ?, ?, ?, ?, ?)",
                     "mesh", "primary", 12, 96, 456, credential, credential)
        try mesh.run("INSERT INTO nodePropertys VALUES ('mesh', 'primary', 11, NULL, NULL, NULL, NULL), ('mesh', 'space-network', 13, 64, 1, NULL, NULL), ('other', 'primary', 14, 64, 1, NULL, NULL)")
        let appChanges = app.totalChanges, meshChanges = mesh.totalChanges
        let raw = try DebugCloudJSONRecords.readSite(app: app, mesh: mesh, siteID: "site", region: 1,
                                                    meshUUID: "mesh", networkID: "primary")
        precondition((raw["sites"] as! [[String: Any]]).only["name"] as? String == "selected")
        let gateways = raw["gateways"] as! [[String: Any]]
        precondition(gateways.count == 2)
        let orphan = gateways.first { $0["address"] as? Int64 == 11 }!
        precondition(orphan["lastUploadCloudTimestamp"] is NSNull)
        precondition(orphan["serverDeletionPendingLocalReset"] as? Int64 == 1)
        let association = orphan["associatedSpaces"] as! [String: Any]
        precondition(Data(base64Encoded: association["base64"] as! String) == invalidAssociation)
        let primary = raw["primaryMesh"] as! [String: Any]
        precondition(primary["meshUUID"] as? String == "mesh" && primary["networkId"] as? String == "primary")
        let node = (primary["nodes"] as! [[String: Any]]).only
        precondition(node["UUID"] as? String == "gateway-node" && node["deviceKey"] == nil)
        let properties = primary["nodePropertys"] as! [[String: Any]]
        precondition(properties.count == 2, "Orphan properties must not be lost through a Node join")
        let active = properties.first { $0["unicastAddress"] as? Int64 == 12 }!
        precondition(active["timezoneOffset"] as? Int64 == 96 && active["timestamp"] as? Int64 == 456)
        precondition(gateways.allSatisfy { $0["mqttServerInfo"] == nil && $0["registrationProtectionSnapshot"] == nil })
        precondition(properties.allSatisfy { $0["gatewayInfo"] == nil && $0["enOceanProxySwitchKeys"] == nil })
        precondition(raw["omittedColumns"] != nil)
        let encoded = try JSONSerialization.data(withJSONObject: raw)
        let text = String(data: encoded, encoding: .utf8)!
        precondition(!text.contains("secret fixture") && !text.contains(Data("secret fixture".utf8).base64EncodedString()))
        precondition(app.totalChanges == appChanges && mesh.totalChanges == meshChanges)

        let empty = try DebugCloudJSONRecords.readSite(app: Connection(.inMemory), mesh: Connection(.inMemory),
            siteID: "site", region: 1, meshUUID: "mesh", networkID: "primary")
        precondition((empty["gateways"] as! [Any]).isEmpty)
        precondition(((empty["primaryMesh"] as! [String: Any])["nodes"] as! [Any]).isEmpty)
        try app.run("ALTER TABLE gateways RENAME COLUMN siteUUID TO invalidScope")
        do {
            _ = try DebugCloudJSONRecords.readSite(app: app, mesh: mesh, siteID: "site", region: 1,
                                                  meshUUID: "mesh", networkID: "primary")
            preconditionFailure("A gateway read error was presented as an empty collection")
        } catch {}
        print("PASS: Site gateway orphans/pending deletion, primary-network scope, stored timezone, credential exclusion, no writes, legacy tables and read failures")
    }
}

private extension Array {
    var only: Element { precondition(count == 1); return self[0] }
}
