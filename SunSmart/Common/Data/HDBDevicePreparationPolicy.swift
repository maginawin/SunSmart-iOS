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
                     publicationTargets: [HDBModelTarget]) throws -> HDBDevicePreparationPlan {
        let base = try HDBLightingZonePolicy.requiredTargets(from: targets)
        let sensorServers = Array(Set(targets.filter {
            $0.companyIdentifier == nil && $0.modelIdentifier == 0x1100
        })).sorted { $0.elementAddress < $1.elementAddress }
        let hasSensor = !sensorServers.isEmpty
        if (hasSensor || !publicationTargets.isEmpty) && sensorGroupId == nil { throw HDBConfigurationError.addressUnavailable }
        if let address = sensorGroupId, !(0xC001..<0xFEFD).contains(Int(address)) { throw HDBConfigurationError.invalidData }
        let sensors = Array(Set(publicationTargets)).sorted { $0.elementAddress < $1.elementAddress }
        guard sensors.allSatisfy({ $0.modelId == 0x1100 }) else { throw HDBConfigurationError.unsupportedModels }
        return .init(nodeUuid: nodeUuid, nodeAddress: nodeAddress, appKeyIndex: appKeyIndex,
            baseTargets: base.map { .init(model: $0) }, sensorGroupId: sensorGroupId,
            publicationTargets: sensors,
            subscriptionTargets: hasSensor && sensorGroupId != nil
                ? base.filter { $0.modelId == 0x130F } + sensorServers : [])
    }
}
