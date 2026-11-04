import Foundation

@main enum CityCatalogTests {
    static func main() throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1])
        let countries = try CountryRegionCatalog(response: ["code": 200, "data": [["code": "US", "name": "United States"], ["code": "CN", "name": "China"], ["code": "FR", "name": "France"]]])
        let zones = try SiteTimeZoneCatalog(data: Data(contentsOf: repo.appendingPathComponent("SunSmart/all_utc_timezones.json")))
        try testDraft(countries: countries, zones: zones)
        try testStoredIdentity(zones: zones)
        try testSearchCancellation()
        print("PASS: city identity/name drafts, missing/legacy display, same-ID rename, GPS/manual values, search cancellation and replacement")
    }
    static func record(_ id: Int, name: String = "Springfield", zone: String = "America/Chicago") -> [String: Any] {
        ["id": id, "name": name, "names_json": ["en": "Springfield", "zh-Hans": "斯普林菲尔德"],
         "timezone": zone, "latitude": 39.7817, "longitude": -89.6501]
    }
    static func response() -> [String: Any] {
        ["code": 200, "data": [record(1), record(2, zone: "America/New_York")]]
    }
    static func testDraft(countries: CountryRegionCatalog, zones: SiteTimeZoneCatalog) throws {
        let catalog = try CityCatalog(response: response(), countryCode: "US")
        let one = catalog.entry(id: "geonames:1")!, two = catalog.entry(id: "geonames:2")!
        let initial = zones.value(matchingIdentifier: "Asia/Shanghai")!
        let chicago = zones.value(matchingIdentifier: one.timezoneIdentifier)!, newYork = zones.value(matchingIdentifier: two.timezoneIdentifier)!
        var draft = SiteFormDraft(siteName: "City", timezone: initial)
        precondition(!draft.selectCity(one, timezone: chicago), "City needs a confirmed matching country")
        draft.selectCountry(countries.entry(code: "US")!)
        let before = try draft.standardProperties()
        precondition(!draft.selectCity(one, timezone: nil) && (try? draft.standardProperties()) == before)
        precondition(!draft.selectCity(one, timezone: newYork) && (try? draft.standardProperties()) == before)
        precondition(draft.selectCity(one, timezone: chicago))
        precondition(draft.timezone == chicago && draft.text[.latitude] == "39.7817" && draft.text[.longitude] == "-89.6501")
        draft.editText(.latitude, value: " 1 ")
        draft.selectManualTimezone(newYork)
        precondition(draft.selectCity(one, timezone: chicago))
        precondition(draft.text[.latitude] == " 1 " && draft.timezone == newYork, "Same city preserves manual values")
        draft.selectCountry(countries.entry(code: "US")!)
        precondition(draft.city?.id == one.id)
        draft.selectCountry(countries.entry(code: "FR")!)
        precondition(draft.city == nil && draft.text[.latitude] == " 1 " && draft.text[.longitude] == nil && draft.timezone == newYork)
        let afterCountryChange = try draft.standardProperties()
        precondition(afterCountryChange.city == nil && afterCountryChange.cityId == nil && afterCountryChange.latitude == 1 && afterCountryChange.longitude == nil)
        precondition(!draft.selectCity(one, timezone: chicago), "Old-country rows cannot commit")
        draft.selectCountry(countries.entry(code: "US")!)
        precondition(draft.selectCity(two, timezone: newYork))
        draft.editText(.latitude, value: "")
        draft.editText(.longitude, value: "0")
        precondition(draft.selectCity(two, timezone: newYork) && draft.text[.latitude] == "")
        precondition(draft.selectCity(one, timezone: chicago), "A different city replaces prior manual values")
        let saved = try draft.standardProperties().jsonObject
        precondition(saved["city"] as? String == "Springfield" && saved["cityId"] as? Int == 1 && saved["latitude"] as? String == "39.7817")
        precondition(saved["longitude"] as? String == "-89.6501" && saved["countryRegion"] as? String == "US")
        precondition(catalog.entry(id: "geonames:\(saved["cityId"] as! Int)")?.record.id == one.record.id)
        draft.selectCountry(countries.entry(code: "CN")!)
        precondition(draft.city == nil && draft.timezone == initial && draft.text[.latitude] == nil && draft.text[.longitude] == nil)
        precondition(draft.applyCurrentLocation(latitude: 1.25, longitude: -2.5))
        draft.selectCountry(countries.entry(code: "US")!)
        precondition(draft.text[.latitude] == "1.25" && draft.text[.longitude] == "-2.5")
        precondition(draft.selectCity(one, timezone: chicago))
        precondition(draft.text[.latitude] == one.latitudeText && draft.text[.longitude] == one.longitudeText)
        precondition(draft.applyCurrentLocation(latitude: 1.25, longitude: -2.5))
        precondition(draft.selectCity(one, timezone: chicago))
        precondition(draft.text[.latitude] == "1.25" && draft.text[.longitude] == "-2.5")

        // Feedback must follow retained manual values, cleared city values and new city replacements.
        precondition(draft.selectCity(two, timezone: newYork))
        precondition(draft.coordinateValidation(for: .longitude) == .valid(two.record.longitude))
        precondition(draft.coordinateSources[.longitude] == .city, "Validation must preserve the coordinate source")
        draft.editText(.latitude, value: " 91 ")
        draft.selectCountry(countries.entry(code: "FR")!)
        precondition(draft.coordinateValidation(for: .latitude) == .outOfRange && draft.text[.latitude] == " 91 ")
        precondition(draft.coordinateValidation(for: .longitude) == .empty)
        draft.selectCountry(countries.entry(code: "US")!)
        precondition(draft.selectCity(one, timezone: chicago))
        precondition(draft.coordinateValidation(for: .latitude) == .valid(one.record.latitude))
        precondition(draft.coordinateValidation(for: .longitude) == .valid(one.record.longitude))

        let stored = SiteStandardProperties(latitude: 1.25, longitude: 0, countryRegion: "US", city: "Springfield", cityId: 1)
        var editor = SiteFormDraft(values: .init(siteName: "Existing", imageId: 1, timezone: initial),
                                   properties: stored, siteType: .standard)
        editor.resolveStoredCity(one)
        precondition(editor.city?.id == one.id && editor.timezone == initial)
        precondition((try? editor.standardProperties()) == stored, "Hydration must not apply city coordinates")
        precondition(editor.selectCity(one, timezone: chicago))
        precondition((try? editor.standardProperties()) == stored && editor.timezone == initial)
        editor.selectCountry(countries.entry(code: "FR")!)
        editor.resolveStoredCity(one)
        precondition(editor.city == nil && editor.cityID == nil && editor.timezone == initial)
        precondition(editor.text[.latitude] == "1.25" && editor.text[.longitude] == "0.0")
        editor.selectCountry(countries.entry(code: "US")!)
        precondition(editor.selectCity(two, timezone: newYork))
        precondition(editor.timezone == newYork && editor.cityID == 2)

        var unknown = SiteFormDraft(siteName: "Unknown", timezone: nil)
        unknown.selectCountry(countries.entry(code: "US")!)
        precondition(unknown.selectCity(one, timezone: chicago))
        unknown.selectCountry(countries.entry(code: "CN")!)
        precondition(unknown.timezone == nil && unknown.isNameValid(isDuplicate: false))
    }

    static func testStoredIdentity(zones: SiteTimeZoneCatalog) throws {
        let catalog = try CityCatalog(response: response(), countryCode: "US")
        let renamed = try CityCatalog(response: ["code": 200, "data": [record(1, name: "New raw name")]], countryCode: "US")
        let empty = try CityCatalog(response: ["code": 200, "data": []], countryCode: "US")
        let initial = zones.value(matchingIdentifier: "Asia/Shanghai")!
        for props in [SiteStandardProperties(countryRegion: "US", city: "1"),
                      .init(countryRegion: "US", cityId: 1), .init(countryRegion: "US", city: " ", cityId: 1),
                      .init(countryRegion: "US", city: "Springfield", cityId: 999),
                      .init(countryRegion: "CN", city: "Springfield", cityId: 1)] {
            var draft = SiteFormDraft(values: .init(siteName: "Old", imageId: 1, timezone: initial), properties: props, siteType: .standard)
            precondition(draft.resolvedCity(in: catalog) == nil)
            draft.resolveStoredCity(catalog.entries[0])
            precondition((try? draft.standardProperties()) == props, "No match does not migrate/dirty old values")
        }
        let stored = SiteStandardProperties(latitude: 1, longitude: 2, countryRegion: "US", city: "Old raw name", cityId: 1)
        var draft = SiteFormDraft(values: .init(siteName: "Site", imageId: 1, timezone: initial), properties: stored, siteType: .standard)
        precondition(draft.resolvedCity(in: catalog)?.record.id == 1, "ID matches independently of stale server name")
        precondition(draft.resolvedCity(in: catalog)?.displayName(language: "zh-Hans") == "斯普林菲尔德")
        draft.resolveStoredCity(renamed.entries[0])
        precondition(draft.resolvedCity(in: empty) == nil && draft.resolvedCity(in: nil) == nil)
        precondition((try? draft.standardProperties()) == stored && draft.timezone == initial)
        precondition(draft.selectCity(renamed.entries[0], timezone: zones.value(matchingIdentifier: "America/Chicago")))
        let saved = try draft.standardProperties()
        precondition(saved.city == "New raw name" && saved.cityId == 1 && saved.latitude == 1 && saved.longitude == 2)
        precondition(draft.timezone == initial)
        let unknown = try CityCatalog(response: ["code": 200, "data": [record(3, zone: "Unknown/City")]], countryCode: "US")
        precondition(!draft.selectCity(unknown.entries[0], timezone: nil))
        precondition((try? draft.standardProperties()) == saved)
    }

    static func testSearchCancellation() throws {
        let catalog = try CityCatalog(response: response(), countryCode: "US")
        let loader = CityCatalogLoader()
        var state = SiteLocationSearchState(context: "US")
        state.beginSearch(); let old = state.ticket
        var unexpected = false, done = false
        loader.search(catalog: catalog, query: "Spring") { _ in unexpected = true }
        state.replaceSelection(id: nil, context: "CN"); state.beginSearch()
        state.replaceSelection(id: nil, context: "US"); state.beginSearch()
        state.updateQuery("Spring", isComposing: false)
        precondition(!state.accepts(old))
        let ticket = state.ticket
        state.updateQuery("zhong", isComposing: true)
        precondition(state.ticket == ticket)
        loader.search(catalog: catalog, query: state.query) { entries in
            precondition(state.accepts(ticket) && entries.count == 2); done = true
        }
        let deadline = Date().addingTimeInterval(5)
        while !done, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        precondition(done && !unexpected)
        state.invalidateResults()
        precondition(!state.accepts(ticket) && state.query == "Spring")
        loader.search(catalog: catalog, query: "") { _ in unexpected = true }
        loader.cancel(); state.dismiss()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        precondition(!unexpected)
    }
}
