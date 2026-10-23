import Foundation

@main enum SiteCreationMetadataTests {
    static func main() throws {
        let keys = ["countryRegion", "city", "description", "streetAddress", "postalCode", "latitude", "longitude"]
        let legacy = try SiteExtensionData.parse(#"{"schemaVersion":2,"triggerZones":[],"future":{"keep":7}}"#)
        let object = try legacy.jsonObject()
        for key in keys {
            precondition(object[key] is NSNull, "Legacy export must explicitly fill missing metadata with null: \(key)")
            precondition(legacy.fields[key] == nil, "Parsing must preserve missing-field evidence")
        }
        var explicit = legacy
        keys.forEach { explicit.fields[$0] = .null }
        precondition(explicit == legacy, "Null defaults must not cause false conflicts")
        precondition(object["schemaVersion"] as? Int == 2)
        precondition(legacy.fields["future"] == .object(["keep": .integer(7)]))

        var configured = legacy
        configured.fields["description"] = .string("Lobby")
        configured.fields["latitude"] = .string("0")
        var state = SiteExtensionState()
        state.receive(configured, timestamp: 10)
        state.receive(legacy, timestamp: 10)
        precondition(!state.hasAmbiguousRemote, "Partial same-version responses must preserve known metadata")
        state.receive(legacy, timestamp: 11)
        precondition(state.data.fields["description"] == .string("Lobby"))
        precondition(state.data.fields["latitude"] == .string("0"))
        var cleared = legacy
        cleared.fields["description"] = .null
        state.receive(cleared, timestamp: 12)
        precondition(state.data.fields["description"] == .null)
        precondition(state.data.fields["latitude"] == .string("0"))

        var edited = state.data
        edited.fields["description"] = .string("New description")
        state.commit(edited, now: 13, siteTimestamp: 12)
        state.receive(legacy, timestamp: 14)
        precondition(state.pending != nil, "Omitted edited metadata cannot confirm a pending edit")
        state.receive(edited, timestamp: 15)
        precondition(state.pending == nil && state.data == edited)
        let zone = SiteTriggerZone()
        let withZone = edited.replacingZone(zone)!
        precondition(withZone.fields["description"] == .string("New description"))
        precondition(withZone.fields["future"] == legacy.fields["future"])
        let roundtrip = try JSONDecoder().decode(SiteExtensionData.self, from: JSONEncoder().encode(withZone))
        precondition(roundtrip == withZone)
        print("PASS: Site metadata null defaults, partial response preservation, explicit clear, pending confirmation and Zone roundtrip")
    }
}
