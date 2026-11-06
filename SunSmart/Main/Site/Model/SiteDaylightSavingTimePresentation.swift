import Foundation

/// Page-local disclosure state. The existing timezone store owns all requests and persistence.
struct SiteDaylightSavingTimePresentation: Equatable {
    enum Status { case active, inactive, refreshRequired }
    struct Content: Equatable {
        let currentOffset: String
        let nextSwitch: String
        let switchesTo: String
        let status: Status
    }

    private var identifier: String?
    private(set) var content: Content?
    private(set) var isExpanded = false
    let allowsExpansion: Bool

    init(allowsExpansion: Bool = true) {
        self.allowsExpansion = allowsExpansion
    }

    mutating func update(identifier: String?, snapshot: SiteTimeZoneSnapshot?, at date: Date) {
        if self.identifier != identifier {
            self.identifier = identifier
            content = nil
            isExpanded = false
        }
        // Reject late data for another selection without replacing the current hint.
        if let identifier, let snapshot, snapshot.identifier != identifier { return }
        guard identifier != nil, let snapshot, let nextSwitch = snapshot.nextSwitchDate,
              let switchesTo = snapshot.switchesTo,
              let timeZone = TimeZone(secondsFromGMT: snapshot.offsetMinutes * 60) else {
            content = nil
            isExpanded = false
            return
        }
        let dstSuffix = NSLocalizedString("site_time_zone_dst_suffix", value: " (DST)", comment: "Daylight saving time suffix")
        // Decorate presentation only; the snapshot keeps raw offsets for clocks and synchronization.
        content = Content(currentOffset: snapshot.currentOffset + (snapshot.isDST ? dstSuffix : ""),
                          nextSwitch: Self.formattedNextSwitch(nextSwitch, timeZone: timeZone),
                          switchesTo: switchesTo + (snapshot.isDST ? "" : dstSuffix),
                          status: snapshot.isUsable(at: date) ? (snapshot.isDST ? .active : .inactive) : .refreshRequired)
    }

    private static func formattedNextSwitch(_ date: Date, timeZone: TimeZone) -> String {
        // Show the transition on the pre-switch clock, including when displaying stale cache.
        // The snapshot expires at this instant, so effectiveOffset(at:) cannot format it.
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd hh:mm a"
        return formatter.string(from: date)
    }

    mutating func toggleExpansion() {
        guard allowsExpansion, content != nil else { return }
        isExpanded.toggle()
    }
}
