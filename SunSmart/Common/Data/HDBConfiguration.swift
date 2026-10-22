import Foundation

enum HDBSyncStatus: String, Codable { case pending, synced }

struct HDBConfiguration: Codable, Equatable {
    var schemaVersion = 2
    var lightingZones: [HDBLightingZone] = []
    var devices: [HDBDeviceConfiguration] = []
    var allGroupAddresses: Set<UInt16> {
        Set(lightingZones.map(\.groupAddress)).union(devices.compactMap(\.sensorGroupId))
    }
}

extension HDBConfiguration {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion == 2 else { throw HDBConfigurationError.invalidData }
        lightingZones = try c.decode([HDBLightingZone].self, forKey: .lightingZones)
        devices = try c.decode([HDBDeviceConfiguration].self, forKey: .devices)
    }
}

/// External HDB v2 representation only; Mesh values and preparation signatures
/// retain their numeric types and existing encoding.
private struct HDBHexUInt16: Codable {
    let value: UInt16
    init(_ value: UInt16) { self.value = value }
    init(from decoder: Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard text.count == 4, text.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
              let value = UInt16(text, radix: 16) else { throw HDBConfigurationError.invalidData }
        self.value = value
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(String(format: "%04X", value))
    }
}

struct HDBLightingZone: Codable, Equatable {
    var zoneId: Int
    var name: String
    var groupAddress: UInt16
}

extension HDBLightingZone {
    private enum CodingKeys: String, CodingKey { case zoneId, name, groupId, groupAddress }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard !c.contains(.groupAddress) else { throw HDBConfigurationError.invalidData }
        zoneId = try c.decode(Int.self, forKey: .zoneId)
        name = try c.decode(String.self, forKey: .name)
        groupAddress = try c.decode(HDBHexUInt16.self, forKey: .groupId).value
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(zoneId, forKey: .zoneId)
        try c.encode(name, forKey: .name)
        try c.encode(HDBHexUInt16(groupAddress), forKey: .groupId)
    }
}

struct HDBDeviceConfiguration: Codable, Equatable {
    var nodeUuid: UUID
    var nodeAddress: UInt16
    var mac: String
    var lightingZones: [HDBZoneMembership] = []
    var lightingZonesStatus: HDBSyncStatus = .pending
    var sensorGroupId: UInt16?
    var zoneModels: [HDBModelReference] = []
    var sensorGroupModels: [HDBModelReference] = []
    var broadcastModels: [HDBModelReference] = []
    var broadcastId: UInt16 = 0xFEFD
    var lightingConfiguration: HDBLightingConfiguration?

    /// Keep the existing internal identity/display format. HDB JSON uses compact MACs.
    static func normalizedMAC(_ value: String?) throws -> String {
        guard let value, value.range(of: "^([0-9A-Fa-f]{12}|[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}|[0-9A-Fa-f]{2}(-[0-9A-Fa-f]{2}){5})$", options: .regularExpression) == value.startIndex..<value.endIndex else {
            throw HDBConfigurationError.invalidMAC
        }
        let raw = value.replacingOccurrences(of: ":", with: "").replacingOccurrences(of: "-", with: "").uppercased()
        return stride(from: 0, to: 12, by: 2).map { offset in
            let start = raw.index(raw.startIndex, offsetBy: offset)
            return String(raw[start..<raw.index(start, offsetBy: 2)])
        }.joined(separator: ":")
    }

