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
struct SiteFormDraft {
    struct InvalidCoordinate: Error { let field: SiteCreationTextField }
    enum CoordinateValidation: Equatable {
        case empty, valid(Double), invalidNumber, outOfRange
    }
    enum ValueSource { case initial, city, manual }
    var siteName: String
    private(set) var timezone: SiteTimeZoneValue?
    private let initialTimezone: SiteTimeZoneValue?
    private(set) var timezoneSource: ValueSource = .initial
    private(set) var coordinateSources: [SiteCreationTextField: ValueSource] = [:]
    private(set) var city: CityCatalog.Entry?
    private(set) var cityName: String?
    private(set) var cityID: Int?
    private var originalProperties: SiteStandardProperties?
    private var originalText: [SiteCreationTextField: String] = [:]
    var imageId = 1
    var siteType: SiteExtensionData.ProjectType = .standard
    var text: [SiteCreationTextField: String] = [:]
    private(set) var countryRegionCode: String?

    init(siteName: String, timezone: SiteTimeZoneValue?) {
        self.siteName = siteName
        self.timezone = timezone
        initialTimezone = timezone
    }

    init(values: SitePropsValues, properties: SiteStandardProperties, siteType: SiteExtensionData.ProjectType) {
        self.init(siteName: values.siteName, timezone: values.timezone)
        imageId = values.imageId
        self.siteType = siteType
        countryRegionCode = properties.countryRegion
        cityName = properties.city
        cityID = properties.cityId
        text = [.description: properties.siteDescription ?? "", .streetAddress: properties.address ?? "",
                .postalCode: properties.postalCode ?? "", .latitude: properties.latitude.map { String($0) } ?? "",
                .longitude: properties.longitude.map { String($0) } ?? ""]
        originalProperties = properties
        originalText = text
    }

    /// Catalog hydration resolves a label only; it must never reapply city defaults.
    mutating func resolveStoredCity(_ entry: CityCatalog.Entry) {
        guard hasCityIdentity, countryRegionCode == entry.countryCode, cityID == entry.record.id else { return }
        city = entry
    }

    private var hasCityIdentity: Bool {
        guard let cityName, let cityID else { return false }
        return !cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && cityID > 0
    }

    func resolvedCity(in catalog: CityCatalog?) -> CityCatalog.Entry? {
        guard hasCityIdentity, let cityID, let catalog, catalog.countryCode == countryRegionCode else { return nil }
        return catalog.entry(id: "geonames:\(cityID)")
    }

    static func canSubmit(isNameValid: Bool, showsCoordinateError: Bool, isCommitting: Bool) -> Bool {
        isNameValid && !showsCoordinateError && !isCommitting
    }

    mutating func selectCountry(_ entry: CountryRegionCatalog.Entry) {
        guard countryRegionCode != entry.code else { return }
        countryRegionCode = entry.code
        city = nil
        cityName = nil
        cityID = nil
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
        city = entry
        cityName = entry.record.name
        guard cityID != entry.record.id else { return true }
        cityID = entry.record.id
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

    /// GPS is an explicit form edit, so a later country change must not clear it as city-derived data.
    @discardableResult
    mutating func applyCurrentLocation(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite,
              (-90...90).contains(latitude), (-180...180).contains(longitude) else { return false }
        func format(_ value: Double) -> String {
            let rounded = (value * 1_000_000).rounded() / 1_000_000
            if rounded == 0 { return "0" }
            return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), rounded)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
        editText(.latitude, value: format(latitude))
        editText(.longitude, value: format(longitude))
        return true
    }

    func isNameValid(isDuplicate: Bool) -> Bool {
        // Match Edit Site's existing ordinary-space and Character-count semantics.
        !siteName.isEmpty && siteName.contains(where: { $0 != " " })
            && siteName.count <= 32 && !isDuplicate
    }

    var extensionData: SiteExtensionData {
        var data = SiteExtensionData()
        data.siteType = siteType
        return data
    }

    /// Shared by per-field feedback and CREATE; validation never changes the draft text or its source.
    func coordinateValidation(for field: SiteCreationTextField) -> CoordinateValidation {
        precondition(field == .latitude || field == .longitude)
        let raw = (text[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return .empty }
        guard let value = Double(raw), value.isFinite else { return .invalidNumber }
        let range: ClosedRange<Double> = field == .latitude ? -90...90 : -180...180
        return range.contains(value) ? .valid(value) : .outOfRange
    }

    func standardProperties() throws -> SiteStandardProperties {
        func coordinate(_ field: SiteCreationTextField) throws -> Double? {
            switch coordinateValidation(for: field) {
            case .empty: return nil
            case .valid(let value): return value
            case .invalidNumber, .outOfRange: throw InvalidCoordinate(field: field)
            }
        }
        func preservedText(_ field: SiteCreationTextField, original: String?) -> String? {
            if originalProperties != nil, (text[field] ?? "") == (originalText[field] ?? "") { return original }
            return field.normalized(text[field] ?? "")
        }
        return try SiteStandardProperties(
            latitude: coordinate(.latitude),
            longitude: coordinate(.longitude),
            countryRegion: countryRegionCode,
            postalCode: preservedText(.postalCode, original: originalProperties?.postalCode),
            city: cityName,
            cityId: cityID,
            address: preservedText(.streetAddress, original: originalProperties?.address),
            siteDescription: preservedText(.description, original: originalProperties?.siteDescription)
        )
    }
}
