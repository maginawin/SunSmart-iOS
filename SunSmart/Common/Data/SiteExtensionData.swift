import Foundation

/// Preserve unknown fields when reading or updating Site extensionData.
enum SiteJSONValue: Codable, Equatable, Sendable {
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

/// Complete Site extensionData shared by Site type, Trigger Zones and cloud payloads.
struct SiteExtensionData: Codable, Equatable {
    enum ParseError: Error { case invalidObject }
    enum ProjectType: String, Codable {
        case standard = "Standard"
        case hdb = "HDB"
    }

    var fields: [String: SiteJSONValue]

    init() { fields = ["schemaVersion": .integer(1), "triggerZones": .array([]), "siteType": .null] }

    /// Missing/null/invalid values are legacy Standard Sites, never an inferred HDB type.
    /// Parsing preserves field presence until partial responses have been merged.
    var siteType: ProjectType? {
        get {
            guard case .string(let value) = fields["siteType"] else { return nil }
            return ProjectType(rawValue: value)
        }
        set { fields["siteType"] = newValue.map { .string($0.rawValue) } ?? .null }
    }

    var isHdbSite: Bool { siteType == .hdb }

    private var encodedFields: [String: SiteJSONValue] {
        var result = fields
        result.removeValue(forKey: "isHdbSite")
        result["siteType"] = siteType.map { .string($0.rawValue) } ?? .null
        return result
    }

    private var normalizedFields: [String: SiteJSONValue] {
        var result = encodedFields
        result["siteType"] = .string((siteType ?? .standard).rawValue)
        return result
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.normalizedFields == rhs.normalizedFields
    }

    init(from decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode([String: SiteJSONValue].self)
        fields.removeValue(forKey: "isHdbSite")
        if fields["schemaVersion"] == nil { fields["schemaVersion"] = .integer(1) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(encodedFields)
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

    var supportsMemberEditing: Bool {
        guard let zones else { return false }
        switch fields["schemaVersion"] {
        case .integer(1), nil: return zones.allSatisfy(\.isEmpty)
        case .integer(2): return zones.allSatisfy { $0.members != nil }
        default: return false
        }
    }

    /// A row update may preserve other Zones verbatim while editing one valid Zone.
    func supportsZoneEditing(_ id: UUID) -> Bool {
        guard let zones, let zone = zones.first(where: { $0.zoneId == id }),
              zone.members != nil else { return false }
        switch fields["schemaVersion"] {
        case .integer(1), nil: return zones.allSatisfy(\.isEmpty)
        case .integer(2): return true
        default: return false
        }
    }

    mutating func replaceZones(_ zones: [SiteTriggerZone]) {
        fields["triggerZones"] = .array(zones.map { .object($0.fields) })
    }

    /// Build the complete extension object for a row Save while retaining server-owned fields.
    func replacingZone(_ zone: SiteTriggerZone) -> Self? {
        guard var zones else { return nil }
        if let index = zones.firstIndex(where: { $0.zoneId == zone.zoneId }) {
            zones[index] = zone
        } else {
            guard zones.count < SiteTriggerZone.maximumCount else { return nil }
            zones.append(zone)
        }
        var result = self
        result.replaceZones(zones)
        if !zone.isEmpty { result.fields["schemaVersion"] = .integer(2) }
        return result.supportsZoneEditing(zone.zoneId) ? result : nil
    }

    /// Rebase only when the local target already contains every server change
    /// since its base. Unknown fields and whole Zone objects must match exactly.
    static func targetCoversServerChanges(base: Self, server: Self, target: Self) -> Bool {
        guard base.supportsMemberEditing, server.supportsMemberEditing,
              target.supportsMemberEditing,
              let baseZones = base.zones, let serverZones = server.zones,
              let targetZones = target.zones else { return false }
        let baseFields = base.normalizedFields, serverFields = server.normalizedFields
        let targetFields = target.normalizedFields
        let fieldNames = Set(baseFields.keys).union(serverFields.keys)
        for name in fieldNames where name != "triggerZones" {
            if baseFields[name] != serverFields[name],
               targetFields[name] != serverFields[name] { return false }
        }
        let baseByID = Dictionary(uniqueKeysWithValues: baseZones.map { ($0.zoneId, $0) })
        let serverByID = Dictionary(uniqueKeysWithValues: serverZones.map { ($0.zoneId, $0) })
        let targetByID = Dictionary(uniqueKeysWithValues: targetZones.map { ($0.zoneId, $0) })
        for id in Set(baseByID.keys).union(serverByID.keys) {
            if baseByID[id] != serverByID[id], targetByID[id] != serverByID[id] { return false }
        }
        let serverIDs = serverZones.map(\.zoneId)
        let targetIDs = targetZones.map(\.zoneId)
        return targetIDs.filter { serverByID[$0] != nil } == serverIDs
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

enum SiteExtensionUpdatePayload {
    static func props(extensionData: SiteExtensionData) throws -> [String: Any] {
        ["extensionData": try extensionData.jsonObject()]
    }
}
