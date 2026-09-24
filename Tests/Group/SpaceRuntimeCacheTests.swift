import Foundation

private final class TestSpaceOwner {
    deinit { NodeSyncStatusRefresh.endSession(owner: self) }
}

extension NodeSyncStatusRefreshTests {
    static func spaceRuntimeCacheTests() async {
        var network = fixture(8)
        let space = NSObject(), cell = NSObject(), object = NSObject()
        NodeSyncStatusRefresh.beginSession(owner: space)
        var made = 0, checks = 0, completed = 0
        func request() {
            NodeSyncStatusRefresh.requestRead(object: object, owner: cell, makeRead: { _ in
                made += 1
                var cursor = 0
                return { _ in
                    checks += 1; cursor += 1
                    return cursor == 3 ? false : nil
                }
            }, completion: { value in require(!value, "page read changed"); completed += 1 })
        }
        request(); await drain { completed == 1 }
        request(); await drain { completed == 2 }
        require(made == 1 && checks == 3, "Space reentry repeated an unchanged page read")
        NodeSyncStatusGeneration.invalidate()
        request(); await drain { completed == 3 }
        require(made == 2, "device change did not invalidate page result")
        ConfigurationSnapshotRevision.value = 9
        request(); await drain { completed == 4 }
        require(made == 3, "saved edit did not invalidate page result")
        NodeSyncStatusRefresh.endSession(owner: space)
        NodeSyncStatusRefresh.beginSession(owner: space)
        request(); await drain { completed == 5 }
        require(made == 4, "Space exit retained runtime results")
        NodeSyncStatusRefresh.requestRead(object: NSObject(), owner: cell, makeRead: { _ in
            { _ in preconditionFailure("cancelled page computed") }
        }, completion: { _ in preconditionFailure("cancelled page published") })
        NodeSyncStatusRefresh.endSession(owner: space)
        var transient: TestSpaceOwner? = TestSpaceOwner()
        NodeSyncStatusRefresh.beginSession(owner: transient!)
        request(); await drain { completed == 6 }
        transient = nil
        request(); await drain { completed == 7 }
        require(made == 6, "deinit did not release the completed session cache")
        network = fixture(8)
        NodeSyncStatusRefresh.requestRead(object: object, owner: cell, makeRead: { _ in
            { _ in preconditionFailure("previous network page computed") }
        }, completion: { _ in preconditionFailure("previous network page published") })
        network = fixture(8)
        var currentDone = false
        NodeSyncStatusRefresh.request(nodes: network.nodes, owner: space) { _ in currentDone = true }
        await drain { currentDone }

        // Compare the production incremental page query with the original full
        // planner. Device comparisons are isolated; both enumerate real policies
        // for target membership, pending Groups/Scenes and orphan deletion.
        network = fixture(12)
        for address: Address in [0xC002, 0xC003] {
            let group = Group(address); group.network = network; network.groups.append(group)
        }
        for (index, node) in network.nodes.enumerated() {
            node.sunricherVendorModel?.subscribe = [network.groups[index % 3].address.address]
            if index % 4 == 0 { node.groupState = .exitFailure }
        }
        let context = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes,
                                          protection: SpaceConfigurationSafety.testSnapshot(network))
        await prepare(context)
        let scene = Scene(); scene.info.groups = [network.groups[1], network.groups[2]]
        for mode in Schedule.TargetType.allCases {
            for seed in 0..<80 {
                let schedule = Schedule(); schedule.selectTargetType = mode
                schedule.groups = seed % 2 == 0 ? [network.groups[0]] : []
                schedule.scene = seed % 3 == 0 ? scene : nil
                schedule.nodeAddresses = network.nodes.enumerated().filter { ($0.offset + seed) % 5 == 0 }.map { $0.element.primaryUnicastAddress }
                schedule.needDeleteNodes = [network.nodes[1], network.nodes[5]]
                schedule.needDeleteGroups = [network.groups[2]]; schedule.needDeleteScenes = [scene]
                schedule.syncRead = { [weak schedule] node, group in
                    schedule?.targets(node: node, contextGroup: group) == true && (Int(node.primaryUnicastAddress) + seed) % 7 == 0
                }
                schedule.deleteRead = { [weak schedule] node, group in
                    schedule?.targets(node: node, contextGroup: group) == false && (Int(node.primaryUnicastAddress) + seed + Int(group?.address.address ?? 0)) % 6 == 0
                }
                require(schedule.signature(schedule.getNeedSyncDatas()) == schedule.signature(schedule.legacyNeedSyncDatas()),
                        "schedule plan changed target/removal semantics")
                let expected = !schedule.getNeedSyncDatas().isEmpty()
                let read = context.perform { SpacePageSyncRead(schedule: schedule, context: context) }
                var actual: Bool?
                while actual == nil { actual = context.perform { read.advance(until: 0) } }
                require(actual == expected, "incremental schedule changed full planner result")
            }
        }
        for seed in 0..<13 {
            scene.unsynced = [Address(seed)]
            let expected = scene.info.groups.contains { group in group.nodes.contains { scene.unsynced.contains($0.primaryUnicastAddress) } }
            let read = SpacePageSyncRead(scene: scene, context: context)
            var result: Bool?
            while result == nil { result = context.perform { read.advance(until: 0) } }
            require(result == expected, "incremental scene changed member result")
        }
        require(context.node(elementAddress: network.nodes[0].elements[0].unicastAddress) === network.nodes[0], "sensor index mismatch")
        var reads = 0
        for _ in 0..<5 {
            let value: Int = context.memoized("controllers") { reads += 1; return 42 }
            require(value == 42, "memoized controller value changed")
        }
        require(reads == 1, "controllers were loaded per node")

