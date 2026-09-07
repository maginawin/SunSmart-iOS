import Foundation
import CoreFoundation

/// Validity is independent of the previous profile type. A complete 7/8 -> 1
/// change is a supported operation, including when it arrives from another phone.
enum SpaceConfigurationIntegrityPolicy {
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
        let levels = ["highEndTrim", "lowEndTrim", "occupancyLevel", "vacantLevel", "taskLevel"]
        for key in levels {
            guard let value = integer(profile[key]), (0...100).contains(value) else {
                return "invalidProfileField:\(key)"
            }
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
        for key in ["standbyLevel", "autoMinLevel", "relativeSensitivity", "adjustSpeed"] {
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
                for key in ["occupancyLevel", "vacantLevel", "standbyLevel", "taskLevel"] {
                    guard let value = integer(scene[key]), (0...100).contains(value) else {
                        return "invalidPhotocellSceneField:\(key)"
                    }
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
        return try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    static func confirmedTimestamp(previous: Int64?, submitted: Int64) -> Int64 {
        return max(previous ?? submitted, submitted)
    }
}
