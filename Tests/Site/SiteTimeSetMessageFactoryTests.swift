import Foundation
@main
struct SiteTimeSetMessageFactoryTests {
    static func main() throws {
        let now = Date()
        SiteTimeZoneValue.snapshotProvider = { _, _ in nil }
        check(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago (UTC-06:00)") == nil, "A legacy suffix must not authorize a TimeSet")
        check(SiteTimeSetMessageFactory.resolve(storageValue: nil) == nil, "Missing Site offset must not silently use the phone")
        let snapshot = try SiteTimeZoneSnapshot(identifier: "America/Chicago", response: ["code":200,"data":["is_dst":true,"current_offset":"UTC-05:00","next_switch":SiteTimeZoneSnapshot.requestDateString(now.addingTimeInterval(60)),"switches_to":"UTC-06:00"]], requestedAt: now.addingTimeInterval(-10))
        SiteTimeZoneValue.snapshotProvider = { id, _ in id == snapshot.identifier ? snapshot : nil }
        let resolved = SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago (UTC-06:00)", at: now)
        check(resolved?.offsetMinutes == -300 && resolved?.source == .site, "Server current_offset must win over stored standard offset")
        check(SiteTimeSetMessageFactory.resolve(storageValue: "America/Chicago", at: now.addingTimeInterval(61)) == nil, "Expired response must not be sent")
        check(SiteTimeSetMessageFactory.resolve(storageValue: "Asia/Singapore", at: now) == nil, "Other IANA's snapshot must not leak")
        print("SiteTimeSetMessageFactoryTests passed")
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) { if !condition() { fatalError(message) } }
}