        await schedulerReadQueueTests()
        await schedulerCandidateChangesTests()
        await groupOnOffReadTests()
        #if DEBUG
        print("PASS: Space cache hit/invalidation/exit/cross-network, 320 schedule plans, 13 scenes, sensor/controller reuse, BLE queue lifecycle")
        #endif
    }

    static func groupOnOffReadTests() async {
        let network = stressFixture(), owner = NSObject()
        let groups = network.groups
        NodeSyncStatusRefresh.beginSession(owner: owner)
        defer { NodeSyncStatusRefresh.endSession(owner: owner) }
        Model.subscriptionReads = 0
        let started = ProcessInfo.processInfo.systemUptime
        require(NodeSyncStatusRefresh.groupOnOffStates(groups).allSatisfy { !$0 }, "cold group read changed member-derived off state")
        let fallbackElapsed = ProcessInfo.processInfo.systemUptime - started
        let fallbackReads = Model.subscriptionReads
        let onePassStart = Model.subscriptionReads
        for node in network.nodes { _ = node.group }
        require(fallbackReads == Model.subscriptionReads - onePassStart, "fallback scanned the whole network once per Group")
        #if DEBUG
        print("Group live fallback: \(groups.count) groups / \(network.nodes.count) nodes, subscription reads=\(fallbackReads), seconds=\(fallbackElapsed)")
        #endif
        var done = false
        NodeSyncStatusRefresh.request(group: groups[0], owner: owner) { _ in done = true }
        await drain { done }
        let revision = SpacePageRevision()
        let reads = Model.subscriptionReads, plans = TestMetrics.planBuilds
        let checks = network.nodes.reduce(0) { $0 + $1.checks }
        network.nodes[0].isOn = true
        require(NodeSyncStatusRefresh.groupOnOffStates([groups[0]]) == [true], "cached membership froze live on/off")
        network.nodes[0].isOn = false
        for _ in 0..<10 {
            require(NodeSyncStatusRefresh.groupOnOffStates(groups).allSatisfy { !$0 }, "reentry retained an old live value")
        }
        require(revision.isCurrent, "live state invalidated the page revision")
        require(Model.subscriptionReads == reads && TestMetrics.planBuilds == plans
                && network.nodes.reduce(0, { $0 + $1.checks }) == checks,
                "live appearance repeated membership or sync computation")

        // A configuration change must reject cached membership, not just read
        // fresh on/off from nodes in the previous member list.
        network.nodes[0].sunricherVendorModel?.subscribe = [groups[1].address.address]
        network.nodes[0].isOn = true
        ConfigurationSnapshotRevision.value = 1
        require(NodeSyncStatusRefresh.groupOnOffStates(Array(groups.prefix(2))) == [false, true], "invalid context reused old members")
        NodeSyncStatusRefresh.endSession(owner: owner)

        // No context/revision is required for either member-derived states or a
        // local override. An empty group preserves the existing on appearance.
        ConfigurationSnapshotRevision.value = nil
        let empty = Group(0xC100); empty.network = network; network.groups.append(empty)
        require(NodeSyncStatusRefresh.groupOnOffStates([groups[0], groups[1], empty]) == [false, true, true], "unavailable context changed live state")
        groups[0].isOn = true; groups[1].isOn = false
        Model.subscriptionReads = 0
        require(NodeSyncStatusRefresh.groupOnOffStates(Array(groups.prefix(2))) == [true, false], "local on/off override was ignored")
        require(Model.subscriptionReads == 0, "local overrides unnecessarily loaded members")
        ConfigurationSnapshotRevision.value = 0
    }

    static func schedulerReadQueueTests() async {
        struct Item { let id = UUID() }
        let items = (0..<5).map { _ in Item() }
        var clock = 10.0, connected = true, busy = true, current = true
        var batches: [[Item]] = [], updates = 0
        var completions: [() -> Void] = []
        let queue = SpaceSchedulerReadQueue(candidates: { items + [items[0]] }, identifier: { $0.id },
            isCurrent: { current }, connected: { connected }, busy: { busy }, now: { clock },
            read: { batch, finished in batches.append(batch); completions.append(finished) },
            updated: { updates += 1 })
        queue.request(); queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        require(batches.isEmpty, "background read ignored Mesh busy state")
        busy = false
        await drain { batches.count == 1 }
        queue.request(); completions.removeFirst()()
        await drain { batches.count == 2 }
        completions.removeFirst()()
        await drain { batches.count == 3 }
        completions.removeFirst()()
        try? await Task.sleep(nanoseconds: 150_000_000)
        require(batches.map(\.count) == [2, 2, 1] && updates == 3, "read demand duplicated nodes or exceeded batch size")
        queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        require(batches.count == 3, "unknown failure retried without cooldown")
        clock += 31; connected = false; queue.request()
        require(batches.count == 3, "disconnected read started")
        connected = true; queue.request()
        await drain { batches.count == 4 }
        current = false
        completions.removeFirst()()
        require(updates == 3, "late network callback updated another Space")
        current = true; queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        require(batches.count == 4, "stopped old queue restarted")
        var exitCompletion: (() -> Void)?
        let exitQueue = SpaceSchedulerReadQueue(candidates: { items }, identifier: { $0.id },
            isCurrent: { true }, connected: { true }, busy: { false },
            read: { _, done in exitCompletion = done }, updated: { preconditionFailure("exit callback published") })
        exitQueue.request(); await drain { exitCompletion != nil }
        exitQueue.stop(); exitCompletion?()
    }

    static func schedulerCandidateChangesTests() async {
        final class Item {
            let id: UUID
            var models: [[Int: Bool]?] = [nil]
            init(id: UUID = UUID()) { self.id = id }
            var unknown: Bool {
                TimedSchedulerCacheRepairPolicy.needsAuthoritativeRead(modelKnownStates: models.map { $0 != nil })
            }
        }
        var items = (0..<6).map { _ in Item() }
        var busy = true, current = true, connected = true, candidateReads = 0
        var batches: [[Item]] = [], completions: [() -> Void] = [], updates = 0
        let queue = SpaceSchedulerReadQueue(candidates: {
            candidateReads += 1
            return items.filter(\.unknown)
        }, identifier: { $0.id }, isCurrent: { current }, connected: { connected }, busy: { busy },
            read: { batch, done in batches.append(batch); completions.append(done) }, updated: { updates += 1 })
        defer { queue.stop() }

        queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        // Both an authoritative empty record and a populated record are known.
        for (index, item) in items.enumerated() { item.models = [index.isMultiple(of: 2) ? [:] : [1: true]] }
        busy = false
        try? await Task.sleep(nanoseconds: 550_000_000)
        require(batches.isEmpty && updates == 0, "known candidates were dispatched after Mesh busy wait")

        // Skipped nodes must not receive a retry cooldown, and an empty pass
        // must release running so a new demand can start immediately.
        items[0].models = [[:], nil]
        queue.request()
        await drain { batches.count == 1 }
        require(batches[0].count == 1 && batches[0][0] === items[0], "skipped candidate was cooled down or partial Model unknown was ignored")
        items[0].models = [[:], [:]]
        completions.removeFirst()()
        try? await Task.sleep(nanoseconds: 150_000_000)

        items = (0..<6).map { _ in Item() }
        busy = true; queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let removed = items[2], replacement = Item(id: items[3].id)
        items[0].models = [[:]]; items[1].models = [[1: true]]
        items.remove(at: 2)
        items[2] = replacement
        items.append(replacement) // duplicate current UUID must not duplicate a read
        busy = false
        await drain { batches.count == 2 }
        require(batches[1].count == 2 && batches[1][0] === replacement && batches[1][1] === items[3],
                "stale prefix prevented a later batch, priority changed, or old instance was sent")
        require(!batches.flatMap { $0 }.contains { $0 === removed }, "removed node was dispatched")
        items[4].models = [[:]] // remaining node becomes known while the first batch is in flight
        let newlyUnknown = Item(); items.append(newlyUnknown)
        completions.removeFirst()()
        try? await Task.sleep(nanoseconds: 150_000_000)
        require(batches.count == 2 && updates == 2, "later batch reused stale candidates or expanded the original demand")
        queue.request()
        await drain { batches.count == 3 }
        require(batches[2].count == 1 && batches[2][0] === newlyUnknown, "next demand missed a new candidate or ignored cooldown")
        newlyUnknown.models = [[:]]; completions.removeFirst()()
        try? await Task.sleep(nanoseconds: 150_000_000)

        items = [Item()]; busy = true; queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        connected = false; busy = false
        let readsBeforeDisconnect = candidateReads
        try? await Task.sleep(nanoseconds: 550_000_000)
        require(batches.count == 3 && candidateReads == readsBeforeDisconnect, "disconnected queue selected or dispatched a batch")
        connected = true; busy = true; queue.request()
        try? await Task.sleep(nanoseconds: 20_000_000)
        current = false; busy = false
        try? await Task.sleep(nanoseconds: 550_000_000)
        require(batches.count == 3 && updates == 3, "old Space dispatched while waiting")
    }
}
