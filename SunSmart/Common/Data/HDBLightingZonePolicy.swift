import Foundation

enum HDBLightingZonePolicy {
    static func validate(_ configuration: HDBConfiguration) throws {
        for device in configuration.devices {
            try device.lightingConfiguration?.values.validate()
            try validateModels(device)
            guard device.mac == (try HDBDeviceConfiguration.normalizedMAC(device.mac)) else { throw HDBConfigurationError.invalidMAC }
        }
        let zones = configuration.lightingZones
        let sensorAddresses = configuration.devices.compactMap(\.sensorGroupId)
        guard Set(sensorAddresses).count == sensorAddresses.count,
              sensorAddresses.allSatisfy({ (0xC001..<0xFEFD).contains(Int($0)) }),
              Set(sensorAddresses).isDisjoint(with: zones.map(\.groupAddress)) else { throw HDBConfigurationError.invalidData }
        guard configuration.schemaVersion == 2,
              Set(zones.map(\.zoneId)).count == zones.count,
              Set(zones.map(\.groupAddress)).count == zones.count,
              zones.allSatisfy({ (1...63).contains($0.zoneId) && (0xC000..<0xFEFD).contains(Int($0.groupAddress)) && !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              Set(configuration.devices.map(\.nodeUuid)).count == configuration.devices.count,
              Set(configuration.devices.map(\.nodeAddress)).count == configuration.devices.count else { throw HDBConfigurationError.invalidData }
        let ids = Set(zones.map(\.zoneId))
        for device in configuration.devices {
            guard (1...0x7FFF).contains(Int(device.nodeAddress)),
                  Set(device.lightingZones.map(\.zoneId)).count == device.lightingZones.count,
                  device.lightingZones.count <= 8,
                  device.lightingZones.allSatisfy({ ids.contains($0.zoneId) }) else { throw HDBConfigurationError.invalidData }

        }
    }

    static func replacingZones(_ zoneIds: [Int], for device: HDBDeviceConfiguration, in configuration: HDBConfiguration) throws -> HDBConfiguration {
        try validate(configuration)
        let requested = Set(zoneIds)
        let available = Set(configuration.lightingZones.map(\.zoneId))
        guard zoneIds.count <= 8, requested.count == zoneIds.count, requested.isSubset(of: available) else { throw HDBConfigurationError.invalidZones }
        var next = configuration
        var updated = configuration.devices.first { $0.nodeUuid == device.nodeUuid } ?? device
        updated.nodeAddress = device.nodeAddress; updated.mac = device.mac
        updated.copyModels(from: device)
        try updated.refreshSensorPublication()
        updated.lightingZones = requested.sorted().map { HDBZoneMembership(zoneId: $0) }
        updated.lightingZonesStatus = .pending
        next.devices.removeAll { $0.nodeUuid == device.nodeUuid }
        next.devices.append(updated)
        try validate(next)
        return next
    }

    static func isZoneTarget(_ target: HDBModelTarget) -> Bool {
        (target.companyIdentifier == nil && [0x130F, 0x1310, 0x1000, 0x1300].contains(target.modelIdentifier))
            || (target.companyIdentifier == 0x0A78 && target.modelIdentifier == 1)
    }

    static func zoneTargets(from models: [HDBModelTarget], primaryAddress: UInt16) -> [HDBModelTarget] {
        Set(models.filter {
            isZoneTarget($0) && ($0.modelId != 0x1000 && $0.modelId != 0x0A780001
                || $0.elementAddress == primaryAddress)
        }).sorted(by: targetOrder)
    }

    static func requiredZoneTargets(from models: [HDBModelTarget], primaryAddress: UInt16) throws -> [HDBModelTarget] {
        try requiredTargets(from: zoneTargets(from: models, primaryAddress: primaryAddress))
    }

    static func sensorGroupTargets(from models: [HDBModelTarget]) -> [HDBModelTarget] {
        let elements = Set(models.filter { $0.modelId == 0x130F }.map(\.elementAddress))
        return Set(models.filter {
            elements.contains($0.elementAddress) && [0x1000, 0x130F, 0x1310].contains($0.modelId)
        }).sorted(by: targetOrder)
    }

    static func validateModels(_ device: HDBDeviceConfiguration) throws {
        try device.validateSensorPublication(models: device.zoneModels.map(\.target))
        let all = device.zoneModels + device.sensorGroupModels + device.broadcastModels
        guard device.broadcastId == 0xFEFD,
              all.allSatisfy({ $0.elementAddress >= device.nodeAddress && (1...0x7FFF).contains(Int($0.elementAddress)) }),
              device.zoneModels.allSatisfy({ zoneTargets(from: [$0.target], primaryAddress: device.nodeAddress).count == 1 }),
              device.sensorGroupModels.allSatisfy({ [0x1000, 0x130F, 0x1310].contains($0.modelId) }),
              device.broadcastModels.allSatisfy({ $0.elementAddress != device.nodeAddress && [0x1000, 0x1300, 0x1306, 0x130F, 0x1310].contains($0.modelId) }) else {
            throw HDBConfigurationError.invalidData
        }
    }

    static func requiredTargets(from models: [HDBModelTarget]) throws -> [HDBModelTarget] {
        let sig: Set<UInt16> = [0x130F, 0x1310, 0x1000, 0x1300]
        let selected = Set(models.filter(isZoneTarget))
        guard sig.isSubset(of: Set(selected.filter { $0.companyIdentifier == nil }.map(\.modelIdentifier))),
              selected.contains(where: { $0.companyIdentifier == 0x0A78 && $0.modelIdentifier == 1 }) else { throw HDBConfigurationError.unsupportedModels }
        return selected.sorted {
            if $0.elementAddress != $1.elementAddress { return $0.elementAddress < $1.elementAddress }
            if $0.companyIdentifier != $1.companyIdentifier { return ($0.companyIdentifier ?? 0) < ($1.companyIdentifier ?? 0) }
            return $0.modelIdentifier < $1.modelIdentifier
        }
    }

    /// Every retry rebuilds the entire target, including an empty target.
    static func operations(for device: HDBDeviceConfiguration, in configuration: HDBConfiguration,
                           targets: [HDBModelTarget], sensorTargets: [HDBModelTarget]? = nil,
                           broadcastTargets: [HDBModelTarget] = []) throws -> [HDBZoneOperation] {
        try validate(configuration)
        let available = Set(targets)
        let sensorTargets = sensorTargets ?? sensorGroupTargets(from: targets)
        let targets = try requiredZoneTargets(from: targets, primaryAddress: device.nodeAddress)
        guard Set(sensorTargets).isSubset(of: available), Set(broadcastTargets).isSubset(of: available),
              Set(sensorTargets) == Set(sensorGroupTargets(from: Array(available))),
              Set(device.zoneModels.map(\.target)) == Set(targets),
              Set(device.sensorGroupModels.map(\.target)) == Set(sensorTargets),
              Set(device.broadcastModels.map(\.target)) == Set(broadcastTargets) else { throw HDBConfigurationError.invalidData }
        guard device.lightingZonesStatus == .pending else { return [] }
        let zones = try device.lightingZones.sorted { $0.zoneId < $1.zoneId }.map { member -> HDBZoneDestination in
            guard let zone = configuration.lightingZones.first(where: { $0.zoneId == member.zoneId }) else { throw HDBConfigurationError.invalidZones }
            return .init(zoneId: zone.zoneId, groupAddress: zone.groupAddress)
        }
        let sensors = Array(Set(sensorTargets)).sorted(by: targetOrder)
        let broadcasts = Array(Set(broadcastTargets)).sorted(by: targetOrder)
        let plan = HDBZonePlan(nodeUuid: device.nodeUuid, nodeAddress: device.nodeAddress,
            zones: zones, sensorGroupId: device.sensorGroupId, targets: targets,
            sensorTargets: sensors, broadcastTargets: broadcasts, broadcastId: device.broadcastId)
        // DeleteAll can clear an extension chain across elements. No Add may precede
        // the final reset, and every desired address must be explicitly restored.
        var stages: [(HDBZoneOperation.Stage, [HDBZoneSubscription])] = [
            (.reset, targets.map { .init(target: $0, command: .deleteAll, address: 0) })
        ]
        if !broadcasts.isEmpty {
            stages.append((.broadcast, broadcasts.map { .init(target: $0, command: .add, address: device.broadcastId) }))
        }
        // Sensor Group metadata remains reserved for other features. This local
        // Sensor -> LC path does not restore any Sensor Group subscriptions.
        var additions: [HDBZoneSubscription] = []
        for zone in zones {
            additions += targets.map {
                .init(target: $0, command: .add, address: zone.groupAddress)
            }
        }
        if !additions.isEmpty { stages.append((.add, additions)) }
        return stages.enumerated().map { index, stage in
            .init(plan: plan, stage: stage.0, subscriptions: stage.1, isLast: index == stages.count - 1)
        }
    }

    static func targetOrder(_ lhs: HDBModelTarget, _ rhs: HDBModelTarget) -> Bool {
        if lhs.elementAddress != rhs.elementAddress { return lhs.elementAddress < rhs.elementAddress }
        if lhs.companyIdentifier != rhs.companyIdentifier { return (lhs.companyIdentifier ?? 0) < (rhs.companyIdentifier ?? 0) }
        return lhs.modelIdentifier < rhs.modelIdentifier
    }

    static func matches(_ plan: HDBZonePlan, in configuration: HDBConfiguration) -> Bool {
        guard let device = get(plan.nodeUuid, in: configuration), device.nodeAddress == plan.nodeAddress,
              device.sensorGroupId == plan.sensorGroupId,
              device.broadcastId == plan.broadcastId,
              Set(device.zoneModels.map(\.target)) == Set(plan.targets),
              Set(device.sensorGroupModels.map(\.target)) == Set(plan.sensorTargets),
              Set(device.broadcastModels.map(\.target)) == Set(plan.broadcastTargets),
              device.lightingZones.map(\.zoneId).sorted() == plan.zones.map(\.zoneId) else { return false }
        return plan.zones.allSatisfy { expected in
            configuration.lightingZones.contains { $0.zoneId == expected.zoneId && $0.groupAddress == expected.groupAddress }
        }
    }

    static func complete(_ operation: HDBZoneOperation, in configuration: inout HDBConfiguration) throws {
        guard matches(operation.plan, in: configuration),
              let index = configuration.devices.firstIndex(where: { $0.nodeUuid == operation.nodeUuid }) else {
            throw HDBConfigurationError.unavailable
        }
        if operation.isLast { configuration.devices[index].lightingZonesStatus = .synced }
    }

    static func get(_ nodeUuid: UUID, in configuration: HDBConfiguration) -> HDBDeviceConfiguration? {
        configuration.devices.first { $0.nodeUuid == nodeUuid }
    }
}

extension HDBLightingZonePolicy {
    static func json(_ configuration: HDBConfiguration) throws -> [String: Any] {
        try validate(configuration)
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(configuration)) as! [String: Any]
    }

    static func decode(payload: [String: Any]) throws -> HDBConfiguration? {
        if let raw = payload["spaceData"], !(raw is [String: Any]) { throw HDBConfigurationError.invalidData }
        let data = payload["spaceData"] as? [String: Any] ?? payload
        guard let raw = data["hdb"] else { return nil }
        guard raw is [String: Any] else { throw HDBConfigurationError.invalidData }
        let result = try JSONDecoder().decode(HDBConfiguration.self, from: JSONSerialization.data(withJSONObject: raw))
        try validate(result)
        return result
    }

    static func groupAddresses(in payload: [String: Any]) throws -> Set<UInt16> {
        try decode(payload: payload)?.allGroupAddresses ?? []
    }

    static func validateReferences(_ config: HDBConfiguration, payload: [String: Any]) throws {
        try validate(config)
        guard let groups = payload["groups"] as? [[String: Any]], let nodes = payload["nodes"] as? [[String: Any]] else { throw HDBConfigurationError.invalidData }
        let addresses = Set(groups.filter { !($0["isVirtual"] as? Bool ?? false) }.compactMap { ($0["address"] as? String).flatMap { UInt16($0, radix: 16) } })
        let virtualAddresses = Set(groups.filter { ($0["isVirtual"] as? Bool ?? false) }.compactMap { ($0["address"] as? String).flatMap { UInt16($0, radix: 16) } })
        guard Set(config.lightingZones.map(\.groupAddress)).isSubset(of: addresses),
              Set(config.devices.compactMap(\.sensorGroupId)).isSubset(of: virtualAddresses) else { throw HDBConfigurationError.invalidData }
        for device in config.devices {
            guard let node = nodes.first(where: {
                ($0["uuid"] as? String).flatMap(UUID.init(uuidString:)) == device.nodeUuid &&
                    ($0["unicastAddress"] as? String).flatMap { UInt16($0, radix: 16) } == device.nodeAddress
            }) else { throw HDBConfigurationError.invalidData }
            if let mac = try? HDBDeviceConfiguration.normalizedMAC(node["macAddress"] as? String), mac != device.mac {
                throw HDBConfigurationError.invalidMAC
            }
            let references = device.zoneModels + device.sensorGroupModels + device.broadcastModels
            if !references.isEmpty || device.sensorGroupId != nil {
                let models = try compositionTargets(node: node, primaryAddress: device.nodeAddress)
                try device.validateSensorPublication(models: models)
                guard Set(references.map(\.target)).isSubset(of: Set(models)),
                      Set(device.zoneModels.map(\.target)) == Set(zoneTargets(from: models, primaryAddress: device.nodeAddress)),
                      Set(device.sensorGroupModels.map(\.target)) == Set(sensorGroupTargets(from: models)) else {
                    throw HDBConfigurationError.invalidData
                }
            }
        }
    }

    private static func compositionTargets(node: [String: Any], primaryAddress: UInt16) throws -> [HDBModelTarget] {
        struct ImportedModel: Decodable { let modelId: String }
        struct ImportedElement: Decodable { let index: UInt8; let models: [ImportedModel] }
        guard let raw = node["elements"] as? [[String: Any]] else { throw HDBConfigurationError.invalidData }
        let elements = try JSONDecoder().decode([ImportedElement].self, from: JSONSerialization.data(withJSONObject: raw))
        guard Set(elements.map(\.index)).count == elements.count else { throw HDBConfigurationError.invalidData }
        return try elements.flatMap { element -> [HDBModelTarget] in
            let address = Int(primaryAddress) + Int(element.index)
            guard (1...0x7FFF).contains(address) else { throw HDBConfigurationError.invalidData }
            return try element.models.map { model in
                let text = model.modelId
                guard [4, 8].contains(text.count), text.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
                      let id = UInt32(text, radix: 16), text.count == 4 || id > 0xFFFF else { throw HDBConfigurationError.invalidData }
                return .init(elementAddress: UInt16(address), modelIdentifier: UInt16(id & 0xFFFF),
                             companyIdentifier: id > 0xFFFF ? UInt16(id >> 16) : nil)
            }
        }
    }

    /// A validated HDB snapshot can supply the MAC missing from its ordinary Node extension.
    /// Ordinary payloads retain their existing optional/raw value unchanged.
    static func importedNodeMAC(_ raw: String?, nodeUuid: UUID, nodeAddress: UInt16, in config: HDBConfiguration?) -> String? {
        guard (try? HDBDeviceConfiguration.normalizedMAC(raw)) == nil,
              let device = config?.devices.first(where: { $0.nodeUuid == nodeUuid && $0.nodeAddress == nodeAddress }) else { return raw }
        return device.mac.replacingOccurrences(of: ":", with: "")
    }

    /// Stable comparison order; keep all receipt fields, including the device synchronization status.
    static func canonical(_ config: HDBConfiguration) throws -> [String: Any] {
        var sorted = config
        sorted.lightingZones.sort { $0.zoneId < $1.zoneId }
        sorted.devices.sort { $0.nodeUuid.uuidString < $1.nodeUuid.uuidString }
        for index in sorted.devices.indices { sorted.devices[index].lightingZones.sort { $0.zoneId < $1.zoneId } }
        return try json(sorted)
    }
}

/// ACKs are transient and must cover every requested target/address in this stage.
struct HDBZoneAcknowledgements {
    let operation: HDBZoneOperation
    private var acknowledged = Set<HDBZoneSubscription>()
    private var failed = false
    init(operation: HDBZoneOperation) { self.operation = operation }
    mutating func receive(target: HDBModelTarget, nodeAddress: UInt16, groupAddress: UInt16, successful: Bool) {
        guard successful, nodeAddress == operation.nodeAddress,
              let subscription = operation.subscriptions.first(where: { $0.target == target && $0.address == groupAddress }) else {
            failed = true; return
        }
        acknowledged.insert(subscription)
    }
    mutating func reject() { failed = true }
    var successful: Bool { !failed && !operation.subscriptions.isEmpty && acknowledged == Set(operation.subscriptions) }
}


extension HDBLightingZonePolicy {
    static func configurationForSave(current: HDBConfiguration?, baseline: HDBConfiguration?, persisted: HDBConfiguration?, rowExists: Bool) throws -> HDBConfiguration? {
        guard rowExists else { return current }
        if current == baseline { return persisted } // nil is an authoritative clear, not a missing row.
        guard persisted == baseline else { throw HDBConfigurationError.persistenceFailed }
        return current
    }
}

extension HDBLightingZonePolicy {
    /// Explicit recovery only. Nodes and Groups come exclusively from the selected
    /// cloud snapshot; this must never merge devices from the phone into that copy.
    static func repairingDefaults(in payload: [String: Any],
                                  deviceConfiguration: (([String: Any], String) throws -> HDBDeviceConfiguration)? = nil,
                                  zoneName: (Int) -> String) throws -> [String: Any] {
        guard let nodes = payload["nodes"] as? [[String: Any]],
              let groups = payload["groups"] as? [[String: Any]] else { throw HDBConfigurationError.invalidData }
        guard var extensionData = payload["spaceData"] as? [String: Any] else {
            if payload["spaceData"] != nil { throw HDBConfigurationError.invalidData }
            return payload
        }
        guard let raw = extensionData["hdb"] else { return payload }
        guard let object = raw as? [String: Any], let version = object["schemaVersion"] as? Int,
              [1, 2].contains(version),
              let zones = object["lightingZones"] as? [[String: Any]],
              let devices = object["devices"] as? [[String: Any]] else { throw HDBConfigurationError.invalidData }
        let groupAddresses = Set(groups.filter { !($0["isVirtual"] as? Bool ?? false) }
            .compactMap { ($0["address"] as? String).flatMap { UInt16($0, radix: 16) } })
        let nodeIdentities = try nodes.map { node -> (UUID, UInt16) in
            guard let id = (node["uuid"] as? String).flatMap(UUID.init(uuidString:)),
                  let address = (node["unicastAddress"] as? String).flatMap({ UInt16($0, radix: 16) }),
                  (1...0x7FFF).contains(Int(address)) else { throw HDBConfigurationError.invalidData }
            return (id, address)
        }
        guard Set(nodeIdentities.map { $0.0 }).count == nodes.count,
              Set(nodeIdentities.map { $0.1 }).count == nodes.count else { throw HDBConfigurationError.invalidData }
        var configuration = HDBConfiguration()
        for zone in zones {
            guard let id = zone["zoneId"] as? Int, (1...63).contains(id) else { throw HDBConfigurationError.invalidZones }
            let address: UInt16
            if let value = recoveryAddress(zone["groupId"]) {
                address = value
                if let old = recoveryAddress(zone["groupAddress"]), old != value { throw HDBConfigurationError.invalidZones }
            } else if zone["groupId"] == nil, let value = recoveryAddress(zone["groupAddress"]) { address = value }
            else { throw HDBConfigurationError.invalidZones }
            // A removed cloud Group cannot remain a target in the recovered HDB.
            guard groupAddresses.contains(address) else { continue }
            let name = (zone["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            configuration.lightingZones.append(.init(zoneId: id,
                name: name?.isEmpty == false ? name! : zoneName(id), groupAddress: address))
        }
        let zoneIDs = Set(configuration.lightingZones.map(\.zoneId))
        let sensorGroupAddresses = Set(groups.filter { $0["isVirtual"] as? Bool == true }
            .compactMap { recoveryAddress($0["address"]) })
        for rawDevice in devices {
            guard let id = (rawDevice["nodeUuid"] as? String).flatMap(UUID.init(uuidString:)) else { throw HDBConfigurationError.invalidData }
            guard let identity = nodeIdentities.first(where: { $0.0 == id }) else { continue }
            let node = nodes.first { ($0["uuid"] as? String).flatMap(UUID.init(uuidString:)) == id }!
            configuration.devices.append(try repairedDevice(rawDevice, node: node, identity: identity,
                version: version, zoneIDs: zoneIDs, sensorGroupAddresses: sensorGroupAddresses,
                deviceConfiguration: deviceConfiguration))
        }
        try validateReferences(configuration, payload: payload)
        extensionData["hdb"] = try json(configuration)
        var result = payload
        result["spaceData"] = extensionData
        result["deviceCount"] = nodes.count
        return result
    }