    private enum CodingKeys: String, CodingKey { case nodeUuid, nodeAddress, mac, lightingZones, lightingZonesStatus, sensorGroupId, zoneModels, sensorGroupModels, broadcastModels, broadcastId, lightingConfiguration }
    init(nodeUuid: UUID, nodeAddress: UInt16, mac: String, lightingZones: [HDBZoneMembership] = []) {
        self.nodeUuid = nodeUuid; self.nodeAddress = nodeAddress; self.mac = mac; self.lightingZones = lightingZones
        lightingConfiguration = .defaults
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeUuid = try c.decode(UUID.self, forKey: .nodeUuid)
        nodeAddress = try c.decode(HDBHexUInt16.self, forKey: .nodeAddress).value
        let rawMAC = try c.decode(String.self, forKey: .mac)
        guard rawMAC.count == 12, rawMAC.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }) else { throw HDBConfigurationError.invalidMAC }
        mac = try Self.normalizedMAC(rawMAC)
        lightingZones = try c.decode([Int].self, forKey: .lightingZones).map { HDBZoneMembership(zoneId: $0) }
        lightingZonesStatus = try c.decode(HDBSyncStatus.self, forKey: .lightingZonesStatus)
        guard c.contains(.sensorGroupId) else { throw HDBConfigurationError.invalidData }
        sensorGroupId = try c.decodeIfPresent(HDBHexUInt16.self, forKey: .sensorGroupId)?.value
        zoneModels = HDBModelReference.normalized(try c.decode([HDBModelReference].self, forKey: .zoneModels))
        sensorGroupModels = HDBModelReference.normalized(try c.decode([HDBModelReference].self, forKey: .sensorGroupModels))
        broadcastModels = HDBModelReference.normalized(try c.decode([HDBModelReference].self, forKey: .broadcastModels))
        broadcastId = try c.decode(HDBHexUInt16.self, forKey: .broadcastId).value
        guard broadcastId == 0xFEFD else { throw HDBConfigurationError.invalidData }
        if c.contains(.lightingConfiguration), try !c.decodeNil(forKey: .lightingConfiguration) {
            lightingConfiguration = try HDBLightingConfiguration.decode(from: c.superDecoder(forKey: .lightingConfiguration),
                models: zoneModels.map(\.target), primaryAddress: nodeAddress)
        } else { lightingConfiguration = nil }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nodeUuid, forKey: .nodeUuid); try c.encode(HDBHexUInt16(nodeAddress), forKey: .nodeAddress)
        try c.encode(Self.normalizedMAC(mac).replacingOccurrences(of: ":", with: ""), forKey: .mac)
        try c.encode(lightingZones.map(\.zoneId), forKey: .lightingZones)
        try c.encode(lightingZonesStatus, forKey: .lightingZonesStatus)
        try c.encode(sensorGroupId.map(HDBHexUInt16.init), forKey: .sensorGroupId)
        try c.encode(HDBModelReference.normalized(zoneModels), forKey: .zoneModels)
        try c.encode(HDBModelReference.normalized(sensorGroupModels), forKey: .sensorGroupModels)
        try c.encode(HDBModelReference.normalized(broadcastModels), forKey: .broadcastModels)
        try c.encode(HDBHexUInt16(broadcastId), forKey: .broadcastId)
        if let lightingConfiguration {
            try lightingConfiguration.encode(to: c.superEncoder(forKey: .lightingConfiguration),
                models: zoneModels.map(\.target), primaryAddress: nodeAddress)
        } else { try c.encodeNil(forKey: .lightingConfiguration) }
    }

    mutating func copyModels(from device: Self) {
        zoneModels = device.zoneModels; sensorGroupModels = device.sensorGroupModels
        broadcastModels = device.broadcastModels; broadcastId = device.broadcastId
    }

    func hasSameModels(as device: Self) -> Bool {
        Set(zoneModels) == Set(device.zoneModels) && Set(sensorGroupModels) == Set(device.sensorGroupModels)
            && Set(broadcastModels) == Set(device.broadcastModels) && broadcastId == device.broadcastId
    }
}

/// Hexadecimal wire representation for the HDB device metadata. Internal preparation
/// targets retain their existing hexadecimal encoding and initialization signature.
struct HDBModelReference: Codable, Hashable {
    let elementAddress: UInt16
    let modelId: UInt32

    init(_ target: HDBModelTarget) { elementAddress = target.elementAddress; modelId = target.modelId }

    private enum CodingKeys: String, CodingKey { case elementAddress, modelId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elementAddress = try c.decode(HDBHexUInt16.self, forKey: .elementAddress).value
        let text = try c.decode(String.self, forKey: .modelId)
        guard [4, 8].contains(text.count), text.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
              let id = UInt32(text, radix: 16), text.count == 4 || id > 0xFFFF else { throw HDBConfigurationError.invalidData }
        modelId = id
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(HDBHexUInt16(elementAddress), forKey: .elementAddress)
        try c.encode(String(format: modelId > 0xFFFF ? "%08X" : "%04X", modelId), forKey: .modelId)
    }

    var target: HDBModelTarget {
        .init(elementAddress: elementAddress, modelIdentifier: UInt16(modelId & 0xFFFF),
              companyIdentifier: modelId > 0xFFFF ? UInt16(modelId >> 16) : nil)
    }

