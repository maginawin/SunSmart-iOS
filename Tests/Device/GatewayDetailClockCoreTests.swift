import Foundation

@main
struct GatewayDetailClockCoreTests {

    static func main() {
        testUsesStoredSiteTimeZone()
        testFallsBackToCurrentPhoneOffset()
        testKeepsUnencodableSiteOffsetVisible()
        testOffByUsesGatewayDateTimeMinusLocalDateTime()
        testOffsetFormattingAndThreshold()
        testSyncVerificationRequiresReadbackOffsetAndThreshold()
        testRejectsUndisplayableGatewayDate()
        testReadAndSyncFailureRetainPreviousSample()
        testReadCompletionCannotEndActiveSyncPresentation()
        testSyncingPresentationLastsAtLeastOneSecond()
        testDateFormattingUsesRequiredShape()
        print("GatewayDetailClockCoreTests passed")
    }

    private static func testUsesStoredSiteTimeZone() {
        let target = GatewayDetailTimeZoneResolver.resolve(
            storageValue: "America/Anchorage (UTC-09:00)",
            phoneTimeZone: TimeZone(secondsFromGMT: 8 * 3600)!,
            at: Date(timeIntervalSince1970: 0)
        )
        require(target.identifier == "America/Anchorage", "Stored Site identifier must win")
        require(target.offsetMinutes == -540, "Stored Site fixed offset must win")
        require(target.source == .site, "Stored Site timezone must be identified")
        require(target.isMeshEncodable, "Quarter-hour Site offset must be encodable")
    }

    private static func testFallsBackToCurrentPhoneOffset() {
        let phone = TimeZone(identifier: "Asia/Singapore")!
        let target = GatewayDetailTimeZoneResolver.resolve(
            storageValue: nil,
            phoneTimeZone: phone,
            at: Date(timeIntervalSince1970: 1_786_653_600)
        )
        require(target.identifier == "Asia/Singapore", "Missing Site timezone must show phone identifier")
        require(target.offsetMinutes == 480, "Phone fallback must use the current effective offset")
        require(target.source == .phoneFallback, "Missing Site timezone must be a non-persistent fallback")
    }

    private static func testKeepsUnencodableSiteOffsetVisible() {
        let target = GatewayDetailTimeZoneResolver.resolve(
            storageValue: "Test/Zone (UTC+08:01)",
            phoneTimeZone: TimeZone(secondsFromGMT: 0)!,
            at: Date(timeIntervalSince1970: 0)
        )
        require(target.identifier == "Test/Zone", "Valid Site display value must not silently fall back")
        require(target.offsetMinutes == 481, "Unencodable Site offset must remain the target")
        require(!target.isMeshEncodable, "Non-quarter-hour target must be rejected by Mesh sync")
    }

    private static func testOffByUsesGatewayDateTimeMinusLocalDateTime() {
        let sample = GatewayDetailClockSample(
            seconds: 100,
            subSecond: 0,
            offsetMinutes: 0
        )
        let gatewayAbsolute = TimeInterval(100) + GatewayDetailClockCore.meshEpochOffset
        let localDate = Date(timeIntervalSince1970: gatewayAbsolute)
        let offBy = GatewayDetailClockCore.offBySeconds(
            localDate: localDate,
            targetOffsetMinutes: 480,
            sample: sample
        )
        require(
            offBy == -28_800,
            "Off by must be Gateway datetime minus Local datetime"
        )

        let gatewayAheadSample = GatewayDetailClockSample(
            seconds: 190,
            subSecond: 0,
            offsetMinutes: 480
        )
        let gatewayAhead = GatewayDetailClockCore.offBySeconds(
            localDate: localDate,
            targetOffsetMinutes: 480,
            sample: gatewayAheadSample
        )
        require(
            gatewayAhead == 90,
            "A Gateway datetime ahead of Local datetime must have a positive Off by"
        )
        require(
            GatewayDetailClockCore.gatewayDisplayDate(
                localDate: localDate,
                offBySeconds: gatewayAhead
            ) == localDate.addingTimeInterval(90),
            "Gateway display ticks must add Gateway-minus-Local Off by to Local"
        )
    }

