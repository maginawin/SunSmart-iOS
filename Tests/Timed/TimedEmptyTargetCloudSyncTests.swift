import Foundation

// UI callbacks remain queued so assertions can run before the 1.5s dismissal.
final class DispatchQueue {
    static let main = DispatchQueue()
    var pending: [() -> Void] = []
    func asyncAfter(wallDeadline: DispatchWallTime, execute: @escaping () -> Void) { pending.append(execute) }
    func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { pending.append(execute) }
    func drain() { let work = pending; pending = []; work.forEach { $0() } }
}
extension String { var localizedString: String { self } }
enum XWHUDManager {
    static var successes = 0, failures = 0
    static func showSuccessTipHUD(_ text: String) { successes += 1 }
    static func showErrorTipHUD(_ text: String) { failures += 1 }
    static func hide() {}
}
let schedulesRefreshNotificationName = "refresh"
let spaceDataChangedNotificaitonName = "changed"
final class Button { var isEnabled = true }
final class Node {
    enum DeviceType { case light }
    let deviceType = DeviceType.light
    func clearSyncStateCache() {}
}
final class Group: NSObject {
    final class Info { var bindSchedules: [Schedule] = [] }
    let info = Info()
    var nodes: [Node] = []
    var isVirtual = false
}
final class Scene {
    final class Info { var groups: [Group] = [] }
    let info = Info()
}
final class Schedule {
    static var rows: [Int: Schedule] = [:]
    let id: Int
    var groups: [Group] = [], needDeleteGroups: [Group] = [], needDeleteScenes: [Scene] = []
    var scene: Scene?
    var deleteSucceeds = true, requiresDeviceSync = false
    var existNodes: [Node] { groups.flatMap(\.nodes) + (scene?.info.groups.flatMap(\.nodes) ?? []) }
    init(_ id: Int) { self.id = id }
    func deleteData() -> Bool {
        guard deleteSucceeds else { return false }
        Self.rows[id] = nil
        return true
    }
    static func load(meshUUID: String, meshNetworkId: String) -> [Schedule] { Array(rows.values) }
    struct SyncData {
        let needsSync: Bool
        func isEmpty() -> Bool { !needsSync }
    }
    func getNeedSyncDatas() -> SyncData { .init(needsSync: requiresDeviceSync) }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var schedules: [Schedule] = [], groups: [Group] = [], scenes: [Scene] = []
}
enum ProximityLightingTopologyContext {
    static func network(for space: SpaceData) -> MeshNetworkManager? { .instance }
    static func realNodes(in network: MeshNetworkManager) -> [Node] { network.groups.flatMap(\.nodes) }
}
enum DeviceSwitchData {
    static func load(meshUUID: String, meshNetworkId: String) -> [Int] { [] }
}
enum Permission { case owner, editor, visitor }
final class SpaceData {
    let id = "space", siteId = "site", meshUUID = "mesh", meshNetworkId = "network"
    var permission = Permission.owner, timedSchemaVersion = 2
    var lastUpdate: Int64 = 100, lastUploadCloudTimestamp: Int64? = 100
    var savedUpdate: Int64 = 100
    var deviceCount = 0, luminairesCount = 0, groupCount = 0, sceneCount = 0, scheheduleCount = 0, switchesCount = 0
    var needUploadCloud: Bool { lastUpdate > (lastUploadCloudTimestamp ?? 0) && permission != .visitor }
    @discardableResult func save() -> Bool { savedUpdate = lastUpdate; return true }
    static func load(siteId: String) -> [SpaceData] { [] }
    func appliesCloud(remoteCount: Int, timestamp: Int64) -> Bool {
        let resumingImport = false, initialize = false
        let lastUpdate = timestamp
        let sameTimestampSummaryDiffers = lastUpdate == self.lastUpdate && remoteCount != scheheduleCount
        let localNeedsUpload = needUploadCloud
        // PRODUCTION_IMPORT_DECISION
        return shouldApplyServerData
    }
}
final class SiteData {
    static let current = SiteData()
    let id = "site"
    var spaces: [SpaceData] = [], uploadCloud = true
    var lastUpdate: Int64 = 100, lastUploadCloudTimestamp: Int64? = 100
    static func load(siteId: String) -> SiteData? { current }
    @discardableResult func save() -> Bool { true }
}
enum SpaceConfigurationSafety {
    static func requiresAuthorityImport(_ space: SpaceData) -> Bool { false }
    static func isBlocked(_ space: SpaceData) -> Bool { false }
}
enum SyncLevel { case slow, promptly }
enum SyncOperation { case syncSpace(space: SpaceData), syncSite(site: SiteData, syncSpaces: [SpaceData] = []) }
final class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    var submissions: [(timestamp: Int64, count: Int)] = []
    func addSynchronizationHandle(operation: SyncOperation, level: SyncLevel) {
        if case .syncSpace(let space) = operation { submissions.append((space.lastUpdate, space.scheheduleCount)) }
    }
}
// PRODUCTION_SPACE_CHANGE
final class Editor {
    let space: SpaceData
    var schedule: Schedule?, addFineshed = false
    let saveBtn = Button()
    var devicePushes = 0, closed = false
    init(_ space: SpaceData) { self.space = space }
    func back() { closed = true }
    func pushToSyncDevices(schedule: Schedule) { devicePushes += 1 }
    // Entry boundary: reservation transaction already succeeded; execute the
    // actual remaining controller body, including memory/notification ordering.
    func added(_ schedule: Schedule, groups: [Group], scene: Scene?, needSync: Bool) {
        // PRODUCTION_ADD_SUCCESS
    func edited(_ schedule: Schedule, candidates: [Schedule]) {
        // PRODUCTION_EDIT_SUCCESS
    // PRODUCTION_EMPTY_DELETE
}

@main struct Run {
    static func main() {
        let manager = MeshNetworkManager.instance
        for kind in ["group", "empty-scene", "scene-empty-group"] {
            Schedule.rows = [:]; manager.schedules = []; manager.groups = [Group()]
            CloudSynchronizationManager.shared.submissions = []
            let space = SpaceData()
            let active = Editor(space)
            let observer = NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: nil) { notification in
                space.commitLocalChangeForCloudSync(changeType: notification.object as! SpaceChangeDataType)
            }
            var firstTimestamp: Int64 = 0
            for id in 0..<17 {
                let schedule = Schedule(id)
                if kind == "group" { schedule.groups = manager.groups }
                else {
                    schedule.scene = Scene()
                    if kind == "scene-empty-group" { schedule.scene!.info.groups = manager.groups }
                }
                Schedule.rows[id] = schedule
                active.added(schedule, groups: schedule.groups, scene: schedule.scene, needSync: false)
                precondition(space.needUploadCloud && space.savedUpdate == space.lastUpdate)
                precondition(space.scheheduleCount == id + 1 && !active.closed)
                if id == 0 { firstTimestamp = space.lastUpdate }
            }
            precondition(CloudSynchronizationManager.shared.submissions.count == 17)
            precondition(CloudSynchronizationManager.shared.submissions.last!.count == 17)
            // Emulate confirmation of the first snapshot after later edits.
            // Actual receipt/retry processing is exercised by recovery tests.
            space.lastUploadCloudTimestamp = firstTimestamp
            precondition(space.needUploadCloud && space.lastUpdate > firstTimestamp)
            precondition(!space.appliesCloud(remoteCount: 1, timestamp: firstTimestamp))
            precondition(!space.appliesCloud(remoteCount: 1, timestamp: space.lastUpdate))
            DispatchQueue.main.drain()
            precondition(CloudSynchronizationManager.shared.submissions.count == 17)

            let doomed = manager.schedules[0], survivor = manager.schedules[1]
            manager.groups[0].info.bindSchedules = [doomed, survivor]
            active.schedule = doomed
            doomed.deleteSucceeds = false
            let generation = space.lastUpdate, successCount = XWHUDManager.successes
            active.closed = false
            active.deleteBtnAction()
            precondition(space.lastUpdate == generation && Schedule.rows.count == 17)
            precondition(manager.schedules.count == 17 && manager.groups[0].info.bindSchedules.count == 2)
            precondition(XWHUDManager.successes == successCount && !active.closed && DispatchQueue.main.pending.isEmpty)
            doomed.deleteSucceeds = true
            active.deleteBtnAction()
            precondition(space.lastUpdate > generation && space.scheheduleCount == 16)
            precondition(Schedule.rows.count == 16 && manager.schedules.count == 16)
            precondition(manager.groups[0].info.bindSchedules.map(\.id) == [survivor.id])
            precondition(!active.closed)
            DispatchQueue.main.drain()

            // Editing without BLE must mark the change before dismissal too.
            active.closed = false
            let beforeEdit = space.lastUpdate
            active.edited(survivor, candidates: manager.schedules)
            precondition(space.lastUpdate > beforeEdit && !active.closed)
            let enqueued = CloudSynchronizationManager.shared.submissions.count
            DispatchQueue.main.drain()
            precondition(CloudSynchronizationManager.shared.submissions.count == enqueued)
            NotificationCenter.default.removeObserver(observer)
            print("PASS: \(kind) 17 adds mark cloud immediately; old acknowledgement stays dirty; delete failure/success and edit-before-dismissal")
        }
        // Device operations retain the existing SyncExecutionSession handoff.
        let space = SpaceData(), editor = Editor(space), item = Schedule(99)
        let observer = NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: nil) { _ in
            preconditionFailure("device sync must own its configuration completion")
        }
        editor.added(item, groups: [], scene: nil, needSync: true)
        item.requiresDeviceSync = true
        editor.edited(item, candidates: [item])
        precondition(editor.devicePushes == 2 && DispatchQueue.main.pending.isEmpty)
        NotificationCenter.default.removeObserver(observer)
        print("PASS: nonempty/device-sync add and edit retain their existing completion owner")
    }
}