    static func normalized(_ models: [Self]) -> [Self] {
        Set(models).sorted { $0.elementAddress == $1.elementAddress ? $0.modelId < $1.modelId : $0.elementAddress < $1.elementAddress }
    }
}

struct HDBZoneMembership: Codable, Equatable {
    var zoneId: Int
}

struct HDBModelTarget: Hashable, Codable {
    let elementAddress: UInt16
    let modelIdentifier: UInt16
    let companyIdentifier: UInt16?

    var modelId: UInt32 { UInt32(companyIdentifier ?? 0) << 16 | UInt32(modelIdentifier) }

    init(elementAddress: UInt16, modelIdentifier: UInt16, companyIdentifier: UInt16?) {
        self.elementAddress = elementAddress
        self.modelIdentifier = modelIdentifier
        self.companyIdentifier = companyIdentifier
    }

    private enum CodingKeys: String, CodingKey { case elementAddress, modelId }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        elementAddress = try c.decode(UInt16.self, forKey: .elementAddress)
        let text = try c.decode(String.self, forKey: .modelId)
        guard [4, 8].contains(text.count),
              text.allSatisfy({ "0123456789abcdefABCDEF".contains($0) }),
              let id = UInt32(text, radix: 16),
              text.count == 4 || id > 0xFFFF else { throw HDBConfigurationError.invalidData }
        modelIdentifier = UInt16(id & 0xFFFF)
        companyIdentifier = text.count == 8 ? UInt16(id >> 16) : nil
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elementAddress, forKey: .elementAddress)
        try c.encode(String(format: companyIdentifier == nil ? "%04X" : "%08X", modelId), forKey: .modelId)
    }
}

/// Typed desired values; a successful preparation is not a live device readback.
enum HDBPreparationValue: Hashable {
    struct LC: Codable, Hashable {
        var occupancyMode: Bool
        var mode: Bool
    }
    struct LCSetup: Codable, Hashable {
        /// Raw Mesh Time Millisecond 24 value, including the existing infinite sentinel.
        var prolongTimeMilliseconds: UInt32
    }
    struct Vendor: Codable, Hashable {
        struct ManualOverrideTimeout: Codable, Hashable {
            enum State: String, Codable { case standby, on, prolong }
            var enabled: Bool
            var state: State
            /// Raw Vendor interval in milliseconds, including UInt32.max for infinite.
            var intervalMilliseconds: UInt32
        }
        var manualControlEnabled: Bool
        var lightAutoAdjustEnabled: Bool
        var manualOverrideTimeout: ManualOverrideTimeout
    }
    case lc(LC), lcSetup(LCSetup), vendor(Vendor)
}

struct HDBPreparationTarget: Codable, Hashable {
    let model: HDBModelTarget
    var value: HDBPreparationValue?

    /// The single source for the fixed HDB initialization values.
    init(model: HDBModelTarget) {
        self.model = model
        switch model.modelId {
        case 0x130F: value = .lc(.init(occupancyMode: true, mode: true))
        case 0x1310: value = .lcSetup(.init(prolongTimeMilliseconds: 0xFFFFFE))
        case 0x0A780001:
            value = .vendor(.init(manualControlEnabled: false, lightAutoAdjustEnabled: false,
                manualOverrideTimeout: .init(enabled: true, state: .standby, intervalMilliseconds: .max)))
        default: value = nil
        }
    }

    private enum CodingKeys: String, CodingKey { case value }
    init(from decoder: Decoder) throws {
        model = try HDBModelTarget(from: decoder)
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch model.modelId {
        case 0x130F: value = .lc(try c.decode(HDBPreparationValue.LC.self, forKey: .value))
        case 0x1310: value = .lcSetup(try c.decode(HDBPreparationValue.LCSetup.self, forKey: .value))
        case 0x0A780001: value = .vendor(try c.decode(HDBPreparationValue.Vendor.self, forKey: .value))
        default:
            guard !c.contains(.value) else { throw HDBConfigurationError.invalidData }
            value = nil
        }
        try validate()
    }
    func encode(to encoder: Encoder) throws {
        try validate()
        try model.encode(to: encoder)
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch value {
        case .lc(let value): try c.encode(value, forKey: .value)
        case .lcSetup(let value): try c.encode(value, forKey: .value)
        case .vendor(let value): try c.encode(value, forKey: .value)
        case nil: break
        }
    }
    func validate() throws {
        guard (1...0x7FFF).contains(Int(model.elementAddress)) else { throw HDBConfigurationError.invalidData }
        switch (model.modelId, value) {
        case (0x130F, .lc), (0x0A780001, .vendor), (0x1000, nil), (0x1300, nil): break
        case (0x1310, .lcSetup(let value)) where value.prolongTimeMilliseconds <= 0xFFFFFE: break
        default: throw HDBConfigurationError.invalidData
        }
    }
}

