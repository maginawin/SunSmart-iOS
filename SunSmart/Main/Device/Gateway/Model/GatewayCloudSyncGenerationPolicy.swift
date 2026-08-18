//
//  GatewayCloudSyncGenerationPolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/13.
//

import Foundation

enum GatewayCloudSyncGenerationPolicy {
    static func next(
        now: Int64,
        current: Int64,
        uploaded: Int64?
    ) -> Int64 {
        max(now, current + 1, (uploaded ?? 0) + 1)
    }

    static func confirmed(
        previous: Int64?,
        submitted: Int64
    ) -> Int64 {
        max(previous ?? 0, submitted)
    }

    static func needsAnotherUpload(
        current: Int64,
        confirmed: Int64?
    ) -> Bool {
        current > (confirmed ?? 0)
    }
}

enum GatewayCloudSnapshotMergeDecision: Equatable {
    case importNew
    case preserveLocal
    case replaceRemote
    case mergeFields
}

enum GatewayCloudSnapshotMergePolicy {

    static func resolve(
        hasLocalGateway: Bool,
        localNeedsUpload: Bool,
        uploadInProgress: Bool,
        deletionInProgress: Bool,
        identityChanged: Bool,
        remoteUpdateTimestamp: Int64?,
        localUpdateTimestamp: Int64
    ) -> GatewayCloudSnapshotMergeDecision {
        guard hasLocalGateway else {
            return .importNew
        }
        guard !localNeedsUpload,
              !uploadInProgress,
              !deletionInProgress else {
            return .preserveLocal
        }
        if identityChanged {
            return .replaceRemote
        }
        if let remoteUpdateTimestamp,
           remoteUpdateTimestamp > localUpdateTimestamp {
            return .replaceRemote
        }
        return .mergeFields
    }

    static func identityChanged(
        localUUID: String?,
        localAddress: UInt16?,
        localDeviceKey: String?,
        remoteUUID: String?,
        remoteAddress: UInt16?,
        remoteDeviceKey: String?
    ) -> Bool {
        if let localUUID = normalized(localUUID),
           let remoteUUID = normalized(remoteUUID),
           localUUID != remoteUUID {
            return true
        }
        if let localAddress,
           let remoteAddress,
           localAddress != remoteAddress {
            return true
        }
        if let localDeviceKey = normalized(localDeviceKey),
           let remoteDeviceKey = normalized(remoteDeviceKey),
           localDeviceKey != remoteDeviceKey {
            return true
        }
        return false
    }

    static func canUpdateRegistrationSnapshot(
        decision: GatewayCloudSnapshotMergeDecision,
        identityChanged: Bool
    ) -> Bool {
        !(decision == .preserveLocal && identityChanged)
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return normalized.isEmpty ? nil : normalized
    }
}

struct GatewayRegistrationProtectionSnapshot: Equatable {

    private static let protectedSectionKeys = [
        "netKeys",
        "appKeys",
        "elements"
    ]

    let data: Data

