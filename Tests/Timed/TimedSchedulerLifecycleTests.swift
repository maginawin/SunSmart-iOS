// The queue/air boundary is controlled. Status bytes, SDK cache observation,
// Proxy completion/reset, App binding results, SDK property codecs and Schedule SQLite are real code.
typealias StaticMeshMessage = StaticMeshResponse
typealias MessageCommandProgressCallback = (Int, Int) -> Void
typealias MessageCommandSuccessfulCallback = (MeshMessageHandle, StaticMeshMessage) -> Void
typealias MessageCommandFailedCallback = (MeshMessageHandle) -> Void
typealias MessageCommandFinishedCallback = ([MeshMessageHandle]) -> Void
final class MeshLibManager {
    static let manager = MeshLibManager()
    var delegate: NSObject?, messageDelegate: NSObject?
    var isMeshNetworkConnected = true
}
final class MeshNodeHeartbeatManager {
    static let shared = MeshNodeHeartbeatManager()
    func refreshOfflineNodes() {}
}
final class MeshMessageManager {
    static let manager = MeshMessageManager()
    func cancelSchedulerTasks(_ tasks: [MeshSchedulerTask]) { tasks.forEach { $0.cancel() } }
}
final class LifecycleNetworkParameters { var acknowledgmentMessageTimeout: TimeInterval = 5 }
extension MeshNetworkManager {
    static let lifecycleParameters = LifecycleNetworkParameters()
    var networkParameters: LifecycleNetworkParameters { Self.lifecycleParameters }
}
// Device registers are independent of the App's observed cache. A dropped ACK
// can leave hardware changed, while a cancelled-before-send request cannot.
final class SchedulerPeer {
    var registers: [Model: [Int: Entry]] = [:]
    init(nodes: [Node]) {
        nodes.forEach { node in node.schedulerSetupModels.forEach { registers[$0] = node.allSchedulerModelEntrys[$0] ?? [:] } }
    }
    func execute(_ handle: MeshMessageHandle) {
        guard handle.schedulerTask?.isCancelled != true else { return }
        let set = handle.message as! SchedulerActionSet
        if set.entry.isValid { registers[handle.model!]![Int(set.index)] = set.entry }
        else { registers[handle.model!]!.removeValue(forKey: Int(set.index)) }
    }
    func readBack(_ node: Node) {
        for model in node.schedulerSetupModels {
            let owner = MeshSchedulerTask(), address = model.parentElement!.unicastAddress
            let entries = registers[model]!
            let bits = entries.keys.reduce(UInt16(0)) { $0 | (1 << $1) }
            model.schedulerObservation.sent(SchedulerGet(), owner: owner)
            let status = SchedulerStatus(parameters: SchedulerStatus(report: bits).parameters!)!
            node.observe(status, source: address)
            for (slot, entry) in entries {
                model.schedulerObservation.sent(SchedulerActionGet(index: UInt8(slot)), owner: owner)
                let bytes = SchedulerActionStatus(index: UInt8(slot), entry: entry).parameters!
                node.observe(SchedulerActionStatus(parameters: bytes)!, source: address)
            }
        }
    }
}
final class MeshProxyMessageCommand: NSObject {
    static let shared = MeshProxyMessageCommand()
    var sendMessageHandles: [MeshMessageHandle] = []
    var isBusy: Bool {
        get { !sendMessageHandles.isEmpty }
        set { if !newValue { sendMessageHandles.removeAll() } }
    }
    // PRODUCTION_SUBMISSION
    private var submissions: [Submission] = []
    private var callbackSubmission: Submission?
    private var stopCompletion: MessageCommandFinishedCallback?
    var preparationID: UUID?, batchID = UUID(), currentIndex = 0, stopSend = false
    var progressBack: MessageCommandProgressCallback?, sendSuccessfulBack: MessageCommandSuccessfulCallback?
    var sendFailedBack: MessageCommandFailedCallback?, finnishedBack: MessageCommandFinishedCallback?
    var lastMeshLibDelegate: NSObject?, lastMessageDelegate: NSObject?
    var networkParameterAcknowledgedMessageTimeout: TimeInterval = 5
    @objc func sendMessageWaitTimeout() {}
    @objc func meshNetworkConnectTimeout() {}
    func cancelSchedulerTasks(_ tasks: [MeshSchedulerTask]) { tasks.forEach { $0.cancel() } }
    // PRODUCTION_COMPLETION

