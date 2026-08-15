import Foundation

@main
struct SiteTimeZoneValueTests {

    static func main() {
        testParsesAndFormatsFullStorageValue()
        testSupportsUTCAndFractionalHourOffsets()
        testMeshTimeZoneOffsetRequiresExactQuarterHour()
        testRejectsMalformedAndOutOfRangeOffsets()
        testIanaIdentifierParticipatesInEquality()
        testFixedOffsetLocalTimeCrossesDateBoundaries()
        testLocalTimeIgnoresIanaDaylightSavingRules()
        print("SiteTimeZoneValueTests passed")
    }

    private static func testParsesAndFormatsFullStorageValue() {
        let value = SiteTimeZoneValue(storageValue: "  Asia/Singapore (UTC+08:00)  ")

        require(value?.ianaId == "Asia/Singapore", "Expected trimmed IANA identifier")
        require(value?.offsetMinutes == 480, "Expected +08:00 to equal 480 minutes")
        require(value?.displayOffset == "UTC+08:00", "Expected normalized display offset")
        require(
            value?.storageValue == "Asia/Singapore (UTC+08:00)",
            "Expected normalized full storage value"
        )
    }

    private static func testSupportsUTCAndFractionalHourOffsets() {
        let utc = SiteTimeZoneValue(ianaId: "Etc/UTC", rawUTCOffset: "+00:00")
        let negativeHalfHour = SiteTimeZoneValue(
            ianaId: "America/St_Johns",
            rawUTCOffset: "-03:30"
        )
        let positiveQuarterHour = SiteTimeZoneValue(
            ianaId: "Asia/Kathmandu",
            rawUTCOffset: "+05:45"
        )

        require(utc?.storageValue == "Etc/UTC (UTC+00:00)", "Expected canonical UTC")
        require(negativeHalfHour?.offsetMinutes == -210, "Expected -03:30")
        require(positiveQuarterHour?.offsetMinutes == 345, "Expected +05:45")
    }

    private static func testMeshTimeZoneOffsetRequiresExactQuarterHour() {
        let exact = SiteTimeZoneValue(
            ianaId: "Asia/Kathmandu",
            rawUTCOffset: "+05:45"
        )
        let inexact = SiteTimeZoneValue(
            ianaId: "Asia/Singapore",
            rawUTCOffset: "+08:01"
        )

        require(
            exact?.isMeshTimeZoneOffsetEncodable == true,
            "A 15-minute offset must be exactly Mesh encodable"
        )
        require(
            inexact?.isMeshTimeZoneOffsetEncodable == false,
            "A non-15-minute offset must not be silently quantized"
        )
    }

    private static func testRejectsMalformedAndOutOfRangeOffsets() {
        let invalidStorageValues = [
            "",
            "Asia/Singapore",
            "Asia/Singapore UTC+08:00",
            "Asia/Singapore (+08:00)",
            "Asia/Singapore (UTC08:00)",
            "Asia/Singapore (UTC+08:60)",
            "Asia/Singapore (UTC+14:01)",
            "Asia/Singapore (UTC-14:01)",
            " (UTC+08:00)"
        ]

        for storageValue in invalidStorageValues {
            require(
                SiteTimeZoneValue(storageValue: storageValue) == nil,
                "Expected invalid storage value: \(storageValue)"
            )
        }

        require(
            SiteTimeZoneValue(ianaId: "Asia/Singapore", rawUTCOffset: "08:00") == nil,
            "Expected raw offset to require an explicit sign"
        )
    }

    private static func testIanaIdentifierParticipatesInEquality() {
        let singapore = SiteTimeZoneValue(
            ianaId: "Asia/Singapore",
            rawUTCOffset: "+08:00"
        )
        let shanghai = SiteTimeZoneValue(
            ianaId: "Asia/Shanghai",
            rawUTCOffset: "+08:00"
        )

        require(singapore != shanghai, "Different IANA identifiers must be different values")
    }

    private static func testFixedOffsetLocalTimeCrossesDateBoundaries() {
        let utcEpoch = Date(timeIntervalSince1970: 0)
        let positive = SiteTimeZoneValue(ianaId: "Asia/Singapore", rawUTCOffset: "+08:00")
        let negative = SiteTimeZoneValue(ianaId: "America/St_Johns", rawUTCOffset: "-03:30")

        require(
            positive?.formattedLocalDate(at: utcEpoch) == "1970-1-1 8:00:00 AM",
            "Expected fixed positive offset date"
        )
        require(
            negative?.formattedLocalDate(at: utcEpoch) == "1969-12-31 8:30:00 PM",
            "Expected fixed negative offset to cross the year boundary"
        )
    }

    private static func testLocalTimeIgnoresIanaDaylightSavingRules() {
        let summerUTC = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
        let newYorkStandardOffset = SiteTimeZoneValue(
            ianaId: "America/New_York",
            rawUTCOffset: "-05:00"
        )

        require(
            newYorkStandardOffset?.formattedLocalDate(at: summerUTC) == "2026-7-1 7:00:00 AM",
            "Expected fixed -05:00 instead of New York daylight-saving time"
        )
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
