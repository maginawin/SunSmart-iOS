import Foundation

/// Pure validation of a complete Space snapshot. Device observations are retained;
/// known encoding aliases and references whose owner is absent/ineligible are repaired.
enum SpaceSyncCleanupPolicy {
    typealias Reconciler = ProximityLightingTopologyReconciler

    struct Device: Equatable {
        let uuid: String
        let primaryAddress: UInt16
        let elementAddresses: Set<UInt16>
        let topologyAddress: UInt16
        let groupAddress: UInt16?
    }

    struct Result {
        let payload: [String: Any]
        let devices: [Device]
        let topology: Reconciler.Result
        let orphanSubscriptions: [String: Set<UInt16>]
        let repairs: [String]
        var didChange: Bool { !repairs.isEmpty }
    }

    enum Invalid: Error, Equatable {
        case structure(String)
    }

    static func address(_ value: Any?) -> UInt16? {
        guard let text = value as? String else { return nil }
        return UInt16(text, radix: 16)
    }

    static func isBusinessGroup(_ address: UInt16) -> Bool {
        // FEFD (sub-elements), FEFE (OTA), FEFF (local client) are fixed-purpose subscriptions.
        (0xC000..<0xFEFD).contains(address)
    }

    static func normalize(_ input: [String: Any]) throws -> Result {
        guard var groups = input["groups"] as? [[String: Any]],
              var nodes = input["nodes"] as? [[String: Any]],
              input["scenes"] is [[String: Any]], input["schedules"] is [[String: Any]],
              SpaceConfigurationIntegrityPolicy.profilesIssue(in: input) == nil else {
            throw Invalid.structure("incompleteSpace")
        }
        let hdbAddresses = try HDBLightingZonePolicy.groupAddresses(in: input)
        if let hdb = try HDBLightingZonePolicy.decode(payload: input) { try HDBLightingZonePolicy.validateReferences(hdb, payload: input) }
        var allGroups = Set<UInt16>()
        var realGroups = Set<UInt16>()
        for group in groups {
            guard let address = address(group["address"]), allGroups.insert(address).inserted else {
                throw Invalid.structure("groupIdentity")
            }
            if !(group["isVirtual"] as? Bool ?? false), !hdbAddresses.contains(address) { realGroups.insert(address) }
        }
        var identities = Set<String>(), occupiedAddresses = Set<UInt16>()
        var members: [UInt16: Set<UInt16>] = [:]
        var devices: [Device] = []
        var orphanSubscriptions: [String: Set<UInt16>] = [:]
        var repairs: [String] = []
        for index in nodes.indices {
            let node = nodes[index]
            guard let uuid = node["uuid"] as? String, UUID(uuidString: uuid) != nil,
                  identities.insert(uuid.uppercased()).inserted,
                  let primary = address(node["unicastAddress"]), primary > 0,
                  let elements = node["elements"] as? [[String: Any]], !elements.isEmpty,
                  Int(primary) + elements.count <= 0x8000,
                  let state = SpaceConfigurationIntegrityPolicy.integer(node["groupState"]),
                  (0...2).contains(state) else { throw Invalid.structure("nodeIdentityOrState") }
            let addresses = Set((0..<elements.count).map { primary + UInt16($0) })
            guard occupiedAddresses.isDisjoint(with: addresses) else { throw Invalid.structure("duplicateElement") }
            occupiedAddresses.formUnion(addresses)
            var subscriptions = Set<UInt16>()
            var topologyAddress = primary
            for (offset, element) in elements.enumerated() {
                guard let models = element["models"] as? [[String: Any]] else {
                    throw Invalid.structure("nodeModels")
                }
                for model in models {
                    guard let modelID = model["modelId"] as? String,
                          let rawSubscriptions = model["subscribe"] as? [String] else {
                        throw Invalid.structure("modelSubscriptions")
                    }
                    for raw in rawSubscriptions {
                        // Virtual Mesh addresses may be encoded as UUIDs.
                        if let value = address(raw) { subscriptions.insert(value) }
                        else if UUID(uuidString: raw) == nil { throw Invalid.structure("subscriptionAddress") }
                    }
                    if modelID.uppercased() == "0A780001" { topologyAddress = primary + UInt16(offset) }
                }
            }
            let existing = subscriptions.intersection(realGroups)
            guard existing.count <= 1 else { throw Invalid.structure("ambiguousGroupMembership") }
            let stale = Set(subscriptions.filter { isBusinessGroup($0) && !allGroups.contains($0) })
            if !stale.isEmpty { orphanSubscriptions[uuid] = stale }
            if let raw = node["groupAddress"], !(raw is String)
                || ((raw as? String) != "" && address(raw) == nil) { throw Invalid.structure("declaredGroup") }
            let rawDeclared = address(node["groupAddress"])
            let declared = rawDeclared.flatMap { hdbAddresses.contains($0) ? nil : $0 }
            if let declared, declared != 0, allGroups.contains(declared), !existing.contains(declared), state != 2 {
                throw Invalid.structure("inconsistentExistingMembership")
            }
            // A valid current Group wins over an obsolete declaration. Retain raw
            // subscriptions until real unsubscribe acknowledgements arrive.
            let group = state == 2 ? nil : existing.first
            if state != 2 {
                let targetState = group != nil ? 1 : (stale.isEmpty ? 0 : 2)
                if state != Int64(targetState) || declared != group {
                    nodes[index]["groupState"] = targetState
                    nodes[index].removeValue(forKey: "groupAddress")
                    if let group { nodes[index]["groupAddress"] = String(format: "%04X", group) }
                    repairs.append("nodeMembership[\(uuid)]")
                }
            }
            if let group { members[group, default: []].insert(topologyAddress) }
            devices.append(.init(uuid: uuid, primaryAddress: primary, elementAddresses: addresses,
                                 topologyAddress: topologyAddress, groupAddress: group))
        }

        var states: [Reconciler.GroupState] = []
        for index in groups.indices where !(groups[index]["isVirtual"] as? Bool ?? false) {
            let group = groups[index]
            let groupAddress = address(group["address"])!
            if hdbAddresses.contains(groupAddress) { continue }
            var profile = group["profile"] as! [String: Any]
            let type = SpaceConfigurationIntegrityPolicy.integer(profile["type"])!
            let eligible = type == 7 || type == 8
            if let normalized = SpaceConfigurationIntegrityPolicy.normalizedProximityLightingNumber(profile["proximityLightingNumber"]),
               SpaceConfigurationIntegrityPolicy.integer(profile["proximityLightingNumber"]) != Int64(normalized) {
                profile["proximityLightingNumber"] = Int(normalized)
                groups[index]["profile"] = profile
                repairs.append("normalizedProximityRelay[group=\(groupAddress)]")
            }
            let relay = SpaceConfigurationIntegrityPolicy.integer(profile["proximityLightingNumber"]) ?? 2
            guard let relay = UInt8(exactly: relay) else { throw Invalid.structure("relay") }
            var paths: [[UInt16?]] = [], zones: [[UInt16]] = []
            if let raw = group["proximityLightingPath"] {
                guard let path = raw as? [String: Any],
                      let rawPaths = path["paths"] as? [[String: Any]],
                      let rawZones = path["zones"] as? [[String: Any]] else {
                    throw Invalid.structure("groupTopology")
                }
                for path in rawPaths {
                    guard let values = path["items"] as? [Any] else { throw Invalid.structure("pathItems") }
                    paths.append(try values.map { value in
                        guard let number = SpaceConfigurationIntegrityPolicy.integer(value), (0..<0x8000).contains(number) else {
                            throw Invalid.structure("pathAddress")
                        }
                        return number == 0 ? nil : UInt16(number)
                    })
                }
                for zone in rawZones {
                    guard let values = zone["addresses"] as? [Any] else { throw Invalid.structure("zoneMembers") }
                    zones.append(try values.map { value in
                        guard let number = SpaceConfigurationIntegrityPolicy.integer(value), (1..<0x8000).contains(number) else {
                            throw Invalid.structure("zoneAddress")
                        }
                        return UInt16(number)
                    })
                }
            }
            states.append(.init(address: groupAddress, eligible: eligible, relayNumber: relay,
                                memberAddresses: members[groupAddress] ?? [],
                                hasTopology: group["proximityLightingPath"] != nil, paths: paths, zones: zones))
        }
        var extensionData: [String: Any]
        if let raw = input["spaceData"] {
            guard let object = raw as? [String: Any] else { throw Invalid.structure("spaceData") }
            extensionData = object
        } else { extensionData = input }
        if let raw = extensionData["proximityLightingSchemaVersion"], SpaceConfigurationIntegrityPolicy.integer(raw) != 1 {
            throw Invalid.structure("schema")
        }
        var spaceZones: [ProximityLightingTopologyPolicy.SpaceZoneSnapshot] = []
        if let raw = extensionData["triggerZones"] {
            guard let zones = raw as? [[String: Any]] else { throw Invalid.structure("spaceZones") }
            for zone in zones {
                guard let items = zone["items"] as? [[String: Any]] else { throw Invalid.structure("spaceZoneItems") }
                let members = try items.map { item -> ProximityLightingTopologyPolicy.SpaceZoneMember in
                    guard let group = SpaceConfigurationIntegrityPolicy.integer(item["groupAddress"]),
                          let node = SpaceConfigurationIntegrityPolicy.integer(item["deviceAddress"]),
                          (0xC000...0xFEFF).contains(group), (1..<0x8000).contains(node) else {
                        throw Invalid.structure("spaceZoneMember")
                    }
                    return .init(groupAddress: UInt16(group), deviceAddress: UInt16(node))
                }
                spaceZones.append(.init(members: members))
            }
        } else if extensionData["proximityLightingSchemaVersion"] != nil {
            throw Invalid.structure("missingSpaceZones")
        }
        let topology = Reconciler.normalize(.init(groups: states, spaceZones: spaceZones))
        guard topology.isValid else { throw Invalid.structure("topology:\(topology.hardErrors)") }
        repairs += topology.repairs.map(\.diagnosticDescription)
        var result = input
        result["nodes"] = nodes
        result["groups"] = groups.map { original -> [String: Any] in
            var group = original
            guard let target = topology.snapshot.group(address: address(group["address"])!) else { return group }
            if !target.hasTopology { group.removeValue(forKey: "proximityLightingPath") }
            else {
                var path = group["proximityLightingPath"] as! [String: Any]
                path["paths"] = zip(path["paths"] as! [[String: Any]], target.paths).map { original, values in
                    var object = original; object["items"] = values.map { Int($0 ?? 0) }; return object
                }
                path["zones"] = zip(path["zones"] as! [[String: Any]], target.zones).map { original, values in
                    var object = original; object["addresses"] = values.map(Int.init); return object
                }
                group["proximityLightingPath"] = path
            }
            return group
        }
        if let originalZones = extensionData["triggerZones"] as? [[String: Any]] {
            extensionData["triggerZones"] = zip(originalZones, topology.snapshot.spaceZones).map { original, target in
                var zone = original
                let valid = Set(target.members)
                var seen = Set<ProximityLightingTopologyPolicy.SpaceZoneMember>()
                zone["items"] = (original["items"] as! [[String: Any]]).filter { item in
                    let member = ProximityLightingTopologyPolicy.SpaceZoneMember(
                        groupAddress: UInt16(SpaceConfigurationIntegrityPolicy.integer(item["groupAddress"])!),
                        deviceAddress: UInt16(SpaceConfigurationIntegrityPolicy.integer(item["deviceAddress"])!))
                    return valid.contains(member) && seen.insert(member).inserted
                }
                return zone
            }
            if input["spaceData"] != nil { result["spaceData"] = extensionData }
            else { result["triggerZones"] = extensionData["triggerZones"] }
        }
        return .init(payload: result, devices: devices, topology: topology,
                     orphanSubscriptions: orphanSubscriptions, repairs: repairs)
    }

