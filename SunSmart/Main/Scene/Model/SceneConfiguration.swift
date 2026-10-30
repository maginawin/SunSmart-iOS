import Foundation
import CoreFoundation

enum SceneKind: String, Codable { case groups, devices }

struct SceneParameters: Codable, Equatable {
    var isOn: Bool
    var lightness: UInt16
    var cct: UInt16
}

struct SceneDeviceMember: Codable, Equatable {
    let identity: TimedSchedulerNodeIdentity
    var parameters: SceneParameters
}

struct ScenePendingOperation: Codable, Equatable {
    enum Action: String, Codable { case write, remove }
    let identity: TimedSchedulerNodeIdentity
    let action: Action
    let generation: UUID

    init(identity: TimedSchedulerNodeIdentity, action: Action, generation: UUID = UUID()) {
        self.identity = identity
        self.action = action
        self.generation = generation
    }
}

struct SceneScope: Codable, Equatable {
    let meshUUID: String
    let networkID: String
}

/// Local recovery evidence only; never exported as a Scene configuration.
struct SceneRestoreReceipt: Codable, Equatable {
    enum Stage: String, Codable { case prepared, verified, applied }
    let id: UUID
    let scope: SceneScope
    let recoveryGeneration: UUID
    let oldIdentity: TimedSchedulerNodeIdentity
    var newIdentity: TimedSchedulerNodeIdentity?
    var stage: Stage = .prepared
}

struct SceneConfiguration: Codable, Equatable {
    enum Failure: Error { case invalidVersion, invalidIdentity, duplicateIdentity, conflictingMode, conflictingOperation, invalidDraft }
    var schemaVersion = 1
    var kind: SceneKind
    var name: String
    var revision = UUID()
    var deviceMembers: [SceneDeviceMember] = []
    var pendingOperations: [ScenePendingOperation] = []
    var isDeleting = false

