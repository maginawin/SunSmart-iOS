import Foundation

@main
struct GatewayTimeInformationCoordinatorTests {

    static func main() {
        testFormatsGatewayTimeAndOffset()
        testFormatsZeroAndNegativeOffsets()
        testFormatsQuarterHourOffset()
        testRejectsUnknownTime()
        testStandardAndLegacySamplesShowSameTime()
        print("GatewayTimeInformationCoordinatorTests passed")
    }

    private static func testFormatsGatewayTimeAndOffset() {
        let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: 1, subSecond: 0, taiDelta: 0,
            offsetMinutes: 480
        )
        require(snapshot != nil, "Known Gateway time must format")
        require(snapshot?.timeZoneText == "UTC+08:00", "Expected UTC+08:00")
        require(
            snapshot?.dateTimeText == "2000-01-01 08:00:01",
            "Mesh epoch conversion and Gateway offset must both be applied"
        )
    }

    private static func testFormatsZeroAndNegativeOffsets() {
        let utc = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: 1, subSecond: 0, taiDelta: 0,
            offsetMinutes: 0
        )
        require(utc?.timeZoneText == "UTC+00:00", "UTC must include an explicit plus sign")
        require(utc?.dateTimeText == "2000-01-01 00:00:01", "UTC date must not shift")

        let negative = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: 1, subSecond: 0, taiDelta: 0,
            offsetMinutes: -330
        )
        require(negative?.timeZoneText == "UTC-05:30", "Negative half-hour offsets must format")
        require(
            negative?.dateTimeText == "1999-12-31 18:30:01",
            "Negative Gateway offset must be applied to display time"
        )
    }

    private static func testFormatsQuarterHourOffset() {
        let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: 1, subSecond: 0, taiDelta: 0,
            offsetMinutes: 345
        )
        require(snapshot?.timeZoneText == "UTC+05:45", "15-minute encoded offsets must be preserved")
        require(snapshot?.dateTimeText == "2000-01-01 05:45:01", "Quarter-hour offset must shift display time")
    }

    private static func testRejectsUnknownTime() {
        require(
            GatewayTimeInformationFormatter.makeSnapshot(seconds: 0, subSecond: 0, taiDelta: 0, offsetMinutes: 480) == nil,
            "seconds == 0 must remain unknown"
        )
    }

    private static func testStandardAndLegacySamplesShowSameTime() {
        for delta: Int16 in [0, 36, 37] {
            let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
                seconds: UInt64(551_892_600 + Int(delta)), subSecond: 128,
                taiDelta: delta, offsetMinutes: 345
            )
            require(snapshot?.dateTimeText == "2017-06-27 21:15:00", "Gateway and Light Information must apply delta before the timezone")
            require(snapshot?.seconds == UInt64(551_892_600 + Int(delta)), "Keep the raw TAI value in the snapshot")
            require(snapshot?.taiDelta == delta, "Retain the delta associated with this sample")
        }
        require(GatewayTimeInformationFormatter.makeSnapshot(
            seconds: UInt64.max, subSecond: 0, taiDelta: 37, offsetMinutes: 0
        ) == nil, "Malformed seconds must not reach DateFormatter")
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
