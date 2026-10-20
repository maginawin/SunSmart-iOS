import Foundation

@main
enum SiteHDBTypeTests {
    static func exportedType(_ data: SiteExtensionData) throws -> Bool? {
        try data.jsonObject()["isHdbSite"] as? Bool
    }

    static func main() throws {
        // Missing/null/untyped values must never enable HDB and export a Boolean default.
        for raw in [#"{}"#, #"{"isHdbSite":null}"#, #"{"isHdbSite":false}"#,
                    #"{"isHdbSite":"true"}"#, #"{"isHdbSite":1}"#] {
            let data = try SiteExtensionData.parse(raw)
            let value = try exportedType(data)
            precondition(value == false, "Legacy/default Site must export isHdbSite=false: \(raw)")
        }
        var hdb = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"isHdbSite":true,"future":{"keep":7}}"#)
        let restored = try JSONDecoder().decode(SiteExtensionData.self, from: JSONEncoder().encode(hdb))
        precondition(tryValue(restored) == true && restored.fields["future"] == hdb.fields["future"])
        let zone = SiteTriggerZone()
        hdb = hdb.replacingZone(zone)!
        precondition(tryValue(hdb) == true, "Editing a Trigger Zone must retain the Site type")

        var state = SiteExtensionState()
        state.receive(hdb, timestamp: 10)
        let partial = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[]}"#)
        state.receive(partial, timestamp: 11)
        precondition(tryValue(state.data) == true, "Partial cloud response must not clear a saved HDB type")
        let explicitNull = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"isHdbSite":null}"#)
        state.receive(explicitNull, timestamp: 12)
        precondition(tryValue(state.data) == false, "Explicit null must resolve to Standard")

        // A legacy server representation is semantically equal to explicit false.
        var standard = SiteExtensionState()
        standard.receive(partial, timestamp: 20)
        let explicitFalse = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"isHdbSite":false}"#)
        standard.receive(explicitFalse, timestamp: 20)
        precondition(!standard.hasAmbiguousRemote, "Default normalization must not introduce a same-version conflict")
        let changed = standard.data.replacingZone(zone)!
        standard.commit(changed, now: 30, siteTimestamp: 20)
        var response = changed
        response.fields.removeValue(forKey: "isHdbSite")
        standard.receive(response, timestamp: 31)
        precondition(standard.pending == nil, "Legacy false representation must confirm a Zone save")

        var unconfirmed = SiteExtensionState()
        unconfirmed.receive(explicitFalse, timestamp: 40)
        var newType = explicitFalse
        newType.fields["isHdbSite"] = .bool(true)
        unconfirmed.commit(newType, now: 41, siteTimestamp: 40)
        unconfirmed.receive(partial, timestamp: 42)
        precondition(unconfirmed.pending != nil && tryValue(unconfirmed.data) == true,
                     "An omitted field must not acknowledge an unconfirmed type change")
        unconfirmed.receive(newType, timestamp: 43)
        precondition(unconfirmed.pending == nil)
        print("PASS: Site HDB defaults, strict Bool, roundtrip, Zone edits, partial responses and pending confirmation")
    }

    static func tryValue(_ data: SiteExtensionData) -> Bool? { try! exportedType(data) }
}
