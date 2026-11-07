import Foundation
import CryptoKit
import SQLite
import struct SQLite.Expression

typealias Address = UInt16
typealias SceneNumber = UInt16
typealias SchedulerAction = Schedule.Action
typealias SchedulerRegistryEntry = Entry
typealias MeshMessage = Any
enum SchedulerSetupModelOwner { case ordinary, lightLC }
extension UInt16 {
    init?(hex: String) { self.init(hex, radix: 16) }
    var hex: String { String(format: "%04X", self) }
    var isUnicast: Bool { (1..<0x8000).contains(self) }
    var isGroup: Bool { (0xC000..<0xFF00).contains(self) }
    var isVirtual: Bool { (0x8000..<0xC000).contains(self) }
    var isSpecialGroup: Bool { self >= 0xFF00 }
    var isValidSceneNumber: Bool { self > 0 }
    var isSpecialScene: Bool { self >= 0xFF00 }
}
extension String { var localizedString: String { self } }
let jsonEncoder = JSONEncoder(), jsonDecoder = JSONDecoder()
// Scene validation has a separate production-projection suite in
// check_scene_topology.py. This fixture isolates Scheduler/SQLite semantics.
enum SceneCapacity {
    struct Failure: Error {}
    static func showFailure(_ error: Error) {}
    static func validateTopology(group: Group? = nil, members: [Node] = [], addingMembers: [Node] = [],
                                 scene: Scene? = nil, sceneGroups: [Group] = [], sceneSnapshot: SceneTargetSnapshot? = nil) throws {}
    static func canAddDevice(to group: Group, node: Node) -> Bool { true }
}
enum WeekDay: UInt8 { case Monday = 1, Tuesday = 2, Wednesday = 4, Thursday = 8, Friday = 16, Saturday = 32, Sunday = 64 }
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
    // ACTUAL_CONFIGURATION_TRANSACTION
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    struct Network { let uuid = UUID() }
    struct Key { let networkId: Address = 1 }
    var meshNetwork: Network? = Network()
    let currentNetworkKey = Key()
    var schedules: [Schedule] = []
    var scenes: [Scene] = []
    var realNodes: [Node] = []
    var groups: [Group] = []
}
// Object/network ownership is the isolated boundary; every table operation below
// is the production Database.swift extension, including migrations and failures.
final class Schedule: Codable {
    enum TargetType: Int { case groups, devices, scene, profile }
    enum Action: UInt8 { case off = 0, on = 1, scene = 2, noAction = 15 }
    var schedulerEntry: Entry { .init(isValid: action != .noAction, sceneNumber: sceneNumber ?? 0, enabled: enabled) }
    // ACTUAL_SYNC_DIFFERENCE
    // ACTUAL_MESSAGE_HANDLES
    // ACTUAL_PROFILE_CODEC
    var id: Int, name: String, enabled: Bool
    var nodeAddresses: [Address] = [], groupAddresses: [Address] = [], sceneNumber: SceneNumber?
    var profiles: [ScheduleProfile] = [], selectTargetType: TargetType, action: Action
    var fadeTime: Int, weekDays: [WeekDay], hour: Int, minute: Int
    var needDeleteNodeAddresses: [Address] = [], needDeleteGroupAddresses: [Address] = [], needDeleteSceneNumbers: [SceneNumber] = []
    var nodeSlots: [TimedSchedulerNodeSlot]?, nodeSlotsLoadFailed = false
    var groups: [Group] = []
    var scene: Scene?
    var nodes: [Node] { MeshNetworkManager.instance.realNodes.filter { nodeAddresses.contains($0.primaryUnicastAddress) } }
    var needDeleteNodes: [Node] = [], needDeleteGroups: [Group] = [], needDeleteScenes: [Scene] = []
    func needsSync(on node: Node, contextGroup: Group? = nil) -> Bool {
        !node.schedulerSetupModels.isEmpty && targets(node: node, contextGroup: contextGroup) && node.appliedEnabled != enabled
    }
    // ACTUAL_TARGETS
    // ACTUAL_NEEDS_DELETE
    // ACTUAL_CODEC
    // ACTUAL_WEEKDAYS
    // ACTUAL_EXIST_NODES