    var nodeData: [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any] else {
            return [:]
        }
        return dictionary
    }

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
              let dictionary = object as? [String: Any],
              let sanitizedData = Self.sanitizedData(from: dictionary) else {
            return nil
        }
        self.data = sanitizedData
    }

    private init?(nodeData: [String: Any]) {
        guard let data = Self.sanitizedData(from: nodeData) else {
            return nil
        }
        self.data = data
    }

    static func updating(
        current: GatewayRegistrationProtectionSnapshot?,
        remoteNode: [String: Any],
        resetExisting: Bool,
        responseIsComplete: Bool
    ) -> GatewayRegistrationProtectionSnapshot? {
        var result = resetExisting ? [:] : current?.nodeData ?? [:]
        for key in protectedSectionKeys {
            guard remoteNode.keys.contains(key),
                  let section = dictionaries(remoteNode[key]) else {
                continue
            }
            if responseIsComplete || resetExisting {
                result[key] = section
            } else if key == "elements" {
                result[key] = mergeElements(
                    current: dictionaries(result[key]) ?? [],
                    remote: section
                )
            } else {
                result[key] = mergeIndexedDictionaries(
                    current: dictionaries(result[key]) ?? [],
                    remote: section
                )
            }
        }
        return GatewayRegistrationProtectionSnapshot(nodeData: result)
    }

    private static func mergeIndexedDictionaries(
        current: [[String: Any]],
        remote: [[String: Any]]
    ) -> [[String: Any]] {
        var valuesByIndex: [Int: [String: Any]] = [:]
        current.forEach { value in
            guard let index = integer(value["index"]) else { return }
            valuesByIndex[index] = value
        }
        remote.forEach { value in
            guard let index = integer(value["index"]) else { return }
            valuesByIndex[index] = value
        }
        return valuesByIndex.keys.sorted().compactMap { valuesByIndex[$0] }
    }

    private static func mergeElements(
        current: [[String: Any]],
        remote: [[String: Any]]
    ) -> [[String: Any]] {
        var elementsByIndex: [Int: [String: Any]] = [:]
        current.forEach { element in
            guard let index = integer(element["index"]) else { return }
            elementsByIndex[index] = element
        }
        remote.forEach { remoteElement in
            guard let index = integer(remoteElement["index"]) else { return }
            var element = elementsByIndex[index] ?? [:]
            remoteElement.forEach { element[$0.key] = $0.value }

            let currentModels = dictionaries(
                elementsByIndex[index]?["models"]
            ) ?? []
            let remoteModels = dictionaries(remoteElement["models"]) ?? []
            var modelsByID: [String: [String: Any]] = [:]
            currentModels.forEach { model in
                guard let modelID = model["modelId"] as? String else { return }
                modelsByID[modelID.uppercased()] = model
            }
            remoteModels.forEach { remoteModel in
                guard let modelID = remoteModel["modelId"] as? String else {
                    return
                }
                let key = modelID.uppercased()
                let currentModel = modelsByID[key]
                var model = currentModel ?? [:]
                remoteModel.forEach { model[$0.key] = $0.value }
                if remoteModel.keys.contains("bind"),
                   let remoteBinds = integers(remoteModel["bind"]) {
                    model["bind"] = Array(
                        Set(integers(currentModel?["bind"]) ?? [])
                            .union(remoteBinds)
                    ).sorted()
                }
                modelsByID[key] = model
            }
            if !currentModels.isEmpty || !remoteModels.isEmpty {
                element["models"] = modelsByID.keys.sorted().compactMap {
                    modelsByID[$0]
                }
            }
            elementsByIndex[index] = element
        }
        return elementsByIndex.keys.sorted().compactMap { elementsByIndex[$0] }
    }

    private static func sanitizedData(from nodeData: [String: Any]) -> Data? {
        var sanitized: [String: Any] = [:]
        for key in protectedSectionKeys {
            guard let section = dictionaries(nodeData[key]) else { continue }
            sanitized[key] = section
        }
        guard !sanitized.isEmpty,
              JSONSerialization.isValidJSONObject(sanitized) else {
            return nil
        }
        return try? JSONSerialization.data(
            withJSONObject: sanitized,
            options: [.sortedKeys]
        )
    }

    private static func dictionaries(_ value: Any?) -> [[String: Any]]? {
        guard let values = value as? [Any] else { return nil }
        var dictionaries: [[String: Any]] = []
        for value in values {
            guard let dictionary = value as? [String: Any] else { return nil }
            dictionaries.append(dictionary)
        }
        return dictionaries
    }

    private static func integers(_ value: Any?) -> [Int]? {
        guard let values = value as? [Any] else { return nil }
        var integers: [Int] = []
        for value in values {
            guard let integer = integer(value) else { return nil }
            integers.append(integer)
        }
        return integers
    }

    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let integer = number.intValue
        guard number.doubleValue == Double(integer) else { return nil }
        return integer
    }
}

