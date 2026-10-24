import Foundation

// SDK radio/connection boundaries. The actual App service and shared command sender run in tests.
typealias Address = UInt16
extension UInt16 {
    var isGroup: Bool { self >= 0xC000 }
    var isUnicast: Bool { self > 0 && self < 0x8000 }
    static var allNodes: UInt16 { 0xFFFF }
}
extension Node {
    var onoffModel: Model? { elements.first?.models.first }
    var lightnessModel: Model? { onoffModel }
    var temperatureModel: Model? { onoffModel }
    var healthModel: Model? { onoffModel }
    static func getLightness(lightness100: Int) -> UInt16 {
        UInt16(Double(max(0, min(100, lightness100))) / 100 * 65535)
    }
}
extension MeshNetwork {
    func node(withAddress address: UInt16) -> Node? { nodes.first { $0.primaryUnicastAddress == address } }
    func group(withAddress address: UInt16) -> Group? { groups.first { $0.address.address == address } }
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
    var subElementGroupSubscriptionModelIDs: [UInt16] = [0x1306, 0x130F]
}
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand()
    var isBusy = false
}
enum EmergencyFireControllerSceneEventManager {
    static var blockedNodes = Set<UUID>()
    static var blockedGroups = Set<UInt16>()
    static func isManualControlBlocked(for node: Node) -> Bool { blockedNodes.contains(node.uuid) }
    static func isManualControlBlocked(for group: Group) -> Bool { blockedGroups.contains(group.address.address) }
}
enum ControlRadio {
    static var messages: [(message: MeshMessage, address: UInt16?)] = []
}
extension MeshAPI {
    static func sendMessage(message: MeshMessage, address: UInt16) { ControlRadio.messages.append((message, address)) }
    static func sendMessage(message: MeshMessage, model: Model) { ControlRadio.messages.append((message, nil)) }
}
protocol ControlMessage: MeshMessage {}
extension ControlMessage { var parameters: Data { Data() } }
struct GenericOnOffSet: ControlMessage { let isOn: Bool; init(_ on: Bool) { isOn = on } }
struct GenericOnOffSetUnacknowledged: ControlMessage { let isOn: Bool; init(_ on: Bool) { isOn = on } }
struct LightLightnessSet: ControlMessage { let lightness: UInt16 }
struct LightLightnessSetUnacknowledged: ControlMessage { let lightness: UInt16 }
enum TransitionTime { case `default` }
struct LightLCLightOnOffSetUnacknowledged: ControlMessage {
    let isOn: Bool
    let transitionTime: TransitionTime?
    let delay: UInt8?
    init(_ on: Bool) {
        isOn = on; transitionTime = nil; delay = nil
    }
    init(_ on: Bool, transitionTime: TransitionTime, delay: UInt8) {
        isOn = on; self.transitionTime = transitionTime; self.delay = delay
    }
}
struct LightCTLTemperatureSet: ControlMessage { let temperature: UInt16, deltaUV: Int16 }
struct LightCTLTemperatureSetUnacknowledged: ControlMessage { let temperature: UInt16, deltaUV: Int16 }
struct AttentionSet: ControlMessage { let attention: UInt8; init(attentionTimer: UInt8) { attention = attentionTimer } }
struct AttentionSetUnacknowledged: ControlMessage { let attention: UInt8; init(attentionTimer: UInt8) { attention = attentionTimer } }
struct SunricherVendorSet: ControlMessage {}

// Radio boundary only. check_hdb_zone_control.py replaces this type with the
// mapped SDK's Sensor Status construction, marshalling and Bool encoding.
struct SensorStatus: ControlMessage {
    enum Property { case presenceDetected }
    enum Value { case bool(Bool) }
    init(_ value: (property: Property, value: Value)) {}
}
