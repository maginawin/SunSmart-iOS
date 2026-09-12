import Foundation
import SQLite3

/// Only projects display/membership columns from existing databases. Opening either
/// connection cannot create a database, repair a network, or construct Mesh keys.
enum SiteTriggerZoneCandidateReader {
    struct Request {
        let siteID: String
        let meshUUID: String
        let subnetID: String
        let space: SiteTriggerZoneCandidates.Space
        let expectedGroupCount: Int
    }

    struct Source {
        let appPath: String
        let meshPath: String
        let eligibleProfileTypes: Set<Int>
        let excludedGroupAddresses: Set<UInt16>
    }

    enum ReadError: Error { case database, invalidData }

    static func load(_ requests: [Request], source: Source, devicesFor spaceID: String? = nil) -> [SiteTriggerZoneCandidates.Space] {
        // Restricted Spaces need only their already-authorized display summary.
        guard requests.contains(where: { $0.space.availability != .restricted }) else { return requests.map(\.space) }
        do {
            let app = try Database(path: source.appPath)
            let mesh = try Database(path: source.meshPath)
            let result = requests.map { request in
                guard request.space.availability != .restricted else { return request.space }
                var result = request.space
                do {
                    let access = try app.rows("SELECT permission, state, requiresPasswordVerification FROM spaces WHERE uuid = ? AND siteUUID = ? AND subNetworkKey = ?", [request.space.id, request.siteID, request.subnetID])
                    guard access.count == 1 else { throw ReadError.invalidData }
                    let role = try access[0][0].integer()
                    let state = try access[0][1].integer()
                    let requiresVerification = try access[0][2].integer()
                    if !(role == 1 || role == 2) || state != 1 || requiresVerification != 0 {
                        return .init(id: result.id, name: result.name,
                                     accessLabelKey: role == 3 ? "visitor" : "site_zones_access_unknown", availability: .restricted)
                    }
                    let groups = try loadGroups(request, source: source, app: app, mesh: mesh)
                    let eligible = groups.filter(\.eligible)
                    result.availability = eligible.isEmpty ? .noGroups : .ready
                    if result.isSelectable, request.space.id == spaceID {
                        result.devices = try loadDevices(request, groups: groups, mesh: mesh)
                        result.devicesLoaded = true
                    }
                } catch {
                    result.availability = .unavailable
                    result.devices = []
                    result.devicesLoaded = false
                }
                return result
            }
            // An import may commit while the two files are being read. Discard
            // that mixed projection instead of presenting partial candidates.
            try mesh.finishSnapshot()
            try app.finishSnapshot()
            return result
        } catch {
            return requests.map {
                var space = $0.space
                if space.availability != .restricted { space.availability = .unavailable }
                return space
            }
        }
    }

    private struct Group {
        let address: UInt16
        let eligible: Bool
    }

    private static func loadGroups(_ request: Request, source: Source, app: Database, mesh: Database) throws -> [Group] {
        let rows = try mesh.rows("SELECT groupAddress, isVirtual FROM groups WHERE meshUUID = ? AND subnetworkId = ? ORDER BY id", [request.meshUUID, request.subnetID])
        guard rows.count >= request.expectedGroupCount else { throw ReadError.invalidData }
        // A missing network is incomplete data, even when groups has zero rows.
        guard try mesh.rows("SELECT meshUUID FROM meshNetwork WHERE meshUUID = ?", [request.meshUUID]).count == 1 else { throw ReadError.invalidData }
        var groups: [Group] = []
        var seen = Set<UInt16>()
        for row in rows {
            let address = try row[0].address()
            guard seen.insert(address).inserted else { throw ReadError.invalidData }
            let isVirtual = try row[1].integer()
            guard isVirtual == 0 || isVirtual == 1 else { throw ReadError.invalidData }
            guard isVirtual == 0, (0xC000...0xFEFF).contains(address), !source.excludedGroupAddresses.contains(address) else { continue }
            let profiles = try app.rows("SELECT p.type FROM groupInfos g JOIN profiles p ON p.uuid = g.profileId AND p.meshUUID = g.meshUUID AND p.subNetworkKey = g.subNetworkKey WHERE g.meshUUID = ? AND g.subNetworkKey = ? AND g.groupAddress = ?", [request.meshUUID, request.subnetID, String(address)])
            guard profiles.count == 1 else { throw ReadError.invalidData }
            let type = try profiles[0][0].integer()
            guard (1...8).contains(type) else { throw ReadError.invalidData }
            groups.append(.init(address: address, eligible: source.eligibleProfileTypes.contains(type)))
        }
        return groups
    }

    private struct Provisioner: Decodable { let UUID: UUID }
    private struct Element: Decodable {
        let models: [Model]
        struct Model: Decodable { let subscribe: [String] }
    }

