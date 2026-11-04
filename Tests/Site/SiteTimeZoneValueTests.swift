import Foundation

@main
struct SiteTimeZoneValueTests {
    static func main() {
        let pure = SiteTimeZoneValue(storageValue: "America/Chicago")
        require(pure?.ianaId == "America/Chicago", "Pure IANA must survive Site import")
        let legacy = SiteTimeZoneValue(storageValue: "  America/Chicago (UTC-06:00)  ")
        require(legacy?.storageValue == "America/Chicago", "Old suffix must not be exported")
        require(legacy == pure, "Old format and new format are the same Site property")
        require(legacy == SiteTimeZoneValue(storageValue: "America/Chicago (UTC-05:00)"), "DST does not edit Site identity")
        require(Set([pure!, legacy!]).count == 1, "Hash must follow IANA identity")
        require(SiteTimeZoneValue(storageValue: "Asia/Singapore") != SiteTimeZoneValue(storageValue: "Asia/Shanghai"), "Equal offsets do not mean equal identities")
        for invalid in ["", "Asia/Singapore UTC+08:00", "Asia/Singapore (+08:00)", "Asia/Singapore (UTC+08:60)", "Asia/Singapore (UTC+14:01)", " (UTC+08:00)"] {
            require(SiteTimeZoneValue(storageValue: invalid) == nil, "Malformed value must not be normalized into a different identity: \(invalid)")
        }
        require(SiteTimeZoneValue(storageValue: "Legacy/Unknown")?.storageValue == "Legacy/Unknown", "New server identifiers must not be dropped by an older OS")
        let date = ISO8601DateFormatter().date(from: "2026-07-01T12:00:00Z")!
        require(SiteTimeZoneValue.formattedGatewayLastOnline(timestamp: Int64(date.timeIntervalSince1970), storageValue: "America/Chicago (UTC-06:00)") == "2026-07-01 07:00", "Historical rendering uses the timestamp's IANA rules, not a stored suffix")
        print("SiteTimeZoneValueTests passed")
    }
    static func require(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
}
