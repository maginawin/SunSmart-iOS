import Foundation

/// Pure validation of a complete Space snapshot. Device observations are retained;
/// only references whose owner is known to be absent/ineligible are repaired.
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
        guard let groups = input["groups"] as? [[String: Any]],
              var nodes = input["nodes"] as? [[String: Any]],
              input["scenes"] is [[String: Any]], input["schedules"] is [[String: Any]],
              SpaceConfigurationIntegrityPolicy.profilesIssue(in: input) == nil else {
            throw Invalid.structure("incompleteSpace")
        }
        var allGroups = Set<UInt16>()
        var realGroups = Set<UInt16>()
        for group in groups {
            guard let address = address(group["address"]), allGroups.insert(address).inserted else {
                throw Invalid.structure("groupIdentity")
            }
            if !(group["isVirtual"] as? Bool ?? false) { realGroups.insert(address) }
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
            let declared = address(node["groupAddress"])
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
        for group in groups where !(group["isVirtual"] as? Bool ?? false) {
            let groupAddress = address(group["address"])!
            let profile = group["profile"] as! [String: Any]
            let type = SpaceConfigurationIntegrityPolicy.integer(profile["type"])!
            let eligible = type == 7 || type == 8
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
        result["groups"] = (result["groups"] as? [[String: Any]])?.map { original -> [String: Any] in
            var group = original
            if var profile = group["profile"] as? [String: Any] {
                if profile["calibrationMode"] == nil { profile["calibrationMode"] = "none" }
                if profile["targetNightBrightness"] == nil { profile["targetNightBrightness"] = 50 }
                group["profile"] = profile
            }
            return group
        }
        var extensionData = result["spaceData"] as? [String: Any] ?? [:]
        if extensionData["triggerZones"] == nil { extensionData["triggerZones"] = [[String: Any]]() }
        result["spaceData"] = extensionData
        return SpaceConfigurationIntegrityPolicy.configurationData(result)
    }
}
