import Foundation

/// A slot belongs to a provisioned node, not to an address that may be reused.
struct TimedSchedulerNodeIdentity: Codable, Hashable {
    let nodeUUID: String
    let unicastAddress: String
    let deviceKeyFingerprint: String

    var isValid: Bool {
        UUID(uuidString: nodeUUID) != nil && unicastAddress.count == 4
            && UInt16(unicastAddress, radix: 16).map { (1...0x7FFF).contains($0) } == true
            && deviceKeyFingerprint.count == 64
            && deviceKeyFingerprint.allSatisfy { $0.isASCII && $0.isHexDigit }
    }
}

struct TimedSchedulerActionAddress: Codable, Equatable {
    var autoOn: String
    var off: String
    var recall: String

    enum CodingKeys: String, CodingKey { case autoOn = "auto_on", off, recall }
    var addresses: [String] { [autoOn, off, recall] }
    var isValid: Bool { addresses.allSatisfy(Self.isAddress) }
    static func isAddress(_ value: String) -> Bool {
        value.count == 4 && value == value.uppercased()
            && UInt16(value, radix: 16).map { (1...0x7FFF).contains($0) } == true
    }
}

struct TimedSchedulerNodeSlot: Codable, Equatable {
    // assigned is read only for the v1/v2 compatibility boundary.
    enum State: String, Codable { case assigned, pendingApply, synced, pendingRemoval }
    let identity: TimedSchedulerNodeIdentity
    let slot: Int
    var state: State
    var actionAddress: TimedSchedulerActionAddress?

    init(identity: TimedSchedulerNodeIdentity, slot: Int, state: State,
         actionAddress: TimedSchedulerActionAddress? = nil) {
        self.identity = identity
        self.slot = slot
        self.state = state
        self.actionAddress = actionAddress
    }

    var isValid: Bool {
        identity.isValid && (0..<16).contains(slot)
            && (actionAddress?.isValid ?? (state == .assigned || state == .pendingRemoval))
    }
    var isV3: Bool { isValid && state != .assigned && actionAddress != nil }
}

/// Shared v3 representation. Only a validated complete Space may expand it to
/// the provisioning identity retained in local storage and running tasks.
struct TimedSchedulerWireNodeSlot: Codable {
    struct Identity: Codable { let unicastAddress: String }
    let identity: Identity
    let slot: Int
    let state: TimedSchedulerNodeSlot.State
    let actionAddress: TimedSchedulerActionAddress

    var isValid: Bool {
        TimedSchedulerActionAddress.isAddress(identity.unicastAddress)
            && (0..<16).contains(slot) && state != .assigned && actionAddress.isValid
    }
}

/// Pure reservation planner. Observations are physical slots across all Models.
/// No mutation or release occurs here: pending removal remains reserved until
/// an identity-matched, completed cleanup explicitly releases the binding.
enum TimedSchedulerSlotPolicy {
    enum Failure: Error, Equatable {
        case invalidIdentity, invalidSchedule, conflictingSlot, unknownCapacity, capacityExceeded
    }

    struct Intent {
        let scheduleID: Int
        let targetsNode: Bool
        let legacy: Bool
        let binding: TimedSchedulerNodeSlot?
        var preservesBinding = false
    }

    static func plan(identity: TimedSchedulerNodeIdentity, intents: [Intent],
                     observedSlots: Set<Int>?) throws -> [Int: TimedSchedulerNodeSlot] {
        guard identity.isValid else { throw Failure.invalidIdentity }
        guard intents.allSatisfy({ $0.scheduleID >= 0 }),
              Set(intents.map(\.scheduleID)).count == intents.count,
              observedSlots?.allSatisfy({ (0..<16).contains($0) }) != false else {
            throw Failure.invalidSchedule
        }
        var result: [Int: TimedSchedulerNodeSlot] = [:]
        var owners: [Int: Int] = [:]
        for intent in intents.sorted(by: { $0.scheduleID < $1.scheduleID }) {
            var binding = intent.binding
            if intent.legacy {
                guard (0..<16).contains(intent.scheduleID), binding == nil else {
                    throw Failure.invalidSchedule
                }
                // Unknown legacy Models may still contain an old orphan at id.
                if intent.preservesBinding || intent.targetsNode || observedSlots == nil || observedSlots!.contains(intent.scheduleID) {
                    binding = .init(identity: identity, slot: intent.scheduleID, state: .assigned)
                }
            }
            if var binding {
                guard binding.isValid, binding.identity == identity else { throw Failure.invalidIdentity }
                guard owners[binding.slot] == nil else { throw Failure.conflictingSlot }
                owners[binding.slot] = intent.scheduleID
                if !intent.preservesBinding { binding.state = intent.targetsNode ? .assigned : .pendingRemoval }
                result[intent.scheduleID] = binding
            }
        }
        var occupied = (observedSlots ?? []).union(owners.keys)
        for intent in intents.sorted(by: { $0.scheduleID < $1.scheduleID })
            where intent.targetsNode && result[intent.scheduleID] == nil {
            guard observedSlots != nil else { throw Failure.unknownCapacity }
            guard let slot = (0..<16).first(where: { !occupied.contains($0) }) else {
                throw Failure.capacityExceeded
            }
            result[intent.scheduleID] = .init(identity: identity, slot: slot, state: .assigned)
            occupied.insert(slot)
        }
        return result
    }
}

