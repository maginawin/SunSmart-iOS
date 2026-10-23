import Foundation

/// Offline, language-independent identities with explicitly versioned display names.
struct CountryRegionCatalog {
    enum CatalogError: Error { case resourceMissing, invalidCatalog, invalidEntry }

    struct Entry: Decodable, Equatable {
        let code: String
        let names: [String: String]

        private enum CodingKeys: String, CodingKey { case code, names }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            code = try container.decode(String.self, forKey: .code)
            names = try container.decode([String: String].self, forKey: .names)
            guard code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }),
                  let english = names["en"], !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.invalidEntry
            }
        }

        func displayName(language: String) -> String {
            if language.lowercased().hasPrefix("zh"), let chinese = names["zh-Hans"],
               !chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return chinese
            }
            return names["en"]!
        }
    }

    private struct Document: Decodable {
        let schemaVersion: Int
        let countries: [Entry]
    }

    let entries: [Entry]
    private let byCode: [String: Entry]
    private let searchNames: [String: [String]]
    private static let sortLocale = Locale(identifier: "en_US_POSIX")
    private static let bundledResult = Result { try load(bundle: .main) }

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, !document.countries.isEmpty,
              Set(document.countries.map(\.code)).count == document.countries.count else {
            throw CatalogError.invalidCatalog
        }
        entries = document.countries.sorted { lhs, rhs in
            let order = Self.fold(lhs.names["en"]!).compare(Self.fold(rhs.names["en"]!), locale: Self.sortLocale)
            return order == .orderedSame ? lhs.code < rhs.code : order == .orderedAscending
        }
        byCode = Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
        searchNames = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.code, [$0.names["en"], $0.names["zh-Hans"]].compactMap { $0 }.map(Self.fold))
        })
    }

    func entry(code: String) -> Entry? { byCode[code.uppercased()] }

    /// Unknown/legacy server strings remain visible and are never rewritten here.
    func displayName(forStoredCode code: String?, language: String) -> String? {
        guard let code else { return nil }
        return entry(code: code)?.displayName(language: language) ?? code
    }

    func entries(matching query: String) -> [Entry] {
        let query = Self.fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !query.isEmpty else { return entries }
        return entries.filter { entry in
            entry.code.lowercased() == query || searchNames[entry.code]!.contains { $0.contains(query) }
        }
    }

    static func bundled() throws -> Self { try bundledResult.get() }

    static func load(bundle: Bundle) throws -> Self {
        guard let url = bundle.url(forResource: "country_regions", withExtension: "json") else {
            throw CatalogError.resourceMissing
        }
        return try Self(data: Data(contentsOf: url))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: sortLocale)
            .lowercased(with: sortLocale)
    }
}
