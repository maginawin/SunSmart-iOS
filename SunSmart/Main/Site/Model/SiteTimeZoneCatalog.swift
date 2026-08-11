//
//  SiteTimeZoneCatalog.swift
//  SunSmart
//
//  Created by One on 2026/8/11.
//

import Foundation

struct SiteTimeZoneCatalogEntry: Equatable, Decodable {

    let region: String
    let ianaId: String
    let utcOffset: String

    var value: SiteTimeZoneValue {
        return SiteTimeZoneValue(ianaId: ianaId, rawUTCOffset: utcOffset)!
    }

    init(region: String, ianaId: String, utcOffset: String) throws {
        let normalizedRegion = region.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedIanaId = ianaId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOffset = utcOffset.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRegion.isEmpty,
              SiteTimeZoneValue(
                ianaId: normalizedIanaId,
                rawUTCOffset: normalizedOffset
              ) != nil else {
            throw SiteTimeZoneCatalogError.invalidEntry
        }
        self.region = normalizedRegion
        self.ianaId = normalizedIanaId
        self.utcOffset = normalizedOffset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            region: container.decode(String.self, forKey: .region),
            ianaId: container.decode(String.self, forKey: .ianaId),
            utcOffset: container.decode(String.self, forKey: .utcOffset)
        )
    }

    private enum CodingKeys: String, CodingKey {
        case region
        case ianaId
        case utcOffset
    }
}

struct SiteTimeZoneCatalogSection: Equatable {
    let region: String
    let entries: [SiteTimeZoneCatalogEntry]
}

struct SiteTimeZoneCatalog {

    let allSections: [SiteTimeZoneCatalogSection]

    init(data: Data) throws {
        let entries = try JSONDecoder().decode([SiteTimeZoneCatalogEntry].self, from: data)
        var regionOrder: [String] = []
        var entriesByRegion: [String: [SiteTimeZoneCatalogEntry]] = [:]

        for entry in entries {
            if entriesByRegion[entry.region] == nil {
                regionOrder.append(entry.region)
                entriesByRegion[entry.region] = []
            }
            entriesByRegion[entry.region]?.append(entry)
        }

        let utcEntry = try SiteTimeZoneCatalogEntry(
            region: "UTC",
            ianaId: "Etc/UTC",
            utcOffset: "+00:00"
        )
        var sections = [SiteTimeZoneCatalogSection(region: "UTC", entries: [utcEntry])]
        sections.append(contentsOf: regionOrder.map {
            SiteTimeZoneCatalogSection(region: $0, entries: entriesByRegion[$0] ?? [])
        })
        self.allSections = sections
    }

    func sections(matching query: String) -> [SiteTimeZoneCatalogSection] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuery.isEmpty else {
            return allSections
        }

        return allSections.compactMap { section in
            if section.region.localizedCaseInsensitiveContains(normalizedQuery) {
                return section
            }
            let entries = section.entries.filter { entry in
                entry.ianaId.localizedCaseInsensitiveContains(normalizedQuery)
                    || entry.utcOffset.localizedCaseInsensitiveContains(normalizedQuery)
                    || entry.value.displayOffset.localizedCaseInsensitiveContains(normalizedQuery)
            }
            guard !entries.isEmpty else {
                return nil
            }
            return SiteTimeZoneCatalogSection(region: section.region, entries: entries)
        }
    }

    func defaultValue(for phoneTimeZone: TimeZone, at date: Date) -> SiteTimeZoneValue {
        if let entry = allSections
            .flatMap(\.entries)
            .first(where: { $0.ianaId == phoneTimeZone.identifier }) {
            return entry.value
        }

        let utcIdentifiers: Set<String> = ["UTC", "GMT", "Etc/UTC", "Etc/GMT"]
        if utcIdentifiers.contains(phoneTimeZone.identifier) {
            return SiteTimeZoneValue(ianaId: "Etc/UTC", rawUTCOffset: "+00:00")!
        }

        return Self.fallbackValue(for: phoneTimeZone, at: date)
    }

    static func bundled() throws -> SiteTimeZoneCatalog {
        guard let url = Bundle.main.url(
            forResource: "all_utc_timezones",
            withExtension: "json"
        ) else {
            throw SiteTimeZoneCatalogError.resourceMissing
        }
        return try SiteTimeZoneCatalog(data: Data(contentsOf: url))
    }

    static func phoneDefaultValue(
        for phoneTimeZone: TimeZone = .current,
        at date: Date = Date()
    ) -> SiteTimeZoneValue {
        if let catalog = try? bundled() {
            return catalog.defaultValue(for: phoneTimeZone, at: date)
        }
        return fallbackValue(for: phoneTimeZone, at: date)
    }
}

extension SiteTimeZoneCatalog {

    static func fallbackValue(for phoneTimeZone: TimeZone, at date: Date) -> SiteTimeZoneValue {
        let currentSeconds = phoneTimeZone.secondsFromGMT(for: date)
        let daylightSavingSeconds = Int(phoneTimeZone.daylightSavingTimeOffset(for: date))
        let standardSeconds = currentSeconds - daylightSavingSeconds
        let offsetMinutes = min(max(Int((Double(standardSeconds) / 60.0).rounded()), -840), 840)
        let sign = offsetMinutes < 0 ? "-" : "+"
        let magnitude = abs(offsetMinutes)
        let rawOffset = String(format: "%@%02d:%02d", sign, magnitude / 60, magnitude % 60)
        return SiteTimeZoneValue(
            ianaId: phoneTimeZone.identifier,
            rawUTCOffset: rawOffset
        )!
    }
}

enum SiteTimeZoneCatalogError: Error {
    case invalidEntry
    case resourceMissing
}
