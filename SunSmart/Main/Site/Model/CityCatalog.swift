import Foundation
import CryptoKit

/// One country's immutable offline catalog. Decoding/indexing happens on CityCatalogLoader's queue.
struct CityCatalog {
    enum CatalogError: Error { case resourceMissing, invalidCatalog, invalidEntry }

    struct Record: Decodable {
        let id: Int
        let names: [String: String]
        let aliases: [String]
        let admin1: String
        let admin2: String
        let timezone: String
        let latitude: Double
        let longitude: Double
    }

    struct Entry {
        let countryCode: String
        let record: Record
        var id: String { "geonames:\(record.id)" }
        var timezoneIdentifier: String { record.timezone }
        var latitudeText: String { Self.coordinateText(record.latitude) }
        var longitudeText: String { Self.coordinateText(record.longitude) }

        func displayName(language: String) -> String { CityCatalog.name(record.names, language: language) }

        private static func coordinateText(_ value: Double) -> String {
            if value == 0 { return "0" }
            return String(format: "%.6f", locale: Locale(identifier: "en_US_POSIX"), value)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let countryCode: String
        let administrativeAreas: [String: [String: String]]
        let cities: [Record]
    }

    struct Manifest: Decodable {
        struct Country: Decodable { let count: Int; let bytes: Int; let sha256: String }
        let schemaVersion: Int
        let countries: [String: Country]
    }

    let countryCode: String
    let entries: [Entry]
    private let byID: [String: Entry]
    private let searchNames: [[String]]
    private let englishTitles: [String: String]
    private let chineseTitles: [String: String]
    private static let locale = Locale(identifier: "en_US_POSIX")

    init(data: Data, countryCode: String) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, document.countryCode == countryCode,
              countryCode.utf8.count == 2, countryCode.utf8.allSatisfy({ (65...90).contains($0) }),
              Set(document.cities.map(\.id)).count == document.cities.count else {
            throw CatalogError.invalidCatalog
        }
        for record in document.cities {
            guard record.id > 0, !(record.names["en"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  !record.timezone.isEmpty, record.latitude.isFinite, record.longitude.isFinite,
                  (-90...90).contains(record.latitude), (-180...180).contains(record.longitude),
                  record.admin1.isEmpty || document.administrativeAreas[record.admin1] != nil,
                  record.admin2.isEmpty || document.administrativeAreas[record.admin2] != nil else {
                throw CatalogError.invalidEntry
            }
        }
        self.countryCode = countryCode
        entries = document.cities.map { Entry(countryCode: countryCode, record: $0) }.sorted {
            let a = Self.fold($0.record.names["en"]!), b = Self.fold($1.record.names["en"]!)
            if a != b { return a < b }
            if $0.record.admin1 != $1.record.admin1 { return $0.record.admin1 < $1.record.admin1 }
            if $0.record.admin2 != $1.record.admin2 { return $0.record.admin2 < $1.record.admin2 }
            return $0.record.id < $1.record.id
        }
        byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        searchNames = entries.map { entry in
            Array(Set((Array(entry.record.names.values) + entry.record.aliases).map(Self.fold)))
        }
        englishTitles = Self.titles(entries, areas: document.administrativeAreas, language: "en")
        chineseTitles = Self.titles(entries, areas: document.administrativeAreas, language: "zh-Hans")
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

    static func load(countryCode: String, root: URL) throws -> Self {
        // Never turn a legacy/free-text country value into a file-system path.
        guard countryCode.utf8.count == 2, countryCode.utf8.allSatisfy({ (65...90).contains($0) }) else {
            throw CatalogError.invalidCatalog
        }
        let manifestURL = root.appendingPathComponent("manifest.json")
        let file = root.appendingPathComponent("countries/\(countryCode).json")
        guard FileManager.default.fileExists(atPath: manifestURL.path), FileManager.default.fileExists(atPath: file.path) else {
            throw CatalogError.resourceMissing
        }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion == 1, let expected = manifest.countries[countryCode], expected.count >= 0 else {
            throw CatalogError.invalidCatalog
        }
        let data = try Data(contentsOf: file)
        guard data.count == expected.bytes,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == expected.sha256 else {
            throw CatalogError.invalidCatalog
        }
        let catalog = try Self(data: data, countryCode: countryCode)
        guard catalog.entries.count == expected.count else { throw CatalogError.invalidCatalog }
        return catalog
    }

    private static func name(_ names: [String: String], language: String) -> String {
        if language.lowercased().hasPrefix("zh"), let chinese = names["zh-Hans"], !chinese.isEmpty { return chinese }
        return names["en"] ?? ""
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: locale).lowercased(with: locale)
    }

    private static func titles(_ entries: [Entry], areas: [String: [String: String]], language: String) -> [String: String] {
        var titles = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0.displayName(language: language)) })
        for level in 0...2 {
            let groups = Dictionary(grouping: entries, by: { fold(titles[$0.id]!) })
            for group in groups.values where group.count > 1 {
                for entry in group {
                    if level < 2 {
                        let key = level == 0 ? entry.record.admin1 : entry.record.admin2
                        if let area = areas[key] {
                            let text = name(area, language: language)
                            if !text.isEmpty { titles[entry.id]! += ", " + text }
                        }
                    } else {
                        titles[entry.id]! += " (\(entry.latitudeText), \(entry.longitudeText))"
                    }
                }
            }
        }
        return titles
    }
}

/// Queue-confined two-country cache; callers invalidate UI tickets independently of disk work.
final class CityCatalogLoader {
    private let queue = DispatchQueue(label: "com.sunricher.site-city-catalog", qos: .userInitiated)
    private let readCatalog: (String) throws -> CityCatalog
    private var cache: [CityCatalog] = []
    private var pending: DispatchWorkItem?

    init(root: URL? = Bundle.main.url(forResource: "CityCatalog", withExtension: nil)) {
        readCatalog = { country in
            guard let root else { throw CityCatalog.CatalogError.resourceMissing }
            return try CityCatalog.load(countryCode: country, root: root)
        }
    }

    init(readCatalog: @escaping (String) throws -> CityCatalog) { self.readCatalog = readCatalog }

    // Called on main. Completion is always delivered on main, including resource errors.
    func search(countryCode: String, query: String, completion: @escaping (Result<(CityCatalog, [CityCatalog.Entry]), Error>) -> Void) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let result = Result { () throws -> (CityCatalog, [CityCatalog.Entry]) in
                let catalog: CityCatalog
                if let index = self.cache.firstIndex(where: { $0.countryCode == countryCode }) {
                    catalog = self.cache.remove(at: index)
                } else {
                    catalog = try self.readCatalog(countryCode)
                }
                self.cache.insert(catalog, at: 0)
                if self.cache.count > 2 { self.cache.removeLast() }
                return (catalog, catalog.entries(matching: query))
            }
            DispatchQueue.main.async { completion(result) }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + (query.isEmpty ? 0 : 0.12), execute: work)
    }

    func cancel() { pending?.cancel(); pending = nil }
}
