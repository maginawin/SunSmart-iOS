import Foundation

@main
struct GatewayTimeInformationCoordinatorTests {

    static func main() {
        testFormatsGatewayTimeAndOffset()
        testFormatsZeroAndNegativeOffsets()
        testFormatsQuarterHourOffset()
        testRejectsUnknownTime()
        testAttemptDeduplicatesAndRestoresAfterDetach()
        testWrongAttemptIsIgnored()
        testFailureAllowsRetry()
        print("GatewayTimeInformationCoordinatorTests passed")
    }

    private static func testFormatsGatewayTimeAndOffset() {
        let snapshot = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: 1,
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
            seconds: 1,
            offsetMinutes: 0
        )
        require(utc?.timeZoneText == "UTC+00:00", "UTC must include an explicit plus sign")
        require(utc?.dateTimeText == "2000-01-01 00:00:01", "UTC date must not shift")

        let negative = GatewayTimeInformationFormatter.makeSnapshot(
            seconds: 1,
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
            seconds: 1,
            offsetMinutes: 345
        )
        require(snapshot?.timeZoneText == "UTC+05:45", "15-minute encoded offsets must be preserved")
        require(snapshot?.dateTimeText == "2000-01-01 05:45:01", "Quarter-hour offset must shift display time")
    }

    private static func testRejectsUnknownTime() {
        require(
            GatewayTimeInformationFormatter.makeSnapshot(seconds: 0, offsetMinutes: 480) == nil,
            "seconds == 0 must remain unknown"
        )
    }

    private static func testAttemptDeduplicatesAndRestoresAfterDetach() {
        var core = GatewayTimeInformationAttemptCore()
        let attempt = core.begin()
        require(attempt != nil, "First read must start")
        require(core.begin() == nil, "Concurrent read must be ignored")
        core.detach()
        require(
            core.receive(attemptID: attempt!, seconds: 100, offsetMinutes: 480) == .restoreOnly,
            "A response after page exit must restore the pre-send Node state"
        )
    }

    private static func testWrongAttemptIsIgnored() {
        var core = GatewayTimeInformationAttemptCore()
        require(core.begin() != nil, "Read must start")
        require(
            core.receive(attemptID: UUID(), seconds: 100, offsetMinutes: 480) == .ignored,
            "A stale response must not finish the active read"
        )
        require(core.begin() == nil, "A stale response must leave the active read in progress")
    }

    private static func testFailureAllowsRetry() {
        var core = GatewayTimeInformationAttemptCore()
        let first = core.begin()!
        require(core.fail(attemptID: first) == .failure(showError: true), "Timeout must report one read failure")
        require(core.begin() != nil, "A terminal failure must allow a tap retry")
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
