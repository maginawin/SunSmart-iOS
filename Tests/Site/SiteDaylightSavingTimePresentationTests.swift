import Foundation

@main
struct SiteDaylightSavingTimePresentationTests {
    static let sampled = date("2026-10-28T12:00:00Z")
    static let transition = date("2026-11-01T07:00:00Z")
    static func date(_ value: String) -> Date { SiteTimeZoneSnapshot.parseDate(value)! }
    static func check(_ value: @autoclosure () -> Bool, _ message: String) {
        if !value() { fatalError(message) }
    }
    static func pump(_ condition: () -> Bool) {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        check(condition(), "Asynchronous cache operation timed out")
    }
    static func response(dst: Bool = true, current: String = "UTC-05:00",
                         next: Any = "2026-11-01T01:00:00-06:00", to: Any = "UTC-06:00") -> [String: Any] {
        ["code": 200, "data": ["is_dst": dst, "current_offset": current, "next_switch": next, "switches_to": to]]
    }
    static func snapshot(_ id: String = "America/Chicago", response: [String: Any] = response(),
                         at: Date = sampled) throws -> SiteTimeZoneSnapshot {
        try SiteTimeZoneSnapshot(identifier: id, response: response, requestedAt: at)
    }

    static func main() throws {
        try visibilityAndExpansion()
        try nextSwitchFormatting()
        try gatewaySummaryMode()
        try originalValuesAndExpiry()
        try cacheAndLateResponses()
        try cacheAndLateResponses(allowsExpansion: false)
        print("SiteDaylightSavingTimePresentationTests passed (visibility, expansion, current-offset dates, raw snapshot preservation, expiry, durable cache, late responses)")
    }

    static func visibilityAndExpansion() throws {
        var state = SiteDaylightSavingTimePresentation()
        let chicago = try snapshot()
        state.update(identifier: nil, snapshot: nil, at: sampled)
        state.toggleExpansion()
        check(state.content == nil && !state.isExpanded, "Unknown timezone has no hint to expand")
        state.update(identifier: chicago.identifier, snapshot: nil, at: sampled)
        check(state.content == nil, "No server/cache snapshot must not invent DST support")
        state.update(identifier: chicago.identifier, snapshot: chicago, at: sampled)
        check(state.content?.status == .active && !state.isExpanded, "First supported timezone starts collapsed")
        state.toggleExpansion()
        check(state.isExpanded, "Disclosure reveals help")
        state.update(identifier: chicago.identifier, snapshot: chicago, at: sampled.addingTimeInterval(60))
        check(state.isExpanded, "Same IANA refresh or selection cancellation preserves expanded help")

        let paris = try snapshot("Europe/Paris", response: response(dst: false, current: "UTC+01:00",
            next: "2027-03-28T03:00:00+02:00", to: "UTC+02:00"))
        state.update(identifier: paris.identifier, snapshot: paris, at: sampled)
        check(state.content?.status == .inactive && !state.isExpanded, "Supported standard time remains visible; changing IANA collapses")
        state.toggleExpansion()
        state.update(identifier: paris.identifier, snapshot: chicago, at: sampled)
        check(state.content?.currentOffset == "UTC+01:00" && state.isExpanded, "Wrong-IANA late data cannot replace current content")
        state.update(identifier: chicago.identifier, snapshot: chicago, at: sampled)
        check(!state.isExpanded, "A to B to A must not restore A's old disclosure preference")

        state.toggleExpansion()
        let fixed = try snapshot(response: response(dst: true, next: NSNull(), to: NSNull()))
        state.update(identifier: chicago.identifier, snapshot: fixed, at: sampled)
        check(state.content == nil && !state.isExpanded, "Only next_switch controls visibility, even if is_dst is true")
        state.update(identifier: chicago.identifier, snapshot: chicago, at: sampled)
        check(state.content != nil && !state.isExpanded, "Support reappearing for same IANA starts collapsed")
        state.toggleExpansion()
        state.update(identifier: "Europe/Paris", snapshot: nil, at: sampled)
        check(state.content == nil && !state.isExpanded, "Changing to uncached IANA immediately removes old hint")
    }

