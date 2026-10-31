// Production controller decisions, resolver, bindings and SQLite run together.
// UIKit, connectivity and the asynchronous read are recording boundaries.
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
}
final class ScheduleEntryBoundary {
    var opensSync = false
    var reads: [Node] = []
    func saveBtnAction() {}
    func doneBtnAction() {}
    func resolveSchedulerState(nodes: [Node], retry: @escaping () -> Void) -> Bool {
        reads = nodes
        return true
    }
    func create(schedule: Schedule) {
        // ACTUAL_CREATE_DECISION
        opensSync = needSync
    }
    func edit(original: Schedule, schedule: Schedule) {
        // ACTUAL_EDIT_PREREAD
    }
}
extension Run {
    static func deviceSceneReferences() throws {
        let manager = MeshNetworkManager.instance
        let a = Node(101), b = Node(102)
        let old = Scene(61), next = Scene(62)
        func configure(_ scene: Scene, nodes: [Node]) throws {
            scene.info.configuration = try SceneConfiguration(kind: .devices, name: "Devices",
                deviceMembers: nodes.map { .init(identity: $0.timedSchedulerIdentity!,
                    parameters: .init(isOn: true, lightness: 2000, cct: 4000)) }).normalized()
        }
        try configure(old, nodes: [a, b]); try configure(next, nodes: [b])
        manager.scenes = [old, next]; manager.realNodes = [a, b]
        let original = Schedule(id: 901, name: "Before", enabled: true, sceneNumber: old.number)
        original.scene = old
        let schedule = Schedule(id: 902, name: "After", enabled: true, sceneNumber: next.number)
        schedule.scene = next; schedule.nodeSlots = []
        manager.schedules = [schedule]
        let entry = ScheduleEntryBoundary()
        entry.create(schedule: schedule)
        precondition(entry.opensSync && entry.reads == [b], "device scene opens Sync")
        let disconnected = ScheduleEntryBoundary()
        MeshLibManager.manager.isMeshNetworkConnected = false
        disconnected.create(schedule: schedule)
        precondition(!disconnected.opensSync && disconnected.reads.isEmpty)
        MeshLibManager.manager.isMeshNetworkConnected = true
        b.allSchedulerModelEntrys = [:]
        entry.edit(original: original, schedule: schedule)
        precondition(entry.reads.contains(a) && entry.reads.contains(b), "pre-read both old and candidate targets")
        b.schedulerSetupModels.forEach { b.allSchedulerModelEntrys[$0] = [:] }
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [schedule]))
        precondition(schedule.slot(on: b) != nil, "read candidate can reserve a slot")
        let empty = Schedule(id: 903, name: "Empty", enabled: true)
        let emptyEntry = ScheduleEntryBoundary()
        MeshLibManager.manager.isMeshNetworkConnected = false
        emptyEntry.create(schedule: empty)
        precondition(!emptyEntry.opensSync && emptyEntry.reads.isEmpty)
        emptyEntry.edit(original: empty, schedule: schedule)
        precondition(emptyEntry.reads.isEmpty, "new direct target also enforces edit connectivity")
        MeshLibManager.manager.isMeshNetworkConnected = true

        schedule.needDeleteScenes = [old]; schedule.needDeleteSceneNumbers = [old.number]
        schedule.nodeSlots = [a, b].map { .init(identity: $0.timedSchedulerIdentity!, slot: 3, state: .pendingRemoval) }
        for node in [a, b] {
            node.schedulerSetupModels.forEach { node.allSchedulerModelEntrys[$0] = [3: .init(sceneNumber: old.number)] }
        }
        a.allSchedulerModelEntrys[a.schedulerSetupModels[0]] = [:]
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers == [61], "one Model ACK is insufficient")
        a.schedulerSetupModels.forEach { a.allSchedulerModelEntrys[$0] = [:] }
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers == [61], "another member still recalls old Scene")
        b.allSchedulerModelEntrys[b.schedulerSetupModels[0]] = nil
        b.allSchedulerModelEntrys[b.schedulerSetupModels[1]] = [:]
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers == [61], "unknown is not cleared")
        // Shared member keeps its slot, but every Model now references B.
        b.schedulerSetupModels.forEach { b.allSchedulerModelEntrys[$0] = [3: .init(sceneNumber: next.number)] }
        // Reproduce the actual Node.updateData clear-ACK path, not just the helper.
        b.schedulerSetupModels.forEach { b.allSchedulerModelEntrys[$0] = [3: .init(sceneNumber: old.number)] }
        for (index, model) in b.schedulerSetupModels.enumerated() {
            b.updateData(message: SchedulerActionSet(index: 3, entry: .init(isValid: false)),
                isSuccess: false, model: model)
            precondition(schedule.needDeleteSceneNumbers == [61], "failed ACK retains old reference")
            b.updateData(message: SchedulerActionSet(index: 3, entry: .init(isValid: false)),
                isSuccess: true, model: model)
            precondition(schedule.needDeleteSceneNumbers == (index == 0 ? [61] : []))
        }
        schedule.needDeleteSceneNumbers = [61]
        schedule.nodeSlots = [a, b].map { .init(identity: $0.timedSchedulerIdentity!, slot: 3, state: .assigned) }
        b.schedulerSetupModels.forEach { b.allSchedulerModelEntrys[$0] = [3: .init(sceneNumber: old.number)] }
        for (index, model) in b.schedulerSetupModels.enumerated() {
            b.updateData(message: SchedulerActionSet(index: 3, entry: .init(sceneNumber: next.number)),
                isSuccess: true, model: model)
            precondition(schedule.needDeleteSceneNumbers == (index == 0 ? [61] : []),
                "overwrite ACK releases shared target reference only after all Models converge")
        }
        schedule.needDeleteSceneNumbers = [61]
        let db = SunSmartDataManager.shared.db
        SunSmartDataManager.shared.db = nil
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers == [61], "failed persistence rolls back reference")
        SunSmartDataManager.shared.db = db
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers.isEmpty)
        let loaded = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
            meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: schedule.id).first!
        precondition(loaded.needDeleteSceneNumbers.isEmpty, "reference release survives reload")
        // Older versions may have released all bindings but left the reference.
        schedule.needDeleteSceneNumbers = [61]; schedule.nodeSlots = []
        precondition(schedule.save())
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers.isEmpty, "retry repairs already released bindings")
        schedule.needDeleteSceneNumbers = [61]
        a.deviceKey = Data(repeating: 2, count: 16)
        schedule.reconcilePendingSceneReferences()
        precondition(schedule.needDeleteSceneNumbers == [61], "replaced identity cannot prove old device cleared")
        manager.schedules = []; manager.scenes = []; manager.realNodes = []
        print("PASS device Scene creation/pre-read, multi-Model cleanup, overlap, unknown identity, rollback and reload")
    }
}