// The business payload is versioned separately from physical Model snapshots.
// This Foundation-only boundary also validates inactive Spaces without relying
// on MeshNetworkManager's current network.
import CryptoKit
import CoreFoundation

enum TimedSchedulerPayloadPolicy {
    /// In v2, omitted/null bindings mean unassigned, just like an explicit empty
    /// array. Preserve existing bindings and let validation reject malformed ones.
    /// Old clients preserve logical IDs above 15 but drop the schema and every
    /// node binding when writing a Space. Keep the desired schedules, defaulting
    /// lost bindings to unassigned and omitted business properties to Schedule defaults.
    /// Never infer physical slots from IDs.
    static func fillingMissingBindings(_ payload: [String: Any]) -> [String: Any] {
        var payload = withoutBindingGeneration(payload)
        // Native v3 is strict. Legacy defaults must never turn a damaged new
        // document into a valid empty configuration or a successful receipt.
        if declaredSchema(payload) == 3 { return payload }
        if payload["schedules"] == nil { payload["schedules"] = [[String: Any]]() }
        if let schedules = payload["schedules"] as? [[String: Any]] {
            let defaults: [String: Any] = ["name": "", "enabled": false, "selectTarget": 0,
                "action": 15, "fadeTime": 0, "hour": 0, "minute": 0, "dayOfWeek": 0, "sceneAddress": NSNull()]
            payload["schedules"] = schedules.map { defaults.merging($0) { _, supplied in supplied } }
        }
        if declaredSchema(payload) == 2,
           let schedules = payload["schedules"] as? [[String: Any]] {
            var result = payload
            result["schedules"] = schedules.map { schedule -> [String: Any] in
                guard schedule["nodeSlots"] == nil || schedule["nodeSlots"] is NSNull else { return schedule }
                var schedule = schedule
                schedule["nodeSlots"] = [[String: Any]]()
                return schedule
            }
            return result
        }
        guard declaredSchema(payload) == 1,
              payload["spaceData"] == nil || payload["spaceData"] is [String: Any],
              let schedules = payload["schedules"] as? [[String: Any]],
              schedules.contains(where: { integer($0["id"]).map { $0 >= 16 } == true }),
              schedules.allSatisfy({ $0["nodeSlots"] == nil }) else { return payload }
        var result = payload
        var spaceData = payload["spaceData"] as? [String: Any] ?? [:]
        spaceData["timedSchemaVersion"] = 2
        result["spaceData"] = spaceData
        result["schedules"] = schedules.map { schedule -> [String: Any] in
            var schedule = schedule
            schedule["nodeSlots"] = [[String: Any]]()
            // Normalize the known legacy sentinel before promoting the payload
            // to v2, whose native representation still requires null.
            if let target = integer(schedule["selectTarget"]), [0, 1, 3].contains(target),
               schedule["sceneAddress"] as? String == "" {
                schedule["sceneAddress"] = NSNull()
            }
            return schedule
        }
        return result
    }

    /// Only the retired binding field is removed. Other modules' generations,
    /// unknown business fields, and malformed structures remain untouched.
    static func withoutBindingGeneration(_ payload: [String: Any]) -> [String: Any] {
        var result = payload
        if let schedules = payload["schedules"] as? [[String: Any]] {
            result["schedules"] = schedules.map { schedule -> [String: Any] in
                var schedule = schedule
                if let slots = schedule["nodeSlots"] as? [[String: Any]] {
                    schedule["nodeSlots"] = slots.map { slot -> [String: Any] in
                        var slot = slot
                        slot.removeValue(forKey: "generation")
                        return slot
                    }
                }
                return schedule
            }
        }
        return result
    }

    static func siteWithoutBindingGeneration(_ site: [String: Any]) -> [String: Any] {
        var result = site
        if let spaces = site["spaces"] as? [[String: Any]] {
            result["spaces"] = spaces.map(withoutBindingGeneration)
        }
        return result
    }