    private static func loadDevices(_ request: Request, groups: [Group], mesh: Database) throws -> [SiteTriggerZoneCandidates.Device] {
        let provisionerRows = try mesh.rows("SELECT provisioners FROM meshNetwork WHERE meshUUID = ?", [request.meshUUID])
        guard provisionerRows.count == 1 else { throw ReadError.invalidData }
        let provisioners = try JSONDecoder().decode([Provisioner].self, from: provisionerRows[0][0].data())
        let provisionerIDs = Set(provisioners.map(\.UUID))
        let rows = try mesh.rows("SELECT UUID, name, unicastAddress, elements FROM nodes WHERE meshUUID = ? AND subnetworkId = ? AND configComplete = 0 ORDER BY id", [request.meshUUID, request.subnetID])
        var devices: [SiteTriggerZoneCandidates.Device] = []
        var seenIDs = Set<UUID>()
        var seenAddresses = Set<UInt16>()
        for row in rows {
            guard let uuid = UUID(uuidString: try row[0].string()) else { throw ReadError.invalidData }
            if provisionerIDs.contains(uuid) { continue }
            let address = try row[2].address()
            guard (1...0x7FFF).contains(address), seenIDs.insert(uuid).inserted,
                  seenAddresses.insert(address).inserted else { throw ReadError.invalidData }
            let elements = try JSONDecoder().decode([Element].self, from: row[3].data())
            var group: Group?
            // Same element/model order and business-Group rule as Node.group.
            // Do not expand membership to every subscription on every model.
            outer: for element in elements {
                for model in element.models {
                    let addresses = try Set(model.subscribe.map { value -> UInt16 in
                        guard value.count == 4 || value.count == 32 else { throw ReadError.invalidData }
                        if value.count == 32 { return 0 } // virtual subscription
                        guard let address = UInt16(value, radix: 16) else { throw ReadError.invalidData }
                        return address
                    })
                    let matches = groups.filter { addresses.contains($0.address) }
                    guard matches.count <= 1 else { throw ReadError.invalidData }
                    if let match = matches.first { group = match; break outer }
                }
            }
            guard let group, group.eligible else { continue }
            let name = row[1] == .null ? "" : try row[1].string()
            devices.append(.init(identity: .init(siteID: request.siteID, spaceID: request.space.id, deviceID: uuid.uuidString),
                                 name: name.isEmpty ? String(format: "%04X", address) : name,
                                 address: address, groupAddress: group.address))
        }
        return devices
    }

    private enum Value: Equatable {
        case text(String), number(Int), blob(Data), null
        func string() throws -> String { guard case .text(let value) = self else { throw ReadError.invalidData }; return value }
        func integer() throws -> Int { guard case .number(let value) = self else { throw ReadError.invalidData }; return value }
        func data() throws -> Data { guard case .blob(let value) = self else { throw ReadError.invalidData }; return value }
        func address() throws -> UInt16 {
            guard let value = UInt16(exactly: try integer()) else { throw ReadError.invalidData }
            return value
        }
    }

    private final class Database {
        private var handle: OpaquePointer?
        private var version: [[Value]] = []
        init(path: String) throws {
            guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
                sqlite3_close(handle)
                handle = nil
                throw ReadError.database
            }
            sqlite3_busy_timeout(handle, 200)
            // Keep each file's reads on one snapshot until this short-lived reader closes.
            guard sqlite3_exec(handle, "BEGIN DEFERRED", nil, nil, nil) == SQLITE_OK else { throw ReadError.database }
            version = try rows("PRAGMA data_version", [])
        }
        deinit { sqlite3_close(handle) }

        func finishSnapshot() throws {
            guard sqlite3_exec(handle, "COMMIT", nil, nil, nil) == SQLITE_OK,
                  try rows("PRAGMA data_version", []) == version else { throw ReadError.database }
        }

        func rows(_ sql: String, _ bindings: [String]) throws -> [[Value]] {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { throw ReadError.database }
            defer { sqlite3_finalize(statement) }
            for (index, value) in bindings.enumerated() {
                let result = value.withCString { sqlite3_bind_text(statement, Int32(index + 1), $0, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
                guard result == SQLITE_OK else { throw ReadError.database }
            }
            var rows: [[Value]] = []
            while true {
                let result = sqlite3_step(statement)
                if result == SQLITE_DONE { return rows }
                guard result == SQLITE_ROW else { throw ReadError.database }
                var row: [Value] = []
                for column in 0..<sqlite3_column_count(statement) {
                    switch sqlite3_column_type(statement, column) {
                    case SQLITE_INTEGER: row.append(.number(Int(sqlite3_column_int64(statement, column))))
                    case SQLITE_TEXT:
                        guard let text = sqlite3_column_text(statement, column) else { throw ReadError.invalidData }
                        row.append(.text(String(cString: text)))
                    case SQLITE_BLOB:
                        let count = Int(sqlite3_column_bytes(statement, column))
                        guard let bytes = sqlite3_column_blob(statement, column), count > 0 else { throw ReadError.invalidData }
                        row.append(.blob(Data(bytes: bytes, count: count)))
                    case SQLITE_NULL: row.append(.null)
                    default: throw ReadError.invalidData
                    }
                }
                rows.append(row)
            }
        }
    }
}
