import Foundation

typealias Address = UInt16
protocol MeshMessage {}
struct SchedulerRegistryEntry {
    let enabled: Bool
    static func marshal(index: UInt8, entry: Self) -> Data { Data([index, entry.enabled ? 1 : 0]) }
}
struct SchedulerActionSet: MeshMessage { let index: UInt8; let entry: SchedulerRegistryEntry }
final class Element { let unicastAddress: Address; init(_ address: Address) { unicastAddress = address } }
final class Model { let parentElement: Element?; init(_ address: Address) { parentElement = Element(address) } }
struct GroupAddress { let address: Address = 0xC001 }
final class Group { let address = GroupAddress() }
final class Scene { let number: UInt16 = 1 }
final class Network {
    let uuid = UUID()
    func node(withAddress address: Address) -> Node? { MeshNetworkManager.instance.realNodes.first { $0.primaryUnicastAddress == address } }
}
struct NetworkKey { let networkId = Data([1]); }
extension Data { var hex: String { map { String(format: "%02X", $0) }.joined() } }
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network()
    var currentNetworkKey = NetworkKey()
    var schedules: [Schedule] = []
    var realNodes: [Node] = []
}
final class Node {
    let primaryUnicastAddress: Address
    var network: Network? { MeshNetworkManager.instance.meshNetwork }
    var subNetworkId: String? { "01" }
    var timedSchedulerIdentity: TimedSchedulerNodeIdentity?
    let normal: Model, extra: Model, collection: Model
    var collectionSchedulerSetupModel: Model? { collection }
    var timeModel: Model? { nil }
    var observedTimedSlots: Set<Int>? = []
    var appliedEnabled = false
    @discardableResult func savePropertys() -> Bool { true }
    init(_ address: Address) {
        primaryUnicastAddress = address
        normal = Model(address); extra = Model(address + 1); collection = Model(address + 2)
        timedSchedulerIdentity = .init(nodeUUID: UUID().uuidString, unicastAddress: String(format: "%04X", address), deviceKeyFingerprint: String(repeating: "a", count: 64))
    }
    func applyMessageHandle(_ handle: MeshMessageHandle) {
        guard handle.schedulerTask?.isCancelled != true else { return }
        if let message = handle.message as? SchedulerActionSet { appliedEnabled = message.entry.enabled }
    }
}
final class MeshMessageHandle {
    let message: MeshMessage
    var model: Model?, address: Address?
    var schedulerTask: MeshSchedulerTask?, schedulerAdmission: (() -> Void)?
    var transmissionIsValid: (() -> Bool)?, responseIsValid: ((MeshMessage) -> Bool)?
    var continuous = true, successful = false
    var isSuccessful: Bool { successful && schedulerTask?.isCancelled != true }
    init(message: MeshMessage, model: Model) { self.message = message; self.model = model }
}
final class Schedule: Encodable {
    enum Target: Int, Encodable { case devices, profile }
    let id: Int
    enum Action: Int, Encodable { case on, noAction }
    var action = Action.on
    var deleted = false
    var groupAddresses: [Address] = [], needDeleteGroupAddresses: [Address] = [], needDeleteSceneNumbers: [UInt16] = []
    var sceneNumber: UInt16?
    var scene: Scene? { nil }
    var groups: [Group] { [] }
    var nodes: [Node] { MeshNetworkManager.instance.realNodes.filter { nodeAddresses.contains($0.primaryUnicastAddress) } }
    var enabled = false, name = "Test"
    var nodeSlots: [TimedSchedulerNodeSlot]?
    var nodeAddresses: [Address]
    var needDeleteNodeAddresses: [Address] = []
    var selectTargetType = Target.devices
    var saves = 0, saveSucceeds = true
    func reconcileBinding(on node: Node) {
        guard let index = nodeSlots?.firstIndex(where: { $0.identity == node.timedSchedulerIdentity }),
              nodeSlots![index].state != .pendingRemoval else { return }
        nodeSlots![index].state = needsSync(on: node) ? .pendingApply : .synced
        save()
    }
    // PRODUCTION_RELEASE
    enum CodingKeys: CodingKey { case id, enabled, name, nodeSlots, nodeAddresses, needDeleteNodeAddresses, selectTargetType, action }
    init(id: Int = 1, nodes: [Node]) {
        self.id = id; nodeAddresses = nodes.map(\.primaryUnicastAddress)
        nodeSlots = nodes.map { .init(identity: $0.timedSchedulerIdentity!, slot: 0, state: .assigned) }
    }
    var existNodes: [Node] { MeshNetworkManager.instance.realNodes.filter { node in
        (nodeAddresses + needDeleteNodeAddresses).contains(node.primaryUnicastAddress)
            || nodeSlots?.contains { $0.identity == node.timedSchedulerIdentity } == true
    } }
    var schedulerEntry: SchedulerRegistryEntry { .init(enabled: enabled && action != .noAction) }
    func copy() -> Schedule {
        let result = Schedule(id: id, nodes: existNodes)
        result.action = action; result.enabled = enabled; result.nodeSlots = nodeSlots
        result.nodeAddresses = nodeAddresses; result.needDeleteNodeAddresses = needDeleteNodeAddresses
        return result
    }
    func deleteData() -> Bool { deleted = true; return true }
    func targets(node: Node) -> Bool { nodeAddresses.contains(node.primaryUnicastAddress) }
    func slot(on node: Node) -> Int? { nodeSlots?.first { $0.identity == node.timedSchedulerIdentity }?.slot }
    func needsSync(on node: Node, contextGroup: Group? = nil) -> Bool { node.appliedEnabled != enabled }
    func deletionIsSynchronized(on node: Node) -> Bool { !node.appliedEnabled }
    @discardableResult func save(meshUUID: String? = nil, meshNetworkId: String? = nil) -> Bool {
        saves += 1
        guard saveSucceeds else { return false }
        TimedSchedulerTaskCoordinator.configurationSaved(self, meshUUID: meshUUID ?? MeshNetworkManager.instance.meshNetwork!.uuid.uuidString, networkID: meshNetworkId ?? "01")
        return true
    }
    func getNeedSyncDatas() -> (deleteNodes: [Node], deleteGroups: [(Group, [Node])], syncNodes: [Node], syncGroups: [(Group, [Node])]) {
        action == .noAction ? (existNodes, [], [], []) : ([], [], existNodes.filter { needsSync(on: $0) }, [])
    }
    func getMessageHandles(node: Node, contextGroup: Group? = nil, delete: Bool = false) -> [MeshMessageHandle] {
        let handle = MeshMessageHandle(message: SchedulerActionSet(index: UInt8(slot(on: node)!), entry: schedulerEntry), model: node.normal)
        TimedSchedulerTaskCoordinator.attach([handle], node: node, schedule: self)
        return [handle]
    }
}
enum TimedSchedulerBindings {
    static func prepare(schedules: [Schedule]) -> [Schedule] { schedules }
    static func commit(_ schedules: [Schedule]) throws { schedules.forEach { _ = $0.save() } }
    static func reserveForDeletion(schedule: Schedule, node: Node? = nil) -> Bool { true }
    static func reserveForSending(schedule: Schedule, node: Node, contextGroup: Group?) -> Bool { true }
}
enum SiteTimeSetMessageFactory {
    static func makeHandle(node: Node, model: Model) -> MeshMessageHandle? { nil }
}
final class MeshProxyMessageCommand {
    static let shared = MeshProxyMessageCommand()
    struct Batch {
        let handles: [MeshMessageHandle]
        let success: ((MeshMessageHandle, Int) -> Void)?
        let finish: (([MeshMessageHandle]) -> Void)?
    }
    var batches: [Batch] = []
    var isBusy = false
    func cancelSchedulerTasks(_ tasks: [MeshSchedulerTask]) { tasks.forEach { $0.cancel() } }
    func addMessage(messageHandles: [MeshMessageHandle], progressBack: ((Int, Int) -> Void)? = nil,
                    successfulBack: ((MeshMessageHandle, Int) -> Void)? = nil,
                    failedBack: ((MeshMessageHandle) -> Void)? = nil,
                    finishedBack: (([MeshMessageHandle]) -> Void)?) {
        messageHandles.forEach { $0.schedulerAdmission?() }
        batches.append(Batch(handles: messageHandles, success: successfulBack, finish: finishedBack))
    }
    func complete(_ index: Int, success: Bool) {
        let batch = batches[index]
        batch.handles.forEach { handle in
            handle.successful = success
            if success { batch.success?(handle, 0) }
        }
        batch.finish?(batch.handles)
    }
}
struct ScheduleServer {
    private struct ScheduleDeviceBatch { let node: Node; let contextGroup: Group?; let delete: Bool }
    typealias ScheduleOperateSuccessCallback = (Schedule) -> Void
    typealias ScheduleOperateFailedCallback = (Schedule) -> Void
    static func nodesRequiringAuthoritativeSchedulerRead(_ nodes: [Node]) -> [Node] { [] }
    static func readUnknownSchedulerState(nodes: [Node], finished: (Bool) -> Void) { finished(true) }
    // PRODUCTION_SERVER
}

