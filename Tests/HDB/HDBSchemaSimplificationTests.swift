import Foundation

@main enum HDBSchemaSimplificationTests {
    static func main() throws {
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
}
