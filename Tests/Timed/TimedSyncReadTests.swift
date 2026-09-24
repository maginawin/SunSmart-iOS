import Foundation

// Pre-fix planner retained as a semantic oracle on small fixtures. It does not
// define the new reader and is never used for the large performance scenario.
extension Schedule {
    func legacyNeedSyncDatas() -> ScheduleSyncData {

        var syncNodes: [Node] = []
        var syncGroupData: [Group: [Node]] = [:]

//        var allSetScheduleNodes: [Node] = []

        // 所有需要同步的设备 直接关联-间接关联（组、场景）只设置一次不需要重复同步
        var allSyncNodes: [Node] = []
        // 所有需要删的设备 直接关联-间接关联（组、场景） 只删除一次不需要重复删除
//        var allDeleteNodes: [Node] = []

        switch selectTargetType {
        case .devices:
            syncNodes = nodes.filter({ needsSync(on: $0) })
            allSyncNodes.append(contentsOf: nodes)
        case .groups:
            groups.forEach({ group in
                let groupTargetNodes = group.nodes.filter({ node in targets(node: node, contextGroup: group) })
                let groupSyncNodes = groupTargetNodes.filter({ node in needsSync(on: node, contextGroup: group) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: group)
                }
                allSyncNodes.append(contentsOf: groupTargetNodes)
            })
        case .scene:
            scene?.info.groups.forEach({ group in
                let groupTargetNodes = group.nodes.filter({ node in targets(node: node, contextGroup: group) })
                let groupSyncNodes = groupTargetNodes.filter({ node in needsSync(on: node, contextGroup: group) })
                if groupSyncNodes.count > 0 {
                    syncGroupData.updateValue(groupSyncNodes, forKey: group)
                }
                allSyncNodes.append(contentsOf: groupTargetNodes)
            })
        case .profile:
            break
        }

        var deleteNodes = needDeleteNodes.filter({ needsDelete(from: $0) && !allSyncNodes.contains($0) })

        var deleteGroupData: [Group: [Node]] = [:]
        needDeleteGroups.forEach({ group in
            let groupDeleteNodes = group.nodes.filter({ node in needsDelete(from: node, contextGroup: group) && !allSyncNodes.contains(node) && !deleteNodes.contains(node) })
            // ((!allSyncNodes.contains($0) && !allDeleteNodes.contains($0)) || !nodes.contains($0))
            if groupDeleteNodes.count > 0 {
                deleteGroupData.updateValue(groupDeleteNodes, forKey: group)
//                allDeleteNodes.append(contentsOf: groupDeleteNodes)
            }
        })

        needDeleteScenes.forEach({ scene in
            scene.info.groups.forEach { group in
                let groupDeleteNodes = group.nodes.filter({ node in needsDelete(from: node, contextGroup: group) && !allSyncNodes.contains(node) && !deleteNodes.contains(node) })
                // && !allSyncNodes.contains($0)) && !allDeleteNodes.contains($0)
                if groupDeleteNodes.count > 0 {
                    deleteGroupData.updateValue(groupDeleteNodes, forKey: group)
//                    allDeleteNodes.append(contentsOf: groupDeleteNodes)
                }
            }
        })

        let groupedDeleteNodes = deleteGroupData.values.flatMap({ $0 })
        let orphanDeleteNodes = MeshNetworkManager.instance.realNodes.filter({
            needsDelete(from: $0) &&
            !allSyncNodes.contains($0) &&
            !deleteNodes.contains($0) &&
            !groupedDeleteNodes.contains($0)
        })
        deleteNodes.append(contentsOf: orphanDeleteNodes)

        let data = ScheduleSyncData(syncNodes: syncNodes, deleteNodes: deleteNodes, syncGroups: syncGroupData, deleteGroups: deleteGroupData)
        return data
    }


    func signature(_ data: ScheduleSyncData) -> [String] {
        var rows = data.syncNodes.map { "sync-device-\($0.primaryUnicastAddress)" }
        rows += data.deleteNodes.map { "delete-device-\($0.primaryUnicastAddress)" }
        for (group, nodes) in data.syncGroups { rows += nodes.map { "sync-\(group.address.address)-\($0.primaryUnicastAddress)" } }
        for (group, nodes) in data.deleteGroups { rows += nodes.map { "delete-\(group.address.address)-\($0.primaryUnicastAddress)" } }
        return rows.sorted()
    }
}

