import Foundation

enum HDBLightingWrite: Equatable {
    case auto, off, lightness(UInt16), property(UInt16, UInt32)
    var fieldName: String {
        switch self {
        case .auto, .off, .lightness: return "lightingControl"
        case .property(let id, _):
            switch id {
            case 0x002F: return "dimIntensity"
            case 0x002E: return "brightIntensity"
            case 0x0037: return "rampUpTime"
            case 0x0036: return "rampDownTime"
            case 0x003C: return "holdTime"
            default: return ""
            }
        }
    }
    var modelIdentifier: UInt16 {
        switch self { case .auto: return 0x130F; case .off: return 0x1000; case .lightness: return 0x1300; case .property: return 0x1310 }
    }
}
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
            switch control { case .auto: result.append(.auto); case .forceOff: result.append(.off); case .forceOn: result.append(.lightness(65535)) }
        }
        if let dim = values.dimIntensity { result.append(.property(0x002F, UInt32(Double(dim) / 100 * 65535))) }
        if let bright = values.brightIntensity { result.append(.property(0x002E, UInt32(Double(bright) / 100 * 65535))) }
        if let up = values.rampUpTime { result.append(.property(0x0037, UInt32(up * 1000))) }
        if let down = values.rampDownTime { result.append(.property(0x0036, UInt32(down * 1000))) }
        if let hold = values.holdTime { result.append(.property(0x003C, UInt32(hold * 1000))) }
        return result
    }

    /// Force Off uses the primary OnOff; other commands retain all matching instances.
    static func targets(for write: HDBLightingWrite, recipient: HDBLightingRecipient) throws -> [HDBModelTarget] {
        let matching = recipient.targets.filter {
            $0.companyIdentifier == nil && $0.modelIdentifier == write.modelIdentifier
                && (write != .off || $0.elementAddress == recipient.nodeAddress)
        }
        guard !matching.isEmpty else { throw HDBConfigurationError.unsupportedModels }
        return matching
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