    static func equivalentTopology(_ lhs: Reconciler.Snapshot, _ rhs: Reconciler.Snapshot) -> Bool {
        func canonical(_ snapshot: Reconciler.Snapshot) -> Reconciler.Snapshot {
            var result = snapshot
            for index in result.groups.indices where !result.groups[index].eligible {
                // Legacy exporters omit the inactive relay value for types 1...6.
                result.groups[index].relayNumber = 2
            }
            return result
        }
        return canonical(lhs) == canonical(rhs)
    }

    /// Used only to establish a migration baseline. Observation caches and the
    /// two legacy omitted Profile defaults cannot create a configuration conflict.
    static func baseline(_ payload: [String: Any], excludingDeletedUUIDs: Set<String> = []) -> Data? {
        guard let cleaned = try? normalize(payload) else { return nil }
        var result = cleaned.payload
        result["nodes"] = (result["nodes"] as? [[String: Any]])?.filter {
            !excludingDeletedUUIDs.contains(($0["uuid"] as? String ?? "").uppercased())
        }
        return SpaceConfigurationIntegrityPolicy.upgradeConfigurationData(result)
    }

    /// A historical upgrade block can be lifted only for already valid, equal
    /// configuration. Unlike cleanup baselines, this must not absorb repairs.
    static func upgradeRecoveryConfiguration(_ payload: [String: Any]) -> Data? {
        guard let cleaned = try? normalize(payload), !cleaned.didChange,
              let data = SpaceConfigurationIntegrityPolicy.upgradeConfigurationData(payload),
              let configuration = try? JSONSerialization.jsonObject(with: data),
              let uuid = payload["uuid"] as? String,
              let groups = payload["groups"] as? [[String: Any]] else { return nil }
        var result: [String: Any] = ["uuid": uuid, "configuration": configuration]
        for field in ["netKey", "appKey"] {
            guard let key = payload[field] as? [String: Any], key["key"] is String,
                  SpaceConfigurationIntegrityPolicy.integer(key["index"]) != nil else { return nil }
            if field == "appKey", SpaceConfigurationIntegrityPolicy.integer(key["boundNetKey"]) == nil { return nil }
            result[field] = key.filter { ["index", "key", "oldKey", "phase", "boundNetKey"].contains($0.key) }
        }
        for field in ["scenes", "schedules", "switches", "emergencyFireControllers"] {
            guard let values = payload[field] as? [[String: Any]] else { return nil }
            result[field] = values
        }
        result["groupSettings"] = groups.map { group in
            group.filter { $0.key != "profile" && $0.key != "proximityLightingPath" }
        }.sorted { ($0["address"] as? String ?? "") < ($1["address"] as? String ?? "") }
        return try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }
}