    static func decode(_ data: Data) throws -> SceneConfiguration {
        try JSONDecoder().decode(Self.self, from: data)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// The codec is also the validation boundary for database and later import.
    /// Only an absent *outer* block is legacy data; fields inside a block are required.
    func normalized() throws -> SceneConfiguration {
        guard schemaVersion == 1 else { throw Failure.invalidVersion }
        guard kind != .groups || deviceMembers.isEmpty else { throw Failure.conflictingMode }
        var result = self
        result.deviceMembers = try deviceMembers.map {
            .init(identity: try Self.identity($0.identity), parameters: $0.parameters)
        }.sorted { Self.key($0.identity) < Self.key($1.identity) }
        result.pendingOperations = try pendingOperations.map {
            .init(identity: try Self.identity($0.identity), action: $0.action, generation: $0.generation)
        }.sorted { Self.key($0.identity) < Self.key($1.identity) }
        let members = result.deviceMembers.map(\.identity)
        let operations = result.pendingOperations.map(\.identity)
        guard Set(members).count == members.count,
              Set(members.map(\.nodeUUID)).count == members.count,
              Set(members.map(\.unicastAddress)).count == members.count,
              Set(operations).count == operations.count else { throw Failure.duplicateIdentity }
        for operation in result.pendingOperations {
            if isDeleting && operation.action == .write { throw Failure.conflictingOperation }
            if kind == .devices {
                if operation.action == .write && !members.contains(operation.identity) { throw Failure.conflictingOperation }
                if !isDeleting && operation.action == .remove && members.contains(operation.identity) { throw Failure.conflictingOperation }
            }
        }
        return result
    }

    func removingConfirmedIdentities(_ identities: Set<TimedSchedulerNodeIdentity>) throws -> SceneConfiguration {
        var result = try normalized()
        let removed = try Set(identities.map(Self.identity))
        result.deviceMembers.removeAll { removed.contains($0.identity) }
        result.pendingOperations.removeAll { removed.contains($0.identity) }
        return result
    }

    /// Only an explicit, verified Restore receipt may call this. A new device
    /// at the same address never reaches this migration through ordinary add.
    func restoringIdentity(from old: TimedSchedulerNodeIdentity, to new: TimedSchedulerNodeIdentity) throws -> SceneConfiguration {
        let old = try Self.identity(old), new = try Self.identity(new)
        guard old.nodeUUID == new.nodeUUID else { throw Failure.invalidIdentity }
        var result = try normalized()
        let member = result.deviceMembers.first { $0.identity == old }
        let operation = result.pendingOperations.first { $0.identity == old }
        guard member != nil || operation != nil else { return result }
        guard old != new else { return result }
        guard !result.deviceMembers.contains(where: { $0.identity == new }),
              !result.pendingOperations.contains(where: { $0.identity == new }) else { throw Failure.duplicateIdentity }
        result.deviceMembers.removeAll { $0.identity == old }
        result.pendingOperations.removeAll { $0.identity == old }
        if let member { result.deviceMembers.append(.init(identity: new, parameters: member.parameters)) }
        let action: ScenePendingOperation.Action = result.isDeleting || operation?.action == .remove ? .remove : .write
        result.pendingOperations.append(.init(identity: new, action: action))
        result.revision = UUID()
        return try result.normalized()
    }

    static func identity(_ identity: TimedSchedulerNodeIdentity) throws -> TimedSchedulerNodeIdentity {
        guard identity.isValid else { throw Failure.invalidIdentity }
        return .init(nodeUUID: identity.nodeUUID.uppercased(), unicastAddress: identity.unicastAddress.uppercased(),
                     deviceKeyFingerprint: identity.deviceKeyFingerprint.uppercased())
    }

    static func key(_ identity: TimedSchedulerNodeIdentity) -> String {
        identity.nodeUUID + ":" + identity.unicastAddress + ":" + identity.deviceKeyFingerprint
    }
}

extension SceneConfiguration {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, kind, name, revision, deviceMembers, pendingOperations, isDeleting
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        kind = try values.decode(SceneKind.self, forKey: .kind)
        name = try values.decode(String.self, forKey: .name)
        revision = try values.decode(UUID.self, forKey: .revision)
        deviceMembers = try values.decode([SceneDeviceMember].self, forKey: .deviceMembers)
        pendingOperations = try values.decode([ScenePendingOperation].self, forKey: .pendingOperations)
        isDeleting = try values.decode(Bool.self, forKey: .isDeleting)
        self = try normalized()
    }

    func encode(to encoder: Encoder) throws {
        let value = try normalized()
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(value.schemaVersion, forKey: .schemaVersion)
        try values.encode(value.kind, forKey: .kind)
        try values.encode(value.name, forKey: .name)
        try values.encode(value.revision, forKey: .revision)
        try values.encode(value.deviceMembers, forKey: .deviceMembers)
        try values.encode(value.pendingOperations, forKey: .pendingOperations)
        try values.encode(value.isDeleting, forKey: .isDeleting)
    }
}

struct SceneDraft: Equatable {
    let number: UInt16?
    let scope: SceneScope
    private(set) var name: String
    private(set) var imageId: Int
    private(set) var kind: SceneKind
    private(set) var groupParameters: [UInt16: SceneParameters]
    private(set) var deviceMembers: [SceneDeviceMember]
    private(set) var revision = UUID()
    let sourceConfiguration: SceneConfiguration?
    let sourceGroupAuxiliaryData: [UInt16: Data]
    let sourceGroupParameters: [UInt16: SceneParameters]
    let sourceGroupAddresses: Set<UInt16>
    let sourceCleanupIdentities: [TimedSchedulerNodeIdentity]
    let sourceImageId: Int
    let sourceName: String

