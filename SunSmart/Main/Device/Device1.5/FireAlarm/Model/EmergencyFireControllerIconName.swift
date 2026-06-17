//
//  EmergencyFireControllerIconName.swift
//  SunSmart
//
//  Created by Plato Jobs on 2026/5/7.
//

import NordicSigMeshSDK

enum EmergencyFireControllerIconName {
    enum Device {
        static let main = "emergency"
    }

    enum Monitor {
        enum Action {
            static let identify = "efc_identify"
            static let mockFireAlarm = "mock_fire_alarm"
            static let mockPowerLoss = "mock_power_loss"
            static let mockRestore = "mock_restore"
            static let powerLossTrigger = "yingjimoni"
            static let powerLossStop = "yingjimonitc"
            static let fireTrigger = "yjhjmn"
            static let fireStop = "yjhjstop"
        }

        enum StatusSet {
            static let powerLossEnabled = "yingjiduandianopen"
            static let powerLossDisabled = "sts1"
            static let powerLossActive = "sts2"
            static let fireEnabled = "huojingopen"
            static let fireDisabled = "sts3"
            static let fireActive = "sts5"
            static let inactive = "sts6"
            static let disabled = "sts4"
        }
    }

    static let main = Device.main

    static func addListIconName(for deviceType: Node.DeviceType, fallback: String) -> String {
        deviceType == .emergencyController ? Device.main : fallback
    }
}
