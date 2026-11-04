import Foundation

/// Real response decoding supplies current offsets; legacy suffixes never authorize sync.
enum SiteDSTFixtures {
    static func install() {
        let values = ["Asia/Singapore": "UTC+08:00", "Asia/Shanghai": "UTC+08:00",
                      "Asia/Tokyo": "UTC+09:00", "Etc/UTC": "UTC+00:00",
                      "America/Anchorage": "UTC-08:00", "Test/Zone": "UTC+08:01"]
        let snapshots = values.mapValues { offset in offset }
        SiteTimeZoneValue.snapshotProvider = { identifier, _ in
            guard let offset = snapshots[identifier] else { return nil }
            return try? SiteTimeZoneSnapshot(identifier: identifier, response: ["code": 200, "data": [
                "is_dst": false, "current_offset": offset, "next_switch": NSNull(), "switches_to": NSNull()
            ]], requestedAt: Date(timeIntervalSince1970: 0))
        }
    }
}