@main struct TimedTaskReplacementTests {
    static func testClearedBinding() {
        let manager = MeshNetworkManager.instance, queue = MeshProxyMessageCommand.shared
        let node = Node(20)
        manager.realNodes = [node]
        for outcome in ["success", "failedSave", "unknown", "partialClear", "busy", "replacement", "assignedRemoval", "changedIntentRemoval", "unknownRemoval", "partialRemoval", "busyRemoval", "missingSlots"] {
            TimedSchedulerTaskCoordinator.invalidateAll()
            let schedule = Schedule(nodes: [node])
            schedule.nodeAddresses = []
            schedule.nodeSlots![0].state = .pendingRemoval
            manager.schedules = [schedule]
            let first = schedule.getMessageHandles(node: node)[0]
            let second = MeshMessageHandle(message: first.message, model: node.extra)
            // One task owns both Scheduler Models of this physical slot.
            first.schedulerTask = nil
            TimedSchedulerTaskCoordinator.attach([first, second], node: node, schedule: schedule)
            first.schedulerAdmission?(); second.schedulerAdmission?()
            first.successful = true; second.successful = true
            node.observedTimedSlots = []
            node.appliedEnabled = false
            queue.isBusy = outcome == "busy"
            schedule.saveSucceeds = outcome != "failedSave"
            if outcome == "unknown" { node.observedTimedSlots = nil; node.appliedEnabled = true }
            if outcome == "partialClear" { node.observedTimedSlots = [0]; node.appliedEnabled = true }
            if outcome == "replacement" {
                schedule.nodeAddresses = [node.primaryUnicastAddress]
                schedule.nodeSlots![0].state = .assigned
                schedule.save()
                precondition(first.schedulerTask!.isCancelled, "replacement must still cancel the completed old task")
            } else if ["changedIntentRemoval", "unknownRemoval", "partialRemoval", "busyRemoval", "missingSlots"].contains(outcome) {
                schedule.nodeSlots = outcome == "missingSlots" ? nil : []
                if outcome == "changedIntentRemoval" { schedule.nodeAddresses = [node.primaryUnicastAddress] }
                if outcome == "unknownRemoval" { node.observedTimedSlots = nil }
                if outcome == "partialRemoval" { node.observedTimedSlots = [0] }
                if outcome == "busyRemoval" { queue.isBusy = true }
                schedule.save()
                precondition(first.schedulerTask!.isCancelled, "unverified binding disappearance must invalidate old receipts: \(outcome)")
            } else if outcome == "assignedRemoval" {
                schedule.nodeSlots![0].state = .assigned
                schedule.save()
                let assigned = schedule.getMessageHandles(node: node)[0]
                assigned.schedulerAdmission?(); assigned.successful = true
                schedule.nodeSlots = []; schedule.save()
                precondition(assigned.schedulerTask!.isCancelled, "arbitrary assigned binding removal is not cleanup completion")
            } else {
                // Proxy is already reset before the synchronization result applies
                // this production release method and then checks isSuccessful.
                schedule.releaseClearedBinding(on: node)
                precondition([first, second].allSatisfy { $0.isSuccessful }, "normal cleanup must preserve successful receipts: \(outcome)")
                precondition(schedule.nodeSlots!.isEmpty == (outcome == "success"))
                if outcome == "failedSave" {
                    schedule.saveSucceeds = true
                    schedule.releaseClearedBinding(on: node)
                    precondition(schedule.nodeSlots!.isEmpty && first.isSuccessful, "failed save can retry without cancelling its receipt")
                }
                if outcome == "success" {
                    precondition(first.transmissionIsValid?() == false, "released work cannot be transmitted again")
                    schedule.nodeSlots = [.init(identity: node.timedSchedulerIdentity!, slot: 0, state: .assigned)]
                    schedule.nodeAddresses = [node.primaryUnicastAddress]
                    schedule.save()
                    precondition(first.schedulerTask!.isCancelled, "slot reuse must invalidate old receipts")
                }
            }
        }
        queue.isBusy = false
        TimedSchedulerTaskCoordinator.invalidateAll()
        print("PASS: production binding release preserves multi-Model receipts; failed save/retry, unknown/partial state, busy and replacement remain protected")
    }
    static func main() {
        let manager = MeshNetworkManager.instance, queue = MeshProxyMessageCommand.shared
        let a = Node(1), b = Node(5)
        manager.realNodes = [a, b]
        let schedule = Schedule(nodes: [a, b]); manager.schedules = [schedule]
        let old = schedule.getMessageHandles(node: a)
        old.forEach { $0.schedulerAdmission?() }
        let differentSlot = MeshMessageHandle(message: SchedulerActionSet(index: 1, entry: schedule.schedulerEntry), model: a.normal)
        let collection = MeshMessageHandle(message: SchedulerActionSet(index: 0, entry: schedule.schedulerEntry), model: a.collection)
        TimedSchedulerTaskCoordinator.attach([differentSlot, collection], node: a)
        differentSlot.schedulerAdmission?(); collection.schedulerAdmission?()
        let cleanup = MeshMessageHandle(message: SchedulerActionSet(index: 0, entry: schedule.schedulerEntry), model: a.extra)
        let write = MeshMessageHandle(message: SchedulerActionSet(index: 0, entry: schedule.schedulerEntry), model: a.normal)
        TimedSchedulerTaskCoordinator.attach([cleanup, write], node: a, schedule: schedule)
        precondition(old[0].schedulerTask?.isCancelled == false, "building a preview cannot cancel a send")
        cleanup.schedulerAdmission?(); write.schedulerAdmission?()
        precondition(cleanup.schedulerTask === write.schedulerTask && cleanup.schedulerTask?.isCancelled == false)
        precondition(old[0].schedulerTask?.isCancelled == true)
        precondition(differentSlot.schedulerTask?.isCancelled == false && collection.schedulerTask?.isCancelled == false)
        schedule.needDeleteNodeAddresses = [9]; schedule.save()
        precondition(write.schedulerTask?.isCancelled == false, "cleanup progress cannot cancel its own operation")
        let stalePreview = schedule.getMessageHandles(node: a)
        schedule.enabled = true; schedule.save()
        let fresh = schedule.getMessageHandles(node: a); fresh[0].schedulerAdmission?()
        stalePreview[0].schedulerAdmission?()
        precondition(stalePreview[0].schedulerTask?.isCancelled == true && fresh[0].schedulerTask?.isCancelled == false)
        let beforeImport = schedule.getMessageHandles(node: b)
        TimedSchedulerTaskCoordinator.invalidateAll()
        beforeImport[0].schedulerAdmission?()
        precondition(beforeImport[0].schedulerTask?.isCancelled == true)
        // Execute the real toggle -> save -> per-device batch continuations.
        var oldCallbacks = 0, newCallbacks = 0
        schedule.enabled = false
        ScheduleServer.setEnabledState(schedule: schedule, enabled: true, success: { _ in oldCallbacks += 1 }, failed: { _ in oldCallbacks += 1 })
        precondition(queue.batches.count == 1)
        ScheduleServer.setEnabledState(schedule: schedule, enabled: false, success: { _ in newCallbacks += 1 }, failed: { _ in newCallbacks += 1 })
        let admittedCount = queue.batches.count
        queue.complete(0, success: false)
        precondition(!schedule.enabled && oldCallbacks == 0 && newCallbacks == 1)
        precondition(queue.batches.count == admittedCount, "superseded batch cannot advance to the next device")
        // Current total failure still rolls back, while partial success persists.
        queue.batches = []
        ScheduleServer.setEnabledState(schedule: schedule, enabled: true, success: nil, failed: nil)
        queue.complete(0, success: false); queue.complete(1, success: false)
        precondition(!schedule.enabled)
        queue.batches = []
        ScheduleServer.setEnabledState(schedule: schedule, enabled: true, success: nil, failed: nil)
        queue.complete(0, success: true); queue.complete(1, success: false)
        precondition(schedule.enabled && a.appliedEnabled && !b.appliedEnabled)
        // The real deletion completion must not remove a same-ID replacement.
        queue.batches = []
        ScheduleServer.deleteSchedule(schedule: schedule, success: nil, failed: nil)
        precondition(queue.batches.count == 1)
        let newSchedule = Schedule(nodes: [a, b]); newSchedule.enabled = true
        manager.schedules = [newSchedule]
        ScheduleServer.saveSchedule(schedule: newSchedule, setNodes: [a, b], success: nil, failed: nil)
        let beforeLateDelete = queue.batches.count
        queue.complete(0, success: true)
        precondition(!schedule.deleted && manager.schedules.first === newSchedule && queue.batches.count == beforeLateDelete,
                     "obsolete deletion cannot delete the replacement or start its next device")
        TimedSchedulerTaskCoordinator.invalidateAll()
        testClearedBinding()
        print("PASS: production admission, per-node/slot/domain ownership, preflight, stale construction, cloud lifecycle, old callbacks, batch continuation and toggle rollback/partial success")
    }
}
