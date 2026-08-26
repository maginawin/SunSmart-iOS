//
//  LabSettings.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

enum LabSettings {

    private static let displayLightAckDetailsKey = "lab_display_light_ack_details"
    private static let overrideOutgoingMeshTTLKey = "lab_override_light_group_control_ttl"
    private static let outgoingMeshTTLKey = "lab_light_group_control_ttl"
    private static let defaultOutgoingMeshTTL = 5

    static var displayLightAckDetails: Bool {
        get {
            UserDefaults.standard.bool(forKey: displayLightAckDetailsKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: displayLightAckDetailsKey)
            UserDefaults.standard.synchronize()
        }
    }

    static var overrideOutgoingMeshTTL: Bool {
        get {
            UserDefaults.standard.bool(forKey: overrideOutgoingMeshTTLKey)
        }
        set {
            UserDefaults.standard.set(newValue, forKey: overrideOutgoingMeshTTLKey)
            UserDefaults.standard.synchronize()
            applyOutgoingMeshTTLOverride()
        }
    }

    static var outgoingMeshTTL: UInt8 {
        get {
            guard UserDefaults.standard.object(forKey: outgoingMeshTTLKey) != nil else {
                return UInt8(defaultOutgoingMeshTTL)
            }
            let value = UserDefaults.standard.integer(forKey: outgoingMeshTTLKey)
            return UInt8(min(max(value, 0), 127))
        }
        set {
            let value = min(max(Int(newValue), 0), 127)
            UserDefaults.standard.set(value, forKey: outgoingMeshTTLKey)
            UserDefaults.standard.synchronize()
            applyOutgoingMeshTTLOverride()
        }
    }

    static var outgoingMeshTTLOverride: UInt8? {
        guard overrideOutgoingMeshTTL else {
            return nil
        }
        return outgoingMeshTTL
    }

    static func applyOutgoingMeshTTLOverride() {
        try? MeshNetworkManager.setOutgoingAccessMessageTtlOverride(outgoingMeshTTLOverride)
    }
}
