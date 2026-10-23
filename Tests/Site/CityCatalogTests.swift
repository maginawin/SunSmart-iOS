import Foundation
import CryptoKit

@main enum CityCatalogTests {
    static func main() throws {
        let repo = URL(fileURLWithPath: CommandLine.arguments[1])
        let countries = try CountryRegionCatalog(data: Data(contentsOf: repo.appendingPathComponent("SunSmart/country_regions.json")))
        let zones = try SiteTimeZoneCatalog(data: Data(contentsOf: repo.appendingPathComponent("SunSmart/all_utc_timezones.json")))
        try testBundledCatalog(repo, countries: countries, zones: zones)
        try testSearchAndValidation()
        try testDraft(countries: countries, zones: zones)
        try testLateResponsesAndCache()
        print("PASS: city catalog coverage/integrity, bilingual search, disambiguation, draft transitions and late-response/cache behavior")
    }

    static func record(_ id: Int, name: String, zone: String = "America/Chicago", lat: Double = 39.7817,
                       admin: String = "US.IL", chinese: String? = "斯普林菲尔德") -> [String: Any] {
        var names = ["en": name]
        if let chinese { names["zh-Hans"] = chinese }
        return ["id": id, "names": names, "aliases": name == "Åland" ? ["Aland Islands"] : ["Spring Field"], "admin1": admin, "admin2": "",
                "timezone": zone, "latitude": lat, "longitude": -89.6501]
    }