struct HDBZoneDestination: Equatable {
    let zoneId: Int
    let groupAddress: UInt16
}

/// Immutable device intent shared by every stage; no per-model result is persisted.
struct HDBZonePlan: Equatable {
    let nodeUuid: UUID
    let nodeAddress: UInt16
    let zones: [HDBZoneDestination]
    let sensorGroupId: UInt16?
    let targets: [HDBModelTarget]
    let sensorTargets: [HDBModelTarget]
    let broadcastTargets: [HDBModelTarget]
    let broadcastId: UInt16
}

struct HDBZoneSubscription: Hashable {
    enum Command: Hashable { case deleteAll, add }
    let target: HDBModelTarget
    let command: Command
    /// DeleteAll has no address in its request, and expects zero in its Status.
    let address: UInt16

    var parameters: Data {
        var bytes = Data()
        func append(_ value: UInt16) { bytes.append(UInt8(value & 255)); bytes.append(UInt8(value >> 8)) }
        append(target.elementAddress)
        if command != .deleteAll { append(address) }
        if let company = target.companyIdentifier { append(company) }
        append(target.modelIdentifier)
        return bytes
    }
}

struct HDBZoneOperation: Equatable {
    enum Stage: Int { case reset, broadcast, sensor, add }
    let plan: HDBZonePlan
    let stage: Stage
    let subscriptions: [HDBZoneSubscription]
    let isLast: Bool
    var nodeUuid: UUID { plan.nodeUuid }
    var nodeAddress: UInt16 { plan.nodeAddress }
    var targets: [HDBModelTarget] { plan.targets }
}

struct HDBZoneReceipt {
    let operation: HDBZoneOperation
    let successful: Bool
    var error: Error? = nil
}

enum HDBConfigurationError: Error {
    case invalidData, invalidMAC, invalidZones, unsupportedModels, unavailable, permissionDenied, persistenceFailed, addressUnavailable, busy
    case applicationKeyUnavailable, modelNotBound, unexpectedApplicationKey, responseMismatch
}

enum HDBPreparationStepID: Codable, Hashable {
    case subscription(HDBModelTarget), publication(HDBModelTarget)
}

struct HDBDevicePreparationPlan: Codable, Equatable {
    let nodeUuid: UUID
    let nodeAddress: UInt16
    var appKeyIndex: UInt16
    let baseTargets: [HDBPreparationTarget]
    let sensorGroupId: UInt16?
    let publicationTargets: [HDBModelTarget]
    let subscriptionTargets: [HDBModelTarget]

}

enum HDBLightingCommand: String, Codable, CaseIterable {
    case override, intensity, softDimming, timeDelay, installDate
    var titleKey: String { "hdb_lighting_" + rawValue }
}

enum HDBLightingControl: String, Codable, CaseIterable {
    case auto = "Auto", forceOn = "Force_On", forceOff = "Force_Off"
    var write: HDBLightingWrite {
        switch self { case .auto: return .auto; case .forceOn: return .lightness(65535); case .forceOff: return .off }
    }
}


/// Shared field/property/value rules for JSON descriptors and actual Mesh writes.
enum HDBLightingProperty: String, CaseIterable {
    case dimIntensity, brightIntensity, rampUpTime, rampDownTime, holdTime
    var identifier: UInt16 {
        switch self {
        case .dimIntensity: return 0x002F
        case .brightIntensity: return 0x002E
        case .rampUpTime: return 0x0037
        case .rampDownTime: return 0x0036
        case .holdTime: return 0x003C
        }
    }
    func value(in values: HDBLightingValues) -> Int? {
        switch self {
        case .dimIntensity: return values.dimIntensity
        case .brightIntensity: return values.brightIntensity
        case .rampUpTime: return values.rampUpTime
        case .rampDownTime: return values.rampDownTime
        case .holdTime: return values.holdTime
        }
    }
    func rawValue(for value: Int) -> UInt32 {
        switch self {
        case .dimIntensity, .brightIntensity: return UInt32(Double(value) / 100 * 65535)
        default: return UInt32(value * 1000)
        }
    }
}