/// Pure candidate construction; authority, checkpoints and commit belong to the
/// existing recovery coordinator. No radio state is inferred from record removal.
enum SpaceRecoveryPayloadPolicy {
    static func repair(_ input: [String: Any]) throws -> [String: Any] {
        guard let timed = TimedSchedulerPayloadPolicy.repairingStaleBindings(input) else {
            throw SpaceSyncCleanupPolicy.Invalid.structure("timed")
        }
        let cleaned = try SpaceSyncCleanupPolicy.normalize(timed)
        var result = cleaned.payload
        guard let nodes = result["nodes"] as? [[String: Any]],
              let groups = result["groups"] as? [[String: Any]] else {
            throw SpaceSyncCleanupPolicy.Invalid.structure("recoveryCollections")
        }
        let addresses = Set(nodes.compactMap { $0["unicastAddress"] as? String }.map { $0.uppercased() })
        let groupAddresses = Set(groups.compactMap { $0["address"] as? String }.map { $0.uppercased() })
        let elementAddresses = Set(cleaned.devices.flatMap(\.elementAddresses).map { String(format: "%04X", $0) })
        let sceneNumbers = Set((result["scenes"] as? [[String: Any]] ?? []).compactMap { ($0["number"] as? String)?.uppercased() })
        result["schedules"] = (result["schedules"] as? [[String: Any]] ?? []).map { original in
            var item = original
            for field in ["deviceAddresses", "needDeleteNodeAddresses"] {
                if let values = item[field] as? [String] { item[field] = values.filter { elementAddresses.contains($0.uppercased()) } }
            }
            for field in ["groupAddresses", "needDeleteGroupAddresses"] {
                if let values = item[field] as? [String] { item[field] = values.filter { groupAddresses.contains($0.uppercased()) } }
            }
            if let values = item["needDeleteSceneNumbers"] as? [String] { item["needDeleteSceneNumbers"] = values.filter { sceneNumbers.contains($0.uppercased()) } }
            if let scene = item["sceneAddress"] as? String, !sceneNumbers.contains(scene.uppercased()) { item.removeValue(forKey: "sceneAddress") }
            if let profiles = item["profiles"] as? [[String: Any]] {
                item["profiles"] = profiles.filter { profile in
                    guard let address = profile["groupAddress"] as? String,
                          let number = profile["profileSceneNumber"] as? String,
                          let group = groups.first(where: { ($0["address"] as? String)?.uppercased() == address.uppercased() }),
                          let configuration = group["profile"] as? [String: Any],
                          let scenes = configuration["scenes"] as? [[String: Any]] else { return false }
                    return scenes.contains { ($0["number"] as? String)?.uppercased() == number.uppercased() }
                }
            }
            return item
        }
        if result["switches"] == nil { result["switches"] = [[String: Any]]() }
        if result["emergencyFireControllers"] == nil { result["emergencyFireControllers"] = [[String: Any]]() }
        if let raw = result["switches"] {
            guard let switches = raw as? [[String: Any]] else { throw SpaceSyncCleanupPolicy.Invalid.structure("switches") }
            result["switches"] = switches.map { original in
                var item = original
                for key in ["proxyNodeAddress", "deleteProxyNodeAddress"] {
                    if let address = item[key] as? String, !addresses.contains(address.uppercased()) {
                        item.removeValue(forKey: key)
                    }
                }
                for key in ["bindGroupAddresses", "unbindGroupAddresses"] {
                    if let values = item[key] as? [String] {
                        item[key] = values.filter { groupAddresses.contains($0.uppercased()) }
                    }
                }
                return item
            }
        }
        result["groups"] = groups.map { original in
            var group = original
            if let address = group["daylightSensorAddress"] as? String, !addresses.contains(address.uppercased()) {
                group.removeValue(forKey: "daylightSensorAddress")
            }
            return group
        }
        if let raw = result["emergencyFireControllers"] {
            guard let controllers = raw as? [[String: Any]] else { throw SpaceSyncCleanupPolicy.Invalid.structure("emergencyFireControllers") }
            result["emergencyFireControllers"] = controllers.map { original in
                var item = original
                if let address = item["bindNodeAddress"] as? String, !addresses.contains(address.uppercased()) {
                    item.removeValue(forKey: "bindNodeAddress")
                    item["isSynced"] = false
                    item["controllerSelfSyncPending"] = true
                }
                return item
            }
        }
        result["deviceCount"] = nodes.count
        return result
    }

