import Foundation

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
        for key in ["mapValues", "elementAddress", "modelId", "property"] {
            var changedObject = object, records = object["devices"] as! [[String: Any]]
            var fields = records[0]["lightingConfiguration"] as! [String: Any]
            let name = key == "mapValues" ? "lightingControl" : "brightIntensity"
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
}
