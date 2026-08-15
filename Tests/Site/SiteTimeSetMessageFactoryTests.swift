import Foundation

@main
struct SiteTimeSetMessageFactoryTests {

    static func main() {
        testUsesValidSiteOffsets()
        testFallsBackForMissingAndMalformedSiteValues()
        testFallsBackForUnencodableSiteOffset()
        testAcceptsUnknownIanaWhenOffsetIsUsable()
        testRejectsUnencodablePhoneFallback()
        print("SiteTimeSetMessageFactoryTests passed")
    }

    private static func testUsesValidSiteOffsets() {
        let fixtures: [(String, Int)] = [
            ("Asia/Singapore (UTC+08:00)", 480),
            ("America/New_York (UTC-05:00)", -300),
            ("Asia/Kathmandu (UTC+05:45)", 345),
            ("Etc/UTC (UTC+00:00)", 0)
        ]

        for (storageValue, expectedMinutes) in fixtures {
            let result = SiteTimeSetMessageFactory.resolve(
                storageValue: storageValue,
                phoneTimeZone: TimeZone(secondsFromGMT: 9 * 3600)!
            )
            require(result?.offsetMinutes == expectedMinutes, "Expected Site offset")
            require(result?.source == .site, "Expected Site timezone source")
        }
    }

    private static func testFallsBackForMissingAndMalformedSiteValues() {
        let phoneTimeZone = TimeZone(secondsFromGMT: 9 * 3600)!
        let fixtures: [(String?, SiteTimeSetPhoneFallbackReason)] = [
            (nil, .missingTimeZone),
            ("", .missingTimeZone),
            ("Asia/Singapore", .invalidTimeZone),
            ("Asia/Singapore (GMT+08:00)", .invalidTimeZone)
        ]

        for (storageValue, expectedReason) in fixtures {
            let result = SiteTimeSetMessageFactory.resolve(
                storageValue: storageValue,
                phoneTimeZone: phoneTimeZone
            )
            require(result?.offsetMinutes == 540, "Expected phone +09:00 fallback")
            require(
                result?.source == .phoneFallback(expectedReason),
                "Expected matching phone fallback reason"
            )
        }
    }

    private static func testFallsBackForUnencodableSiteOffset() {
        let result = SiteTimeSetMessageFactory.resolve(
            storageValue: "Asia/Singapore (UTC+08:01)",
            phoneTimeZone: TimeZone(secondsFromGMT: -3 * 3600)!
        )

        require(result?.offsetMinutes == -180, "Expected phone -03:00 fallback")
        require(
            result?.source == .phoneFallback(.unencodableSiteOffset),
            "Expected unencodable Site offset reason"
        )
    }

    private static func testAcceptsUnknownIanaWhenOffsetIsUsable() {
        let result = SiteTimeSetMessageFactory.resolve(
            storageValue: "Legacy/Unknown (UTC+02:00)",
            phoneTimeZone: TimeZone(secondsFromGMT: 0)!
        )

        require(result?.offsetMinutes == 120, "Expected stored fixed offset")
        require(result?.source == .site, "TimeSet does not consume the IANA identifier")
    }

    private static func testRejectsUnencodablePhoneFallback() {
        let result = SiteTimeSetMessageFactory.resolve(
            storageValue: nil,
            phoneTimeZone: TimeZone(secondsFromGMT: 8 * 3600 + 60)!
        )

        require(result == nil, "Phone fallback must not be silently quantized")
    }

    private static func require(
        _ condition: @autoclosure () -> Bool,
        _ message: String,
        file: StaticString = #file,
        line: UInt = #line
    ) {
        guard condition() else {
            fatalError(message, file: file, line: line)
        }
    }
}
