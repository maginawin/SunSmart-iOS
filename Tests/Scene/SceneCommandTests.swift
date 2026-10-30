import Foundation

@main struct SceneCommandTests {
    static func main() throws {
        try productionIdentityCase()
        let node = Node(1)
        node.lightnessModel = nil; node.effectiveSupportCct = false
        let scene = Scene(1)
        let manager = MeshNetworkManager.instance
        manager.realNodes = [node]; manager.scenes = [scene]
        let identity = node.timedSchedulerIdentity!
        scene.info.configuration = SceneConfiguration(kind: .devices, name: "Test",
            deviceMembers: [.init(identity: identity, parameters: .init(isOn: true, lightness: 0, cct: 0))],
            pendingOperations: [.init(identity: identity, action: .write)])
        let handles = scene.getSyncMessageHandles(node: node, data: .init(sceneNumber: 1, isOn: true, lightness: 0))
        guard (handles.first?.message as? GenericOnOffSet)?.isOn == true else {
            print("FAIL Relay ON must use isOn, not brightness"); exit(1)
        }
        let context = try SceneMessageContext(scene: scene, node: node, action: .write)
        guard context.matches(node: node) else { print("FAIL current owner rejected"); exit(1) }
        EmergencyFireControllerSceneEventManager.blocked = [ObjectIdentifier(node)]
        precondition(!context.matches(node: node) && !context.apply(node: node, successful: true), "EFC must reject direct Store result without clearing pending")
        precondition(scene.info.configuration!.pendingOperations.count == 1)
        precondition(scene.getSyncMessageHandles(node: node, data: .init(sceneNumber: 1)).isEmpty, "EFC must block ordinary Sync factory")
        let writeConfiguration = scene.info.configuration!
        scene.info.configuration!.deviceMembers = []
        scene.info.configuration!.pendingOperations = [.init(identity: identity, action: .remove)]
        precondition(!scene.getDeleteMessageHandles(node: node).isEmpty, "pure cleanup must remain permitted under EFC")
        scene.info.configuration = writeConfiguration
        EmergencyFireControllerSceneEventManager.blocked = []
        precondition(context.matches(node: node), "unblocked same intent can retry")
        scene.info.configuration!.revision = UUID()
        guard !context.matches(node: node) else { print("FAIL stale Store accepted new revision"); exit(1) }
        print("PASS revision ownership")
        precondition(node.getStandardNeedSync(), "ungrouped pending write must reach standard needSync")
        guard node.getNodeSyncSceneDatas().count == 1 else { print("FAIL ungrouped write missing"); exit(1) }
        node.sceneExecuteDatas = [.init(sceneNumber: 1, isOn: true, lightness: 0)]
        node.groupState = .exitFailure
        guard node.getNodeNeedDeleteSceneDatas().isEmpty else { print("FAIL group exit deletes device scene"); exit(1) }
        print("PASS ungrouped write and group exit")
        let second = Node(2); second.effectiveSupportCct = false
        manager.realNodes.append(second)
        scene.info.configuration!.deviceMembers.append(.init(identity: second.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 1200, cct: 0)))
        scene.info.configuration!.pendingOperations.append(.init(identity: second.timedSchedulerIdentity!, action: .write))
        let a = try SceneMessageContext(scene: scene, node: node, action: .write)
        let b = try SceneMessageContext(scene: scene, node: second, action: .write)
        let comparison = try SceneTargetResolver.resolve(scene: scene).comparison
        precondition(a.apply(node: node, successful: true))
        precondition(node.cacheClears > 0, "successful Store invalidates cached needSync")
        precondition(b.matches(node: second), "first success must not invalidate B")
        let after = try SceneTargetResolver.resolve(scene: scene).comparison
        precondition(after == comparison)
        TestPersistence.fail = true
        precondition(!b.apply(node: second, successful: true))
        precondition(scene.info.configuration!.pendingOperations.count == 1, "failed persistence keeps write")
        TestPersistence.fail = false
        precondition(!b.apply(node: second, successful: false), "failed Store keeps write")
        manager.currentNetworkKey.networkId = 2
        precondition(!b.matches(node: second), "Space switch")
        manager.currentNetworkKey.networkId = 1
        second.fingerprint = String(repeating: "B", count: 64)
        precondition(!b.matches(node: second), "reprovisioned address")
        second.fingerprint = String(repeating: "A", count: 64)
        scene.info.configuration!.deviceMembers.removeAll { $0.identity == second.timedSchedulerIdentity! }
        scene.info.configuration!.pendingOperations = [.init(identity: second.timedSchedulerIdentity!, action: .remove)]
        let removal = try SceneMessageContext(scene: scene, node: second, action: .remove)
        scene.info.configuration!.deviceMembers.append(.init(identity: second.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 800, cct: 0)))
        scene.info.configuration!.pendingOperations = [.init(identity: second.timedSchedulerIdentity!, action: .write)]
        precondition(!removal.apply(node: second, successful: true), "late Delete cannot remove readded member")
        let preview = SceneCommandBuilder.parameterHandles(node: second, parameters: .init(isOn: true, lightness: 1000, cct: 0))
        precondition(preview.count == 1 && !(preview[0].message is SceneStore))
        second.effectiveSupportCct = true
        let cct = SceneCommandBuilder.parameterHandles(node: second, parameters: .init(isOn: true, lightness: 1000, cct: 9000))
        precondition((cct[0].message as? LightCTLSet)?.temperature == 6500)
        let off = SceneCommandBuilder.parameterHandles(node: second, parameters: .init(isOn: false, lightness: 1000, cct: 5000))
        precondition((off[0].message as? GenericOnOffSet)?.isOn == false)
        let group = Group(); manager.groups = [group]; node.group = group; second.group = group
        let x = Node(3); x.group = group; manager.realNodes.append(x)
        let schedule = Schedule(1, scene: scene); manager.schedules = [schedule]
        let writes = SyncDevicesSectionModel(), removes = SyncDevicesSectionModel()
        SyncSceneScheduleTaskBuilder().appendScene(to: writes, removal: removes, scene: scene)
        precondition(writes.groups.count == 1 && writes.groups[0].deviceModels.count == 2,
            "A needs its Scheduler restored, B needs Store; unselected X stays excluded")
        let device = writes.groups[0].deviceModels[0]
        precondition(device.steps.count == 2 && device.steps[1].relevanceStepModels.first === device.steps[0])
        precondition(device.parentGroupModel === writes.groups[0])
        scene.info.configuration!.deviceMembers.removeAll { $0.identity == second.timedSchedulerIdentity! }
        scene.info.configuration!.pendingOperations = [.init(identity: second.timedSchedulerIdentity!, action: .remove)]
        let deletion = SyncDevicesSectionModel()
        SyncSceneScheduleTaskBuilder().appendScene(to: SyncDevicesSectionModel(), removal: deletion, scene: scene)
        let steps = deletion.groups[0].deviceModels[0].steps
        precondition(steps.count == 2 && steps[1].relevanceStepModels.first === steps[0])
        let groupScene = Scene(9)
        groupScene.info.configuration = .init(kind: .groups, name: "Legacy edited")
        group.info.sceneExecuteDatas.append(.init(sceneNumber: 9, isOn: true, lightness: 2000))
        manager.scenes.append(groupScene)
        node.sceneExecuteDatas.append(.init(sceneNumber: 9))
        node.groupState = .exitFailure
        precondition(node.getNodeNeedDeleteSceneDatas(scene: groupScene).count == 1,
            "explicit group scene must still be removed on group exit")
        groupScene.info.configuration!.pendingOperations = [.init(identity: node.timedSchedulerIdentity!, action: .write)]
        let beforeExit = groupScene.info.configuration!.pendingOperations[0].generation
        let deleteHandles = groupScene.getDeleteMessageHandles(node: node)
        precondition(deleteHandles.count == 1)
        precondition(groupScene.info.configuration!.pendingOperations[0].action == .remove,
            "group exit must durably replace pending write before sending Delete")
        precondition(groupScene.info.configuration!.pendingOperations[0].generation != beforeExit)
        node.groupState = .normal
        let readded = node.getNodeSyncSceneDatas(scene: groupScene)
        precondition(readded.count == 1, "readded group target must produce a new write")
        let writeHandles = groupScene.getSyncMessageHandles(node: node, data: readded[0].data)
        precondition(writeHandles.count == 2)
        let full = group.info.sceneExecuteDatas.first { $0.sceneNumber == 9 }!
        full.hue = 456; full.saturation = 789; full.lightControlData = 12
        let fullContext = try SceneMessageContext(scene: groupScene, node: node, action: .write)
        precondition(fullContext.target?.hue == 456 && fullContext.target?.saturation == 789 && fullContext.target?.lightControlData == 12,
            "legacy group auxiliary fields survive production deviceTarget")
        precondition(!deleteHandles[0].sceneContext!.matches(node: node))
        // Missing old identities remain pending even though no physical task can be built.
        scene.info.configuration!.deviceMembers = []
        scene.info.configuration!.pendingOperations = [.init(identity: second.timedSchedulerIdentity!, action: .remove)]
        manager.realNodes = []
        let absentWrites = SyncDevicesSectionModel(), absentRemovals = SyncDevicesSectionModel()
        SyncSceneScheduleTaskBuilder().appendScene(to: absentWrites, removal: absentRemovals, scene: scene)
        precondition(absentWrites.groups.isEmpty && absentWrites.devices.isEmpty
            && absentRemovals.groups.isEmpty && absentRemovals.devices.isEmpty)
        precondition(scene.needSync, "production Scene state must retain unresolved cleanup despite an empty plan")
        scene.info.configuration!.pendingOperations = []
        precondition(!scene.needSync, "genuinely empty scene may complete")
        print("PASS sync: command, ownership, persistence and production task dependencies")
    }

    static func productionIdentityCase() throws {
        let manager = MeshNetworkManager.instance
        let nodes = [Node(5), Node(8)], groups = [Group(0xC000), Group(0xC001)]
        let scene = Scene(13)
        manager.realNodes = nodes; manager.groups = groups; manager.scenes = [scene]
        for (node, group) in zip(nodes, groups) {
            node.group = group
            node.fingerprint = String(repeating: "ab", count: 32) // Production SHA256 hex is lowercase.
            group.info.sceneExecuteDatas = [.init(sceneNumber: 13, isOn: true, lightness: 2000)]
        }
        scene.info.configuration = try SceneConfiguration(kind: .groups, name: "Two groups",
            pendingOperations: nodes.map { .init(identity: $0.timedSchedulerIdentity!, action: .write) }).normalized()
        let pending = scene.info.configuration!.pendingOperations
        let snapshot = try SceneTargetResolver.resolve(scene: scene)
        precondition(snapshot.targets.count == 2)
        for node in nodes {
            let handles = scene.getSyncMessageHandles(node: node, data: .init(sceneNumber: 13))
            guard handles.count == 2, handles.last?.message is SceneStore else {
                print("FAIL lowercase production identity must generate parameters + SceneStore for both groups"); exit(1)
            }
            precondition(scene.info.configuration!.pendingOperations == pending, "retry must reuse pending generations")
            let context = handles.last!.sceneContext!
            precondition(context.matches(node: node))
            node.fingerprint = node.fingerprint.uppercased()
            precondition(context.matches(node: node), "hex case is not a provisioning change")
            node.fingerprint = String(repeating: "cd", count: 32)
            precondition(!context.matches(node: node), "different key must reject old owner")
            node.fingerprint = String(repeating: "ab", count: 32)
        }
        let node = nodes[0]
        scene.info.configuration = try SceneConfiguration(kind: .devices, name: "Removed",
            pendingOperations: [.init(identity: node.timedSchedulerIdentity!, action: .remove)]).normalized()
        groups.forEach { $0.info.sceneExecuteDatas = [] }
        precondition(node.getNodeNeedDeleteSceneDatas(scene: scene).count == 1, "lowercase device must retain durable delete task")
        let deletion = scene.getDeleteMessageHandles(node: node)
        precondition(deletion.count == 1 && deletion[0].message is SceneDelete)
        print("PASS production identity: two groups, pending reuse, case equivalence, changed-key rejection and delete discovery")
        manager.groups = []; manager.scenes = []; manager.realNodes = []
    }
}
