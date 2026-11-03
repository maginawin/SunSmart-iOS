import Foundation

/// Validated server identities and names, also used for the last successful disk snapshot.
struct CountryRegionCatalog {
    enum CatalogError: Error { case invalidCatalog, invalidEntry }

    struct Entry: Codable, Equatable {
        let code: String
        let names: [String: String]
        let aliases: [String]

        private enum CodingKeys: String, CodingKey { case code, names, aliases }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            try self.init(code: container.decode(String.self, forKey: .code),
                          names: container.decode([String: String].self, forKey: .names),
                          aliases: container.decodeIfPresent([String].self, forKey: .aliases) ?? [])
        }

        fileprivate init(code: String, names: [String: String], aliases: [String] = []) throws {
            guard code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }),
                  let english = names["en"], !english.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw CatalogError.invalidEntry
            }
            self.code = code
            self.names = names
            self.aliases = aliases
        }

        func displayName(language: String) -> String {
            if language.lowercased().hasPrefix("zh"), let chinese = names["zh-Hans"],
               !chinese.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return chinese
            }
            return names["en"]!
        }
    }

    private struct Document: Codable {
        let schemaVersion: Int
        let countries: [Entry]
        let fetchedAt: Date?
    }

    private struct Response: Decodable {
        struct Country: Decodable {
            let code: String
            let name: String?
            let names_json: [String: String]?
        }
        let code: Int
        let data: [Country]
    }

    let entries: [Entry]
    private let byCode: [String: Entry]
    private let searchNames: [String: [String]]
    private static let sortLocale = Locale(identifier: "en_US_POSIX")

    init(data: Data) throws {
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1 else { throw CatalogError.invalidCatalog }
        try self.init(entries: document.countries)
    }

    init(response: [String: Any]) throws {
        let document = try JSONDecoder().decode(Response.self, from: JSONSerialization.data(withJSONObject: response))
        guard document.code == 200 else { throw CatalogError.invalidCatalog }
        try self.init(entries: document.data.map { country in
            var names = country.names_json ?? [:]
            if names["en"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                names["en"] = country.name
            }
            return try Entry(code: country.code, names: names, aliases: country.name.map { [$0] } ?? [])
        })
    }

    private init(entries countries: [Entry]) throws {
        guard !countries.isEmpty, Set(countries.map(\.code)).count == countries.count else {
            throw CatalogError.invalidCatalog
        }
        entries = countries.sorted { lhs, rhs in
            let order = Self.fold(lhs.names["en"]!).compare(Self.fold(rhs.names["en"]!), locale: Self.sortLocale)
            return order == .orderedSame ? lhs.code < rhs.code : order == .orderedAscending
        }
        byCode = Dictionary(uniqueKeysWithValues: entries.map { ($0.code, $0) })
        searchNames = Dictionary(uniqueKeysWithValues: entries.map {
            ($0.code, ([$0.names["en"], $0.names["zh-Hans"]].compactMap { $0 } + $0.aliases).map(Self.fold))
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

    func cacheData(fetchedAt: Date) throws -> Data {
        try JSONEncoder().encode(Document(schemaVersion: 1, countries: entries, fetchedAt: fetchedAt))
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: sortLocale)
            .lowercased(with: sortLocale)
    }
}
