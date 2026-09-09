import Foundation

@main
struct SiteTriggerZoneDataTests {
    static func main() throws {
        func check(_ condition: @autoclosure () -> Bool, _ message: String) {
            precondition(condition(), message)
        }
        var data = SiteExtensionData()
        let zones = (0..<100).map { _ in SiteTriggerZone() }
        data.replaceZones(zones)
        check(data.supportsEmptyZoneEditing, "100 Site zones are supported")
        check(Set(zones.map(\.zoneId)).count == 100, "Empty zones have distinct durable identities")
        check(tryRoundTrip(data) == data, "IDs and order survive serialization")
        data.replaceZones(zones + [SiteTriggerZone()])
        check(!data.supportsEmptyZoneEditing, "101 zones must not be silently truncated")
        data.replaceZones([zones[0], zones[0]])
        check(!data.supportsEmptyZoneEditing, "Duplicate IDs must block editing")
        data.replaceZones([zones[0]])
        data.fields["futureSetting"] = .object(["value": .integer(Int64.max)])
        check(tryRoundTrip(data) == data, "Unknown extension values survive roundtrip")
        let object = try data.jsonObject()
        let text = String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
        let parsedObject = try SiteExtensionData.parse(object)
        let parsedText = try SiteExtensionData.parse(text)
        check(parsedObject == data && parsedText == data,
              "Server object and JSON-string extensions preserve zones and unknown fields equally")
        let emptyObject = try SiteExtensionData.parse([String: Any]())
        let emptyText = try SiteExtensionData.parse("{}")
        check(emptyText == emptyObject && emptyText.fields["triggerZones"] == nil,
              "The startup response extensionData string is a missing-zone patch, not a deletion")
        let invalidValues: [Any] = [NSNull(), 7, true, [Any](), "", "invalid", "[]", "null", "7",
                                    "true", "\"{}\"", ["invalid": Date()], ["invalid": Double.nan]]
        for value in invalidValues {
            do {
                _ = try SiteExtensionData.parse(value)
                preconditionFailure("Invalid extension must throw a catchable Swift error")
            } catch { /* Unsupported remote data must never raise an Objective-C exception. */ }
        }
        var startup = SiteTriggerZoneState()
        startup.receive(data, timestamp: 10)
        startup.receive(emptyText, timestamp: 11)
        check(startup.data.zones == data.zones, "Stringified empty object does not erase existing zones")
        startup.commit(SiteExtensionData(), now: 20, siteTimestamp: 11)
        let startupPending = startup.pending
        startup.receive(emptyText, timestamp: 30)
        check(startup.pending == startupPending, "Startup stringified empty object cannot acknowledge pending edits")
        var state = SiteTriggerZoneState()
        state.receive(SiteExtensionData(), timestamp: 10)
        state.commit(data, now: 20, siteTimestamp: 10)
        check(state.pending != nil, "Local changes are durable pending work")
        let first = state.pending!
        state.submitted = first
        var secondData = data
        secondData.replaceZones([zones[0], zones[1]])
        state.commit(secondData, now: 20, siteTimestamp: 10)
        state.receive(first.target, timestamp: first.timestamp)
        check(state.data == secondData && state.pending != nil && !state.conflict,
              "An older own response rebases the new draft without discarding it")
        check(state.pending?.base == first.target, "The next request compares against the acknowledged base")
        let second = state.pending!
        state.receive(second.target, timestamp: second.timestamp)
        check(state.pending == nil && state.data == secondData, "Exact readback acknowledges the current draft")
        var missing = SiteExtensionData()
        missing.fields.removeValue(forKey: "triggerZones")
        state.receive(missing, timestamp: second.timestamp + 1)
        check(state.data.zones?.count == 2, "Missing zones do not erase existing zones")
        var deleted = secondData
        deleted.replaceZones([])
        state.commit(deleted, now: 30, siteTimestamp: 10)
        let deletion = state.pending!
        state.receive(missing, timestamp: 50)
        check(state.pending == deletion, "Missing fields cannot confirm a pending deletion")
        state.receive(deleted, timestamp: deletion.timestamp)
        check(state.data.zones?.isEmpty == true && state.pending == nil, "Explicit empty array confirms deletion")
        state.commit(data, now: 60, siteTimestamp: 10)
        state.receive(secondData, timestamp: 61)
        check(state.conflict && state.data == data, "Concurrent remote edits preserve the local draft and signal conflict")
        state.discardPending()
        check(state.data == secondData && state.pending == nil, "Explicit conflict resolution adopts the server version")
        let beforeOldResponse = state
        state.receive(SiteExtensionData(), timestamp: 1)
        check(state == beforeOldResponse, "Old responses cannot resurrect deleted or replaced data")
        var future = data
        future.fields["schemaVersion"] = .integer(2)
        check(!future.supportsEmptyZoneEditing && tryRoundTrip(future) == future, "Future schema is retained and read-only")
        var nonempty = zones[0]
        nonempty.fields["members"] = .array([.object(["spaceId": .string("private")])])
        future = SiteExtensionData()
        future.replaceZones([nonempty])
        check(!future.supportsEmptyZoneEditing, "Nonempty members cannot be edited by phase-one controls")
        let restored = try JSONDecoder().decode(SiteTriggerZoneState.self, from: JSONEncoder().encode(state))
        check(restored == state, "Restart restores the full sync state")
        print("PASS: Site Trigger Zone identity, 100-zone limit, compatibility, pending, conflict and restart checks")
    }

    static func tryRoundTrip(_ value: SiteExtensionData) -> SiteExtensionData? {
        guard let encoded = try? JSONEncoder().encode(value) else { return nil }
        return try? JSONDecoder().decode(SiteExtensionData.self, from: encoded)
    }
}
