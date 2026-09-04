//
//  EnergyStatisticsFilterPolicy.swift
//  SunSmart
//
//  Created on 2026/9/4.
//

enum EnergyMeteringType: String, Codable {
    case truePowerMeter
    case manualDataEntry
}

enum EnergyStatisticsFilter {
    case all
    case truePowerMeter
    case manualDataEntry
}

struct EnergyStatisticsFilterPolicy {

    private static let truePowerMeterProductIdentifiers: Set<UInt16> = [
        0x2302, 0x2303, 0x2304, 0x2305, 0x2801, 0x2802
    ]

    static func supportsTruePowerMeter(productIdentifier: UInt16?) -> Bool {
        guard let productIdentifier else {
            return false
        }
        return truePowerMeterProductIdentifiers.contains(productIdentifier)
    }

    static func meteringType(
        productIdentifier: UInt16?,
        supportsTruePowerMeter: Bool? = nil
    ) -> EnergyMeteringType {
        let isTruePowerMeter = supportsTruePowerMeter
            ?? self.supportsTruePowerMeter(productIdentifier: productIdentifier)
        return isTruePowerMeter ? .truePowerMeter : .manualDataEntry
    }

    static func includes(
        meteringType: EnergyMeteringType,
        filter: EnergyStatisticsFilter
    ) -> Bool {
        switch filter {
        case .all:
            return true
        case .truePowerMeter:
            return meteringType == .truePowerMeter
        case .manualDataEntry:
            return meteringType == .manualDataEntry
        }
    }

    static func filter<Value>(
        _ values: [Value],
        by filter: EnergyStatisticsFilter,
        meteringType: (Value) -> EnergyMeteringType
    ) -> [Value] {
        values.filter {
            includes(meteringType: meteringType($0), filter: filter)
        }
    }
}