enum HDBLightingWrite: Equatable {
    case auto, off, lightness(UInt16), property(UInt16, UInt32)
    var fieldName: String {
        switch self {
        case .auto, .off, .lightness: return "lightingControl"
        case .property(let id, _):
            return HDBLightingProperty.allCases.first { $0.identifier == id }?.rawValue ?? ""
        }
    }
    var modelIdentifier: UInt16 {
        switch self { case .auto: return 0x130F; case .off: return 0x1000; case .lightness: return 0x1300; case .property: return 0x1310 }
    }
    /// Property writes belong to the first LC's element, even when an earlier
    /// or later element independently exposes a Setup Server.
    func target(in models: [HDBModelTarget], primaryAddress: UInt16) -> HDBModelTarget? {
        let sig = models.filter {
            $0.companyIdentifier == nil && (1...0x7FFF).contains(Int($0.elementAddress))
                && $0.elementAddress >= primaryAddress
        }
        if case .property = self {
            guard let lc = sig.filter({ $0.modelIdentifier == 0x130F }).min(by: { $0.elementAddress < $1.elementAddress }) else { return nil }
            return sig.first { $0.modelIdentifier == modelIdentifier && $0.elementAddress == lc.elementAddress }
        }
        return sig.filter {
            $0.modelIdentifier == modelIdentifier && (self != .off || $0.elementAddress == primaryAddress)
        }.min { $0.elementAddress < $1.elementAddress }
    }

}

struct HDBLightingValues: Codable, Equatable {
    var lightingControl: HDBLightingControl?
    var failsafeDelay: Int?
    var dimIntensity: Int?
    var brightIntensity: Int?
    var rampUpTime: Int?
    var rampDownTime: Int?
    var holdTime: Int?
    var installDate: String?

    static let defaults = HDBLightingValues(lightingControl: .auto, failsafeDelay: 5, dimIntensity: 20,
        brightIntensity: 80, rampUpTime: 1, rampDownTime: 2, holdTime: 30)

    func only(_ field: String) -> Self {
        switch field {
        case "lightingControl": return .init(lightingControl: lightingControl)
        case "failsafeDelay": return .init(failsafeDelay: failsafeDelay)
        case "dimIntensity": return .init(dimIntensity: dimIntensity)
        case "brightIntensity": return .init(brightIntensity: brightIntensity)
        case "rampUpTime": return .init(rampUpTime: rampUpTime)
        case "rampDownTime": return .init(rampDownTime: rampDownTime)
        case "holdTime": return .init(holdTime: holdTime)
        case "installDate": return .init(installDate: installDate)
        default: return .init()
        }
    }

    func selected(_ command: HDBLightingCommand) -> Self {
        switch command {
        case .override: return .init(lightingControl: lightingControl, failsafeDelay: failsafeDelay)
        case .intensity: return .init(dimIntensity: dimIntensity, brightIntensity: brightIntensity)
        case .softDimming: return .init(rampUpTime: rampUpTime, rampDownTime: rampDownTime)
        case .timeDelay: return .init(holdTime: holdTime)
        case .installDate: return .init(installDate: installDate)
        }
    }
    func merging(_ other: Self) -> Self {
        .init(lightingControl: other.lightingControl ?? lightingControl,
              failsafeDelay: other.failsafeDelay ?? failsafeDelay,
              dimIntensity: other.dimIntensity ?? dimIntensity, brightIntensity: other.brightIntensity ?? brightIntensity,
              rampUpTime: other.rampUpTime ?? rampUpTime, rampDownTime: other.rampDownTime ?? rampDownTime,
              holdTime: other.holdTime ?? holdTime, installDate: other.installDate ?? installDate)
    }
    var fieldNames: [String] {
        [("lightingControl", lightingControl != nil), ("failsafeDelay", failsafeDelay != nil),
         ("dimIntensity", dimIntensity != nil), ("brightIntensity", brightIntensity != nil),
         ("rampUpTime", rampUpTime != nil), ("rampDownTime", rampDownTime != nil),
         ("holdTime", holdTime != nil), ("installDate", installDate != nil)].filter { $0.1 }.map { $0.0 }
    }
    func validate() throws {
        for (value, range) in [(failsafeDelay, 0...250), (dimIntensity, 0...50), (brightIntensity, 50...100),
                               (rampUpTime, 1...3), (rampDownTime, 1...3), (holdTime, 10...3600)] {
            if let value = value, !range.contains(value) { throw HDBConfigurationError.invalidData }
        }
        if let date = installDate {
            guard date.range(of: "^[0-9]{2}-[0-9]{2}-[0-9]{4}$", options: .regularExpression) != nil else { throw HDBConfigurationError.invalidData }
            let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian); formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "dd-MM-yyyy"; formatter.isLenient = false
            guard let parsed = formatter.date(from: date), formatter.string(from: parsed) == date else { throw HDBConfigurationError.invalidData }
        }
    }
}

