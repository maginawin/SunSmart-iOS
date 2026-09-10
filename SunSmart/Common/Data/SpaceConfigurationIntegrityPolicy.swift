import Foundation
import CoreFoundation
import CryptoKit

/// The wire contract is checked independently of topology/readback projections.
/// Never include key material in an Issue or a diagnostic description.
enum SpaceMeshKeyPolicy {
    enum Issue: String, Error {
        case missingNetKey, missingAppKey, invalidNetKey, invalidAppKey
        case invalidBinding, invalidNodeKeyReference, invalidAppKeyIndex
        case networkIdentityMismatch, netKeyIndexConflict, appKeyIndexConflict
        case keyRefreshNeedsReview, ambiguousKeys, persistenceFailed, staleSnapshot
    }

    struct Key: Equatable {
        let index: Int64
        let value: String
        let oldValue: String?
        let phase: Int64?
        let boundNetKey: Int64?
    }

    struct Pair: Equatable {
        let network: Key
        let application: Key
    }

    struct Additions: Equatable {
        let network: Bool
        let application: Bool
    }

    /// Ignore display metadata, but never let a stale caller overwrite keys
    /// another Space has added, removed or refreshed since it loaded.
    static func sameInventory(_ lhs: [[String: Any]], _ rhs: [[String: Any]], network: Bool) -> Bool {
        let left = lhs.compactMap { key($0, network: network) }
        let right = rhs.compactMap { key($0, network: network) }
        guard left.count == lhs.count, right.count == rhs.count,
              Set(left.map(\.index)).count == left.count,
              Set(right.map(\.index)).count == right.count else { return false }
        return left.sorted { $0.index < $1.index } == right.sorted { $0.index < $1.index }
    }

    private static func key(_ raw: Any?, network: Bool) -> Key? {
        guard let dictionary = raw as? [String: Any],
              let index = SpaceConfigurationIntegrityPolicy.integer(dictionary["index"]),
              (0...4095).contains(index), let value = hexKey(dictionary["key"]) else { return nil }
        let oldValue = dictionary["oldKey"].flatMap(hexKey)
        if dictionary["oldKey"] != nil && oldValue == nil { return nil }
        if network {
            let phase = SpaceConfigurationIntegrityPolicy.integer(dictionary["phase"]) ?? (dictionary["phase"] == nil ? 0 : -1)
            guard (0...2).contains(phase), phase == 0 || oldValue != nil else { return nil }
            return Key(index: index, value: value, oldValue: oldValue, phase: phase, boundNetKey: nil)
        }
        guard let bound = SpaceConfigurationIntegrityPolicy.integer(dictionary["boundNetKey"]),
              (0...4095).contains(bound) else { return nil }
        return Key(index: index, value: value, oldValue: oldValue, phase: nil, boundNetKey: bound)
    }

    private static func hexKey(_ raw: Any?) -> String? {
        guard let value = raw as? String, value.utf8.count == 32,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return value.uppercased()
    }

    static func pair(_ payload: [String: Any]) -> Result<Pair, Issue> {
        guard payload["netKey"] != nil else { return .failure(.missingNetKey) }
        guard payload["appKey"] != nil else { return .failure(.missingAppKey) }
        guard let network = key(payload["netKey"], network: true) else { return .failure(.invalidNetKey) }
        guard let application = key(payload["appKey"], network: false) else { return .failure(.invalidAppKey) }
        guard application.boundNetKey == network.index else { return .failure(.invalidBinding) }
        if let index = payload["appKeyIndex"], SpaceConfigurationIntegrityPolicy.integer(index) != application.index {
            return .failure(.invalidAppKeyIndex)
        }
        return .success(Pair(network: network, application: application))
    }

    static func issue(in payload: [String: Any]) -> Issue? {
        let pair: Pair
        switch self.pair(payload) {
        case .failure(let issue): return issue
        case .success(let value): pair = value
        }
        if let rawNodes = payload["nodes"] {
            guard let nodes = rawNodes as? [[String: Any]] else { return .invalidNodeKeyReference }
            for node in nodes {
                for (field, expected) in [("netKeys", pair.network.index), ("appKeys", pair.application.index)] {
                    guard let raw = node[field] else { continue }
                    guard let references = raw as? [[String: Any]] else { return .invalidNodeKeyReference }
                    let indices = references.compactMap { SpaceConfigurationIntegrityPolicy.integer($0["index"]) }
                    guard indices.count == references.count, indices.allSatisfy({ (0...4095).contains($0) }),
                          indices.isEmpty || indices.contains(expected) else { return .invalidNodeKeyReference }
                }
            }
        }
        return nil
    }