    /// Historical receipts have no Nodes, so do not pass them through the
    /// Space repair path (which could drop bindings). Preserve all other bytes'
    /// JSON meaning; a corrupt receipt cannot become an empty valid receipt.
    static func normalizedComparison(_ data: Data) -> Data? {
        guard let value = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let version = integer(value["timedSchemaVersion"]), [1, 2, 3].contains(version),
              let schedules = value["schedules"] as? [[String: Any]] else { return nil }
        if version == 3 {
            return canonicalValidated(["spaceData": ["timedSchemaVersion": 3],
                                       "schedules": schedules, "nodes": [[String: Any]]()], comparisonOnly: true)
        }
        var identities = Set<TimedSchedulerNodeIdentity>()
        if version == 2 {
            for schedule in schedules {
                guard let raw = schedule["nodeSlots"] as? [[String: Any]],
                      let data = try? JSONSerialization.data(withJSONObject: raw),
                      let slots = try? JSONDecoder().decode([TimedSchedulerNodeSlot].self, from: data),
                      slots.allSatisfy(\.isValid) else { return nil }
                identities.formUnion(slots.map(\.identity))
            }
        }
        let validation: [String: Any] = ["spaceData": ["timedSchemaVersion": version], "schedules": schedules, "nodes": [[String: Any]]()]
        guard canonicalValidated(validation, knownIdentities: identities) != nil else { return nil }
        return try? JSONSerialization.data(withJSONObject: withoutBindingGeneration(value), options: [.sortedKeys])
    }

    static func comparisonsMatch(_ lhs: Data?, _ rhs: Data?) -> Bool {
        guard let lhs, let rhs,
              let left = normalizedComparison(lhs), let right = normalizedComparison(rhs) else { return false }
        return left == right
    }

    /// A reservation belongs to one provisioning instance. Keep the schedule,
    /// but drop references to instances absent from this complete node snapshot.
    /// Invalid identities/slots are still errors, not evidence of a deletion.
    static func repairingStaleBindings(_ payload: [String: Any]) -> [String: Any]? {
        let payload = fillingMissingBindings(payload)
        guard declaredSchema(payload) == 2 else { return payload }
        guard let nodes = payload["nodes"] as? [[String: Any]],
              let schedules = payload["schedules"] as? [[String: Any]] else { return nil }
        let identities = nodes.compactMap(identity)
        guard identities.count == nodes.count,
              Set(identities.map(\.nodeUUID)).count == nodes.count,
              Set(identities.map(\.unicastAddress)).count == nodes.count else { return nil }
        let current = Set(identities)
        var occupied: [TimedSchedulerNodeIdentity: Set<Int>] = [:]
        var repaired: [[String: Any]] = []
        for schedule in schedules {
            guard let raw = schedule["nodeSlots"] as? [[String: Any]],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let bindings = try? JSONDecoder().decode([TimedSchedulerNodeSlot].self, from: data),
                  Set(bindings.map(\.identity)).count == bindings.count else { return nil }
            for binding in bindings {
                guard binding.isValid,
                      occupied[binding.identity, default: []].insert(binding.slot).inserted else { return nil }
            }
            let stale = bindings.filter { !current.contains($0.identity) }
            guard !stale.isEmpty else { repaired.append(schedule); continue }
            let retained = bindings.filter { current.contains($0.identity) }
            // An explicitly bound current instance may reuse an old address.
            // Its target remains valid; an old address-only target must not be
            // inherited by a different instance merely because it is reused.
            let removedAddresses = Set(stale.map { $0.identity.unicastAddress.uppercased() })
                .subtracting(retained.map { $0.identity.unicastAddress.uppercased() })
            var item = schedule
            item["nodeSlots"] = zip(raw, bindings).compactMap { object, binding in
                current.contains(binding.identity) ? object : nil
            }
            for field in ["deviceAddresses", "needDeleteNodeAddresses"] {
                guard let rawAddresses = schedule[field] else { continue }
                guard let addresses = rawAddresses as? [String] else { return nil }
                item[field] = addresses.filter { !removedAddresses.contains($0.uppercased()) }
            }
            repaired.append(item)
        }
        var result = payload
        result["schedules"] = repaired
        return result
    }

    /// Keep v2 file sharing out of the legacy importer's editable root shape.
    /// Cloud requests continue to use the unwrapped Space API payload.
    static func backupEnvelope(_ payload: [String: Any]) -> [String: Any]? {
        guard let payload = repairingStaleBindings(payload) else { return nil }
        guard let version = schema(payload), canonical(payload) != nil else { return nil }
        if version == 1 { return payload }
        return ["format": "sunSmartSpace", "formatVersion": version, "space": payload]
    }

    static func backupPayload(_ document: [String: Any]) -> [String: Any]? {
        if document["format"] != nil {
            guard document["format"] as? String == "sunSmartSpace",
                  let version = integer(document["formatVersion"]), [2, 3].contains(version),
                  let source = document["space"] as? [String: Any],
                  let payload = repairingStaleBindings(source),
                  schema(payload) == version, canonical(payload) != nil else { return nil }
            return payload
        }
        guard declaredSchema(document) == 1, canonical(document) != nil else { return nil }
        return fillingMissingBindings(document)
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              let value = Int(number.stringValue) else { return nil }
        return value
    }