enum GatewayCloudPatchField<Value> {
    case absent
    case clear
    case value(Value)
}

struct GatewayCloudAssociatedSpace: Equatable {
    let spaceId: String
    let spaceName: String
    let deviceCount: Int
    let appKeyIndex: UInt16
}

enum GatewayCloudAssociatedSpaceMergePolicy {
    static func resolve(
        local: [GatewayCloudAssociatedSpace],
        remote: [GatewayCloudAssociatedSpace],
        responseIsComplete: Bool
    ) -> [GatewayCloudAssociatedSpace] {
        guard !responseIsComplete else { return remote }
        var result = local
        for remoteSpace in remote {
            if let index = result.firstIndex(where: {
                $0.spaceId.caseInsensitiveCompare(remoteSpace.spaceId) ==
                    .orderedSame
            }) {
                result[index] = remoteSpace
            } else {
                result.append(remoteSpace)
            }
        }
        return result
    }
}

struct GatewayCloudMQTTConnectInfo: Equatable {
    let serverAddress: String
    let userName: String?
    let password: String?
    let clientId: String
    let keepalive: UInt16
    let clearSession: Bool
    let authMode: UInt8
    let sslVersion: UInt8
}

struct GatewayCloudConfigurationPatch {
    let name: GatewayCloudPatchField<String>
    let activate: GatewayCloudPatchField<Bool>
    let associatedSpaces: GatewayCloudPatchField<[GatewayCloudAssociatedSpace]>
    let apn: GatewayCloudPatchField<String>
    let mqttConnectInfo: GatewayCloudPatchField<GatewayCloudMQTTConnectInfo>

    init(nodePayload: [String: Any]) {
        name = Self.stringField(key: "name", in: nodePayload)
        guard let preconfigured = nodePayload["gatewayPreconfigured"] as? [String: Any] else {
            activate = .absent
            associatedSpaces = .absent
            apn = .absent
            mqttConnectInfo = .absent
            return
        }
        activate = Self.boolField(key: "activate", in: preconfigured)
        associatedSpaces = Self.associatedSpacesField(in: preconfigured)
        apn = Self.stringField(key: "apn", in: preconfigured)
        mqttConnectInfo = Self.mqttField(in: preconfigured)
    }

    private static func stringField(
        key: String,
        in dictionary: [String: Any]
    ) -> GatewayCloudPatchField<String> {
        guard dictionary.keys.contains(key) else { return .absent }
        let rawValue = dictionary[key]
        if rawValue is NSNull { return .clear }
        guard let value = rawValue as? String else { return .absent }
        return .value(value)
    }

    private static func boolField(
        key: String,
        in dictionary: [String: Any]
    ) -> GatewayCloudPatchField<Bool> {
        guard dictionary.keys.contains(key) else { return .absent }
        let rawValue = dictionary[key]
        if rawValue is NSNull { return .clear }
        guard let value = bool(rawValue) else { return .absent }
        return .value(value)
    }

    private static func associatedSpacesField(
        in dictionary: [String: Any]
    ) -> GatewayCloudPatchField<[GatewayCloudAssociatedSpace]> {
        let key = "associatedSpaces"
        guard dictionary.keys.contains(key) else { return .absent }
        let rawValue = dictionary[key]
        if rawValue is NSNull { return .clear }
        guard let values = rawValue as? [Any] else { return .absent }
        var spaces: [GatewayCloudAssociatedSpace] = []
        for value in values {
            guard let space = value as? [String: Any],
                  let spaceId = space["spaceId"] as? String,
                  let spaceName = space["spaceName"] as? String,
                  let deviceCount = integer(space["deviceCount"]),
                  let appKeyIndexValue = integer(space["appKeyIndex"]),
                  let appKeyIndex = UInt16(exactly: appKeyIndexValue) else {
                return .absent
            }
            spaces.append(
                GatewayCloudAssociatedSpace(
                    spaceId: spaceId,
                    spaceName: spaceName,
                    deviceCount: deviceCount,
                    appKeyIndex: appKeyIndex
                )
            )
        }
        return .value(spaces)
    }

