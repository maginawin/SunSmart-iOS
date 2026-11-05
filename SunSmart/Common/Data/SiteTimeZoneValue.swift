import Foundation
import CoreFoundation

/// A Site property is an IANA identity. Offsets are dated server observations, never stored Site props.
struct SiteTimeZoneValue: Hashable {
    let ianaId: String
    private let catalogOffsetMinutes: Int?

    // Installed once by the runtime service. Kept injectable for the Foundation-only policy tests.
    static var snapshotProvider: (String, Date) -> SiteTimeZoneSnapshot? = { _, _ in nil }

    init?(storageValue: String) {
        var value = storageValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = Self.match(#"^(.+?) \(UTC([+-]\d{2}:\d{2})\)$"#, value),
           let name = Range(match.range(at: 1), in: value),
           let offset = Range(match.range(at: 2), in: value) {
            guard Self.parseOffset(String(value[offset])) != nil else { return nil }
            value = String(value[name]) // Deliberately discard the legacy offset.
        }
        guard Self.validIdentifier(value) else { return nil }
        ianaId = value
        catalogOffsetMinutes = Self.bundledOffsets[value]
    }

    /// Catalog-only fallback for display. This offset never authorizes a TimeSet.
    init?(ianaId: String, rawUTCOffset: String) {
        let identifier = ianaId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.validIdentifier(identifier), let offset = Self.parseOffset(rawUTCOffset) else { return nil }
        self.ianaId = identifier
        catalogOffsetMinutes = offset
    }

    /// Preserve unsupported stored values without treating them as usable time zones.
    /// This keeps field merging/export lossless while clock consumers can fall back.
    static func preservingStorageValue(_ raw: String) -> Self {
        if let value = Self(storageValue: raw) { return value }
        return Self(unvalidatedStorageValue: raw)
    }
    private init(unvalidatedStorageValue: String) {
        ianaId = unvalidatedStorageValue
        catalogOffsetMinutes = nil
    }
    var isRecognizedTimeZone: Bool {
        Self.validIdentifier(ianaId) && (TimeZone(identifier: ianaId) != nil
            || catalogOffsetMinutes != nil || snapshot() != nil)
    }
    var storageValue: String { ianaId }
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.ianaId == rhs.ianaId }
    func hash(into hasher: inout Hasher) { hasher.combine(ianaId) }

    func snapshot(at date: Date = Date()) -> SiteTimeZoneSnapshot? {
        guard let snapshot = Self.snapshotProvider(ianaId, date), snapshot.identifier == ianaId else { return nil }
        return snapshot
    }
    func effectiveOffset(at date: Date = Date()) -> Int? {
        guard let snapshot = snapshot(at: date), snapshot.isUsable(at: date) else { return nil }
        return snapshot.offsetMinutes
    }
    var offsetMinutes: Int? { effectiveOffset() }
    var isMeshTimeZoneOffsetEncodable: Bool { offsetMinutes.map(Self.isMeshEncodable) ?? false }
    var displayOffset: String { displayOffset(at: Date()) }
    func displayOffset(at date: Date) -> String {
        if let snapshot = snapshot(at: date), snapshot.isUsable(at: date) { return snapshot.displayOffset }
        let fallback = catalogOffsetMinutes.map(Self.formatOffset)
            ?? NSLocalizedString("site_create_unknown", value: "Unknown", comment: "Unknown time zone")
        guard snapshot(at: date) != nil else { return fallback }
        return fallback + " · " + NSLocalizedString("site_time_zone_refresh_required", value: "Refresh required", comment: "Expired time zone snapshot")
    }
    var currentOffsetDescription: String {
        offsetMinutes.map(Self.formatOffset) ?? NSLocalizedString("site_time_zone_refresh_required", value: "Refresh required", comment: "Time zone unavailable")
    }
    func formattedLocalDate(at date: Date) -> String {
        guard let offset = effectiveOffset(at: date),
              let zone = TimeZone(secondsFromGMT: offset * 60) else { return "--" }
        let formatter = Self.formatter(timeZone: zone, format: "yyyy-M-d h:mm:ss a")
        return formatter.string(from: date)
    }
    static func formattedGatewayLastOnline(timestamp: Int64?, storageValue: String?, phoneTimeZone: TimeZone = .current) -> String? {
        guard let timestamp, timestamp > 0 else { return nil }
        let identity = storageValue.flatMap(Self.init(storageValue:))
        // Historical instants need historical rules; today's API snapshot cannot describe them.
        let zone = identity.flatMap { TimeZone(identifier: $0.ianaId) }
            ?? (identity == nil ? phoneTimeZone : TimeZone(secondsFromGMT: 0)!)
        return formatter(timeZone: zone, format: "yyyy-MM-dd HH:mm").string(from: Date(timeIntervalSince1970: TimeInterval(timestamp)))
    }
    static func parseOffset(_ raw: String) -> Int? {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(?:UTC)?([+-])(\d{2}):(\d{2})$"#
        guard let match = match(pattern, value),
              let sign = Range(match.range(at: 1), in: value),
              let hour = Range(match.range(at: 2), in: value),
              let minute = Range(match.range(at: 3), in: value),
              let hours = Int(value[hour]), let minutes = Int(value[minute]),
              minutes < 60, hours * 60 + minutes <= 840 else { return nil }
        return (value[sign] == "-" ? -1 : 1) * (hours * 60 + minutes)
    }
    static func formatOffset(_ minutes: Int) -> String {
        String(format: "UTC%@%02d:%02d", minutes < 0 ? "-" : "+", abs(minutes) / 60, abs(minutes) % 60)
    }
    static func isMeshEncodable(_ minutes: Int) -> Bool {
        minutes.isMultiple(of: 15) && (0...255).contains(minutes / 15 + 64)
    }
    private static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 255
            && match(#"^[A-Za-z0-9_+.-]+(?:/[A-Za-z0-9_+.-]+)*$"#, value) != nil
            && !value.split(separator: "/").contains(where: { $0 == "." || $0 == ".." })
    }
    private static func match(_ pattern: String, _ value: String) -> NSTextCheckingResult? {
        (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: value, range: NSRange(value.startIndex..., in: value))
    }
    private static func formatter(timeZone: TimeZone, format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = format
        return formatter
    }
    private static let bundledOffsets: [String: Int] = {
        var offsets = ["Etc/UTC": 0]
        if let url = Bundle.main.url(forResource: "all_utc_timezones", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let entries = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            for entry in entries {
                if let id = entry["ianaId"] as? String, let raw = entry["utcOffset"] as? String,
                   let offset = parseOffset(raw) { offsets[id] = offset }
            }
        }
        return offsets
    }()
}