extension NodeSyncStatusRefreshTests {
    static func timedSyncReadTests() async {
        let network = fixture(487), session = NSObject()
        network.groups = (0..<18).map { index in
            let group = Group(Address(0xCD60 + index)); group.network = network
            group.info.profile.type = .ordinary
            return group
        }
        for (index, node) in network.nodes.enumerated() {
            node.sunricherVendorModel?.subscribe = [network.groups[index % 18].address.address]
        }
        let scene = Scene(); scene.info.groups = network.groups
        let schedule = Schedule(); schedule.selectTargetType = .scene; schedule.scene = scene
        schedule.needDeleteGroups = Array(network.groups.prefix(2))
        MeshNetworkManager.instance.schedules = [schedule]
        MeshNetworkManager.instance.scenes = [scene]
        for group in network.groups { group.info.bindSchedules = [schedule] }
        var syncChecks = 0, deleteChecks = 0
        var changed = Set<Address>()
        schedule.syncRead = { node, group in
            syncChecks += 1
            return schedule.targets(node: node, contextGroup: group) && changed.contains(node.primaryUnicastAddress)
        }
        schedule.deleteRead = { node, group in
            deleteChecks += 1
            return !schedule.targets(node: node, contextGroup: group)
        }
        Model.subscriptionReads = 0
        let initial = schedule.getNeedSyncDatas()
        require(initial.isEmpty(), "unchanged Scene acquired tasks")
        require(syncChecks == 487 && deleteChecks == 0, "overlapping targets were rechecked for deletion")
        require(Model.subscriptionReads == 487, "full planner rebuilt membership per Group or target node")
        print("PASS: Timed 487 nodes/18 groups: 487 subscription reads, 487 sync checks, 0 covered-target delete checks")

        let context = NodeSyncReadContext(network: network, networkID: "net", nodes: network.nodes,
                                          protection: SpaceConfigurationSafety.testSnapshot(network))
        await prepare(context)
        // Explicit incoming Group is additive to actual membership. An exiting
        // node cannot regain a Group target, but its direct-device target stays.
        let probe = network.nodes[0], other = network.groups[1]
        schedule.scene = nil; schedule.groups = [other]
        require(schedule.targets(node: probe, contextGroup: other), "new member context lost")
        require(!schedule.targets(node: probe), "unrelated live membership accepted")
        probe.groupState = .exitFailure
        require(!schedule.targets(node: probe, contextGroup: other), "exitFailure accepted a Group target")
        schedule.nodeAddresses = [probe.primaryUnicastAddress]
        require(schedule.targets(node: probe, contextGroup: other), "direct target was removed by exitFailure")
        probe.groupState = .inGroup; schedule.nodeAddresses = []; schedule.groups = []; schedule.scene = scene

        changed = [probe.primaryUnicastAddress]
        let overlap = context.perform { network.groups[0].getNeedSyncScheduleDataNodes(schedule) }
        require(overlap.syncNodes == [probe] && overlap.deleteNodes.isEmpty, "pending/current Group hid sync work")
        let incremental = context.perform { Schedule.SyncDataRead(schedule: schedule, nodes: context.nodes, members: context.members(of:)) }
        syncChecks = 0
        require(context.perform { incremental.advance(until: 0) } == nil && syncChecks == 1,
                "a display slice consumed the entire schedule")
        while context.perform({ incremental.advance(until: 0) }) == nil {}
        require(schedule.signature(incremental.result!) == schedule.signature(schedule.getNeedSyncDatas()),
                "sliced plan differs from complete plan")

        NodeSyncStatusRefresh.beginSession(owner: session)
        defer { NodeSyncStatusRefresh.endSession(owner: session) }
        let first = ScheduleTargetDisplayState(), second = ScheduleTargetDisplayState()
        var completed = 0
        syncChecks = 0
        first.refresh(schedule: schedule) { completed += 1 }
        second.refresh(schedule: schedule) { completed += 1 }
        await drain { completed == 2 }
        require(syncChecks == 487, "pickers repeated the same plan")
        require(first.currentSnapshot?.groups == [ObjectIdentifier(network.groups[0])], "Group warning changed")
        require(first.currentSnapshot?.scenes == [ObjectIdentifier(scene)], "Scene warning changed")
        require(first.currentSnapshot?.nodes.isEmpty == true, "Scene work leaked into direct-device warning list")
        first.refresh(schedule: schedule) { fatalError("unchanged picker reloaded") }
        require(syncChecks == 487, "unchanged picker recalculated")

        changed = []; NodeSyncStatusGeneration.invalidate()
        require(first.currentSnapshot == nil, "stale result remained available")
        first.refresh(schedule: schedule) { completed += 1 }
        await drain { completed == 3 }
        require(first.currentSnapshot?.groups.isEmpty == true, "old mismatch survived invalidation")

        // Reusing a display owner for a different schedule must use a different
        // read-result key even in the same unchanged Space generation.
        let otherSchedule = Schedule(); otherSchedule.selectTargetType = .devices
        otherSchedule.nodeAddresses = [probe.primaryUnicastAddress]
        otherSchedule.syncRead = { _, _ in true }
        MeshNetworkManager.instance.schedules.append(otherSchedule)
        first.refresh(schedule: otherSchedule) { completed += 1 }
        await drain { completed == 4 }
        require(first.currentSnapshot?.nodes == [ObjectIdentifier(probe)], "new schedule reused old Bool/result")

        NodeSyncStatusGeneration.invalidate()
        second.refresh(schedule: schedule) { fatalError("closed picker received callback") }
        second.cancel()
        first.refresh(schedule: otherSchedule) { completed += 1 }
        await drain { completed == 5 }

        // Protection failure must not publish a clean plan.
        let request = SpaceConfigurationSafety.syncReadRequest(meshUUID: network.uuid.uuidString, networkId: "net")
        try! FileManager.default.createDirectory(at: request.root, withIntermediateDirectories: true)
        let file = request.root.appendingPathComponent(request.scope.storageKey + ".json")
        SpaceProtectionReadGeneration.beginMutation(); try! Data("broken".utf8).write(to: file); SpaceProtectionReadGeneration.endMutation()
        first.refresh(schedule: otherSchedule) { completed += 1 }
        await drain { completed == 6 }
        require(first.currentSnapshot == nil, "unavailable protection published synchronized targets")
        SpaceProtectionReadGeneration.beginMutation(); try! FileManager.default.removeItem(at: file); SpaceProtectionReadGeneration.endMutation()
        print("PASS: Timed target overlap, incoming/exiting/direct targets, sliced/shared reads, edit invalidation, replacement, cancellation and unavailable protection")
    }
}
