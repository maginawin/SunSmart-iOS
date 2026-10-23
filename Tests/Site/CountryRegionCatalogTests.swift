import Foundation

@main enum CountryRegionCatalogTests {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let data = try Data(contentsOf: root.appendingPathComponent("SunSmart/country_regions.json"))
        let catalog = try CountryRegionCatalog(data: data)
        let snapshot = try String(contentsOf: root.appendingPathComponent("Tests/Site/Fixtures/country_region_iso_codes.txt"), encoding: .utf8)
        let expected = Set(snapshot.split(separator: "\n").filter { !$0.hasPrefix("#") }.flatMap { $0.split(separator: " ").map(String.init) })
        precondition(expected.count == 249 && Set(catalog.entries.map(\.code)) == expected)
        precondition(catalog.entries.allSatisfy { !($0.names["en"] ?? "").isEmpty && !($0.names["zh-Hans"] ?? "").isEmpty })
        for (left, right) in zip(catalog.entries, catalog.entries.dropFirst()) {
            precondition(left.names["en"]!.compare(right.names["en"]!, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                                   locale: Locale(identifier: "en_US_POSIX")) != .orderedDescending)
        }
        precondition(catalog.displayName(forStoredCode: "CN", language: "en") == "China")
        precondition(catalog.displayName(forStoredCode: "CN", language: "zh-Hans") == "中国")
        precondition(catalog.displayName(forStoredCode: "CN", language: "de") == "China")
        precondition(catalog.displayName(forStoredCode: nil, language: "en") == nil)
        precondition(catalog.displayName(forStoredCode: "ZZ", language: "zh-Hans") == "ZZ")
        precondition(catalog.displayName(forStoredCode: "Legacy country", language: "en") == "Legacy country")
        for query in ["  ", "\n\t", ""] { precondition(catalog.entries(matching: query) == catalog.entries) }
        for query in ["china", "CHINA", "中国", "cn", "ＣＮ"] {
            precondition(catalog.entries(matching: query).contains { $0.code == "CN" })
        }
        precondition(catalog.entries(matching: "c").contains { $0.code == "FR" })
        precondition(catalog.entries(matching: "  aland islands ").map(\.code) == ["AX"])
        precondition(catalog.entries(matching: "no-country-12345").isEmpty)
        let results = catalog.entries(matching: "c")
        precondition(results == catalog.entries.filter { entry in results.contains(entry) }, "Filtering preserves English name order")

        let small = try CountryRegionCatalog(data: Data(#"{"schemaVersion":1,"countries":[{"code":"FR","names":{"en":"France"}},{"code":"CN","names":{"en":"China","zh-Hans":"中国"}},{"code":"CA","names":{"en":"Canada","zh-Hans":""}},{"code":"AX","names":{"en":"Åland Islands"}}]}"#.utf8))
        precondition(small.entries.map(\.code) == ["AX", "CA", "CN", "FR"])
        precondition(small.entries(matching: "C").map(\.code) == ["CA", "CN", "FR"])
        precondition(small.displayName(forStoredCode: "FR", language: "zh-Hans") == "France")
        precondition(small.displayName(forStoredCode: "CA", language: "zh-Hans") == "Canada")
        for invalid in [
            "broken", #"{"schemaVersion":2,"countries":[]}"#, #"{"schemaVersion":1,"countries":[]}"#,
            #"{"schemaVersion":1,"countries":[{"code":"cn","names":{"en":"China"}}]}"#,
            #"{"schemaVersion":1,"countries":[{"code":"中国","names":{"en":"China"}}]}"#,
            #"{"schemaVersion":1,"countries":[{"code":"CN","names":{"en":" "}}]}"#,
            #"{"schemaVersion":1,"countries":[{"code":"CN","names":{"zh-Hans":"中国"}}]}"#,
            #"{"schemaVersion":1,"countries":[{"code":"CN","names":{"en":"China"}},{"code":"CN","names":{"en":"China"}}]}"#
        ] {
            do { _ = try CountryRegionCatalog(data: Data(invalid.utf8)); preconditionFailure("Invalid catalog must fail") }
            catch {}
        }
        do { _ = try CountryRegionCatalog.load(bundle: .main); preconditionFailure("Fixture bundle has no country resource") }
        catch CountryRegionCatalog.CatalogError.resourceMissing {}

        // Use production field state and draft serialization together. Query/close events
        // must never become a selected code, including an exact name/code and empty input.
        for initial in [nil, "CN"] as [String?] {
            var draft = SiteCreationDraft(siteName: "Country test", timezone: nil)
            if let initial { draft.selectCountry(catalog.entry(code: initial)!) }
            var state = SiteLocationSearchState(selectedID: draft.countryRegionCode, context: "countries")
            let original = draft.extensionData
            precondition(draft.isNameValid(isDuplicate: false), "Country remains optional")
            for query in ["China", "CN", "US", "United States", "任意国家", ""] {
                state.beginSearch()
                precondition(state.isExpanded && state.query.isEmpty)
                state.beginSearch()
                state.updateQuery(query, isComposing: false)
                state.beginSearch()
                precondition(state.query == query, "Tapping an active editor must preserve input")
                state.dismiss() // Shared outside/down-arrow/Return/focus/CREATE cancellation.
                state.dismiss() // A later didEndEditing callback must be harmless.
                precondition(state.selectedID == initial && !state.isExpanded && state.query.isEmpty)
                precondition(draft.extensionData == original)
                let stored = try draft.extensionData.jsonObject()["countryRegion"]
                if let initial { precondition(stored as? String == initial) }
                else { precondition(stored is NSNull) }
            }
            state.beginSearch()
            state.updateQuery("c", isComposing: false)
            state.updateQuery("zhong", isComposing: true)
            precondition(state.query == "c" && state.selectedID == initial)
            state.updateQuery("中国", isComposing: false)
            precondition(state.query == "中国")
            let selected = catalog.entry(code: "US")!
            draft.selectCountry(selected) // The owner's successful list-selection callback.
            state.select(id: selected.code)
            state.dismiss() // Selection must survive subsequent focus callbacks.
            precondition(state.selectedID == "US" && draft.countryRegionCode == "US")
            let selectedObject = try draft.extensionData.jsonObject()
            precondition(selectedObject["countryRegion"] as? String == "US")
            let confirmedData = draft.extensionData
            state.beginSearch()
            state.updateQuery("China", isComposing: false)
            state.dismiss()
            precondition(state.selectedID == "US" && draft.extensionData == confirmedData)
            for language in ["en", "zh-Hans", "fr"] {
                precondition(catalog.displayName(forStoredCode: draft.countryRegionCode, language: language) != nil)
                precondition(draft.extensionData == confirmedData, "Language changes cannot alter persistence")
            }
            state.select(id: "CN")
            precondition(state.selectedID == "US", "Closed lists cannot accept stale selection events")
        }
        print("PASS: 249-code catalog coverage, bilingual names/fallback, stable sorting, search, invalid resources, selection/cancel and draft persistence")
    }
}
