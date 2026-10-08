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

struct TimedSchedulerNodeSlot: Codable, Equatable {
    enum State: String, Codable { case assigned, pendingRemoval }
    let identity: TimedSchedulerNodeIdentity
    let slot: Int
    var state: State
    let generation: UUID

    init(identity: TimedSchedulerNodeIdentity, slot: Int, state: State,
         generation: UUID = UUID()) {
        self.identity = identity
        self.slot = slot
        self.state = state
        self.generation = generation
    }

    var isValid: Bool { identity.isValid && (0..<16).contains(slot) }
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
                if intent.targetsNode || observedSlots == nil || observedSlots!.contains(intent.scheduleID) {
                    binding = .init(identity: identity, slot: intent.scheduleID, state: .assigned)
                }
            }
            if var binding {
                guard binding.isValid, binding.identity == identity else { throw Failure.invalidIdentity }
                guard owners[binding.slot] == nil else { throw Failure.conflictingSlot }
                owners[binding.slot] = intent.scheduleID
                binding.state = intent.targetsNode ? .assigned : .pendingRemoval
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
    /// Keep v2 file sharing out of the legacy importer's editable root shape.
    /// Cloud requests continue to use the unwrapped Space API payload.
    static func backupEnvelope(_ payload: [String: Any]) -> [String: Any]? {
        guard let version = schema(payload), canonical(payload) != nil else { return nil }
        if version == 1 { return payload }
        return ["format": "sunSmartSpace", "formatVersion": 2, "space": payload]
    }

    static func backupPayload(_ document: [String: Any]) -> [String: Any]? {
        if document["format"] != nil {
            guard document["format"] as? String == "sunSmartSpace",
                  integer(document["formatVersion"]) == 2,
                  let payload = document["space"] as? [String: Any],
                  schema(payload) == 2, canonical(payload) != nil else { return nil }
            return payload
        }
        guard schema(document) == 1, canonical(document) != nil else { return nil }
        return document
    }

    static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              let value = Int(number.stringValue) else { return nil }
        return value
    }

    static func schema(_ payload: [String: Any]) -> Int? {
        let data = payload["spaceData"] as? [String: Any] ?? [:]
        guard let raw = data["timedSchemaVersion"] else { return 1 }
        guard let version = integer(raw), (1...2).contains(version) else { return nil }
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
        guard let version = schema(payload), let schedules = payload["schedules"] as? [[String: Any]],
              let nodes = payload["nodes"] as? [[String: Any]] else { return nil }
        let identities = Set(nodes.compactMap(identity))
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
            for key in ["deviceAddresses", "groupAddresses", "needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"] {
                let raw = schedule[key] ?? [String]()
                guard let addresses = raw as? [String], addresses.allSatisfy({ address in
                    guard address.count == 4, let value = UInt16(address, radix: 16), value > 0 else { return false }
                    if key == "deviceAddresses" || key == "needDeleteNodeAddresses" { return value < 0x8000 }
                    if key == "groupAddresses" || key == "needDeleteGroupAddresses" { return value >= 0x8000 && value < 0xFF00 }
                    return true
                }) else { return nil }
                item[key] = Array(Set(addresses.map { $0.uppercased() })).sorted()
            }
            if let raw = schedule["sceneAddress"], !(raw is NSNull) {
                let value = (raw as? String).flatMap { UInt16($0, radix: 16) } ?? integer(raw).flatMap(UInt16.init(exactly:))
                guard let value, value > 0 else { return nil }
                item["sceneAddress"] = String(format: "%04X", value)
            } else { item["sceneAddress"] = NSNull() }
            guard let profiles = schedule["profiles"] as? [[String: Any]] ?? (schedule["profiles"] == nil ? [] : nil),
                  JSONSerialization.isValidJSONObject(profiles) else { return nil }
            item["profiles"] = profiles.sorted { ($0["groupAddress"] as? String ?? "") < ($1["groupAddress"] as? String ?? "") }
            if version == 1 {
                guard id < 16, schedule["nodeSlots"] == nil else { return nil }
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
        if version == 2 {
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
                        return value?["nodeUUID"] as? String == identity.nodeUUID
                    }
                    // Retain both desired entries and outstanding removals. A
                    // target without a reservation cannot be imported as v2.
                    if isTarget {
                        guard binding != nil else { return nil }
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
        guard var value = (try? JSONSerialization.jsonObject(with: canonical)) as? [String: Any],
              let schedules = value["schedules"] as? [[String: Any]] else { return nil }
        value["schedules"] = schedules.map { schedule -> [String: Any] in
            var result = schedule
            for key in ["deviceAddresses", "needDeleteNodeAddresses"] {
                result[key] = (schedule[key] as? [String] ?? []).filter { !addresses.contains($0.uppercased()) }
            }
            if let bindings = schedule["nodeSlots"] as? [[String: Any]] {
                result["nodeSlots"] = bindings.filter { binding in
                    guard let identity = binding["identity"] as? [String: Any],
                          let uuid = identity["nodeUUID"] as? String, let address = identity["unicastAddress"] as? String else { return false }
                    return !(uuids.contains(uuid.uppercased()) && addresses.contains(address.uppercased()))
                }
            }
            return result
        }
        return try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }
}
