import Foundation

enum HDBSyncStatus: String, Codable { case pending, synced }

struct HDBConfiguration: Codable, Equatable {
    var schemaVersion = 1
    var lightingZones: [HDBLightingZone] = []
    var devices: [HDBDeviceConfiguration] = []
    var allGroupAddresses: Set<UInt16> {
        Set(lightingZones.map(\.groupAddress)).union(devices.compactMap(\.sensorGroupId))
    }
}

struct HDBLightingZone: Codable, Equatable {
    var zoneId: Int
    var name: String
    var groupAddress: UInt16
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

    /// Accept the existing Node/scanner formats, but persist one canonical HDB value.
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
        nodeAddress = try c.decode(UInt16.self, forKey: .nodeAddress)
        mac = try c.decode(String.self, forKey: .mac)
        guard mac == (try Self.normalizedMAC(mac)) else { throw HDBConfigurationError.invalidMAC }
        lightingZones = try c.decode([HDBZoneMembership].self, forKey: .lightingZones)
        lightingZonesStatus = try c.decode(HDBSyncStatus.self, forKey: .lightingZonesStatus)
        guard c.contains(.sensorGroupId) else { throw HDBConfigurationError.invalidData }
        sensorGroupId = try c.decodeIfPresent(UInt16.self, forKey: .sensorGroupId)
        zoneModels = HDBModelReference.normalized(try c.decode([HDBModelReference].self, forKey: .zoneModels))
        sensorGroupModels = HDBModelReference.normalized(try c.decode([HDBModelReference].self, forKey: .sensorGroupModels))
        broadcastModels = HDBModelReference.normalized(try c.decode([HDBModelReference].self, forKey: .broadcastModels))
        broadcastId = try c.decode(UInt16.self, forKey: .broadcastId)
        guard broadcastId == 0xFEFD else { throw HDBConfigurationError.invalidData }
        lightingConfiguration = try c.decodeIfPresent(HDBLightingConfiguration.self, forKey: .lightingConfiguration)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nodeUuid, forKey: .nodeUuid); try c.encode(nodeAddress, forKey: .nodeAddress)
        try c.encode(mac, forKey: .mac)
        try c.encode(lightingZones, forKey: .lightingZones)
        try c.encode(lightingZonesStatus, forKey: .lightingZonesStatus)
        try c.encode(sensorGroupId, forKey: .sensorGroupId)
        try c.encode(HDBModelReference.normalized(zoneModels), forKey: .zoneModels)
        try c.encode(HDBModelReference.normalized(sensorGroupModels), forKey: .sensorGroupModels)
        try c.encode(HDBModelReference.normalized(broadcastModels), forKey: .broadcastModels)
        try c.encode(broadcastId, forKey: .broadcastId)
        try c.encode(lightingConfiguration, forKey: .lightingConfiguration)
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

/// Numeric wire representation for the HDB device metadata. Internal preparation
/// targets retain their existing hexadecimal encoding and initialization signature.
struct HDBModelReference: Codable, Hashable {
    let elementAddress: UInt16
    let modelId: UInt32

    init(_ target: HDBModelTarget) { elementAddress = target.elementAddress; modelId = target.modelId }

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

enum HDBLightingControl: String, Codable, CaseIterable { case auto = "Auto", forceOn = "Force_On", forceOff = "Force_Off" }

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
