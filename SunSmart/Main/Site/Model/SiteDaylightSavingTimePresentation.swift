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

    mutating func update(identifier: String?, snapshot: SiteTimeZoneSnapshot?, at date: Date) {
        if self.identifier != identifier {
            self.identifier = identifier
            content = nil
            isExpanded = false
        }
        // Reject late data for another selection without replacing the current hint.
        if let identifier, let snapshot, snapshot.identifier != identifier { return }
        guard identifier != nil, let snapshot, let nextSwitch = snapshot.nextSwitch,
              let switchesTo = snapshot.switchesTo else {
            content = nil
            isExpanded = false
            return
        }
        let dstSuffix = NSLocalizedString("site_time_zone_dst_suffix", value: " (DST)", comment: "Daylight saving time suffix")
        // Decorate presentation only; the snapshot keeps raw offsets for clocks and synchronization.
        content = Content(currentOffset: snapshot.currentOffset + (snapshot.isDST ? dstSuffix : ""),
                          nextSwitch: nextSwitch, switchesTo: switchesTo + (snapshot.isDST ? "" : dstSuffix),
                          status: snapshot.isUsable(at: date) ? (snapshot.isDST ? .active : .inactive) : .refreshRequired)
    }

    mutating func toggleExpansion() {
        guard content != nil else { return }
        isExpanded.toggle()
    }
}
