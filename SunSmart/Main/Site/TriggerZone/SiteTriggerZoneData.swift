import Foundation

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