    static func gatewaySummaryMode() throws {
        var form = SiteDaylightSavingTimePresentation()
        var summary = SiteDaylightSavingTimePresentation(allowsExpansion: false)
        let active = try snapshot("Australia/Lord_Howe", response: response(current: "UTC+11:00",
            next: "2027-04-04T01:30:00.123+10:30", to: "UTC+10:30"))
        for instant in [sampled, date("2027-04-03T15:00:00.123Z"), sampled.addingTimeInterval(-1)] {
            form.update(identifier: active.identifier, snapshot: active, at: instant)
            summary.update(identifier: active.identifier, snapshot: active, at: instant)
            check(summary.content == form.content, "Both hosts must share values, status and expiry")
            check(summary.content?.currentOffset == "UTC+11:00 (DST)"
                && summary.content?.switchesTo == "UTC+10:30"
                && summary.content?.nextSwitch == "2027-04-04 02:00 AM",
                "Summary must format the switch using the current half-hour DST offset")
            summary.toggleExpansion()
            check(!summary.isExpanded, "Gateway summary cannot expand, including stale cache")
        }
        form.toggleExpansion()
        check(form.isExpanded, "Default form must remain expandable")
        let standard = try snapshot("Europe/Paris", response: response(dst: false, current: "UTC+01:00",
            next: "2027-03-28T03:00:00+02:00", to: "UTC+02:00"))
        summary.update(identifier: standard.identifier, snapshot: standard, at: sampled)
        check(summary.content?.status == .inactive && summary.content?.currentOffset == "UTC+01:00"
            && summary.content?.switchesTo == "UTC+02:00 (DST)", "Inactive summary must use real values, not Figma examples")
        summary.toggleExpansion()
        check(!summary.isExpanded, "Inactive summary is also read-only")
        summary.update(identifier: active.identifier, snapshot: standard, at: sampled)
        check(summary.content == nil, "Changed IANA must not flash a previous summary")
        let fixed = try snapshot("Asia/Kathmandu", response: response(dst: false, current: "UTC+05:45",
            next: NSNull(), to: NSNull()))
        summary.update(identifier: fixed.identifier, snapshot: fixed, at: sampled)
        check(summary.content == nil, "Non-DST zones do not leave an empty summary")
        summary.update(identifier: active.identifier, snapshot: nil, at: sampled)
        check(summary.content == nil, "Pending first response is hidden")
    }

    static func originalValuesAndExpiry() throws {
        var state = SiteDaylightSavingTimePresentation()
        let halfHour = try snapshot("Australia/Lord_Howe", response: response(current: "UTC+11:00",
            next: "2027-04-04T01:30:00.123+10:30", to: "UTC+10:30"))
        state.update(identifier: halfHour.identifier, snapshot: halfHour, at: sampled)
        check(state.content?.currentOffset == "UTC+11:00 (DST)", "Active DST marks the current offset")
        check(state.content?.nextSwitch == "2027-04-04 02:00 AM", "Presentation uses the pre-switch clock without displaying seconds")
        check(halfHour.nextSwitch == "2027-04-04T01:30:00.123+10:30"
            && halfHour.nextSwitchDate == date("2027-04-03T15:00:00.123Z"), "Snapshot retains fractional seconds, timezone and absolute instant")
        check(state.content?.switchesTo == "UTC+10:30", "Half-hour target is neither inferred nor reordered")
        let standardTime = try snapshot(response: response(dst: false, current: "UTC-05:00",
            next: "2027-03-14T03:00:00-04:00", to: "UTC-04:00"))
        state.update(identifier: standardTime.identifier, snapshot: standardTime, at: sampled)
        check(state.content?.currentOffset == "UTC-05:00" && state.content?.switchesTo == "UTC-04:00 (DST)",
              "Inactive DST marks only the future offset, using is_dst rather than numeric ordering")
        let chicago = try snapshot()
        state.update(identifier: chicago.identifier, snapshot: chicago, at: transition.addingTimeInterval(-1))
        state.toggleExpansion()
        state.update(identifier: chicago.identifier, snapshot: chicago, at: transition)
        check(state.content?.status == .refreshRequired && state.isExpanded, "Expiry replaces active status without closing help")
        check(state.content?.currentOffset == "UTC-05:00 (DST)" && state.content?.switchesTo == "UTC-06:00"
            && state.content?.nextSwitch == "2026-11-01 02:00 AM",
              "Expired cache is shown as historical values, never locally flipped")
        state.update(identifier: chicago.identifier, snapshot: chicago, at: sampled.addingTimeInterval(-1))
        check(state.content?.status == .refreshRequired, "Clock rollback cannot label a future snapshot current")
        let standard = try snapshot(response: response(dst: false, current: "UTC-06:00",
            next: "2027-03-14T03:00:00-05:00", to: "UTC-05:00"), at: transition)
        state.update(identifier: chicago.identifier, snapshot: standard, at: transition)
        check(state.content?.status == .inactive && state.isExpanded, "Successful refresh restores status and keeps disclosure")
    }

