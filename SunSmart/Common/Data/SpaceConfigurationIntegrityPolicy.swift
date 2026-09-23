import Foundation
import CoreFoundation
import CryptoKit

/// Lossless node observations transported in the server's existing JSON column.
/// A missing container is unknown; a present container with zero bytes is known empty.
struct SchedulerModelSnapshot: Codable, Equatable {
    struct Container: Codable, Equatable {
        let elementAddress: String
        let modelId: String
        let entriesData: Data
    }
    enum Invalid: Error { case schema, identity, topology, entries, legacyProjection }

    let schemaVersion: Int
    let nodeUUID: String
    let unicastAddress: String
    let deviceKeyFingerprint: String
    let models: [Container]
    // Preserve the existing compatibility projection too, without rounding its
    // transition time or replacing its month mask during import.
    let legacyEntriesData: Data

    static func keyFingerprint(_ node: [String: Any]) throws -> String {
        guard let key = node["deviceKey"] as? String, key.count == 32,
              key.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw Invalid.identity }
        return SHA256.hash(data: Data(key.uppercased().utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func decode(node: [String: Any]) throws -> Self? {
        // custProps predates this contract and is opaque to other clients. Only
        // the explicit schedulerModelStates member declares our schema.
        guard let properties = node["custProps"] as? [String: Any] else { return nil }
        guard let raw = properties["schedulerModelStates"] else { return nil }
        let snapshot = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: raw))
        try snapshot.validate(node: node)
        return snapshot
    }

    func validate(node: [String: Any]) throws {
        guard schemaVersion == 1 else { throw Invalid.schema }
        guard let uuid = UUID(uuidString: node["uuid"] as? String ?? node["UUID"] as? String ?? ""),
              UUID(uuidString: nodeUUID) == uuid,
              let address = Self.address(node["unicastAddress"]),
              Self.address(unicastAddress) == address,
              deviceKeyFingerprint == (try Self.keyFingerprint(node)) else { throw Invalid.identity }
        guard let elements = node["elements"] as? [[String: Any]] else { throw Invalid.topology }
        var elementIndices = Set<Int64>()
        var supported = Set<UInt16>()
        for element in elements {
            guard let index = SpaceConfigurationIntegrityPolicy.integer(element["index"]),
                  (0...255).contains(index), elementIndices.insert(index).inserted,
                  Int64(address) + index <= 0x7FFF,
                  let modelList = element["models"] as? [[String: Any]] else { throw Invalid.topology }
            let setupModels = modelList.filter { ($0["modelId"] as? String)?.uppercased() == "1207" }
            guard setupModels.count <= 1 else { throw Invalid.topology }
            if !setupModels.isEmpty { supported.insert(address + UInt16(index)) }
        }
        var seen = Set<UInt16>()
        for model in models {
            guard model.modelId.uppercased() == "1207", let address = Self.address(model.elementAddress),
                  supported.contains(address), seen.insert(address).inserted else { throw Invalid.topology }
            _ = try Self.entries(model.entriesData)
        }
        let legacy = try Self.entries(legacyEntriesData)
        guard let schedules = node["schedules"] as? [[String: Any]], schedules.count == legacy.count else {
            throw Invalid.legacyProjection
        }
        var indices = Set<Int64>()
        for schedule in schedules {
            guard let index = SpaceConfigurationIntegrityPolicy.integer(schedule["id"]),
                  indices.insert(index).inserted,
                  let entry = legacy.first(where: { Int64($0[0] & 0x0F) == index }) else { throw Invalid.legacyProjection }
            for (key, value) in Self.legacyFields(entry) {
                guard SpaceConfigurationIntegrityPolicy.integer(schedule[key]) == value else { throw Invalid.legacyProjection }
            }
        }
    }

    static func address(_ raw: Any?) -> UInt16? {
        guard let hex = raw as? String, hex.count == 4,
              let value = UInt16(hex, radix: 16), (1...0x7FFF).contains(value) else { return nil }
        return value
    }

