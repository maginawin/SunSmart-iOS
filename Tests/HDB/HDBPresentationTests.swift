import Foundation

@main enum HDBPresentationTests {
    static func main() throws {
        var device = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 1)])
        precondition(HDBPresentation.statusKey(device) == "hdb_pending")
        precondition(HDBPresentation.selectedZones(device) == [1])
        device.lightingZonesStatus = .synced
        precondition(HDBPresentation.statusKey(device) == "hdb_synced")
        let json = try HDBPresentation.json(device)
        precondition(json.contains("lightingZonesStatus") && !json.contains("desired"))
        let pending = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 3, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 1)])
        let unrelated = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 4, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 2)])
        let config = HDBConfiguration(devices: [pending, unrelated, device])
        precondition(HDBPresentation.members(zoneId: 1, in: config).map(\.nodeAddress) == [1, 3])
        precondition(HDBPresentation.members(zoneId: 63, in: config).isEmpty)
        device.lightingZones = []; device.lightingZonesStatus = .pending
        precondition(HDBPresentation.statusKey(device) == "hdb_pending" && HDBPresentation.selectedZones(device).isEmpty)
        print("PASS: target membership, device status including empty pending target, and local JSON")
    }
}
