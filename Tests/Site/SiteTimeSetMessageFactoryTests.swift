import Foundation
@main
struct SiteTimeSetMessageFactoryTests {
    static func main() throws {
        let now = Date()
        SiteTimeZoneValue.snapshotProvider = { _, _ in nil }
        check(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago (UTC-06:00)") == nil, "A legacy suffix must not authorize a TimeSet")
        let phone = TimeZone(secondsFromGMT: 8 * 3600)!
        let missing = SiteTimeSetMessageFactory.resolve(storageValue: nil, phoneTimeZone: phone, at: now)
        check(missing?.offsetMinutes == 480 && missing?.source == .phoneFallback(.missingTimeZone), "Missing Site timezone must use the phone offset")
        for raw in ["", "  ", "not a timezone", "Invalid/Nowhere"] {
            check(SiteTimeSetMessageFactory.resolve(storageValue: raw, phoneTimeZone: phone, at: now)?.storageValue == raw, "Fallback must preserve even empty stored values for identity validation")
            check(SiteTimeSetMessageFactory.resolve(storageValue: raw, phoneTimeZone: phone, at: now)?.offsetMinutes == 480, "Empty or invalid timezone falls back to phone")
        }
        check(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", phoneTimeZone: phone, at: now) == nil, "Known valid Site without a usable snapshot must wait, not silently move to the phone zone")
        let snapshot = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: ["code":200,"data":["is_dst":true,"current_offset":"UTC-05:00","next_switch":SiteTimeZoneSnapshot.requestDateString(now.addingTimeInterval(60)),"switches_to":"UTC-06:00"]], requestedAt: now.addingTimeInterval(-10))
        SiteTimeZoneValue.snapshotProvider = { id, _ in id == snapshot.identifier ? snapshot : nil }
        let resolved = SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago (UTC-06:00)", at: now)
        check(resolved?.storageValue == "America/Chicago (UTC-06:00)", "Prepared identity must preserve the stored legacy value for the Site ownership check")
        check(resolved?.offsetMinutes == -300 && resolved?.source == .site, "Server current_offset must win over stored standard offset")
        check(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now.addingTimeInterval(61)) == nil, "Expired response must not be sent")
        check(SiteTimeSetMessageFactory.resolve(storageValue: "Asia/Singapore", at: now) == nil, "Other IANA's snapshot must not leak")
        let serverOnly = try SiteTimeZoneSnapshot(identifier: "Future/ServerOnly", response: ["code":200,"data":["is_dst":false,"current_offset":"UTC+05:30","next_switch":NSNull(),"switches_to":NSNull()]], requestedAt: now.addingTimeInterval(-10))
        SiteTimeZoneValue.snapshotProvider = { id, _ in id == serverOnly.identifier ? serverOnly : nil }
        check(SiteTimeSetMessageFactory.resolve(storageValue: "Future/ServerOnly", phoneTimeZone: phone, at: now)?.offsetMinutes == 330,
              "A server-confirmed identity is usable even when the phone does not recognize it")
        check(missing?.isCurrent(at: now, phoneTimeZone: TimeZone(secondsFromGMT: 3600)!) == false,
              "Changing the phone offset invalidates an existing fallback")
        print("SiteTimeSetMessageFactoryTests passed")
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
}
