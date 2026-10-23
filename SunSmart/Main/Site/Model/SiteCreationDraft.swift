import Foundation

enum SiteCreationTextField: String, CaseIterable {
    case description, streetAddress, postalCode, latitude, longitude

    var maximumLength: Int {
        switch self {
        case .description, .streetAddress: return 300
        case .postalCode: return 100
        case .latitude, .longitude: return 50
        }
    }

    func normalized(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(trimmed.prefix(maximumLength)).trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    /// Do not trim ordinary keystrokes; preserve spaces while typing a multi-word value.
    func limitingInput(_ text: String) -> String {
        guard text.trimmingCharacters(in: .whitespacesAndNewlines).count > maximumLength else { return text }
        return normalized(text) ?? ""
    }
}

/// Transient form values. Constructing or changing a draft never creates a Site or Mesh.
struct SiteCreationDraft {
    enum ValueSource { case initial, city, manual }
    var siteName: String
    private(set) var timezone: SiteTimeZoneValue?
    private let initialTimezone: SiteTimeZoneValue?
    private(set) var timezoneSource: ValueSource = .initial
    private(set) var coordinateSources: [SiteCreationTextField: ValueSource] = [:]
    private(set) var city: CityCatalog.Entry?
    var imageId = 1
    var siteType: SiteExtensionData.ProjectType = .standard
    var text: [SiteCreationTextField: String] = [:]
    private(set) var countryRegionCode: String?

    init(siteName: String, timezone: SiteTimeZoneValue?) {
        self.siteName = siteName
        self.timezone = timezone
        initialTimezone = timezone
    }

    mutating func selectCountry(_ entry: CountryRegionCatalog.Entry) {
        guard countryRegionCode != entry.code else { return }
        countryRegionCode = entry.code
        city = nil
        for field in [SiteCreationTextField.latitude, .longitude] where coordinateSources[field] == .city {
            text[field] = nil
            coordinateSources[field] = .initial
        }
        if timezoneSource == .city { timezone = initialTimezone; timezoneSource = .initial }
    }

    @discardableResult
    mutating func selectCity(_ entry: CityCatalog.Entry, timezone: SiteTimeZoneValue?) -> Bool {
        guard entry.countryCode == countryRegionCode,
              let timezone, timezone.ianaId == entry.timezoneIdentifier,
              entry.record.latitude.isFinite, entry.record.longitude.isFinite,
              (-90...90).contains(entry.record.latitude), (-180...180).contains(entry.record.longitude) else { return false }
        guard city?.id != entry.id else { return true }
        city = entry
        self.timezone = timezone
        timezoneSource = .city
        text[.latitude] = entry.latitudeText
        text[.longitude] = entry.longitudeText
        coordinateSources[.latitude] = .city
        coordinateSources[.longitude] = .city
        return true
    }

    mutating func selectManualTimezone(_ value: SiteTimeZoneValue) {
        timezone = value; timezoneSource = .manual
    }

    mutating func editText(_ field: SiteCreationTextField, value: String) {
        text[field] = value
        if field == .latitude || field == .longitude { coordinateSources[field] = .manual }
    }

    func isNameValid(isDuplicate: Bool) -> Bool {
        // Match Edit Site's existing ordinary-space and Character-count semantics.
        !siteName.isEmpty && siteName.contains(where: { $0 != " " })
            && siteName.count <= 32 && !isDuplicate
    }

    var extensionData: SiteExtensionData {
        var data = SiteExtensionData()
        data.siteType = siteType
        for key in SiteExtensionData.metadataKeys { data.fields[key] = .null }
        data.fields["countryRegion"] = countryRegionCode.map(SiteJSONValue.string) ?? .null
        data.fields["city"] = city.map { .string($0.id) } ?? .null
        for field in SiteCreationTextField.allCases {
            data.fields[field.rawValue] = field.normalized(text[field] ?? "").map(SiteJSONValue.string) ?? .null
        }
        return data
    }
}