    /// Both known schemas share identity, membership, defaults and status handling.
    private static func repairedDevice(_ rawDevice: [String: Any], node: [String: Any],
                                       identity: (UUID, UInt16), version: Int, zoneIDs: Set<Int>,
                                       sensorGroupAddresses: Set<UInt16>,
                                       deviceConfiguration: (([String: Any], String) throws -> HDBDeviceConfiguration)?) throws -> HDBDeviceConfiguration {
        var deviceObject = rawDevice
        let selected = recoveryZoneIDs(rawDevice["lightingZones"]).filter { zoneIDs.contains($0) }
        let normalizedZones = Array(Set(selected)).sorted()
        guard normalizedZones.count <= 8 else { throw HDBConfigurationError.invalidZones }
        deviceObject["lightingZones"] = normalizedZones
        if normalizedZones != rawDevice["lightingZones"] as? [Int]
            || (rawDevice["lightingZonesStatus"] as? String).flatMap(HDBSyncStatus.init(rawValue:)) == nil {
            deviceObject["lightingZonesStatus"] = HDBSyncStatus.pending.rawValue
        }
        // The current cloud Node supplies identity and Composition. Reuse the
        // normal device factory so recovery and subsequent import/export agree,
        // including SDK Model extension rules for broadcast receivers.
        deviceObject["lightingConfiguration"] = NSNull()
        var device: HDBDeviceConfiguration
        var modelsChanged = false
        if let deviceConfiguration {
            let mac: String
            if let cloudMAC = try? HDBDeviceConfiguration.normalizedMAC(node["macAddress"] as? String) { mac = cloudMAC }
            else { mac = try HDBDeviceConfiguration.normalizedMAC(rawDevice["mac"] as? String) }
            device = try deviceConfiguration(node, mac)
            guard device.nodeUuid == identity.0, device.nodeAddress == identity.1 else { throw HDBConfigurationError.invalidData }
            let previous = try? JSONDecoder().decode(HDBDeviceConfiguration.self,
                from: JSONSerialization.data(withJSONObject: deviceObject))
            modelsChanged = previous == nil || previous?.nodeAddress != device.nodeAddress
                || previous?.hasSameModels(as: device) != true
            device.lightingZones = normalizedZones.map { .init(zoneId: $0) }
            device.lightingZonesStatus = (deviceObject["lightingZonesStatus"] as? String)
                .flatMap(HDBSyncStatus.init(rawValue:)) ?? .pending
            let sensor = recoveryAddress(rawDevice["sensorGroupId"])
            device.sensorGroupId = sensor.flatMap { address in
                sensorGroupAddresses.contains(address) ? address : nil
            }
            try device.refreshSensorPublication()
            if modelsChanged || device.sensorGroupId != sensor { device.lightingZonesStatus = .pending }
        } else {
            // Value-only callers cannot reconstruct legacy Composition metadata.
            guard version == 2, recoveryAddress(rawDevice["nodeAddress"]) == identity.1 else { throw HDBConfigurationError.invalidData }
            device = try JSONDecoder().decode(HDBDeviceConfiguration.self,
                from: JSONSerialization.data(withJSONObject: deviceObject))
        }
        device.lightingConfiguration = version == 1 ? .defaults : nil
        if let lighting = rawDevice["lightingConfiguration"], !(lighting is NSNull) {
            device.lightingConfiguration = try repairedLighting(lighting)
        }
        if modelsChanged {
            device.lightingConfiguration?.mark(fields: ["lightingControl", "dimIntensity", "brightIntensity",
                "rampUpTime", "rampDownTime", "holdTime"], status: .pending)
        }
        return device
    }