    static func data(country: String = "US", rows: [[String: Any]]? = nil) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 1, "countryCode": country,
            "administrativeAreas": ["US.IL": ["en": "Illinois", "zh-Hans": "伊利诺伊州"], "US.GA": ["en": "Georgia"]],
            "cities": rows ?? [record(1, name: "Springfield"), record(2, name: "Springfield", zone: "America/New_York", admin: "US.GA"),
                               record(3, name: "Åland", lat: 0, chinese: nil)]])
    }

    static func testSearchAndValidation() throws {
        let catalog = try CityCatalog(data: data(), countryCode: "US")
        precondition(catalog.entries.map(\.record.id) == [3, 2, 1])
        for query in ["spring", "ＳＰＲＩＮＧ", "斯普", "Spring Field"] {
            precondition(catalog.entries(matching: query).count == 2)
        }
        precondition(catalog.entries(matching: " aland ").first?.record.id == 3)
        precondition(catalog.entries(matching: "  ").count == 3 && catalog.entries(matching: "not a city").isEmpty)
        let first = catalog.entry(id: "geonames:1")!, second = catalog.entry(id: "geonames:2")!
        precondition(catalog.displayTitle(for: first, language: "en") == "Springfield, Illinois")
        precondition(catalog.displayTitle(for: second, language: "en") == "Springfield, Georgia")
        precondition(catalog.displayTitle(for: first, language: "zh-Hans").contains("伊利诺伊州"))
        precondition(catalog.entry(id: "geonames:3")!.displayName(language: "zh-Hans") == "Åland")
        precondition(first.displayName(language: "de") == "Springfield")
        precondition(catalog.entry(id: "geonames:3")!.latitudeText == "0" && first.longitudeText == "-89.6501")
        let sameAdmin = try CityCatalog(data: data(rows: [record(1, name: "Twin"), record(2, name: "Twin", lat: 40)]), countryCode: "US")
        precondition(sameAdmin.displayTitle(for: sameAdmin.entries[0], language: "en").contains("39.7817"))
        precondition(sameAdmin.displayTitle(for: sameAdmin.entries[1], language: "en").contains("40"))
        let empty = try CityCatalog(data: data(rows: []), countryCode: "US")
        precondition(empty.entries.isEmpty)
        for bad in [Data("bad".utf8), try data(country: "FR"), try data(rows: [record(1, name: "One"), record(1, name: "Two")]),
                    try data(rows: [record(0, name: "Zero")]), try data(rows: [record(1, name: " ")]),
                    try data(rows: [record(1, name: "Invalid", lat: 91)]), try data(rows: [record(1, name: "Invalid", admin: "missing")])] {
            do { _ = try CityCatalog(data: bad, countryCode: "US"); preconditionFailure("Invalid catalog must fail") } catch {}
        }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("countries"), withIntermediateDirectories: true)
        let contents = try data()
        try contents.write(to: root.appendingPathComponent("countries/US.json"))
        let manifest: [String: Any] = ["schemaVersion": 1, "countries": ["US": ["count": 3, "bytes": contents.count,
            "sha256": SHA256.hash(data: contents).map { String(format: "%02x", $0) }.joined()]]]
        try JSONSerialization.data(withJSONObject: manifest).write(to: root.appendingPathComponent("manifest.json"))
        let verified = try CityCatalog.load(countryCode: "US", root: root)
        precondition(verified.entries.count == 3)
        try (contents + Data(" ".utf8)).write(to: root.appendingPathComponent("countries/US.json"))
        do { _ = try CityCatalog.load(countryCode: "US", root: root); preconditionFailure("Corruption must fail") } catch {}
        for code in ["FR", "../US", "us"] {
            do { _ = try CityCatalog.load(countryCode: code, root: root); preconditionFailure("Missing/invalid country must fail") } catch {}
        }
    }

    static func testDraft(countries: CountryRegionCatalog, zones: SiteTimeZoneCatalog) throws {
        let catalog = try CityCatalog(data: data(), countryCode: "US")
        let one = catalog.entry(id: "geonames:1")!, two = catalog.entry(id: "geonames:2")!
        let initial = zones.value(matchingIdentifier: "Asia/Shanghai")!
        let chicago = zones.value(matchingIdentifier: one.timezoneIdentifier)!, newYork = zones.value(matchingIdentifier: two.timezoneIdentifier)!
        var draft = SiteCreationDraft(siteName: "City", timezone: initial)
        precondition(!draft.selectCity(one, timezone: chicago), "City needs a confirmed matching country")
        draft.selectCountry(countries.entry(code: "US")!)
        let before = draft.extensionData
        precondition(!draft.selectCity(one, timezone: nil) && draft.extensionData == before)
        precondition(!draft.selectCity(one, timezone: newYork) && draft.extensionData == before)
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
        precondition(draft.extensionData.fields["city"] == .null)
        precondition(!draft.selectCity(one, timezone: chicago), "Old-country rows cannot commit")
        draft.selectCountry(countries.entry(code: "US")!)
        precondition(draft.selectCity(two, timezone: newYork))
        draft.editText(.latitude, value: "")
        draft.editText(.longitude, value: "0")
        precondition(draft.selectCity(two, timezone: newYork) && draft.text[.latitude] == "")
        precondition(draft.selectCity(one, timezone: chicago), "A different city replaces prior manual values")
        let saved = try draft.extensionData.jsonObject()
        precondition(saved["city"] as? String == "geonames:1" && saved["latitude"] as? String == "39.7817")
        precondition(saved["longitude"] as? String == "-89.6501" && saved["countryRegion"] as? String == "US")
        draft.selectCountry(countries.entry(code: "CN")!)
        precondition(draft.city == nil && draft.timezone == initial && draft.text[.latitude] == nil && draft.text[.longitude] == nil)
        var unknown = SiteCreationDraft(siteName: "Unknown", timezone: nil)
        unknown.selectCountry(countries.entry(code: "US")!)
        precondition(unknown.selectCity(one, timezone: chicago))
        unknown.selectCountry(countries.entry(code: "CN")!)
        precondition(unknown.timezone == nil && unknown.isNameValid(isDuplicate: false))
    }

    static func drain(until completed: () -> Bool) {
        let deadline = Date().addingTimeInterval(10)
        while !completed(), Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.005)) }
        precondition(completed(), "Background catalog callback timed out")
    }

    static func testLateResponsesAndCache() throws {
        let us = try CityCatalog(data: data(), countryCode: "US")
        let fr = try CityCatalog(data: data(country: "FR", rows: []), countryCode: "FR")
        let cn = try CityCatalog(data: data(country: "CN", rows: []), countryCode: "CN")
        var reads: [String] = []
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        let loader = CityCatalogLoader { code in
            reads.append(code)
            if reads.count == 1 { started.signal(); precondition(release.wait(timeout: .now() + 5) == .success) }
            return ["US": us, "FR": fr, "CN": cn][code]!
        }
        var state = SiteLocationSearchState(context: "US")
        state.beginSearch()
        let old = state.ticket
        var responses = 0, accepted = 0
        loader.search(countryCode: "US", query: "") { result in
            precondition((try? result.get().0.countryCode) == "US")
            responses += 1
            if state.accepts(old) { accepted += 1 }
        }
        precondition(started.wait(timeout: .now() + 5) == .success)
        state.replaceSelection(id: nil, context: "FR"); state.beginSearch()
        state.replaceSelection(id: nil, context: "US"); state.beginSearch()
        state.updateQuery("Spring", isComposing: false)
        let current = state.ticket
        state.updateQuery("zhong", isComposing: true)
        precondition(state.ticket == current, "IME composition leaves the committed query intact")
        loader.search(countryCode: "US", query: state.query) { result in
            precondition((try? result.get().1.count) == 2)
            responses += 1
            if state.accepts(current) { accepted += 1; state.select(id: "geonames:1") }
        }
        release.signal()
        drain { responses == 2 }
        precondition(accepted == 1 && state.selectedID == "geonames:1" && reads == ["US"], "A→B→A must reject the first A and reuse only the catalog")
        state.beginSearch(); let closing = state.ticket; state.dismiss()
        var late = false
        loader.search(countryCode: "US", query: "") { _ in late = true; precondition(!state.accepts(closing)) }
        drain { late }
        for country in ["FR", "CN", "US"] {
            var done = false
            loader.search(countryCode: country, query: "") { _ in done = true }
            drain { done }
        }
        precondition(reads == ["US", "FR", "CN", "US"], "Only the two most recent countries stay cached")
        let failing = CityCatalogLoader { _ in throw CityCatalog.CatalogError.resourceMissing }
        var failed = false
        failing.search(countryCode: "US", query: "") { result in
            if case .failure = result { failed = true }
        }
        drain { failed }
    }

    static func testBundledCatalog(_ repo: URL, countries: CountryRegionCatalog, zones: SiteTimeZoneCatalog) throws {
        let root = repo.appendingPathComponent("SunSmart/CityCatalog")
        let manifest = try JSONDecoder().decode(CityCatalog.Manifest.self, from: Data(contentsOf: root.appendingPathComponent("manifest.json")))
        precondition(Set(manifest.countries.keys) == Set(countries.entries.map(\.code)))
        var ids: Set<String> = [], total = 0
        for country in countries.entries {
            let catalog = try CityCatalog.load(countryCode: country.code, root: root)
            total += catalog.entries.count
            for entry in catalog.entries {
                precondition(ids.insert(entry.id).inserted, "City IDs must be globally unique")
                precondition(zones.value(matchingIdentifier: entry.timezoneIdentifier) != nil, "Every selectable city needs a shared timezone")
                precondition(entry.countryCode == country.code)
            }
        }
        precondition(total == 225061, "Pinned, reviewed snapshot changed; review the generation report")
        let china = try CityCatalog.load(countryCode: "CN", root: root)
        let shanghai = china.entry(id: "geonames:1796236")!
        precondition(shanghai.timezoneIdentifier == "Asia/Shanghai")
        precondition(china.entries(matching: "上海").contains { $0.id == shanghai.id })
        precondition(china.entries(matching: "SHANGHAI").contains { $0.id == shanghai.id })
        // These are distinct places, not duplicate search rows. The UI must show the full title.
        let shenzhen = china.entry(id: "geonames:1795565")!
        let shenzhenTown = china.entry(id: "geonames:1795566")!
        let shenzhenMatches = Set(china.entries(matching: "Shenzhen").map(\.id))
        precondition(shenzhenMatches.contains(shenzhen.id) && shenzhenMatches.contains(shenzhenTown.id))
        precondition(shenzhen.displayName(language: "zh-Hans") == "深圳")
        precondition(shenzhenTown.displayName(language: "zh-Hans") == "深镇")
        precondition(china.displayTitle(for: shenzhen, language: "en") == "Shenzhen, Guangdong, Shenzhen")
        precondition(china.displayTitle(for: shenzhenTown, language: "en") == "Shenzhen, Guangdong, Maoming Shi")
        precondition(shenzhen.latitudeText != shenzhenTown.latitudeText && shenzhen.longitudeText != shenzhenTown.longitudeText)
        let canada = try CityCatalog.load(countryCode: "CA", root: root)
        precondition(canada.entry(id: "geonames:5965812")!.displayName(language: "en") == "Greater Napanee")
        precondition(canada.entry(id: "geonames:6085931")!.displayName(language: "en") == "Napanee")
        let loadStart = Date()
        let us = try CityCatalog.load(countryCode: "US", root: root)
        let loadSeconds = Date().timeIntervalSince(loadStart)
        let start = Date()
        for query in ["Springfield", "New York", "纽约", "ZZZX"] { _ = us.entries(matching: query) }
        print("Catalog: \(total) cities, \(manifest.countries.count) countries; US load/index \(loadSeconds) s; four US searches \(Date().timeIntervalSince(start)) s (CLI, not device UI)")
    }
}