struct HDBLightingField<Value: Codable & Equatable>: Codable, Equatable {
    var status: HDBSyncStatus
    var value: Value
}

/// Business targets and completion only. Transport ownership stays in the active session.
struct HDBLightingConfiguration: Codable, Equatable {
    var lightingControl: HDBLightingField<HDBLightingControl>?
    var failsafeDelay: HDBLightingField<Int>?
    var dimIntensity: HDBLightingField<Int>?
    var brightIntensity: HDBLightingField<Int>?
    var rampUpTime: HDBLightingField<Int>?
    var rampDownTime: HDBLightingField<Int>?
    var holdTime: HDBLightingField<Int>?
    var installDate: HDBLightingField<String>?

    static var defaults: Self {
        var result = Self(values: .defaults)
        result.failsafeDelay?.status = .synced
        return result
    }
    init(values: HDBLightingValues = .init(), status: HDBSyncStatus = .pending) {
        merge(values, status: status)
    }
    var values: HDBLightingValues {
        .init(lightingControl: lightingControl?.value, failsafeDelay: failsafeDelay?.value,
              dimIntensity: dimIntensity?.value, brightIntensity: brightIntensity?.value,
              rampUpTime: rampUpTime?.value, rampDownTime: rampDownTime?.value,
              holdTime: holdTime?.value, installDate: installDate?.value)
    }
    mutating func merge(_ values: HDBLightingValues, status: HDBSyncStatus) {
        if let value = values.lightingControl { lightingControl = .init(status: status, value: value) }
        if let value = values.failsafeDelay { failsafeDelay = .init(status: .synced, value: value) }
        if let value = values.dimIntensity { dimIntensity = .init(status: status, value: value) }
        if let value = values.brightIntensity { brightIntensity = .init(status: status, value: value) }
        if let value = values.rampUpTime { rampUpTime = .init(status: status, value: value) }
        if let value = values.rampDownTime { rampDownTime = .init(status: status, value: value) }
        if let value = values.holdTime { holdTime = .init(status: status, value: value) }
        if let value = values.installDate { installDate = .init(status: .synced, value: value) }
    }
    func status(field: String) -> HDBSyncStatus? {
        switch field {
        case "lightingControl": return lightingControl?.status
        case "failsafeDelay": return failsafeDelay?.status
        case "dimIntensity": return dimIntensity?.status
        case "brightIntensity": return brightIntensity?.status
        case "rampUpTime": return rampUpTime?.status
        case "rampDownTime": return rampDownTime?.status
        case "holdTime": return holdTime?.status
        case "installDate": return installDate?.status
        default: return nil
        }
    }
    mutating func mark(fields: [String], status: HDBSyncStatus) {
        for field in fields {
            switch field {
            case "lightingControl": lightingControl?.status = status
            case "failsafeDelay": failsafeDelay?.status = status
            case "dimIntensity": dimIntensity?.status = status
            case "brightIntensity": brightIntensity?.status = status
            case "rampUpTime": rampUpTime?.status = status
            case "rampDownTime": rampDownTime?.status = status
            case "holdTime": holdTime?.status = status
            case "installDate": installDate?.status = status
            default: break
            }
        }
    }
    func status(for command: HDBLightingCommand) -> HDBSyncStatus? {
        let states = values.selected(command).fieldNames.compactMap { status(field: $0) }
        return states.isEmpty ? nil : (states.contains(.pending) ? .pending : .synced)
    }
}


