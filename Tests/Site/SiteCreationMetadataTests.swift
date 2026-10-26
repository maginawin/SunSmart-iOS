import Foundation

@main enum SiteCreationMetadataTests {
    static func main() throws {
        let properties = SiteStandardProperties(latitude: 0, longitude: -72.123456789,
            countryRegion: "SG", postalCode: "018983", city: "795565", address: "1 Marina Boulevard",
            siteDescription: "Lobby")
        let bytes = try JSONSerialization.data(withJSONObject: properties.jsonObject)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        precondition(object["latitude"] as? Double == 0 && !(object["latitude"] is String))
        precondition(object["city"] as? String == "795565" && object["postalCode"] as? String == "018983")
        precondition(object["address"] as? String == properties.address && object["streetAddress"] == nil)
        let roundtrip = try SiteStandardProperties.Patch(object).applying(to: .init())
        precondition(roundtrip == properties)
        let missing = try SiteStandardProperties.Patch([:])
        precondition(missing.applying(to: properties) == properties)
        let partial = try SiteStandardProperties.Patch(["latitude": NSNull(), "city": "99999999"])
        let merged = partial.applying(to: properties)
        precondition(merged.latitude == nil && merged.longitude == properties.longitude)
        precondition(merged.city == "99999999" && merged.address == properties.address)
        precondition(partial.merging(to: properties, localTimestamp: 10, remoteTimestamp: 9, hasPendingChanges: false) == properties)
        precondition(partial.merging(to: properties, localTimestamp: 10, remoteTimestamp: 11, hasPendingChanges: true) == properties)
        precondition(partial.merging(to: properties, localTimestamp: 10, remoteTimestamp: 10, hasPendingChanges: false) == merged)
        for object: [String: Any] in [["latitude": true], ["longitude": false], ["latitude": "0"],
            ["longitude": Double.nan], ["latitude": Double.infinity], ["latitude": 91],
            ["longitude": -181], ["city": 795565], ["address": []]] {
            do { _ = try SiteStandardProperties.Patch(object); preconditionFailure("Invalid types/ranges must fail") }
            catch is SiteStandardProperties.Patch.ParseError {}
        }
        for latitude in [-90, 0, 90] {
            let parsed = try SiteStandardProperties.Patch(["latitude": latitude, "longitude": 180.0]).applying(to: .init())
            precondition(parsed.latitude == Double(latitude) && parsed.longitude == 180)
        }
        var local = SitePropsLocalState(values: .init(siteName: "Site", imageId: 1, timezone: nil),
            lastUpdate: 10, lastUploadCloudTimestamp: 10, pending: .init(fields: [], timestamp: nil),
            standardProperties: properties)
        let remote = SitePropsRemoteSnapshot(siteName: nil, imageId: nil, timezone: nil,
            providedFields: [], timestamp: 10, standardProperties: partial)
        let result = SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote)
        precondition(result.shouldPersist && result.state.standardProperties == merged)
        let full = SitePropsRemoteSnapshot(siteName: nil, imageId: nil, timezone: nil,
            providedFields: [], timestamp: 10, standardProperties: try .init(properties.jsonObject))
        precondition(SitePropsEditPolicy.mergeRetrieve(local: result.state, remote: full).state.standardProperties == properties)
        local = .init(values: local.values, lastUpdate: 11, lastUploadCloudTimestamp: 10,
            pending: .init(fields: [.siteName], timestamp: 11), standardProperties: properties)
        precondition(!SitePropsEditPolicy.mergeRetrieve(local: local, remote: remote).shouldPersist)

        let extensionData = SiteExtensionData()
        let extensionObject = try extensionData.jsonObject()
        for key in SiteStandardProperties.keys + ["streetAddress"] { precondition(extensionObject[key] == nil) }
        let opaque = try SiteExtensionData.parse(["future": ["keep": 7], "triggerZones": []])
        let withZone = opaque.replacingZone(SiteTriggerZone())!
        precondition(withZone.fields["future"] == opaque.fields["future"])
        var state = SiteExtensionState()
        state.receive(opaque, timestamp: 10)
        state.commit(withZone, now: 11, siteTimestamp: 10)
        state.receive(withZone, timestamp: 12)
        precondition(state.pending == nil && state.data == withZone)
        print("PASS: standard Site JSON types, null/missing, version merge and independent extension state")
    }
}
