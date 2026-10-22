import Foundation

@main enum HDBSchemaSimplificationTests {
    static func main() throws {
        try testLightingMetadata()
        let device = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF")
        let data = try JSONEncoder().encode(device)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(json["lightingZonesStatus"] as? String == "pending",
                     "An empty target must retain a durable pending result until the device is configured")
        let target = try JSONDecoder().decode(HDBZoneMembership.self, from: Data("{\"zoneId\":1}".utf8))
        let targetJSON = try JSONSerialization.jsonObject(with: JSONEncoder().encode(target)) as! [String: Any]
        precondition(Set(targetJSON.keys) == ["zoneId"], "Only the device owns the synchronization result")
        guard let configuration = json["lightingConfiguration"] as? [String: Any],
              let bright = configuration["brightIntensity"] as? [String: Any] else {
            fatalError("New HDB devices must persist field-level default targets before initialization")
        }
        precondition(bright["value"] as? Int == 80 && bright["status"] as? String == "pending")
        precondition(configuration["values"] == nil && configuration["results"] == nil)
        precondition(configuration["installDate"] == nil)
        precondition(json["preparation"] == nil && json["sensorGroupId"] is NSNull)
        precondition(HDBSyncStatus(rawValue: "failed") == nil && HDBSyncStatus(rawValue: "sent") == nil)
        let root = HDBConfiguration(lightingZones: [.init(zoneId: 1, name: "One", groupAddress: 0xC001)], devices: [device])
        let encoded = try JSONEncoder().encode(root)
        let payload = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(payload["sensorGroups"] == nil && payload["lightingConfiguration"] == nil)
        precondition(payload["broadcast"] == nil)
        precondition((payload["lightingZones"] as? [[String: Any]])?.first?["lightingConfiguration"] == nil)
        let decoded = try JSONDecoder().decode(HDBConfiguration.self, from: encoded)
        precondition(decoded == root)
        print("PASS: HDB two-state schema, device-only scopes and per-field initialization defaults")
    }
    static func testLightingMetadata() throws {
        var device = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 10, mac: "AA:BB:CC:DD:EE:FF")
        device.zoneModels = [(13, 0x130F), (13, 0x1310), (12, 0x1300), (11, 0x130F),
                             (11, 0x1310), (10, 0x1300), (10, 0x1000)].map {
            HDBModelReference(.init(elementAddress: UInt16($0.0), modelIdentifier: UInt16($0.1), companyIdentifier: nil))
        }
        device.lightingConfiguration?.merge(.init(installDate: "22-10-2026"), status: .synced)
        func object(_ device: HDBDeviceConfiguration) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) as! [String: Any]
        }
        let json = try object(device), fields = json["lightingConfiguration"] as! [String: Any]
        let control = fields["lightingControl"] as! [String: Any]
        guard let mappings = control["mapValues"] as? [String: [String: Any]] else {
            fatalError("Lighting Control must export all three command mappings")
        }
        precondition(Set(mappings.keys) == ["Auto", "Force_On", "Force_Off"])
        for (key, address, model, value): (String, Int, Int, Any) in [
            ("Auto", 11, 4879, true), ("Force_On", 10, 4864, 65535), ("Force_Off", 10, 4096, false)
        ] {
            let item = mappings[key]!
            precondition(item["elementAddress"] as? Int == address && item["modelId"] as? Int == model)
            precondition(NSDictionary(dictionary: item["value"].map { ["v": $0] }!) == NSDictionary(dictionary: ["v": value]))
            precondition(Set(item.keys) == ["elementAddress", "modelId", "value"])
        }
        for (field, property) in [("dimIntensity", 47), ("brightIntensity", 46), ("rampUpTime", 55), ("rampDownTime", 54), ("holdTime", 60)] {
            let item = fields[field] as! [String: Any]
            precondition(item["elementAddress"] as? Int == 11 && item["modelId"] as? Int == 4880 && item["property"] as? Int == property)
        }
        for field in ["failsafeDelay", "installDate"] {
            precondition(Set((fields[field] as! [String: Any]).keys) == ["status", "value"])
        }
        let roundtrip = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONEncoder().encode(device))
        var normalized = device; normalized.zoneModels = HDBModelReference.normalized(device.zoneModels)
        precondition(roundtrip == normalized)
        func rejected(_ mutate: (inout [String: Any]) -> Void) throws {
            var edited = fields; mutate(&edited)
            var payload = json; payload["lightingConfiguration"] = edited
            let data = try JSONSerialization.data(withJSONObject: payload)
            do { _ = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: data); fatalError("Invalid command metadata accepted") }
            catch is DecodingError {} catch HDBConfigurationError.invalidData {}
        }
        for key in ["elementAddress", "modelId", "property"] {
            try rejected { fields in var item = fields["brightIntensity"] as! [String: Any]; item.removeValue(forKey: key); fields["brightIntensity"] = item }
        }
        for value: Any in [13, 0, -1, 32768, "000B", true, NSNull()] {
            try rejected { fields in var item = fields["brightIntensity"] as! [String: Any]; item["elementAddress"] = value; fields["brightIntensity"] = item }
        }
        for (key, value): (String, Any) in [("modelId", 4879), ("property", 47), ("property", true), ("modelId", "1310")] {
            try rejected { fields in var item = fields["brightIntensity"] as! [String: Any]; item[key] = value; fields["brightIntensity"] = item }
        }
        try rejected { fields in var item = control; item.removeValue(forKey: "mapValues"); fields["lightingControl"] = item }
        for name in ["Auto", "Force_On", "Force_Off"] {
            try rejected { fields in var item = control, map = mappings; map.removeValue(forKey: name); item["mapValues"] = map; fields["lightingControl"] = item }
        }
        for (name, value): (String, Any) in [("Auto", 1), ("Auto", false), ("Force_On", true), ("Force_On", 1), ("Force_Off", 0)] {
            try rejected { fields in var item = control, map = mappings; map[name]!["value"] = value; item["mapValues"] = map; fields["lightingControl"] = item }
        }
        try rejected { fields in var item = control, map = mappings; map["Extra"] = map["Auto"]; item["mapValues"] = map; fields["lightingControl"] = item }
        try rejected { fields in var item = fields["failsafeDelay"] as! [String: Any]; item["modelId"] = 4880; fields["failsafeDelay"] = item }
        device.zoneModels = []
        let empty = try object(device)["lightingConfiguration"] as! [String: Any]
        precondition((empty["brightIntensity"] as! [String: Any])["elementAddress"] is NSNull)
        let emptyRoundtrip = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONEncoder().encode(device))
        precondition(emptyRoundtrip == device)
        var nullableFields = fields; nullableFields["brightIntensity"] = NSNull()
        var nullablePayload = json; nullablePayload["lightingConfiguration"] = nullableFields
        let nullable = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONSerialization.data(withJSONObject: nullablePayload))
        precondition(nullable.lightingConfiguration?.brightIntensity == nil)
        let nullableRoundtrip = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONEncoder().encode(nullable))
        precondition(nullableRoundtrip == nullable)
        device.lightingConfiguration = nil
        let nullConfiguration = try object(device)
        precondition(nullConfiguration["lightingConfiguration"] is NSNull)
        print("PASS: per-device command metadata, first targets, strict mappings, legacy rejection, metadata-only fields and null targets")
    }

}