    func begin(_ handles: [MeshMessageHandle], finished: @escaping MessageCommandFinishedCallback) {
        precondition(!isBusy)
        handles.forEach { $0.schedulerAdmission?() }
        sendMessageHandles = handles
        submissions = [Submission(handles: handles, progress: nil, success: nil, failure: nil, finished: finished)]
        // Models remember the owner at the real send boundary, before any response.
        handles.forEach { $0.model!.schedulerObservation.sent($0.message, owner: $0.schedulerTask) }
    }
    func deliver(_ bytes: Data, to handle: MeshMessageHandle, node: Node) {
        let status = SchedulerActionStatus(parameters: bytes)!
        // Global SDK cache update precedes the awaited response/Proxy callback.
        node.observe(status, source: handle.allAddresss[0])
        guard handle.schedulerTask?.isCancelled != true,
              NetworkManager.schedulerResponseMatches(handle.message, response: status),
              handle.responseIsValid?(status) != false else { return }
        handle.respondAddresss = handle.allAddresss
        reportSuccess(handle, status)
    }
    func finish() { finishMessages() }
}

extension Run {
    static func schedulerLifecycle(path: String) throws {
        setbuf(stdout, nil)
        let manager = MeshNetworkManager.instance, proxy = MeshProxyMessageCommand.shared
        for scenario in ["normal", "lateOldACK", "partial", "nodeSaveFailure", "scheduleSaveFailure", "cancelled", "replacement", "readded"] {
            TimedSchedulerTaskCoordinator.invalidateAll()
            let nodes = [Node(0x49F9), Node(0x49FC)]
            let group = Group(); group.nodes = nodes; nodes.forEach { $0.group = group }
            manager.realNodes = nodes; manager.groups = [group]
            var schedule = Schedule(id: 4100, name: "Group", enabled: true, groupAddresses: [group.address.address], selectTargetType: .groups)
            schedule.groups = [group]
            schedule.nodeSlots = nodes.map { .init(identity: $0.timedSchedulerIdentity!, slot: 0, state: .pendingApply, actionAddress: $0.timedActionAddress()) }
            // Off stays on the ordinary Model across Group membership changes.
            // Auto/On intentionally changes owner for an automatic Group.
            let retained = Schedule(id: 4101, name: "Direct", enabled: true, nodeAddresses: nodes.map(\.primaryUnicastAddress), action: .off)
            retained.nodeSlots = nodes.map { .init(identity: $0.timedSchedulerIdentity!, slot: 1, state: .synced, actionAddress: $0.timedActionAddress()) }
            manager.schedules = [schedule, retained]
            precondition(schedule.save() && retained.save())
            for node in nodes { node.allSchedulerModelEntrys[node.schedulerSetupModels[0]] = [1: retained.schedulerEntry] }
            let peer = SchedulerPeer(nodes: nodes)
            let retainedBindings = retained.nodeSlots
            var addHandles: [Address: [MeshMessageHandle]] = [:]
            for node in nodes {
                let handles = schedule.getMessageHandles(node: node)
                precondition(!handles.isEmpty)
                var completed: Bool?
                proxy.begin(handles) { completed = schedule.applySchedulerResults($0, expected: handles, on: node) }
                for handle in handles {
                    peer.execute(handle)
                    proxy.deliver((handle.message as! SchedulerActionSet).parameters!, to: handle, node: node)
                }
                proxy.finish()
                precondition(completed == true && schedule.schedulerSyncDifference(on: node) == .synchronized, "add: \(scenario)")
                addHandles[node.primaryUnicastAddress] = handles
            }
            nodes.forEach { $0.groupState = .exitFailure }
            for (offset, node) in nodes.enumerated() {
                let failing = offset == 0 && scenario != "normal"
                if failing && scenario == "partial" {
                    node.allSchedulerModelEntrys[node.schedulerSetupModels[0]]![0] = schedule.schedulerEntry
                    peer.registers[node.schedulerSetupModels[0]]![0] = schedule.schedulerEntry
                }
                // The production reservation invalidates the old apply owner.
                precondition(TimedSchedulerBindings.reserveForDeletion(schedule: schedule, node: node))
                if failing && scenario == "lateOldACK" {
                    let old = addHandles[node.primaryUnicastAddress]!.last!
                    let bytes = (old.message as! SchedulerActionSet).parameters!
                    proxy.deliver(bytes, to: old, node: node)
                    precondition(node.observedTimedSlots == nil, "obsolete reply must invalidate observation")
                }
                let handles = schedule.getMessageHandles(node: node, delete: true)
                precondition(!handles.isEmpty)
                var completed: Bool?
                proxy.begin(handles) { results in
                    precondition(!proxy.isBusy, "Proxy resets before App binding release")
                    completed = schedule.applySchedulerResults(results, expected: handles, on: node)
                }
                if failing && scenario == "cancelled" { handles[0].schedulerTask!.cancel() }
                if failing && scenario == "replacement" { schedule.enabled = false; precondition(schedule.save()) }
                if failing && scenario == "readded" {
                    node.groupState = .inGroup
                    precondition(TimedSchedulerBindings.reserveForSending(schedule: schedule, node: node, contextGroup: group))
                }
                handles.forEach { peer.execute($0) }
                var pendingDeliveries = 0
                for (index, handle) in handles.enumerated() where !failing || scenario != "partial" || index == 0 {
                    let bytes = (handle.message as! SchedulerActionSet).parameters!
                    precondition(bytes.hex == "40060080791EF03F0000", "use the captured removal payload")
                    // Delivery is asynchronous, just like the SDK's delegate queue.
                    pendingDeliveries += 1
                    DispatchQueue.main.async {
                        proxy.deliver(bytes, to: handle, node: node)
                        pendingDeliveries -= 1
                    }
                }
                let deadline = Date().addingTimeInterval(2)
                while pendingDeliveries > 0 && Date() < deadline {
                    RunLoop.current.run(until: Date().addingTimeInterval(0.001))
                }
                precondition(pendingDeliveries == 0, "delegate delivery must complete")
                if failing && scenario == "nodeSaveFailure" { node.propertiesSaveSucceeds = false }
                if failing && scenario == "scheduleSaveFailure" {
                    try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER fail_lifecycle BEFORE INSERT ON schedules WHEN NEW.scheduleIndex = 4100 BEGIN SELECT RAISE(ABORT, 'lifecycle failure'); END")
                }
                proxy.finish()
                precondition(completed == !failing, "remove: \(scenario), node \(offset)")
                precondition((schedule.slot(on: node) != nil) == failing, "result binding: \(scenario)")
                if failing && scenario == "scheduleSaveFailure" { try SunSmartDataManager.shared.db!.execute("DROP TRIGGER fail_lifecycle") }
                node.propertiesSaveSucceeds = true
                if failing {
                    SunSmartDataManager.shared.db = try Connection(path)
                    schedule = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
                        meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: schedule.id).first!
                    schedule.groups = [group]; manager.schedules = [schedule, retained]
                    precondition(schedule.slot(on: node) == 0, "failed work remains durable after reopen")
                    // Recovery uses a new authoritative register read, never pretends
                    // an unknown Model was emptied by a single-slot response.
                    peer.readBack(node)
                    schedule.enabled = true; precondition(schedule.save())
                    let retry = schedule.getMessageHandles(node: node, delete: scenario != "readded")
                    let needsSend = scenario == "cancelled" || scenario == "replacement"
                    precondition(retry.count == (needsSend ? 1 : 0), "retry only uncleared Models")
                    proxy.begin(retry) { precondition(schedule.applySchedulerResults($0, expected: retry, on: node), "retry result: \(scenario)") }
                    for handle in retry {
                        peer.execute(handle)
                        proxy.deliver((handle.message as! SchedulerActionSet).parameters!, to: handle, node: node)
                    }
                    proxy.finish()
                }
                SunSmartDataManager.shared.db = try Connection(path)
                let loaded = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
                    meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: schedule.id).first!
                precondition(loaded.nodeSlots == schedule.nodeSlots, "reload binding: \(scenario)")
                precondition((loaded.slot(on: node) == nil) == !(failing && scenario == "readded"), "final slot: \(scenario)")
                let sortBindings: ([TimedSchedulerNodeSlot]?) -> [TimedSchedulerNodeSlot] = {
                    ($0 ?? []).sorted { $0.identity.unicastAddress < $1.identity.unicastAddress }
                }
                let before = sortBindings(retainedBindings), after = sortBindings(retained.nodeSlots)
                precondition(after.count == before.count)
                // prepare() refreshes the unused Auto/On route for the other
                // exiting node. Off's target, slot, progress and actual route stay.
                precondition(zip(before, after).allSatisfy { old, new in
                    old.identity == new.identity && old.slot == new.slot && old.state == new.state
                        && old.actionAddress?.off == new.actionAddress?.off && new.isV3
                }, "retained Off binding: \(scenario)")
                // Other slots remain intact even when the old observation is rejected.
                precondition(node.allSchedulerModelEntrys[node.schedulerSetupModels[0]]?[1] == retained.schedulerEntry, "retained cache: \(scenario)")
                precondition(peer.registers[node.schedulerSetupModels[0]]?[1] == retained.schedulerEntry, "retained device register: \(scenario)")
            }
            print("PASS: Scheduler wire -> SDK observation -> Proxy reset -> App result -> SQLite: \(scenario)")
        }
        // Exact field-log payload: Wednesday 08:00 Off, fade 38 seconds, slot 0.
        TimedSchedulerTaskCoordinator.invalidateAll()
        let original = Node(0x0010)
        original.schedulerSetupModels[1].parentElement!.unicastAddress = 0x0012
        original.allSchedulerModelEntrys = [:]
        manager.realNodes = [original]; manager.groups = []
        let timed = Schedule(id: 4200, name: "Entry", enabled: true, nodeAddresses: [0x0010], action: .off)
        timed.weekDays = [.Wednesday]; timed.hour = 8; timed.minute = 0; timed.fadeTime = 38
        timed.nodeSlots = [.init(identity: original.timedSchedulerIdentity!, slot: 0, state: .pendingApply, actionAddress: original.timedActionAddress())]
        manager.schedules = [timed]
        precondition(timed.save())
        let handles = timed.getMessageHandles(node: original)
        precondition(handles.count == 2)
        precondition((handles.last!.message as! SchedulerActionSet).parameters!.hex == "40FE7F80008000660000")
        proxy.begin(handles) { precondition(timed.applySchedulerResults($0, expected: handles, on: original)) }
        for handle in handles { proxy.deliver((handle.message as! SchedulerActionSet).parameters!, to: handle, node: original) }
        proxy.finish()
        var current = original
        for _ in 0..<3 {
            // Equal-version v3 import creates new Node/Model objects without observations.
            let replacement = Node(0x0010)
            replacement.uuid = original.uuid
            replacement.schedulerSetupModels[1].parentElement!.unicastAddress = 0x0012
            replacement.allSchedulerModelEntrys = [:]
            replacement.restoreLocalSchedulerObservation(from: current)
            precondition(replacement.savePropertys())
            // Discard memory and reload real SDK property bytes from SQLite.
            replacement.allSchedulerModelEntrys = [:]
            try replacement.reloadProperties()
            let reloaded = Schedule.load(meshUUID: manager.meshNetwork!.uuid.uuidString,
                meshNetworkId: manager.currentNetworkKey.networkId.hex, scheduleId: timed.id).first!
            manager.realNodes = [replacement]; manager.schedules = [reloaded]
            precondition(reloaded.schedulerSyncDifference(on: replacement) == .synchronized)
            precondition(reloaded.getMessageHandles(node: replacement).isEmpty, "re-entry must not resend successful Models")
            current = replacement
        }
        let loaded = manager.schedules[0]
        loaded.minute = 1
        precondition(loaded.save())
        precondition(loaded.needsSync(on: current), "new desired configuration still needs synchronization")
        precondition(loaded.getMessageHandles(node: current).count == 1, "changed owner entry must not resend confirmed cleanup")
        print("PASS: field-log ACK -> binding -> SQLite -> v3 Node replacement -> SDK reload -> zero tasks across three entries; changed intent still sends")
        TimedSchedulerTaskCoordinator.invalidateAll()
    }
}
