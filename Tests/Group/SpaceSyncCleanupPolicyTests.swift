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

    static func jsonData(_ object: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    static func withRelay(_ value: Any, in input: [String: Any]) -> [String: Any] {
        var result = input
        var groups = result["groups"] as! [[String: Any]]
        var profile = groups[0]["profile"] as! [String: Any]
        profile["proximityLightingNumber"] = value
        groups[0]["profile"] = profile
        result["groups"] = groups
        return result
    }

    static func mutationCount(_ result: SpaceSyncCleanupPolicy.Result) -> Int {
        let observations = Dictionary(uniqueKeysWithValues:
            (result.payload["nodes"] as! [[String: Any]]).map { ($0["uuid"] as! String, $0) })
        return result.devices.filter { device in
            let observation = observations[device.uuid]!
            let current = ProximityLightingTopologyPolicy.CurrentState(
                enabled: observation["proximityLightingEnabled"] as! Bool,
                relayNumber: UInt8(exactly: SpaceConfigurationIntegrityPolicy.integer(
                    observation["proximityLightingRelayCount"])!),
                neighborAddresses: (observation["proximityLightingNeighborAddresses"] as! [Int]).map {
                    UInt16(exactly: $0)!
                })
            return ProximityLightingTopologyPolicy.mutation(
                from: current, to: result.topology.plan.target(for: device.topologyAddress)) != nil
        }.count
    }

    static func testRelayCompatibility() throws {
        for type in [7, 8] {
            var local = withRelay(255, in: payload(type: type))
            local["nodes"] = (local["nodes"] as! [[String: Any]]).map { original in
                var node = original
                node["proximityLightingEnabled"] = true
                node["proximityLightingRelayCount"] = 255
                node["proximityLightingNeighborAddresses"] =
                    (node["unicastAddress"] as! String) == "0010" ? [32] : [16]
                node["futureObservation"] = ["value": 123]
                return node
            }
            let localConfiguration = SpaceConfigurationIntegrityPolicy.configurationData(local)
            let localData = try jsonData(local)
            let allValues: [Any] = Array(21...255).map { $0 as Any }
                + [256, 65535, Int64.max, UInt64.max]
            for value in allValues {
                let cloud = withRelay(value, in: local)
                let originalData = try jsonData(cloud)
                let decoded = try JSONSerialization.jsonObject(with: originalData) as! [String: Any]
                precondition(SpaceConfigurationIntegrityPolicy.profilesIssue(in: decoded) == nil)
                let cloudConfiguration = SpaceConfigurationIntegrityPolicy.configurationData(decoded)
                precondition(cloudConfiguration != nil && cloudConfiguration == localConfiguration,
                             "Every integer above 20 must compare equally before cleanup for both Profile types")
                precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(cloudConfiguration, localConfiguration))
                precondition(SpaceSyncCleanupPolicy.baseline(decoded) == SpaceSyncCleanupPolicy.baseline(local))
                let cleaned = try SpaceSyncCleanupPolicy.normalize(decoded)
                let needsRepair = SpaceConfigurationIntegrityPolicy.integer(value) != 255
                precondition(cleaned.didChange == needsRepair && cleaned.repairs.count == (needsRepair ? 1 : 0))
                precondition(cleaned.topology.isValid && cleaned.topology.repairs.isEmpty)
                precondition(cleaned.topology.snapshot.groups[0].relayNumber == 255)
                let cleanedData = try jsonData(cleaned.payload)
                precondition(cleanedData == localData,
                             "Only the relay value changes; paths, zones, times, scenes and observations survive")
                let retainedOriginalData = try jsonData(cloud)
                precondition(retainedOriginalData == originalData, "Normalization must retain the original payload")
                precondition(mutationCount(cleaned) == 0, "ALL normalization cannot create proximity device tasks")
                let repeated = try SpaceSyncCleanupPolicy.normalize(cleaned.payload)
                precondition(!repeated.didChange)
                let repeatedData = try jsonData(repeated.payload)
                precondition(cleanedData == repeatedData, "Relay normalization must be idempotent")
            }

            var changedTimes = local
            var changedGroups = changedTimes["groups"] as! [[String: Any]]
            var changedProfile = changedGroups[0]["profile"] as! [String: Any]
            changedProfile["timeT2"] = 1200
            changedProfile["timeT4"] = 600
            changedProfile["manualOverrideTimeout"] = 600
            changedGroups[0]["profile"] = changedProfile
            changedTimes["groups"] = changedGroups
            precondition(SpaceConfigurationIntegrityPolicy.configurationData(changedTimes) != localConfiguration,
                         "Real Profile time changes must remain visible to configuration comparison")

            for number in Array(0...20) + [255] {
                precondition(SpaceConfigurationIntegrityPolicy.normalizedProximityLightingNumber(number) == UInt8(number))
                let unchanged = try SpaceSyncCleanupPolicy.normalize(withRelay(number, in: payload(type: type)))
                precondition(!unchanged.didChange, "Already valid relay values require no repair")
            }
            let invalidValues: [Any] = [-1, Int64.min, 1.5, 21.5, 256.5, "21", "255", true, false, NSNull()]
            for invalid in invalidValues {
                precondition(SpaceConfigurationIntegrityPolicy.normalizedProximityLightingNumber(invalid) == nil)
                let malformed = withRelay(invalid, in: payload(type: type))
                precondition(SpaceConfigurationIntegrityPolicy.profilesIssue(in: malformed) == "C001:invalidProfileRelay")
                precondition(SpaceConfigurationIntegrityPolicy.configurationData(malformed) == nil)
                try mustReject(malformed)
            }
        }
        for type in 1...6 {
            var ordinary = payload(type: type)
            var groups = ordinary["groups"] as! [[String: Any]]
            groups[0].removeValue(forKey: "proximityLightingPath")
            ordinary["groups"] = groups
            ordinary["spaceData"] = ["proximityLightingSchemaVersion": 1, "triggerZones": [[String: Any]]()]
            for value: Any in [21, 254, 256, 65535, Int64.max, UInt64.max] {
                let cloud = withRelay(value, in: ordinary)
                let cleaned = try SpaceSyncCleanupPolicy.normalize(cloud)
                precondition(cleaned.didChange && cleaned.repairs.count == 1)
                precondition(cleaned.topology.isValid && cleaned.topology.snapshot.groups[0].relayNumber == 255)
                let actual = try jsonData(cleaned.payload)
                let expected = try jsonData(withRelay(255, in: ordinary))
                precondition(actual == expected, "Inactive relay normalization must retain all other configuration")
            }
        }
    }

    static func testSnapshot(at path: String) throws {
        let root = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        let source = root["data"] as? [String: Any] ?? root
        precondition(SpaceConfigurationIntegrityPolicy.profilesIssue(in: source) == nil,
                     "The real snapshot must pass Profile validation after relay normalization")
        var expected = source
        var expectedGroups = source["groups"] as! [[String: Any]]
        var aliasCount = 0
        for index in expectedGroups.indices where !(expectedGroups[index]["isVirtual"] as? Bool ?? false) {
            var profile = expectedGroups[index]["profile"] as! [String: Any]
            if SpaceConfigurationIntegrityPolicy.normalizedProximityLightingNumber(profile["proximityLightingNumber"]) == 255,
               SpaceConfigurationIntegrityPolicy.integer(profile["proximityLightingNumber"]) != 255 {
                profile["proximityLightingNumber"] = 255
                expectedGroups[index]["profile"] = profile
                aliasCount += 1
            }
        }
        expected["groups"] = expectedGroups
        let cleaned = try SpaceSyncCleanupPolicy.normalize(source)
        precondition(cleaned.topology.isValid && cleaned.topology.repairs.isEmpty)
        precondition(cleaned.repairs.count == aliasCount && cleaned.orphanSubscriptions.isEmpty)
        let cleanedData = try jsonData(cleaned.payload)
        let expectedData = try jsonData(expected)
        precondition(cleanedData == expectedData, "All real snapshot fields except the normalized relay value must survive")
        precondition(SpaceConfigurationIntegrityPolicy.profilesIssue(in: cleaned.payload) == nil)
        precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(
            SpaceConfigurationIntegrityPolicy.configurationData(source),
            SpaceConfigurationIntegrityPolicy.configurationData(cleaned.payload)))
        let repeated = try SpaceSyncCleanupPolicy.normalize(cleaned.payload)
        precondition(!repeated.didChange)
        let repeatedData = try jsonData(repeated.payload)
        precondition(repeatedData == cleanedData)
        let tasks = mutationCount(cleaned)
        precondition(tasks == 0, "The provided device observations must require no proximity mutations")
        print("PASS: external snapshot devices=\(cleaned.devices.count) relayAliases=\(aliasCount) proximityMutations=\(tasks); all other fields retained")
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
        try testRelayCompatibility()
        print("PASS: complete Space cleanup, missing device/Group, Profile 1...8, retained observations, idempotency and malformed snapshots")
        print("PASS: Profile 7/8 ALL alias compatibility, canonical comparison, retained configuration and zero proximity mutations")
        if CommandLine.arguments.count > 1 {
            precondition(CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--snapshot")
            try testSnapshot(at: CommandLine.arguments[2])
        }
    }
}