    private static func testOffsetFormattingAndThreshold() {
        require(GatewayDetailClockCore.formatOffBy(seconds: 156) == "+2m 36s", "Positive minute offset format")
        require(GatewayDetailClockCore.formatOffBy(seconds: -156) == "-2m 36s", "Negative minute offset format")
        require(GatewayDetailClockCore.formatOffBy(seconds: -36) == "-36s", "Sub-minute offset format")
        require(GatewayDetailClockCore.formatOffBy(seconds: 0) == "0s", "Zero offset format")
        require(GatewayDetailClockCore.isWithinTolerance(seconds: 30), "+30 seconds must be green")
        require(GatewayDetailClockCore.isWithinTolerance(seconds: -30), "-30 seconds must be green")
        require(!GatewayDetailClockCore.isWithinTolerance(seconds: 31), "31 seconds must be amber")
    }

    private static func testSyncVerificationRequiresReadbackOffsetAndThreshold() {
        require(
            GatewayDetailClockCore.isVerifiedSync(
                targetOffsetMinutes: 480,
                sampleOffsetMinutes: 480,
                offBySeconds: 30
            ),
            "Matching readback at the threshold must succeed"
        )
        require(
            !GatewayDetailClockCore.isVerifiedSync(
                targetOffsetMinutes: 480,
                sampleOffsetMinutes: 0,
                offBySeconds: 0
            ),
            "Readback timezone mismatch must fail"
        )
        require(
            !GatewayDetailClockCore.isVerifiedSync(
                targetOffsetMinutes: 480,
                sampleOffsetMinutes: 480,
                offBySeconds: 31
            ),
            "Readback clock outside tolerance must fail"
        )
    }

    private static func testReadAndSyncFailureRetainPreviousSample() {
        let sample = GatewayDetailClockSample(seconds: 100, subSecond: 0, offsetMinutes: 480)
        var state = GatewayDetailClockState()
        state.accept(sample: sample, offBySeconds: 2, targetOffsetMinutes: 480)
        state.failRead()
        require(state.sample == sample, "Read failure must retain the previous valid sample")
        require(state.requiresSync, "Read failure must show Sync required")
        state.beginSync()
        state.failSync()
        require(state.sample == sample, "Sync failure must retain the previous valid sample")

        var unknown = GatewayDetailClockState()
        unknown.failSync()
        require(unknown.sample == nil, "An originally unknown Gateway must remain unknown")
    }

    private static func testReadCompletionCannotEndActiveSyncPresentation() {
        let sample = GatewayDetailClockSample(seconds: 100, subSecond: 0, offsetMinutes: 480)
        var state = GatewayDetailClockState()
        state.beginSync()
        state.accept(sample: sample, offBySeconds: 2, targetOffsetMinutes: 480)
        require(state.isSyncing, "A pending TimeGet completion must not restore Sync clock")
        state.completeSync(
            sample: sample,
            offBySeconds: 1,
            targetOffsetMinutes: 480
        )
        require(!state.isSyncing, "Only the sync completion may end the Syncing presentation")
    }

    private static func testRejectsUndisplayableGatewayDate() {
        let sample = GatewayDetailClockSample(
            seconds: (1 << 40) - 1,
            subSecond: 0,
            offsetMinutes: 0
        )
        require(
            !GatewayDetailClockCore.isDisplayable(sample: sample),
            "A parsed Mesh value outside the supported display year range must fail"
        )
    }

    private static func testSyncingPresentationLastsAtLeastOneSecond() {
        let remaining = GatewayDetailClockCore.remainingSyncPresentationDuration(
            startedAtUptime: 10,
            completedAtUptime: 10.2
        )
        require(
            abs(remaining - 0.8) < 0.000_001,
            "An immediate Gateway response must keep Syncing visible for the remaining interval"
        )
        require(
            GatewayDetailClockCore.remainingSyncPresentationDuration(
                startedAtUptime: 10,
                completedAtUptime: 11.2
            ) == 0,
            "A response after one second must be presented immediately"
        )
    }

    private static func testDateFormattingUsesRequiredShape() {
        let date = Date(timeIntervalSince1970: 1_786_753_559)
        require(
            GatewayDetailClockCore.format(date: date, offsetMinutes: 0) == "2026-8-15 12:25:59 AM",
            "Gateway detail date must use two-digit 12-hour time and POSIX AM/PM"
        )
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
