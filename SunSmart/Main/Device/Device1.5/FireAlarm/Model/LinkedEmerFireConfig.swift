//
//  LinkedEmerFireConfig.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import Foundation
//模拟数据
struct LinkedEmerFireConfig {
    var deviceId: String?
    var spaceId: String?
    var meshUUID: String?
    var meshNetworkId: String?
    var deviceName: String
    var isSynced: Bool
    var reportToGateway: Bool
    var enablePowerLossEmergency: Bool
    var enableFireAlarmEmergency: Bool
    var powerLossGroupIndex: Int
    var fireAlarmGroupIndex: Int
    var powerLossGroupAddresses: [UInt16]
    var fireAlarmGroupAddresses: [UInt16]
    var powerLossBrightness: Int
    var powerLossResuming: Int
    var powerLossSendCount: Int
    var fireAlarmBrightness: Int
    var fireAlarmResuming: Int
    var fireAlarmSendCount: Int
}

extension Notification.Name {
    static let linkedEmerFireConfigDidChange = Notification.Name("linkedEmerFireConfigDidChange")
}
