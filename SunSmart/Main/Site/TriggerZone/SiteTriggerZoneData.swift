import Foundation

/// Preserve extension fields owned by later clients when editing an empty Site zone.
enum SiteJSONValue: Codable, Equatable {
    case object([String: SiteJSONValue]), array([SiteJSONValue]), string(String)
    case integer(Int64), number(Double), bool(Bool), null

    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer()
        if value.decodeNil() { self = .null }
        else if let item = try? value.decode(Bool.self) { self = .bool(item) }
        else if let item = try? value.decode(Int64.self) { self = .integer(item) }
        else if let item = try? value.decode(Double.self) { self = .number(item) }
        else if let item = try? value.decode(String.self) { self = .string(item) }
        else if let item = try? value.decode([SiteJSONValue].self) { self = .array(item) }
        else { self = .object(try value.decode([String: SiteJSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct SiteTriggerZone: Equatable {
    static let maximumCount = 100
    let zoneId: UUID
    var fields: [String: SiteJSONValue]

    init() {
        zoneId = UUID()
        fields = ["zoneId": .string(zoneId.uuidString), "members": .array([])]
    }

    init?(value: SiteJSONValue) {
        guard case .object(let fields) = value,
              case .string(let identifier) = fields["zoneId"],
              let identifier = UUID(uuidString: identifier),
              case .array = fields["members"] else { return nil }
        zoneId = identifier
        self.fields = fields
    }

    var isEmpty: Bool { fields["members"] == .array([]) }
}

struct SiteExtensionData: Codable, Equatable {
    enum ParseError: Error { case invalidObject }

    var fields: [String: SiteJSONValue]

    init() { fields = ["schemaVersion": .integer(1), "triggerZones": .array([])] }

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: SiteJSONValue].self)
        if fields["schemaVersion"] == nil { fields["schemaVersion"] = .integer(1) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(fields)
    }

    var zones: [SiteTriggerZone]? {
        guard let value = fields["triggerZones"] else { return [] }
        guard case .array(let values) = value else { return nil }
        let zones = values.compactMap(SiteTriggerZone.init(value:))
        guard zones.count == values.count,
              zones.count <= SiteTriggerZone.maximumCount,
              Set(zones.map(\.zoneId)).count == zones.count else { return nil }
        return zones
    }

    var supportsEmptyZoneEditing: Bool {
        guard fields["schemaVersion"] == nil || fields["schemaVersion"] == .integer(1),
              let zones else { return false }
        return zones.allSatisfy(\.isEmpty)
    }

    mutating func replaceZones(_ zones: [SiteTriggerZone]) {
        fields["triggerZones"] = .array(zones.map { .object($0.fields) })
    }

    func jsonObject() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
    }

    static func parse(_ value: Any) throws -> SiteExtensionData {
        let data: Data
        if let string = value as? String {
            // Site GET responses may carry a JSON object encoded inside a string.
            data = Data(string.utf8)
        } else {
            // Invalid top-level values raise NSException in JSONSerialization, not Swift Error.
            guard value is [String: Any], JSONSerialization.isValidJSONObject(value) else {
                throw ParseError.invalidObject
            }
            data = try JSONSerialization.data(withJSONObject: value)
        }
        return try JSONDecoder().decode(Self.self, from: data)
    }
}

struct SiteTriggerZonePending: Codable, Equatable {
    let operationId: UUID
    let timestamp: Int64
    let base: SiteExtensionData?
    let target: SiteExtensionData
}

struct SiteTriggerZoneState: Codable, Equatable {
    var data = SiteExtensionData()
    var serverData: SiteExtensionData?
    var serverTimestamp: Int64 = 0
    var pending: SiteTriggerZonePending?
    var submitted: SiteTriggerZonePending?
    var rejectedRemote: Data?
    var conflict = false

    mutating func commit(_ data: SiteExtensionData, now: Int64, siteTimestamp: Int64) {
        guard data != self.data else { return }
        let timestamp = max(now, max(siteTimestamp, max(serverTimestamp, pending?.timestamp ?? 0)) + 1)
        pending = .init(operationId: UUID(), timestamp: timestamp,
                        base: pending?.base ?? serverData, target: data)
        self.data = data
    }

    /// Missing fields are patches, never a deletion. A readback confirms only its own target.
    mutating func receive(_ remote: SiteExtensionData, timestamp: Int64) {
        guard timestamp >= serverTimestamp else { return }
        var remote = remote
        if remote.fields["triggerZones"] == nil {
            remote.fields["triggerZones"] = (serverData ?? data).fields["triggerZones"]
            // A response without the requested field cannot acknowledge a pending mutation.
            guard pending == nil else { return }
        }
        if let pending {
            if remote == pending.target && timestamp >= pending.timestamp {
                self.pending = nil
                submitted = nil
                data = remote
                conflict = false
            } else if let submitted, remote == submitted.target, timestamp >= submitted.timestamp,
               submitted.operationId != pending.operationId {
                self.pending = .init(operationId: pending.operationId,
                                     timestamp: max(pending.timestamp, timestamp + 1),
                                     base: remote, target: pending.target)
                self.submitted = nil
                conflict = false
            } else if let base = pending.base, remote != base {
                conflict = true
            }
        } else {
            data = remote
            conflict = false
        }
        serverData = remote
        serverTimestamp = timestamp
    }

    mutating func discardPending() {
        guard let serverData else { return }
        data = serverData
        pending = nil
        submitted = nil
        conflict = false
    }
}
