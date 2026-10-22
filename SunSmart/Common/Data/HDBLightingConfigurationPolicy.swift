import Foundation

struct HDBLightingRecipient {
    let nodeUuid: UUID
    let nodeAddress: UInt16
    let targets: [HDBModelTarget]
}
struct HDBLightingDelivery: Equatable {
    let write: HDBLightingWrite
    let address: UInt16
    let nodeUuid: UUID
    let target: HDBModelTarget
}

enum HDBLightingConfigurationPolicy {
    static func writes(_ command: HDBLightingCommand, values: HDBLightingValues) throws -> [HDBLightingWrite] {
        let values = values.selected(command)
        try values.validate()
        guard values != HDBLightingValues() else { throw HDBConfigurationError.invalidData }
        var result: [HDBLightingWrite] = []
        if let control = values.lightingControl {
            result.append(control.write)
        }
        for property in HDBLightingProperty.allCases {
            if let value = property.value(in: values) {
                result.append(.property(property.identifier, property.rawValue(for: value)))
            }
        }
        return result
    }

    /// Select the same single instance described by the persisted command metadata.
    static func targets(for write: HDBLightingWrite, recipient: HDBLightingRecipient) throws -> [HDBModelTarget] {
        guard let target = write.target(in: recipient.targets, primaryAddress: recipient.nodeAddress) else {
            throw HDBConfigurationError.unsupportedModels
        }
        return [target]
    }

    static func route(_ writes: [HDBLightingWrite], recipient: HDBLightingRecipient) throws -> [HDBLightingDelivery] {
        try writes.flatMap { write in
            try targets(for: write, recipient: recipient).map { target in
                guard (1...0x7FFF).contains(Int(target.elementAddress)) else { throw HDBConfigurationError.invalidData }
                return HDBLightingDelivery(write: write, address: target.elementAddress,
                    nodeUuid: recipient.nodeUuid, target: target)
            }
        }
    }

    static func saved(nodeUuid: UUID, in config: HDBConfiguration) -> HDBLightingConfiguration? {
        config.devices.first { $0.nodeUuid == nodeUuid }?.lightingConfiguration
    }

    static func record(nodeUuid: UUID, command: HDBLightingCommand, values: HDBLightingValues,
                       status: HDBSyncStatus, in config: inout HDBConfiguration) throws {
        let selected = values.selected(command)
        try selected.validate()
        guard let index = config.devices.firstIndex(where: { $0.nodeUuid == nodeUuid }) else { throw HDBConfigurationError.unavailable }
        var next = config.devices[index].lightingConfiguration ?? HDBLightingConfiguration()
        next.merge(selected, status: status)
        config.devices[index].lightingConfiguration = next
    }
}
