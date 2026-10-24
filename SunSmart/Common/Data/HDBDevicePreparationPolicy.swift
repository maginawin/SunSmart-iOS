import Foundation
import CryptoKit

enum HDBDevicePreparationPolicy {
    static func signature(_ plan: HDBDevicePreparationPlan, deviceKey: Data?, createdTimestamp: Int64) throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        var data = try encoder.encode(plan)
        data.append(deviceKey ?? Data())
        data.append(Data(String(createdTimestamp).utf8))
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func matchesConfigurationStatus(request: Data?, response: Data?, successful: Bool) -> Bool {
        guard successful, let request, let response, response.count == request.count + 1 else { return false }
        return response.dropFirst().elementsEqual(request)
    }

    static func plan(nodeUuid: UUID, nodeAddress: UInt16, appKeyIndex: UInt16,
                     targets: [HDBModelTarget], sensorGroupId: UInt16?,
                     publicationTargets: [HDBModelTarget],
                     sensorPublication: [HDBSensorPublication]) throws -> HDBDevicePreparationPlan {
        // Metadata and a skipped publication remain valid without full LC capability.
        // The initialization/Zone executor checks its own complete model requirements.
        let base = Set(targets.filter(HDBLightingZonePolicy.isZoneTarget)).sorted(by: HDBLightingZonePolicy.targetOrder)
        if let address = sensorGroupId, !(0xC001..<0xFEFD).contains(Int(address)) { throw HDBConfigurationError.invalidData }
        guard sensorPublication == (try HDBSensorPublication.expected(sensorGroupId: sensorGroupId,
            models: targets, publicationTargets: publicationTargets)) else {
            throw HDBConfigurationError.invalidData
        }
        let address = sensorPublication.first?.publishAddress
        let sensors = sensorPublication.map(\.target)
        guard sensors.allSatisfy({ $0.modelId == 0x1100 && targets.contains($0) }) else { throw HDBConfigurationError.unsupportedModels }
        return .init(nodeUuid: nodeUuid, nodeAddress: nodeAddress, appKeyIndex: appKeyIndex,
            baseTargets: base.map { .init(model: $0) }, sensorGroupId: sensorGroupId,
            publicationAddress: address, publicationTargets: address == nil ? [] : sensors)
    }
}
