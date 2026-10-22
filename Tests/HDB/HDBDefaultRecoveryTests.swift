import Foundation

@main enum HDBDefaultRecoveryTests {
    static func repair(_ value: [String: Any]) throws -> [String: Any] {
        try HDBLightingZonePolicy.repairingDefaults(in: value,
            deviceConfiguration: RecoveryMeshFactory.resolve) { "Zone \($0)" }
    }
    static func rejected(_ value: [String: Any]) {
        do { _ = try repair(value); fatalError("invalid recovery input accepted") } catch {}
    }
    static func main() throws {
        let id = UUID(), replacementID = UUID()
        var device = HDBDeviceConfiguration(nodeUuid: id, nodeAddress: 14, mac: "AA:BB:CC:DD:EE:FF")
        device.lightingZonesStatus = .synced
        device.lightingConfiguration = .init(values: .init(lightingControl: .auto,
            dimIntensity: 5, brightIntensity: 80, holdTime: 10), status: .synced)
        let original = HDBConfiguration(lightingZones: (1...63).map {
            .init(zoneId: $0, name: "Zone \($0)", groupAddress: UInt16(0xC000 + $0))
        }, devices: [device])
        var hdb = try HDBLightingZonePolicy.json(original)
        hdb["lightingZones"] = original.lightingZones.map {
            ["zoneId": $0.zoneId, "name": $0.name, "groupAddress": Int($0.groupAddress)] as [String: Any]
        }
        let groups = original.lightingZones.map {
            ["address": String(format: "%04X", $0.groupAddress), "isVirtual": false] as [String: Any]
        }
        var payload: [String: Any] = ["spaceData": ["hdb": hdb], "groups": groups,
            "nodes": [["uuid": id.uuidString, "unicastAddress": "000E"]], "deviceCount": 1]
        let normalized = try repair(payload)
        let decoded = try HDBLightingZonePolicy.decode(payload: normalized)!
        precondition(decoded == original, "format-only repair must preserve valid settings and statuses")
        let repeated = try repair(normalized)
        precondition(NSDictionary(dictionary: repeated).isEqual(to: normalized), "repair must be idempotent")
        print("PASS: mixed v2 Zone fields repaired; valid lighting and empty memberships preserved")

        payload["nodes"] = [[String: Any]]()
        let empty = try repair(payload)
        let emptyConfig = try HDBLightingZonePolicy.decode(payload: empty)!
        precondition(emptyConfig.devices.isEmpty && emptyConfig.lightingZones.count == 63)
        precondition(empty["deviceCount"] as? Int == 0)
        try HDBLightingZonePolicy.validateReferences(emptyConfig, payload: empty)
        payload["nodes"] = [["uuid": replacementID.uuidString, "unicastAddress": "000E"]]
        let replaced = try HDBLightingZonePolicy.decode(payload: repair(payload))!
        precondition(replaced.devices.isEmpty)
        print("PASS: empty/replaced cloud Nodes remove stale HDB devices without local resurrection")

        var malformed = try HDBLightingZonePolicy.json(original)
        var devices = malformed["devices"] as! [[String: Any]]
        var lighting = devices[0]["lightingConfiguration"] as! [String: Any]
        lighting["dimIntensity"] = ["value": 75, "status": "synced"]
        lighting["lightingControl"] = ["value": "invalid", "status": "synced"]
        lighting["holdTime"] = ["value": 10, "status": "bad"]
        devices[0]["lightingConfiguration"] = lighting; malformed["devices"] = devices
        payload["nodes"] = [["uuid": id.uuidString, "unicastAddress": "000E"]]
        payload["spaceData"] = ["hdb": malformed]
        let defaults = try HDBLightingZonePolicy.decode(payload: repair(payload))!.devices[0].lightingConfiguration!
        precondition(defaults.dimIntensity?.value == 20 && defaults.dimIntensity?.status == .pending)
        precondition(defaults.lightingControl?.value == .auto && defaults.lightingControl?.status == .pending)
        precondition(defaults.holdTime?.value == 10 && defaults.holdTime?.status == .pending)
        precondition(defaults.brightIntensity?.value == 80 && defaults.brightIntensity?.status == .synced)
        precondition(defaults.installDate == nil && defaults.rampUpTime == nil)
        print("PASS: only invalid values/statuses default; valid optional omissions stay omitted")

        payload.removeValue(forKey: "nodes"); rejected(payload)
        payload["nodes"] = "bad"; rejected(payload)
        payload["nodes"] = [["uuid": id.uuidString, "unicastAddress": "FFFF"]]; rejected(payload)
        payload["nodes"] = [[String: Any]]()
        malformed["schemaVersion"] = 3; payload["spaceData"] = ["hdb": malformed]; rejected(payload)
        let ordinary: [String: Any] = ["nodes": [[String: Any]](), "groups": [[String: Any]]()]
        let unchanged = try repair(ordinary)
        precondition(NSDictionary(dictionary: unchanged).isEqual(to: ordinary))
        print("PASS: missing/malformed Nodes, invalid identities and unknown schema rejected; ordinary empty Space unchanged")
        try testLegacyRecovery()
        for path in CommandLine.arguments.dropFirst() {
            let input = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
            let source = input["data"] as? [String: Any] ?? input
            let result = try repair(source)
            let repaired = try HDBLightingZonePolicy.decode(payload: result)!
            try HDBLightingZonePolicy.validateReferences(repaired, payload: result)
            precondition(NSArray(array: result["nodes"] as! [Any]).isEqual(to: source["nodes"] as! [Any]))
            print("PASS: supplied snapshot repaired with \(repaired.lightingZones.count) Zones and \(repaired.devices.count) HDB devices; cloud Nodes unchanged")
        }
    }

