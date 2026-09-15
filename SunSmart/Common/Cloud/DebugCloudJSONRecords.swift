#if DEBUG
import Foundation
import SQLite
import NordicSigMeshSDK

/// Reads persisted configuration without decoding it into models (which may drop
/// invalid fields). Every query is scoped; account credentials are never selected.
enum DebugCloudJSONRecords {
    struct Scope {
        let siteID: String
        let spaceID: String
        let meshUUID: String
        let networkID: String
    }

    static func space(_ space: SpaceData) throws -> [String: Any] {
        guard let app = SunSmartDataManager.shared.db,
              let path = MeshDataManager.customDatabasePath else { throw CocoaError(.fileReadUnknown) }
        let mesh = try Connection(path, readonly: true)
        mesh.busyTimeout = 1.5
        var result = try read(app: app, mesh: mesh, scope: .init(siteID: space.siteId,
            spaceID: space.id, meshUUID: space.meshUUID, networkID: space.meshNetworkId))
        // These keys remain available even when group/zone decoding prevents
        // model payload assembly. Never include keys for sibling Spaces.
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let network = MeshNetwork.load(meshUUID: space.meshUUID, allData: false),
           let key = network.networkKeys.first(where: { $0.networkId.hex == space.meshNetworkId }) {
            var keys: [String: Any] = ["netKey": try JSONSerialization.jsonObject(with: encoder.encode(key))]
            if let appKey = network.applicationKeys.first(where: { $0.boundNetworkKeyIndex == key.index }) {
                keys["appKey"] = try JSONSerialization.jsonObject(with: encoder.encode(appKey))
            }
            result["networkConfiguration"] = keys
        } else {
            result["networkConfigurationUnavailable"] = true
        }
        return result
    }

    static func site(_ site: SiteData) throws -> [String: Any] {
        guard let db = SunSmartDataManager.shared.db else { throw CocoaError(.fileReadUnknown) }
        var result: [String: Any] = [
            "sites": try rows(db, table: "sites", predicate: "uuid = ? AND regionType = ?",
                              bindings: [site.id, Int64(site.region.rawValue)]),
            "site_extensions": try rows(db, table: "site_extensions", predicate: "siteId = ? AND region = ?",
                                        bindings: [site.id, Int64(site.region.rawValue)])
        ]
        guard let path = MeshDataManager.customDatabasePath else { throw CocoaError(.fileReadUnknown) }
        let mesh = try Connection(path, readonly: true)
        result["meshNetwork"] = try rows(mesh, table: "meshNetwork", predicate: "meshUUID = ?", bindings: [site.meshUUID])
        result["exclusions"] = try rows(mesh, table: "exclusions", predicate: "meshUUID = ?", bindings: [site.meshUUID])
        return result
    }

    static func read(app: Connection, mesh: Connection, scope: Scope) throws -> [String: Any] {
        var appRows: [String: Any] = [:]
        var meshRows: [String: Any] = [:]
        // A read transaction pins each database. The caller also checks the
        // cross-database revision before accepting the whole captured payload.
        try mesh.transaction(.deferred) {
            for table in ["nodes", "nodePropertys", "groups", "scenes"] {
                meshRows[table] = try rows(mesh, table: table,
                    predicate: "meshUUID = ? AND subnetworkId = ?", bindings: [scope.meshUUID, scope.networkID])
            }
        }
        try app.savepoint {
            appRows["spaces"] = try rows(app, table: "spaces", predicate: "uuid = ? AND siteUUID = ?",
                                         bindings: [scope.spaceID, scope.siteID])
            for table in ["groupInfos", "sceneInfos", "schedules", "profiles", "switchs",
                          "emergencyFireControllers", "pjEightKeySwitchs"] {
                // Unscoped legacy profiles are read only when referenced by this Space.
                let predicate = table == "profiles"
                    ? "meshUUID = ? AND (subNetworkKey = ? OR ((subNetworkKey IS NULL OR subNetworkKey = '') AND uuid IN (SELECT profileId FROM groupInfos WHERE meshUUID = ? AND subNetworkKey = ?)))"
                    : "meshUUID = ? AND subNetworkKey = ?"
                let bindings: [Binding?] = table == "profiles"
                    ? [scope.meshUUID, scope.networkID, scope.meshUUID, scope.networkID]
                    : [scope.meshUUID, scope.networkID]
                appRows[table] = try rows(app, table: table, predicate: predicate, bindings: bindings)
            }
            let profiles = (appRows["profiles"] as? [[String: Any]] ?? []).compactMap { $0["uuid"] as? String }
            appRows["profileLightSensorTemplate"] = try rows(app, table: "profileLightSensorTemplate",
                predicate: "profileId IN (\(placeholders(profiles.count)))", bindings: profiles.map { $0 as Binding? })
            let nodes = (meshRows["nodes"] as? [[String: Any]] ?? []).compactMap { $0["unicastAddress"] as? Int64 }
            appRows["node_preConfiguration"] = try rows(app, table: "node_preConfiguration",
                predicate: "meshUUID = ? AND nodeAddress IN (\(placeholders(nodes.count)))",
                bindings: [scope.meshUUID] + nodes.map { $0 as Binding? })
        }
        return ["app": appRows, "mesh": meshRows]
    }

    private static func placeholders(_ count: Int) -> String {
        count == 0 ? "NULL" : Array(repeating: "?", count: count).joined(separator: ",")
    }

    private static let excludedColumns: Set<String> = [
        "editorPassword", "vistorPassword", "authorizationPassword", "transferPassword",
        "transferCode", "shareCode", "editor", "vistors"
    ]

    static func rows(_ db: Connection, table: String, predicate: String,
                     bindings: [Binding?]) throws -> [[String: Any]] {
        // Optional tables did not exist in older app versions. A failed SELECT
        // on an existing table must throw, never masquerade as an empty table.
        guard try db.scalar("SELECT count(*) FROM sqlite_master WHERE type = 'table' AND name = ?", table) as? Int64 == 1 else {
            return []
        }
        let columns = try db.schema.columnDefinitions(table: table).map(\.name).filter { !excludedColumns.contains($0) }
        func quoted(_ name: String) -> String { "\"" + name.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let statement = try db.prepare("SELECT \(columns.map(quoted).joined(separator: ",")) FROM \(quoted(table)) WHERE \(predicate)", bindings)
        var result: [[String: Any]] = []
        while let values = try statement.failableNext() {
            var row: [String: Any] = [:]
            for (column, value) in zip(statement.columnNames, values) {
                if let blob = value as? Blob {
                    row[column] = blobValue(Data(blob.bytes))
                } else if let number = value as? Double, !number.isFinite {
                    row[column] = ["sqliteType": "real", "value": String(number)]
                } else if let value {
                    row[column] = value
                } else {
                    row[column] = NSNull()
                }
            }
            result.append(row)
        }
        return result
    }

    static func blobValue(_ data: Data) -> [String: Any] {
        var value: [String: Any] = ["sqliteType": "blob", "base64": data.base64EncodedString()]
        if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
            value["json"] = json
        } else if let text = String(data: data, encoding: .utf8) {
            value["utf8"] = text
        }
        return value
    }
}
#endif