    static func schema(_ payload: [String: Any]) -> Int? {
        declaredSchema(fillingMissingBindings(payload))
    }

    private static func declaredSchema(_ payload: [String: Any]) -> Int? {
        let data = payload["spaceData"] as? [String: Any] ?? [:]
        guard let raw = data["timedSchemaVersion"] else { return 1 }
        guard let version = integer(raw), (1...3).contains(version) else { return nil }
        return version
    }

    static func identity(node: [String: Any]) -> TimedSchedulerNodeIdentity? {
        guard let uuid = UUID(uuidString: node["uuid"] as? String ?? node["UUID"] as? String ?? ""),
              let address = node["unicastAddress"] as? String,
              let key = node["deviceKey"] as? String, key.count == 32,
              key.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { return nil }
        let fingerprint = SHA256.hash(data: Data(key.uppercased().utf8)).map { String(format: "%02x", $0) }.joined()
        let identity = TimedSchedulerNodeIdentity(nodeUUID: uuid.uuidString.uppercased(),
            unicastAddress: address.uppercased(), deviceKeyFingerprint: fingerprint)
        return identity.isValid ? identity : nil
    }

    /// nil means invalid, never an empty configuration. Array order is immaterial.
    static func canonical(_ payload: [String: Any]) -> Data? {
        guard let payload = repairingStaleBindings(payload) else { return nil }
        return canonicalValidated(payload)
    }

    private static func wireBindings(_ schedule: [String: Any]) -> [TimedSchedulerWireNodeSlot]? {
        guard let raw = schedule["nodeSlots"] as? [[String: Any]],
              raw.allSatisfy({ value in
                  guard Set(value.keys) == Set(["identity", "slot", "state", "actionAddress"]),
                        let identity = value["identity"] as? [String: Any], Set(identity.keys) == ["unicastAddress"],
                        let route = value["actionAddress"] as? [String: Any],
                        Set(route.keys) == Set(["auto_on", "off", "recall"]) else { return false }
                  return integer(value["slot"]) != nil
              }),
              let data = try? JSONSerialization.data(withJSONObject: raw),
              let slots = try? JSONDecoder().decode([TimedSchedulerWireNodeSlot].self, from: data),
              slots.allSatisfy(\.isValid),
              Set(slots.map { $0.identity.unicastAddress }).count == slots.count else { return nil }
        return slots
    }

    /// Decode only after validating the shared snapshot. The resulting complete
    /// identities are durable local ownership, never an address lookup at send time.
    static func decodingSchedules(_ payload: [String: Any]) -> [[String: Any]]? {
        guard let normalized = repairingStaleBindings(payload), canonical(normalized) != nil,
              let rows = normalized["schedules"] as? [[String: Any]] else { return nil }
        guard schema(normalized) == 3 else { return rows }
        guard let nodes = normalized["nodes"] as? [[String: Any]] else { return nil }
        let identities = Dictionary(uniqueKeysWithValues: nodes.compactMap(identity).map { ($0.unicastAddress, $0) })
        var result: [[String: Any]] = []
        for row in rows {
            guard let wire = wireBindings(row) else { return nil }
            var bindings: [TimedSchedulerNodeSlot] = []
            for value in wire {
                guard let identity = identities[value.identity.unicastAddress] else { return nil }
                bindings.append(.init(identity: identity, slot: value.slot, state: value.state, actionAddress: value.actionAddress))
            }
            guard let data = try? JSONEncoder().encode(bindings),
                  let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            var decoded = row
            decoded["nodeSlots"] = object
            result.append(decoded)
        }
        return result
    }

    static func withoutSharedSchedulerObservation(_ node: [String: Any]) -> [String: Any] {
        var node = node
        node.removeValue(forKey: "schedules")
        if var properties = node["custProps"] as? [String: Any] {
            properties.removeValue(forKey: "schedulerModelStates")
            node["custProps"] = properties.isEmpty ? nil : properties
        }
        return node
    }

