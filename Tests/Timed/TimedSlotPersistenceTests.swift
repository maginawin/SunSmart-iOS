import Foundation
import CryptoKit
import SQLite
import struct SQLite.Expression

typealias Address = UInt16
typealias SceneNumber = UInt16
extension UInt16 {
    var hex: String { String(format: "%04X", self) }
    var isUnicast: Bool { (1..<0x8000).contains(self) }
    var isGroup: Bool { (0xC000..<0xFF00).contains(self) }
    var isValidSceneNumber: Bool { self > 0 }
}
extension String { var localizedString: String { self } }
let jsonEncoder = JSONEncoder(), jsonDecoder = JSONDecoder()
enum WeekDay: UInt8 { case Monday = 1, Tuesday = 2, Wednesday = 4, Thursday = 8, Friday = 16, Saturday = 32, Sunday = 64 }
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Connection?
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    struct Network { let uuid = UUID() }
    struct Key { let networkId: Address = 1 }
    var meshNetwork: Network? = Network()
    let currentNetworkKey = Key()
    var schedules: [Schedule] = []
    var realNodes: [Node] = []
}
// Object/network ownership is the isolated boundary; every table operation below
// is the production Database.swift extension, including migrations and failures.
final class Schedule {
    enum TargetType: Int { case groups, devices, scene, profile }
    enum Action: UInt8 { case off = 0, on = 1, scene = 2, noAction = 15 }
    typealias ScheduleProfile = Int
    var id: Int, name: String, enabled: Bool
    var nodeAddresses: [Address], groupAddresses: [Address], sceneNumber: SceneNumber?
    var profiles: [ScheduleProfile], selectTargetType: TargetType, action: Action
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

    init(id: Int, name: String, enabled: Bool, nodeAddresses: [Address] = [], groupAddresses: [Address] = [],
         sceneNumber: SceneNumber? = nil, profiles: [ScheduleProfile] = [], selectTargetType: TargetType = .devices,
         action: Action = .on, fadeTime: Int = 0, weekDays: [WeekDay] = [.Monday], hour: Int = 8, minute: Int = 0) {
        self.id = id; self.name = name; self.enabled = enabled; self.nodeAddresses = nodeAddresses
        self.groupAddresses = groupAddresses; self.sceneNumber = sceneNumber; self.profiles = profiles
        self.selectTargetType = selectTargetType; self.action = action; self.fadeTime = fadeTime
        self.weekDays = weekDays; self.hour = hour; self.minute = minute
    }
}
final class Model: NSObject {}
struct Entry { var isValid = true }
final class Node: NSObject {
    enum GroupState { case inGroup, exitFailure }
    var groupState = GroupState.inGroup
    var deviceKey: Data? = Data(repeating: 1, count: 16)
    let uuid = UUID()
    let primaryUnicastAddress: Address
    let name: String? = nil
    var group: Group?
    var network = MeshNetworkManager.instance.meshNetwork
    var subNetworkId: String? = MeshNetworkManager.instance.currentNetworkKey.networkId.hex
    var schedulerSetupModels = [Model(), Model()]
    var allSchedulerModelEntrys: [Model: [Int: Entry]] = [:]
    var schedulerActions: [Int: Entry] = [:]
    var sceneSetupModel: Model? = Model()
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
        schedulerSetupModels.forEach { allSchedulerModelEntrys[$0] = [:] }
    }
    func updateData(message: Int, isSuccess: Bool, model: Model?) { if isSuccess { appliedMessages += 1 } }
}
extension Data { var hex: String { map { String(format: "%02X", $0) }.joined() } }
enum SchedulerModelSnapshot {
    static func keyFingerprint(_ value: [String: Any]) throws -> String {
        SHA256.hash(data: Data((value["deviceKey"] as! String).uppercased().utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
final class Group: NSObject {
    struct GroupAddress: Equatable { var address: Address = 0xC001 }
    var address = GroupAddress(), name: String? = nil
    var nodes: [Node] = []
    final class Info { var sceneExecuteDatas: [SceneExecuteData] = [] }
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
final class SceneExecuteData {
    enum State { case normal, waitDelete }
    let sceneNumber: UInt16 = 6
    var state = State.normal
    var value = 1
    func isSynced(with other: SceneExecuteData, for node: Node) -> Bool { value == other.value }
}
enum NodeSyncReadContext {
    static var current: NodeSyncReadContext? { nil }
    func contains(_ node: Node, in group: Group) -> Bool { group.nodes.contains(node) }
}
final class Scene: NSObject {
    let number: UInt16 = 6
    let name = "Scene"
    final class Info { var groups: [Group] = []; var bindSchedules: [Schedule] = [] }
    let info = Info()
}
final class MeshMessageHandle: NSObject { var message = 0; var model: Model?; var continuous = true }
final class MeshProxyMessageCommand { static let shared = MeshProxyMessageCommand(); var isBusy = false }
enum XWHUDManager { static func showTipHUD(_ message: String, isLineFeed: Bool) {} }
final class SpaceData {
    static var savesSucceed = true
    var timedSchemaVersion = 1
    var meshUUID = MeshNetworkManager.instance.meshNetwork!.uuid.uuidString
    static func load(subNetworkId: String) -> SpaceData? { SpaceData() }
    func save() -> Bool { Self.savesSucceed }
}
enum SpaceConfigurationSafety {
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
        SunSmartDataManager.shared.db = nil
        precondition(!item.save(meshUUID: "mesh", meshNetworkId: "one"), "missing database cannot confirm a saved reservation")
        print("PASS: production Schedule SQLite migration, 17th logical record, restart, pending cleanup, corruption and rollback")
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
        precondition(pending.first { $0.identity == b.timedSchedulerIdentity }?.state == .assigned)
        precondition(zip(assigned, pending).allSatisfy { $0.slot == $1.slot && $0.generation == $1.generation })
        let reloaded = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: grouped.id).first!
        precondition(reloaded.nodeSlots == pending)
        let slot = grouped.slot(on: a)!
        a.allSchedulerModelEntrys[a.schedulerSetupModels[0]] = [slot: Entry()]
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
        precondition(legacy.slot(on: a) == 7 && legacy.nodeSlots?.first?.state == .assigned)
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
            if observed == "occupied" { node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [15: Entry()] }
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
            precondition(grouped.nodeSlots?.first?.state == .assigned, "explicit reselection must restore membership")
        }
        print("PASS: unrelated Group/Scene edits preserve pending exits; empty slots reusable; explicit re-add restores assignment")
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
                precondition(schedule.nodeSlots == slots, "retry must preserve slots and generations")
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
        print("PASS: legacy enabled toggles roll back SQLite on total failure, retain partial success and retry with stable slots")
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
        handle.timedSchedulerContext = TimedSchedulerMessageContext(schedule: schedule, node: a)
        a.applyMessageHandle(handle)
        precondition(a.appliedMessages == 1)
        let binding = schedule.nodeSlots![0]
        schedule.nodeSlots = [.init(identity: binding.identity, slot: binding.slot, state: .assigned)]
        a.applyMessageHandle(handle)
        precondition(a.appliedMessages == 1, "a late reply cannot mutate a reused slot generation")
        handle.timedSchedulerContext = TimedSchedulerMessageContext(schedule: schedule, node: a)
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
        print("PASS: production reservation transaction, per-device lookup, failed Space save and late-reply identity/generation guards")
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
