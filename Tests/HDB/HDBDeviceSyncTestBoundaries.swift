import Foundation
// Radio task execution is covered by the App build and strict ACK policy tests.
// These doubles retain operation payloads to exercise the actual planner and Store.
final class HDBDeviceSyncTask {
    enum Operation {
        case preparation(HDBDevicePreparationPlan, HDBPreparationStepID)
        case initialization(HDBDevicePreparationPlan, HDBLightingConfiguration)
        case zone(HDBZoneOperation)
        case configuration(HDBLightingCommand, HDBLightingConfiguration)
        case cleanup(UInt16, HDBModelTarget, Bool)
    }
    let context: HDBDeviceSyncContext, operation: Operation
    var title: String { "task" }
    init(context: HDBDeviceSyncContext, operation: Operation) { self.context = context; self.operation = operation }
}
final class SyncDeviceStepTaskModel {
    enum Operation { case configuration(node: Node, type: Action) }
    enum Action { case hdb(HDBDeviceSyncTask) }
    weak var parentStepModel: SyncDeviceStepModel?
    let operationType: Operation
    init(name: String, operationType: Operation) { self.operationType = operationType }
}
final class SyncDeviceStepModel {
    enum State { case none }
    var relevanceStepModels: [SyncDeviceStepModel] = []
    let tasks: [SyncDeviceStepTaskModel]
    init(type: String, state: State, tasks: [SyncDeviceStepTaskModel]) { self.tasks = tasks }
}
enum NodeSyncData { case test }
enum SyncDevicesViewController { enum SyncType { case devices([Node]), spaceTriggerZones(datas: [(node: Node, syncData: NodeSyncData)]) } }

func seedPrepared(space: SpaceData, node: Node, zonesSynced: Bool = true) throws {
    let context = try HDBDeviceSyncContext.resolve(space: space, node: node)!
    try HDBDeviceSyncService.prepareIntent(context: context)
    let plan = try context.plan(in: HDBConfigurationStore.load(space: space))
    node.preConfiguration.hdbInitializationSignature = try HDBDeviceSyncService.signature(context: context, plan: plan)
    if let address = plan.publicationAddress {
        for target in plan.publicationTargets {
            try HDBLightingMessages.model(target, node: node, key: context.key!).publish = TestPublish(
                publicationAddress: MeshAddress(address), index: plan.appKeyIndex,
                retransmit: HDBDeviceSyncService.sensorPublicationRetransmit)
        }
    }
    try HDBConfigurationStore.update(space: space) { config in
        let index = config.devices.firstIndex { $0.nodeUuid == node.uuid }!
        config.devices[index].lightingZonesStatus = zonesSynced ? .synced : .pending
        config.devices[index].lightingConfiguration?.mark(fields: ["lightingControl", "dimIntensity", "brightIntensity", "rampUpTime", "rampDownTime", "holdTime"], status: .synced)
    }
}

extension Node {
    func clearSyncStateCache() {}
    func getStandardNeedSync() -> Bool { !isKeybindComplete }
    func getNeedSync() -> Bool { getStandardNeedSync() || HDBDeviceSyncService.needsSync(node: self) }
}
enum TestSyncState { case inSync, syncSuccess, syncFailure }
final class SyncExecutionSession {
    var publishesCloudChange = true
    final class Environment { var configurationIsCurrent: () -> Bool = { true } }
    static var started: [SyncExecutionSession] = []
    let environment = Environment()
    var sections: [SyncDeviceStepModel] = []
    var onSettled: ((TestSyncState) -> Void)?, onPlanInvalidated: (() -> Void)?, onStopped: (() -> Void)?
    init(type: SyncDevicesViewController.SyncType, reSync: Bool) {}
    func start() { Self.started.append(self) }
    func close() { onStopped?() }
}
enum SpaceSyncTaskScope { static func capture() -> () -> Bool { { true } } }
struct SyncTaskPlanBuilder {
    struct Result { var sections: [SyncDeviceStepModel] = [] }
    private let type: SyncDevicesViewController.SyncType
    init(type: SyncDevicesViewController.SyncType, initialState: TestSyncState,
         profileSensorProtectionContext: Int?, groupProfileSyncContext: Int?,
         supplementaryProximityLightingSyncDatas: [Int], imageExists: (String) -> Bool) { self.type = type }
    func build() -> Result {
        guard case .devices(let nodes) = type else { return Result() }
        return Result(sections: nodes.flatMap { node in
            let context = try! HDBDeviceSyncContext.resolve(node: node)!
            return try! HDBDeviceSyncService.makeSteps(context: context)
        })
    }
}
