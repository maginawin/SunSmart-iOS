import Foundation

@main
struct SiteTimeZoneCatalogTests {

    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            fatalError("Expected all_utc_timezones.json path")
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let catalog = try SiteTimeZoneCatalog(data: data)

        testInjectsUTCAndPreservesBundledOrder(catalog)
        testSearchTrimsAndMatchesRegionAsAWhole(catalog)
        testSearchMatchesIanaAndBothOffsetFormats(catalog)
        testSearchRestoresAllSectionsAndReturnsNoResult(catalog)
        testUsesBundledStaticOffsetForExactPhoneIdentifier(catalog)
        testNormalizesPhoneUTCToEtcUTC(catalog)
        try testFallbackPreservesIdentifierAndRemovesDaylightSavingOffset()
        try testRejectsMalformedCatalogRows()
        print("SiteTimeZoneCatalogTests passed")
    }

    private static func testInjectsUTCAndPreservesBundledOrder(
        _ catalog: SiteTimeZoneCatalog
    ) {
        require(catalog.allSections.count == 9, "Expected UTC plus 8 bundled regions")
        require(
            catalog.allSections.reduce(0) { $0 + $1.entries.count } == 398,
            "Expected UTC plus 397 bundled entries"
        )
        require(catalog.allSections.first?.region == "UTC", "UTC must be the first group")
        require(
            catalog.allSections.first?.entries.first?.value.storageValue
                == "Etc/UTC (UTC+00:00)",
            "Expected canonical UTC entry"
        )
        require(catalog.allSections[1].region == "Africa", "Expected original first region")
        require(
            catalog.allSections[1].entries.first?.ianaId == "Africa/Abidjan",
            "Expected original first row"
        )
        require(catalog.allSections.last?.region == "Pacific", "Expected original last region")
        require(
            catalog.allSections.last?.entries.last?.ianaId == "Pacific/Wallis",
            "Expected original last row"
        )
    }

    private static func testSearchTrimsAndMatchesRegionAsAWhole(
        _ catalog: SiteTimeZoneCatalog
    ) {
        let sections = catalog.sections(matching: "  aSiA  ")

        require(sections.count == 1, "Expected only the Asia group")
        require(sections.first?.region == "Asia", "Expected case-insensitive region match")
        require(sections.first?.entries.count == 82, "Region match must return all Asia rows")
    }

    private static func testSearchMatchesIanaAndBothOffsetFormats(
        _ catalog: SiteTimeZoneCatalog
    ) {
        let ianaSections = catalog.sections(matching: "SINGAPORE")
        let rawOffsetSections = catalog.sections(matching: "+05:45")
        let displayOffsetSections = catalog.sections(matching: "utc+05:45")

        require(
            ianaSections.flatMap(\.entries).map(\.ianaId) == ["Asia/Singapore"],
            "Expected case-insensitive IANA substring match"
        )
        require(
            rawOffsetSections.flatMap(\.entries).map(\.ianaId) == ["Asia/Kathmandu"],
            "Expected raw offset match"
        )
        require(
            displayOffsetSections.flatMap(\.entries).map(\.ianaId) == ["Asia/Kathmandu"],
            "Expected displayed offset match"
        )
    }

    private static func testSearchRestoresAllSectionsAndReturnsNoResult(
        _ catalog: SiteTimeZoneCatalog
    ) {
        require(
            catalog.sections(matching: "   ").count == 9,
            "Trimmed empty search must restore the full catalog"
        )
        require(
            catalog.sections(matching: "not-a-real-time-zone").isEmpty,
            "Expected an empty result"
        )
    }

    private static func testUsesBundledStaticOffsetForExactPhoneIdentifier(
        _ catalog: SiteTimeZoneCatalog
    ) {
        let phoneTimeZone = TimeZone(identifier: "Asia/Singapore")!
        let value = catalog.defaultValue(for: phoneTimeZone, at: Date(timeIntervalSince1970: 0))

        require(
            value.storageValue == "Asia/Singapore (UTC+08:00)",
            "Expected the bundled static offset for an exact identifier"
        )
    }

    private static func testNormalizesPhoneUTCToEtcUTC(
        _ catalog: SiteTimeZoneCatalog
    ) {
        let phoneTimeZone = TimeZone(identifier: "UTC")!
        let value = catalog.defaultValue(for: phoneTimeZone, at: Date(timeIntervalSince1970: 0))

        require(
            value.storageValue == "Etc/UTC (UTC+00:00)",
            "Expected phone UTC to normalize to Etc/UTC"
        )
    }

    private static func testFallbackPreservesIdentifierAndRemovesDaylightSavingOffset() throws {
        let smallCatalogJSON = """
        [
          {
            "region": "Asia",
            "ianaId": "Asia/Singapore",
            "utcOffset": "+08:00"
          }
        ]
        """
        let catalog = try SiteTimeZoneCatalog(data: Data(smallCatalogJSON.utf8))
        let phoneTimeZone = TimeZone(identifier: "America/New_York")!
        let summerDate = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
        let value = catalog.defaultValue(for: phoneTimeZone, at: summerDate)

        require(value.ianaId == "America/New_York", "Expected fallback to preserve identifier")
        require(value.offsetMinutes == -300, "Expected standard -05:00 with DST removed")
    }

    private static func testRejectsMalformedCatalogRows() throws {
        let malformedOffset = """
        [{"region":"Asia","ianaId":"Asia/Invalid","utcOffset":"+15:00"}]
        """
        let missingIdentifier = """
        [{"region":"Asia","utcOffset":"+08:00"}]
        """

        requireThrows(
            try SiteTimeZoneCatalog(data: Data(malformedOffset.utf8)),
            "Expected invalid offset to reject the complete catalog"
        )
        requireThrows(
            try SiteTimeZoneCatalog(data: Data(missingIdentifier.utf8)),
            "Expected a missing required field to reject the complete catalog"
        )
    }

    private static func requireThrows<T>(
        _ expression: @autoclosure () throws -> T,
        _ message: String
    ) {
        do {
            _ = try expression()
            fatalError(message)
        } catch {
            return
        }
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) {
        guard condition() else {
            fatalError(message)
        }
    }
}
