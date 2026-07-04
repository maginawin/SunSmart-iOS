//
//  LightGroupControlCommandSender.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

enum LightGroupControlCommandSender {

    static var defaultTTL: UInt8? {
        LabSettings.lightGroupControlTTLOverride
    }

    private static var ttlOverride: UInt8? {
        LabSettings.lightGroupControlTTLOverride
    }

    static func setNodeOnOff(address: Address, isOn: Bool, ack: Bool = false) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              let model = node.onoffModel else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: GenericOnOffSet(isOn), model: model, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(isOn), model: model, defaultTTL: ttlOverride)
        }
    }

    static func setGroupOnOff(address: Address, isOn: Bool, ack: Bool = false) {
        guard address.isGroup else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: GenericOnOffSet(isOn), address: address, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(isOn), address: address, defaultTTL: ttlOverride)
        }
    }

    static func setAllOnOff(isOn: Bool, ack: Bool = false) {
        if ack {
            MeshAPI.sendMessage(message: GenericOnOffSet(isOn), address: .allNodes, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(isOn), address: .allNodes, defaultTTL: ttlOverride)
        }
    }

    static func setNodeLightness(address: Address, lightness: UInt16, ack: Bool = false) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              let model = node.lightnessModel else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightLightnessSet(lightness: lightness), model: model, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), model: model, defaultTTL: ttlOverride)
        }
    }

    static func setGroupLightness(address: Address, lightness: UInt16, ack: Bool = false) {
        guard address.isGroup else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightLightnessSet(lightness: lightness), address: address, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: address, defaultTTL: ttlOverride)
        }
    }

    static func setAllLightness(lightness: UInt16, ack: Bool = false) {
        if ack {
            MeshAPI.sendMessage(message: LightLightnessSet(lightness: lightness), address: .allNodes, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: .allNodes, defaultTTL: ttlOverride)
        }
    }

    static func setNodeColorTemperature(address: Address, temperature: UInt16, ack: Bool = false) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              let model = node.temperatureModel else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightCTLTemperatureSet(temperature: temperature, deltaUV: 0), model: model, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0), model: model, defaultTTL: ttlOverride)
        }
    }

    static func setGroupColorTemperature(address: Address, temperature: UInt16, ack: Bool = false) {
        guard address.isGroup else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightCTLTemperatureSet(temperature: temperature, deltaUV: 0), address: address, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0), address: address, defaultTTL: ttlOverride)
        }
    }

    static func identify(address: Address, attentionTimer: UInt8 = 5, ack: Bool = false) {
        let message: MeshMessage = ack ? AttentionSet(attentionTimer: attentionTimer) : AttentionSetUnacknowledged(attentionTimer: attentionTimer)

        if address.isUnicast,
           let model = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)?.healthModel {
            MeshAPI.sendMessage(message: message, model: model, defaultTTL: ttlOverride)
        } else {
            MeshAPI.sendMessage(message: message, address: address, defaultTTL: ttlOverride)
        }
    }

    static func sendVendorIdentify(_ message: SunricherVendorSet, model: Model) {
        MeshAPI.sendMessage(message: message, model: model, defaultTTL: ttlOverride)
    }
}
