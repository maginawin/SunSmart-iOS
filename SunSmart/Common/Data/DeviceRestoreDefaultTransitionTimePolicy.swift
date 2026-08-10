//
//  DeviceRestoreDefaultTransitionTimePolicy.swift
//  SunSmart
//
//  Created by One on 2026/8/10.
//

import Foundation

enum DeviceRestoreDefaultTransitionTimePolicy {
    static func pendingTargetRawValue(
        restoreTargetRawValue: UInt8?,
        currentRawValue: UInt8?,
        isSupported: Bool
    ) -> UInt8? {
        guard isSupported,
              let restoreTargetRawValue,
              restoreTargetRawValue & 0x3F != 0x3F,
              restoreTargetRawValue != currentRawValue else {
            return nil
        }
        return restoreTargetRawValue
    }

    static func shouldClearRestoreTarget(
        restoreTargetRawValue: UInt8?,
        successfulSetRawValue: UInt8
    ) -> Bool {
        guard let restoreTargetRawValue else {
            return false
        }
        return restoreTargetRawValue == successfulSetRawValue
    }
}
