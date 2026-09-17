import Foundation

// 只替换 SDK、数据库和协议输入；构建算法、优先级和列表模型由检查脚本加载生产源码。
typealias Address = UInt16
typealias KeyIndex = UInt16
class CAAnimation {}
extension String { var localizedString: String { self } }
final class Group: NSObject {}
struct GroupProfileSyncContext { let marker: Int }
struct SceneExecuteData {}
struct Scene { let name: String; let number: UInt16 }
struct Schedule { let name: String; let enabled: Bool }
struct SchedulerRegistryEntry {
    var marker = 0
    var isValid: Bool { marker != 0 }
}
struct DeviceDongleData { var bindNode: Node? }
struct PJEightKeySwitchData { let name: String }
struct DeviceSwitchData { let name: String; var batteryPowerSwitchData: PJEightKeySwitchData? }
struct DeviceEmerFireData {}
enum EmergencyFireControllerSyncTaskKind: Hashable {
    case associationSubscription, associationCleanup
    var localizedTitle: String { String(describing: self) }
}
struct EmergencyFireControllerSyncTask { let kind: EmergencyFireControllerSyncTaskKind; let title: String }
enum ProfileType: String {
    case profileToggleTriggerConditionLuxLock, profileDayToggleTriggerConditionLux
    case profileNightToggleTriggerConditionLux, lightControlSwitch, daylightSensorConditionRecall
    case lightControlStore, powerOnState, daylightCalibration, daylightCalibrateRate
    case daylightCalibrateInflectionPoint, sensitivity, lightControlDelete
    case profileToggleTriggerConditionLuxDelete, occupancyLevel
    var title: String { rawValue }
}
enum DeviceParameterType {
    case pwmFrequency(frequency: Int), ratedPower(datas: Int), motionSensitivityRange(range: Int)
    case defaultTransitionTime(transitionTime: Int), powerCalibration(calibrationValue: Int)
    case absoluteCctRange(range: Int), photosensorException(Bool)
}
struct NetworkIdentifier { let hex: String }
struct NetworkKey {
    let index: KeyIndex
    var isSecondary: Bool { index > 0 }
    var networkId: NetworkIdentifier { NetworkIdentifier(hex: String(index)) }
}
struct ApplicationKey { let index: KeyIndex; let boundNetworkKeyIndex: KeyIndex }
struct GatewaySpaceData { let appKeyIndex: KeyIndex; let spaceName: String }
enum GatewayInformation { struct MQTTConnectInformation { let marker: Int } }
final class GatewayModel {
    var name = "Gateway"
    var associatedSpaces: [GatewaySpaceData] = []
    var activate = true
    var siteId = "site"
    var mqttServerInfo: GatewayInformation.MQTTConnectInformation?
}
final class MeshNetwork {
    var networkKeys: [NetworkKey] = []
    var applicationKeys: [ApplicationKey] = []
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork?
}
struct SpaceData {
    let name: String
    static var names: [String: String] = [:]
    static func load(subNetworkId: String) -> SpaceData? { names[subNetworkId].map { SpaceData(name: $0) } }
}
enum NodeSyncType { case group(Group?, effectiveMemberCount: Int?); case all; case dongle(dongleData: DeviceDongleData) }
final class Node: Equatable {
    static func == (lhs: Node, rhs: Node) -> Bool { lhs === rhs }
    enum DeviceType { case gateway, light }
    enum GroupState { case none, exitFailure }
    var name: String? = "Lamp"
    var iconName = "device_light"
    var primaryUnicastAddress: Address = 1
    var group: Group?
    var groupState: GroupState = .none
    var timeModel: Int? = 1
    var deviceType: DeviceType = .light
    var isWiFiGateway = false
    var networkKeys: [NetworkKey] = []
    var orphanAddresses: Set<Address> = []
    var inputs: [NodeSyncData] = []
    var requests: [(NodeSyncType, GroupProfileSyncContext?)] = []
    func getSyncData(type: NodeSyncType, profileSyncContext: GroupProfileSyncContext? = nil) -> [NodeSyncData] {
        requests.append((type, profileSyncContext))
        return inputs
    }
}
enum ActionType {
    case missingGroupSubscriptions
    case collectionSchedule(index: Int, entry: SchedulerRegistryEntry)
    case group(group: Group), profile(type: ProfileType), pirEnabled(Bool)
    case scene(sceneId: UInt16, executeData: SceneExecuteData?), schedule(schedule: Schedule)
    case timeSynchronization, enOceanProxy(switchData: DeviceSwitchData), enOceanSwitch(switchData: DeviceSwitchData)
    case batteryPowerSwitchTargetSubscription(switchData: PJEightKeySwitchData, group: Group, unsubscribe: Bool)
    case deviceInitialize, deviceParameters(parameterType: DeviceParameterType)
    case proximityLightingEnabled(enabled: Bool), proximityLightingRelayNumber(relayNumber: UInt8)
    case proximityLightingNeighbor(relayNumber: UInt8, neighborAddresses: [Address])
    case emergencyFireController(task: EmergencyFireControllerSyncTask, data: DeviceEmerFireData)
    case gatewayAssociationProjectId(projectId: String)
    case gatewayAssociatedSpace(networkKey: NetworkKey, applicationKey: ApplicationKey, activate: Bool)
    case gatewayUnbindAssociatedSpace(networkKey: NetworkKey, applicationKey: ApplicationKey, activate: Bool)
    case gatewaySubnetAppkeyIndexs(appkeyIndexs: [KeyIndex]), gatewaySIMAPN(apn: String)
    case gatewayMQTTInformation(mqttInformation: GatewayInformation.MQTTConnectInformation)
    case gatewayServerAuthorization(gateway: GatewayModel), gatewayServerInformation(gateway: GatewayModel)
    case gatewayServerInformationVerification(gateway: GatewayModel)
    case gatewayRecoveryInitialization, gatewayRepairInitialization
    case gatewayRecoveryAssociatedSpace(networkKey: NetworkKey, applicationKey: ApplicationKey, activate: Bool)
    case gatewayRecoveryVerification(gateway: GatewayModel)
}
final class MeshMessageHandle {
    var respondAddresss: [Address] = [1]
    var notRespondAddresss: [Address] = [2]
}
enum DeviceOperationType {
    static var allowsMessageFactory = false
    static var testHandles: [MeshMessageHandle] = []
    case configuration(node: Node, type: ActionType), delete(node: Node, type: ActionType)
    var action: ActionType {
        switch self { case .configuration(_, let action), .delete(_, let action): return action }
    }
    var isDelete: Bool { if case .delete = self { return true }; return false }
    // 构建期访问消息工厂立即失败，防止无意提前冻结 TimeSet 或服务器信息。
    var messageHandles: [MeshMessageHandle] {
        precondition(Self.allowsMessageFactory, "Builder must not generate messages")
        return Self.testHandles
    }
    var isTimedScheduleTimeSyncOperation: Bool {
        if case .timeSynchronization = action { return true }
        return false
    }
}
enum SyncDevicesViewController {
    enum GatewayRecoveryTrigger { case devicesNotSynced, repair }
}

enum MissingGroupSubscriptionCleanup {
    static func addresses(for node: Node) -> Set<Address> { node.orphanAddresses }
    static func finish(for node: Node) -> Bool { node.orphanAddresses.isEmpty }
}
