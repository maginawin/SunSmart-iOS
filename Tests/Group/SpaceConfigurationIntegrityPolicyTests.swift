import Foundation

@main
struct SpaceConfigurationIntegrityPolicyTests {
    static func main() {
        typealias P = SpaceConfigurationIntegrityPolicy
        var profile: [String: Any] = ["id": "original-profile", "type": 7,
            "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 100,
            "vacantLevel": 50, "taskLevel": 100, "timeT1": 0, "timeT2": 30,
            "timeT3": 60, "timeT4": 0, "timeT5": 0,
            "manualOverrideTimeout": 600, "powerUpState": 0, "proximityLightingNumber": 2]
        precondition(P.profileIssue(profile) == nil)
        // All normal profile changes, including remote Proximity -> occupancy,
        // remain valid. No old-type comparison participates in this decision.
        for type in 1...7 {
            profile["type"] = type
            precondition(P.profileIssue(profile) == nil)
        }
        for key in ["id", "type", "highEndTrim", "timeT2"] {
            var incomplete = profile
            incomplete.removeValue(forKey: key)
            precondition(P.profileIssue(incomplete) != nil)
        }
        profile["type"] = true
        precondition(P.profileIssue(profile) != nil)
        profile["type"] = "1"
        precondition(P.profileIssue(profile) != nil)
        profile["type"] = 8
        precondition(P.profileIssue(profile) != nil)
        let scenes: [[String: Any]] = ["FF01", "FF02"].map { number in
            ["number": number, "name": number, "occupancyLevel": 100, "vacantLevel": 50,
             "standbyLevel": 0, "taskLevel": 100, "timeT1": 2, "timeT2": 30,
             "timeT3": 2, "timeT4": 60, "timeT5": 2]
        }
        profile["scenes"] = scenes
        profile["day"] = ["id": 0, "startsBelowLux": 100, "sceneNumber": "FF01"]
        profile["night"] = ["id": 1, "startsBelowLux": 50, "sceneNumber": "FF02"]
        precondition(P.profileIssue(profile) == nil)
        var missingSceneField = scenes
        missingSceneField[0].removeValue(forKey: "occupancyLevel")
        profile["scenes"] = missingSceneField
        precondition(P.profileIssue(profile) != nil)
        profile["scenes"] = scenes + [scenes[0]]
        precondition(P.profileIssue(profile) != nil)
        profile["scenes"] = scenes
        profile["night"] = ["id": 1, "startsBelowLux": 50, "sceneNumber": "FFFF"]
        precondition(P.profileIssue(profile) != nil)
        profile["type"] = 1
        let first: [String: Any] = ["groups": [["address": "C000", "profile": profile]],
            "spaceData": ["triggerZones": []]]
        var renamed = first
        renamed["spaceName"] = "Renamed"
        precondition(P.configurationData(first) == P.configurationData(renamed))
        var switchedProfile = profile
        switchedProfile.removeValue(forKey: "day")
        switchedProfile.removeValue(forKey: "night")
        switchedProfile.removeValue(forKey: "proximityLightingNumber")
        let switchedPayload: [String: Any] = ["groups": [["address": "C000", "profile": switchedProfile]],
            "spaceData": ["triggerZones": []]]
        precondition(P.configurationData(first) == P.configurationData(switchedPayload))
        var missing = first
        missing.removeValue(forKey: "spaceData")
        precondition(P.configurationData(first) != P.configurationData(missing))
        var observed = first
        observed["nodes"] = [["uuid": "node-1", "unicastAddress": "0001", "groupAddress": "C000", "groupState": 2, "proximityLightingEnabled": true]]
        var differentCache = observed
        differentCache["nodes"] = [["uuid": "node-1", "unicastAddress": "0001", "groupAddress": "C000", "groupState": 2, "proximityLightingEnabled": false]]
        precondition(P.configurationData(observed) == P.configurationData(differentCache))
        differentCache["nodes"] = [["uuid": "node-1", "unicastAddress": "0001", "groupAddress": "C001", "groupState": 2]]
        precondition(P.configurationData(observed) != P.configurationData(differentCache))
        precondition(P.confirmedTimestamp(previous: 10, submitted: 20) == 20)
        precondition(P.confirmedTimestamp(previous: 30, submitted: 20) == 30)
        precondition(P.legacySpaceZoneDeletionNeedsReview(["triggerZones": []], hasLocalZones: true))
        precondition(P.legacySpaceZoneDeletionNeedsReview([:], hasLocalZones: true))
        precondition(!P.legacySpaceZoneDeletionNeedsReview(["triggerZones": []], hasLocalZones: false))
        precondition(!P.legacySpaceZoneDeletionNeedsReview(
            ["spaceData": ["proximityLightingSchemaVersion": 1, "triggerZones": []]], hasLocalZones: true))
        print("PASS: complete profile switches, incomplete payloads, photocell references, readback and submission generation")
    }
}
