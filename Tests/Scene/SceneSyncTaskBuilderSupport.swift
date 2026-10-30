import Foundation
extension String { var localizedString: String { self } }
extension Node { var iconName: String { "light" } }
extension Group { var name: String { "Group" } }
extension Schedule { func needsSync(on node: Node, contextGroup: Group?) -> Bool { testSyncNeededAddresses?.contains(node.primaryUnicastAddress) ?? true } }
enum ActionType { case scene(sceneId: UInt16, executeData: SceneExecuteData?), schedule(schedule: Schedule) }
enum DeviceOperationType { case configuration(node: Node, type: ActionType), delete(node: Node, type: ActionType) }
class SyncDevicesModel {
    var imageName = ""
    var operationType: DeviceOperationType?
    var steps: [SyncDeviceStepModel] = []
    weak var parentGroupModel: SyncDevicesGroupModel?
    init(name: String, address: UInt16) {}
}
final class SyncDevicesGroupModel {
    let address: UInt16
    let deviceModels: [SyncDevicesModel]
    init(groupName: String, groupAddress: UInt16, deviceModels: [SyncDevicesModel]) { address = groupAddress; self.deviceModels = deviceModels }
}
final class SyncDevicesSectionModel {
    var devices: [SyncDevicesModel] = []
    var groups: [SyncDevicesGroupModel] = []
}
final class SyncDeviceStepTaskModel {
    let operationType: DeviceOperationType
    weak var parentStepModel: SyncDeviceStepModel?
    init(name: String, operationType: DeviceOperationType) { self.operationType = operationType }
}
final class SyncDeviceStepModel {
    enum State { case none }
    var showProgress = true
    weak var parentDeviceModel: SyncDevicesModel?
    var relevanceStepModels: [SyncDeviceStepModel] = []
    let tasks: [SyncDeviceStepTaskModel]
    init(type: String, state: State, tasks: [SyncDeviceStepTaskModel]) { self.tasks = tasks }
}
enum MissingGroupSubscriptionCleanup { static func addresses(for node: Node) -> [UInt16] { [] } }
struct FixtureRestore {
    var addGroup: Group?; var pwmFrequency: Int?; var phaseEnergyConsumptions: Int?
    var motionSensitivityRange: Int?; var photosensorException: Int?; var defaultTransitionTime: FixtureTransition?
}
struct FixtureTransition { let rawValue: UInt8 }
struct FixtureDongle { let bindNodeAddress: UInt16 }
struct GatewayModel { static func load(node: Node) -> GatewayModel? { nil } }
enum DeviceRestoreDefaultTransitionTimePolicy {
    static func pendingTargetRawValue(restoreTargetRawValue: UInt8?, currentRawValue: UInt8?, isSupported: Bool) -> UInt8? { nil }
}
extension MeshNetworkManager { var dongles: [FixtureDongle] { [] } }
extension Node {
    enum FixtureDeviceType { case light, dongle, gateway }
    enum FixtureSyncType { case dongle(dongleData: FixtureDongle) }
    var deviceType: FixtureDeviceType { .light }
    var isKeybindComplete: Bool { true }
    var restoreData: FixtureRestore? { nil }
    var pwmFrequency: Int? { nil }; var phaseEnergyConsumptions: Int? { nil }; var motionSensitivityRange: Int? { nil }
    var photosensorException: Int? { nil }; var supportPhotosensorException: Bool { false }
    var defaultTransitionTime: FixtureTransition? { nil }; var supportDefaultTransitionTime: Bool { false }
    func getNodeNeedDeleteSwitchs() -> (delteSwitchProxy: Int?, unlinkSwitchs: [Int]) { (nil, []) }
    func getNodeSyncProximityLighting() -> Int? { nil }
    func getNeedSyncGroup(group: Group) -> Bool { false }
    func getNodeSyncProfiles(group: Group?) -> [Int] { [] }
    func getNodeSyncSchedules() -> [Schedule] { [] }
    func getNodeNeedDeleteSchedules() -> [Schedule] { [] }
    func getNodeSyncGatewayData(gateway: GatewayModel) -> [Int] { [] }
    func getSyncData(type: FixtureSyncType) -> [Int] { [] }
}
