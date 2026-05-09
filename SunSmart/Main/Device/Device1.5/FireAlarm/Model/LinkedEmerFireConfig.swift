//
//  LinkedEmerFireConfig.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import Foundation
import NordicSigMeshSDK

enum EmergencyFireControllerWorkMode: String, Codable, Equatable {
    case powerLossEmergency
    case fireAlarmEmergency
    case allDisabled

    var vendorMode: EmergencyControllerMode {
        switch self {
        case .powerLossEmergency:
            return .emergency
        case .fireAlarmEmergency:
            return .fire
        case .allDisabled:
            return .disabled
        }
    }
}

struct EmergencyFireControllerModeSettings: Codable, Equatable {
    var associateGroupAddresses: [UInt16]
    var triggerBrightness: Int
    var triggerIntervalSeconds: UInt16
    var triggerCount: UInt16
    var stopIntervalSeconds: UInt16
    var stopCount: UInt16
    var restoreDelaySeconds: UInt8
    var pendingUnassociateGroupAddresses: [UInt16]
    var pendingStopSceneRewriteGroupAddresses: [UInt16]

    private enum CodingKeys: String, CodingKey {
        case associateGroupAddresses
        case triggerBrightness
        case triggerIntervalSeconds
        case triggerCount
        case stopIntervalSeconds
        case stopCount
        case restoreDelaySeconds
        case pendingUnassociateGroupAddresses
        case pendingStopSceneRewriteGroupAddresses
    }

    static let defaultValue = EmergencyFireControllerModeSettings(
        associateGroupAddresses: [],
        triggerBrightness: 100,
        triggerIntervalSeconds: 5,
        triggerCount: 0xFFFF,
        stopIntervalSeconds: 5,
        stopCount: 2,
        restoreDelaySeconds: 2,
        pendingUnassociateGroupAddresses: [],
        pendingStopSceneRewriteGroupAddresses: []
    )

    init(
        associateGroupAddresses: [UInt16],
        triggerBrightness: Int,
        triggerIntervalSeconds: UInt16,
        triggerCount: UInt16,
        stopIntervalSeconds: UInt16,
        stopCount: UInt16,
        restoreDelaySeconds: UInt8,
        pendingUnassociateGroupAddresses: [UInt16],
        pendingStopSceneRewriteGroupAddresses: [UInt16]
    ) {
        self.associateGroupAddresses = associateGroupAddresses
        self.triggerBrightness = triggerBrightness
        self.triggerIntervalSeconds = triggerIntervalSeconds
        self.triggerCount = triggerCount
        self.stopIntervalSeconds = stopIntervalSeconds
        self.stopCount = stopCount
        self.restoreDelaySeconds = restoreDelaySeconds
        self.pendingUnassociateGroupAddresses = pendingUnassociateGroupAddresses
        self.pendingStopSceneRewriteGroupAddresses = pendingStopSceneRewriteGroupAddresses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Self.defaultValue
        associateGroupAddresses = try container.decodeIfPresent([UInt16].self, forKey: .associateGroupAddresses) ?? defaults.associateGroupAddresses
        triggerBrightness = try container.decodeIfPresent(Int.self, forKey: .triggerBrightness) ?? defaults.triggerBrightness
        triggerIntervalSeconds = try container.decodeIfPresent(UInt16.self, forKey: .triggerIntervalSeconds) ?? defaults.triggerIntervalSeconds
        triggerCount = try container.decodeIfPresent(UInt16.self, forKey: .triggerCount) ?? defaults.triggerCount
        stopIntervalSeconds = try container.decodeIfPresent(UInt16.self, forKey: .stopIntervalSeconds) ?? defaults.stopIntervalSeconds
        stopCount = try container.decodeIfPresent(UInt16.self, forKey: .stopCount) ?? defaults.stopCount
        restoreDelaySeconds = try container.decodeIfPresent(UInt8.self, forKey: .restoreDelaySeconds) ?? defaults.restoreDelaySeconds
        pendingUnassociateGroupAddresses = try container.decodeIfPresent([UInt16].self, forKey: .pendingUnassociateGroupAddresses) ?? []
        pendingStopSceneRewriteGroupAddresses = try container.decodeIfPresent([UInt16].self, forKey: .pendingStopSceneRewriteGroupAddresses) ?? []
    }
}

struct EmergencyFireControllerConfiguration: Codable, Equatable {
    var workMode: EmergencyFireControllerWorkMode
    var powerLossSettings: EmergencyFireControllerModeSettings
    var fireAlarmSettings: EmergencyFireControllerModeSettings

    static let defaultValue = EmergencyFireControllerConfiguration(
        workMode: .powerLossEmergency,
        powerLossSettings: .defaultValue,
        fireAlarmSettings: .defaultValue
    )
}

struct LinkedEmerFireConfig {
    var deviceId: String?
    var spaceId: String?
    var meshUUID: String?
    var meshNetworkId: String?
    var deviceName: String
    var isSynced: Bool
    var reportToGateway: Bool
    var publishGroupAddress: Address?
    var configuration: EmergencyFireControllerConfiguration
}

extension Notification.Name {
    static let linkedEmerFireConfigDidChange = Notification.Name("linkedEmerFireConfigDidChange")
}
