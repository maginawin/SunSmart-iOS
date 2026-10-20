import Foundation

@main enum HDBGroupLifecycleTests {
    static func main() throws {
        let uuid = UUID()
        let profile: [String: Any] = ["id": "p", "type": 1, "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 80, "vacantLevel": 20, "taskLevel": 80, "standbyLevel": 0, "timeT1": 10, "timeT2": 10, "timeT3": 10, "timeT4": 10, "timeT5": 10, "manualOverrideTimeout": 10, "powerUpState": 0]
        let config = HDBConfiguration(lightingZones: [.init(zoneId: 1, name: "One", groupAddress: 0xC001), .init(zoneId: 2, name: "Two", groupAddress: 0xC002)], devices: [.init(nodeUuid: uuid, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF", lightingZones: [.init(zoneId: 1), .init(zoneId: 2)])])
        let node: [String: Any] = ["uuid": uuid.uuidString, "unicastAddress": "0001", "groupState": 0, "elements": [["models": [["modelId": "1000", "subscribe": ["C001", "C002"]]]]]]
        var payload: [String: Any] = ["nodes": [node], "groups": ["C001", "C002"].map { ["address": $0, "profile": profile] }, "spaceData": ["hdb": try HDBLightingZonePolicy.json(config)], "scenes": [[String: Any]](), "schedules": [[String: Any]]()]
        let result = try SpaceSyncCleanupPolicy.normalize(payload)
        precondition(result.devices[0].groupAddress == nil && result.orphanSubscriptions.isEmpty)
        precondition(result.topology.snapshot.groups.isEmpty)
        payload["spaceData"] = [:] as [String: Any]
        do { _ = try SpaceSyncCleanupPolicy.normalize(payload); fatalError("ordinary multiple membership accepted") } catch {}
        let empty = try HDBLightingZonePolicy.replacingZones([], for: config.devices[0], in: config)
        precondition(empty.devices[0].lightingZones.isEmpty && empty.devices[0].lightingZonesStatus == .pending)
        precondition(empty.lightingZones == config.lightingZones, "empty target retains directory addresses")
        try HDBLightingZonePolicy.validate(empty)
        print("PASS: multiple HDB groups remain known, ordinary ambiguity rejected, empty target retains directory")
    }
}
