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
        testReadbackDiagnostics()
        testEmptyGroupAddressCompatibility()
        testProximityAllCompatibility()
        testUpgradeOnlyDefaults()
        print("PASS: complete profile switches, incomplete payloads, photocell references, readback and submission generation")
    }

    static func testProximityAllCompatibility() {
        typealias P = SpaceConfigurationIntegrityPolicy
        var profile: [String: Any] = ["id": "profile", "type": 7,
            "highEndTrim": 100, "lowEndTrim": 0, "occupancyLevel": 100,
            "vacantLevel": 50, "taskLevel": 100, "timeT1": 0, "timeT2": 30,
            "timeT3": 60, "timeT4": 0, "timeT5": 0,
            "manualOverrideTimeout": 600, "powerUpState": 0, "proximityLightingNumber": 255]
        func payload(_ value: [String: Any]) -> [String: Any] {
            ["groups": [["address": "C00D", "profile": value]], "spaceData": ["triggerZones": []]]
        }
        let canonical = P.configurationData(payload(profile))!
        let allValues: [Any] = Array(21...255).map { $0 as Any }
            + [256, 65535, Int64.max, UInt64.max]
        for value in allValues {
            profile["proximityLightingNumber"] = value
            precondition(P.normalizedProximityLightingNumber(value) == 255)
            precondition(P.profileIssue(profile) == nil)
            precondition(P.configurationData(payload(profile)) == canonical,
                         "Every integer above 20 must match ALL for recovery baselines and cloud readback")
            let wire = try! JSONSerialization.data(withJSONObject: payload(profile))
            let decoded = try! JSONSerialization.jsonObject(with: wire) as! [String: Any]
            precondition(P.profilesIssue(in: decoded) == nil && P.configurationData(decoded) == canonical)
            // Stored baselines may predate normalization, so bypass the exporter.
            var baseline = try! JSONSerialization.jsonObject(with: canonical) as! [String: Any]
            var groups = baseline["groups"] as! [[String: Any]]
            var storedProfile = groups[0]["profile"] as! [String: Any]
            storedProfile["proximityLightingNumber"] = value
            groups[0]["profile"] = storedProfile
            baseline["groups"] = groups
            let rawBaseline = try! JSONSerialization.data(withJSONObject: baseline)
            precondition(P.configurationsMatch(rawBaseline, canonical) && P.configurationsMatch(canonical, rawBaseline))
            precondition(P.readbackDiagnostic(submittedConfiguration: rawBaseline, remote: decoded)
                .contains("canonicalEqual=true"))
        }
        profile["timeT2"] = 5
        precondition(P.configurationData(payload(profile)) != canonical,
                     "Real Profile changes must not be hidden by relay compatibility")
        for invalid: Any in [-1, Int64.min, 1.5, 21.5, 256.5, "21", "255", true, false, NSNull()] {
            profile["proximityLightingNumber"] = invalid
            precondition(P.normalizedProximityLightingNumber(invalid) == nil)
            precondition(P.profileIssue(profile) == "invalidProfileRelay")
            precondition(P.configurationData(payload(profile)) == nil)
        }
        for relay in Array(0...20) + [255] {
            precondition(P.normalizedProximityLightingNumber(relay) == UInt8(relay))
        }
    }

    static func testUpgradeOnlyDefaults() {
        typealias P = SpaceConfigurationIntegrityPolicy
        let legacy: [String: Any] = ["groups": [], "nodes": [], "spaceData": [:]]
        let modern: [String: Any] = ["groups": [], "nodes": [],
                                    "spaceData": ["proximityLightingSchemaVersion": 1, "triggerZones": []]]
        precondition(P.upgradeConfigurationData(legacy) == P.upgradeConfigurationData(modern))
        precondition(P.configurationData(legacy) != P.configurationData(modern))
        for data: Any in ["invalid", NSNull(), ["proximityLightingSchemaVersion": 2, "triggerZones": []],
                           ["proximityLightingSchemaVersion": 1], ["triggerZones": NSNull()]] {
            var invalid = legacy; invalid["spaceData"] = data
            precondition(P.upgradeConfigurationData(invalid) == nil)
        }
        var changed = modern
        changed["spaceData"] = ["proximityLightingSchemaVersion": 1,
            "triggerZones": [["items": [["groupAddress": 49160, "deviceAddress": 554]]]]]
        precondition(P.upgradeConfigurationData(legacy) != P.upgradeConfigurationData(changed))
        print("PASS: omitted legacy empty zones are upgrade-only compatibility; malformed/schema/nonempty differences remain distinct")
    }

    static func testEmptyGroupAddressCompatibility() {
        typealias P = SpaceConfigurationIntegrityPolicy
        let node: [String: Any] = ["uuid": "node", "unicastAddress": "0046", "groupState": 0]
        let payload: [String: Any] = ["groups": [], "nodes": [node], "spaceData": ["triggerZones": []]]
        let expected = P.configurationData(payload)!
        var otherNode = node
        otherNode["groupAddress"] = ""
        var other = payload
        other["nodes"] = [otherNode]
        precondition(expected == P.configurationData(other))
        // Build the on-disk shape directly, without the newly normalized exporter.
        let legacy = try! JSONSerialization.data(withJSONObject: ["groups": [], "memberships": [otherNode], "triggerZones": []])
        precondition(P.configurationsMatch(legacy, expected) && P.configurationsMatch(expected, legacy))
        precondition(P.readbackDiagnostic(submittedConfiguration: legacy, remote: payload).contains("canonicalEqual=true"))
        for address: Any in [NSNull(), " ", "0000", "C000", "invalid", 0] {
            otherNode["groupAddress"] = address
            other["nodes"] = [otherNode]
            precondition(!P.configurationsMatch(expected, P.configurationData(other)))
        }
        for (key, value): (String, Any) in [("uuid", "another"), ("unicastAddress", "0047"), ("groupState", 2)] {
            otherNode = node
            otherNode[key] = value
            other["nodes"] = [otherNode]
            precondition(!P.configurationsMatch(legacy, P.configurationData(other)))
        }
        other = payload
        other["spaceData"] = ["triggerZones": [["items": [["groupAddress": 49152, "deviceAddress": 70]]]]]
        precondition(!P.configurationsMatch(legacy, P.configurationData(other)))
        precondition(!P.configurationsMatch(nil, nil))
        precondition(!P.configurationsMatch(Data("invalid".utf8), Data("invalid".utf8)))
        print("PASS: empty Group address compatibility preserves membership, type and topology differences")
    }

    static func testReadbackDiagnostics() {
        typealias P = SpaceConfigurationIntegrityPolicy
        let node: [String: Any] = ["uuid": "private-node-identity", "unicastAddress": "0046", "groupState": 0]
        let submitted: [String: Any] = ["groups": [], "nodes": [node], "spaceData": ["triggerZones": []], "updateTimestamp": 10]
        var remote = submitted
        remote["updateTimestamp"] = 20
        remote.removeValue(forKey: "spaceData")
        var remoteNode = node
        remoteNode["groupState"] = "0"
        remoteNode["groupAddress"] = NSNull()
        remote["nodes"] = [remoteNode]
        let text = P.readbackDiagnostic(submitted: submitted, remote: remote)
        precondition(text.contains("submittedTimestamp=10 remoteTimestamp=20"))
        precondition(text.contains("path=$.triggerZones submitted=array(count=0) remote=missing"))
        precondition(text.contains("path=$.memberships[0].groupAddress submitted=missing remote=null"))
        precondition(text.contains("path=$.memberships[0].groupState submitted=number(0) remote=string(length=1,sha256="))
        let persisted = P.configurationData(submitted)!
        precondition(text.hasSuffix(P.readbackDiagnostic(submittedConfiguration: persisted, remote: remote)))
        remoteNode["groupState"] = false
        remote["nodes"] = [remoteNode]
        precondition(P.readbackDiagnostic(submitted: submitted, remote: remote)
            .contains("groupState submitted=number(0) remote=bool(0)"))

        // Unknown extension dictionaries may carry names or credentials: neither
        // their keys nor values may escape through recursive diagnostics.
        let secret = "PRIVATE-KEY-DO-NOT-LOG\n[forged-log]"
        var privateRemote = submitted
        remoteNode["uuid"] = "private-remote-node-identity"
        remoteNode["deviceKey"] = secret
        privateRemote["nodes"] = [remoteNode]
        privateRemote["passwd"] = secret
        privateRemote["netKey"] = ["key": secret]
        privateRemote["appKey"] = ["key": secret]
        var privateSubmitted = submitted
        privateSubmitted["spaceData"] = ["triggerZones": [["items": [], "name": "old-private-name", secret: ["address": "0046", "number": 123456]]]]
        privateRemote["spaceData"] = ["triggerZones": [["items": [], "name": "new-private-name", secret: ["address": "0047", "number": 654321]]]]
        let privateText = P.readbackDiagnostic(submitted: privateSubmitted, remote: privateRemote)
        for forbidden in [secret, "old-private-name", "new-private-name", "private-node-identity", "private-remote-node-identity", "deviceKey", "passwd", "netKey", "appKey", "123456", "654321", "string(0047)"] {
            precondition(!privateText.contains(forbidden), "Unredacted diagnostic")
        }
        precondition(privateText.contains("redactedKey_"))
        precondition(privateText.contains("number(redacted)"))
        precondition(privateText.contains("extraRemoteNodes=1"))
        precondition(privateText.contains("missingRemoteNodes=1"))

        var ordered = submitted
        var reordered = submitted
        ordered["spaceData"] = ["triggerZones": [["items": [["groupAddress": 49152, "deviceAddress": 70], ["groupAddress": 49152, "deviceAddress": 71]]]]]
        reordered["spaceData"] = ["triggerZones": [["items": [["groupAddress": 49152, "deviceAddress": 71], ["groupAddress": 49152, "deviceAddress": 70]]]]]
        let orderText = P.readbackDiagnostic(submitted: ordered, remote: reordered)
        precondition(orderText.contains("path=$.triggerZones[0].items[0].deviceAddress submitted=number(70) remote=number(71)"))
        var many = submitted
        many["nodes"] = (0..<100).map { ["uuid": "private-node-\($0)", "unicastAddress": String(format: "%04X", $0 + 100)] }
        let limited = P.readbackDiagnostic(submitted: submitted, remote: many)
        precondition(limited.contains("scanLimited=true"))
        precondition(limited.components(separatedBy: "[SpaceConfigurationDiff] path=").count - 1 == 24)

        // Observations and transport/auth metadata must not manufacture a diff.
        var observations = submitted
        observations["passwd"] = secret
        observations["updateTimestamp"] = 99
        var observedNode = node
        observedNode["configComplete"] = true
        observations["nodes"] = [observedNode]
        let same = P.readbackDiagnostic(submitted: submitted, remote: observations)
        precondition(same.contains("canonicalEqual=true differencesShown=0 scanLimited=false"))
        precondition(!same.contains(secret))
        print("PASS: readback field paths, missing/null/types/order, persisted submission, redaction and bounded output")
        print(text)
    }
}
