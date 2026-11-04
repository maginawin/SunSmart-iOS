import Foundation

@main enum SiteCreationMetadataTests {
    static func main() throws {
        try cityIdentityRoundTripAndReceipts()
        let properties = SiteStandardProperties(latitude: 0, longitude: -72.123456789,
            countryRegion: "SG", postalCode: "018983", city: "795565", address: "1 Marina Boulevard",
            siteDescription: "Lobby")
        let bytes = try JSONSerialization.data(withJSONObject: properties.jsonObject)
        let object = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
        precondition(object["latitude"] as? String == "0.0")
        precondition(object["longitude"] as? String == "-72.123456789")
        let empty = SiteStandardProperties().jsonObject
        precondition(empty["latitude"] is NSNull && empty["longitude"] is NSNull)
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
        for object: [String: Any] in [["latitude": true], ["longitude": false], ["latitude": "invalid"],
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

    // Losing cityId used to be invisible: the parser silently ignored it and export omitted it.
    static func cityIdentityRoundTripAndReceipts() throws {
        let original = try SiteStandardProperties.Patch(["city": "shenzhen", "cityId": 1880252])
            .applying(to: .init())
        let encoded = original.jsonObject
        precondition(encoded["cityId"] as? Int == 1880252, "Site cityId must survive parsing and JSON export as an integer")
        precondition(encoded["city"] as? String == "shenzhen")
        precondition(SiteStandardProperties().jsonObject["cityId"] is NSNull)
        let unchanged = try SiteStandardProperties.Patch([:]).applying(to: original)
        precondition(unchanged == original)
        let nameOnly = try SiteStandardProperties.Patch(["city": "Shenzhen"]).applying(to: original)
        precondition(nameOnly.jsonObject["cityId"] as? Int == 1880252)
        let cleared = try SiteStandardProperties.Patch(["cityId": NSNull()]).applying(to: original)
        precondition(cleared.city == "shenzhen" && cleared.jsonObject["cityId"] is NSNull)
        for invalid: Any in [true, false, 0, -1, 1.5, "1880252", Double.infinity, Double.nan,
                             NSNumber(value: UInt64.max), [], [:]] {
            do { _ = try SiteStandardProperties.Patch(["cityId": invalid]); preconditionFailure("Invalid cityId must be rejected") }
            catch is SiteStandardProperties.Patch.ParseError {}
        }
        let values = SitePropsValues(siteName: "Site", imageId: 1, timezone: nil)
        let local = SitePropsLocalState(values: values, lastUpdate: 10, lastUploadCloudTimestamp: 10,
            pending: .init(fields: [], timestamp: nil), standardProperties: original)
        let another = try SiteStandardProperties.Patch(["cityId": 1880253]).applying(to: original)
        let request = SitePropsEditPolicy.makeUpdateSnapshot(siteId: "site", local: local,
            original: values, draft: values, now: 11, originalStandardProperties: original, standardProperties: another)!
        let patch = request.standardProperties.patch(for: request.fields).jsonObject
        precondition(patch["city"] as? String == "shenzhen" && patch["cityId"] as? Int == 1880253,
                     "Same-name different-ID choices must send both fields")
        for response: [String: Any] in [["city": "shenzhen"], ["cityId": 1880253],
                                        ["city": "shenzhen", "cityId": 1880252]] {
            let remote = SitePropsRemoteSnapshot(siteName: nil, imageId: nil, timezone: nil,
                providedFields: [], timestamp: 11, standardProperties: try .init(response))
            precondition(!SitePropsEditPolicy.updateResponseMatches(request: request, response: remote))
        }
        let accepted = SitePropsRemoteSnapshot(siteName: nil, imageId: nil, timezone: nil,
            providedFields: [], timestamp: 11, standardProperties: try .init(patch))
        precondition(SitePropsEditPolicy.updateResponseMatches(request: request, response: accepted))
        let renamed = SitePropsEditPolicy.makeUpdateSnapshot(siteId: "site", local: local,
            original: values, draft: values, now: 11, originalStandardProperties: original, standardProperties: nameOnly)!
        precondition(renamed.standardProperties.patch(for: renamed.fields).jsonObject["cityId"] as? Int == 1880252,
                     "Same-ID rename must send the ID too")
        let pending = SitePropsLocalState(values: values, lastUpdate: 11, lastUploadCloudTimestamp: 10,
            pending: .init(fields: request.fields, timestamp: 11), standardProperties: another)
        for response: [String: Any] in [["city": "shenzhen"], ["cityId": 1880253],
                                        ["city": "shenzhen", "cityId": 1880252]] {
            let remote = SitePropsRemoteSnapshot(siteName: nil, imageId: nil, timezone: nil,
                providedFields: [], timestamp: 11, standardProperties: try .init(response))
            precondition(!SitePropsEditPolicy.mergeRetrieve(local: pending, remote: remote).shouldPersist)
        }
        precondition(SitePropsEditPolicy.mergeRetrieve(local: pending, remote: accepted).state.pending.fields.isEmpty)
        let legacyPending = SitePropsLocalState(values: values, lastUpdate: 11, lastUploadCloudTimestamp: 10,
            pending: .init(fields: .city, timestamp: 11), standardProperties: .init(city: "1880252"))
        let retry = SitePropsEditPolicy.makeUpdateSnapshot(siteId: "site", local: legacyPending,
            original: values, draft: values, now: 12)!
        precondition(retry.fields == [.city, .cityId] && retry.timestamp == 11,
                     "A persisted city-only pending mask must resend the complete identity without migrating its value")
        let retryPatch = retry.standardProperties.patch(for: retry.fields).jsonObject
        precondition(retryPatch["city"] as? String == "1880252" && retryPatch["cityId"] is NSNull)
    }
}
