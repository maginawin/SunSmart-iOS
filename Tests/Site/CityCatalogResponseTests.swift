import Foundation

@main enum CityCatalogResponseTests {
    static func row(_ id: Int, name: String = "raw name", names: Any? = nil,
                    latitude: Any = "0", longitude: Any = "-1.25") -> [String: Any] {
        var row: [String: Any] = ["id": id, "name": name, "latitude": latitude,
                                "longitude": longitude, "timezone": "America/Chicago"]
        if let names { row["names_json"] = names }
        return row
    }

    static func catalog(_ rows: [[String: Any]]) throws -> CityCatalog {
        try CityCatalog(response: ["code": 200, "data": rows], countryCode: "US")
    }

    static func main() throws {
        // Missing en must not invalidate a Chinese-only record, and other locales never use zh-Hans.
        let fixtures: [(Any?, String, String)] = [
            (["en": "English", "zh-Hans": "中文"], "中文", "English"),
            (["en": "English"], "English", "English"),
            (["zh-Hans": "中文"], "中文", "raw name"),
            ([:], "raw name", "raw name"), (nil, "raw name", "raw name"),
            (NSNull(), "raw name", "raw name"),
            (["en": " ", "zh-Hans": NSNull()], "raw name", "raw name")
        ]
        for (names, chinese, other) in fixtures {
            let value = try catalog([row(1, names: names)])
            let restored = try CityCatalog(data: value.cacheData(fetchedAt: Date()), countryCode: "US")
            for c in [value, restored] {
                let entry = c.entry(id: "geonames:1")!
                precondition(entry.record.name == "raw name")
                precondition(entry.displayName(language: "zh-Hans") == chinese)
                for language in ["en", "fr", "de"] { precondition(entry.displayName(language: language) == other) }
                precondition(entry.latitudeText == "0" && entry.longitudeText == "-1.25")
            }
        }
        let c = try catalog([row(1, name: "Åland", names: ["en": "Aland", "zh-Hans": "奥兰"]),
                             row(2, name: "Twin"), row(3, name: "Twin"), row(4, name: "Twin", latitude: 1)])
        precondition(c.entries(matching: " ＡＬＡＮＤ ").map(\.record.id) == [1])
        precondition(c.entries(matching: "奥兰").count == 1 && c.entries(matching: "missing").isEmpty)
        let twins = c.entries(matching: "twin")
        let titles = twins.map { c.displayTitle(for: $0, language: "en") }
        precondition(Set(titles).count == 3 && titles.allSatisfy { $0.contains("(") }, "Even same-name same-coordinate IDs must remain distinguishable")
        precondition(tryEmpty().entries.isEmpty)
        let bytes = try c.cacheData(fetchedAt: Date())
        for code in ["CN", "../US", "us"] {
            do { _ = try CityCatalog(data: bytes, countryCode: code); preconditionFailure("Wrong-country cache must fail") } catch {}
        }
        let badRows: [[String: Any]] = [row(0), row(-1), row(1, name: " "), row(1, names: "bad"),
            row(1, names: ["en": 7]), row(1, latitude: true), row(1, latitude: "NaN"),
            row(1, latitude: 91), row(1, longitude: "181"), row(1, latitude: "oops")]
        for r in badRows {
            do { _ = try catalog([r]); preconditionFailure("Bad city must reject the snapshot") } catch {}
        }
        for response: [String: Any] in [["code": 500, "data": []], ["code": 200],
                                      ["code": 200, "data": NSNull()], ["code": 200, "data": [row(1), row(1)]]] {
            do { _ = try CityCatalog(response: response, countryCode: "US"); preconditionFailure("Bad response must fail") } catch {}
        }
        let file = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("Tests/Site/Fixtures/cities_us_response.json")
        let sample = try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as! [String: Any]
        let us = try CityCatalog(response: sample, countryCode: "US")
        precondition(us.entries.count == 21016)
        precondition(us.entry(id: "geonames:4046255")?.displayName(language: "zh-Hans") == "贝米内特")
        precondition(us.entry(id: "geonames:4046274")?.displayName(language: "zh-Hans") == "Edna")
        print("PASS: US API sample, language/name fallbacks, raw-name cache, numeric coordinates, empty/invalid responses and duplicate-title identity")
    }

    static func tryEmpty() -> CityCatalog { try! catalog([]) }
}