    private static func mqttField(
        in dictionary: [String: Any]
    ) -> GatewayCloudPatchField<GatewayCloudMQTTConnectInfo> {
        let key = "mqttConnectInfo"
        guard dictionary.keys.contains(key) else { return .absent }
        let rawValue = dictionary[key]
        if rawValue is NSNull { return .clear }
        guard let mqtt = rawValue as? [String: Any],
              let serverAddress = mqtt["serverAddress"] as? String,
              let clientId = mqtt["clientId"] as? String else {
            return .absent
        }

        let userName: String?
        if mqtt.keys.contains("userName") {
            guard mqtt["userName"] is NSNull || mqtt["userName"] is String else {
                return .absent
            }
            userName = mqtt["userName"] as? String
        } else {
            userName = nil
        }

        let password: String?
        if mqtt.keys.contains("password") {
            guard mqtt["password"] is NSNull || mqtt["password"] is String else {
                return .absent
            }
            password = mqtt["password"] as? String
        } else {
            password = nil
        }

        guard let keepalive = optionalUInt16(
            mqtt["keepalive"],
            defaultValue: 60
        ),
        let clearSession = optionalBool(
            mqtt["clearSession"],
            defaultValue: true
        ),
        let authMode = optionalUInt8(
            mqtt["authMode"],
            defaultValue: 0
        ),
        let sslVersion = optionalUInt8(
            mqtt["sslVersion"],
            defaultValue: 4
        ) else {
            return .absent
        }

        return .value(
            GatewayCloudMQTTConnectInfo(
                serverAddress: serverAddress,
                userName: userName,
                password: password,
                clientId: clientId,
                keepalive: keepalive,
                clearSession: clearSession,
                authMode: authMode,
                sslVersion: sslVersion
            )
        )
    }

    private static func optionalUInt16(
        _ rawValue: Any?,
        defaultValue: UInt16
    ) -> UInt16? {
        guard let rawValue else { return defaultValue }
        guard !(rawValue is NSNull),
              let value = integer(rawValue) else { return nil }
        return UInt16(exactly: value)
    }

    private static func optionalUInt8(
        _ rawValue: Any?,
        defaultValue: UInt8
    ) -> UInt8? {
        guard let rawValue else { return defaultValue }
        guard !(rawValue is NSNull),
              let value = integer(rawValue) else { return nil }
        return UInt8(exactly: value)
    }

    private static func optionalBool(
        _ rawValue: Any?,
        defaultValue: Bool
    ) -> Bool? {
        guard let rawValue else { return defaultValue }
        guard !(rawValue is NSNull) else { return nil }
        return bool(rawValue)
    }

    private static func bool(_ rawValue: Any?) -> Bool? {
        guard let number = rawValue as? NSNumber,
              CFGetTypeID(number) == CFBooleanGetTypeID() else {
            return nil
        }
        return number.boolValue
    }

    private static func integer(_ rawValue: Any?) -> Int? {
        guard let number = rawValue as? NSNumber,
              CFGetTypeID(number) != CFBooleanGetTypeID() else {
            return nil
        }
        let value = number.intValue
        guard number.doubleValue == Double(value) else { return nil }
        return value
    }
}

enum GatewayRegistrationPayloadPolicy {

