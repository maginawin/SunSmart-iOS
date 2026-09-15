import Foundation

@main
enum SpaceSyncCleanupPolicyTests {
    static let first = "00000000-0000-0000-0000-000000000001"
    static let second = "00000000-0000-0000-0000-000000000002"
    static func profile(_ type: Int) -> [String: Any] {
        var value: [String: Any] = ["id": "profile", "type": type, "highEndTrim": 100,
            "lowEndTrim": 0, "occupancyLevel": 80, "vacantLevel": 20, "taskLevel": 80,
            "standbyLevel": 0, "timeT1": 10, "timeT2": 10, "timeT3": 10, "timeT4": 10,
            "timeT5": 10, "manualOverrideTimeout": 10, "powerUpState": 0,
            "proximityLightingNumber": 2]
        if type == 8 {
            var scene = value
            scene["number"] = "FF01"; scene["name"] = "Night"
            value["scenes"] = [scene]
            value["day"] = ["id": 1, "startsBelowLux": 70, "sceneNumber": "FF01"]
            value["night"] = ["id": 0, "startsBelowLux": 30, "sceneNumber": "FF01"]
        }
        return value
    }
    static func node(_ uuid: String, _ address: String, group: String = "C001") -> [String: Any] {
        ["uuid": uuid, "unicastAddress": address, "groupState": 1, "groupAddress": group,
         "elements": [["models": [["modelId": "0A780001", "subscribe": [group, "FEFD"]]]]]]
    }
    static func payload(type: Int = 7) -> [String: Any] {
        ["nodes": [node(first, "0010"), node(second, "0020")],
         "groups": [["address": "C001", "profile": profile(type), "futureGroup": 123,
                     "proximityLightingPath": ["paths": [["items": [16, 32, 0], "futurePath": true]],
                                                "zones": [["addresses": [16, 32]]]]]],
         "spaceData": ["proximityLightingSchemaVersion": 1,
                       "triggerZones": [["name": "Keep", "items": [
                        ["groupAddress": 49153, "deviceAddress": 16],
                        ["groupAddress": 49153, "deviceAddress": 32]]]]],
         "scenes": [[String: Any]](), "schedules": [[String: Any]]()]
    }
    static func mustReject(_ payload: [String: Any]) throws {
        do { _ = try SpaceSyncCleanupPolicy.normalize(payload) }
        catch { return }
        preconditionFailure("Unknown or ambiguous data must never be cleaned as missing")
    }
    static func main() throws {
        let valid = try SpaceSyncCleanupPolicy.normalize(payload())
        precondition(!valid.didChange, "A valid, possibly offline device remains in the topology")
        var missing = payload()
        missing["nodes"] = [node(first, "0010")]
        let removed = try SpaceSyncCleanupPolicy.normalize(missing)
        precondition(removed.topology.snapshot.groups[0].paths == [[16, nil, nil]])
        precondition(removed.topology.snapshot.groups[0].zones == [[16]])
        precondition(removed.topology.snapshot.spaceZones[0].members.count == 1)
        let groups = removed.payload["groups"] as! [[String: Any]]
        precondition(groups[0]["futureGroup"] as? Int == 123)
        let repeated = try SpaceSyncCleanupPolicy.normalize(removed.payload)
        precondition(!repeated.didChange, "Cleanup must converge without extra writes")

        for type in 1...6 {
            let changed = try SpaceSyncCleanupPolicy.normalize(payload(type: type))
            precondition(!changed.topology.snapshot.groups[0].hasTopology)
            precondition(changed.topology.snapshot.spaceZones[0].members.isEmpty)
            precondition(changed.devices.count == 2, "Changing Profile never removes devices")
        }
        for type in [7, 8] {
            let changed = try SpaceSyncCleanupPolicy.normalize(payload(type: type))
            precondition(!changed.didChange && changed.topology.snapshot.groups[0].paths == [[16, 32, nil]])
        }
        var noGroup = payload()
        noGroup["groups"] = [[String: Any]]()
        let orphan = try SpaceSyncCleanupPolicy.normalize(noGroup)
        precondition(orphan.devices.allSatisfy { $0.groupAddress == nil })
        precondition(orphan.orphanSubscriptions[first] == [0xC001])
        let oldNode = (noGroup["nodes"] as! [[String: Any]])[0]
        let pendingNode = (orphan.payload["nodes"] as! [[String: Any]])[0]
        precondition(pendingNode["groupState"] as? Int == 2)
        let observed = try JSONSerialization.data(withJSONObject: oldNode["elements"]!, options: .sortedKeys)
        let pendingObserved = try JSONSerialization.data(withJSONObject: pendingNode["elements"]!, options: .sortedKeys)
        precondition(observed == pendingObserved, "Actual subscriptions remain until a real device receipt")
        let pendingAgain = try SpaceSyncCleanupPolicy.normalize(orphan.payload)
        precondition(!pendingAgain.didChange, "Offline unsubscribe remains actionable without rewriting the Space")
        for address: UInt16 in [0x8001, 0xFEFD, 0xFEFE, 0xFEFF, 0xFFFF] {
            precondition(!SpaceSyncCleanupPolicy.isBusinessGroup(address), "Virtual/reserved addresses are not business Group tombstones")
        }
        precondition(SpaceSyncCleanupPolicy.isBusinessGroup(0xFE00))
        var withVirtual = payload()
        var virtualGroups = withVirtual["groups"] as! [[String: Any]]
        virtualGroups.append(["address": "FE00", "isVirtual": true])
        withVirtual["groups"] = virtualGroups
        var virtualNode = node(first, "0010")
        virtualNode["elements"] = [["models": [["modelId": "0A780001", "subscribe": ["C001", "FE00", "FEFD"]]]]]
        withVirtual["nodes"] = [virtualNode, node(second, "0020")]
        let virtual = try SpaceSyncCleanupPolicy.normalize(withVirtual)
        precondition(!virtual.didChange && virtual.orphanSubscriptions.isEmpty, "An existing virtual switch Group is retained")
        var broken = payload()
        broken["nodes"] = [node(first, "0010"), node(second, "0010")]
        try mustReject(broken)
        broken = payload(); broken["groups"] = [["address": "C001"]]
        try mustReject(broken)
        broken = payload(); broken["nodes"] = NSNull()
        try mustReject(broken)
        broken = payload(); broken["spaceData"] = ["proximityLightingSchemaVersion": 9, "triggerZones": []]
        try mustReject(broken)
        print("PASS: complete Space cleanup, missing device/Group, Profile 1...8, retained observations, idempotency and malformed snapshots")
    }
}
