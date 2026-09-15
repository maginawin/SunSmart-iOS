import Foundation

/// Preserve extension fields owned by later clients when editing a Site zone.
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

struct SiteTriggerZoneMember: Equatable, Sendable {
    struct Identity: Hashable, Sendable {
        let spaceID: String
        let nodeUUID: UUID
    }

    let identity: Identity
    var fields: [String: SiteJSONValue]

    init(identity: Identity, groupAddress: UInt16, primaryAddress: UInt16, deviceAddress: UInt16) {
        self.identity = identity
        fields = [
            "spaceId": .string(identity.spaceID),
            "nodeUUID": .string(identity.nodeUUID.uuidString),
            "groupAddress": .integer(Int64(groupAddress)),
            "primaryAddress": .integer(Int64(primaryAddress)),
            "deviceAddress": .integer(Int64(deviceAddress))
        ]
    }

    init?(value: SiteJSONValue) {
        guard case .object(let fields) = value,
              case .string(let spaceID) = fields["spaceId"], !spaceID.isEmpty,
              case .string(let nodeID) = fields["nodeUUID"], let nodeUUID = UUID(uuidString: nodeID),
              case .integer(let group) = fields["groupAddress"], (0xC000...0xFEFF).contains(group),
              case .integer(let primary) = fields["primaryAddress"], (1...0x7FFF).contains(primary),
              case .integer(let device) = fields["deviceAddress"], (primary...0x7FFF).contains(device)
        else { return nil }
        identity = .init(spaceID: spaceID, nodeUUID: nodeUUID)
        self.fields = fields
    }

    var groupAddress: UInt16? {
        guard case .integer(let value) = fields["groupAddress"] else { return nil }
        return UInt16(exactly: value)
    }

    var primaryAddress: UInt16? {
        guard case .integer(let value) = fields["primaryAddress"] else { return nil }
        return UInt16(exactly: value)
    }

    var deviceAddress: UInt16? {
        guard case .integer(let value) = fields["deviceAddress"] else { return nil }
        return UInt16(exactly: value)
    }
}

/// A member can be shown by stable identity even when an older payload has no
/// normalized deviceAddress. This projection is never used for device writes.
struct SiteTriggerZoneDisplayMember {
    let identity: SiteTriggerZoneMember.Identity
    let primaryAddress: UInt16?

    init?(value: SiteJSONValue) {
        guard case .object(let fields) = value,
              case .string(let spaceID) = fields["spaceId"], !spaceID.isEmpty,
              case .string(let nodeID) = fields["nodeUUID"],
              let nodeUUID = UUID(uuidString: nodeID) else { return nil }
        identity = .init(spaceID: spaceID, nodeUUID: nodeUUID)
        if case .integer(let address) = fields["primaryAddress"] {
            primaryAddress = UInt16(exactly: address)
        } else {
            primaryAddress = nil
        }
    }