    static func nextSwitchFormatting() throws {
        // Synthetic server offsets deliberately differ from the IANA and the phone timezone.
        let cases: [(current: String, next: String, to: String, utc: String, expected: String)] = [
            ("UTC+09:00", "2027-04-30T01:00:00+03:00", "UTC+03:00", "2027-04-29T22:00:00Z", "2027-04-30 07:00 AM"),
            ("UTC+02:00", "2027-04-30T01:00:00+03:00", "UTC+03:00", "2027-04-29T22:00:00Z", "2027-04-30 12:00 AM"),
            ("UTC+01:00", "2027-03-28T03:00:00+02:00", "UTC+02:00", "2027-03-28T01:00:00Z", "2027-03-28 02:00 AM"),
            ("UTC-05:00", "2027-11-07T01:00:00-06:00", "UTC-06:00", "2027-11-07T07:00:00Z", "2027-11-07 02:00 AM"),
            ("UTC+11:00", "2027-04-04T01:30:00.123+10:30", "UTC+10:30", "2027-04-03T15:00:00.123Z", "2027-04-04 02:00 AM"),
            ("UTC-05:00", "2027-01-01T02:00:00Z", "UTC-04:00", "2027-01-01T02:00:00Z", "2026-12-31 09:00 PM"),
            ("UTC+05:45", "2027-04-30T01:00:00Z", "UTC+06:00", "2027-04-30T01:00:00Z", "2027-04-30 06:45 AM"),
            ("UTC+03:00", "2027-04-30T01:00:00+03:00", "UTC+04:00", "2027-04-29T22:00:00Z", "2027-04-30 01:00 AM"),
            ("UTC+02:00", "2027-12-31T23:30:00Z", "UTC+03:00", "2027-12-31T23:30:00Z", "2028-01-01 01:30 AM"),
            ("UTC+00:00", "2027-04-30T12:00:59.999Z", "UTC+01:00", "2027-04-30T12:00:59.999Z", "2027-04-30 12:00 PM")
        ]
        let savedTimeZone = NSTimeZone.default
        defer { NSTimeZone.default = savedTimeZone }
        for item in cases {
            let original = try snapshot("Etc/UTC", response: response(dst: false, current: item.current, next: item.next, to: item.to))
            let encoded = try JSONEncoder().encode(original)
            let restored = try JSONDecoder().decode(SiteTimeZoneSnapshot.self, from: encoded)
            let switchDate = date(item.utc)
            check(original.nextSwitchDate == switchDate && restored == original, "Real parsing and Codable must preserve the absolute transition")
            check(restored.nextSwitch == item.next && restored.nextSwitchDate == switchDate, "Cached ISO precision must not be replaced by presentation text")
            check(restored.isUsable(at: switchDate.addingTimeInterval(-0.001)) && !restored.isUsable(at: switchDate),
                  "Minute-only display must not round the actual validity boundary")
            for phoneOffset in [-10 * 3600, 14 * 3600] {
                NSTimeZone.default = TimeZone(secondsFromGMT: phoneOffset)!
                var form = SiteDaylightSavingTimePresentation()
                var summary = SiteDaylightSavingTimePresentation(allowsExpansion: false)
                for instant in [sampled, switchDate] {
                    form.update(identifier: restored.identifier, snapshot: restored, at: instant)
                    summary.update(identifier: restored.identifier, snapshot: restored, at: instant)
                    check(form.content?.nextSwitch == item.expected, "Wrong current-offset display for \(item.next), \(item.current): \(form.content?.nextSwitch ?? "nil")")
                    check(form.content == summary.content, "Form and gateway must show the same date independent of the phone timezone")
                    check(form.content?.status == (instant == sampled ? .inactive : .refreshRequired), "Formatting must retain expiry status")
                }
            }
        }
    }