    /// Validate before calling SDK unmarshal, which assumes ten bytes and a valid action.
    static func entries(_ data: Data) throws -> [Data] {
        guard data.count <= 160, data.count.isMultiple(of: 10) else { throw Invalid.entries }
        var indices = Set<UInt8>()
        return try stride(from: 0, to: data.count, by: 10).map { offset in
            let entry = data.subdata(in: offset..<offset + 10)
            guard indices.insert(entry[0] & 0x0F).inserted,
                  [0, 1, 2, 15].contains(entry[6] >> 4) else { throw Invalid.entries }
            return entry
        }.sorted { ($0[0] & 0x0F) < ($1[0] & 0x0F) }
    }

    private static func legacyFields(_ data: Data) -> [String: Int64] {
        func bits(_ offset: Int, _ length: Int) -> Int64 {
            (0..<length).reduce(0) { $0 | (Int64((data[(offset + $1) / 8] >> ((offset + $1) % 8)) & 1) << $1) }
        }
        let steps = Int64(data[7] & 0x3F)
        let resolution = [0.1, 1, 10, 600][Int(data[7] >> 6)]
        return ["id": bits(0, 4), "year": bits(4, 7), "month": bits(11, 12), "day": bits(23, 5),
                "hour": bits(28, 5), "minute": bits(33, 6), "second": bits(39, 6), "dayOfWeek": bits(45, 7),
                "action": bits(52, 4), "transitionTime": steps == 63 ? 0 : Int64(Double(steps) * resolution),
                "sceneNumber": bits(64, 16)]
    }

    func dictionary() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
    }

    private func canonical() throws -> Self {
        .init(schemaVersion: schemaVersion, nodeUUID: nodeUUID.uppercased(), unicastAddress: unicastAddress.uppercased(),
              deviceKeyFingerprint: deviceKeyFingerprint, models: try models.map {
                  .init(elementAddress: $0.elementAddress.uppercased(), modelId: $0.modelId.uppercased(),
                        entriesData: try Self.entries($0.entriesData).reduce(into: Data()) { $0.append($1) })
              }.sorted { $0.elementAddress < $1.elementAddress },
              legacyEntriesData: try Self.entries(legacyEntriesData).reduce(into: Data()) { $0.append($1) })
    }

    static func spaceData(_ payload: [String: Any]) -> Data? {
        guard let nodes = payload["nodes"] as? [[String: Any]] else { return nil }
        do {
            let snapshots = try nodes.compactMap { try decode(node: $0)?.canonical() }.sorted { $0.nodeUUID < $1.nodeUUID }
            guard Set(snapshots.map(\.nodeUUID)).count == snapshots.count else { return nil }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return try encoder.encode(snapshots)
        } catch { return nil }
    }

    static func remoteChanged(_ data: Data, since baseline: Data?) -> Bool {
        // Old installations have no baseline. Only a new-format snapshot can
        // trigger a same-timestamp import in that case. Never compare cloud
        // observations to live local observations: the latter may be newer.
        data != (baseline ?? Data("[]".utf8))
    }
}

/// Validity is independent of the previous profile type. A complete 7/8 -> 1
/// change is a supported operation, including when it arrives from another phone.
enum SpaceConfigurationIntegrityPolicy {
    /// Types 1/2/5 store illuminance; Photocell (8) still stores percentages.
    /// The SDK's received lux cache is UInt16, even though the wire format is wider.
    static func levelIssue(type: Int64, values: [String: Any],
                           requiredFields: [String] = ["highEndTrim", "lowEndTrim", "occupancyLevel",
                                                       "vacantLevel", "standbyLevel", "taskLevel"]) -> String? {
        let daylight = type == 1 || type == 2 || type == 5
        for field in ["highEndTrim", "lowEndTrim", "occupancyLevel", "vacantLevel", "standbyLevel", "taskLevel"] {
            guard let raw = values[field] else {
                if requiredFields.contains(field) { return field }
                continue
            }
            let maximum: Int64 = daylight && field != "highEndTrim" && field != "lowEndTrim"
                ? Int64(UInt16.max) : 100
            guard let value = integer(raw), (0...maximum).contains(value) else { return field }
        }
        return nil
    }

