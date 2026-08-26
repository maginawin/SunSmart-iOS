//
//  LightGroupControlCommandSender.swift
//  SunSmart
//

import Foundation
import NordicSigMeshSDK

enum LightGroupControlCommandSender {

    static func setNodeOnOff(address: Address, isOn: Bool, ack: Bool = false) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              let model = node.onoffModel else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: GenericOnOffSet(isOn), model: model)
        } else {
            MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(isOn), model: model)
        }
    }

    static func setGroupOnOff(address: Address, isOn: Bool, ack: Bool = false) {
        guard address.isGroup else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: GenericOnOffSet(isOn), address: address)
        } else {
            MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(isOn), address: address)
        }
    }

    static func setAllOnOff(isOn: Bool, ack: Bool = false) {
        if ack {
            MeshAPI.sendMessage(message: GenericOnOffSet(isOn), address: .allNodes)
        } else {
            MeshAPI.sendMessage(message: GenericOnOffSetUnacknowledged(isOn), address: .allNodes)
        }
    }

    static func setNodeLightness(address: Address, lightness: UInt16, ack: Bool = false) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              let model = node.lightnessModel else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightLightnessSet(lightness: lightness), model: model)
        } else {
            MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), model: model)
        }
    }

    static func setGroupLightness(address: Address, lightness: UInt16, ack: Bool = false) {
        guard address.isGroup else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightLightnessSet(lightness: lightness), address: address)
        } else {
            MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: address)
        }
    }

    static func setAllLightness(lightness: UInt16, ack: Bool = false) {
        if ack {
            MeshAPI.sendMessage(message: LightLightnessSet(lightness: lightness), address: .allNodes)
        } else {
            MeshAPI.sendMessage(message: LightLightnessSetUnacknowledged(lightness: lightness), address: .allNodes)
        }
    }

    static func setNodeColorTemperature(address: Address, temperature: UInt16, ack: Bool = false) {
        guard let node = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address),
              let model = node.temperatureModel else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightCTLTemperatureSet(temperature: temperature, deltaUV: 0), model: model)
        } else {
            MeshAPI.sendMessage(message: LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0), model: model)
        }
    }

    static func setGroupColorTemperature(address: Address, temperature: UInt16, ack: Bool = false) {
        guard address.isGroup else {
            return
        }

        if ack {
            MeshAPI.sendMessage(message: LightCTLTemperatureSet(temperature: temperature, deltaUV: 0), address: address)
        } else {
            MeshAPI.sendMessage(message: LightCTLTemperatureSetUnacknowledged(temperature: temperature, deltaUV: 0), address: address)
        }
    }

    static func identify(address: Address, attentionTimer: UInt8 = 5, ack: Bool = false) {
        let message: MeshMessage = ack ? AttentionSet(attentionTimer: attentionTimer) : AttentionSetUnacknowledged(attentionTimer: attentionTimer)

        if address.isUnicast,
           let model = MeshNetworkManager.instance.meshNetwork?.node(withAddress: address)?.healthModel {
            MeshAPI.sendMessage(message: message, model: model)
        } else {
            MeshAPI.sendMessage(message: message, address: address)
        }
    }

    static func sendVendorIdentify(_ message: SunricherVendorSet, model: Model) {
        MeshAPI.sendMessage(message: message, model: model)
    }
}
