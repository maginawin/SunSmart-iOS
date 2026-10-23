import Foundation

@main
enum SiteHDBTypeTests {
    static func check(_ value: @autoclosure () throws -> Bool, _ message: String = "Site type contract") rethrows {
        let result = try value()
        precondition(result, message)
    }

    static func main() throws {
        for raw in [#"{}"#, #"{"siteType":null}"#, #"{"isHdbSite":true}"#,
                    #"{"isHdbSite":false}"#, #"{"isHdbSite":null}"#,
                    #"{"siteType":true}"#, #"{"siteType":1}"#, #"{"siteType":"hdb"}"#,
                    #"{"siteType":"Unknown"}"#, #"{"siteType":"true"}"#] {
            let data = try SiteExtensionData.parse(raw)
            let object = try data.jsonObject()
            precondition(!data.isHdbSite && data.siteType == nil && object["siteType"] is NSNull,
                         "Legacy or invalid types must export null: \(raw)")
            precondition(object["isHdbSite"] == nil)
        }
        for (value, expected) in [("Standard", false), ("HDB", true)] {
            let data = try SiteExtensionData.parse(["siteType": value, "isHdbSite": !expected])
            precondition(data.isHdbSite == expected)
            try check(data.jsonObject()["siteType"] as? String == value)
            try check(data.jsonObject()["isHdbSite"] == nil)
        }
        var hdb = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"siteType":"HDB","future":{"keep":7}}"#)
        let restored = try JSONDecoder().decode(SiteExtensionData.self, from: JSONEncoder().encode(hdb))
        precondition(restored.isHdbSite && restored.fields["future"] == hdb.fields["future"])
        let zone = SiteTriggerZone()
        hdb = hdb.replacingZone(zone)!
        precondition(hdb.isHdbSite, "Editing a Trigger Zone must retain the Site type")
        let props = try SiteExtensionUpdatePayload.props(extensionData: hdb)
        precondition((props["extensionData"] as? [String: Any])?["siteType"] as? String == "HDB")

        var state = SiteExtensionState()
        state.receive(hdb, timestamp: 10)
        // Include a conflicting old flag: partial legacy replies cannot clear a new HDB type.
        let partial = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"isHdbSite":false}"#)
        precondition(partial.fields["siteType"] == nil, "Parsing must retain missing-field evidence")
        state.receive(partial, timestamp: 11)
        precondition(state.data.isHdbSite)
        let explicitNull = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"siteType":null,"isHdbSite":true}"#)
        state.receive(explicitNull, timestamp: 12)
        precondition(!state.data.isHdbSite && state.data.siteType == nil)
        state.receive(hdb, timestamp: 11)
        precondition(!state.data.isHdbSite, "Stale HDB responses cannot restore a cleared type")

        let explicitStandard = try SiteExtensionData.parse(#"{"schemaVersion":1,"triggerZones":[],"siteType":"Standard"}"#)
        precondition(partial == explicitNull && explicitNull == explicitStandard)
        try check(explicitNull.jsonObject()["siteType"] is NSNull)
        try check(explicitStandard.jsonObject()["siteType"] as? String == "Standard")
        var standard = SiteExtensionState()
        standard.receive(partial, timestamp: 20)
        standard.receive(explicitStandard, timestamp: 20)
        precondition(!standard.hasAmbiguousRemote)
        let changed = standard.data.replacingZone(zone)!
        standard.commit(changed, now: 30, siteTimestamp: 20)
        var response = changed
        response.fields.removeValue(forKey: "siteType")
        standard.receive(response, timestamp: 31)
        precondition(standard.pending == nil, "Missing type can confirm a Zone-only save")
        precondition(SiteExtensionData.targetCoversServerChanges(base: partial, server: explicitStandard, target: changed))

        var unconfirmed = SiteExtensionState()
        unconfirmed.receive(explicitStandard, timestamp: 40)
        var newType = explicitStandard
        newType.siteType = .hdb
        unconfirmed.commit(newType, now: 41, siteTimestamp: 40)
        unconfirmed.submitted = unconfirmed.pending
        unconfirmed.receive(partial, timestamp: 42)
        precondition(unconfirmed.pending != nil && unconfirmed.data.isHdbSite && unconfirmed.serverTimestamp == 40,
                     "A missing field must not acknowledge a new HDB type")
        unconfirmed.receive(newType, timestamp: 43)
        precondition(unconfirmed.pending == nil && unconfirmed.submitted == nil)
        unconfirmed.receive(explicitStandard, timestamp: 43)
        precondition(unconfirmed.hasAmbiguousRemote && unconfirmed.data.isHdbSite,
                     "A true type conflict at the same version must remain protected")
        unconfirmed.receive(explicitStandard, timestamp: 44)
        precondition(!unconfirmed.data.isHdbSite && !unconfirmed.hasAmbiguousRemote)

        // Newer local edits and an older in-flight receipt retain their existing identity/rebase rules.
        var queued = SiteExtensionState()
        queued.receive(newType, timestamp: 50)
        let first = newType.replacingZone(zone)!
        queued.commit(first, now: 51, siteTimestamp: 50)
        queued.submitted = queued.pending
        let second = first.replacingZone(SiteTriggerZone())!
        queued.commit(second, now: 52, siteTimestamp: 50)
        let operation = queued.pending!.operationId
        queued.receive(first, timestamp: 53)
        precondition(queued.pending?.operationId == operation && queued.pending?.base == first && queued.data == second)
        queued.receive(second, timestamp: 54)
        precondition(queued.pending == nil && queued.data.isHdbSite)
        print("PASS: Site three-state encoding, legacy true exclusion, new-key precedence, Zone edits, partial/late responses, pending confirmation and rebasing")
    }
}