    private static func recoveryZoneIDs(_ raw: Any?) -> [Int] {
        guard let members = raw as? [Any] else { return [] }
        return members.compactMap { member in
            if let id = member as? Int { return id }
            return (member as? [String: Any])?["zoneId"] as? Int
        }
    }

    /// Compatibility belongs only to explicit recovery, never the normal decoder.
    private static func recoveryAddress(_ raw: Any?) -> UInt16? {
        if let text = raw as? String, text.count == 4,
           text.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) { return UInt16(text, radix: 16) }
        if let value = raw as? Int, !(raw is Bool) { return UInt16(exactly: value) }
        return nil
    }

    private static func repairedLighting(_ raw: Any) throws -> HDBLightingConfiguration {
        guard let fields = raw as? [String: Any] else { return .defaults }
        let defaults = try JSONSerialization.jsonObject(with: JSONEncoder().encode(HDBLightingConfiguration.defaults)) as! [String: Any]
        var repaired: [String: Any] = [:]
        for key in ["lightingControl", "failsafeDelay", "dimIntensity", "brightIntensity", "rampUpTime", "rampDownTime", "holdTime", "installDate"] {
            guard let field = fields[key], !(field is NSNull) else { continue }
            var candidate = field as? [String: Any] ?? [:]
            if (candidate["status"] as? String).flatMap(HDBSyncStatus.init(rawValue:)) == nil {
                candidate["status"] = HDBSyncStatus.pending.rawValue
            }
            do {
                let decoded = try JSONDecoder().decode(HDBLightingConfiguration.self,
                    from: JSONSerialization.data(withJSONObject: [key: candidate]))
                try decoded.values.validate()
                repaired[key] = candidate
            } catch {
                repaired[key] = defaults[key]
            }
        }
        return try JSONDecoder().decode(HDBLightingConfiguration.self,
            from: JSONSerialization.data(withJSONObject: repaired))
    }
}