    init(_ member: SiteTriggerZoneMember) {
        identity = member.identity
        primaryAddress = member.primaryAddress
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

    var members: [SiteTriggerZoneMember]? {
        guard case .array(let values) = fields["members"] else { return nil }
        let members = values.compactMap(SiteTriggerZoneMember.init(value:))
        guard members.count == values.count,
              Set(members.map(\.identity)).count == members.count else { return nil }
        return members
    }

    var displayMembers: [SiteTriggerZoneDisplayMember] {
        guard case .array(let values) = fields["members"] else { return [] }
        return values.compactMap(SiteTriggerZoneDisplayMember.init(value:))
    }

    var hasCompleteDisplayMembers: Bool {
        guard case .array(let values) = fields["members"] else { return false }
        let members = displayMembers
        return members.count == values.count
            && Set(members.map(\.identity)).count == members.count
    }

    mutating func replaceMembers(_ members: [SiteTriggerZoneMember]) {
        fields["members"] = .array(members.map { .object($0.fields) })
    }
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
        let fieldNames = Set(base.fields.keys).union(server.fields.keys)
        for name in fieldNames where name != "triggerZones" {
            if base.fields[name] != server.fields[name],
               target.fields[name] != server.fields[name] { return false }
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

enum SiteTriggerZoneUpdatePayload {
    static func props(extensionData: SiteExtensionData) throws -> [String: Any] {
        ["extensionData": try extensionData.jsonObject()]
    }
}

/// Page-scoped member edits. They are not part of extensionData until Save.
struct SiteTriggerZoneDraft: Equatable {
    let zoneID: UUID
    private(set) var base: [SiteTriggerZoneMember]
    private(set) var members: [SiteTriggerZoneMember]

    init?(zone: SiteTriggerZone) {
        guard let members = zone.members else { return nil }
        self.init(zoneID: zone.zoneId, members: members)
    }

    init(zoneID: UUID, members: [SiteTriggerZoneMember]) {
        self.zoneID = zoneID
        base = members
        self.members = members
    }

    var isDirty: Bool { members != base }

    @discardableResult
    mutating func add(_ member: SiteTriggerZoneMember) -> Bool {
        guard !members.contains(where: { $0.identity == member.identity }) else { return false }
        members.append(member)
        return true
    }

    @discardableResult
    mutating func remove(_ identity: SiteTriggerZoneMember.Identity) -> Bool {
        guard let index = members.firstIndex(where: { $0.identity == identity }) else { return false }
        members.remove(at: index)
        return true
    }

    mutating func reset() { members = base }
}

struct SiteTriggerZonePending: Codable, Equatable {
    let operationId: UUID
    /// Local ordering token only. The Site props endpoint assigns its own updateTimestamp.
    let timestamp: Int64
    let base: SiteExtensionData?
    let target: SiteExtensionData
}

struct SiteTriggerZoneDeviceSyncChange: Codable, Equatable {
    let zoneID: UUID
    let previousMembers: SiteJSONValue
    let targetMembers: SiteJSONValue

    struct KnownMemberImpact: Equatable {
        let added: Int
        let removed: Int
        let changed: Int
        var hasDelta: Bool { added > 0 || removed > 0 || changed > 0 }
    }

    /// Counts only this Zone's known membership difference. Shared device work
    /// and physical state require the complete Site topology and device evidence.
    var knownMemberImpact: KnownMemberImpact? {
        guard let previous = Self.relevantMembers(previousMembers),
              let target = Self.relevantMembers(targetMembers) else { return nil }
        let previousIDs = Set(previous.keys)
        let targetIDs = Set(target.keys)
        return .init(added: targetIDs.subtracting(previousIDs).count,
                     removed: previousIDs.subtracting(targetIDs).count,
                     changed: previousIDs.intersection(targetIDs).filter {
                         previous[$0] != target[$0]
                     }.count)
    }

    /// A legacy trigger address can equal the normalized device address even
    /// when the JSON fields differ. This is only for display; it never proves
    /// that the physical device already has the target configuration.
    var hasKnownDeviceDelta: Bool { knownMemberImpact?.hasDelta ?? true }

    private struct RelevantMember: Equatable {
        let groupAddress: UInt16
        let primaryAddress: UInt16
        let deviceAddress: UInt16
    }

    private static func relevantMembers(_ value: SiteJSONValue)
        -> [SiteTriggerZoneMember.Identity: RelevantMember]? {
        guard case .array(let values) = value else { return nil }
        var result: [SiteTriggerZoneMember.Identity: RelevantMember] = [:]
        for value in values {
            guard case .object(let fields) = value,
                  let display = SiteTriggerZoneDisplayMember(value: value),
                  case .integer(let group) = fields["groupAddress"],
                  let groupAddress = UInt16(exactly: group),
                  let primaryAddress = display.primaryAddress,
                  case .integer(let address) = fields["deviceAddress"] ?? fields["triggerElementAddress"],
                  let deviceAddress = UInt16(exactly: address),
                  result[display.identity] == nil else { return nil }
            result[display.identity] = .init(groupAddress: groupAddress,
                                             primaryAddress: primaryAddress,
                                             deviceAddress: deviceAddress)
        }
        return result
    }
}

struct SiteTriggerZoneState: Codable, Equatable {
    /// Local recovery only. The table already isolates Site and region; accounts
    /// retain independent generations even if a database is reused at sign-in.
    var referenceCleanupRequests: [String: UUID]?
    var data = SiteExtensionData()
    var serverData: SiteExtensionData?
    var serverTimestamp: Int64 = 0
    var pending: SiteTriggerZonePending?
    var submitted: SiteTriggerZonePending?
    /// Superseded local edits are retained for review, never retried automatically.
    var archivedPendings: [SiteTriggerZonePending]?
    var archivedReviewNeeded: Bool?
    var needsArchivedReview: Bool { archivedReviewNeeded == true }
    var rejectedRemote: Data?
    var conflict = false
    /// Equal server versions with different content cannot establish an ordering.
    var ambiguousRemote: Bool?
    var hasAmbiguousRemote: Bool { ambiguousRemote == true }
    /// Retained after cloud confirmation for the later device-sync planner.
    var deviceSyncChanges: [SiteTriggerZoneDeviceSyncChange]?

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
        if timestamp == serverTimestamp, let serverData, remote != serverData {
            ambiguousRemote = true
            return
        }
        ambiguousRemote = false
        let previousServer = serverData
        let pendingBeforeReceive = pending
        let submittedBeforeReceive = submitted
        if let pending {
            if remote == pending.target {
                self.pending = nil
                submitted = nil
                data = remote
                conflict = false
            } else if let submitted, remote == submitted.target,
               submitted.operationId != pending.operationId {
                self.pending = .init(operationId: pending.operationId,
                                     timestamp: max(pending.timestamp, timestamp + 1),
                                     base: remote, target: pending.target)
                self.submitted = nil
                conflict = false
            } else if let base = pending.base, remote != base {
                if SiteExtensionData.targetCoversServerChanges(
                    base: base, server: remote, target: pending.target
                ) {
                    self.pending = .init(
                        operationId: pending.operationId,
                        timestamp: max(pending.timestamp, timestamp + 1),
                        base: remote, target: pending.target
                    )
                    submitted = nil
                    conflict = false
                } else {
                    archive(pending)
                    self.pending = nil
                    submitted = nil
                    data = remote
                    conflict = false
                }
            } else if pending.base == nil, remote != pending.target {
                archive(pending)
                self.pending = nil
                submitted = nil
                data = remote
                conflict = false
            }
        } else {
            data = remote
            conflict = false
        }
        if let previousServer, previousServer != remote {
            recordDeviceSyncChanges(from: .init(
                operationId: UUID(), timestamp: timestamp,
                base: previousServer, target: remote
            ))
        } else if previousServer == nil,
                  let receipt = [pendingBeforeReceive, submittedBeforeReceive].compactMap({ $0 })
                    .first(where: { $0.target == remote }) {
            recordDeviceSyncChanges(from: receipt)
        }
        serverData = remote
        serverTimestamp = timestamp
    }

    private mutating func archive(_ pending: SiteTriggerZonePending) {
        var records = archivedPendings ?? []
        if !records.contains(where: { $0.operationId == pending.operationId }) {
            records.append(pending)
        }
        archivedPendings = records
        archivedReviewNeeded = true
    }

    mutating func acknowledgeArchivedReview() { archivedReviewNeeded = false }

    private mutating func recordDeviceSyncChanges(from receipt: SiteTriggerZonePending) {
        guard let targetZones = receipt.target.zones else { return }
        let baseZones = receipt.base?.zones ?? []
        let zoneIDs = targetZones.map(\.zoneId)
            + baseZones.map(\.zoneId).filter { id in !targetZones.contains { $0.zoneId == id } }
        var changes = deviceSyncChanges ?? []
        for id in zoneIDs {
            let old = baseZones.first(where: { $0.zoneId == id })?.fields["members"] ?? .array([])
            let new = targetZones.first(where: { $0.zoneId == id })?.fields["members"] ?? .array([])
            guard old != new else { continue }
            let original = changes.first(where: { $0.zoneID == id })?.previousMembers ?? old
            changes.removeAll { $0.zoneID == id }
            if original != new {
                changes.append(.init(zoneID: id, previousMembers: original, targetMembers: new))
            }
        }
        deviceSyncChanges = changes
    }

    mutating func discardPending() {
        guard let serverData else { return }
        if let pending { archive(pending) }
        data = serverData
        pending = nil
        submitted = nil
        conflict = false
    }
}

/// Only an explicit, complete inventory can classify a member as obsolete.
/// Unknown members and all unrelated fields remain byte-for-byte JSON values.
enum SiteTriggerZoneReferenceCleanup {
    enum Classification { case valid, obsolete, unknown }

    static func clean(_ zone: SiteTriggerZone,
                      classify: (SiteJSONValue) -> Classification) -> SiteTriggerZone {
        guard zone.hasCompleteDisplayMembers, case .array(let members) = zone.fields["members"] else { return zone }
        var result = zone
        result.fields["members"] = .array(members.filter { classify($0) != .obsolete })
        return result
    }

    static func clean(_ data: SiteExtensionData,
                      classify: (SiteJSONValue) -> Classification) -> SiteExtensionData {
        guard data.fields["schemaVersion"] == .integer(1) || data.fields["schemaVersion"] == .integer(2),
              let zones = data.zones else { return data }
        var result = data
        result.replaceZones(zones.map { clean($0, classify: classify) })
        return result
    }
}