    /// Only fill absent slots. Key refresh and colliding material must use their
    /// own reviewed protocol; never replace another Space's keys by index.
    static func additions(for pair: Pair, networks: [[String: Any]], applications: [[String: Any]]) -> Result<Additions, Issue> {
        let nets = networks.compactMap { key($0, network: true) }
        let apps = applications.compactMap { key($0, network: false) }
        guard nets.count == networks.count else { return .failure(.invalidNetKey) }
        guard apps.count == applications.count else { return .failure(.invalidAppKey) }
        guard Set(nets.map(\.index)).count == nets.count,
              Set(apps.map(\.index)).count == apps.count else { return .failure(.ambiguousKeys) }
        guard !nets.contains(where: { $0.value == pair.network.value && $0.index != pair.network.index }) else {
            return .failure(.networkIdentityMismatch)
        }
        // Space export has one application key per subnet. Do not persist a
        // second candidate that the exporter could only choose arbitrarily.
        guard !apps.contains(where: { $0.boundNetKey == pair.network.index && $0.index != pair.application.index }) else {
            return .failure(.ambiguousKeys)
        }
        if let local = nets.first(where: { $0.index == pair.network.index }), local != pair.network {
            let refresh = local.value == pair.network.value || local.oldValue == pair.network.value || pair.network.oldValue == local.value
            return .failure(refresh ? .keyRefreshNeedsReview : .netKeyIndexConflict)
        }
        if let local = apps.first(where: { $0.index == pair.application.index }), local != pair.application {
            let refresh = local.boundNetKey == pair.application.boundNetKey
                && (local.value == pair.application.value || local.oldValue == pair.application.value || pair.application.oldValue == local.value)
            return .failure(refresh ? .keyRefreshNeedsReview : .appKeyIndexConflict)
        }
        return .success(Additions(network: !nets.contains { $0.index == pair.network.index },
                                  application: !apps.contains { $0.index == pair.application.index }))
    }

    /// A private receipt proves the pair, without logging or storing raw keys in
    /// the topology projection. Old receipts remain unproven until re-submission.
    static func fingerprint(_ payload: [String: Any]) -> String? {
        guard issue(in: payload) == nil, case .success(let pair) = pair(payload) else { return nil }
        let fields = [String(pair.network.index), pair.network.value, pair.network.oldValue ?? "",
                      String(pair.network.phase ?? 0), String(pair.application.index), pair.application.value,
                      pair.application.oldValue ?? "", String(pair.application.boundNetKey ?? -1)]
        return SHA256.hash(data: Data(fields.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

/// Validity is independent of the previous profile type. A complete 7/8 -> 1
/// change is a supported operation, including when it arrives from another phone.
enum SpaceConfigurationIntegrityPolicy {
    static func cloudIsNewer(_ payload: [String: Any], localTimestamp: Int64,
                             submittedTimestamp: Int64?) -> Bool {
        guard let remote = integer(payload["updateTimestamp"]), remote > 0 else { return false }
        return remote > max(localTimestamp, submittedTimestamp ?? localTimestamp)
    }

    /// A detail response, not a Site summary or a partially decoded export.
    static func completeCloudSnapshot(_ payload: [String: Any]) -> Bool {
        guard integer(payload["updateTimestamp"]) != nil,
              payload["spaceName"] is String,
              ["nodes", "groups", "scenes", "schedules", "switches", "emergencyFireControllers"].allSatisfy({
                  payload[$0] is [[String: Any]]
              }), SpaceMeshKeyPolicy.fingerprint(payload) != nil,
              configurationData(payload) != nil else { return false }
        if let extensionData = payload["spaceData"] {
            guard let data = extensionData as? [String: Any],
                  data["triggerZones"] is [[String: Any]] else { return false }
        }
        return true
    }

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
            guard let relay = integer(profile["proximityLightingNumber"]),
                  (0...20).contains(relay) || relay == 255 else {
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

    // Cloud responses may fill an omitted Group address with an empty string.
    // Normalize only that representation; null, invalid and real addresses stay distinct.
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