    init(id: Int, name: String, enabled: Bool, nodeAddresses: [Address] = [], groupAddresses: [Address] = [],
         sceneNumber: SceneNumber? = nil, profiles: [ScheduleProfile] = [], selectTargetType: TargetType = .devices,
         action: Action = .on, fadeTime: Int = 0, weekDays: [WeekDay] = [.Monday], hour: Int = 8, minute: Int = 0) {
        self.id = id; self.name = name; self.enabled = enabled; self.nodeAddresses = nodeAddresses
        self.groupAddresses = groupAddresses; self.sceneNumber = sceneNumber; self.profiles = profiles
        self.selectTargetType = selectTargetType; self.action = action; self.fadeTime = fadeTime
        self.weekDays = weekDays; self.hour = hour; self.minute = minute
    }
}
extension Schedule.Action { static var turnOn: Self { .on } }
// ACTUAL_MODEL_OWNER
final class Element { var observedSceneRegister: Set<UInt16>? = []; var unicastAddress: UInt16 = 1 }
final class Model: NSObject { let parentElement: Element? = Element() }
struct Entry: Equatable {
    var isValid = false; var sceneNumber: UInt16 = 0; var enabled = true
    static func marshal(index: UInt8, entry: Self) -> Data { Data([index, entry.enabled ? 1 : 0]) }
}
struct SchedulerActionSet { let index: UInt8; let entry: Entry }
final class Node: NSObject {
    enum GroupState { case inGroup, exitFailure }
    var groupState = GroupState.inGroup
    var deviceKey: Data? = Data(repeating: 1, count: 16)
    let uuid = UUID()
    let primaryUnicastAddress: Address
    let name: String? = nil
    var group: Group?
    struct Restore { var addGroup: Group? }
    var restoreData: Restore?
    var syncReadGroup: Group? { group }
    func schedulerSetupModel(for owner: SchedulerSetupModelOwner) -> Model? {
        owner == .lightLC ? schedulerSetupModels.last : schedulerSetupModels.first
    }
    func schedulerCleanupModels(for owner: SchedulerSetupModelOwner) -> [Model] {
        schedulerSetupModels.filter { $0 !== schedulerSetupModel(for: owner) }
    }
    var network = MeshNetworkManager.instance.meshNetwork
    var subNetworkId: String? = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
    var schedulerSetupModels = [Model(), Model()]
    var collectionSchedulerSetupModel: Model? { nil }
    var allSchedulerModelEntrys: [Model: [Int: Entry]] = [:]
    var schedulerActions: [Int: Entry] = [:]
    var sceneSetupModel: Model? = Model()
    var onoffModel: Model? = Model()
    var lightnessModel: Model? = Model()
    var state = true
    var lightnessRange: ClosedRange<UInt16> = 0...65535
    var effectiveCctRange: ClosedRange<UInt16> = 2700...6500
    var effectiveSupportCct = true
    func clampEffectiveCct(_ value: UInt16) -> UInt16 { min(effectiveCctRange.upperBound, max(effectiveCctRange.lowerBound, value)) }
    // ACTUAL_SCENE_REMOVAL
    var sceneExecuteDatas: [SceneExecuteData] = []
    var iconName = "fixture"
    var appliedMessages = 0
    var appliedEnabled = false
    var exitSchedules: [Schedule] = []
    enum SyncType { case group(Group?) }
    func getSyncData(type: SyncType) -> [NodeSyncData] { exitSchedules.isEmpty ? [] : [.deleteSchedules(exitSchedules)] }
    init(_ address: Address) {
        primaryUnicastAddress = address
        super.init()
        for (index, model) in schedulerSetupModels.enumerated() { model.parentElement?.unicastAddress = address + UInt16(index) }
        schedulerSetupModels.forEach { allSchedulerModelEntrys[$0] = [:] }
    }
    func clearSyncStateCache() {}
    func completeGroupSceneRemoval(sceneId: UInt16) -> Bool { true } // Scene lifecycle is exercised by the Scene suite.
    var scheduleIds: [Int] = []
    var propertiesSaveSucceeds = true
    @discardableResult func savePropertys() -> Bool { propertiesSaveSucceeds }
    func rebuildTimedSchedulerActions() {
        schedulerActions = allSchedulerModelEntrys.values.reduce(into: [:]) { result, entries in
            result.merge(entries) { _, new in new }
        }
    }
    func updateData(message: Any, isSuccess: Bool, model: Model?, finalizeSchedulerBinding: Bool = true) {
        guard isSuccess else { return }
        appliedMessages += 1
        switch message {
        // ACTUAL_SCHEDULER_ACK
        default: break
        }
    }
}
extension Data { var hex: String { map { String(format: "%02X", $0) }.joined() } }
final class Group: NSObject {
    struct GroupAddress: Equatable { var address: Address = 0xC001 }
    var address = GroupAddress(), name: String? = nil
    var nodes: [Node] = []
    final class Info {
        struct Profile { enum Kind { case manualControl, automatic }; var type = Kind.automatic }
        var profile = Profile()
        var sceneExecuteDatas: [SceneExecuteData] = []; var bindSchedules: [Schedule] = []
    }
    let info = Info()
    // ACTUAL_GROUP_EXIT
    // ACTUAL_SCENE_READER
}
enum NodeSyncData {
    case deleteSchedules([Schedule])
    case syncSchedules(schedules: [Schedule])
    case syncScenes(datas: [SceneExecuteData])
    case deleteScenes(scenes: [Scene])
    func getMessageHandles(node: Node) -> [MeshMessageHandle] { [MeshMessageHandle()] }
}
final class SceneExecuteData: Codable {
    enum State: String, Codable { case normal, waitDelete }
    let sceneNumber: UInt16
    var state = State.normal
    var value = 1
    var isOn = true
    var lightness: UInt16 = 65535
    var cct: UInt16 = 4500
    init(sceneNumber: UInt16 = 6, isOn: Bool = true, lightness: UInt16 = 65535, cct: UInt16 = 4500) {
        self.sceneNumber = sceneNumber; self.isOn = isOn; self.lightness = lightness; self.cct = cct
    }
    func deviceTarget(for node: Node) -> SceneExecuteData {
        .init(sceneNumber: sceneNumber, isOn: isOn, lightness: isOn ? lightness : 0,
              cct: node.effectiveSupportCct ? node.clampEffectiveCct(cct) : cct)
    }
    func isSynced(with other: SceneExecuteData, for node: Node) -> Bool { value == other.value }
}
final class NodeSyncReadContext {
    static var current: NodeSyncReadContext? { nil }
    func contains(_ node: Node, in group: Group) -> Bool { group.nodes.contains(node) }
    func sceneGroup(for node: Node) -> Group? { node.group }
    func memoized<Value>(_ key: String, read: () -> Value) -> Value { read() }
}
final class Scene: NSObject {
    let number: UInt16
    init(_ number: UInt16 = 6) { self.number = number }
    let name = "Scene"
    var network = MeshNetworkManager.instance.meshNetwork
    var subNetworkId = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
    final class Info {
        var groups: [Group] = []; var bindSchedules: [Schedule] = []
        var configuration: SceneConfiguration?
        var configurationLoadFailed = false
        var imageId = 0
    }
    let info = Info()
}
// This suite has no durable cascade references. Production reference discovery,
// task dependencies and admission gates run in check_scene_deletion_cascade.py.
enum SceneDeletionCascade {
    private static func requireEmptyReferences() {
        precondition(MeshNetworkManager.instance.scenes.allSatisfy {
            $0.info.configuration?.deletionReferences?.pending.isEmpty != false
        }, "Reference cleanup must use the production cascade suite")
    }
    static func appendTasks(scene: Scene, to section: SyncDevicesSectionModel) -> [SyncDeviceStepModel] {
        requireEmptyReferences(); return []
    }
    static func permitsReferences(_ numbers: [UInt16], meshUUID: String, networkID: String) -> Bool {
        requireEmptyReferences(); return true
    }
    static func owns(scheduleID: Int, meshUUID: String, networkID: String) -> Bool {
        requireEmptyReferences(); return false
    }
}
final class MeshMessageHandle: NSObject {
    var schedulerTask: MeshSchedulerTask?; var sceneContext: SceneMessageContext?; var message: Any = 0; var model: Model?; var continuous = true
    var schedulerAdmission: (() -> Void)?
    var transmissionIsValid: (() -> Bool)?, responseIsValid: ((MeshMessage) -> Bool)?
    var allAddresss: [Address] { [model?.parentElement?.unicastAddress ?? 1] }
    var respondAddresss: [Address] = []
    // ACTUAL_SCHEDULER_SUCCESS
    override init() { super.init() }
    init(message: Any, model: Model) { self.message = message; self.model = model }
}
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand(); var isBusy = false
    func cancelSchedulerTasks(_ tasks: [MeshSchedulerTask]) { tasks.forEach { $0.cancel() } }
}
enum XWHUDManager { static func showTipHUD(_ message: String, isLineFeed: Bool) {} }
// Minimal Space column adapter backed by the same real SQLite connection;
// Schedule codec/save/load and nested transactions are production implementations.
final class SpaceData {
    enum Permission { case owner, editor, visitor }
    static var savesSucceed = true
    var permission = Permission.owner
    var timedSchemaVersion = 1
    var meshUUID = MeshNetworkManager.instance.meshNetwork!.uuid.uuidString
    var lastUpdate: Int64 = 10, lastUploadCloudTimestamp: Int64? = 10
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) }
    static func load(subNetworkId: String) -> SpaceData? {
        guard let db = SunSmartDataManager.shared.db else { return nil }
        let space = SpaceData()
        try! db.execute("CREATE TABLE IF NOT EXISTS timed_test_spaces (mesh TEXT PRIMARY KEY, revision INTEGER, confirmed INTEGER, schemaVersion INTEGER)")
        if let row = try! db.prepare("SELECT revision, confirmed, schemaVersion FROM timed_test_spaces WHERE mesh = ?", space.meshUUID).first(where: { _ in true }) {
            space.lastUpdate = row[0] as! Int64
            space.lastUploadCloudTimestamp = row[1] as? Int64
            space.timedSchemaVersion = Int(row[2] as! Int64)
        }
        return space
    }
    @discardableResult func save() -> Bool {
        guard Self.savesSucceed, let db = SunSmartDataManager.shared.db else { return false }
        do {
            if let old = Self.load(subNetworkId: "") {
                lastUpdate = max(lastUpdate, old.lastUpdate)
                timedSchemaVersion = max(timedSchemaVersion, old.timedSchemaVersion)
            }
            try db.run("INSERT OR REPLACE INTO timed_test_spaces VALUES (?, ?, ?, ?)", meshUUID, lastUpdate, lastUploadCloudTimestamp, timedSchemaVersion)
            return true
        } catch { return false }
    }
    // ACTUAL_MARK_LOCAL_CHANGE
    // ACTUAL_MARK_UPLOAD
}
enum SpaceConfigurationSafety {
    enum SafetyError: Error { case persistenceFailed }
    static var missingTimedBaseline = false
    static func needsTimedUpgradeBaseline(_ space: SpaceData) -> Bool { missingTimedBaseline }
}
// Transport completion is controlled; reservation, enabled-state handling and
// SQLite persistence execute production code.
enum ScheduleServer {
    typealias ScheduleOperateSuccessCallback = (Schedule) -> Void
    typealias ScheduleOperateFailedCallback = (Schedule) -> Void
    static var successfulAddresses = Set<Address>()
    static var beforeCompletion: (() -> Void)?
    static func saveSchedule(schedule: Schedule, setNodes: [Node],
                             success: ScheduleOperateSuccessCallback?, failed: ScheduleOperateFailedCallback?) {
        var hasFailure = false
        for node in setNodes {
            guard TimedSchedulerBindings.reserveForSending(schedule: schedule, node: node, contextGroup: nil) else {
                hasFailure = true
                continue
            }
            if successfulAddresses.contains(node.primaryUnicastAddress) { node.appliedEnabled = schedule.enabled }
            else { hasFailure = true }
        }
        beforeCompletion?()
        if hasFailure { failed?(schedule) } else { success?(schedule) }
    }
    // ACTUAL_TOGGLE
}
@main struct Run {
    enum Failure: Error { case rollback }
    static func main() throws {
        let path = CommandLine.arguments[1]
        var db = try Connection(path)
        SunSmartDataManager.shared.db = db
        Schedule.initDatabase()
        try schedulerResultPersistence(path: path)
        try timedCleanupRoundTrip(path: path)
        try localIntentRevision(path: path)
        try nativeProfileBindingsSurviveUnrelatedEdits(db: db, path: path)
        try legacyCleanupRequiresOwnedSlot()
        try v3PersistenceAndProgress(db: db, path: path)
        try deviceSceneReferences()
        try staleBindingsSurviveRepairAndRestart(db: db, path: path)
        try defaultedBindingsSurviveReload()
        try missingV2BindingsSurviveRestart(db: db, path: path)
        for id in 0..<16 {
            precondition(Schedule(id: id, name: "Schedule \(id + 1)", enabled: false).save(meshUUID: "mesh", meshNetworkId: "one"))
        }
        try db.execute("ALTER TABLE schedules DROP COLUMN nodeSlots")
        Schedule.initDatabase()
        let old = Schedule.load(meshUUID: "mesh", meshNetworkId: "one")
        precondition(old.count == 16 && old.allSatisfy { $0.nodeSlots == nil && !$0.nodeSlotsLoadFailed })
        precondition(Schedule.getNextScheduleName(meshUUID: "mesh", meshNetworkId: "one", defaultName: "Schedule ") == "Schedule 17")
        let item = Schedule(id: 300, name: "Beyond Space 16", enabled: false, nodeAddresses: [1])
        item.nodeSlots = [.init(identity: .init(nodeUUID: "11111111-1111-1111-1111-111111111111",
            unicastAddress: "0001", deviceKeyFingerprint: String(repeating: "a", count: 64)), slot: 7, state: .pendingRemoval)]
        item.needDeleteNodeAddresses = [1]
        item.needDeleteGroupAddresses = [0xC001]
        item.needDeleteSceneNumbers = [6]
        do {
            try db.transaction {
                precondition(item.save(meshUUID: "mesh", meshNetworkId: "one"))
                throw Failure.rollback
            }
        } catch Failure.rollback {}
        precondition(Schedule.load(meshUUID: "mesh", meshNetworkId: "one").count == 16)
        precondition(item.save(meshUUID: "mesh", meshNetworkId: "one"))
        precondition(Schedule.load(meshUUID: "mesh", meshNetworkId: "two").isEmpty)
        SunSmartDataManager.shared.db = nil
        db = try Connection(path)
        SunSmartDataManager.shared.db = db
        let loaded = Schedule.load(meshUUID: "mesh", meshNetworkId: "one", scheduleId: 300).first!
        precondition(loaded.nodeSlots == item.nodeSlots && loaded.needDeleteNodeAddresses == [1])
        precondition(loaded.needDeleteGroupAddresses == [0xC001] && loaded.needDeleteSceneNumbers == [6])
        for value: Any in [UUID().uuidString, NSNull(), 123, ["bad": true], "invalid"] {
            var raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(item.nodeSlots!)) as! [[String: Any]]
            raw[0]["generation"] = value
            let bytes = try JSONSerialization.data(withJSONObject: raw).map { String(format: "%02X", $0) }.joined()
            try db.execute("UPDATE schedules SET nodeSlots = X'\(bytes)' WHERE scheduleIndex = 300")
            SunSmartDataManager.shared.db = nil
            db = try Connection(path); SunSmartDataManager.shared.db = db
            let legacy = Schedule.load(meshUUID: "mesh", meshNetworkId: "one", scheduleId: 300).first!
            precondition(!legacy.nodeSlotsLoadFailed && legacy.nodeSlots == item.nodeSlots)
            precondition(legacy.save(meshUUID: "mesh", meshNetworkId: "one"))
            let saved = Schedule.load(meshUUID: "mesh", meshNetworkId: "one", scheduleId: 300).first!
            let output = try JSONSerialization.jsonObject(with: JSONEncoder().encode(saved.nodeSlots!)) as! [[String: Any]]
            precondition(output.allSatisfy { $0["generation"] == nil })
        }
        try db.execute("UPDATE schedules SET nodeSlots = X'FFFF' WHERE scheduleIndex = 300")
        let damaged = Schedule.load(meshUUID: "mesh", meshNetworkId: "one", scheduleId: 300).first!
        precondition(damaged.nodeSlotsLoadFailed && !damaged.save(meshUUID: "mesh", meshNetworkId: "one"))
        try runtimeReservationsAndLateReplies(db: db)
        try groupExitReleasesOnlyClearedNode(db: db)
        try groupExitWithNoDeviceCleanup()
        try topologyKeepsPendingExits()
        try migrationRequiresPersistedBaseline()
        try sceneRecoveryRebuildsTimedTasks()
        try enabledFailurePersistsRollback(db: db)
        unknownDeviceCapacityIsDeferred()
        sceneRemovalIsNotAnActiveTarget()
        try emptyTargetsSurviveReload(db: db, path: path)
        try profileSchedulesSurviveRestore(path: path)
        try missingPropertiesSurviveRestore(path: path)
        SunSmartDataManager.shared.db = nil
        precondition(!item.save(meshUUID: "mesh", meshNetworkId: "one"), "missing database cannot confirm a saved reservation")
        print("PASS: production Schedule SQLite migration, 17th logical record, restart, pending cleanup, corruption and rollback")
    }
    static func missingPropertiesSurviveRestore(path: String) throws {
        let file = path + ".legacy-properties"
        SunSmartDataManager.shared.db = try Connection(file)
        Schedule.initDatabase()
        let legacy: [String: Any] = ["nodes": [], "schedules": [["id": 0]]]
        let normalized = TimedSchedulerPayloadPolicy.fillingMissingBindings(legacy)
        let wire = try JSONSerialization.data(withJSONObject: normalized["schedules"]!)
        let schedule = try JSONDecoder().decode([Schedule].self, from: wire)[0]
        precondition(schedule.name.isEmpty && !schedule.enabled && schedule.fadeTime == 0)
        precondition(schedule.save(meshUUID: "legacy", meshNetworkId: "legacy"))
        SunSmartDataManager.shared.db = try Connection(file)
        let restored = Schedule.load(meshUUID: "legacy", meshNetworkId: "legacy")
        precondition(restored.count == 1)
        var readback = legacy
        readback["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored))
        precondition(TimedSchedulerPayloadPolicy.canonical(readback) == TimedSchedulerPayloadPolicy.canonical(legacy))
        print("PASS: missing Schedule properties -> production Codable -> SQLite restart/export -> equivalent cloud comparison")
    }

    static func profileSchedulesSurviveRestore(path: String) throws {
        let file = path + ".profiles"
        SunSmartDataManager.shared.db = try Connection(file)
        Schedule.initDatabase()
        let rows: [[String: Any]] = (0..<2).map { id in
            ["id": id, "name": "Profile \(id)", "enabled": true, "selectTarget": 3,
             "sceneAddress": "", "profiles": [["groupAddress": "C001", "profileSceneNumber": "FF00", "groupName": "Group 1", "type": 3]],
             "action": 2, "hour": 14 + id, "minute": 28, "dayOfWeek": 127, "fadeTime": 2]
        }
        let remote: [String: Any] = ["nodes": [], "schedules": rows, "spaceData": ["timedSchemaVersion": 1]]
        let decoded = try JSONDecoder().decode([Schedule].self, from: JSONSerialization.data(withJSONObject: rows))
        let manager = MeshNetworkManager.instance
        let mesh = manager.meshNetwork!.uuid.uuidString, network = manager.currentNetworkKey.networkId.hex
        for row in decoded { precondition(row.save(meshUUID: mesh, meshNetworkId: network)) }
        SunSmartDataManager.shared.db = try Connection(file)
        let restored = Schedule.load(meshUUID: mesh, meshNetworkId: network)
        precondition(restored.count == 2 && restored.allSatisfy { $0.profiles.first?.groupName == "Group 1" && $0.profiles.first?.type == 3 })
        var readback = remote
        readback["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored))
        precondition(TimedSchedulerPayloadPolicy.canonical(readback) == TimedSchedulerPayloadPolicy.canonical(remote))
        manager.schedules = restored
        let node = Node(1), group = Group(), unrelated = Group()
        unrelated.address.address = 0xC002
        node.group = group; group.nodes = [node]; manager.realNodes = [node]; manager.groups = [group, unrelated]
        let profile = restored.first!
        node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = [profile.id: Entry(isValid: true)] }
        precondition(!profile.targets(node: node) && !profile.needsDelete(from: node))
        precondition(!TimedSchedulerBindings.reserveForSending(schedule: profile, node: node, contextGroup: group))
        precondition(!TimedSchedulerBindings.reserveForDeletion(schedule: profile, node: node))
        var failed = false
        ScheduleServer.setEnabledState(schedule: profile, enabled: false, success: { _ in preconditionFailure("unsupported success") }, failed: { _ in failed = true })
        precondition(failed && profile.enabled && node.appliedMessages == 0)
        precondition(!TimedSchedulerBindings.canAddDevice(to: group, node: node))
        precondition(group.getNodeExitMessageHandles(node: node) == nil && node.groupState == .inGroup)
        do { _ = try TimedSchedulerBindings.prepareTopology(group: group); preconditionFailure("protected Group") }
        catch TimedSchedulerBindings.Failure.unsupportedProfile {}
        let ordinary = Schedule(id: 300, name: "Ordinary", enabled: true, nodeAddresses: [1]); ordinary.nodeSlots = []
        manager.schedules.append(ordinary)
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules))
        precondition(restored.allSatisfy { $0.slot(on: node) == $0.id && $0.nodeSlots?.first?.state == .pendingApply })
        precondition(ordinary.slot(on: node) == 2)
        let preserved = profile.nodeSlots!
        profile.nodeSlots![0].state = .pendingRemoval
        let pending = profile.nodeSlots!
        node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = [:] }
        profile.releaseClearedBinding(on: node)
        precondition(profile.nodeSlots == pending)
        let plan = try TimedSchedulerBindings.prepare(schedules: manager.schedules)
        precondition(plan.bindings[profile.id] == pending)
        profile.nodeSlots = preserved
        node.group = unrelated
        precondition(TimedSchedulerBindings.canAddDevice(to: unrelated, node: node))
        precondition(unrelated.getNodeExitMessageHandles(node: node) != nil, "unrelated Group exit must not attempt to delete preserved Profile slots")
        _ = try TimedSchedulerBindings.prepareTopology(group: unrelated)
        print("PASS: Profile GET/Codable/SQLite restart, readback equality, read-only toggle, protected topology and reserved slots")
    }

    static func nativeProfileBindingsSurviveUnrelatedEdits(db originalDB: Connection, path: String) throws {
        let file = path + ".native-profiles"
        SunSmartDataManager.shared.db = try Connection(file)
        Schedule.initDatabase()
        let manager = MeshNetworkManager.instance, node = Node(1)
        let mesh = manager.meshNetwork!.uuid.uuidString, network = manager.currentNetworkKey.networkId.hex
        manager.realNodes = [node]
        defer {
            SunSmartDataManager.shared.db = originalDB
            manager.realNodes = []; manager.schedules = []
        }
        // The shared Profile route is valid but differs from this App's ordinary
        // routing inference. Both the route and the remote result are read-only.
        let states: [TimedSchedulerNodeSlot.State] = [.synced, .pendingApply, .pendingRemoval]
        let rows: [[String: Any]] = states.enumerated().map { slot, state in
            ["id": 100 + slot, "name": "Profile \(slot)", "enabled": true, "selectTarget": 3,
             "sceneAddress": NSNull(), "profiles": [["groupAddress": "C001", "profileSceneNumber": "FF00", "groupName": "Group 1", "type": 3]],
             "action": 2, "hour": 8, "minute": 0, "dayOfWeek": 127, "fadeTime": 0,
             "nodeSlots": [["identity": ["unicastAddress": "0001"], "slot": slot, "state": state.rawValue,
                            "actionAddress": ["auto_on": "0002", "off": "0001", "recall": "0001"]]]]
        }
        let payload: [String: Any] = ["spaceData": ["timedSchemaVersion": 3], "schedules": rows,
            "nodes": [["uuid": node.uuid.uuidString, "unicastAddress": "0001", "deviceKey": node.deviceKey!.hex,
                "elements": [["index": 0, "models": [["modelId": "1206"], ["modelId": "1207"]]],
                             ["index": 1, "models": [["modelId": "130F"], ["modelId": "1206"], ["modelId": "1207"]]]]]]]
        let decoded = try JSONDecoder().decode([Schedule].self, from: JSONSerialization.data(
            withJSONObject: TimedSchedulerPayloadPolicy.decodingSchedules(payload)!))
        for schedule in decoded { precondition(schedule.save()) }
        SunSmartDataManager.shared.db = try Connection(file)
        let restored = Schedule.load(meshUUID: mesh, meshNetworkId: network).sorted { $0.id < $1.id }
        let expected = restored.map(\.nodeSlots)
        let ordinary = Schedule(id: 300, name: "Unrelated", enabled: true, nodeAddresses: [1])
        ordinary.nodeSlots = []
        manager.schedules = restored + [ordinary]
        let plan = try TimedSchedulerBindings.prepare(schedules: manager.schedules)
        precondition(restored.map { plan.bindings[$0.id] } == expected,
                     "unrelated reservation must preserve every native Profile binding")
        do {
            try TimedSchedulerBindings.commit(plan) { throw Failure.rollback }
            preconditionFailure("injected failure must abort reservation")
        } catch Failure.rollback {}
        precondition(restored.map(\.nodeSlots) == expected && ordinary.nodeSlots == [])
        // Exercise retry after restart. SQLite's failed savepoint leaves its
        // outer transaction open until the connection closes.
        SunSmartDataManager.shared.db = try Connection(file)
        precondition(Schedule.load(meshUUID: mesh, meshNetworkId: network).sorted { $0.id < $1.id }.map(\.nodeSlots) == expected)
        try TimedSchedulerBindings.commit(plan)
        precondition(ordinary.slot(on: node) == 3, "all Profile states must retain their reserved slots")
        // Unknown local Model observations cannot invalidate a shared Profile result.
        node.allSchedulerModelEntrys = [:]
        ordinary.enabled = false
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules))
        SunSmartDataManager.shared.db = try Connection(file)
        let reopened = Schedule.load(meshUUID: mesh, meshNetworkId: network).sorted { $0.id < $1.id }
        precondition(Array(reopened.prefix(3)).map(\.nodeSlots) == expected)
        precondition(reopened.last?.nodeSlots?.first?.state == .pendingApply)
        var readback = payload
        readback["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Array(reopened.prefix(3))))
        let exported = TimedSchedulerPayloadPolicy.exportPayload(readback)!
        precondition(TimedSchedulerPayloadPolicy.canonical(exported) == TimedSchedulerPayloadPolicy.canonical(payload))
        print("PASS: native Profile states/routes survive unrelated reservations, rollback/retry, unknown Models, SQLite reopen and cloud export")
    }

    static func staleBindingsSurviveRepairAndRestart(db originalDB: Connection, path: String) throws {
        let file = path + ".stale-bindings"
        let db = try Connection(file)
        SunSmartDataManager.shared.db = db
        Schedule.initDatabase()
        defer { SunSmartDataManager.shared.db = originalDB }
        let old = Node(1), current = Node(5)
        let oldIdentity = old.timedSchedulerIdentity!, currentIdentity = current.timedSchedulerIdentity!
        for id in 0..<16 {
            let schedule = Schedule(id: id, name: "Retained \(id)", enabled: true, nodeAddresses: [1, 5])
            schedule.needDeleteNodeAddresses = [1]
            schedule.nodeSlots = [.init(identity: oldIdentity, slot: id, state: .assigned),
                                  .init(identity: currentIdentity, slot: id, state: .assigned)]
            precondition(schedule.save(meshUUID: "repair", meshNetworkId: "one"))
        }
        let stored = Schedule.load(meshUUID: "repair", meshNetworkId: "one").sorted { $0.id < $1.id }
        let nodes: [[String: Any]] = [
            ["uuid": currentIdentity.nodeUUID, "unicastAddress": "0005", "deviceKey": current.deviceKey!.hex],
            ["uuid": oldIdentity.nodeUUID, "unicastAddress": "0009", "deviceKey": String(repeating: "2", count: 32)]
        ]
        let payload: [String: Any] = ["spaceData": ["timedSchemaVersion": 2], "nodes": nodes,
            "schedules": try JSONSerialization.jsonObject(with: jsonEncoder.encode(stored))]
        let repaired = TimedSchedulerPayloadPolicy.repairingStaleBindings(payload)!
        let schedules = try jsonDecoder.decode([Schedule].self, from: JSONSerialization.data(withJSONObject: repaired["schedules"]!))
        try db.execute("CREATE TRIGGER fail_stale_repair BEFORE INSERT ON schedules WHEN NEW.scheduleIndex = 8 BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        func persist() throws {
            try db.transaction {
                for schedule in schedules {
                    guard schedule.save(meshUUID: "repair", meshNetworkId: "one") else { throw Failure.rollback }
                }
            }
        }
        do { try persist(); preconditionFailure("write failure must abort all repairs") } catch Failure.rollback {}
        let failed = Schedule.load(meshUUID: "repair", meshNetworkId: "one")
        precondition(failed.count == 16 && failed.allSatisfy { $0.nodeSlots?.count == 2 && $0.nodeAddresses == [1, 5] })
        try db.execute("DROP TRIGGER fail_stale_repair")
        try persist()
        SunSmartDataManager.shared.db = try Connection(file)
        let reopened = Schedule.load(meshUUID: "repair", meshNetworkId: "one").sorted { $0.id < $1.id }
        precondition(reopened.map(\.id) == Array(0..<16))
        precondition(reopened.allSatisfy { $0.nodeSlots?.count == 1 && $0.nodeSlots?.first?.identity == currentIdentity
            && $0.nodeAddresses == [5] && $0.needDeleteNodeAddresses.isEmpty && $0.enabled })
        precondition(reopened.map(\.name) == stored.map(\.name))
        var readback = payload
        readback["schedules"] = try JSONSerialization.jsonObject(with: jsonEncoder.encode(reopened))
        precondition(TimedSchedulerPayloadPolicy.canonical(readback) == TimedSchedulerPayloadPolicy.canonical(payload))
        precondition(TimedSchedulerPayloadPolicy.canonical(readback) != nil)
        print("PASS: stale-instance repair keeps 16 schedules/current bindings; SQLite failure rolls back, retry and reopen retain the repair")
    }

    static func emptyTargetsSurviveReload(db originalDB: Connection, path originalPath: String) throws {
        let manager = MeshNetworkManager.instance
        let mesh = manager.meshNetwork!.uuid.uuidString, network = manager.currentNetworkKey.networkId.hex
        // Earlier fixtures inject savepoint failures. Use an independent database
        // so this normal reopen test does not inherit their transaction state.
        let path = originalPath + ".empty-targets"
        let db = try Connection(path)
        SunSmartDataManager.shared.db = db
        Schedule.initDatabase()
        defer { SunSmartDataManager.shared.db = originalDB; manager.realNodes = []; manager.schedules = [] }
        for kind in [Schedule.TargetType.groups, .scene] {
            precondition(Schedule.deleteAll(meshUUID: mesh, meshNetworkId: network))
            manager.realNodes = []; manager.schedules = []
            let group = Group(), scene = Scene()
            for id in 0..<17 {
                let schedule = Schedule(id: id, name: "Empty \(id)", enabled: true,
                    groupAddresses: kind == .groups ? [group.address.address] : [],
                    sceneNumber: kind == .scene ? scene.number : nil, selectTargetType: kind)
                schedule.groups = kind == .groups ? [group] : []
                schedule.scene = kind == .scene ? scene : nil
                schedule.nodeSlots = []
                let candidates = manager.schedules + [schedule]
                try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: candidates))
                manager.schedules = candidates
            }
            SunSmartDataManager.shared.db = try Connection(path)
            let reloaded = Schedule.load(meshUUID: mesh, meshNetworkId: network).sorted { $0.id < $1.id }
            precondition(reloaded.map(\.id) == Array(0..<17) && reloaded.allSatisfy { $0.nodeSlots == [] },
                         "empty targets must survive a new SQLite connection with all IDs and empty bindings")
            let decoded = try jsonDecoder.decode([Schedule].self, from: jsonEncoder.encode(reloaded))
            precondition(decoded.count == 17 && decoded.allSatisfy { $0.nodeSlots == [] })
            precondition(decoded.map(\.groupAddresses) == reloaded.map(\.groupAddresses))
            precondition(decoded.map(\.sceneNumber) == reloaded.map(\.sceneNumber))
            SunSmartDataManager.shared.db = db
            // A legitimate empty configuration must still reject an overloaded
            // device when Group membership or Scene targets are added later.
            let node = Node(1)
            manager.realNodes = [node]; group.nodes = [node]; node.group = group
            do {
                _ = try kind == .groups
                    ? TimedSchedulerBindings.prepareTopology(group: group, members: [node], addingMembers: [node])
                    : TimedSchedulerBindings.prepareTopology(scene: scene, sceneGroups: [group])
                preconditionFailure("17 empty-target schedules cannot all be assigned to one device")
            } catch TimedSchedulerBindings.Failure.deviceCapacity { }
            precondition(manager.schedules.allSatisfy { $0.nodeSlots == [] })
            try db.execute("PRAGMA query_only = ON")
            precondition(!reloaded[0].deleteData(meshUUID: mesh, meshNetworkId: network))
            precondition(Schedule.load(meshUUID: mesh, meshNetworkId: network).count == 17)
            try db.execute("PRAGMA query_only = OFF")
            precondition(reloaded[0].deleteData(meshUUID: mesh, meshNetworkId: network))
            precondition(Schedule.load(meshUUID: mesh, meshNetworkId: network).count == 16)
            print("PASS: empty target \(kind) keeps 17 records through reservation, SQLite reopen and Codable; later device capacity and failed deletion remain protected")
        }
    }
    static func missingV2BindingsSurviveRestart(db originalDB: Connection, path: String) throws {
        let file = path + ".missing-v2-bindings"
        SunSmartDataManager.shared.db = try Connection(file)
        Schedule.initDatabase()
        defer { SunSmartDataManager.shared.db = originalDB }
        let node = Node(1), identity = node.timedSchedulerIdentity!
        let originals = (0..<6).map { id in
            Schedule(id: id, name: "Mixed \(id)", enabled: id >= 3, sceneNumber: 0x0661, selectTargetType: .scene, action: .scene)
        }
        for id in 0..<3 {
            originals[id].nodeSlots = [.init(identity: identity, slot: id, state: .assigned)]
        }
        originals[5].nodeSlots = []
        var rows = try JSONSerialization.jsonObject(with: jsonEncoder.encode(originals)) as! [[String: Any]]
        rows[4]["nodeSlots"] = NSNull()
        let source: [String: Any] = ["spaceData": ["timedSchemaVersion": 2], "schedules": rows,
            "nodes": [["uuid": identity.nodeUUID, "unicastAddress": identity.unicastAddress, "deviceKey": node.deviceKey!.hex]]]
        let normalized = TimedSchedulerPayloadPolicy.repairingStaleBindings(source)!
        let schedules = try jsonDecoder.decode([Schedule].self, from: JSONSerialization.data(withJSONObject: normalized["schedules"]!))
        for schedule in schedules { precondition(schedule.save(meshUUID: "mixed-v2", meshNetworkId: "one")) }
        let unrelated = Schedule(id: 0, name: "Other Space", enabled: true)
        unrelated.nodeSlots = []
        precondition(unrelated.save(meshUUID: "mixed-v2", meshNetworkId: "two"))
        SunSmartDataManager.shared.db = try Connection(file)
        let reloaded = Schedule.load(meshUUID: "mixed-v2", meshNetworkId: "one").sorted { $0.id < $1.id }
        precondition(reloaded.map(\.id) == Array(0..<6) && reloaded.map(\.enabled) == originals.map(\.enabled))
        precondition(reloaded.prefix(3).map(\.nodeSlots) == originals.prefix(3).map(\.nodeSlots))
        precondition(reloaded.suffix(3).allSatisfy { $0.nodeSlots == [] && $0.slot(on: node) == nil })
        var exported = source
        exported["schedules"] = try JSONSerialization.jsonObject(with: jsonEncoder.encode(reloaded))
        precondition(TimedSchedulerPayloadPolicy.canonical(exported) == TimedSchedulerPayloadPolicy.canonical(source))
        precondition(Schedule.deleteAll(meshUUID: "mixed-v2", meshNetworkId: "one"))
        precondition(Schedule.load(meshUUID: "mixed-v2", meshNetworkId: "one").isEmpty)
        precondition(Schedule.load(meshUUID: "mixed-v2", meshNetworkId: "two").count == 1)
        print("PASS: mixed v2 missing/null/empty/assigned bindings survive SQLite restart, export and scoped Space cleanup")
    }
    static func defaultedBindingsSurviveReload() throws {
        let manager = MeshNetworkManager.instance
        let a = Node(1), b = Node(5)
        let originals = (0..<17).map { id in
            Schedule(id: id, name: "Kept \(id)", enabled: true, nodeAddresses: [id < 16 ? 1 : 5])
        }
        // Production old-format encoding omits nil bindings. The import adapter
        // must supply defaults before the production decoder sees logical ID 16.
        let rows = try JSONSerialization.jsonObject(with: jsonEncoder.encode(originals))
        let source: [String: Any] = ["schedules": rows]
        let normalized = TimedSchedulerPayloadPolicy.fillingMissingBindings(source)
        let data = try JSONSerialization.data(withJSONObject: normalized["schedules"]!)
        let decoded = try jsonDecoder.decode([Schedule].self, from: data)
        precondition(decoded.count == 17 && decoded.allSatisfy { $0.nodeSlots == [] })
        precondition(decoded.last?.id == 16 && decoded.last?.name == "Kept 16" && decoded.last?.nodeAddresses == [5])
        for schedule in decoded {
            precondition(schedule.save(meshUUID: "defaulted", meshNetworkId: "one"))
        }
        let reloaded = Schedule.load(meshUUID: "defaulted", meshNetworkId: "one").sorted { $0.id < $1.id }
        precondition(reloaded.count == 17 && reloaded.allSatisfy { $0.nodeSlots == [] && !$0.nodeSlotsLoadFailed })
        let roundTrip = try jsonDecoder.decode([Schedule].self, from: jsonEncoder.encode(reloaded))
        precondition(roundTrip.map(\.id) == Array(0..<17) && roundTrip.allSatisfy { $0.nodeSlots == [] })
        manager.realNodes = [a, b]; manager.schedules = reloaded
        for node in [a, b] {
            node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [0: Entry(isValid: true)]
            node.schedulerActions = [0: Entry(isValid: true)]
        }
        precondition(reloaded.allSatisfy { $0.slot(on: a) == nil && $0.slot(on: b) == nil })
        precondition(reloaded.allSatisfy { !$0.needsDelete(from: a) && !$0.needsDelete(from: b) },
                     "unassigned defaults must never identify another schedule's physical slot for deletion")
        a.allSchedulerModelEntrys[a.schedulerSetupModels[0]] = Dictionary(uniqueKeysWithValues: (0..<16).map { ($0, Entry(isValid: true)) })
        do {
            _ = try TimedSchedulerBindings.prepare(schedules: reloaded)
            preconditionFailure("unknown occupied slots cannot be overwritten")
        } catch TimedSchedulerBindings.Failure.deviceCapacity { }
        precondition(reloaded.allSatisfy { $0.nodeSlots == [] }, "failed planning must not mutate defaulted schedules")
        for node in [a, b] {
            node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [:]
            node.schedulerActions = [:]
        }
        let plan = try TimedSchedulerBindings.prepare(schedules: reloaded)
        try TimedSchedulerBindings.commit(plan)
        precondition(reloaded[0].slot(on: a) == 0 && reloaded[0].slot(on: b) == nil)
        precondition(reloaded[16].slot(on: b) == 0 && reloaded[16].slot(on: a) == nil)
        manager.realNodes = []; manager.schedules = []
        print("PASS: defaulted 17 schedules decode, persist and reload; deletion ignores unknown slots; capacity failure/retry allocates per device")
    }
    static func groupExitReleasesOnlyClearedNode(db: Connection) throws {
        let manager = MeshNetworkManager.instance
        let a = Node(1), b = Node(5), group = Group()
        group.nodes = [a, b]; a.group = group; b.group = group
        manager.realNodes = [a, b]
        let direct = (0..<15).map { id in
            Schedule(id: id, name: "Direct", enabled: true, nodeAddresses: [1])
        }
        let grouped = Schedule(id: 15, name: "Group", enabled: true, groupAddresses: [group.address.address])
        grouped.groups = [group]
        manager.schedules = direct + [grouped]
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules))
        let assigned = grouped.nodeSlots!
        a.exitSchedules = [grouped]
        // Failure must stop the Group batch, not silently omit its clear messages.
        try db.execute("PRAGMA query_only = ON")
        precondition(group.getNodeExitMessageHandles(node: a) == nil)
        precondition(grouped.nodeSlots == assigned)
        try db.execute("PRAGMA query_only = OFF")
        precondition(group.getNodeExitMessageHandles(node: a)?.isEmpty == false)
        let pending = grouped.nodeSlots!
        precondition(pending.first { $0.identity == a.timedSchedulerIdentity }?.state == .pendingRemoval)
        precondition(pending.first { $0.identity == b.timedSchedulerIdentity }?.state == .pendingApply)
        precondition(zip(assigned, pending).allSatisfy { $0.slot == $1.slot && $0.identity == $1.identity })
        let reloaded = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: grouped.id).first!
        precondition(reloaded.nodeSlots == pending)
        let slot = grouped.slot(on: a)!
        a.allSchedulerModelEntrys[a.schedulerSetupModels[0]] = [slot: Entry(isValid: true)]
        grouped.releaseClearedBinding(on: a)
        precondition(grouped.nodeSlots == pending, "one uncleared Model must retain the slot")
        a.allSchedulerModelEntrys[a.schedulerSetupModels[0]] = [:]
        MeshProxyMessageCommand.shared.isBusy = true
        grouped.releaseClearedBinding(on: a)
        precondition(grouped.nodeSlots == pending, "in-flight slots remain reserved")
        MeshProxyMessageCommand.shared.isBusy = false
        let extra = Schedule(id: 16, name: "Replacement", enabled: true, nodeAddresses: [1])
        extra.nodeSlots = []
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules + [extra]))
        precondition(extra.slot(on: a) == slot && grouped.slot(on: a) == nil)
        precondition(grouped.nodeSlots?.first?.identity == b.timedSchedulerIdentity)

        let legacy = Schedule(id: 7, name: "Legacy", enabled: true, nodeAddresses: [1])
        manager.schedules = [legacy]
        precondition(TimedSchedulerBindings.reserveForDeletion(schedule: legacy))
        precondition(legacy.slot(on: a) == 7 && legacy.nodeSlots?.first?.state == .pendingApply)
        precondition(TimedSchedulerBindings.reserveForDeletion(schedule: legacy, node: a))
        precondition(legacy.slot(on: a) == 7 && legacy.nodeSlots?.first?.state == .pendingRemoval)
        legacy.nodeAddresses = []
        legacy.releaseClearedBinding(on: a)
        precondition(legacy.nodeSlots == [])
        print("PASS: Group exit persists per-node removal, rejects failed writes, and reuses only fully cleared idle slots")
    }

    static func migrationRequiresPersistedBaseline() throws {
        let manager = MeshNetworkManager.instance
        let previousNetwork = manager.meshNetwork
        manager.meshNetwork = MeshNetworkManager.Network()
        defer { manager.meshNetwork = previousNetwork }
        manager.realNodes = [Node(1)]
        let schedule = Schedule(id: 7, name: "Legacy migration", enabled: true, nodeAddresses: [1])
        manager.schedules = [schedule]
        let plan = try TimedSchedulerBindings.prepare(schedules: [schedule])
        SpaceConfigurationSafety.missingTimedBaseline = true
        defer { SpaceConfigurationSafety.missingTimedBaseline = false }
        do { try TimedSchedulerBindings.commit(plan); preconditionFailure("missing baseline must stop before any writes") }
        catch TimedSchedulerBindings.Failure.persistence {}
        precondition(schedule.nodeSlots == nil)
        precondition(Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: schedule.id).isEmpty)
        SpaceConfigurationSafety.missingTimedBaseline = false
        try TimedSchedulerBindings.commit(plan)
        precondition(schedule.slot(on: manager.realNodes[0]) == 7)
        print("PASS: migration requires a durable baseline before SQLite reservations; retry succeeds")
    }

    static func topologyKeepsPendingExits() throws {
        let manager = MeshNetworkManager.instance
        for observed in ["empty", "occupied", "unknown", "busy"] {
            let node = Node(1), group = Group(), unrelated = Group(), scene = Scene()
            unrelated.address.address = 0xC002
            node.group = group; group.nodes = [node]
            manager.realNodes = [node]
            let direct = (0..<15).map { Schedule(id: $0, name: "Direct", enabled: true, nodeAddresses: [1]) }
            let grouped = Schedule(id: 15, name: "Group", enabled: true)
            grouped.groups = [group]
            manager.schedules = direct + [grouped]
            try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules))
            precondition(TimedSchedulerBindings.reserveForDeletion(schedule: grouped, node: node))
            let pending = grouped.nodeSlots!
            node.groupState = .exitFailure
            if observed == "occupied" { node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [15: Entry(isValid: true)] }
            if observed == "unknown" { node.allSchedulerModelEntrys = [:] }
            MeshProxyMessageCommand.shared.isBusy = observed == "busy"
            try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepareTopology(group: unrelated))
            try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepareTopology(scene: scene))
            try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepareTopology(group: group, members: [node]))
            MeshProxyMessageCommand.shared.isBusy = false
            if observed == "empty" {
                precondition(grouped.nodeSlots == [], "unrelated topology must release an already cleared exit")
                let extra = Schedule(id: 16, name: "Replacement", enabled: true, nodeAddresses: [1])
                extra.nodeSlots = []
                try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules + [extra]))
                precondition(extra.slot(on: node) == 15)
                manager.schedules.append(extra)
                do {
                    _ = try TimedSchedulerBindings.prepareTopology(group: group, members: [node], addingMembers: [node])
                    preconditionFailure("explicit re-add must still respect all 16 occupied slots")
                } catch TimedSchedulerBindings.Failure.deviceCapacity {}
                manager.schedules.removeLast()
            } else {
                precondition(grouped.nodeSlots == pending, "pending exit cannot silently become assigned")
            }
            try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepareTopology(group: group, members: [node], addingMembers: [node]))
            precondition(grouped.nodeSlots?.first?.state == .pendingApply, "explicit reselection must restore membership")
        }
        print("PASS: unrelated Group/Scene edits preserve pending exits; empty slots reusable; explicit re-add restores assignment")
    }

    static func legacyCleanupRequiresOwnedSlot() throws {
        let manager = MeshNetworkManager.instance, node = Node(1)
        manager.realNodes = [node]
        for stillTargeted in [false, true] {
            let schedule = Schedule(id: 104, name: "Legacy cleanup", enabled: true,
                                    nodeAddresses: stillTargeted ? [1] : [])
            schedule.nodeSlots = []
            schedule.needDeleteNodeAddresses = [1]
            schedule.needDeleteNodes = [node]
            manager.schedules = [schedule]
            do {
                _ = try TimedSchedulerBindings.prepare(schedules: [schedule])
                preconditionFailure("a missing old cleanup slot must not be discarded or replaced with a new slot")
            } catch TimedSchedulerBindings.Failure.invalidMapping {}
            precondition(schedule.nodeSlots == [] && schedule.needDeleteNodeAddresses == [1])
        }
        print("PASS: legacy cleanup without an owned physical slot is preserved, including overlapping targets")
    }

    static func v3PersistenceAndProgress(db: Connection, path: String) throws {
        let manager = MeshNetworkManager.instance, node = Node(1)
        manager.realNodes = [node]
        let schedule = Schedule(id: 104, name: "V3 durable", enabled: true, nodeAddresses: [1])
        schedule.nodeSlots = []; manager.schedules = [schedule]
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [schedule]))
        let binding = schedule.nodeSlots!.first!
        precondition(binding.state == .pendingApply && binding.isV3)
        let rawNode: [String: Any] = ["uuid": node.uuid.uuidString, "unicastAddress": "0001", "deviceKey": node.deviceKey!.hex,
            "elements": [["index": 0, "models": [["modelId": "1206"], ["modelId": "1207"]]],
                         ["index": 1, "models": [["modelId": "1206"], ["modelId": "1207"], ["modelId": "130F"]]]]]
        let raw: [String: Any] = ["spaceData": ["timedSchemaVersion": 3], "nodes": [rawNode], "groups": [], "scenes": [],
            "schedules": try JSONSerialization.jsonObject(with: JSONEncoder().encode([schedule]))]
        let shared = TimedSchedulerPayloadPolicy.exportPayload(raw)!
        var incoming = shared, incomingRow = (shared["schedules"] as! [[String: Any]])[0]
        for field in ["needDeleteNodeAddresses", "needDeleteGroupAddresses", "needDeleteSceneNumbers"] {
            incomingRow[field] = ["ignored": true]
        }
        incoming["schedules"] = [incomingRow]
        var historicalNode = rawNode
        historicalNode["schedules"] = "unused"
        historicalNode["custProps"] = ["schedulerModelStates": NSNull()]
        incoming["nodes"] = [historicalNode]
        let imported = try JSONDecoder().decode([Schedule].self, from: JSONSerialization.data(
            withJSONObject: TimedSchedulerPayloadPolicy.decodingSchedules(incoming)!))[0]
        precondition(imported.needDeleteNodeAddresses.isEmpty && imported.needDeleteGroupAddresses.isEmpty
            && imported.needDeleteSceneNumbers.isEmpty)
        precondition(imported.save())
        SunSmartDataManager.shared.db = try Connection(path)
        let restored = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: 104).first!
        precondition(restored.nodeSlots == schedule.nodeSlots && restored.nodeSlots!.first!.identity == node.timedSchedulerIdentity)
        var readback = incoming
        readback["schedules"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([restored]))
        let reexported = TimedSchedulerPayloadPolicy.exportPayload(readback)!
        precondition(TimedSchedulerPayloadPolicy.canonical(reexported) == TimedSchedulerPayloadPolicy.canonical(shared))
        precondition((reexported["nodes"] as! [[String: Any]])[0]["schedules"] == nil)
        precondition(((reexported["schedules"] as! [[String: Any]])[0])["needDeleteNodeAddresses"] == nil)
        manager.schedules = [restored]
        let owner = node.schedulerSetupModels[0], other = node.schedulerSetupModels[1]
        node.allSchedulerModelEntrys = [owner: [binding.slot: restored.schedulerEntry]]
        restored.reconcileBinding(on: node)
        precondition(restored.nodeSlots!.first!.state == .pendingApply, "unknown nonOwner is not empty")
        node.allSchedulerModelEntrys[other] = [binding.slot: .init(isValid: true)]
        restored.reconcileBinding(on: node)
        precondition(restored.nodeSlots!.first!.state == .pendingApply, "residual nonOwner prevents success")
        let cleanupOnly = restored.getMessageHandles(node: node)
        precondition(cleanupOnly.count == 1 && cleanupOnly[0].model === other,
                     "retry skips the already matching Owner")
        node.allSchedulerModelEntrys[other] = [:]
        try db.execute("CREATE TRIGGER fail_v3_result BEFORE INSERT ON schedules WHEN NEW.scheduleIndex = 104 BEGIN SELECT RAISE(ABORT, 'fixture failure'); END")
        restored.reconcileBinding(on: node)
        precondition(restored.nodeSlots!.first!.state == .pendingApply, "failed result persistence keeps pending")
        try db.execute("DROP TRIGGER fail_v3_result")
        restored.reconcileBinding(on: node)
        precondition(restored.nodeSlots!.first!.state == .synced)
        restored.minute = 12
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [restored]))
        // Entry fixture omits minute; changing enabled exercises the same real
        // production owner comparison without pretending to test protocol bytes.
        restored.enabled = false
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [restored]))
        precondition(restored.nodeSlots!.first!.state == .pendingApply && restored.slot(on: node) == binding.slot)
        restored.nodeAddresses = []
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [restored]))
        precondition(restored.nodeSlots!.first!.state == .pendingRemoval)
        restored.reconcileBinding(on: node)
        precondition(restored.nodeSlots!.count == 1)
        node.allSchedulerModelEntrys[owner] = [:]
        restored.reconcileBinding(on: node)
        precondition(restored.nodeSlots!.isEmpty)
        let emptyColumns = try db.scalar("SELECT COUNT(*) FROM schedules WHERE scheduleIndex = 104 AND deviceDeleteAddresses IS NULL AND groupDeleteAddresses IS NULL AND sceneDeleteAddresses IS NULL") as? Int64
        precondition(emptyColumns == 1)
        precondition(restored.deleteData())
        SunSmartDataManager.shared.db = db
        manager.schedules = []; manager.realNodes = []
        print("PASS: v3 shared codec -> production Schedule -> SQLite reopen, full identity, unknown/partial/success/save failure and final slot release")
    }

    static func enabledFailurePersistsRollback(db: Connection) throws {
        let manager = MeshNetworkManager.instance
        for original in [false, true] {
            for successfulCount in [0, 1, 2] {
                let a = Node(1), b = Node(5)
                a.appliedEnabled = original; b.appliedEnabled = original
                manager.realNodes = [a, b]
                let schedule = Schedule(id: 0, name: "Toggle", enabled: original, nodeAddresses: [1, 5])
                manager.schedules = [schedule]
                precondition(schedule.save())
                ScheduleServer.successfulAddresses = Set([a, b].prefix(successfulCount).map(\.primaryUnicastAddress))
                var failed = false
                ScheduleServer.setEnabledState(schedule: schedule, enabled: !original,
                    success: { _ in }, failed: { _ in failed = true })
                let uuid = manager.meshNetwork!.uuid.uuidString, networkID = manager.currentNetworkKey.networkId.hex
                let loaded = Schedule.load(meshUUID: uuid, meshNetworkId: networkID, scheduleId: 0).first!
                let expected = successfulCount == 0 ? original : !original
                precondition(schedule.enabled == expected && loaded.enabled == expected)
                precondition(failed == (successfulCount < 2) && loaded.nodeSlots == schedule.nodeSlots)
                let slots = schedule.nodeSlots!
                ScheduleServer.successfulAddresses = [1, 5]
                ScheduleServer.setEnabledState(schedule: schedule, enabled: !original, success: nil, failed: nil)
                precondition(Schedule.load(meshUUID: uuid, meshNetworkId: networkID, scheduleId: 0).first!.enabled == !original)
                precondition(schedule.nodeSlots == slots, "retry must preserve slots and identities")
            }
        }
        let originalNetwork = manager.meshNetwork!
        let schedule = manager.schedules[0]
        let oldEnabled = schedule.enabled
        ScheduleServer.successfulAddresses = []
        ScheduleServer.beforeCompletion = { manager.meshNetwork = MeshNetworkManager.Network() }
        ScheduleServer.setEnabledState(schedule: schedule, enabled: !oldEnabled, success: nil, failed: nil)
        ScheduleServer.beforeCompletion = nil
        precondition(Schedule.load(meshUUID: originalNetwork.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: 0).first!.enabled == oldEnabled)
        precondition(Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex).isEmpty)
        manager.meshNetwork = originalNetwork
        print("PASS: enabled toggles roll back total failure, retain partial success and retry with stable slots")
    }

    static func groupExitWithNoDeviceCleanup() throws {
        let manager = MeshNetworkManager.instance
        let node = Node(1), group = Group()
        node.group = group; group.nodes = [node]
        manager.realNodes = [node]
        let schedule = Schedule(id: 0, name: "Never sent", enabled: true, groupAddresses: [group.address.address])
        schedule.groups = [group]
        manager.schedules = [schedule]
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [schedule]))
        node.exitSchedules = []
        precondition(group.getNodeExitMessageHandles(node: node)?.isEmpty == true)
        precondition(schedule.nodeSlots?.first?.state == .pendingRemoval,
                     "already-empty slots still need a durable binding transition on Group exit")
        schedule.releaseClearedBinding(on: node)
        precondition(schedule.nodeSlots == [])
        print("PASS: Group exit also releases reservations when no physical cleanup task is needed")
    }
    static func runtimeReservationsAndLateReplies(db: Connection) throws {
        let manager = MeshNetworkManager.instance
        let a = Node(1), b = Node(5)
        manager.realNodes = [a, b]
        manager.schedules = (0..<32).map { id in
            let schedule = Schedule(id: id, name: "Runtime \(id)", enabled: false, nodeAddresses: [id < 16 ? 1 : 5])
            schedule.nodeSlots = []
            return schedule
        }
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: manager.schedules))
        precondition(Set(manager.schedules.prefix(16).compactMap { $0.slot(on: a) }) == Set(0..<16))
        precondition(Set(manager.schedules.suffix(16).compactMap { $0.slot(on: b) }) == Set(0..<16))
        let schedule = manager.schedules[0]
        let handle = MeshMessageHandle()
        handle.schedulerTask = MeshSchedulerTask()
        handle.timedSchedulerContext = TimedSchedulerMessageContext(schedule: schedule, node: a)
        a.applyMessageHandle(handle)
        precondition(a.appliedMessages == 1)
        let binding = schedule.nodeSlots![0]
        schedule.nodeSlots = [.init(identity: binding.identity, slot: binding.slot, state: .assigned)]
        handle.schedulerTask?.cancel()
        a.applyMessageHandle(handle)
        precondition(a.appliedMessages == 1, "a cancelled task cannot mutate a reused slot")
        handle.schedulerTask = MeshSchedulerTask()
        handle.timedSchedulerContext = TimedSchedulerMessageContext(schedule: schedule, node: a)
        schedule.selectTargetType = .profile
        a.applyMessageHandle(handle)
        precondition(a.appliedMessages == 1, "late reply must not mutate a cloud-replaced Profile schedule")
        schedule.selectTargetType = .devices
        a.deviceKey = Data(repeating: 2, count: 16)
        a.applyMessageHandle(handle)
        precondition(a.appliedMessages == 1, "a replacement Device Key cannot receive an old reply")
        a.deviceKey = Data(repeating: 1, count: 16)
        let extra = Schedule(id: 500, name: "Failed transaction", enabled: false)
        extra.nodeSlots = []
        let plan = try TimedSchedulerBindings.prepare(schedules: manager.schedules + [extra])
        SpaceData.savesSucceed = false
        do { try TimedSchedulerBindings.commit(plan); preconditionFailure("Space save failure must roll back all reservations") }
        catch {}
        SpaceData.savesSucceed = true
        precondition(extra.nodeSlots == [])
        precondition(Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: 500).isEmpty)
        let c = Node(9)
        manager.realNodes.append(c)
        extra.nodeAddresses = [9]
        let topologyPlan = try TimedSchedulerBindings.prepare(schedules: manager.schedules + [extra])
        do {
            try TimedSchedulerBindings.commit(topologyPlan) { throw Failure.rollback }
        } catch {}
        precondition(extra.nodeSlots == [], "failed membership must roll back the reservation in memory")
        precondition(Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: 500).isEmpty,
            "failed membership must roll back the persisted reservation")
        print("PASS: production reservation transaction, per-device lookup, failed Space save and late-reply identity/task guards")
    }

    static func sceneRemovalIsNotAnActiveTarget() {
        let manager = MeshNetworkManager.instance
        let node = Node(1), group = Group(), scene = Scene(), data = SceneExecuteData()
        node.group = group; group.nodes = [node]; group.info.sceneExecuteDatas = [data]; scene.info.groups = [group]
        manager.realNodes = [node]
        let schedule = Schedule(id: 0, name: "Scene", enabled: true)
        schedule.scene = scene
        precondition(schedule.targets(node: node))
        data.state = .waitDelete
        precondition(!schedule.targets(node: node, contextGroup: group), "failed Scene removal must not re-enable the Timed target")
        print("PASS: production Timed target resolution keeps pending Scene groups on the cleanup path")
    }

    static func unknownDeviceCapacityIsDeferred() {
        let manager = MeshNetworkManager.instance
        let group = Group()
        manager.schedules = (0..<17).map { id in
            let item = Schedule(id: id, name: "Empty group \(id)", enabled: true)
            item.groupAddresses = [group.address.address]
            item.groups = [group]
            item.nodeSlots = []
            return item
        }
        precondition(TimedSchedulerBindings.canAddDevice(to: group),
                     "unknown composition must not blanket-reject non-Scheduler devices")
        let node = Node(12)
        precondition(!TimedSchedulerBindings.canAddDevice(to: group, node: node))
        node.schedulerSetupModels = []
        precondition(TimedSchedulerBindings.canAddDevice(to: group, node: node))
        print("PASS: actual composition gates the per-device Scheduler capacity check")
    }

}

// Scene ownership is exercised by the Scene suite; this fixture keeps its Scheduler assertions.
struct SceneStore {}
struct SceneDelete {}
struct SceneMessageContext {
    enum Action { case write, remove }
    var action: Action = .write
    var number: UInt16 = 0
    var removesGroupRelationship = false
    var revision: UUID? = nil
    func matches(node: Node) -> Bool { false }
    func apply(node: Node, successful: Bool, beforePersist: (() -> Bool)? = nil) -> Bool { false }
}