/// Complete server response, including its sampling instant. No locally inferred DST state.
struct SiteTimeZoneSnapshot: Codable, Equatable {
    let identifier: String
    let isDST: Bool
    let currentOffset: String
    let nextSwitch: String?
    let switchesTo: String?
    let requestedAt: Date

    enum Invalid: Error { case response }
    private let parsedOffsetMinutes: Int?
    let nextSwitchDate: Date?
    private enum CodingKeys: String, CodingKey { case identifier, isDST, currentOffset, nextSwitch, switchesTo, requestedAt }
    var offsetMinutes: Int { parsedOffsetMinutes! }
    var displayOffset: String {
        guard nextSwitch != nil, let switchesTo else { return currentOffset }
        if isDST {
            return switchesTo + " / " + currentOffset + NSLocalizedString("site_time_zone_dst_suffix", value: " (DST)", comment: "Daylight saving time suffix")
        }
        return currentOffset + " / " + switchesTo
    }
    init(identifier: String, response: [String: Any], requestedAt: Date) throws {
        guard let code = response["code"] as? NSNumber, CFGetTypeID(code) != CFBooleanGetTypeID(), code == 200,
              let data = response["data"] as? [String: Any],
              let dst = data["is_dst"] as? NSNumber, CFGetTypeID(dst) == CFBooleanGetTypeID(),
              let current = data["current_offset"] as? String,
              data.keys.contains("next_switch"), data.keys.contains("switches_to"),
              data["next_switch"] is NSNull || data["next_switch"] is String,
              data["switches_to"] is NSNull || data["switches_to"] is String else { throw Invalid.response }
        self.identifier = identifier; isDST = dst.boolValue; currentOffset = current
        nextSwitch = data["next_switch"] as? String; switchesTo = data["switches_to"] as? String
        self.requestedAt = requestedAt
        parsedOffsetMinutes = SiteTimeZoneValue.parseOffset(currentOffset)
        nextSwitchDate = nextSwitch.flatMap(Self.parseDate)
        guard isValid else { throw Invalid.response }
    }
    private var isValid: Bool {
        guard SiteTimeZoneValue(storageValue: identifier)?.ianaId == identifier,
              currentOffset.hasPrefix("UTC"), SiteTimeZoneValue.parseOffset(currentOffset) != nil,
              requestedAt.timeIntervalSince1970.isFinite else { return false }
        if nextSwitch == nil { return switchesTo == nil }
        guard let next = nextSwitchDate, next > requestedAt, let switchesTo,
              switchesTo.hasPrefix("UTC"), SiteTimeZoneValue.parseOffset(switchesTo) != nil else { return false }
        return true
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try c.decode(String.self, forKey: .identifier)
        isDST = try c.decode(Bool.self, forKey: .isDST)
        currentOffset = try c.decode(String.self, forKey: .currentOffset)
        nextSwitch = try c.decodeIfPresent(String.self, forKey: .nextSwitch)
        switchesTo = try c.decodeIfPresent(String.self, forKey: .switchesTo)
        requestedAt = try c.decode(Date.self, forKey: .requestedAt)
        parsedOffsetMinutes = SiteTimeZoneValue.parseOffset(currentOffset)
        nextSwitchDate = nextSwitch.flatMap(Self.parseDate)
        guard isValid else { throw Invalid.response }
    }
    func isUsable(at date: Date) -> Bool {
        date >= requestedAt && (nextSwitchDate.map { date < $0 } ?? true)
    }
    func needsRefresh(at date: Date) -> Bool {
        !isUsable(at: date) || dayKey(at: date) != dayKey(at: requestedAt)
    }
    private func dayKey(at date: Date) -> DateComponents {
        // The server's offset defines the IANA's local date within this snapshot's validity.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: offsetMinutes * 60)!
        return calendar.dateComponents([.year, .month, .day], from: date)
    }
    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions.insert(.withFractionalSeconds)
        return formatter.date(from: text)
    }
    static func requestDateString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date).replacingOccurrences(of: "Z", with: "+00:00")
    }
}