    static func cacheAndLateResponses(allowsExpansion: Bool = true) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = SiteTimeZoneCache(directory: directory)
        var now = sampled
        var requests: [String: (Result<[String: Any], Error>) -> Void] = [:]
        let store = SiteTimeZoneStore(now: { now }, read: cache.read, write: cache.write) { id, _, reply in
            requests[id] = reply
        }
        var selected = "America/Chicago"
        var state = SiteDaylightSavingTimePresentation(allowsExpansion: allowsExpansion)
        func render() { state.update(identifier: selected, snapshot: store.snapshot(for: selected), at: now) }
        var token = store.observe(identifier: selected, callback: render)
        render()
        store.refresh(identifier: selected)
        pump { requests["America/Chicago"] != nil }
        // The host changes identity and removes the previous observer before B is rendered.
        store.removeObserver(token)
        selected = "Australia/Lord_Howe"
        token = store.observe(identifier: selected, callback: render)
        render()
        store.refresh(identifier: selected)
        pump { requests[selected] != nil }
        requests.removeValue(forKey: selected)?(.success(response(current: "UTC+11:00",
            next: "2027-04-04T01:30:00.123+10:30", to: "UTC+10:30")))
        pump { state.content?.currentOffset == "UTC+11:00 (DST)" }
        state.toggleExpansion()
        requests.removeValue(forKey: "America/Chicago")?(.success(response()))
        pump { store.snapshot(for: "America/Chicago") != nil }
        check(state.content?.currentOffset == "UTC+11:00 (DST)" && state.content?.nextSwitch == "2027-04-04 02:00 AM"
            && state.isExpanded == allowsExpansion, "Late A result caches A without disturbing selected B")

        store.removeObserver(token)
        selected = "America/Chicago"
        token = store.observe(identifier: selected, callback: render)
        render()
        check(state.content?.currentOffset == "UTC-05:00 (DST)" && state.content?.nextSwitch == "2026-11-01 02:00 AM"
            && !state.isExpanded, "Switching back uses A cache and resets disclosure")
        state.toggleExpansion()
        now = date("2026-10-29T05:00:00Z")
        store.refreshObserved()
        pump { requests[selected] != nil }
        requests.removeValue(forKey: selected)?(.failure(NSError(domain: "offline", code: 1)))
        var failed = false
        store.refresh(identifier: selected, retry: false) { _ in failed = true }
        pump { failed }
        check(state.content?.status == .active && state.content?.nextSwitch == "2026-11-01 02:00 AM"
            && state.isExpanded == allowsExpansion, "Pre-transition refresh failure retains usable cache")
        now = transition
        store.refreshObserved()
        check(state.content?.status == .refreshRequired, "Boundary notification marks stale content before network returns")
        pump { requests[selected] != nil }
        requests.removeValue(forKey: selected)?(.failure(NSError(domain: "offline", code: 1)))
        failed = false
        store.refresh(identifier: selected, retry: false) { _ in failed = true }
        pump { failed }
        check(state.content?.status == .refreshRequired && state.content?.nextSwitch == "2026-11-01 02:00 AM"
            && state.isExpanded == allowsExpansion, "Post-transition failure preserves the cached date and never restores old active badge")
        var invalidFinished = false
        store.refresh(identifier: selected) { _ in invalidFinished = true }
        pump { requests[selected] != nil }
        requests.removeValue(forKey: selected)?(.success(response(next: "invalid-date")))
        pump { invalidFinished }
        check(state.content?.status == .refreshRequired && state.content?.nextSwitch == "2026-11-01 02:00 AM",
              "Invalid server date cannot replace the formatted cached transition")
        store.refresh(identifier: selected)
        pump { requests[selected] != nil }
        requests.removeValue(forKey: selected)?(.success(response(dst: false, current: "UTC-06:00",
            next: "2027-03-14T03:00:00-05:00", to: "UTC-05:00")))
        pump { state.content?.status == .inactive }
        check(state.content?.nextSwitch == "2027-03-14 02:00 AM" && state.isExpanded == allowsExpansion, "Recovery updates the formatted date and preserves disclosure")
        store.removeObserver(token)

        var restarted = SiteDaylightSavingTimePresentation(allowsExpansion: allowsExpansion)
        var extraRequests = 0
        let restoredStore = SiteTimeZoneStore(now: { now }, read: cache.read, write: cache.write) { _, _, _ in extraRequests += 1 }
        let restoredToken = restoredStore.observe(identifier: selected) {
            restarted.update(identifier: selected, snapshot: restoredStore.snapshot(for: selected), at: now)
        }
        restoredStore.refresh(identifier: selected)
        pump { restarted.content != nil }
        check(restarted.content?.status == .inactive && restarted.content?.nextSwitch == "2027-03-14 02:00 AM"
            && !restarted.isExpanded && extraRequests == 0, "Restart formats real persisted fields without restoring disclosure preference")
        check(restoredStore.snapshot(for: selected)?.nextSwitch == "2027-03-14T03:00:00-05:00"
            && restoredStore.snapshot(for: selected)?.nextSwitchDate == date("2027-03-14T08:00:00Z"), "Disk cache retains the original timestamp for synchronization")
        restoredStore.removeObserver(restoredToken)
    }
}
