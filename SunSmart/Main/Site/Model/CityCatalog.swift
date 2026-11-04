import Foundation

/// Immutable, validated snapshot for one country. Decode/index/search off the main thread.
struct CityCatalog {
    enum CatalogError: Error { case invalidCatalog, invalidEntry }

    struct Record: Codable {
        let id: Int
        let name: String
        let names: [String: String]
        let timezone: String
        let latitude: Double
        let longitude: Double

        private enum CodingKeys: String, CodingKey {
            case id, name, timezone, latitude, longitude
            case names = "names_json"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = try c.decode(Int.self, forKey: .id)
            name = try c.decode(String.self, forKey: .name)
            names = try c.decodeIfPresent([String: String?].self, forKey: .names)?.compactMapValues { $0 } ?? [:]
            timezone = try c.decode(String.self, forKey: .timezone)
            func coordinate(_ key: CodingKeys) throws -> Double {
                if let text = try? c.decode(String.self, forKey: key),
                   let value = Double(text.trimmingCharacters(in: .whitespacesAndNewlines)) { return value }
                return try c.decode(Double.self, forKey: key)
            }
            latitude = try coordinate(.latitude)
            longitude = try coordinate(.longitude)
        }
    }

    struct Entry {
        let countryCode: String
        let record: Record
        var id: String { "geonames:\(record.id)" }
        var timezoneIdentifier: String { record.timezone }
        var latitudeText: String { Self.coordinateText(record.latitude) }
        var longitudeText: String { Self.coordinateText(record.longitude) }

        func displayName(language: String) -> String {
            if language.lowercased().hasPrefix("zh"), let chinese = usable(record.names["zh-Hans"]) { return chinese }
            return usable(record.names["en"]) ?? record.name
        }

        private func usable(_ text: String?) -> String? {
            guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return text
        }

        private static func coordinateText(_ value: Double) -> String {
            if value == 0 { return "0" }
            return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
    }

    private struct Document: Codable {
        let schemaVersion: Int
        let countryCode: String
        let fetchedAt: Date
        let cities: [Record]
    }
    private struct Response: Decodable { let code: Int; let data: [Record] }

    let countryCode: String
    let entries: [Entry]
    private let byID: [String: Entry]
    private let searchNames: [[String]]
    private let englishTitles: [String: String]
    private let chineseTitles: [String: String]
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func isValidCountryCode(_ code: String) -> Bool {
        code.utf8.count == 2 && code.utf8.allSatisfy { (65...90).contains($0) }
    }

    init(response: [String: Any], countryCode: String) throws {
        let response = try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
        guard response.code == 200 else { throw CatalogError.invalidCatalog }
        try self.init(countryCode: countryCode, records: response.data)
    }

    init(data: Data, countryCode: String) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, document.countryCode == countryCode else { throw CatalogError.invalidCatalog }
        try self.init(countryCode: countryCode, records: document.cities)
    }

    private init(countryCode: String, records: [Record]) throws {
        guard Self.isValidCountryCode(countryCode), Set(records.map(\.id)).count == records.count else {
            throw CatalogError.invalidCatalog
        }
        for r in records {
            guard r.id > 0, !r.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !r.timezone.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  r.latitude.isFinite, r.longitude.isFinite,
                  (-90...90).contains(r.latitude), (-180...180).contains(r.longitude) else {
                throw CatalogError.invalidEntry
            }
        }
        self.countryCode = countryCode
        entries = records.map { Entry(countryCode: countryCode, record: $0) }.sorted {
            let a = Self.fold($0.displayName(language: "en")), b = Self.fold($1.displayName(language: "en"))
            return a == b ? $0.record.id < $1.record.id : a < b
        }
        byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        searchNames = entries.map { entry in
            Array(Set((Array(entry.record.names.values) + [entry.record.name]).map(Self.fold)))
        }
        englishTitles = Self.titles(entries, language: "en")
        chineseTitles = Self.titles(entries, language: "zh-Hans")
    }

    func cacheData(fetchedAt: Date) throws -> Data {
        try JSONEncoder().encode(Document(schemaVersion: 1, countryCode: countryCode,
                                         fetchedAt: fetchedAt, cities: entries.map(\.record)))
    }

    func entry(id: String) -> Entry? { byID[id] }

    func displayTitle(for entry: Entry, language: String) -> String {
        (language.lowercased().hasPrefix("zh") ? chineseTitles : englishTitles)[entry.id]
            ?? entry.displayName(language: language)
    }

    func entries(matching query: String) -> [Entry] {
        let query = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return entries }
        return entries.indices.compactMap { index in
            searchNames[index].contains(where: { $0.contains(query) }) ? entries[index] : nil
        }
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale).lowercased(with: locale)
    }

    private static func titles(_ entries: [Entry], language: String) -> [String: String] {
        var titles = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.displayName(language: language)) })
        for step in 0...1 {
            let groups = Dictionary(grouping: entries, by: { fold(titles[$0.id]!) })
            for group in groups.values where group.count > 1 {
                for entry in group {
                    titles[entry.id]! += step == 0
                        ? " (\(entry.latitudeText), \(entry.longitudeText))"
                        : " [\(entry.record.id)]"
                }
            }
        }
        return titles
    }
}

/// Each consumer cancels only its own search; the shared store owns snapshots and network requests.
final class CityCatalogLoader {
    private let queue = DispatchQueue(label: "com.sunricher.site-city-search", qos: .userInitiated)
    private var pending: DispatchWorkItem?
    private var generation: UInt64 = 0

    func search(catalog: CityCatalog, query: String, completion: @escaping ([CityCatalog.Entry]) -> Void) {
        cancel()
        let ticket = generation
        let work = DispatchWorkItem { [weak self] in
            let entries = catalog.entries(matching: query)
            DispatchQueue.main.async {
                guard let self, self.generation == ticket else { return }
                completion(entries)
            }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + (query.isEmpty ? 0 : 0.12), execute: work)
    }

    func cancel() { generation &+= 1; pending?.cancel(); pending = nil }
}
