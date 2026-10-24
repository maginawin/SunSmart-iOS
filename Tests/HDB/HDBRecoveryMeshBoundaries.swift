import Foundation

// Object decoding/storage are boundaries. Model relationships and device factory
// below are injected from the mapped SDK and production App, not reimplemented.
final class RecoveryMeshModel: Hashable {
    let modelIdentifier: UInt16
    let companyIdentifier: UInt16?
    var modelId: UInt32 { UInt32(companyIdentifier ?? 0) << 16 | UInt32(modelIdentifier) }
    var isBluetoothSIGAssigned: Bool { companyIdentifier == nil }
    weak var parentElement: RecoveryMeshElement?
    init(_ id: UInt32) {
        modelIdentifier = UInt16(id & 0xFFFF)
        companyIdentifier = id > 0xFFFF ? UInt16(id >> 16) : nil
    }
    static func == (lhs: RecoveryMeshModel, rhs: RecoveryMeshModel) -> Bool { lhs === rhs }
    func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
    // SDK_MODEL_RELATIONSHIPS
}
final class RecoveryMeshElement: Equatable {
    let index: Int
    let unicastAddress: UInt16
    let models: [RecoveryMeshModel]
    weak var parentNode: RecoveryMeshNode?
    init(index: Int, address: UInt16, models: [RecoveryMeshModel]) {
        self.index = index; unicastAddress = address; self.models = models
        models.forEach { $0.parentElement = self }
    }
    func model(withSigModelId id: UInt16) -> RecoveryMeshModel? {
        models.first { $0.isBluetoothSIGAssigned && $0.modelIdentifier == id }
    }
    func contains(modelWithSigModelId id: UInt16) -> Bool { model(withSigModelId: id) != nil }
    static func == (lhs: RecoveryMeshElement, rhs: RecoveryMeshElement) -> Bool { lhs === rhs }
}
final class RecoveryMeshNode {
    let uuid: UUID
    let primaryUnicastAddress: UInt16
    let elements: [RecoveryMeshElement]
    var macAddress: String?
    struct SensorProperty { let id: UInt16 }
    var sensorModelTypes: [RecoveryMeshModel: SensorProperty] = [:]
    init(_ raw: [String: Any], mac: String) throws {
        guard let uuid = (raw["uuid"] as? String).flatMap(UUID.init(uuidString:)),
              let primary = (raw["unicastAddress"] as? String).flatMap({ UInt16($0, radix: 16) }) else {
            throw HDBConfigurationError.invalidData
        }
        self.uuid = uuid; primaryUnicastAddress = primary; macAddress = mac
        elements = try (raw["elements"] as? [[String: Any]] ?? []).map { element in
            guard let index = element["index"] as? Int,
                  let address = UInt16(exactly: Int(primary) + index),
                  let models = element["models"] as? [[String: Any]] else { throw HDBConfigurationError.invalidData }
            return try RecoveryMeshElement(index: index, address: address, models: models.map {
                guard let id = ($0["modelId"] as? String).flatMap({ UInt32($0, radix: 16) }) else { throw HDBConfigurationError.invalidData }
                return RecoveryMeshModel(id)
            })
        }
        elements.forEach { $0.parentNode = self }
    }
}
enum RecoveryMeshFactory {
    /// Credential-free reproduction of Space 2: v1 numeric addresses, nil MAC,
    /// absent model arrays, a separate CTL element and LC on element index 2.
    static func legacyPayload() -> [String: Any] {
        let uuid = "10000000-0000-0000-0000-00000000000B"
        let modelIDs = [["1000", "1002", "1006", "1300", "0A780001", "1100"],
                        ["1002", "1306", "1100"], ["1000", "130F", "1310"]]
        let node: [String: Any] = ["uuid": uuid, "unicastAddress": "000B", "macAddress": "AABBCCDDEEFF",
            "sensorTypes": ["004D", "004E"], "groupState": 0, "deviceKey": String(repeating: "A1", count: 16), "schedules": [],
            "elements": modelIDs.enumerated().map { ["index": $0.offset, "models": $0.element.map { ["modelId": $0, "subscribe": []] as [String: Any] }] }]
        let profile: [String: Any] = ["id": "synthetic-profile", "type": 1, "highEndTrim": 100,
            "lowEndTrim": 0, "occupancyLevel": 500, "vacantLevel": 100, "standbyLevel": 0,
            "taskLevel": 100, "timeT1": 2, "timeT2": 1200, "timeT3": 2, "timeT4": 600,
            "timeT5": 2, "manualOverrideTimeout": 600, "powerUpState": 255]
        var groups: [[String: Any]] = (1...63).map {
            ["address": String(format: "%04X", 0xC03F + $0), "isVirtual": false, "name": "Zone \($0)",
             "parentAddress": "0000", "profile": profile]
        }
        groups.append(["address": "C07F", "isVirtual": true, "name": "Sensor", "parentAddress": "0000"])
        let lighting: [String: Any] = ["lightingControl": ["value": "Auto", "status": "synced"],
            "failsafeDelay": ["value": 5, "status": "synced"], "dimIntensity": ["value": 20, "status": "synced"],
            "brightIntensity": ["value": 80, "status": "synced"], "rampUpTime": ["value": 1, "status": "synced"],
            "rampDownTime": ["value": 2, "status": "synced"], "holdTime": ["value": 30, "status": "synced"]]
        let hdb: [String: Any] = ["schemaVersion": 1, "broadcast": ["groupAddress": 0xFEFD],
            "lightingZones": (1...63).map { ["zoneId": $0, "name": "Zone \($0)", "groupAddress": 0xC03F + $0,
                "lightingConfiguration": lighting] },
            "devices": [["nodeUuid": uuid, "nodeAddress": 11, "mac": NSNull(), "sensorGroupId": 0xC07F,
                "lightingZones": [], "lightingZonesStatus": "synced", "lightingConfiguration": lighting]]]
        return ["nodes": [node], "groups": groups, "spaceData": ["hdb": hdb], "deviceCount": 1]
    }
    static func resolve(_ raw: [String: Any], _ mac: String) throws -> HDBDeviceConfiguration {
        try deviceConfiguration(node: RecoveryMeshNode(raw, mac: mac), sensorTypes: raw["sensorTypes"] as? [String] ?? [])
    }
    // APP_DEVICE_FACTORY
}