    /// Detached Space conversion, also used for inactive Spaces. No allocation
    /// or approximate entry matching is allowed here. Unbound v2 stays unbound.
    /// nil preserves the source for a later authoritative read/recovery.
    static func migratingLegacyPayload(_ source: [String: Any]) -> [String: Any]? {
        guard let payload = repairingStaleBindings(source), let version = schema(payload), version < 3,
              canonical(payload) != nil, let nodes = payload["nodes"] as? [[String: Any]],
              let rows = payload["schedules"] as? [[String: Any]],
              let groups = payload["groups"] as? [[String: Any]],
              let scenes = payload["scenes"] as? [[String: Any]] else { return nil }
        let identities = nodes.compactMap(identity)
        guard identities.count == nodes.count else { return nil }
        let sceneConfigs = (payload["spaceData"] as? [String: Any])?["sceneConfigurations"] as? [[String: Any]] ?? []
        func number(_ value: Any?) -> Int? { (value as? String).flatMap { Int($0, radix: 16) } ?? integer(value) }
        func sceneNodes(_ scene: Int, cleanup: Bool) -> Set<String>? {
            guard scenes.contains(where: { number($0["number"]) == scene }) else { return nil }
            if let config = sceneConfigs.first(where: { number($0["number"]) == scene }), config["kind"] as? String == "devices" {
                let members = config["deviceMembers"] as? [[String: Any]] ?? []
                var references = members.compactMap { $0["identity"] as? [String: Any] }
                if cleanup { references += (config["pendingOperations"] as? [[String: Any]] ?? []).compactMap { $0["identity"] as? [String: Any] } }
                guard references.allSatisfy({ raw in
                    identities.contains { $0.nodeUUID.caseInsensitiveCompare(raw["nodeUUID"] as? String ?? "") == .orderedSame
                        && $0.unicastAddress == (raw["unicastAddress"] as? String)?.uppercased()
                        && $0.deviceKeyFingerprint.caseInsensitiveCompare(raw["deviceKeyFingerprint"] as? String ?? "") == .orderedSame }
                }) else { return nil }
                return Set(references.compactMap { ($0["unicastAddress"] as? String)?.uppercased() })
            }
            let selected = Set(groups.filter { group in
                (group["scenesDatas"] as? [[String: Any]] ?? []).contains {
                    number($0["sceneNumber"]) == scene && (cleanup || integer($0["state"]) != 2)
                }
            }.compactMap { ($0["address"] as? String)?.uppercased() })
            return Set(nodes.filter { node in
                (cleanup || integer(node["groupState"]) != 2)
                    && (node["groupAddress"] as? String).map { selected.contains($0.uppercased()) } == true
            }.compactMap { ($0["unicastAddress"] as? String)?.uppercased() })
        }
        var output = payload, converted: [[String: Any]] = []
        for row in rows {
            guard let id = integer(row["id"]) else { return nil }
            var target = Set((row["deviceAddresses"] as? [String] ?? []).map { $0.uppercased() })
            let targetGroups = Set((row["groupAddresses"] as? [String] ?? []).map { $0.uppercased() }
                + (row["profiles"] as? [[String: Any]] ?? []).compactMap { ($0["groupAddress"] as? String)?.uppercased() })
            target.formUnion(nodes.filter { integer($0["groupState"]) != 2 && ($0["groupAddress"] as? String).map { targetGroups.contains($0.uppercased()) } == true }
                .compactMap { ($0["unicastAddress"] as? String)?.uppercased() })
            if let scene = number(row["sceneAddress"]) {
                guard let members = sceneNodes(scene, cleanup: false) else { return nil }
                target.formUnion(members)
            }
            var cleanup = Set((row["needDeleteNodeAddresses"] as? [String] ?? []).map { $0.uppercased() })
            for group in row["needDeleteGroupAddresses"] as? [String] ?? [] {
                guard groups.contains(where: { ($0["address"] as? String)?.uppercased() == group.uppercased() }) else { return nil }
                cleanup.formUnion(nodes.filter { ($0["groupAddress"] as? String)?.uppercased() == group.uppercased() }
                    .compactMap { ($0["unicastAddress"] as? String)?.uppercased() })
            }
            for scene in row["needDeleteSceneNumbers"] as? [String] ?? [] {
                guard let number = Int(scene, radix: 16), let members = sceneNodes(number, cleanup: true) else { return nil }
                cleanup.formUnion(members)
            }
            guard cleanup.isSubset(of: Set(identities.map(\.unicastAddress))) else { return nil }
            var bindings: [TimedSchedulerNodeSlot] = []
            if version == 2 {
                guard let raw = row["nodeSlots"], let data = try? JSONSerialization.data(withJSONObject: raw),
                      let decoded = try? JSONDecoder().decode([TimedSchedulerNodeSlot].self, from: data) else { return nil }
                bindings = decoded
                guard cleanup.isSubset(of: Set(bindings.map { $0.identity.unicastAddress })) else { return nil }
            }
            for (index, node) in nodes.enumerated() {
                let identity = identities[index]
                guard let primary = Int(identity.unicastAddress, radix: 16),
                      let elements = node["elements"] as? [[String: Any]] else { return nil }
                let schedulers = elements.filter { element in
                    let models = (element["models"] as? [[String: Any]] ?? []).compactMap { ($0["modelId"] as? String)?.uppercased() }
                    return models.contains("1207") && models.contains("1206")
                }.sorted { (integer($0["index"]) ?? -1) < (integer($1["index"]) ?? -1) }
                guard !schedulers.isEmpty else {
                    if bindings.contains(where: { $0.identity == identity }) { return nil }
                    continue
                }
                let lc = schedulers.first { element in (element["models"] as? [[String: Any]] ?? []).contains { ($0["modelId"] as? String)?.uppercased() == "130F" } }
                let ordinary = schedulers.first { integer($0["index"]) != lc.flatMap { integer($0["index"]) } } ?? schedulers[0]
                let group = groups.first { ($0["address"] as? String)?.uppercased() == (node["groupAddress"] as? String)?.uppercased() }
                let automatic = integer(node["groupState"]) != 2 && group.flatMap { $0["profile"] as? [String: Any] }.flatMap { integer($0["type"]) }.map { $0 != 6 } == true
                guard let ordinaryIndex = integer(ordinary["index"]),
                      let autoIndex = integer((automatic ? lc ?? ordinary : ordinary)["index"]),
                      ordinaryIndex >= 0, autoIndex >= 0, max(ordinaryIndex, autoIndex) <= 0x7FFF - primary else { return nil }
                let route = TimedSchedulerActionAddress(autoOn: String(format: "%04X", primary + autoIndex),
                    off: String(format: "%04X", primary + ordinaryIndex), recall: String(format: "%04X", primary + ordinaryIndex))
                if version == 1 {
                    // v1 owns this index globally. Unknown registers retain a
                    // cleanup reservation, including possible old orphan entries.
                    bindings.append(.init(identity: identity, slot: id, state: target.contains(identity.unicastAddress) ? .pendingApply : .pendingRemoval, actionAddress: route))
                } else if let bindingIndex = bindings.firstIndex(where: { $0.identity == identity }) {
                    bindings[bindingIndex].actionAddress = route
                    if integer(row["selectTarget"]) == 3 {
                        bindings[bindingIndex].state = bindings[bindingIndex].state == .pendingRemoval ? .pendingRemoval : .pendingApply
                    } else {
                        bindings[bindingIndex].state = target.contains(identity.unicastAddress) ? .pendingApply : .pendingRemoval
                    }
                }
            }
            var updated = row
            for key in ["needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"] { updated.removeValue(forKey: key) }
            guard let data = try? JSONEncoder().encode(bindings), let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            updated["nodeSlots"] = object
            converted.append(updated)
        }
        var metadata = payload["spaceData"] as? [String: Any] ?? [:]
        metadata["timedSchemaVersion"] = 3
        output["spaceData"] = metadata; output["schedules"] = converted
        return exportPayload(output)
    }