    static func integer(_ value: Any?) -> Int64? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite,
              number.doubleValue == Double(number.int64Value) else { return nil }
        return number.int64Value
    }

    /// Every integer above the supported 0...20 range represents ALL (255).
    /// Normalize before narrowing so large imported values cannot overflow UInt8.
    static func normalizedProximityLightingNumber(_ value: Any?) -> UInt8? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let value = number.doubleValue
        guard value.isFinite, value >= 0, value.rounded(.towardZero) == value else { return nil }
        return value > 20 ? .max : UInt8(value)
    }

    static func profileIssue(_ profile: [String: Any]?) -> String? {
        guard let profile,
              let id = profile["id"] as? String, !id.isEmpty,
              let type = integer(profile["type"]), (1...8).contains(type) else {
            return "missingOrInvalidProfileIdentity"
        }
        if let field = levelIssue(type: type, values: profile,
                                  requiredFields: ["highEndTrim", "lowEndTrim", "occupancyLevel", "vacantLevel", "taskLevel"]) {
            return "invalidProfileField:\(field)"
        }
        for key in ["timeT1", "timeT2", "timeT3", "timeT4", "timeT5", "manualOverrideTimeout"] {
            guard let value = integer(profile[key]), (0...Int64(UInt32.max)).contains(value) else {
                return "invalidProfileField:\(key)"
            }
        }
        guard let power = integer(profile["powerUpState"]), (0...255).contains(power) else {
            return "invalidProfileField:powerUpState"
        }
        // These fields were optional in older payloads. Keep their established
        // defaults, but do not accept malformed values when they are present.
        for key in ["autoMinLevel", "relativeSensitivity", "adjustSpeed"] {
            if let raw = profile[key] {
                guard let value = integer(raw), (0...255).contains(value) else {
                    return "invalidProfileField:\(key)"
                }
            }
        }
        if type == 7 || type == 8 {
            guard normalizedProximityLightingNumber(profile["proximityLightingNumber"]) != nil else {
                return "invalidProfileRelay"
            }
        }
        // Legacy non-Photocell scenes may omit fields and use importer defaults.
        // When present, their levels must have the same units as the parent.
        if let rawScenes = profile["scenes"] {
            guard let scenes = rawScenes as? [[String: Any]] else { return "invalidProfileScenes" }
            for scene in scenes {
                if let field = levelIssue(type: type, values: scene, requiredFields: []) {
                    return type == 8 ? "invalidPhotocellSceneField:\(field)" : "invalidProfileSceneField:\(field)"
                }
            }
        }
        if type == 8 {
            guard let scenes = profile["scenes"] as? [[String: Any]], !scenes.isEmpty else {
                return "missingPhotocellScenes"
            }
            var sceneNumbers = Set<UInt16>()
            for scene in scenes {
                guard let rawNumber = scene["number"] as? String,
                      let number = UInt16(rawNumber, radix: 16),
                      sceneNumbers.insert(number).inserted, scene["name"] is String else {
                    return "invalidPhotocellScene"
                }
                if let field = levelIssue(type: type, values: scene,
                                          requiredFields: ["occupancyLevel", "vacantLevel", "standbyLevel", "taskLevel"]) {
                    return "invalidPhotocellSceneField:\(field)"
                }
                for key in ["timeT1", "timeT2", "timeT3", "timeT4", "timeT5"] {
                    guard let value = integer(scene[key]), (0...Int64(UInt32.max)).contains(value) else {
                        return "invalidPhotocellSceneField:\(key)"
                    }
                }
            }
            for key in ["day", "night"] {
                guard let condition = profile[key] as? [String: Any],
                      let id = integer(condition["id"]), (0...255).contains(id),
                      let lux = integer(condition["startsBelowLux"]), (0...65535).contains(lux),
                      let number = condition["sceneNumber"] as? String,
                      scenes.contains(where: { ($0["number"] as? String) == number && $0["name"] is String }) else {
                    return "invalidPhotocellCondition:\(key)"
                }
                if let raw = condition["executeType"],
                   integer(raw).map({ (0...1).contains($0) }) != true { return "invalidPhotocellExecuteType" }
                if let raw = condition["fixedStandbyLevel"],
                   integer(raw).map({ (0...100).contains($0) }) != true { return "invalidPhotocellStandbyLevel" }
            }
        }
        return nil
    }

    static func profilesIssue(in payload: [String: Any]) -> String? {
        guard let groups = payload["groups"] as? [[String: Any]] else { return "missingGroups" }
        for group in groups where !(group["isVirtual"] as? Bool ?? false) {
            if let issue = profileIssue(group["profile"] as? [String: Any]) {
                return "\(group["address"] as? String ?? "unknown"):\(issue)"
            }
        }
        return nil
    }

    /// Check scene schedules against this exported Space, never the active Mesh manager.
    static func scheduleTargetIssue(in payload: [String: Any]) -> String? {
        guard let schedules = payload["schedules"] as? [[String: Any]],
              let scenes = payload["scenes"] as? [[String: Any]] else { return "missingSchedulesOrScenes" }
        let sceneNumbers = Set(scenes.compactMap { $0["number"] as? String })
        var ids = Set<Int64>()
        for schedule in schedules {
            guard let id = integer(schedule["id"]), ids.insert(id).inserted,
                  let target = integer(schedule["selectTarget"]), (0...3).contains(target) else {
                return "invalidScheduleIdentityOrTarget"
            }
            if target == 2 {
                guard let number = schedule["sceneAddress"] as? String,
                      sceneNumbers.contains(number) else { return "missingSceneTarget:\(id)" }
            }
        }
        return nil
    }

    /// An additive readback check for new submissions. Old receipts lack this field.
    static func scheduleTargetsData(_ payload: [String: Any]) -> Data? {
        guard scheduleTargetIssue(in: payload) == nil,
              let schedules = payload["schedules"] as? [[String: Any]] else { return nil }
        let targets: [[String: Any]] = schedules.compactMap { schedule in
            guard let id = integer(schedule["id"]), let target = integer(schedule["selectTarget"]) else { return nil }
            return ["id": id, "selectTarget": target,
                    "sceneAddress": target == 2 ? schedule["sceneAddress"] as? String ?? "" : ""]
        }.sorted { (integer($0["id"]) ?? 0) < (integer($1["id"]) ?? 0) }
        return try? JSONSerialization.data(withJSONObject: targets, options: [.sortedKeys])
    }

    static func legacySpaceZoneDeletionNeedsReview(_ payload: [String: Any], hasLocalZones: Bool) -> Bool {
        guard hasLocalZones else { return false }
        let extensionData = payload["spaceData"] as? [String: Any] ?? payload
        // The released old App emits an empty root array when it has never
        // understood the new Space zones. A schema 1 explicit clear is valid.
        return integer(extensionData["proximityLightingSchemaVersion"]) == nil
            && (extensionData["triggerZones"] as? [Any])?.isEmpty != false
    }

    /// Only the logical configuration is compared. Node caches are observations,
    /// and may legitimately differ after a different phone talks to the Mesh.
    static func configurationData(_ payload: [String: Any]) -> Data? {
        guard profilesIssue(in: payload) == nil,
              let groups = payload["groups"] as? [[String: Any]] else { return nil }
        let profileKeys: Set<String> = ["id", "type", "highEndTrim", "lowEndTrim", "occupancyLevel",
            "vacantLevel", "standbyLevel", "taskLevel", "autoMinLevel", "timeT1", "timeT2", "timeT3",
            "timeT4", "timeT5", "manualOverrideTimeout", "powerUpState", "powerOnCct", "adjustSpeed",
            "calibrationMode", "targetNightBrightness", "proximityLightingNumber", "day", "night",
            "scenes", "relativeSensitivity"]
        let configurationGroups = groups.filter { !($0["isVirtual"] as? Bool ?? false) }.map { group in
            var profile = (group["profile"] as? [String: Any] ?? [:]).filter { profileKeys.contains($0.key) }
            let type = integer(profile["type"])
            if type != 8 { profile.removeValue(forKey: "day"); profile.removeValue(forKey: "night") }
            if type != 7 && type != 8 { profile.removeValue(forKey: "proximityLightingNumber") }
            if let scenes = profile["scenes"] as? [[String: Any]] {
                profile["scenes"] = scenes.sorted { ($0["number"] as? String ?? "") < ($1["number"] as? String ?? "") }
            }
            var result: [String: Any] = [
                "address": group["address"] ?? "",
                "profile": profile
            ]
            if let path = group["proximityLightingPath"] { result["proximityLightingPath"] = path }
            return result
        }.sorted { String(describing: $0["address"]!) < String(describing: $1["address"]!) }
        let extensionData = payload["spaceData"] as? [String: Any] ?? payload
        var result: [String: Any] = ["groups": configurationGroups]
        if let nodes = payload["nodes"] as? [[String: Any]] {
            result["memberships"] = nodes.map { node -> [String: Any] in
                var membership: [String: Any] = [:]
                for key in ["uuid", "unicastAddress", "groupAddress", "groupState"] {
                    if let value = node[key] { membership[key] = value }
                }
                return membership
            }.sorted { ($0["unicastAddress"] as? String ?? "") < ($1["unicastAddress"] as? String ?? "") }
        }
        if let zones = extensionData["triggerZones"] { result["triggerZones"] = zones }
        return serializeConfiguration(result)
    }

    /// Compatibility is only for establishing an upgrade baseline. Submission
    /// receipts continue to use configurationData and require explicit fields.
    static func upgradeConfigurationData(_ payload: [String: Any]) -> Data? {
        let extensionData: [String: Any]
        if let raw = payload["spaceData"] {
            guard let value = raw as? [String: Any] else { return nil }
            extensionData = value
        } else {
            extensionData = payload
        }
        if let version = extensionData["proximityLightingSchemaVersion"] {
            guard integer(version) == 1, extensionData["triggerZones"] != nil else { return nil }
        }
        if let zones = extensionData["triggerZones"], !(zones is [[String: Any]]) { return nil }
        guard let data = configurationData(payload),
              var configuration = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let groups = configuration["groups"] as? [[String: Any]] else { return nil }
        configuration["groups"] = groups.map { original in
            var group = original
            if var profile = group["profile"] as? [String: Any] {
                if profile["calibrationMode"] == nil { profile["calibrationMode"] = "none" }
                if profile["targetNightBrightness"] == nil { profile["targetNightBrightness"] = 50 }
                group["profile"] = profile
            }
            return group
        }
        if configuration["triggerZones"] == nil { configuration["triggerZones"] = [[String: Any]]() }
        return serializeConfiguration(configuration)
    }

    // Normalize equivalent Group address and ALL representations in both new
    // configurations and persisted baselines. Invalid values stay distinct.
    private static func serializeConfiguration(_ configuration: [String: Any]) -> Data? {
        var result = configuration
        if let memberships = result["memberships"] as? [[String: Any]] {
            result["memberships"] = memberships.map { membership in
                var normalized = membership
                if normalized["groupAddress"] as? String == "" {
                    normalized.removeValue(forKey: "groupAddress")
                }
                return normalized
            }
        }
        if let groups = result["groups"] as? [[String: Any]] {
            result["groups"] = groups.map { group in
                var normalized = group
                guard var profile = group["profile"] as? [String: Any],
                      let type = integer(profile["type"]), type == 7 || type == 8,
                      let relay = normalizedProximityLightingNumber(profile["proximityLightingNumber"]) else {
                    return group
                }
                profile["proximityLightingNumber"] = relay
                normalized["profile"] = profile
                return normalized
            }
        }
        return try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    /// Persisted snapshots already contain memberships, not the raw payload's nodes.
    /// Preserve every other field when comparing records created before normalization.
    static func normalizedConfigurationData(_ data: Data) -> Data? {
        guard let configuration = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        return serializeConfiguration(configuration)
    }

    static func configurationsMatch(_ lhs: Data?, _ rhs: Data?) -> Bool {
        guard let lhs, let rhs,
              let expected = normalizedConfigurationData(lhs),
              let actual = normalizedConfigurationData(rhs) else { return false }
        return expected == actual
    }

    static func confirmedTimestamp(previous: Int64?, submitted: Int64) -> Int64 {
        return max(previous ?? submitted, submitted)
    }

    /// Diagnose exactly the configuration used for comparison, never the raw payload.
    static func readbackDiagnostic(submitted: [String: Any], remote: [String: Any]) -> String {
        guard let configuration = configurationData(submitted) else { return "submittedConfiguration=invalid" }
        return "submittedTimestamp=\(integer(submitted["updateTimestamp"]).map(String.init) ?? "missing") "
            + readbackDiagnostic(submittedConfiguration: configuration, remote: remote)
    }

    static func readbackDiagnostic(submittedConfiguration: Data, remote: [String: Any]) -> String {
        guard let submittedConfiguration = normalizedConfigurationData(submittedConfiguration) else {
            return "submittedConfiguration=invalid"
        }
        let submitted = (try? JSONSerialization.jsonObject(with: submittedConfiguration)) as? [String: Any]
        let submittedNodes = submitted?["memberships"] as? [[String: Any]]
        let remoteNodes = remote["nodes"] as? [[String: Any]]
        let submittedIds = Set((submittedNodes ?? []).compactMap { $0["uuid"] as? String })
        let remoteIds = Set((remoteNodes ?? []).compactMap { $0["uuid"] as? String })
        let extra = remoteIds.subtracting(submittedIds).sorted()
        let missing = submittedIds.subtracting(remoteIds).sorted()
        let summary = "remoteTimestamp=\(integer(remote["updateTimestamp"]).map(String.init) ?? "missing") "
            + "submittedNodes=\(submittedNodes.map { String($0.count) } ?? "missing") "
            + "remoteNodes=\(remoteNodes.map { String($0.count) } ?? "missing") "
            + "remoteDeviceCount=\(integer(remote["deviceCount"]).map(String.init) ?? "missing") "
            + "extraRemoteNodes=\(extra.count) extraRemoteUUIDHashes=\(extra.prefix(8).map { diagnosticHash(Data($0.utf8)) }) "
            + "missingRemoteNodes=\(missing.count) missingRemoteUUIDHashes=\(missing.prefix(8).map { diagnosticHash(Data($0.utf8)) })"
        guard let actual = configurationData(remote) else { return summary + " remoteConfiguration=invalid" }
        return summary + "\n" + configurationDifferenceDiagnostic(submitted: submittedConfiguration, remote: actual)
    }

    private static func diagnosticHash(_ data: Data) -> String {
        SHA256.hash(data: data).prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    // Keys and scalar values have separate allowlists. Unknown keys can themselves
    // contain user text; neither they nor arbitrary string values are printed.
    private static let diagnosticKeys: Set<String> = [
        "groups", "memberships", "triggerZones", "address", "addresses", "uuid", "unicastAddress",
        "groupAddress", "deviceAddress", "groupState", "profile", "proximityLightingPath",
        "paths", "zones", "items", "id", "type", "name", "highEndTrim", "lowEndTrim",
        "occupancyLevel", "vacantLevel", "standbyLevel", "taskLevel", "autoMinLevel", "timeT1",
        "timeT2", "timeT3", "timeT4", "timeT5", "manualOverrideTimeout", "powerUpState",
        "powerOnCct", "adjustSpeed", "calibrationMode", "targetNightBrightness",
        "proximityLightingNumber", "day", "night", "scenes", "relativeSensitivity", "number",
        "startsBelowLux", "sceneNumber", "executeType", "fixedStandbyLevel"
    ]

    private static func diagnosticType(_ value: Any?) -> String {
        guard let value else { return "missing" }
        if value is NSNull { return "null" }
        if value is [String: Any] { return "object" }
        if value is [Any] { return "array" }
        if value is String { return "string" }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? "bool" : "number"
        }
        return "unknown"
    }

    private static func diagnosticValue(_ value: Any?, key: String) -> String {
        let type = diagnosticType(value)
        switch type {
        case "missing", "null": return type
        case "object": return "object(count=\((value as! [String: Any]).count))"
        case "array": return "array(count=\((value as! [Any]).count))"
        case "number", "bool":
            guard diagnosticKeys.contains(key), key != "name", key != "uuid" else { return "\(type)(redacted)" }
            return "\(type)(\((value as! NSNumber).stringValue))"
        case "string":
            let string = value as! String
            let addressKeys: Set<String> = ["address", "unicastAddress", "groupAddress", "deviceAddress", "number", "sceneNumber"]
            if addressKeys.contains(key), string.utf8.count == 4,
               string.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) {
                return "string(\(string))"
            }
            return "string(length=\(string.utf8.count),sha256=\(diagnosticHash(Data(string.utf8))))"
        default: return "redacted"
        }
    }

    /// Array positions remain significant, as they are in configurationData.
    /// Bounds keep diagnostics usable for large or malformed extension payloads.
    static func configurationDifferenceDiagnostic(submitted: Data, remote: Data) -> String {
        let header = "[SpaceConfigurationDiff] format=1 submittedSHA256=\(diagnosticHash(submitted)) remoteSHA256=\(diagnosticHash(remote))"
        guard let expected = try? JSONSerialization.jsonObject(with: submitted),
              let actual = try? JSONSerialization.jsonObject(with: remote) else {
            return header + " diagnostic=invalidJSON"
        }
        var rows: [String] = []
        var visited = 0
        var limited = false
        func append(_ path: String, _ lhs: Any?, _ rhs: Any?, key: String) {
            rows.append("[SpaceConfigurationDiff] path=\(path) submitted=\(diagnosticValue(lhs, key: key)) remote=\(diagnosticValue(rhs, key: key))")
        }
        func visit(_ lhs: Any?, _ rhs: Any?, path: String, key: String, depth: Int, knownPath: Bool) {
            guard rows.count < 24, visited < 4096, depth <= 16 else { limited = true; return }
            visited += 1
            let leftType = diagnosticType(lhs)
            let rightType = diagnosticType(rhs)
            let valueKey = knownPath ? key : ""
            guard leftType == rightType else { append(path, lhs, rhs, key: valueKey); return }
            if leftType == "object" || leftType == "array",
               let left = lhs, let right = rhs,
               let leftData = try? JSONSerialization.data(withJSONObject: left, options: [.sortedKeys]),
               let rightData = try? JSONSerialization.data(withJSONObject: right, options: [.sortedKeys]),
               leftData == rightData { return }
            if let left = lhs as? [String: Any], let right = rhs as? [String: Any] {
                for child in Set(left.keys).union(right.keys).sorted() {
                    let safeKey = diagnosticKeys.contains(child) ? child : "redactedKey_" + diagnosticHash(Data(child.utf8))
                    visit(left[child], right[child], path: path + "." + safeKey, key: child, depth: depth + 1,
                          knownPath: knownPath && diagnosticKeys.contains(child))
                    if limited { break }
                }
            } else if let left = lhs as? [Any], let right = rhs as? [Any] {
                if left.count != right.count { append(path + ".count", left.count, right.count, key: "number") }
                for index in 0..<max(left.count, right.count) {
                    visit(index < left.count ? left[index] : nil, index < right.count ? right[index] : nil,
                          path: path + "[\(index)]", key: key, depth: depth + 1, knownPath: knownPath)
                    if limited { break }
                }
            } else if let left = lhs as? String, let right = rhs as? String {
                if left != right { append(path, lhs, rhs, key: valueKey) }
            } else if let left = lhs as? NSNumber, let right = rhs as? NSNumber {
                if left != right { append(path, lhs, rhs, key: valueKey) }
            }
        }
        if submitted != remote { visit(expected, actual, path: "$", key: "", depth: 0, knownPath: true) }
        return ([header + " canonicalEqual=\(submitted == remote) differencesShown=\(rows.count) scanLimited=\(limited)"] + rows).joined(separator: "\n")
    }
}