    static func removing(_ uuids: Set<String>, from input: [String: Any]) throws -> [String: Any] {
        guard let nodes = input["nodes"] as? [[String: Any]],
              SpaceCloudNodeRemovalPolicy.instances(input) != nil else {
            throw SpaceSyncCleanupPolicy.Invalid.structure("recoveryNodeIdentity")
        }
        let selected = Set(uuids.map { $0.uppercased() })
        guard selected.isSubset(of: Set(nodes.compactMap { ($0["uuid"] as? String)?.uppercased() })) else {
            throw SpaceSyncCleanupPolicy.Invalid.structure("recoverySelectionChanged")
        }
        var result = input
        result["nodes"] = nodes.filter { !selected.contains(($0["uuid"] as? String ?? "").uppercased()) }
        if var hdb = try HDBLightingZonePolicy.decode(payload: input) {
            let retiredSensorGroups = Set(hdb.devices.filter { selected.contains($0.nodeUuid.uuidString.uppercased()) }.compactMap(\.sensorGroupId))
            result["groups"] = (input["groups"] as? [[String: Any]] ?? []).filter { group in
                guard group["isVirtual"] as? Bool == true, let address = SpaceSyncCleanupPolicy.address(group["address"]) else { return true }
                return !retiredSensorGroups.contains(address)
            }
            hdb.devices.removeAll { selected.contains($0.nodeUuid.uuidString.uppercased()) }
            var data = input["spaceData"] as? [String: Any] ?? [:]
            data["hdb"] = try HDBLightingZonePolicy.json(hdb)
            result["spaceData"] = data
        }
        return try repair(result)
    }

    static func clearing(_ input: [String: Any], hdb: Bool) throws -> [String: Any] {
        var result = input
        for field in ["nodes", "groups", "scenes", "schedules", "switches", "emergencyFireControllers"] {
            result[field] = [[String: Any]]()
        }
        var data: [String: Any] = ["timedSchemaVersion": 2, "proximityLightingSchemaVersion": 1,
                                    "triggerZones": [[String: Any]]()]
        if hdb { data["hdb"] = try HDBLightingZonePolicy.json(HDBConfiguration()) }
        result["spaceData"] = data
        result.removeValue(forKey: "triggerZones")
        result.removeValue(forKey: "hdb")
        result["deviceCount"] = 0
        return try repair(result)
    }
}
