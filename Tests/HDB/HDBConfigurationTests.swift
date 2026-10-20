import Foundation

@main enum HDBConfigurationTests {
    static func main() throws {
        try schemaAndMACValidation()
        try modelArrayContract()
        for path in CommandLine.arguments.dropFirst() {
            let config = try JSONDecoder().decode(HDBConfiguration.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
            try HDBLightingZonePolicy.validate(config)
            let encoded = try JSONEncoder().encode(config)
            let roundTrip = try JSONDecoder().decode(HDBConfiguration.self, from: encoded)
            precondition(roundTrip == config)
            precondition(config.devices.allSatisfy { [.pending, .synced].contains($0.lightingZonesStatus) })
            let json = try JSONSerialization.jsonObject(with: encoded) as! [String: Any]
            for device in json["devices"] as! [[String: Any]] {
                precondition((device["lightingZones"] as! [[String: Any]]).allSatisfy { Set($0.keys) == ["zoneId"] })
            }
        }
        let uuid = UUID()
        let zones = (1...9).map { HDBLightingZone(zoneId: $0, name: "Zone \($0)", groupAddress: UInt16(0xC000 + $0)) }
        let models = [UInt16(0x130F), 0x1310, 0x1000, 0x1300].map {
            HDBModelTarget(elementAddress: 1, modelIdentifier: $0, companyIdentifier: nil)
        } + [HDBModelTarget(elementAddress: 1, modelIdentifier: 1, companyIdentifier: 0x0A78),
             HDBModelTarget(elementAddress: 2, modelIdentifier: 0x1000, companyIdentifier: nil)]
        var device = HDBDeviceConfiguration(nodeUuid: uuid, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF",
            lightingZones: (1...8).map { HDBZoneMembership(zoneId: $0) })
        device.zoneModels = HDBLightingZonePolicy.zoneTargets(from: models, primaryAddress: 1).map(HDBModelReference.init)
        device.sensorGroupModels = HDBLightingZonePolicy.sensorGroupTargets(from: models).map(HDBModelReference.init)
        let original = HDBConfiguration(lightingZones: zones, devices: [device])
        let replacement = try HDBLightingZonePolicy.replacingZones(Array(2...9), for: device, in: original)
        let result = replacement.devices[0]
        precondition(result.lightingZones.map(\.zoneId) == Array(2...9),
                     "Set must retain only the full target, without removal history")
        precondition(result.lightingZonesStatus == .pending)
        let failed = replacement
        let data = try JSONEncoder().encode(failed)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let jsonDevice = (json["devices"] as! [[String: Any]])[0]
        precondition(jsonDevice["mac"] as? String == "AA:BB:CC:DD:EE:FF" && jsonDevice["nodeAddress"] as? Int == 1)
        let decoded = try JSONDecoder().decode(HDBConfiguration.self, from: data)
        precondition(decoded == failed)
        precondition(HDBLightingZonePolicy.get(uuid, in: failed) == failed.devices[0])
        for invalid in [Array(1...9), [1, 1], [10]] {
            do { _ = try HDBLightingZonePolicy.replacingZones(invalid, for: device, in: original); fatalError("accepted invalid target") }
            catch is HDBConfigurationError {}
        }
        let cleared = try HDBLightingZonePolicy.replacingZones([], for: result, in: failed)
        precondition(cleared.devices[0].lightingZones.isEmpty && cleared.devices[0].lightingZonesStatus == .pending)
        let targets = try HDBLightingZonePolicy.requiredTargets(from: models + models)
        precondition(targets.count == 6)
        let reversed = try HDBLightingZonePolicy.requiredTargets(from: models.reversed())
        precondition(reversed == targets)
        do { _ = try HDBLightingZonePolicy.requiredTargets(from: models.filter { $0.companyIdentifier == nil }); fatalError("missing vendor accepted") }
        catch HDBConfigurationError.unsupportedModels {}
        let operations = try HDBLightingZonePolicy.operations(for: result, in: replacement, targets: targets)
        precondition(operations.map(\.stage) == [.reset, .add])
        precondition(operations[0].subscriptions.allSatisfy { $0.command == .deleteAll && $0.address == 0 })
        precondition(operations[1].subscriptions.count == 40 && operations[1].isLast)
        let clearOperations = try HDBLightingZonePolicy.operations(for: cleared.devices[0], in: cleared, targets: targets)
        precondition(clearOperations.count == 1 && clearOperations[0].isLast)
        precondition(clearOperations[0].subscriptions.allSatisfy { $0.command == .deleteAll && $0.address == 0 })
        precondition(clearOperations[0].subscriptions.first!.parameters.count == 4)
        var sensorConfig = cleared
        sensorConfig.devices[0].sensorGroupId = 0xC020
        let sensors = targets.filter { [0x130F, 0x1310, 0x1000].contains($0.modelIdentifier) && $0.elementAddress == 1 }
        let sensorClear = try HDBLightingZonePolicy.operations(for: sensorConfig.devices[0], in: sensorConfig, targets: targets, sensorTargets: sensors)
        precondition(sensorClear.map(\.stage) == [.reset, .sensor])
        precondition(sensorClear[0].subscriptions.count == 5 && sensorClear[0].subscriptions.allSatisfy { $0.command == .deleteAll })
        precondition(sensorClear[1].subscriptions.count == 3 && sensorClear[1].subscriptions.allSatisfy { $0.command == .add && $0.address == 0xC020 })
        sensorConfig = try HDBLightingZonePolicy.replacingZones([2, 1], for: sensorConfig.devices[0], in: sensorConfig)
        let sensorSet = try HDBLightingZonePolicy.operations(for: sensorConfig.devices[0], in: sensorConfig, targets: targets, sensorTargets: sensors)
        precondition(sensorSet.map(\.stage) == [.reset, .sensor, .add])
        precondition(sensorSet[0].subscriptions.allSatisfy { $0.command == .deleteAll })
        precondition(sensorSet[2].subscriptions.map(\.address) == Array(repeating: 0xC001, count: 5) + Array(repeating: 0xC002, count: 5))
        try HDBLightingZonePolicy.complete(sensorSet[0], in: &sensorConfig)
        precondition(sensorConfig.devices[0].lightingZonesStatus == .pending)
        try HDBLightingZonePolicy.complete(sensorSet[2], in: &sensorConfig)
        precondition(sensorConfig.devices[0].lightingZonesStatus == .synced)
        let completed = try HDBLightingZonePolicy.operations(for: sensorConfig.devices[0], in: sensorConfig, targets: targets, sensorTargets: sensors)
        precondition(completed.isEmpty)
        sensorConfig.devices[0].lightingZones = []
        precondition(!HDBLightingZonePolicy.matches(sensorSet[2].plan, in: sensorConfig))
        let desired = targets.map { HDBPreparationTarget(model: $0) }
        let encodedTargets = try JSONSerialization.jsonObject(with: JSONEncoder().encode(desired)) as! [[String: Any]]
        precondition(encodedTargets.count == 6)
        for target in encodedTargets {
            precondition(target["modelIdentifier"] == nil && target["companyIdentifier"] == nil && target["model"] == nil)
            let modelId = target["modelId"] as! String
            switch modelId {
            case "130F":
                precondition(NSDictionary(dictionary: target["value"] as! [String: Any]).isEqual(to: ["occupancyMode": true, "mode": true]))
            case "1310":
                precondition((target["value"] as! [String: Any])["prolongTimeMilliseconds"] as? Int == 0xFFFFFE)
            case "0A780001":
                let value = target["value"] as! [String: Any]
                let timeout = value["manualOverrideTimeout"] as! [String: Any]
                precondition(value["manualControlEnabled"] as? Bool == false && value["lightAutoAdjustEnabled"] as? Bool == false)
                precondition(timeout["enabled"] as? Bool == true && timeout["state"] as? String == "standby")
                precondition(timeout["intervalMilliseconds"] as? UInt32 == UInt32.max)
            case "1000", "1300": precondition(target["value"] == nil)
            default: fatalError("unexpected modelId: \(modelId)")
            }
        }
        let payload = try HDBLightingZonePolicy.json(replacement)
        let roundtrip = try HDBLightingZonePolicy.decode(payload: ["spaceData": ["hdb": payload]])
        precondition(roundtrip == replacement)
        let invalidTargets: [[String: Any]] = [
            ["elementAddress": 1, "modelIdentifier": 0x130F, "value": ["occupancyMode": true, "mode": true]],
            ["elementAddress": 1, "modelId": 0x130F, "value": ["occupancyMode": true, "mode": true]],
            ["elementAddress": 1, "modelId": "130F"],
            ["elementAddress": 1, "modelId": "130F", "value": ["occupancyMode": true]],
            ["elementAddress": 1, "modelId": "1310", "value": ["prolongTimeMilliseconds": 0xFFFFFF]],
            ["elementAddress": 1, "modelId": "1310", "value": ["prolongTimeMilliseconds": 0x1000000]],
            ["elementAddress": 1, "modelId": "1000", "value": ["mode": true]],
            ["elementAddress": 0, "modelId": "1300"],
            ["elementAddress": 1, "modelId": "ZZZZ"],
        ]
        for invalid in invalidTargets {
            do {
                _ = try JSONDecoder().decode(HDBPreparationTarget.self, from: JSONSerialization.data(withJSONObject: invalid))
                fatalError("invalid target accepted: \(invalid)")
            } catch {}
        }
        let reapplied = try HDBLightingZonePolicy.replacingZones(Array(1...8), for: device, in: original)
        precondition(reapplied.devices[0].lightingZonesStatus == .pending)
        print("PASS: HDB JSON, full target replay and empty target recovery, limits, all model instances and local Get")
    }

    static func modelArrayContract() throws {
        func target(_ address: UInt16, _ id: UInt32) -> HDBModelTarget {
            .init(elementAddress: address, modelIdentifier: UInt16(id & 0xFFFF), companyIdentifier: id > 0xFFFF ? UInt16(id >> 16) : nil)
        }
        let models = [target(10, 0x1000), target(10, 0x1300), target(10, 0x0A780001),
                      target(11, 0x1000), target(11, 0x1300), target(11, 0x130F), target(11, 0x1310), target(11, 0x0A780001),
                      target(12, 0x1000), target(12, 0x1310), target(12, 0x1234130F)]
        let zones = try HDBLightingZonePolicy.requiredZoneTargets(from: models, primaryAddress: 10)
        precondition(Set(zones) == Set([models[0], models[1], models[2], models[4], models[5], models[6], models[9]]))
        precondition(try! HDBLightingZonePolicy.requiredTargets(from: models).contains(models[7]), "Preparation retains secondary Vendor")
        let sensors = HDBLightingZonePolicy.sensorGroupTargets(from: models)
        precondition(Set(sensors) == Set([models[3], models[5], models[6]]), "Only LC elements supply sensor receivers")
        for missing in [models[0], models[2]] {
            do { _ = try HDBLightingZonePolicy.requiredZoneTargets(from: models.filter { $0 != missing }, primaryAddress: 10); fatalError("secondary model replaced mandatory primary model") }
            catch HDBConfigurationError.unsupportedModels {}
        }
        var device = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 10, mac: "AA:BB:CC:DD:EE:FF")
        device.zoneModels = zones.map(HDBModelReference.init)
        device.sensorGroupModels = sensors.map(HDBModelReference.init)
        device.broadcastModels = sensors.map(HDBModelReference.init)
        let root = HDBConfiguration(devices: [device])
        let ops = try HDBLightingZonePolicy.operations(for: device, in: root, targets: models, broadcastTargets: sensors)
        precondition(ops.map(\.stage) == [.reset, .broadcast], "nil sensorGroupId skips Sensor even with a nonempty model list")
        precondition(ops[1].subscriptions.allSatisfy { $0.address == 65277 } && ops[1].isLast)
        var withSensor = root; withSensor.devices[0].sensorGroupId = 0xC040
        let sensorOps = try HDBLightingZonePolicy.operations(for: withSensor.devices[0], in: withSensor, targets: models, broadcastTargets: sensors)
        precondition(sensorOps.map(\.stage) == [.reset, .broadcast, .sensor])
        precondition(sensorOps.last!.subscriptions.allSatisfy { $0.address == 0xC040 })
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(device)) as! [String: Any]
        let wire = raw["zoneModels"] as! [[String: Any]]
        precondition(wire.contains { $0["modelId"] as? UInt32 == 175636481 })
        precondition(wire.allSatisfy { Set($0.keys) == ["elementAddress", "modelId"] && $0["modelId"] is NSNumber })
        for key in ["zoneModels", "sensorGroupModels", "broadcastModels", "broadcastId"] {
            for value: Any? in [nil, NSNull(), "invalid"] {
                var bad = raw; bad[key] = value
                do { _ = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONSerialization.data(withJSONObject: bad)); fatalError("missing or invalid new field accepted") } catch {}
            }
        }
        for id in [0, 65276, 65535] {
            var bad = raw; bad["broadcastId"] = id
            do { _ = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONSerialization.data(withJSONObject: bad)); fatalError("non-FEFD broadcast accepted") } catch {}
        }
        for entry: [String: Any] in [["elementAddress": -1, "modelId": 4096], ["elementAddress": 10, "modelId": "1000"], ["elementAddress": 10, "modelId": 4294967296 as UInt64]] {
            var bad = raw; bad["zoneModels"] = [entry]
            do { _ = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONSerialization.data(withJSONObject: bad)); fatalError("invalid numeric reference accepted") } catch {}
        }
        var reordered = raw; reordered["zoneModels"] = Array(wire.reversed()) + wire
        let normalized = try JSONDecoder().decode(HDBDeviceConfiguration.self, from: JSONSerialization.data(withJSONObject: reordered))
        precondition(normalized == device)
        var changed = root; changed.devices[0].zoneModels.removeLast()
        precondition(!HDBLightingZonePolicy.matches(ops[0].plan, in: changed))
        do { _ = try HDBLightingZonePolicy.operations(for: changed.devices[0], in: changed, targets: models, broadcastTargets: sensors); fatalError("stale targets accepted before Reset") } catch HDBConfigurationError.invalidData {}
        changed = root; changed.devices[0].zoneModels.append(HDBModelReference(models[7]))
        do { try HDBLightingZonePolicy.validate(changed); fatalError("secondary Vendor in Zone accepted") } catch HDBConfigurationError.invalidData {}
        let elements: [[String: Any]] = (0...2).map { index in
            ["index": index, "models": models.filter { $0.elementAddress == 10 + index }.map {
                ["modelId": String(format: $0.companyIdentifier == nil ? "%04X" : "%08X", $0.modelId)]
            }]
        }
        let payload: [String: Any] = ["groups": [[String: Any]](), "nodes": [["uuid": device.nodeUuid.uuidString, "unicastAddress": "000A", "elements": elements]]]
        try HDBLightingZonePolicy.validateReferences(root, payload: payload)
        changed = root; changed.devices[0].broadcastModels.append(HDBModelReference(target(13, 0x1306)))
        do { try HDBLightingZonePolicy.validateReferences(changed, payload: payload); fatalError("foreign element accepted") } catch HDBConfigurationError.invalidData {}
        changed = root; changed.devices[0].sensorGroupModels.append(HDBModelReference(models[8]))
        do { try HDBLightingZonePolicy.validateReferences(changed, payload: payload); fatalError("OnOff without same-element LC accepted") } catch HDBConfigurationError.invalidData {}
        print("PASS: numeric model lists, primary-only Zone targets, same-element Sensor targets, FEFD and strict new payload contract")
    }

    static func schemaAndMACValidation() throws {
        let id = UUID()
        let device = HDBDeviceConfiguration(nodeUuid: id, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF")
        let config = HDBConfiguration(lightingZones: (1...63).map {
            .init(zoneId: $0, name: "Zone \($0)", groupAddress: UInt16(0xC000 + $0))
        }, devices: [device])
        let json = try HDBLightingZonePolicy.json(config)
        precondition(json["broadcast"] == nil)
        precondition((json["lightingZones"] as! [[String: Any]]).allSatisfy { Set($0.keys) == ["zoneId", "name", "groupAddress"] })
        for raw in ["aabbccddeeff", "aa-bb-cc-dd-ee-ff", "AA:BB:CC:DD:EE:FF"] {
            let mac = try HDBDeviceConfiguration.normalizedMAC(raw)
            precondition(mac == device.mac)
        }
        for raw: String? in [nil, "", "invalid", "AA:BB:CC:DD:EE", "AA:BB-CCDD:EEFF", "AABBCCDDEEFF\n"] {
            do { _ = try HDBDeviceConfiguration.normalizedMAC(raw); fatalError("invalid MAC accepted") }
            catch HDBConfigurationError.invalidMAC {}
        }
        for raw: Any? in [nil, NSNull(), "", "invalid", "aabbccddeeff", 12] {
            var bad = json
            var entry = (bad["devices"] as! [[String: Any]])[0]
            entry["mac"] = raw
            bad["devices"] = [entry]
            do { _ = try HDBLightingZonePolicy.decode(payload: ["hdb": bad]); fatalError("invalid HDB MAC accepted") }
            catch {}
        }
        let groups = config.lightingZones.map { ["address": String(format: "%04X", $0.groupAddress), "isVirtual": false] as [String: Any] }
        var payload: [String: Any] = ["spaceData": ["hdb": json], "groups": groups,
            "nodes": [["uuid": id.uuidString, "unicastAddress": "0001", "macAddress": "aabbccddeeff"]]]
        try HDBLightingZonePolicy.validateReferences(config, payload: payload)
        payload["nodes"] = [["uuid": id.uuidString, "unicastAddress": "0001", "macAddress": "112233445566"]]
        do { try HDBLightingZonePolicy.validateReferences(config, payload: payload); fatalError("mismatched node MAC accepted") }
        catch HDBConfigurationError.invalidMAC {}
        payload["nodes"] = [["uuid": id.uuidString, "unicastAddress": "0001"]]
        try HDBLightingZonePolicy.validateReferences(config, payload: payload)
        precondition(HDBLightingZonePolicy.importedNodeMAC(nil, nodeUuid: id, nodeAddress: 1, in: config) == "AABBCCDDEEFF")
        precondition(HDBLightingZonePolicy.importedNodeMAC("", nodeUuid: id, nodeAddress: 1, in: config) == "AABBCCDDEEFF")
        precondition(HDBLightingZonePolicy.importedNodeMAC(nil, nodeUuid: id, nodeAddress: 2, in: config) == nil)
        precondition(HDBLightingZonePolicy.importedNodeMAC(nil, nodeUuid: id, nodeAddress: 1, in: nil) == nil)
        precondition(HDBLightingZonePolicy.importedNodeMAC("", nodeUuid: id, nodeAddress: 1, in: nil) == "")
        let ordinary = try HDBLightingZonePolicy.decode(payload: ["spaceData": [:], "nodes": [["uuid": id.uuidString]]])
        precondition(ordinary == nil, "ordinary data without HDB or MAC must remain compatible")
        let empty = try HDBLightingZonePolicy.decode(payload: ["hdb": ["schemaVersion": 1, "lightingZones": [], "devices": []]])
        precondition(empty == HDBConfiguration())
        for key in ["schemaVersion", "lightingZones", "devices"] {
            var bad = json; bad.removeValue(forKey: key)
            do { _ = try HDBLightingZonePolicy.decode(payload: ["hdb": bad]); fatalError("missing required field accepted") }
            catch {}
        }
        print("PASS: device-only schema, strict MAC, normalization, matching references and ordinary/empty data")
    }
}
