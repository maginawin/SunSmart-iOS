import Foundation

// Deterministic SDK, UI and storage boundaries. The cascade and its codec are production sources.
typealias Address = UInt16
typealias SceneNumber = UInt16
extension UInt16 { var hex: String { String(format: "%04X", self) }; static var unassigned: Self { 0 } }
extension String { var localizedString: String { self } }
extension Notification.Name { static let deviceEmerFireDataDidChange = Self("fixture.efc.changed") }

final class Model: NSObject {}
final class Group {}
enum SchedulerAction: String, Codable { case noAction, sceneRecall, turnOn }
struct SchedulerRegistryEntry: Equatable {
    var action: SchedulerAction = .noAction
    var sceneNumber: UInt16 = 0
    var isValid: Bool { action != .noAction }
}
protocol StaticMeshMessage {}
struct SchedulerGet {}
struct SchedulerStatus: StaticMeshMessage { let schedules: UInt16 }
struct SchedulerActionStatus: StaticMeshMessage { let index: UInt8; let entry: SchedulerRegistryEntry }
struct SchedulerActionGet { let index: UInt8 }
struct SchedulerActionSet { let index: UInt8; let entry: SchedulerRegistryEntry }
struct SwitchKey: Equatable {
    enum ShortPress: Equatable { case sceneRecall(UInt16?, address: UInt16); case off }
    enum LongPress: Equatable { case dimUp(UInt16), cctDown(UInt16) }
    enum Direction { case up, down }
    let key: Int
    let shortPressAction: ShortPress
    let longPressAction: LongPress
    let direction: Direction
}
struct BatteryPowerSwitchKeyConfiguration {
    enum Trigger { case click }
    enum Kind { case disabled, sceneRecall }
    let button: UInt8
    var type: Kind = .sceneRecall
    var address: UInt16 = 0
    var sceneID: UInt16? = nil
    init(button: UInt8, trigger: Trigger, type: Kind, address: UInt16, appKeyIndex: UInt16) {
        self.button = button; self.type = type; self.address = address
    }
    init(button: Int, sceneID: UInt16?) { self.button = UInt8(button); self.sceneID = sceneID }
}
struct EmergencyActionConfiguration { let state: Int; let action: EmergencyAction }
struct SunricherVendorSet {
    enum Function {
        case enOceanSwitchKeySet(key: SwitchKey, macAddress: String)
        case batteryPowerSwitchKeyConfig(BatteryPowerSwitchKeyConfiguration)
        case emergencyActionConfig(EmergencyActionConfiguration)
    }
    let function: Function
}
final class MeshMessageHandle {
    let message: Any
    let model: Model
    var isSuccessful = true
    var continuous = true
    init(message: Any, model: Model) { self.message = message; self.model = model }
}
final class Node {
    let primaryUnicastAddress: UInt16
    var name: String?
    var timedSchedulerIdentity: TimedSchedulerNodeIdentity?
    var schedulerSetupModels: [Model] = []
    var allSchedulerModelEntrys: [Model: [Int: SchedulerRegistryEntry]] = [:]
    var schedulerActions: [Int: SchedulerRegistryEntry] = [:]
    var scheduleIds: [Int] = []
    var savedSchedulerEntries: [Model: [Int: SchedulerRegistryEntry]] = [:]
    var savedSchedulerActions: [Int: SchedulerRegistryEntry] = [:]
    func rebuildSchedulerActions() {
        schedulerActions = [:]
        for model in schedulerSetupModels {
            for (slot, entry) in allSchedulerModelEntrys[model] ?? [:] where entry.isValid { schedulerActions[slot] = entry }
        }
        scheduleIds = schedulerActions.keys.sorted()
    }
    func savePropertys() {
        savedSchedulerEntries = allSchedulerModelEntrys
        savedSchedulerActions = schedulerActions
    }
    var sunricherVendorModel: Model? = Model()
    var enOceanProxySwitchKeys: [SwitchKey] = []
    var enOceanMacAddress: String?
    var group: Group?
    var iconName: String { "device" }
    var cacheClears = 0
    init(_ address: UInt16) {
        primaryUnicastAddress = address; name = "Node \(address)"
        timedSchedulerIdentity = .init(nodeUUID: String(format: "00000000-0000-0000-0000-%012X", address),
            unicastAddress: address.hex, deviceKeyFingerprint: String(repeating: "A", count: 64))
    }
    /// Synthetic test key only. Hashing and Scene normalization use extracted production implementations.
    func useProductionFingerprint(key: String = "00112233445566778899AABBCCDDEEFF", uuid: UUID? = nil) throws {
        timedSchedulerIdentity = .init(
            nodeUUID: uuid?.uuidString ?? String(format: "00000000-0000-0000-0000-%012X", primaryUnicastAddress),
            unicastAddress: primaryUnicastAddress.hex,
            deviceKeyFingerprint: try SchedulerModelSnapshot.keyFingerprint(["deviceKey": key]))
    }
    func clearSyncStateCache() { cacheClears += 1 }
    func schedulerSetupModel(for owner: Int) -> Model? { schedulerSetupModels.indices.contains(owner) ? schedulerSetupModels[owner] : nil }
    func applyMessageHandle(_ handle: MeshMessageHandle, isSuccess: Bool) -> Bool {
        guard isSuccess else { return false }
        if let message = handle.message as? SchedulerActionSet {
            if message.entry.isValid { allSchedulerModelEntrys[handle.model]?[Int(message.index)] = message.entry }
            else { allSchedulerModelEntrys[handle.model]?[Int(message.index)] = nil }
        }
        return true
    }
}
final class Schedule: Codable {
    enum Target: String, Codable { case scene, devices, profile }
    var id: Int
    var name: String
    var selectTargetType: Target = .scene
    var nodeSlotsLoadFailed = false
    var action: SchedulerAction = .sceneRecall
    var sceneNumber: UInt16?
    var nodeAddresses: [UInt16] = []
    var groupAddresses: [UInt16] = []
    var needDeleteNodeAddresses: [UInt16] = []
    var needDeleteGroupAddresses: [UInt16] = []
    var needDeleteSceneNumbers: [UInt16] = []
    var nodeSlots: [TimedSchedulerNodeSlot]? = []
    var testExistAddresses: [UInt16] = []
    var ownerModel = 0
    init(_ id: Int, scene: UInt16? = nil) { self.id = id; name = "Timed \(id)"; sceneNumber = scene }
    var existNodes: [Node] {
        MeshNetworkManager.instance.realNodes.filter { node in
            testExistAddresses.contains(node.primaryUnicastAddress) || nodeAddresses.contains(node.primaryUnicastAddress)
                || nodeSlots?.contains(where: { $0.identity == node.timedSchedulerIdentity }) == true
        }
    }
    func copy() -> Schedule { try! JSONDecoder().decode(Self.self, from: JSONEncoder().encode(self)) }
    func slot(on node: Node) -> Int? {
        guard !nodeSlotsLoadFailed else { return nil }
        guard let slots = nodeSlots else { return (0..<16).contains(id) ? id : nil }
        return slots.first { $0.identity == node.timedSchedulerIdentity }?.slot
    }
    func targets(node: Node) -> Bool { nodeAddresses.contains(node.primaryUnicastAddress) }
    func schedulerModelOwner(on node: Node, contextGroup: Group?) -> Int { ownerModel }
    var schedulerEntry: SchedulerRegistryEntry { .init(action: action, sceneNumber: sceneNumber ?? 0) }
    func save(meshUUID: String, meshNetworkId: String) -> Bool {
        guard !FixtureStore.failScheduleSave else { return false }
        FixtureStore.schedules[id] = copy(); return true
    }
    static func load(meshUUID: String, meshNetworkId: String) -> [Schedule] { FixtureStore.schedules.values.map { $0.copy() } }
    func deleteData(meshUUID: String, meshNetworkId: String) -> Bool {
        guard !FixtureStore.failScheduleSave else { return false }
        FixtureStore.schedules[id] = nil; return true
    }
}
class DeviceSwitchData {
    enum Panel: Int { case default_4key, default_2key, scenes_4key, scenes_2key }
    let id: String
    var name: String
    var sceneANumber: UInt16?, sceneBNumber: UInt16?, sceneCNumber: UInt16?, sceneDNumber: UInt16?
    var proxyNodeAddress: UInt16?, deleteProxyNodeAddress: UInt16?
    var linkGroupAddress: UInt16? = 0xC001
    var subLinkGroupAddress: UInt16? = 0xC002
    var panelType: Panel = .scenes_4key
    var enOceanMacAddress: String? = "fixture-mac"
    var longPress: SwitchKey.LongPress = .dimUp(0xC001)
    required init(id: String, name: String) { self.id = id; self.name = name }
    func copy() -> Self {
        let result = type(of: self).init(id: id, name: name)
        result.sceneANumber = sceneANumber; result.sceneBNumber = sceneBNumber
        result.sceneCNumber = sceneCNumber; result.sceneDNumber = sceneDNumber
        result.proxyNodeAddress = proxyNodeAddress; result.deleteProxyNodeAddress = deleteProxyNodeAddress
        result.linkGroupAddress = linkGroupAddress; result.subLinkGroupAddress = subLinkGroupAddress
        result.panelType = panelType; result.enOceanMacAddress = enOceanMacAddress; result.longPress = longPress
        return result
    }
    var switchKeys: [SwitchKey] {
        guard linkGroupAddress != nil else { return [] }
        return [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber].enumerated().map {
            .init(key: 4 - $0.offset, shortPressAction: .sceneRecall($0.element, address: 0xFFFF),
                longPressAction: longPress, direction: $0.offset % 2 == 0 ? .up : .down)
        }
    }
    static func load(meshUUID: String, meshNetworkId: String) -> [DeviceSwitchData] { FixtureStore.switches.values.map { $0.copy() } }
    func save(meshUUID: String, networkId: String) -> Bool {
        guard !FixtureStore.failSwitchSave else { return false }
        FixtureStore.switches[id] = copy(); return true
    }
    func delete(meshUUID: String, networkId: String) -> Bool {
        guard !FixtureStore.failSwitchSave else { return false }
        FixtureStore.switches[id] = nil; return true
    }
}
final class PJEightKeySwitchData: DeviceSwitchData {
    enum SyncState { case pending, synced }
    var desiredConfigHash = "old", appliedConfigHash = "old"
    var desiredConfigVersion = 1
    var syncState: SyncState = .pending
    var needsBatteryPowerSwitchSync: Bool { desiredConfigHash != appliedConfigHash }
    var requiresActivationBeforeOwnConfiguration = true
    override func copy() -> Self {
        let value = super.copy(); value.desiredConfigHash = desiredConfigHash; value.appliedConfigHash = appliedConfigHash
        value.desiredConfigVersion = desiredConfigVersion
        value.requiresActivationBeforeOwnConfiguration = requiresActivationBeforeOwnConfiguration; return value
    }
    func prepareBatteryPowerSwitchDesiredConfig(appKeyIndex: UInt16) {
        desiredConfigHash = [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber].map { $0?.hex ?? "nil" }.joined(separator: ",")
    }
    func batteryPowerSwitchKeyConfigurations(appKeyIndex: UInt16) -> [BatteryPowerSwitchKeyConfiguration] {
        guard linkGroupAddress != nil else { return [] }
        return [sceneANumber, sceneBNumber, sceneCNumber, sceneDNumber].enumerated().map { .init(button: $0.offset, sceneID: $0.element) }
    }
}
final class PJEightKeySwitchRepository {
    static let shared = PJEightKeySwitchRepository()
    func makeEightKeySwitch(from item: DeviceSwitchData) -> PJEightKeySwitchData? { item as? PJEightKeySwitchData }
    func save(_ item: PJEightKeySwitchData, meshUUID: String, networkId: String) -> Bool {
        guard !FixtureStore.failPowerSave else { return false }
        FixtureStore.powerHashes[item.id] = item.appliedConfigHash; return true
    }
    func confirmSceneKeyConfiguration(_ item: PJEightKeySwitchData, meshUUID: String, networkId: String) -> Bool {
        guard !FixtureStore.failPowerSave else { return false }
        FixtureStore.powerHashes[item.id] = item.desiredConfigHash; return true
    }
}
enum EmergencyAction: Codable, Equatable { case sceneRecall(UInt16), invalid, lightness }
struct EmergencySettings: Codable { var triggerActionPreset: EmergencyAction? }
enum EmergencyState { case emergencyTrigger, fireTrigger }
struct EmergencyConfiguration: Codable {
    var powerLossSettings = EmergencySettings()
    var fireAlarmSettings = EmergencySettings()
    func actionConfig(for state: EmergencyState, targetAddress: UInt16?, appKeyIndex: UInt16, ttl: UInt8) -> EmergencyActionConfiguration {
        .init(state: state == .emergencyTrigger ? 0 : 1,
            action: (state == .emergencyTrigger ? powerLossSettings : fireAlarmSettings).triggerActionPreset ?? .lightness)
    }
}
final class DeviceEmerFireData {
    static let emergencyActionTTL: UInt8 = 0xFF
    let id: String
    var name: String
    var configuration = EmergencyConfiguration()
    var bindNodeAddress: UInt16?
    var publishGroupAddress: UInt16? = 0xC010
    var bindNode: Node? { MeshNetworkManager.instance.realNodes.first { $0.primaryUnicastAddress == bindNodeAddress } }
    init(_ id: String) { self.id = id; name = id }
    func copy() -> DeviceEmerFireData {
        let result = DeviceEmerFireData(id); result.name = name; result.configuration = configuration
        result.bindNodeAddress = bindNodeAddress; result.publishGroupAddress = publishGroupAddress; return result
    }
    func save(meshUUID: String, networkId: String) -> Bool {
        guard !FixtureStore.failEmergencySave else { return false }
        FixtureStore.emergency[id] = copy(); return true
    }
}
final class DeviceEmerFireRepository {
    static let shared = DeviceEmerFireRepository()
    func load(meshUUID: String, meshNetworkId: String) -> [DeviceEmerFireData] { FixtureStore.emergency.values.map { $0.copy() } }
}
final class DeviceEmerFireStore {
    static let shared = DeviceEmerFireStore()
    func loadDevices(meshUUID: String, meshNetworkId: String) -> [DeviceEmerFireData] { Array(FixtureStore.emergency.values) }
    func device(id: String, meshUUID: String, meshNetworkId: String) -> DeviceEmerFireData? { FixtureStore.emergency[id] }
}
final class Network { let uuid = UUID() }
final class MeshNetworkManager {
    struct Key { var networkId: UInt16 = 1; var index: UInt16 = 0 }
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network()
    var currentNetworkKey = Key(), currentApplicationKey = Key()
    var realNodes: [Node] = [], schedules: [Schedule] = [], switchs: [DeviceSwitchData] = [], scenes: [Scene] = []
}
final class Scene {
    let number: UInt16
    let info: SceneInfo
    init(_ number: UInt16 = 1) { self.number = number; info = SceneInfo(number) }
}
final class SceneInfo {
    let sceneId: UInt16
    var configuration: SceneConfiguration?
    var configurationLoadFailed = false
    init(_ number: UInt16) { sceneId = number }
    func saveConfiguration(meshUUID: String, subnetworkId: String) throws {
        guard !FixtureStore.failSceneSave else { throw SceneConfigurationStore.Failure.persistence }
        FixtureStore.scenes[sceneId] = try configuration?.encoded()
    }
    static func loadAll(meshUUID: String, subnetworkId: String) throws -> [SceneInfo] {
        try FixtureStore.scenes.map { number, data in
            let info = SceneInfo(number); info.configuration = try SceneConfiguration.decode(data); return info
        }
    }
}
struct SceneTargetSnapshot {
    struct Target { let node: Node }
    let scope: SceneScope
    var targets: [Target] = []
    var cleanupTargets: [Target] = []
}
enum SceneTargetResolver {
    static func resolve(scene: Scene) throws -> SceneTargetSnapshot {
        let manager = MeshNetworkManager.instance
        return .init(scope: .init(meshUUID: manager.meshNetwork!.uuid.uuidString,
            networkID: manager.currentNetworkKey.networkId.hex))
    }
}
enum SceneConfigurationStore {
    enum Failure: Error { case persistence, invalidTargets, unavailable }
    static func deletionReferenceNames(number: UInt16) -> [String] {
        MeshNetworkManager.instance.schedules.filter { $0.sceneNumber == number }.map(\.name)
    }
}
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand()
    var isBusy = false
}
enum FixtureStore {
    static var schedules: [Int: Schedule] = [:], switches: [String: DeviceSwitchData] = [:]
    static var emergency: [String: DeviceEmerFireData] = [:], powerHashes: [String: String] = [:], scenes: [UInt16: Data] = [:]
    static var failSceneSave = false, failScheduleSave = false, failSwitchSave = false, failPowerSave = false, failEmergencySave = false
    static func reset() {
        MeshProxyMessageCommand.shared.isBusy = false
        schedules = [:]; switches = [:]; emergency = [:]; powerHashes = [:]; scenes = [:]
        failSceneSave = false; failScheduleSave = false; failSwitchSave = false; failPowerSave = false; failEmergencySave = false
    }
}
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    func configurationTransaction(_ body: () throws -> Void) -> Bool {
        let schedules = FixtureStore.schedules, switches = FixtureStore.switches, emergency = FixtureStore.emergency
        let powers = FixtureStore.powerHashes, scenes = FixtureStore.scenes
        do { try body(); return true }
        catch {
            FixtureStore.schedules = schedules; FixtureStore.switches = switches; FixtureStore.emergency = emergency
            FixtureStore.powerHashes = powers; FixtureStore.scenes = scenes; return false
        }
    }
}
enum DeviceOperationType {
    enum Action { case sceneReferenceCleanup(SceneDeletionTask) }
    case configuration(node: Node, type: Action)
}
final class SyncDevicesSectionModel {
    var prefersDevicesBeforeGroups = false
    var devices: [SyncDevicesModel] = []
}
final class SyncDevicesModel {
    let name: String, address: UInt16
    var imageName = ""
    var steps: [SyncDeviceStepModel] = []
    init(name: String, address: UInt16) { self.name = name; self.address = address }
}
final class SyncDeviceStepTaskModel {
    let operationType: DeviceOperationType
    weak var parentStepModel: SyncDeviceStepModel?
    init(name: String, operationType: DeviceOperationType) { self.operationType = operationType }
}
final class SyncDeviceStepModel {
    enum State { case none }
    let tasks: [SyncDeviceStepTaskModel]
    var relevanceStepModels: [SyncDeviceStepModel] = []
    weak var parentDeviceModel: SyncDevicesModel?
    init(type: String, state: State, tasks: [SyncDeviceStepTaskModel]) { self.tasks = tasks }
}