    /// Compress only matching complete local identities. Export must not hide
    /// stale ownership merely because a new provisioning instance reused an address.
    static func exportPayload(_ payload: [String: Any]) -> [String: Any]? {
        guard schema(payload) == 3 else {
            guard let repaired = repairingStaleBindings(payload), canonical(repaired) != nil else { return nil }
            return repaired
        }
        guard let nodes = payload["nodes"] as? [[String: Any]],
              let rows = payload["schedules"] as? [[String: Any]] else { return nil }
        let identities = Set(nodes.compactMap(identity))
        guard identities.count == nodes.count else { return nil }
        var result = payload, sharedRows: [[String: Any]] = []
        for row in rows {
            guard let raw = row["nodeSlots"] as? [[String: Any]],
                  let data = try? JSONSerialization.data(withJSONObject: raw),
                  let slots = try? JSONDecoder().decode([TimedSchedulerNodeSlot].self, from: data),
                  slots.allSatisfy({ $0.isV3 && identities.contains($0.identity) }) else { return nil }
            var shared = row
            for key in ["needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"] {
                guard row[key] == nil || (row[key] as? [String])?.isEmpty == true else { return nil }
                shared.removeValue(forKey: key)
            }
            let wire = slots.map { TimedSchedulerWireNodeSlot(identity: .init(unicastAddress: $0.identity.unicastAddress),
                slot: $0.slot, state: $0.state, actionAddress: $0.actionAddress!) }
            guard let data = try? JSONEncoder().encode(wire), let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
            shared["nodeSlots"] = object
            sharedRows.append(shared)
        }
        result["schedules"] = sharedRows
        result["nodes"] = nodes.map(withoutSharedSchedulerObservation)
        return canonical(result) != nil ? result : nil
    }

