import Foundation

@main struct TimedPayloadTests {
    static let uuid = "11111111-1111-1111-1111-111111111111"
    static let key = String(repeating: "1", count: 32)
    static func schedule(_ id: Int, slot: Int? = nil) -> [String: Any] {
        var s: [String: Any] = ["id": id, "name": "Schedule \(id)", "enabled": true, "selectTarget": 1,
            "action": 1, "fadeTime": 0, "hour": 8, "minute": 0, "dayOfWeek": 127,
            "deviceAddresses": ["0001"], "groupAddresses": [], "sceneAddress": NSNull()]
        if let slot {
            let identity = TimedSchedulerPayloadPolicy.identity(node: ["uuid": uuid, "unicastAddress": "0001", "deviceKey": key])!
            let binding = TimedSchedulerNodeSlot(identity: identity, slot: slot, state: .assigned,
                generation: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!)
            s["nodeSlots"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode([binding]))
        }
        return s
    }
    static func payload(_ schedules: [[String: Any]], version: Int = 2) -> [String: Any] {
        ["spaceData": ["timedSchemaVersion": version], "schedules": schedules,
         "nodes": [["uuid": uuid, "unicastAddress": "0001", "deviceKey": key]], "groups": [], "scenes": []]
    }
    static func main() {
        let old = payload([schedule(0), schedule(15)], version: 1)
        precondition(TimedSchedulerPayloadPolicy.canonical(old) != nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(16)], version: 1)) != nil)
        let fresh = payload([schedule(300, slot: 0), schedule(500, slot: 1)])
        let canonical = TimedSchedulerPayloadPolicy.canonical(fresh)!
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(500, slot: 1), schedule(300, slot: 0)])) == canonical)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(300, slot: 0), schedule(500, slot: 0)])) == nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(300, slot: 16)])) == nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(0)])) == nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([], version: 3)) == nil)
        var changed = schedule(300, slot: 0); changed["minute"] = 5
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([changed, schedule(500, slot: 1)])) != canonical)
        changed["minute"] = 70
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([changed])) == nil)
        var corruptIdentity = fresh; corruptIdentity["nodes"] = [["uuid": uuid, "unicastAddress": "0001", "deviceKey": String(repeating: "2", count: 32)]]
        precondition(TimedSchedulerPayloadPolicy.canonical(corruptIdentity) == nil)
        var pending = schedule(300, slot: 0); pending["needDeleteNodeAddresses"] = ["0001"]
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([pending, schedule(500, slot: 1)])) != canonical)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([])) != nil)
        var twoDevices = payload([])
        let second: [String: Any] = ["uuid": "22222222-2222-2222-2222-222222222222", "unicastAddress": "0005", "deviceKey": key]
        twoDevices["nodes"] = (twoDevices["nodes"] as! [[String: Any]]) + [second]
        let identity = TimedSchedulerPayloadPolicy.identity(node: second)!
        let records = (0..<32).map { id -> [String: Any] in
            var record = schedule(id, slot: id % 16)
            if id >= 16 {
                record["deviceAddresses"] = ["0005"]
                let binding = TimedSchedulerNodeSlot(identity: identity, slot: id % 16, state: .assigned)
                record["nodeSlots"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode([binding]))
            }
            return record
        }
        twoDevices["schedules"] = records
        let full = TimedSchedulerPayloadPolicy.canonical(twoDevices)!
        let encoded = try! JSONSerialization.data(withJSONObject: twoDevices)
        let imported = try! JSONSerialization.jsonObject(with: encoded) as! [String: Any]
        precondition(TimedSchedulerPayloadPolicy.canonical(imported) == full)
        twoDevices["schedules"] = Array(records.reversed())
        precondition(TimedSchedulerPayloadPolicy.canonical(twoDevices) == full)
        let backup = TimedSchedulerPayloadPolicy.backupEnvelope(twoDevices)!
        precondition(backup["schedules"] == nil && backup["uuid"] == nil,
                     "v2 files must not look like editable legacy Space payloads")
        precondition(TimedSchedulerPayloadPolicy.canonical(TimedSchedulerPayloadPolicy.backupPayload(backup)!) == full)
        precondition(TimedSchedulerPayloadPolicy.backupPayload(twoDevices) == nil,
                     "v2 files require an explicit envelope")
        precondition(TimedSchedulerPayloadPolicy.backupPayload(old) != nil)
        var futureBackup = backup; futureBackup["formatVersion"] = 3
        precondition(TimedSchedulerPayloadPolicy.backupPayload(futureBackup) == nil)
        // Reproduce an old client's full write: logical IDs survive, while
        // the schema and all per-node bindings are omitted.
        var damaged = twoDevices
        damaged["spaceData"] = ["proximityLightingSchemaVersion": 1, "triggerZones": []]
        damaged["schedules"] = Array(records.prefix(17)).map { item -> [String: Any] in
            var item = item; item.removeValue(forKey: "nodeSlots"); return item
        }
        let repaired = TimedSchedulerPayloadPolicy.fillingMissingBindings(damaged)
        let retained = repaired["schedules"] as! [[String: Any]]
        precondition(retained.count == 17 && retained.allSatisfy { ($0["nodeSlots"] as? [Any])?.isEmpty == true })
        var withoutDefaults = repaired
        withoutDefaults["spaceData"] = damaged["spaceData"]
        withoutDefaults["schedules"] = retained.map { item -> [String: Any] in
            var item = item; item.removeValue(forKey: "nodeSlots"); return item
        }
        precondition(json(withoutDefaults) == json(damaged), "defaults must retain every original field")
        let repairedEvidence = TimedSchedulerPayloadPolicy.canonical(repaired)!
        precondition(TimedSchedulerPayloadPolicy.schema(damaged) == 2)
        precondition(TimedSchedulerPayloadPolicy.canonical(damaged) == repairedEvidence,
                     "raw GET, normalized import and exported defaults use identical receipt evidence")
        precondition(json(TimedSchedulerPayloadPolicy.fillingMissingBindings(repaired)) == json(repaired))
        precondition(json(TimedSchedulerPayloadPolicy.fillingMissingBindings(old)) == json(old))
        precondition(json(TimedSchedulerPayloadPolicy.fillingMissingBindings(fresh)) == json(fresh))
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([])) != repairedEvidence)
        let repairedBackup = TimedSchedulerPayloadPolicy.backupEnvelope(damaged)!
        precondition(TimedSchedulerPayloadPolicy.canonical(TimedSchedulerPayloadPolicy.backupPayload(repairedBackup)!) == repairedEvidence)
        precondition(TimedSchedulerPayloadPolicy.canonical(TimedSchedulerPayloadPolicy.backupPayload(damaged)!) == repairedEvidence)
        for field in ["hour", "id", "nodeSlots"] {
            var invalid = damaged, rows = damaged["schedules"] as! [[String: Any]]
            rows[0][field] = field == "nodeSlots" ? NSNull() : -1
            invalid["schedules"] = rows
            precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil)
        }
        for version: Any in [NSNull(), 3] {
            var invalid = damaged; invalid["spaceData"] = ["timedSchemaVersion": version]
            precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil)
        }
        var duplicate = damaged, duplicateRows = retained
        duplicateRows[16]["id"] = 0; duplicate["schedules"] = duplicateRows
        duplicate["spaceData"] = ["timedSchemaVersion": 2]
        precondition(TimedSchedulerPayloadPolicy.canonical(duplicate) == nil)
        var overCapacity = repaired
        overCapacity["schedules"] = retained.map { item -> [String: Any] in
            var item = item; item["deviceAddresses"] = ["0001"]; return item
        }
        precondition(TimedSchedulerPayloadPolicy.canonical(overCapacity) == nil)
        if CommandLine.arguments.count > 1 {
            let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
            let response = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let source = response["data"] as! [String: Any]
            let result = TimedSchedulerPayloadPolicy.fillingMissingBindings(source)
            let rows = result["schedules"] as! [[String: Any]]
            precondition(rows.count == 17 && rows.allSatisfy { ($0["nodeSlots"] as? [Any])?.isEmpty == true })
            precondition(TimedSchedulerPayloadPolicy.canonical(result) != nil)
            precondition(TimedSchedulerPayloadPolicy.canonical(source) == TimedSchedulerPayloadPolicy.canonical(result))
            precondition(json(result["nodes"]!) == json(source["nodes"]!))
            print("PASS: private snapshot retains all 17 schedules and physical snapshots with unassigned defaults")
        }
        print("PASS: legacy-writer reproduction, default filling, stable round trip and malformed data rejection")
        print("PASS: complete Timed payload validation and canonical cloud comparison")
    }
    static func json(_ value: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
