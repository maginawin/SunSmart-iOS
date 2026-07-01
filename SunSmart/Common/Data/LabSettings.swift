//
//  LabSettings.swift
//  SunSmart
//

import Foundation

enum LabSettings {

    private static let displayLightAckDetailsKey = "lab_display_light_ack_details"

    static var displayLightAckDetails: Bool {
        get {
            UserDefaults.standard.bool(forKey: displayLightAckDetailsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayLightAckDetailsKey)
            UserDefaults.standard.synchronize()
        }
    }
}
