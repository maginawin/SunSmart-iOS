import Foundation
import NordicSigMeshSDK

/// Message encoding shared by preparation and the selective configuration commands.
enum HDBLightingMessages {
    static func message(_ write: HDBLightingWrite) -> AcknowledgedMeshMessage {
        switch write {
        case .auto:
            // Omitting transition fields lets LC use the device's saved Fade On time.
            return LightLCLightOnOffSet(true)
        case .off:
            return GenericOnOffSet(false)
        case .lightness(let value):
            return LightLightnessSet(lightness: value)
        case .property(let id, let raw):
            let value: DevicePropertyCharacteristic = (id == 0x002E || id == 0x002F) ? .perceivedLightness(UInt16(raw)) : .timeMillisecond24(raw)
            return LightLCPropertySet(of: DeviceProperty(id), value: value)
        }
    }

    static func preparation(_ targets: [HDBPreparationTarget]) throws -> [(HDBModelTarget, AcknowledgedMeshMessage)] {
        var writes: [(HDBModelTarget, AcknowledgedMeshMessage)] = []
        var modes: [(HDBModelTarget, AcknowledgedMeshMessage)] = []
        for target in targets {
            try target.validate()
            let model = target.model
            switch target.value {
            case .vendor(let value):
                let timeout = value.manualOverrideTimeout
                let state: ManualOverrideState
                switch timeout.state { case .standby: state = .standby; case .on: state = .on; case .prolong: state = .prolong }
                writes += [(model, SunricherVendorSet(function: .manualControlEnabled(enabled: value.manualControlEnabled))),
                           (model, SunricherVendorSet(function: .lightAutoAdjustEnabled(enabled: value.lightAutoAdjustEnabled))),
                           (model, SunricherVendorSet(function: .manualOverrideTimeout(enabled: timeout.enabled, state: state, interval: timeout.intervalMilliseconds)))]
            case .lcSetup(let value):
                writes.append((model, LightLCPropertySet(of: .lightControlTimeProlong, value: .timeMillisecond24(value.prolongTimeMilliseconds))))
            case .lc(let value):
                writes.append((model, LightLCOccupancyModeSet(value.occupancyMode)))
                modes.append((model, LightLCModeSet(value.mode)))
            case nil: break
            }
        }
        // Enable LC only after all other model instances have been configured.
        return writes + modes
    }

    static func model(_ target: HDBModelTarget, node: Node, key: ApplicationKey) throws -> Model {
        guard let model = node.elements.first(where: { $0.unicastAddress == target.elementAddress })?.models.first(where: {
            $0.modelIdentifier == target.modelIdentifier && $0.companyIdentifier == target.companyIdentifier
        }) else { throw HDBConfigurationError.unsupportedModels }
        guard model.boundApplicationKeys.contains(where: { $0.index == key.index }) else {
            throw HDBConfigurationError.modelNotBound
        }
        // The SDK's acknowledged model API selects parentApplicationKey, otherwise first bound key.
        let selected = node.parentApplicationKey.flatMap { parent in model.boundApplicationKeys.first { $0.index == parent.index } }
            ?? model.boundApplicationKeys.first
        guard selected?.index == key.index else { throw HDBConfigurationError.unexpectedApplicationKey }
        return model
    }

    static func observation(request: MeshMessage, response: MeshMessage) throws -> (String, String) {
        if let request = request as? LightLCPropertyGet, let response = response as? LightLCPropertyStatus,
           request.parameters == Data(response.parameters!.prefix(2)) {
            let data = Data(response.parameters!.dropFirst(2))
            guard data.count == (response.property.id == 0x002E || response.property.id == 0x002F ? 2 : 3) else { throw HDBLightingError.responseMismatch }
            let raw = data.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            switch response.property.id {
            case 0x002E: return ("BrightIntensity", String(Int((Double(raw) / 65535 * 100).rounded())))
            case 0x002F: return ("DimIntensity", String(Int((Double(raw) / 65535 * 100).rounded())))
            case 0x0037: return ("RampUpTime", String(Double(raw) / 1000))
            case 0x0036: return ("RampDownTime", String(Double(raw) / 1000))
            case 0x003C: return ("HoldTime", String(Double(raw) / 1000))
            default: break
            }
        }
        if request is LightLCModeGet, let response = response as? LightLCModeStatus { return ("LCMode", String(response.controllerStatus)) }
        if request is LightLCLightOnOffGet, let response = response as? LightLCLightOnOffStatus { return ("LCOnOff", String(response.targetState ?? response.isOn)) }
        if request is LightLightnessGet, let response = response as? LightLightnessStatus { return ("Lightness", String(Node.getLightness100(lightness: response.lightness))) }
        throw HDBLightingError.responseMismatch
    }

    static func matches(_ request: MeshMessage, response: MeshMessage) -> Bool {
        if let request = request as? LightLCPropertySet, let response = response as? LightLCPropertyStatus {
            return request.parameters == response.parameters
        }
        if request is LightLCModeSet { return (response as? LightLCModeStatus)?.parameters == request.parameters }
        if request is LightLCOccupancyModeSet { return (response as? LightLCOccupancyModeStatus)?.parameters == request.parameters }
        if let request = request as? LightLCLightOnOffSet, let response = response as? LightLCLightOnOffStatus {
            return (response.targetState ?? response.isOn) == request.isOn
        }
        if let request = request as? GenericOnOffSet, let response = response as? GenericOnOffStatus {
            return (response.targetState ?? response.isOn) == request.isOn
        }
        if let request = request as? LightLightnessSet, let response = response as? LightLightnessStatus {
            return (response.targetLightness ?? response.lightness) == request.lightness
        }
        if let request = request as? SunricherVendorSet, let response = response as? SunricherVendorStatus,
           response.status.isSuccessful {
            let code: ResponseCode
            switch request.function {
            case .manualControlEnabled: code = .manualControlEnabled
            case .lightAutoAdjustEnabled: code = .lightAutoAdjustEnabled
            case .manualOverrideTimeout: code = .manualOverrideTimeout
            default: return false
            }
            guard response.status.code == code, let payload = response.parameters,
                  payload.count >= 3, payload[0] == code.code[0],
                  payload[1] == 0, payload[2] == 0 else { return false }
            // These Set commands acknowledge with code/subcode/ret, without
            // echoing values. A successful short ACK does not imply readback.
            if payload.count == 3 { return true }
            // Some firmware also echoes the configuration. Compare the entire
            // raw value so truncated data or SDK-normalized values cannot pass.
            guard let sent = request.parameters else { return false }
            return payload.dropFirst(3) == sent.dropFirst()
        }
        return false
    }
}
