import Foundation
import SQLite

/// A separate table prevents legacy Site insert-or-replace saves from overwriting zones.
enum SiteTriggerZoneStore {
    private static let table = Table("site_extensions")
    private static let siteID = Expression<String>("siteId")
    private static let regionID = Expression<Int>("region")
    private static let payload = Expression<Data>("payload")

    enum StoreError: Error { case databaseUnavailable }

    static func createTable() throws {
        guard let db = SunSmartDataManager.shared.db else { throw StoreError.databaseUnavailable }
        try db.run(table.create(ifNotExists: true) { builder in
            builder.column(siteID)
            builder.column(regionID)
            builder.column(payload)
            builder.primaryKey(siteID, regionID)
        })
    }

    static func load(_ site: SiteData) throws -> SiteTriggerZoneState {
        guard let db = SunSmartDataManager.shared.db else { throw StoreError.databaseUnavailable }
        if let row = try db.pluck(table.filter(siteID == site.id && regionID == site.region.rawValue)) {
            return try JSONDecoder().decode(SiteTriggerZoneState.self, from: row[payload])
        }
        var state = SiteTriggerZoneState()
        state.data = site.siteExtensionData
        return state
    }

    @discardableResult
    static func update(_ site: SiteData, _ mutation: (inout SiteTriggerZoneState) throws -> Void) throws -> SiteTriggerZoneState {
        guard let db = SunSmartDataManager.shared.db else { throw StoreError.databaseUnavailable }
        var state = SiteTriggerZoneState()
        try db.savepoint("site_extension_" + UUID().uuidString) {
            state = try load(site)
            try mutation(&state)
            let encoded = try JSONEncoder().encode(state)
            try db.run(table.insert(or: .replace, siteID <- site.id,
                                   regionID <- site.region.rawValue, payload <- encoded))
        }
        site.siteExtensionData = state.data
        return state
    }

    static func bootstrap(_ site: SiteData) throws {
        guard let db = SunSmartDataManager.shared.db else { throw StoreError.databaseUnavailable }
        guard try db.pluck(table.filter(siteID == site.id && regionID == site.region.rawValue)) == nil else { return }
        try update(site) { _ in }
    }

    static func delete(_ site: SiteData) throws {
        guard let db = SunSmartDataManager.shared.db else { throw StoreError.databaseUnavailable }
        try db.run(table.filter(siteID == site.id && regionID == site.region.rawValue).delete())
    }

    /// A missing extension is an old/partial response; it must not erase local data.
    static func receive(_ site: SiteData, object: [String: Any], timestamp: Int64) throws {
        guard let value = object["extensionData"] else { return }
        let remote: SiteExtensionData
        do {
            remote = try SiteExtensionData.parse(value)
            guard remote.zones != nil else { throw SiteExtensionData.ParseError.invalidObject }
        }
        catch {
            // Validate fragments too before preserving a rejected payload; serialization
            // of a non-JSON Foundation value would otherwise raise an uncaught NSException.
            guard JSONSerialization.isValidJSONObject([value]) else { throw error }
            let raw = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
            try update(site) {
                guard timestamp >= $0.serverTimestamp else { return }
                $0.rejectedRemote = raw
            }
            throw error
        }
        try update(site) {
            guard timestamp >= $0.serverTimestamp else { return }
            $0.rejectedRemote = nil
            $0.receive(remote, timestamp: timestamp)
        }
    }
}
