//
//  LabSettings.swift
//  SunSmart
//

import Foundation

enum LabSettings {

    private static let displayLightAckDetailsKey = "lab_display_light_ack_details"
    private static let overrideLightGroupControlTTLKey = "lab_override_light_group_control_ttl"
    private static let lightGroupControlTTLKey = "lab_light_group_control_ttl"
    private static let defaultLightGroupControlTTL = 5

    static var displayLightAckDetails: Bool {
        get {
            UserDefaults.standard.bool(forKey: displayLightAckDetailsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayLightAckDetailsKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var overrideLightGroupControlTTL: Bool {
        get {
            UserDefaults.standard.bool(forKey: overrideLightGroupControlTTLKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: overrideLightGroupControlTTLKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var lightGroupControlTTL: UInt8 {
        get {
            guard UserDefaults.standard.object(forKey: lightGroupControlTTLKey) != nil else {
                return UInt8(defaultLightGroupControlTTL)
            }
            let value = UserDefaults.standard.integer(forKey: lightGroupControlTTLKey)
            return UInt8(min(max(value, 0), 127))
        }
        set {
            let value = min(max(Int(newValue), 0), 127)
            UserDefaults.standard.set(value, forKey: lightGroupControlTTLKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var lightGroupControlTTLOverride: UInt8? {
        guard overrideLightGroupControlTTL else {
            return nil
        }
        return lightGroupControlTTL
    }
}