    init(number: UInt16? = nil, scope: SceneScope, name: String, imageId: Int, kind: SceneKind,
         groupParameters: [UInt16: SceneParameters] = [:], deviceMembers: [SceneDeviceMember] = [],
         sourceConfiguration: SceneConfiguration? = nil,
         sourceGroupAddresses: Set<UInt16>? = nil,
         sourceCleanupIdentities: [TimedSchedulerNodeIdentity] = [],
         sourceGroupAuxiliaryData: [UInt16: Data] = [:]) throws {
        guard number.map({ (1..<0xFF00).contains($0) }) ?? true,
              kind != .devices || groupParameters.isEmpty,
              kind != .groups || deviceMembers.isEmpty else { throw SceneConfiguration.Failure.invalidDraft }
        let validated = try SceneConfiguration(kind: kind, name: name, deviceMembers: deviceMembers).normalized()
        self.number = number; self.scope = scope; self.name = name; self.imageId = imageId; self.kind = kind
        self.groupParameters = groupParameters; self.deviceMembers = validated.deviceMembers
        self.sourceConfiguration = try sourceConfiguration?.normalized()
        self.sourceGroupAuxiliaryData = sourceGroupAuxiliaryData
        self.sourceGroupAddresses = sourceGroupAddresses ?? Set(groupParameters.keys)
        self.sourceCleanupIdentities = try sourceCleanupIdentities.map(SceneConfiguration.identity)
        sourceGroupParameters = groupParameters; sourceImageId = imageId; sourceName = name
    }

    mutating func setDeviceMembers(_ members: [SceneDeviceMember]) throws {
        guard kind == .devices else { throw SceneConfiguration.Failure.conflictingMode }
        let value = try SceneConfiguration(kind: kind, name: name, deviceMembers: members).normalized().deviceMembers
        guard deviceMembers != value else { return }
        deviceMembers = value; revision = UUID()
    }

    mutating func setGroupParameters(_ parameters: [UInt16: SceneParameters]) throws {
        guard kind == .groups else { throw SceneConfiguration.Failure.conflictingMode }
        guard groupParameters != parameters else { return }
        groupParameters = parameters; revision = UUID()
    }

    mutating func setMetadata(name: String, imageId: Int) {
        guard self.name != name || self.imageId != imageId else { return }
        self.name = name; self.imageId = imageId; revision = UUID()
    }

    mutating func switchKind(to kind: SceneKind) throws {
        guard self.kind != kind else { return }
        if number != nil {
            guard sourceGroupAddresses.isEmpty, sourceCleanupIdentities.isEmpty,
                  sourceConfiguration?.deviceMembers.isEmpty != false,
                  sourceConfiguration?.pendingOperations.isEmpty != false,
                  sourceConfiguration?.isDeleting != true else { throw SceneConfiguration.Failure.conflictingMode }
        }
        self.kind = kind; groupParameters = [:]; deviceMembers = []; revision = UUID()
    }
}

/// The external representation uses the same strict configuration codec as App rows.
/// Metadata is carried alongside intent; SDK presence is deliberately not required.
enum SceneConfigurationPayload {
    enum Failure: Error { case invalidPayload, invalidNumber, duplicateNumber, metadataMismatch, conflictingMode }
    struct Record {
        let number: UInt16
        let name: String
        let imageId: Int
        let configuration: SceneConfiguration?
    }

    static func number(_ raw: Any?) throws -> UInt16 {
        guard let hex = raw as? String, hex.count == 4,
              hex.allSatisfy({ $0.isASCII && $0.isHexDigit }),
              let number = UInt16(hex, radix: 16), (1..<0xFF00).contains(number) else { throw Failure.invalidNumber }
        return number
    }

    static func encode(records: [Record]) throws -> [[String: Any]] {
        var seen = Set<UInt16>()
        return try records.sorted { $0.number < $1.number }.compactMap { record in
            guard (1..<0xFF00).contains(record.number), seen.insert(record.number).inserted else { throw Failure.invalidNumber }
            guard let config = record.configuration else { return nil }
            guard config.name == record.name else { throw Failure.metadataMismatch }
            var row = try JSONSerialization.jsonObject(with: config.encoded()) as! [String: Any]
            row["number"] = String(format: "%04X", record.number)
            return row
        }
    }

    static func metadata(records: [Record]) throws -> [[String: Any]] {
        _ = try encode(records: records)
        return records.sorted { $0.number < $1.number }.map {
            ["number": String(format: "%04X", $0.number), "name": $0.name, "imageId": $0.imageId]
        }
    }