    static func testLegacyRecovery() throws {
        var payload = RecoveryMeshFactory.legacyPayload()
        precondition((try? HDBLightingZonePolicy.decode(payload: payload)) == nil, "ordinary v1 import stays strict")
        let result = try repair(payload)
        let config = try HDBLightingZonePolicy.decode(payload: result)!
        let device = config.devices[0]
        precondition(config.schemaVersion == 2 && config.lightingZones.count == 63 && config.devices.count == 1)
        precondition(device.nodeAddress == 11 && device.mac == "AA:BB:CC:DD:EE:FF" && device.sensorGroupId == 0xC07F)
        precondition(device.zoneModels.count == 5 && device.sensorGroupModels.count == 3 && device.broadcastModels.count == 3)
        precondition(device.broadcastModels.allSatisfy { $0.elementAddress == 13 }, "standalone CTL must not gain a broadcast target")
        precondition(device.lightingZones.isEmpty && device.lightingZonesStatus == .pending)
        precondition(device.lightingConfiguration?.values == .defaults && device.lightingConfiguration?.holdTime?.status == .pending)
        let repeated = try repair(result)
        precondition(NSDictionary(dictionary: result).isEqual(to: repeated), "legacy repair must stabilize after first conversion")
        try HDBLightingZonePolicy.validateReferences(config, payload: result)
        let encoded = ((result["spaceData"] as! [String: Any])["hdb"] as! [String: Any])["devices"] as! [[String: Any]]
        let lighting = encoded[0]["lightingConfiguration"] as! [String: Any]
        precondition((lighting["holdTime"] as! [String: Any])["elementAddress"] as? String == "000D")
        print("PASS: v1 numeric addresses/nil MAC/missing models become current v2 via the production factory and SDK relationships")

        var damagedV2 = result
        var v2Extension = result["spaceData"] as! [String: Any]
        var v2HDB = v2Extension["hdb"] as! [String: Any]
        var v2Devices = v2HDB["devices"] as! [[String: Any]]
        v2Devices[0]["mac"] = NSNull(); v2Devices[0].removeValue(forKey: "zoneModels")
        v2Devices[0]["broadcastModels"] = "bad"
        v2HDB["devices"] = v2Devices; v2Extension["hdb"] = v2HDB; damagedV2["spaceData"] = v2Extension
        let restoredV2 = try HDBLightingZonePolicy.decode(payload: repair(damagedV2))!
        precondition(restoredV2 == config, "v2 missing/invalid derived fields must use the same factory as v1")
        damagedV2["groups"] = (damagedV2["groups"] as! [[String: Any]]).filter { $0["isVirtual"] as? Bool != true }
        let noSensor = try HDBLightingZonePolicy.decode(payload: repair(damagedV2))!.devices[0]
        precondition(noSensor.sensorGroupId == nil && noSensor.lightingZonesStatus == .pending)
        print("PASS: v2 damaged MAC/models reuse the legacy repair path; removed cloud Sensor Group is not resurrected")

        var extensionData = payload["spaceData"] as! [String: Any]
        var legacyHDB = extensionData["hdb"] as! [String: Any]
        var devices = legacyHDB["devices"] as! [[String: Any]]
        devices[0]["lightingZones"] = [["zoneId": 2], ["zoneId": 1], ["zoneId": 2]]
        legacyHDB["devices"] = devices; extensionData["hdb"] = legacyHDB; payload["spaceData"] = extensionData
        let memberships = try HDBLightingZonePolicy.decode(payload: repair(payload))!.devices[0].lightingZones
        precondition(memberships.map(\.zoneId) == [1, 2], "known v1 object memberships must not be discarded")
        print("PASS: v1 object memberships and v2 integer memberships share normalization without losing valid Zone assignments")

        var nodes = payload["nodes"] as! [[String: Any]]
        nodes[0]["unicastAddress"] = "0020"; nodes[0]["macAddress"] = "112233445566"
        payload["nodes"] = nodes
        let moved = try HDBLightingZonePolicy.decode(payload: repair(payload))!.devices[0]
        precondition(moved.nodeAddress == 32 && moved.mac == "11:22:33:44:55:66")
        precondition(moved.sensorGroupModels.allSatisfy { $0.elementAddress == 34 })
        nodes[0].removeValue(forKey: "macAddress"); payload["nodes"] = nodes; rejected(payload)
        payload["nodes"] = [[String: Any]]()
        let empty = try HDBLightingZonePolicy.decode(payload: repair(payload))!
        precondition(empty.devices.isEmpty)
        print("PASS: cloud address/MAC changes win; unresolvable MAC rejected; cloud-empty v1 never restores removed devices")
    }
}
