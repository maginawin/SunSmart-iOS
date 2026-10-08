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
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(16)], version: 1)) == nil)
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
        print("PASS: complete Timed payload validation and canonical cloud comparison")
    }
}