    private static func canonicalValidated(_ payload: [String: Any], knownIdentities: Set<TimedSchedulerNodeIdentity>? = nil,
                                           comparisonOnly: Bool = false) -> Data? {
        guard let version = declaredSchema(payload), let schedules = payload["schedules"] as? [[String: Any]],
              let nodes = payload["nodes"] as? [[String: Any]] else { return nil }
        let identities = knownIdentities ?? Set(nodes.compactMap(identity))
        var wireSlots: [String: Set<Int>] = [:]
        var modelAddresses: [String: Set<String>] = [:]
        if version == 3, !comparisonOnly {
            guard identities.count == nodes.count, Set(identities.map(\.nodeUUID)).count == nodes.count,
                  Set(identities.map(\.unicastAddress)).count == nodes.count else { return nil }
            var elementsInSpace = Set<Int>()
            for node in nodes {
                guard node["schedules"] == nil,
                      (node["custProps"] as? [String: Any])?["schedulerModelStates"] == nil,
                      let identity = identity(node: node),
                      let primary = Int(identity.unicastAddress, radix: 16),
                      let elements = node["elements"] as? [[String: Any]] else { return nil }
                var supported = Set<String>()
                for element in elements {
                    guard let index = integer(element["index"]), index >= 0,
                          index <= 0x7FFF - primary, elementsInSpace.insert(primary + index).inserted,
                          let models = element["models"] as? [[String: Any]] else { return nil }
                    let ids = Set(models.compactMap { ($0["modelId"] as? String)?.uppercased() })
                    if ids.contains("1207"), ids.contains("1206") {
                        supported.insert(String(format: "%04X", primary + index))
                    }
                }
                modelAddresses[identity.unicastAddress] = supported
            }
        }
        var ids = Set<Int>(), slots: [TimedSchedulerNodeIdentity: Set<Int>] = [:]
        var normalized: [[String: Any]] = []
        for schedule in schedules {
            guard let id = integer(schedule["id"]), id >= 0, ids.insert(id).inserted,
                  let name = schedule["name"] as? String,
                  let enabled = schedule["enabled"] as? NSNumber, CFGetTypeID(enabled) == CFBooleanGetTypeID(),
                  let target = integer(schedule["selectTarget"]), (0...3).contains(target),
                  let action = integer(schedule["action"]), [0, 1, 2, 15].contains(action),
                  let fade = integer(schedule["fadeTime"]), (0...63).contains(fade),
                  let hour = integer(schedule["hour"]), (0...23).contains(hour),
                  let minute = integer(schedule["minute"]), (0...59).contains(minute),
                  let days = integer(schedule["dayOfWeek"]), (0...127).contains(days) else { return nil }
            var item: [String: Any] = ["id": id, "name": name, "enabled": enabled.boolValue,
                "selectTarget": target, "action": action, "fadeTime": fade, "hour": hour,
                "minute": minute, "dayOfWeek": days]
            let retired = ["needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"]
            guard version != 3 || retired.allSatisfy({ schedule[$0] == nil }) else { return nil }
            for key in ["deviceAddresses", "groupAddresses"] + (version == 3 ? [] : retired) {
                let raw = schedule[key] ?? [String]()
                guard let addresses = raw as? [String], addresses.allSatisfy({ address in
                    guard address.count == 4, let value = UInt16(address, radix: 16), value > 0 else { return false }
                    if key == "deviceAddresses" || key == "needDeleteNodeAddresses" { return value < 0x8000 }
                    if key == "groupAddresses" || key == "needDeleteGroupAddresses" { return value >= 0x8000 && value < 0xFF00 }
                    return true
                }) else { return nil }
                item[key] = Array(Set(addresses.map { $0.uppercased() })).sorted()
            }
            // Legacy writers use an empty string for an unused Scene field on
            // Group/Device/Profile schedules. The Schedule decoder stores nil.
            // Do not extend this exception to an actual Scene target or v2.
            if version == 1, target != 2, schedule["sceneAddress"] as? String == "" {
                item["sceneAddress"] = NSNull()
            } else if let raw = schedule["sceneAddress"], !(raw is NSNull) {
                let value = (raw as? String).flatMap { UInt16($0, radix: 16) } ?? integer(raw).flatMap(UInt16.init(exactly:))
                guard let value, value > 0 else { return nil }
                item["sceneAddress"] = String(format: "%04X", value)
            } else { item["sceneAddress"] = NSNull() }
            guard let profiles = schedule["profiles"] as? [[String: Any]] ?? (schedule["profiles"] == nil ? [] : nil),
                  JSONSerialization.isValidJSONObject(profiles) else { return nil }
            item["profiles"] = profiles.map { profile -> [String: Any] in
                var profile = profile
                // Match the optional Codable fields without discarding unknown
                // fields or meaningful metadata changes from the receipt.
                for key in ["groupName", "type"] where profile[key] is NSNull {
                    profile.removeValue(forKey: key)
                }
                return profile
            }.sorted { ($0["groupAddress"] as? String ?? "") < ($1["groupAddress"] as? String ?? "") }
            if version == 1 {
                guard id < 16, schedule["nodeSlots"] == nil else { return nil }
            } else if version == 3 {
                guard let bindings = wireBindings(schedule) else { return nil }
                for binding in bindings {
                    let address = binding.identity.unicastAddress
                    guard wireSlots[address, default: []].insert(binding.slot).inserted,
                          comparisonOnly || modelAddresses[address].map({ supported in
                              binding.actionAddress.addresses.allSatisfy(supported.contains)
                          }) == true else { return nil }
                }
                let ordered = bindings.sorted { $0.identity.unicastAddress < $1.identity.unicastAddress }
                guard let data = try? JSONEncoder().encode(ordered),
                      let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
                item["nodeSlots"] = object
            } else {
                guard let raw = schedule["nodeSlots"] as? [[String: Any]],
                      let data = try? JSONSerialization.data(withJSONObject: raw),
                      let bindings = try? JSONDecoder().decode([TimedSchedulerNodeSlot].self, from: data),
                      Set(bindings.map(\.identity)).count == bindings.count else { return nil }
                for binding in bindings {
                    guard binding.isValid, identities.contains(binding.identity),
                          slots[binding.identity, default: []].insert(binding.slot).inserted else { return nil }
                }
                let ordered = bindings.sorted { $0.identity.nodeUUID < $1.identity.nodeUUID }
                guard let data = try? JSONEncoder().encode(ordered),
                      let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
                item["nodeSlots"] = object
            }
            normalized.append(item)
        }
        normalized.sort { ($0["id"] as! Int) < ($1["id"] as! Int) }
        if version >= 2, !comparisonOnly {
            let groups = payload["groups"] as? [[String: Any]] ?? []
            for node in nodes {
                if let elements = node["elements"] as? [[String: Any]],
                   !elements.contains(where: { element in
                       (element["models"] as? [[String: Any]] ?? []).contains { ($0["modelId"] as? String)?.uppercased() == "1207" }
                   }) { continue }
                guard let identity = identity(node: node) else { return nil }
                let address = identity.unicastAddress
                let group = (node["groupAddress"] as? String)?.uppercased()
                var required = Set<Int>()
                for schedule in normalized {
                    let id = schedule["id"] as! Int
                    var isTarget = (schedule["deviceAddresses"] as? [String] ?? []).contains(address)
                    if integer(node["groupState"]) != 2, let group {
                        isTarget = isTarget || (schedule["groupAddresses"] as? [String] ?? []).contains(group)
                        if let number = schedule["sceneAddress"] as? String, let targetScene = UInt16(number, radix: 16) {
                            isTarget = isTarget || groups.contains { candidate in
                                guard (candidate["address"] as? String)?.uppercased() == group else { return false }
                                return (candidate["scenesDatas"] as? [[String: Any]] ?? []).contains {
                                    integer($0["sceneNumber"]) == Int(targetScene) && integer($0["state"]) != 2
                                }
                            }
                        }
                    }
                    let bindings = schedule["nodeSlots"] as? [[String: Any]] ?? []
                    let binding = bindings.first { raw in
                        let value = raw["identity"] as? [String: Any]
                        return version == 3 ? value?["unicastAddress"] as? String == address
                            : value?["nodeUUID"] as? String == identity.nodeUUID
                    }
                    // Missing bindings are unassigned desired schedules. The
                    // existing sync planner reserves a slot before sending.
                    // Still count targets and pending removals for capacity.
                    if isTarget {
                        required.insert(id)
                    }
                    if binding != nil { required.insert(id) }
                }
                guard required.count <= 16 else { return nil }
            }
        }
        return try? JSONSerialization.data(withJSONObject: ["timedSchemaVersion": version, "schedules": normalized], options: [.sortedKeys])
    }

