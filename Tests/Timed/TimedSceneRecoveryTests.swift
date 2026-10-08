// Runs the production Scene node reader and task builder with the production
// reservation transaction. Scene/Scheduler observations and task execution are
// controlled boundaries; this does not simulate device acknowledgements.
enum SceneTaskType {
    case scene(sceneId: UInt16, executeData: SceneExecuteData?)
    case schedule(schedule: Schedule)
}
enum SceneTaskOperation {
    case configuration(node: Node, type: SceneTaskType)
    case delete(node: Node, type: SceneTaskType)
}
final class SyncDevicesSectionModel { var groups: [SyncDevicesGroupModel] = [] }
final class SyncDevicesGroupModel {
    let devices: [SyncDevicesModel]
    init(groupName: String?, groupAddress: Address, deviceModels: [SyncDevicesModel]) { devices = deviceModels }
}
final class SyncDevicesModel {
    var imageName = "", steps: [SyncDeviceStepModel] = []
    var operationType: SceneTaskOperation?, parentGroupModel: SyncDevicesGroupModel?
    init(name: String, address: Address) {}
}
final class SyncDeviceStepModel {
    enum State { case none }
    var parentDeviceModel: SyncDevicesModel?, showProgress = true
    var relevanceStepModels: [SyncDeviceStepModel] = []
    let tasks: [SyncDeviceStepTaskModel]
    init(type: String, state: State, tasks: [SyncDeviceStepTaskModel]) { self.tasks = tasks }
}
final class SyncDeviceStepTaskModel {
    let operationType: SceneTaskOperation
    var parentStepModel: SyncDeviceStepModel?
    init(name: String, operationType: SceneTaskOperation) { self.operationType = operationType }
}
struct SyncSceneScheduleTaskBuilder {
    // ACTUAL_SCENE_TASKS
}
extension Node {
    enum SceneDisplayType { case scenes(Scene?) }
    func getNodeSyncSceneDatas(scene: Scene?) -> [SceneExecuteData] { [] }
    func getNodeNeedDeleteSceneDatas(scene: Scene?) -> [Scene] { [] }
    func sceneDisplayData(_ type: SceneDisplayType) -> [NodeSyncData] {
        var syncDatas: [NodeSyncData] = []
        switch type {
        // ACTUAL_SCENE_DISPLAY
        }
        return syncDatas
    }
}
extension Run {
    static func sceneRecoveryRebuildsTimedTasks() throws {
        let manager = MeshNetworkManager.instance
        let node = Node(1), group = Group(), scene = Scene()
        let desired = SceneExecuteData(), observed = SceneExecuteData()
        node.group = group; group.nodes = [node]
        node.sceneExecuteDatas = [observed]
        group.info.sceneExecuteDatas = [desired]; scene.info.groups = [group]
        let schedule = Schedule(id: 0, name: "Scene schedule", enabled: true)
        schedule.scene = scene; scene.info.bindSchedules = [schedule]
        manager.realNodes = [node]; manager.schedules = [schedule]
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [schedule]))
        desired.state = .waitDelete
        precondition(TimedSchedulerBindings.reserveForDeletion(schedule: schedule, node: node))
        schedule.releaseClearedBinding(on: node)
        precondition(schedule.nodeSlots == [])
        let removed = group.getNeedSyncDataNodes(scene: scene)
        precondition(removed.syncNodes.isEmpty && removed.deleteNodes == [node])
        // SceneDelete failed. Reselect with identical parameters after the
        // Scheduler clear succeeded, then retry the same save without edits.
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepareTopology(scene: scene, sceneGroups: [group])) {
            desired.state = .normal
        }
        for _ in 0..<2 {
            precondition(group.getNeedSyncDataNodes(scene: scene).syncNodes == [node])
            guard case .syncSchedules(let displayed) = node.sceneDisplayData(.scenes(scene)).first else {
                preconditionFailure("Scene display must expose its schedule-only pending state")
            }
            precondition(displayed.count == 1 && displayed[0] === schedule)
            precondition(node.sceneDisplayData(.scenes(nil)).count == 1, "all-Scenes reader must include pending Timed tasks")
            let configuration = SyncDevicesSectionModel(), removal = SyncDevicesSectionModel()
            SyncSceneScheduleTaskBuilder().appendScene(to: configuration, removal: removal, scene: scene)
            precondition(configuration.groups.count == 1 && removal.groups.isEmpty)
            let device = configuration.groups[0].devices[0]
            precondition(device.steps.count == 2)
            let sceneStep = device.steps[0], timedStep = device.steps[1]
            precondition(timedStep.relevanceStepModels.first === sceneStep)
            guard case .configuration(let target, .schedule(let taskSchedule)) = timedStep.tasks[0].operationType else {
                preconditionFailure("restored Scene must generate its missing Scheduler task")
            }
            precondition(target === node && taskSchedule === schedule && schedule.slot(on: node) != nil)
        }
        node.appliedEnabled = true
        precondition(group.getNeedSyncDataNodes(scene: scene).syncNodes.isEmpty)
        precondition(node.sceneDisplayData(.scenes(scene)).isEmpty)
        node.appliedEnabled = false
        node.groupState = .exitFailure
        precondition(group.getNeedSyncDataNodes(scene: scene).syncNodes.isEmpty)
        node.groupState = .inGroup
        node.schedulerSetupModels = []
        precondition(group.getNeedSyncDataNodes(scene: scene).syncNodes.isEmpty)
        observed.value = 2
        precondition(group.getNeedSyncDataNodes(scene: scene).syncNodes == [node], "Scene-only differences still sync")
        let sceneOnly = SyncDevicesSectionModel()
        SyncSceneScheduleTaskBuilder().appendScene(to: sceneOnly, removal: SyncDevicesSectionModel(), scene: scene)
        precondition(sceneOnly.groups[0].devices[0].steps.isEmpty, "unsupported Scheduler must not create Timed tasks")
        guard case .configuration(_, .scene) = sceneOnly.groups[0].devices[0].operationType else {
            preconditionFailure("Scene-only device still needs its Scene operation")
        }
        print("PASS: restored identical Scene regenerates missing Timed tasks, retries, and converges; exiting/Scene-only nodes stay scoped")
    }
}