    static func decode(_ value: Any?) throws -> [UInt16: SceneConfiguration] {
        guard let value else { return [:] }
        guard let rows = value as? [[String: Any]] else { throw Failure.invalidPayload }
        var result: [UInt16: SceneConfiguration] = [:]
        for row in rows {
            let id = try number(row["number"])
            guard result[id] == nil else { throw Failure.duplicateNumber }
            result[id] = try SceneConfiguration.decode(JSONSerialization.data(withJSONObject: row))
        }
        return result
    }

    static func canonical(_ value: Any?) throws -> Data {
        let configs = try decode(value)
        return try JSONSerialization.data(withJSONObject: encode(records: configs.map {
            Record(number: $0.key, name: $0.value.name, imageId: 0, configuration: $0.value)
        }), options: .sortedKeys)
    }

    static func records(payload: [String: Any]) throws -> [Record] {
        let extensionData: [String: Any]
        if let raw = payload["spaceData"] {
            guard let object = raw as? [String: Any] else { throw Failure.invalidPayload }
            extensionData = object
        } else { extensionData = payload }
        let configs = try decode(extensionData["sceneConfigurations"])
        guard let rows = payload["scenes"] as? [[String: Any]] else { throw Failure.invalidPayload }
        var seen = Set<UInt16>()
        let records = try rows.map { row -> Record in
            let id = try number(row["number"])
            guard seen.insert(id).inserted else { throw Failure.duplicateNumber }
            guard let name = row["name"] as? String,
                  row["imageId"] == nil || integer(row["imageId"]) != nil else { throw Failure.invalidPayload }
            if let config = configs[id], config.name != name { throw Failure.metadataMismatch }
            return Record(number: id, name: name, imageId: integer(row["imageId"]) ?? 0, configuration: configs[id])
        }
        guard Set(configs.keys).isSubset(of: seen) else { throw Failure.metadataMismatch }
        guard let groups = payload["groups"] as? [[String: Any]] else { throw Failure.invalidPayload }
        for group in groups {
            for row in try groupParameters(group["scenesDatas"]) {
                let id = UInt16(integer(row["sceneNumber"])!)
                guard configs[id]?.kind != .devices else { throw Failure.conflictingMode }
            }
        }
        return records.sorted { $0.number < $1.number }
    }

    /// Preserve the complete SDK payload, including HSL, LC and cleanup state.
    /// Missing old optional values normalize to the SDK decoder's exact defaults.
    static func groupParameters(_ value: Any?) throws -> [[String: Any]] {
        guard let value else { return [] }
        guard let rows = value as? [[String: Any]] else { throw Failure.invalidPayload }
        var seen = Set<Int>()
        return try rows.map { original in
            var row = original
            guard let number = integer(row["sceneNumber"]), (1...65535).contains(number),
                  seen.insert(number).inserted,
                  let on = row["isOn"] as? NSNumber, CFGetTypeID(on) == CFBooleanGetTypeID(),
                  ["lightness", "cct"].allSatisfy({ integer(row[$0]).map { (0...65535).contains($0) } == true }),
                  let state = integer(row["state"]), [1, 2].contains(state) else { throw Failure.invalidPayload }
            for key in ["hue", "saturation"] {
                if row[key] == nil || row[key] is NSNull { row[key] = 0 }
                guard let value = integer(row[key]), (0...65535).contains(value) else { throw Failure.invalidPayload }
            }
            if row["lightControlData"] is NSNull { row.removeValue(forKey: "lightControlData") }
            if let raw = row["lightControlData"] {
                guard var lc = raw as? [String: Any] else { throw Failure.invalidPayload }
                // Defaults applied by the existing SDK LightLCProperty decoder.
                for key in ["lightnessStandby", "luxLevelStandby", "manualOverrideTimeout"] {
                    if lc[key] == nil || lc[key] is NSNull { lc[key] = 0 }
                }
                lc = lc.filter { !($0.value is NSNull) }
                row["lightControlData"] = lc
            }
            return row
        }.sorted { integer($0["sceneNumber"])! < integer($1["sceneNumber"])! }
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue.rounded() == value.doubleValue else { return nil }
        return Int(exactly: value.doubleValue)
    }
}
