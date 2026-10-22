import Foundation
import SQLite3

@main enum HDBPersistenceTests {
    static func main() throws {
        let id = UUID()
        var device = HDBDeviceConfiguration(nodeUuid: id, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 1)])
        let models = [UInt16(0x1000), 0x1300, 0x130F, 0x1310].map { HDBModelTarget(elementAddress: 1, modelIdentifier: $0, companyIdentifier: nil) }
            + [HDBModelTarget(elementAddress: 1, modelIdentifier: 1, companyIdentifier: 0x0A78)]
        device.zoneModels = HDBLightingZonePolicy.zoneTargets(from: models, primaryAddress: 1).map(HDBModelReference.init)
        device.sensorGroupModels = HDBLightingZonePolicy.sensorGroupTargets(from: models).map(HDBModelReference.init)
        let config = HDBConfiguration(lightingZones: [.init(zoneId: 1, name: "One", groupAddress: 0xC000)], devices: [device])
        let cleared = try HDBLightingZonePolicy.configurationForSave(current: config, baseline: config, persisted: nil, rowExists: true)
        precondition(cleared == nil)
        do { _ = try HDBLightingZonePolicy.configurationForSave(current: nil, baseline: config, persisted: HDBConfiguration(), rowExists: true); fatalError("stale conflicting clear accepted") } catch {}
        try sqliteRoundTrip(config, path: CommandLine.arguments[1])
        let object = try HDBLightingZonePolicy.json(config)
        let payload: [String: Any] = ["groups": [["address": "C000", "isVirtual": false]], "nodes": [["uuid": id.uuidString, "unicastAddress": "0001", "elements": [["index": 0, "models": models.map { ["modelId": String(format: $0.companyIdentifier == nil ? "%04X" : "%08X", $0.modelId)] }]]]], "spaceData": ["hdb": object]]
        let decoded = try HDBLightingZonePolicy.decode(payload: payload)
        precondition(decoded == config)
        try HDBLightingZonePolicy.validateReferences(config, payload: payload)
        var sensorConfig = config
        sensorConfig.devices[0].sensorGroupId = 0xC040
        var sensorPayload = payload
        sensorPayload["groups"] = [["address": "C000", "isVirtual": false], ["address": "C040", "isVirtual": true]]
        try HDBLightingZonePolicy.validateReferences(sensorConfig, payload: sensorPayload)
        sensorPayload["groups"] = [["address": "C000", "isVirtual": false], ["address": "C040", "isVirtual": false]]
        do { try HDBLightingZonePolicy.validateReferences(sensorConfig, payload: sensorPayload); fatalError("sensor address must reference a functional Group") } catch HDBConfigurationError.invalidData {}
        let addresses = try HDBLightingZonePolicy.groupAddresses(in: payload)
        precondition(addresses == [0xC000])
        let empty = try HDBLightingZonePolicy.decode(payload: [:])
        precondition(empty == nil)
        var malformed = object
        var devices = malformed["devices"] as! [[String: Any]]
        devices[0].removeValue(forKey: "lightingZonesStatus")
        malformed["devices"] = devices
        do { _ = try HDBLightingZonePolicy.decode(payload: ["spaceData": ["hdb": malformed]]); fatalError("lost status accepted") } catch {}
        var badIdentity = payload
        badIdentity["nodes"] = [["uuid": UUID().uuidString, "unicastAddress": "0001"]]
        do { try HDBLightingZonePolicy.validateReferences(config, payload: badIdentity); fatalError("address reuse accepted") } catch {}
        let receiptPayload: [String: Any] = ["groups": [[String: Any]](), "nodes": [[String: Any]](), "spaceData": ["hdb": object]]
        let absent: [String: Any] = ["groups": [[String: Any]](), "nodes": [[String: Any]]()]
        let receipt = SpaceConfigurationIntegrityPolicy.configurationData(receiptPayload)
        precondition(receipt != nil && receipt != SpaceConfigurationIntegrityPolicy.configurationData(absent))
        let reloaded = try JSONDecoder().decode(HDBConfiguration.self, from: JSONEncoder().encode(config))
        let reexported: [String: Any] = ["groups": [[String: Any]](), "nodes": [[String: Any]](),
            "spaceData": ["hdb": try HDBLightingZonePolicy.json(reloaded)]]
        precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(
            SpaceConfigurationIntegrityPolicy.configurationData(reexported), receipt))
        for zone: [String: Any] in [
            ["zoneId": 1, "name": "One", "groupAddress": 49152],
            ["zoneId": 1, "name": "One", "groupId": 49152],
            ["zoneId": 1, "name": "One"]
        ] {
            var malformed = object; malformed["lightingZones"] = [zone]
            precondition(SpaceConfigurationIntegrityPolicy.configurationData(["groups": [], "nodes": [], "spaceData": ["hdb": malformed]]) == nil,
                         "readback must not accept old or missing groupId")
        }
        var moved = config; moved.lightingZones[0].groupAddress = 0xC002
        let movedReceipt = SpaceConfigurationIntegrityPolicy.configurationData(["groups": [], "nodes": [], "spaceData": ["hdb": try HDBLightingZonePolicy.json(moved)]])
        precondition(!SpaceConfigurationIntegrityPolicy.configurationsMatch(receipt, movedReceipt), "groupId changes must remain visible to cloud comparison")
        // Persisted v1 baselines must not be promoted or accepted as new receipts.
        let oldHDB: [String: Any] = ["schemaVersion": 1, "devices": [], "lightingZones": []]
        let oldRemote: [String: Any] = ["groups": [], "nodes": [], "spaceData": ["hdb": oldHDB]]
        precondition(SpaceConfigurationIntegrityPolicy.configurationData(oldRemote) == nil)
        let oldBaseline = try JSONSerialization.data(withJSONObject: ["groups": [], "memberships": [], "hdb": oldHDB])
        let emptyV2 = SpaceConfigurationIntegrityPolicy.configurationData(["groups": [], "nodes": [], "spaceData": ["hdb": try HDBLightingZonePolicy.json(HDBConfiguration())]])
        precondition(!SpaceConfigurationIntegrityPolicy.configurationsMatch(oldBaseline, emptyV2))
        precondition(!SpaceConfigurationIntegrityPolicy.configurationsMatch(oldBaseline, receipt))
        // Compact MACs decode back to the same identity and remain strict against Node mismatches.
        let imported = try HDBLightingZonePolicy.decode(payload: payload)!
        precondition(imported.devices[0].mac == device.mac)
        try HDBLightingZonePolicy.validateReferences(imported, payload: payload)
        var changedControl = config
        changedControl.devices[0].lightingConfiguration!.lightingControl = .init(status: .synced, value: .forceOff)
        let changedControlPayload: [String: Any] = ["groups": [], "nodes": [], "spaceData": ["hdb": try HDBLightingZonePolicy.json(changedControl)]]
        precondition(!SpaceConfigurationIntegrityPolicy.configurationsMatch(receipt, SpaceConfigurationIntegrityPolicy.configurationData(changedControlPayload)))
        var changed = config
        changed.devices[0].lightingZonesStatus = .synced
        let newer: [String: Any] = ["groups": [[String: Any]](), "nodes": [[String: Any]](), "spaceData": ["hdb": try HDBLightingZonePolicy.json(changed)]]
        precondition(receipt != SpaceConfigurationIntegrityPolicy.configurationData(newer))
        changed = config
        changed.devices[0].lightingConfiguration!.brightIntensity!.value = 90
        let valueChanged: [String: Any] = ["groups": [[String: Any]](), "nodes": [[String: Any]](),
            "spaceData": ["hdb": try HDBLightingZonePolicy.json(changed)]]
        precondition(receipt != SpaceConfigurationIntegrityPolicy.configurationData(valueChanged),
                     "cloud comparison must retain field values")
        for key in ["Auto", "Force_On", "Force_Off", "elementAddress", "modelId", "property"] {
            var changedObject = object, records = object["devices"] as! [[String: Any]]
            var fields = records[0]["lightingConfiguration"] as! [String: Any]
            let name = ["Auto", "Force_On", "Force_Off"].contains(key) ? "lightingControl" : "brightIntensity"
            var field = fields[name] as! [String: Any]; field.removeValue(forKey: key)
            fields[name] = field; records[0]["lightingConfiguration"] = fields; changedObject["devices"] = records
            let missingDescription: [String: Any] = ["groups": [[String: Any]](), "nodes": [[String: Any]](), "spaceData": ["hdb": changedObject]]
            precondition(SpaceConfigurationIntegrityPolicy.configurationData(missingDescription) == nil,
                         "Cloud readback must not regenerate a missing command description")
        }
        let projection = SpaceCloudNodeRemovalPolicy.projectConfiguration(receipt!, removing: [.init(uuid: id.uuidString, address: 1, keyFingerprint: "")])!
        let projected = try JSONSerialization.jsonObject(with: projection) as! [String: Any]
        let projectedHDB = try HDBLightingZonePolicy.decode(payload: projected)
        precondition(projectedHDB?.devices.isEmpty == true && projectedHDB?.lightingZones == config.lightingZones)
        let stale = SpaceData()
        SpaceData.persisted = SpaceData()
        SpaceData.persisted!.hdb = config
        try HDBConfigurationStore.update(space: stale) { $0.lightingZones[0].name = "New" }
        precondition(stale.hdb?.devices == config.devices && stale.hdb?.lightingZones[0].name == "New")
        let saved = stale.hdb
        let revision = stale.lastUpdate
        SpaceData.failSave = true
        do { try HDBConfigurationStore.update(space: stale) { $0.devices = [] }; fatalError("failed save accepted") } catch {}
        precondition(stale.hdb == saved && SpaceData.persisted?.hdb == saved && stale.lastUpdate == revision)
        precondition(CloudSynchronizationManager.shared.submissions == 1)
        SpaceData.failSave = false
        SpaceData.persisted!.canEditing = false
        do { try HDBConfigurationStore.update(space: stale) { $0.devices = [] }; fatalError("visitor edit accepted") } catch {}
        print("PASS: HDB payload round trip, missing field rejection and UUID/address reference checks")
    }

    /// Real SQLite BLOB durability with production HDB codecs/policy. The minimal
    /// spaces table isolates this column; unrelated App tables/imports are not exercised.
    static func sqliteRoundTrip(_ config: HDBConfiguration, path: String) throws {
        var db: OpaquePointer?
        precondition(sqlite3_open(path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ text: String) { precondition(sqlite3_exec(db, text, nil, nil, nil) == SQLITE_OK) }
        func write(_ data: Data) {
            var statement: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, "INSERT OR REPLACE INTO spaces (id,hdb) VALUES (1,?)", -1, &statement, nil) == SQLITE_OK)
            data.withUnsafeBytes { buffer in
                defer { sqlite3_finalize(statement) }
                precondition(sqlite3_bind_blob(statement, 1, buffer.baseAddress, Int32(buffer.count), nil) == SQLITE_OK)
                precondition(sqlite3_step(statement) == SQLITE_DONE)
            }
        }
        func read() -> Data {
            var statement: OpaquePointer?
            precondition(sqlite3_prepare_v2(db, "SELECT hdb FROM spaces WHERE id=1", -1, &statement, nil) == SQLITE_OK)
            defer { sqlite3_finalize(statement) }
            precondition(sqlite3_step(statement) == SQLITE_ROW)
            return Data(bytes: sqlite3_column_blob(statement, 0)!, count: Int(sqlite3_column_bytes(statement, 0)))
        }
        func decode(_ data: Data) throws -> HDBConfiguration {
            let value = try JSONDecoder().decode(HDBConfiguration.self, from: data)
            try HDBLightingZonePolicy.validate(value)
            return value
        }
        sql("CREATE TABLE spaces (id INTEGER PRIMARY KEY, hdb BLOB)")
        let saved = try JSONEncoder().encode(config)
        write(saved)
        precondition(sqlite3_close(db) == SQLITE_OK)
        db = nil
        precondition(sqlite3_open(path, &db) == SQLITE_OK)
        let reopened = try decode(read())
        precondition(reopened == config)
        let json = try JSONSerialization.jsonObject(with: read()) as! [String: Any]
        let zone = (json["lightingZones"] as! [[String: Any]])[0]
        precondition(zone["groupId"] as? String == "C000" && zone["groupAddress"] == nil)
        let device = (json["devices"] as! [[String: Any]])[0]
        precondition(json["schemaVersion"] as? Int == 2 && device["nodeAddress"] as? String == "0001")
        precondition(device["mac"] as? String == "AABBCCDDEEFF" && device["lightingZones"] as? [Int] == [1])
        // Invalid import fails validation before this fixture commits, preserving the last record.
        sql("BEGIN IMMEDIATE")
        var bad = json; var entries = json["devices"] as! [[String: Any]]
        entries[0]["nodeAddress"] = 1; bad["devices"] = entries
        write(try JSONSerialization.data(withJSONObject: bad))
        do { _ = try decode(read()); fatalError("numeric v1 field accepted from SQLite") }
        catch { sql("ROLLBACK") }
        precondition(read() == saved)
        // Updating desired state survives another connection restart.
        var updated = config
        updated.devices[0].lightingZones = []
        updated.devices[0].lightingConfiguration!.lightingControl = .init(status: .synced, value: .forceOff)
        write(try JSONEncoder().encode(updated))
        precondition(sqlite3_close(db) == SQLITE_OK)
        db = nil
        precondition(sqlite3_open(path, &db) == SQLITE_OK)
        let restored = try decode(read())
        precondition(restored == updated)
        // Reject the old format without modifying its stored bytes.
        let legacy = Data("{\"schemaVersion\":1,\"devices\":[],\"lightingZones\":[]}".utf8)
        write(legacy)
        do { _ = try decode(read()); fatalError("legacy HDB accepted from SQLite") }
        catch HDBConfigurationError.invalidData {}
        precondition(read() == legacy)
        print("PASS: real SQLite HDB BLOB reopen, state/empty Zone persistence, rollback and non-destructive legacy rejection")
        var mixed = json
        mixed["lightingZones"] = [["zoneId": 1, "name": "One", "groupAddress": 49152]]
        let corrupt = try JSONSerialization.data(withJSONObject: mixed)
        write(corrupt)
        let cloud: [String: Any] = ["nodes": [[String: Any]](),
            "groups": [["address": "C000", "isVirtual": false]], "spaceData": ["hdb": mixed]]
        let repaired = try HDBLightingZonePolicy.repairingDefaults(in: cloud) { "Zone \($0)" }
        let recovered = try HDBLightingZonePolicy.decode(payload: repaired)!
        let recoveredData = try JSONEncoder().encode(recovered)
        sql("BEGIN IMMEDIATE"); write(recoveredData); sql("ROLLBACK")
        precondition(read() == corrupt, "failed repair must retain the original invalid BLOB")
        sql("BEGIN IMMEDIATE"); write(recoveredData); sql("COMMIT")
        precondition(sqlite3_close(db) == SQLITE_OK); db = nil
        precondition(sqlite3_open(path, &db) == SQLITE_OK)
        let afterRestart = try decode(read())
        precondition(afterRestart == recovered && afterRestart.devices.isEmpty && afterRestart.lightingZones.count == 1)
        print("PASS: default repair of mixed v2 BLOB rolls back safely and reopens with cloud-empty devices")
        let oldCloud = RecoveryMeshFactory.legacyPayload()
        let oldData = try JSONSerialization.data(withJSONObject: (oldCloud["spaceData"] as! [String: Any])["hdb"]!)
        write(oldData)
        let currentCloud = try HDBLightingZonePolicy.repairingDefaults(in: oldCloud,
            deviceConfiguration: RecoveryMeshFactory.resolve) { "Zone \($0)" }
        let currentConfig = try HDBLightingZonePolicy.decode(payload: currentCloud)!
        let currentData = try JSONEncoder().encode(currentConfig)
        sql("BEGIN IMMEDIATE"); write(currentData); sql("ROLLBACK")
        precondition(read() == oldData)
        sql("BEGIN IMMEDIATE"); write(currentData); sql("COMMIT")
        precondition(sqlite3_close(db) == SQLITE_OK); db = nil
        precondition(sqlite3_open(path, &db) == SQLITE_OK)
        let currentReopened = try decode(read())
        precondition(currentReopened == currentConfig && currentReopened.devices.count == 1
            && currentReopened.lightingZones.count == 63)
        try HDBLightingZonePolicy.validateReferences(currentReopened, payload: currentCloud)
        print("PASS: explicit v1 recovery preserves original bytes on rollback; v2 device/models/defaults survive SQLite reopen")
    }
}
