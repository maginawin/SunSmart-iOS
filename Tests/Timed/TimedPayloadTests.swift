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
            let binding = TimedSchedulerNodeSlot(identity: identity, slot: slot, state: .assigned)
            s["nodeSlots"] = try! JSONSerialization.jsonObject(with: JSONEncoder().encode([binding]))
        }
        return s
    }
    static func payload(_ schedules: [[String: Any]], version: Int = 2) -> [String: Any] {
        ["spaceData": ["timedSchemaVersion": version], "schedules": schedules,
         "nodes": [["uuid": uuid, "unicastAddress": "0001", "deviceKey": key]], "groups": [], "scenes": []]
    }
    static func legacyProfilePayload() {
        var profile = schedule(0)
        profile["selectTarget"] = 3; profile["sceneAddress"] = ""
        let oldWriter = payload([profile, schedule(16)], version: 1)
        let promoted = TimedSchedulerPayloadPolicy.fillingMissingBindings(oldWriter)
        precondition(TimedSchedulerPayloadPolicy.schema(promoted) == 2)
        precondition(TimedSchedulerPayloadPolicy.canonical(oldWriter) != nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(oldWriter) == TimedSchedulerPayloadPolicy.canonical(promoted))
        for target in [0, 1, 3] {
            var row = schedule(0)
            row["selectTarget"] = target
            row["sceneAddress"] = ""
            row["profiles"] = [["groupAddress": "C000", "profileSceneNumber": "FF00", "groupName": "Group 1", "type": 3]]
            let legacy = payload([row], version: 1)
            guard let expected = TimedSchedulerPayloadPolicy.canonical(legacy) else { preconditionFailure("legacy unused Scene sentinel") }
            row["sceneAddress"] = NSNull()
            precondition(TimedSchedulerPayloadPolicy.canonical(payload([row], version: 1)) == expected)
            row.removeValue(forKey: "sceneAddress")
            precondition(TimedSchedulerPayloadPolicy.canonical(payload([row], version: 1)) == expected)
            for bad: Any in ["", "no-scene", "0000", -1, true, "10000"] {
                row["sceneAddress"] = bad
                if bad as? String != "" { precondition(TimedSchedulerPayloadPolicy.canonical(payload([row], version: 1)) == nil) }
                row["selectTarget"] = 2
                precondition(TimedSchedulerPayloadPolicy.canonical(payload([row], version: 1)) == nil)
                row["selectTarget"] = target
            }
            row["sceneAddress"] = ""
            row["nodeSlots"] = [[String: Any]]()
            precondition(TimedSchedulerPayloadPolicy.canonical(payload([row])) == nil, "do not relax v2")
        }
    }

    static func ignoresLegacyGeneration() {
        let original = payload([schedule(300, slot: 0)])
        let expected = TimedSchedulerPayloadPolicy.canonical(original)!
        for value: Any in [UUID().uuidString, NSNull(), 42, ["bad": true], "invalid"] {
            var row = schedule(300, slot: 0)
            var slots = row["nodeSlots"] as! [[String: Any]]
            slots[0]["generation"] = value
            row["nodeSlots"] = slots
            let input = payload([row])
            precondition(TimedSchedulerPayloadPolicy.canonical(input) == expected,
                         "legacy generation of any type must be ignored")
            var rawSpace = input
            rawSpace["generation"] = "retain-space-generation"
            rawSpace["spaceData"] = ["timedSchemaVersion": 2, "generation": "retain-extension-generation"]
            let site: [String: Any] = ["spaces": [rawSpace], "generation": "retain-site-generation"]
            for api in [TimedUploadTestAPI.siteAdd(siteData: site, useDeivceAddressNum: 0),
                        .siteUpload(siteData: site), .spaceUpload(siteId: "site", spaceId: "space", spaceData: rawSpace)] {
                let request = try! JSONSerialization.jsonObject(with: JSONSerialization.data(withJSONObject: api.parameters)) as! [String: Any]
                let body = request["site"] as? [String: Any] ?? request
                let space = (body["spaces"] as! [[String: Any]])[0]
                let records = space["schedules"] as! [[String: Any]]
                precondition((records[0]["nodeSlots"] as! [[String: Any]])[0]["generation"] == nil)
                precondition(space["generation"] as? String == "retain-space-generation")
                precondition((space["spaceData"] as! [String: Any])["generation"] as? String == "retain-extension-generation")
                if request["site"] != nil { precondition(body["generation"] as? String == "retain-site-generation") }
            }
            let normalized = TimedSchedulerPayloadPolicy.repairingStaleBindings(input)!
            let output = normalized["schedules"] as! [[String: Any]]
            precondition((output[0]["nodeSlots"] as! [[String: Any]])[0]["generation"] == nil)
        }
        var row = schedule(300, slot: 0)
        var slots = row["nodeSlots"] as! [[String: Any]]
        slots[0].removeValue(forKey: "generation")
        row["nodeSlots"] = slots
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([row])) == expected)
    }

    static func v3PayloadRoundTrip() {
        var row = schedule(104)
        row["nodeSlots"] = [["identity": ["unicastAddress": "0001"], "slot": 3,
            "state": "pendingApply", "actionAddress": ["auto_on": "0002", "off": "0001", "recall": "0001"]]]
        var value = payload([row], version: 3)
        value["nodes"] = [["uuid": uuid, "unicastAddress": "0001", "deviceKey": key,
            "elements": [["index": 0, "models": [["modelId": "1206"], ["modelId": "1207"]]],
                         ["index": 1, "models": [["modelId": "130F"], ["modelId": "1206"], ["modelId": "1207"]]]]]]
        guard let canonical = TimedSchedulerPayloadPolicy.canonical(value) else {
            preconditionFailure("v3: valid pendingApply must retain its node slot through import")
        }
        let envelope = TimedSchedulerPayloadPolicy.backupEnvelope(value)!
        precondition(envelope["formatVersion"] as? Int == 3)
        let restored = TimedSchedulerPayloadPolicy.backupPayload(envelope)!
        precondition(TimedSchedulerPayloadPolicy.canonical(restored) == canonical)
        precondition(TimedSchedulerPayloadPolicy.normalizedComparison(canonical) == canonical)
        var legacy = value
        legacy["spaceData"] = ["timedSchemaVersion": 2]
        var legacyRow = schedule(104, slot: 3)
        legacyRow["needDeleteNodeAddresses"] = ["0001"]
        legacy["schedules"] = [legacyRow]
        let migrated = TimedSchedulerPayloadPolicy.migratingLegacyPayload(legacy)!
        let migratedRow = (migrated["schedules"] as! [[String: Any]])[0]
        let migratedSlot = (migratedRow["nodeSlots"] as! [[String: Any]])[0]
        precondition(migratedSlot["state"] as? String == "pendingApply")
        precondition((migratedSlot["actionAddress"] as! [String: String])["auto_on"] == "0001", "no Group uses ordinary Scheduler")
        precondition(migratedRow["needDeleteNodeAddresses"] == nil)
        legacyRow["nodeSlots"] = [[String: Any]]()
        legacy["schedules"] = [legacyRow]
        precondition(TimedSchedulerPayloadPolicy.migratingLegacyPayload(legacy) == nil, "do not invent an old cleanup slot")
        legacyRow["needDeleteNodeAddresses"] = [String]()
        legacy["schedules"] = [legacyRow]
        precondition(TimedSchedulerPayloadPolicy.migratingLegacyPayload(legacy) != nil, "v2 unassigned remains unassigned")
        let localRows = TimedSchedulerPayloadPolicy.decodingSchedules(value)!
        let localSlots = try! JSONDecoder().decode([TimedSchedulerNodeSlot].self,
            from: JSONSerialization.data(withJSONObject: localRows[0]["nodeSlots"]!))
        precondition(localSlots[0].identity.nodeUUID == uuid && localSlots[0].isV3)
        var local = value
        local["schedules"] = localRows
        var nodes = local["nodes"] as! [[String: Any]]
        nodes[0]["schedules"] = [["id": 3]]
        nodes[0]["custProps"] = ["schedulerModelStates": ["invalid": true], "keep": 7]
        local["nodes"] = nodes
        let exported = TimedSchedulerPayloadPolicy.exportPayload(local)!
        precondition(TimedSchedulerPayloadPolicy.canonical(exported) == canonical)
        precondition(((exported["nodes"] as! [[String: Any]])[0]["custProps"] as! [String: Any])["keep"] as? Int == 7)
        nodes[0]["deviceKey"] = String(repeating: "2", count: 32)
        local["nodes"] = nodes
        precondition(TimedSchedulerPayloadPolicy.exportPayload(local) == nil, "never rebind to a reused address")
        for field in ["needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"] {
            for extra: Any in [[], ["FFFF"], NSNull(), "legacy", 42, ["unknown": true]] {
                var mixed = value, mixedRow = row
                mixedRow[field] = extra
                mixed["schedules"] = [mixedRow]
                precondition(TimedSchedulerPayloadPolicy.canonical(mixed) == canonical)
                precondition(TimedSchedulerPayloadPolicy.decodingSchedules(mixed)![0][field] == nil,
                             "retired cleanup fields must not reach the Schedule decoder")
            }
        }
        for extra: Any in [[], [["id": 4]], NSNull(), "legacy", 42, ["schemaVersion": 99]] {
            var mixed = value, mixedNodes = value["nodes"] as! [[String: Any]]
            mixedNodes[0]["schedules"] = extra
            mixedNodes[0]["custProps"] = ["schedulerModelStates": extra, "keep": 7]
            mixed["nodes"] = mixedNodes
            let normalized = TimedSchedulerPayloadPolicy.repairingStaleBindings(mixed)!
            let normalizedNode = (normalized["nodes"] as! [[String: Any]])[0]
            precondition(normalizedNode["schedules"] == nil)
            precondition((normalizedNode["custProps"] as! [String: Any])["schedulerModelStates"] == nil)
            precondition((normalizedNode["custProps"] as! [String: Any])["keep"] as? Int == 7)
            precondition(TimedSchedulerPayloadPolicy.canonical(mixed) == canonical)
            precondition(TimedSchedulerPayloadPolicy.canonical(TimedSchedulerPayloadPolicy.backupPayload(
                TimedSchedulerPayloadPolicy.backupEnvelope(mixed)!)!) == canonical)
            precondition(NSDictionary(dictionary: normalized).isEqual(to: TimedSchedulerPayloadPolicy.fillingMissingBindings(normalized)))
        }
        for location in ["binding", "identity", "actionAddress"] {
            var mixed = value, mixedRow = row
            var bindings = row["nodeSlots"] as! [[String: Any]]
            if location == "binding" { bindings[0]["serverOnly"] = ["anything": NSNull()] }
            else {
                var nested = bindings[0][location] as! [String: Any]
                nested["serverOnly"] = ["anything": NSNull()]
                if location == "identity" {
                    nested["nodeUUID"] = "obsolete"
                    nested["deviceKeyFingerprint"] = 42
                }
                bindings[0][location] = nested
            }
            mixedRow["nodeSlots"] = bindings; mixed["schedules"] = [mixedRow]
            precondition(TimedSchedulerPayloadPolicy.canonical(mixed) == canonical)
            let decoded = TimedSchedulerPayloadPolicy.decodingSchedules(mixed)!
            let local = try! JSONDecoder().decode([TimedSchedulerNodeSlot].self,
                from: JSONSerialization.data(withJSONObject: decoded[0]["nodeSlots"]!))
            precondition(local[0].identity.nodeUUID == uuid, "only the complete Node supplies the local identity")
            var invalid = mixed, invalidRow = mixedRow
            bindings[0]["slot"] = true; invalidRow["nodeSlots"] = bindings; invalid["schedules"] = [invalidRow]
            precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil, "extras never hide invalid required data")
        }
        for state in ["assigned", "unknown", "", "pendingRemoval", "synced"] {
            var candidate = value, candidateRow = row
            var bindings = row["nodeSlots"] as! [[String: Any]]
            bindings[0]["state"] = state
            candidateRow["nodeSlots"] = bindings; candidate["schedules"] = [candidateRow]
            precondition((TimedSchedulerPayloadPolicy.canonical(candidate) != nil) == ["pendingRemoval", "synced"].contains(state))
        }
        for route in ["0003", "0000", "8000", "1"] {
            var invalid = value, badRow = row
            var bindings = row["nodeSlots"] as! [[String: Any]]
            bindings[0]["actionAddress"] = ["auto_on": route, "off": "0001", "recall": "0001"]
            badRow["nodeSlots"] = bindings; invalid["schedules"] = [badRow]
            precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil)
        }
        for field in ["identity", "slot", "state", "actionAddress"] {
            for absent in [true, false] {
                var invalid = value, badRow = row
                var bindings = row["nodeSlots"] as! [[String: Any]]
                bindings[0][field] = absent ? nil : NSNull()
                badRow["nodeSlots"] = bindings; invalid["schedules"] = [badRow]
                precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil, "v3 binding fields are required")
            }
        }
        for absent in [true, false] {
            var invalid = value, badRow = row
            badRow["nodeSlots"] = absent ? nil : NSNull()
            invalid["schedules"] = [badRow]
            precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil, "native v3 cannot default to unassigned")
        }
        var conflicting = value, duplicate = row
        duplicate["id"] = 105
        conflicting["schedules"] = [row, duplicate]
        precondition(TimedSchedulerPayloadPolicy.canonical(conflicting) == nil, "one physical slot has one owner")
        for (profile, exit, hasLC, expected) in [(3, 0, true, "0002"), (6, 0, true, "0001"),
                                                 (3, 2, true, "0001"), (3, 0, false, "0001")] {
            var old = legacy
            old["schedules"] = [schedule(104, slot: 3)]
            var node = (value["nodes"] as! [[String: Any]])[0]
            node["groupAddress"] = "C001"; node["groupState"] = exit
            if !hasLC { node["elements"] = Array((node["elements"] as! [[String: Any]]).prefix(1)) }
            old["nodes"] = [node]; old["groups"] = [["address": "C001", "profile": ["type": profile]]]
            let result = TimedSchedulerPayloadPolicy.migratingLegacyPayload(old)!
            let resultRow = (result["schedules"] as! [[String: Any]])[0]
            let resultSlot = (resultRow["nodeSlots"] as! [[String: Any]])[0]
            precondition((resultSlot["actionAddress"] as! [String: String])["auto_on"] == expected,
                         "migration preserves Group routing and actual LC availability")
        }
        print("PASS: v3 address-only pending binding and versioned backup round trip")
    }

    static func main() {
        v3PayloadRoundTrip()
        ignoresLegacyGeneration()
        legacyProfilePayload()
        missingV2Bindings()
        let old = payload([schedule(0), schedule(15)], version: 1)
        precondition(TimedSchedulerPayloadPolicy.canonical(old) != nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(16)], version: 1)) != nil)
        let fresh = payload([schedule(300, slot: 0), schedule(500, slot: 1)])
        let canonical = TimedSchedulerPayloadPolicy.canonical(fresh)!
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(500, slot: 1), schedule(300, slot: 0)])) == canonical)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(300, slot: 0), schedule(500, slot: 0)])) == nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(300, slot: 16)])) == nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([schedule(0)])) != nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([], version: 4)) == nil)
        var changed = schedule(300, slot: 0); changed["minute"] = 5
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([changed, schedule(500, slot: 1)])) != canonical)
        changed["minute"] = 70
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([changed])) == nil)
        var reprovisioned = fresh; reprovisioned["nodes"] = [["uuid": uuid, "unicastAddress": "0001", "deviceKey": String(repeating: "2", count: 32)]]
        precondition(TimedSchedulerPayloadPolicy.canonical(reprovisioned) != nil)
        staleInstanceRepair()
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
        if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--stale-snapshot" {
            let data = try! Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]))
            let response = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
            let source = response["data"] as! [String: Any]
            let result = TimedSchedulerPayloadPolicy.repairingStaleBindings(source)!
            let before = source["schedules"] as! [[String: Any]], after = result["schedules"] as! [[String: Any]]
            let removed = zip(before, after).reduce(0) { $0 + ($1.0["nodeSlots"] as! [Any]).count - ($1.1["nodeSlots"] as! [Any]).count }
            precondition(before.count == after.count && removed > 0)
            precondition(TimedSchedulerPayloadPolicy.canonical(source) == TimedSchedulerPayloadPolicy.canonical(result))
            precondition(TimedSchedulerPayloadPolicy.canonical(result) != nil)
            var originalWithoutSchedules = source, repairedWithoutSchedules = result
            originalWithoutSchedules.removeValue(forKey: "schedules"); repairedWithoutSchedules.removeValue(forKey: "schedules")
            precondition(json(originalWithoutSchedules) == json(repairedWithoutSchedules))
            print("PASS: private snapshot retains \(after.count) schedules and all non-schedule data; removes \(removed) obsolete bindings")
        } else if CommandLine.arguments.count > 1 {
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

    static func staleInstanceRepair() {
        let original = payload((0..<16).map { schedule($0, slot: $0) })
        for replacement in [
            [[String: Any]](),
            [["uuid": uuid, "unicastAddress": "0005", "deviceKey": String(repeating: "2", count: 32)]],
            [["uuid": uuid, "unicastAddress": "0001", "deviceKey": String(repeating: "2", count: 32)]],
            [["uuid": "22222222-2222-2222-2222-222222222222", "unicastAddress": "0001", "deviceKey": key]]
        ] {
            var stale = original; stale["nodes"] = replacement
            let repaired = TimedSchedulerPayloadPolicy.repairingStaleBindings(stale)!
            let schedules = repaired["schedules"] as! [[String: Any]]
            precondition(schedules.count == 16)
            precondition(schedules.allSatisfy { ($0["nodeSlots"] as! [Any]).isEmpty && ($0["deviceAddresses"] as! [String]).isEmpty })
            for (old, new) in zip(original["schedules"] as! [[String: Any]], schedules) {
                var expected = old; expected["nodeSlots"] = [Any](); expected["deviceAddresses"] = [String]()
                precondition(json(expected) == json(new), "only obsolete device references may change")
            }
            precondition(TimedSchedulerPayloadPolicy.canonical(stale) == TimedSchedulerPayloadPolicy.canonical(repaired))
            precondition(TimedSchedulerPayloadPolicy.canonical(repaired) != nil)
            precondition(json(TimedSchedulerPayloadPolicy.repairingStaleBindings(repaired)!) == json(repaired))
            let backup = TimedSchedulerPayloadPolicy.backupEnvelope(stale)!
            precondition(json(TimedSchedulerPayloadPolicy.backupPayload(backup)!) == json(repaired))
        }
        let current = ["uuid": "22222222-2222-2222-2222-222222222222", "unicastAddress": "0001", "deviceKey": key]
        let newBinding = TimedSchedulerNodeSlot(identity: TimedSchedulerPayloadPolicy.identity(node: current)!, slot: 0, state: .assigned)
        var mixed = schedule(0, slot: 0)
        var bindings = mixed["nodeSlots"] as! [[String: Any]]
        bindings[0]["state"] = "pendingRemoval"
        bindings.append(try! JSONSerialization.jsonObject(with: JSONEncoder().encode(newBinding)) as! [String: Any])
        mixed["nodeSlots"] = bindings; mixed["needDeleteNodeAddresses"] = ["0001"]
        mixed["groupAddresses"] = ["C001"]; mixed["sceneAddress"] = "0001"
        var input = payload([mixed]); input["nodes"] = [current]
        let repaired = TimedSchedulerPayloadPolicy.repairingStaleBindings(input)!
        let retained = (repaired["schedules"] as! [[String: Any]])[0]
        precondition((retained["nodeSlots"] as! [Any]).count == 1)
        for field in ["deviceAddresses", "needDeleteNodeAddresses", "groupAddresses", "sceneAddress"] {
            precondition(json(["value":retained[field]!]) == json(["value":mixed[field]!]), "a current explicit binding survives address reuse")
        }
        input["nodes"] = [[String: Any]]()
        let empty = (TimedSchedulerPayloadPolicy.repairingStaleBindings(input)!["schedules"] as! [[String: Any]])[0]
        precondition((empty["needDeleteNodeAddresses"] as! [Any]).isEmpty)
        precondition(empty["sceneAddress"] as? String == "0001" && empty["groupAddresses"] as? [String] == ["C001"])
        var invalid = original; invalid["nodes"] = [["uuid":uuid,"unicastAddress":"0001","deviceKey":"invalid"]]
        precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil, "malformed current identities are not deletion proof")
        invalid = original; invalid["nodes"] = (original["nodes"] as! [[String: Any]]) + (original["nodes"] as! [[String: Any]])
        precondition(TimedSchedulerPayloadPolicy.canonical(invalid) == nil)
        for field in ["slot", "state"] {
            var bad = bindings[0]; bad[field] = field == "slot" ? 16 : "invalid"
            var s = mixed; s["nodeSlots"] = [bad]
            var p = payload([s]); p["nodes"] = [[String: Any]]()
            precondition(TimedSchedulerPayloadPolicy.canonical(p) == nil, "corrupt stale bindings must still fail")
        }
        precondition(json(TimedSchedulerPayloadPolicy.repairingStaleBindings(original)!) == json(original))
        print("PASS: absent/reprovisioned nodes, reused addresses, pending removal, empty targets, backup round trip, idempotence and invalid identities")
    }
    static func missingV2Bindings() {
        let assigned = schedule(0, slot: 0)
        let missing = schedule(3)
        var null = schedule(4); null["nodeSlots"] = NSNull()
        var empty = schedule(5); empty["nodeSlots"] = [[String: Any]]()
        let rows = [null, assigned, missing, empty]
        let source = payload(rows)
        let normalized = TimedSchedulerPayloadPolicy.fillingMissingBindings(source)
        let restored = normalized["schedules"] as! [[String: Any]]
        precondition(restored.map { $0["id"] as! Int } == [4, 0, 3, 5])
        precondition(json(restored[1]) == json(assigned) && json(restored[3]) == json(empty))
        for index in [0, 2] {
            precondition((restored[index]["nodeSlots"] as? [Any])?.isEmpty == true)
            var originalFields = restored[index]
            originalFields["nodeSlots"] = rows[index]["nodeSlots"]
            precondition(json(originalFields) == json(rows[index]), "defaulting must preserve all other fields")
        }
        let canonical = TimedSchedulerPayloadPolicy.canonical(source)!
        precondition(canonical == TimedSchedulerPayloadPolicy.canonical(normalized))
        precondition(json(TimedSchedulerPayloadPolicy.fillingMissingBindings(normalized)) == json(normalized))
        let backup = TimedSchedulerPayloadPolicy.backupEnvelope(source)!
        precondition(TimedSchedulerPayloadPolicy.canonical(TimedSchedulerPayloadPolicy.backupPayload(backup)!) == canonical)
        for value: Any in [NSNull(), [[String: Any]]()] {
            var stripped = normalized, strippedRows = restored
            strippedRows[1]["nodeSlots"] = value; stripped["schedules"] = strippedRows
            precondition(TimedSchedulerPayloadPolicy.canonical(stripped) != canonical,
                         "lost assigned bindings cannot confirm the uploaded configuration")
        }
        for bad: Any in ["invalid", 0, false, ["slot": 0], [0], [["slot": 0]]] {
            var row = missing; row["nodeSlots"] = bad
            precondition(TimedSchedulerPayloadPolicy.canonical(payload([row])) == nil)
        }
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([missing, missing])) == nil)
        var invalid = missing; invalid["hour"] = 25
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([invalid])) == nil)
        invalid = missing; invalid["selectTarget"] = 99
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([invalid])) == nil)
        let legacy = payload([missing], version: 1)
        precondition(json(TimedSchedulerPayloadPolicy.fillingMissingBindings(legacy)) == json(legacy))
        precondition(TimedSchedulerPayloadPolicy.canonical(legacy) != nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([null], version: 1)) == nil)
        precondition(TimedSchedulerPayloadPolicy.canonical(payload([null, missing], version: 3)) == nil)
        let occupied = schedule(1, slot: 1)
        let identity = TimedSchedulerPayloadPolicy.identity(node: (source["nodes"] as! [[String: Any]])[0])!
        let binding = try! JSONDecoder().decode([TimedSchedulerNodeSlot].self, from: json(occupied["nodeSlots"]!))[0]
        let intents: [TimedSchedulerSlotPolicy.Intent] = [
            .init(scheduleID: 1, targetsNode: true, legacy: false, binding: binding),
            .init(scheduleID: 3, targetsNode: true, legacy: false, binding: nil)]
        let plan = try! TimedSchedulerSlotPolicy.plan(identity: identity, intents: intents, observedSlots: [0, 1, 2, 3])
        precondition(plan[1] == binding && plan[3]?.slot == 4, "unassigned records cannot infer slot=id or overwrite observed slots")
        print("PASS: v2 missing/null bindings preserve mixed records, backup and receipt semantics, legacy rules and occupied slots")
    }
    static func json(_ value: Any) -> Data {
        try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
