import Foundation

@main
struct SiteTimeZoneSnapshotTests {
    static let iso = ISO8601DateFormatter()
    static func date(_ text: String) -> Date { iso.date(from: text)! }
    static func response(_ dst: Bool = true, current: String = "UTC-05:00", next: Any = "2026-11-01T01:00:00-06:00", to: Any = "UTC-06:00") -> [String: Any] {
        ["code": 200, "data": ["is_dst": dst, "current_offset": current, "next_switch": next, "switches_to": to]]
    }
    static func main() throws {
        let sampled = date("2026-10-28T12:00:00Z")
        let chicago = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: response(), requestedAt: sampled)
        check(chicago.displayOffset == "UTC-06:00 / UTC-05:00 (DST)", "DST ordering uses is_dst")
        check(chicago.offsetMinutes == -300, "Numeric sync uses current_offset")
        check(chicago.nextSwitchDate == date("2026-11-01T07:00:00Z"), "Transition offset is part of its absolute time")
        check(chicago.isUsable(at: date("2026-11-01T06:59:59Z")), "Old cache usable before known transition")
        check(!chicago.isUsable(at: date("2026-11-01T07:00:00Z")), "Old current_offset must stop exactly at transition")
        check(!chicago.isUsable(at: sampled.addingTimeInterval(-1)), "Future sample cannot justify past clock")
        check(!chicago.needsRefresh(at: date("2026-10-29T04:59:59Z")), "Chicago day is independent of phone/UTC date")
        check(chicago.needsRefresh(at: date("2026-10-29T05:00:00Z")), "Chicago midnight allows next success")
        let standard = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: response(false, current: "UTC-06:00", next: "2027-03-14T03:00:00-05:00", to: "UTC-05:00"), requestedAt: date("2026-11-01T07:00:00Z"))
        check(standard.displayOffset == "UTC-06:00 / UTC-05:00", "No DST suffix in standard time")
        let fixed = try SiteTimeZoneSnapshot(identifier: "Asia/Kathmandu", response: response(false, current: "UTC+05:45", next: NSNull(), to: NSNull()), requestedAt: sampled)
        check(fixed.offsetMinutes == 345 && fixed.displayOffset == "UTC+05:45", "Null switch is valid and quarter-hour offsets survive")
        check(SiteTimeZoneSnapshot.requestDateString(sampled) == "2026-10-28T12:00:00+00:00", "Request sends the phone instant in UTC zero")
        let halfHour = try SiteTimeZoneSnapshot(identifier: "Australia/Lord_Howe", response: response(true, current: "UTC+11:00", next: "2027-04-04T01:30:00+10:30", to: "UTC+10:30"), requestedAt: sampled)
        check(halfHour.displayOffset == "UTC+10:30 / UTC+11:00 (DST)" && halfHour.offsetMinutes == 660,
              "Southern hemisphere half-hour DST uses the server fields without adding an hour")
        let negative = try SiteTimeZoneSnapshot(identifier: "Europe/Dublin", response: response(true, current: "UTC+00:00", next: "2027-03-28T02:00:00+01:00", to: "UTC+01:00"), requestedAt: sampled)
        check(negative.displayOffset == "UTC+01:00 / UTC+00:00 (DST)", "Even negative DST obeys server is_dst rather than numeric sorting")
        let restored = try JSONDecoder().decode(SiteTimeZoneSnapshot.self, from: JSONEncoder().encode(chicago))
        check(restored == chicago && restored.nextSwitchDate == chicago.nextSwitchDate, "Persistent cache uses real Codable round trip")
        for invalid in [response(next: NSNull()), response(current: "UTC+08:60"), response(next: "2026-11-01T01:00:00"), response(next: "2026-01-01T01:00:00Z"), response(to: "UTC+14:01")] {
            check((try? SiteTimeZoneSnapshot(identifier: "America/Chicago", response: invalid, requestedAt: sampled)) == nil, "Invalid payload must not consume a successful daily request")
        }
        var numericBool = response()
        var data = numericBool["data"] as! [String: Any]
        data["is_dst"] = 1; numericBool["data"] = data
        check((try? SiteTimeZoneSnapshot(identifier: "America/Chicago", response: numericBool, requestedAt: sampled)) == nil, "An integer is not is_dst")
        try localTimeUsesCurrentOffset(sampled: sampled)
        print("SiteTimeZoneSnapshotTests passed")
    }

    static func localTimeUsesCurrentOffset(sampled: Date) throws {
        let savedProvider = SiteTimeZoneValue.snapshotProvider
        defer { SiteTimeZoneValue.snapshotProvider = savedProvider }
        // Deliberately disagree with both the catalogue and this date's OS timezone rules.
        let timezone = SiteTimeZoneValue(ianaId: "America/Chicago", rawUTCOffset: "UTC+09:00")!
        var current: SiteTimeZoneSnapshot? = try SiteTimeZoneSnapshot(identifier: "America/Chicago",
            response: response(false, current: "UTC-06:00", next: "2027-03-14T03:00:00-05:00", to: "UTC-05:00"), requestedAt: sampled)
        SiteTimeZoneValue.snapshotProvider = { _, _ in current }
        check(timezone.formattedLocalDate(at: sampled) == "2026-10-28 6:00:00 AM", "Clock uses current_offset, not switches_to, static catalogue or OS DST")
        current = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: response(), requestedAt: sampled)
        check(timezone.formattedLocalDate(at: sampled) == "2026-10-28 7:00:00 AM", "Active DST uses current offset without adding a second DST hour")
        check(timezone.formattedLocalDate(at: sampled.addingTimeInterval(86400)) == "2026-10-29 7:00:00 AM", "Usable cache still supplies current offset during a daily refresh failure")
        check(timezone.formattedLocalDate(at: date("2026-11-01T07:00:00Z")) == "--", "Expired cache must not fall back to the catalogue clock")
        check(timezone.formattedLocalDate(at: sampled.addingTimeInterval(-1)) == "--", "Clock rollback cannot reuse a future snapshot")
        current = nil
        check(timezone.formattedLocalDate(at: sampled) == "--", "No current_offset means no invented local clock")
        current = try SiteTimeZoneSnapshot(identifier: "Asia/Kathmandu",
            response: response(false, current: "UTC+05:45", next: NSNull(), to: NSNull()), requestedAt: sampled)
        check(timezone.formattedLocalDate(at: sampled) == "--", "Another timezone's cached offset must not drive this clock")
        let fixed = SiteTimeZoneValue(ianaId: "Asia/Kathmandu", rawUTCOffset: "UTC+00:00")!
        check(fixed.formattedLocalDate(at: sampled) == "2026-10-28 5:45:00 PM", "Non-DST fractional-hour current offset drives the clock too")
    }
    static func check(_ value: Bool, _ message: String) { if !value { fatalError(message) } }
}
