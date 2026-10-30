import Foundation

@main struct SceneConfigurationRoundTripTests {
    static func main() throws {
        let identity = TimedSchedulerNodeIdentity(nodeUUID: "11111111-1111-1111-1111-111111111111",
            unicastAddress: "0001", deviceKeyFingerprint: String(repeating: "A", count: 64))
        let config = SceneConfiguration(kind: .devices, name: "Offline",
            deviceMembers: [.init(identity: identity, parameters: .init(isOn: true, lightness: 1234, cct: 4567))],
            pendingOperations: [.init(identity: identity, action: .write)])
        var row = try JSONSerialization.jsonObject(with: config.encoded()) as! [String: Any]
        row["number"] = "0007"
        let payload: [String: Any] = ["groups": [], "nodes": [], "scenes": [["number": "0007", "name": "Offline", "imageId": 3]],
            "spaceData": ["sceneConfigurations": [row]]]
        var missing = payload; missing["spaceData"] = [:] as [String: Any]
        guard !SpaceConfigurationIntegrityPolicy.configurationsMatch(
            SpaceConfigurationIntegrityPolicy.configurationData(payload),
            SpaceConfigurationIntegrityPolicy.configurationData(missing)) else {
            print("FAIL: remote dropped committed scene configuration but upload comparison reported equal"); exit(1)
        }
        try payloadValidation(payload, row: row, config: config)
        try groupLoss()
    }
    static func payloadValidation(_ payload: [String: Any], row: [String: Any], config: SceneConfiguration) throws {
        typealias P = SpaceConfigurationIntegrityPolicy
        let expected = P.configurationData(payload)!
        var lostTask = row; lostTask["pendingOperations"] = []
        var lost = payload; lost["spaceData"] = ["sceneConfigurations": [lostTask]]
        precondition(!P.configurationsMatch(expected, P.configurationData(lost)), "lost task is not successful readback")
        for bad in [NSNull(), "invalid", [row, row]] as [Any] {
            var invalid = payload; invalid["spaceData"] = ["sceneConfigurations": bad]
            precondition(P.configurationData(invalid) == nil)
            do { _ = try SceneConfigurationPayload.records(payload: invalid); fatalError("bad payload accepted") } catch {}
        }
        for (field, value) in [("schemaVersion", 2 as Any), ("number", "0000"), ("number", "FF00"), ("name", "Different"),
                               ("kind", "groups"), ("deviceMembers", config.deviceMembers.map { _ in row["deviceMembers"] as! [Any] }.flatMap { $0 } + (row["deviceMembers"] as! [Any]))] {
            var changed = row; changed[field] = value
            var invalid = payload; invalid["spaceData"] = ["sceneConfigurations": [changed]]
            precondition(P.configurationData(invalid) == nil, "explicit invalid field must reject: \(field)")
        }
        var legacy = payload; legacy.removeValue(forKey: "spaceData")
        let legacyRecords = try SceneConfigurationPayload.records(payload: legacy)
        precondition(legacyRecords[0].configuration == nil)
        var second = config
        second.deviceMembers = [.init(identity: .init(nodeUUID: "22222222-2222-2222-2222-222222222222", unicastAddress: "0002", deviceKeyFingerprint: String(repeating: "B", count: 64)), parameters: .init(isOn: false, lightness: 0, cct: 6500))] + config.deviceMembers
        second.pendingOperations = second.deviceMembers.map { .init(identity: $0.identity, action: .write) }
        let encoded = try SceneConfigurationPayload.encode(records: [.init(number: 7, name: second.name, imageId: 3, configuration: second)])
        var reversed = encoded
        reversed[0]["deviceMembers"] = (encoded[0]["deviceMembers"] as! [Any]).reversed().map { $0 }
        reversed[0]["pendingOperations"] = (encoded[0]["pendingOperations"] as! [Any]).reversed().map { $0 }
        let canonical = try SceneConfigurationPayload.canonical(encoded)
        let reordered = try SceneConfigurationPayload.canonical(reversed)
        precondition(canonical == reordered)
        var snapshotPayload = payload
        snapshotPayload["uuid"] = "space"; snapshotPayload["updateTimestamp"] = 1; snapshotPayload["schedules"] = []
        snapshotPayload["spaceData"] = ["sceneConfigurations": encoded]
        let snapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(snapshotPayload)!
        snapshotPayload["spaceData"] = ["sceneConfigurations": reversed]
        precondition(snapshot.properties == SpaceCloudNodeRemovalPolicy.Snapshot.make(snapshotPayload)!.properties,
            "member ordering must not conflict in cloud removal snapshots")
        let identity = config.deviceMembers[0].identity
        let replacement = SpaceCloudNodeRemovalPolicy.Instance(uuid: identity.nodeUUID, address: 1, keyFingerprint: String(repeating: "B", count: 64))
        precondition(SpaceCloudNodeRemovalPolicy.projectConfiguration(expected, removing: [replacement]) == expected)
        let original = SpaceCloudNodeRemovalPolicy.Instance(uuid: identity.nodeUUID, address: 1, keyFingerprint: identity.deviceKeyFingerprint)
        let removed = SpaceCloudNodeRemovalPolicy.projectConfiguration(expected, removing: [original])!
        let object = try JSONSerialization.jsonObject(with: removed) as! [String: Any]
        let after = try SceneConfigurationPayload.decode(object["sceneConfigurations"])[7]!
        precondition(after.deviceMembers.isEmpty && after.pendingOperations.isEmpty && after.revision == config.revision)
        print("PASS: strict version/number/identity/mode/metadata validation, stable ordering and original provisioning removal")
    }
    static func groupLoss() throws {
        let missing: [String: Any] = ["groups": [], "nodes": [], "scenes": [["number": "0007", "name": "Offline", "imageId": 3]]]
        let group: [String: Any] = ["address": "C001", "profile": ["id": "profile", "type": 1, "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 100, "vacantLevel": 50, "taskLevel": 100, "timeT1": 0, "timeT2": 30, "timeT3": 60, "timeT4": 0, "timeT5": 0, "manualOverrideTimeout": 600, "powerUpState": 0], "scenesDatas": [["sceneNumber": 7, "isOn": true, "lightness": 3456, "cct": 4567, "state": 1, "hue": 123, "saturation": 456]]]
        var grouped = missing; grouped["groups"] = [group]
        var editedGroup = group; var parameters = group["scenesDatas"] as! [[String: Any]]; parameters[0]["lightness"] = 999
        editedGroup["scenesDatas"] = parameters
        var edited = grouped; edited["groups"] = [editedGroup]
        precondition(SpaceConfigurationIntegrityPolicy.configurationData(grouped) != nil)
        precondition(SpaceConfigurationIntegrityPolicy.configurationData(grouped) != SpaceConfigurationIntegrityPolicy.configurationData(edited), "group expected parameters must be compared")
        print("PASS: scene field loss, lost task and changed group parameters are rejected")
    }
}