/// Command metadata is derived from the enclosing device snapshot. Decoding
/// validates it before discarding the redundant representation; comparison must
/// never repair missing or altered cloud fields into a successful receipt.
extension HDBLightingConfiguration {
    private struct FieldKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
    private enum MetadataKey: String, CodingKey, CaseIterable {
        case elementAddress, modelId, property, mapValues, models, value
        case auto = "Auto", forceOn = "Force_On", forceOff = "Force_Off"
    }

    func encode(to encoder: Encoder, models: [HDBModelTarget], primaryAddress: UInt16) throws {
        try values.validate()
        var fields = encoder.container(keyedBy: FieldKey.self)
        for name in values.fieldNames {
            let field = fields.superEncoder(forKey: FieldKey(name))
            // Business values and derived metadata share one field container.
            switch name {
            case "lightingControl": try lightingControl.encode(to: field)
            case "failsafeDelay": try failsafeDelay.encode(to: field)
            case "installDate": try installDate.encode(to: field)
            default:
                let property = HDBLightingProperty(rawValue: name)!
                try HDBLightingField(status: status(field: name)!, value: property.value(in: values)!).encode(to: field)
            }
            if name == "lightingControl" {
                var mappings = field.container(keyedBy: FieldKey.self)
                for control in HDBLightingControl.allCases {
                    let address = control.write.target(in: models, primaryAddress: primaryAddress)?.elementAddress
                    try mappings.encode(address.map(HDBHexUInt16.init), forKey: FieldKey(control.rawValue))
                }
            } else if let property = HDBLightingProperty(rawValue: name) {
                var metadata = field.container(keyedBy: MetadataKey.self)
                let write = HDBLightingWrite.property(property.identifier, 0)
                let address = write.target(in: models, primaryAddress: primaryAddress)?.elementAddress
                try metadata.encode(address.map(HDBHexUInt16.init), forKey: .elementAddress)
                try metadata.encode(HDBHexUInt16(write.modelIdentifier), forKey: .modelId)
                try metadata.encode(HDBHexUInt16(property.identifier), forKey: .property)
            }
        }
    }

    static func decode(from decoder: Decoder, models: [HDBModelTarget], primaryAddress: UInt16) throws -> Self {
        let result = try Self(from: decoder)
        try result.values.validate()
        let fields = try decoder.container(keyedBy: FieldKey.self)
        for name in result.values.fieldNames {
            let field = try fields.superDecoder(forKey: FieldKey(name))
            let metadata = try field.container(keyedBy: MetadataKey.self)
            if name == "lightingControl" {
                let mappings = try field.container(keyedBy: FieldKey.self)
                let required = Set(HDBLightingControl.allCases.map(\.rawValue)).union(["status", "value"])
                guard Set(mappings.allKeys.map(\.stringValue)) == required else { throw HDBConfigurationError.invalidData }
                for control in HDBLightingControl.allCases {
                    guard try mappings.decodeIfPresent(HDBHexUInt16.self, forKey: FieldKey(control.rawValue))?.value
                        == control.write.target(in: models, primaryAddress: primaryAddress)?.elementAddress else { throw HDBConfigurationError.invalidData }
                }
            } else if let property = HDBLightingProperty(rawValue: name) {
                try reject([.mapValues, .models, .auto, .forceOn, .forceOff], in: metadata)
                let write = HDBLightingWrite.property(property.identifier, 0)
                guard metadata.contains(.elementAddress),
                      try metadata.decodeIfPresent(HDBHexUInt16.self, forKey: .elementAddress)?.value == write.target(in: models, primaryAddress: primaryAddress)?.elementAddress,
                      try metadata.decode(HDBHexUInt16.self, forKey: .modelId).value == write.modelIdentifier,
                      try metadata.decode(HDBHexUInt16.self, forKey: .property).value == property.identifier else { throw HDBConfigurationError.invalidData }
            } else {
                try reject(MetadataKey.allCases.filter { $0 != .value }, in: metadata)
            }
        }
        return result
    }

    private static func reject(_ keys: [MetadataKey], in container: KeyedDecodingContainer<MetadataKey>) throws {
        guard !keys.contains(where: container.contains) else { throw HDBConfigurationError.invalidData }
    }
}