    /// A confirmed node removal may remove only that provisioning instance's
    /// references from a previously verified receipt, preserving other fields.
    static func removingNodes(from canonical: Data, uuids: Set<String>, addresses: Set<String>) -> Data? {
        guard let canonical = normalizedComparison(canonical),
              var value = (try? JSONSerialization.jsonObject(with: canonical)) as? [String: Any],
              let schedules = value["schedules"] as? [[String: Any]] else { return nil }
        value["schedules"] = schedules.map { schedule -> [String: Any] in
            var result = schedule
            for key in ["deviceAddresses"] + (integer(value["timedSchemaVersion"]) == 3 ? [] : ["needDeleteNodeAddresses"]) {
                result[key] = (schedule[key] as? [String] ?? []).filter { !addresses.contains($0.uppercased()) }
            }
            if let bindings = schedule["nodeSlots"] as? [[String: Any]] {
                result["nodeSlots"] = bindings.filter { binding in
                    guard let identity = binding["identity"] as? [String: Any],
                          let address = identity["unicastAddress"] as? String else { return false }
                    if integer(value["timedSchemaVersion"]) == 3 { return !addresses.contains(address.uppercased()) }
                    guard let uuid = identity["nodeUUID"] as? String else { return false }
                    return !(uuids.contains(uuid.uppercased()) && addresses.contains(address.uppercased()))
                }
            }
            return result
        }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