    static func mergeOpaqueAssociationData(
        localNode: [String: Any],
        remoteNode: [String: Any]?,
        associatedAppKeyIndexes: [UInt16],
        isActivated: Bool
    ) -> [String: Any] {
        guard let remoteNode else { return localNode }

        let associatedIndexes = Set(associatedAppKeyIndexes.map(Int.init))
        let allowedKeyIndexes = associatedIndexes.union([0])
        var result = localNode
        result["netKeys"] = mergeIndexedDictionaries(
            local: localNode["netKeys"],
            remote: remoteNode["netKeys"],
            allowedIndexes: allowedKeyIndexes
        )
        result["appKeys"] = mergeIndexedDictionaries(
            local: localNode["appKeys"],
            remote: remoteNode["appKeys"],
            allowedIndexes: allowedKeyIndexes
        )
        result["elements"] = mergeElements(
            local: localNode["elements"],
            remote: remoteNode["elements"],
            allowedBindIndexes: allowedKeyIndexes
        )

        var gatewayInfo = dictionary(localNode["gatewayInfo"])
            ?? dictionary(remoteNode["gatewayInfo"])
            ?? [:]
        gatewayInfo["subnetAppkeyIndexs"] = isActivated
            ? associatedIndexes.sorted()
            : []
        result["gatewayInfo"] = gatewayInfo
        return result
    }

    private static func mergeIndexedDictionaries(
        local: Any?,
        remote: Any?,
        allowedIndexes: Set<Int>
    ) -> [[String: Any]] {
        let localValues = dictionaries(local)
        let remoteValues = dictionaries(remote)
        var valuesByIndex: [Int: [String: Any]] = [:]
        remoteValues.forEach { value in
            guard let index = int(value["index"]),
                  allowedIndexes.contains(index) else { return }
            valuesByIndex[index] = value
        }
        localValues.forEach { value in
            guard let index = int(value["index"]),
                  allowedIndexes.contains(index) else { return }
            valuesByIndex[index] = value
        }
        return valuesByIndex.keys.sorted().compactMap { valuesByIndex[$0] }
    }

    private static func mergeElements(
        local: Any?,
        remote: Any?,
        allowedBindIndexes: Set<Int>
    ) -> [[String: Any]] {
        let localElements = dictionaries(local)
        let remoteElements = dictionaries(remote)
        var elementsByIndex: [Int: [String: Any]] = [:]
        remoteElements.forEach { element in
            guard let index = int(element["index"]) else { return }
            elementsByIndex[index] = element
        }

        localElements.forEach { localElement in
            guard let elementIndex = int(localElement["index"]) else { return }
            var mergedElement = elementsByIndex[elementIndex] ?? localElement
            localElement.forEach { mergedElement[$0.key] = $0.value }

            let remoteModels = dictionaries(
                elementsByIndex[elementIndex]?["models"]
            )
            let localModels = dictionaries(localElement["models"])
            var modelsByID: [String: [String: Any]] = [:]
            remoteModels.forEach { model in
                guard let modelID = model["modelId"] as? String else { return }
                modelsByID[modelID.uppercased()] = model
            }
            localModels.forEach { localModel in
                guard let modelID = localModel["modelId"] as? String else {
                    return
                }
                let key = modelID.uppercased()
                let remoteModel = modelsByID[key]
                var mergedModel = remoteModel ?? localModel
                localModel.forEach { mergedModel[$0.key] = $0.value }
                let bindIndexes = Set(
                    ints(remoteModel?["bind"])
                        .union(ints(localModel["bind"]))
                        .filter(allowedBindIndexes.contains)
                )
                mergedModel["bind"] = bindIndexes.sorted()
                modelsByID[key] = mergedModel
            }
            mergedElement["models"] = modelsByID.keys.sorted().compactMap {
                modelsByID[$0]
            }
            elementsByIndex[elementIndex] = mergedElement
        }
        return elementsByIndex.keys.sorted().compactMap { elementsByIndex[$0] }
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        value as? [String: Any]
    }

    private static func dictionaries(_ value: Any?) -> [[String: Any]] {
        value as? [[String: Any]] ?? []
    }

    private static func ints(_ value: Any?) -> Set<Int> {
        guard let values = value as? [Any] else { return [] }
        return Set(values.compactMap(int))
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? UInt16 { return Int(value) }
        if let value = value as? NSNumber { return value.intValue }
        return nil
    }
}
