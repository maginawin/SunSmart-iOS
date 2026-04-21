//
//  LinkedEmerFireConfig.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/4/21.
//

import Foundation
//模拟数据
struct LinkedEmerFireConfig {
    var deviceName: String
    var isSynced: Bool
    var reportToGateway: Bool
    var enablePowerLossEmergency: Bool
    var enableFireAlarmEmergency: Bool
    var powerLossGroupIndex: Int
    var fireAlarmGroupIndex: Int
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

final class LinkedEmerFireStore {

    static let shared = LinkedEmerFireStore()

    private(set) var currentConfig: LinkedEmerFireConfig?

    private init() {}

    func save(config: LinkedEmerFireConfig) {
        currentConfig = config
        NotificationCenter.default.post(name: .linkedEmerFireConfigDidChange, object: config)
    }
}
