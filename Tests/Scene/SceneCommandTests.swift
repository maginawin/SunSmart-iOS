import Foundation

@main struct SceneCommandTests {
    static func main() throws {
        try plannedGroupSceneSafetyCase()
        try groupSyncProgressCase()
        try initializationProgressCase()
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
        precondition(node.getNodeSyncSceneDatas(scene: scene).count == 1,
            "EFC keeps the pending write visible to all sync entry points")
        precondition(scene.needSync && node.getStandardNeedSync(), "EFC must not turn pending work into success")
        let blockedWrites = SyncDevicesSectionModel(), blockedRemovals = SyncDevicesSectionModel()
        SyncSceneScheduleTaskBuilder().appendScene(to: blockedWrites, removal: blockedRemovals, scene: scene)
        precondition(blockedWrites.devices.count == 1, "blocked write remains a visible task")
        precondition(scene.info.configuration!.pendingOperations.count == 1)
        let writeConfiguration = scene.info.configuration!
        scene.info.configuration!.deviceMembers = []
        scene.info.configuration!.pendingOperations = [.init(identity: identity, action: .remove)]
        precondition(!scene.getDeleteMessageHandles(node: node).isEmpty, "pure cleanup must remain permitted under EFC")
        scene.info.configuration = writeConfiguration
        EmergencyFireControllerSceneEventManager.blocked = []
        precondition(context.matches(node: node), "unblocked same intent can retry")
        precondition(scene.getSyncMessageHandles(node: node, data: .init(sceneNumber: 1)).count == 2,
            "lifting EFC permits the original parameters and Store task")
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
        EmergencyFireControllerSceneEventManager.blocked = [ObjectIdentifier(node)]
        let groupDifference = node.getNodeSyncSceneDatas(scene: groupScene)
        precondition(groupDifference.count == 1 && groupDifference[0].data.hue == 456
            && groupDifference[0].data.lightControlData == 12, "blocked group diff preserves auxiliary fields")
        precondition(groupScene.needSync && groupScene.getSyncMessageHandles(node: node, data: full).isEmpty)
        EmergencyFireControllerSceneEventManager.blocked = []
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

    static func plannedGroupSceneSafetyCase() throws {
        let manager = MeshNetworkManager.instance
        let node = Node(10), group = Group(0xC015), otherGroup = Group(0xC016), scene = Scene(18)
        manager.realNodes = [node]; manager.groups = [group, otherGroup]; manager.scenes = [scene]; manager.schedules = []
        group.info.sceneExecuteDatas = [.init(sceneNumber: 18)]
        otherGroup.info.sceneExecuteDatas = [.init(sceneNumber: 18)]
        precondition(node.getNodeSyncSceneDatas(group: group).isEmpty, "a group argument alone does not authorize a pending member")
        node.restoreData = .init(addGroupAddress: 0xC015)
        let onOff = node.onoffModel
        node.onoffModel = nil
        guard node.getNodeSyncSceneDatas(group: group).isEmpty else { print("FAIL unsupported joining member gets a Scene write"); exit(1) }
        node.onoffModel = onOff
        node.group = otherGroup
        precondition(node.getNodeSyncSceneDatas(group: group).isEmpty, "another group's member is not an implicit join")
        node.group = nil
        scene.info.configuration = .init(kind: .groups, name: "Deleting", isDeleting: true)
        precondition(node.getNodeSyncSceneDatas(group: group).isEmpty, "joining must never revive a deleting Scene")
    }

    static func groupSyncProgressCase() throws {
        let manager = MeshNetworkManager.instance
        let nodes = [Node(0x49F9), Node(0x49FC)], group = Group(0xC015), scene = Scene(18)
        manager.realNodes = nodes; manager.groups = [group]; manager.scenes = [scene]; manager.schedules = []
        group.info.sceneExecuteDatas = [.init(sceneNumber: 18, lightness: 20000, cct: 4000)]
        nodes.forEach { $0.restoreData = .init(addGroupAddress: 0xC015) }
        let progress = SceneSyncProgress()
        let current = SceneCommandBuilder.captureConfigurations(progress: progress)
        let strict = SceneCommandBuilder.captureConfigurations()
        let transport = SceneProgressTransport()
        transport.configurationWillSend = { SpaceSyncTaskScope.expectSceneProgress($0, in: progress) }
        var receipts = 0
        func send(_ node: Node, message: Any, applying: @escaping () -> Void) {
            let oldReceipts = receipts
            transport.send = { handles, _, success, _, finished in
                DispatchQueue.main.async {
                    applying()
                    success?(handles[0], 0)
                    finished?(handles)
                }
            }
            transport.addMessage(messageHandles: [.init(message: message, address: node.primaryUnicastAddress)],
                                 successfulBack: { _, _ in
                guard current() else { print("FAIL own successful receipt invalidates the sync plan"); exit(1) }
                receipts += 1
            }, finishedBack: { _ in precondition(current()) })
            let deadline = Date().addingTimeInterval(2)
            while receipts == oldReceipts && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
            precondition(receipts == oldReceipts + 1, "asynchronous callback must be delivered")
        }
        precondition(current())
        nodes[1].restoreData?.addGroupAddress = 0xC016
        guard !current() else { print("FAIL changed pending membership accepted before that node starts"); exit(1) }
        nodes[1].restoreData?.addGroupAddress = 0xC015
        nodes[1].group = group
        precondition(!current(), "a member change without a submitted command must invalidate")
        nodes[1].group = nil
        for node in nodes {
            let tasks = node.getNodeSyncSceneDatas(group: group)
            precondition(tasks.count == 1 && tasks[0].scene === scene,
                         "first plan must include the joining member's Scene before subscription")
            precondition(scene.getSyncMessageHandles(node: node, data: tasks[0].data).isEmpty,
                         "planning a future member must not authorize an early Scene send")
            send(node, message: ConfigModelSubscriptionAdd(address: 0xC015)) {
                node.group = group
                node.restoreData?.addGroupAddress = nil
            }
            guard current() else { print("FAIL own successful group subscription invalidates the sync plan"); exit(1) }
            precondition(!strict(), "other Scene callers retain strict topology ownership")
            send(node, message: LightLightnessRangeSet(range: 655...65535)) { node.lightnessRange = 655...65535 }
            guard current() else { print("FAIL own successful range write invalidates the sync plan"); exit(1) }
            let handles = scene.getSyncMessageHandles(node: node, data: tasks[0].data)
            precondition(handles.count == 2 && handles.last?.message is SceneStore,
                         "Scene executes after the member joins without rebuilding")
            precondition(handles.last!.sceneContext!.matches(node: node))
            precondition(handles.last!.sceneContext!.apply(node: node, successful: true))
            precondition(current(), "Scene receipt progress keeps the same plan")
        }
        precondition(nodes.allSatisfy { $0.getNodeSyncSceneDatas(group: group).isEmpty },
                     "successful Scene writes are not rebuilt on retry")
        precondition(receipts == 4)
        let node = nodes[0]
        node.lightnessRange = 656...65535
        precondition(!current(), "a range response differing from the submitted value must invalidate")
        node.lightnessRange = 655...65535
        node.lightnessRange = 0...65535
        precondition(!current(), "completed range must not regress to the old value")
        node.lightnessRange = 655...65535
        node.effectiveCctRange = 3000...6000
        precondition(!current(), "unplanned capability change stays protected")
        node.effectiveCctRange = 2700...6500
        node.fingerprint = String(repeating: "B", count: 64)
        precondition(!current(), "same address with a new identity stays protected")
        node.fingerprint = String(repeating: "A", count: 64)
        node.group = nil
        precondition(!current(), "unplanned membership removal stays protected")
        node.group = group
        group.info.sceneExecuteDatas[0].lightness = 30000
        precondition(!current(), "real desired Scene edits must still invalidate")
        group.info.sceneExecuteDatas[0].lightness = 20000
        precondition(current())

        nodes.forEach { $0.groupState = .exitFailure }
        let exitingProgress = SceneSyncProgress()
        let exiting = SceneCommandBuilder.captureConfigurations(progress: exitingProgress)
        for node in nodes {
            precondition(node.getNodeSyncSceneDatas(group: group).isEmpty)
            exitingProgress.expect(node: node, change: .subscription(group, adding: false))
            node.group = nil
            precondition(exiting())
            node.groupState = .normal
            precondition(exiting(), "final unsubscribe completes exit intent")
        }
        print("PASS two-member Scene plan: expected progress, initial tasks, strict external edits and exit completion")
    }

    static func initializationProgressCase() throws {
        let manager = MeshNetworkManager.instance
        func missingComposition(_ node: Node) {
            node.isCompositionDataReceived = false
            node.sceneSetupModel = nil; node.onoffModel = nil; node.lightnessModel = nil
            node.effectiveSupportCct = false
        }
        func receiveComposition(_ node: Node) {
            // SDK applies Page 0 before delivering the transport callback.
            node.isCompositionDataReceived = true
            node.sceneSetupModel = Model(); node.onoffModel = Model(); node.lightnessModel = Model()
            node.effectiveSupportCct = true
            node.effectiveCctRange = 2200...7000
        }
        for mode in 0...3 {
            let node = Node(1), other = Node(2), group = Group(0xC010), scene = Scene(12)
            manager.realNodes = [node, other]; manager.groups = [group]; manager.scenes = []; manager.schedules = []
            missingComposition(node)
            if mode == 1 { manager.scenes = [scene] } // Existing but unrelated Scene.
            if mode == 2 {
                manager.scenes = [scene]; node.group = group
                group.info.sceneExecuteDatas = [.init(sceneNumber: scene.number, lightness: 20000)]
            }
            if mode == 3 {
                // A restored company identifier alone does not mean Models are available.
                node.isCompositionDataReceived = true
                manager.scenes = [scene]
                scene.info.configuration = .init(kind: .devices, name: "Initializing",
                    deviceMembers: [.init(identity: node.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 20000, cct: 4000))])
            }
            let progress = SceneSyncProgress()
            let current = SceneCommandBuilder.captureConfigurations(progress: progress)
            let strict = SceneCommandBuilder.captureConfigurations()
            let transport = SceneProgressTransport()
            transport.configurationWillSend = { SpaceSyncTaskScope.expectSceneProgress($0, in: progress) }
            let request = MeshMessageHandle(message: ConfigCompositionDataGet(), address: node.primaryUnicastAddress)
            precondition(current())
            // A timeout with no SDK update must leave the plan retryable.
            transport.send = { handles, _, _, failure, finished in
                failure?(handles[0]); finished?(handles)
            }
            transport.addMessage(messageHandles: [request], failedBack: { _ in precondition(current()) },
                                 finishedBack: { _ in precondition(current()) })
            var completed = false
            var followUpSent = false
            transport.send = { handles, _, success, _, finished in
                DispatchQueue.main.async {
                    receiveComposition(node)
                    success?(handles[0], 0)
                    finished?(handles)
                }
            }
            transport.addMessage(messageHandles: [request], successfulBack: { _, _ in
                guard current() else { print("FAIL Composition Data callback invalidates initialization, mode=\(mode)"); exit(1) }
                // Initialization can enqueue its next configuration batch in this callback.
                transport.send = { _, _, _, _, finished in followUpSent = true; finished?([]) }
                transport.addMessage(messageHandles: [], finishedBack: nil)
            }, finishedBack: { _ in precondition(current()); completed = true })
            let deadline = Date().addingTimeInterval(2)
            while !completed && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.001)) }
            precondition(completed && followUpSent, "initialization must reach follow-up configuration")
            if mode >= 2 { precondition(!strict(), "non-sync callers keep strict Scene capability snapshots") }
            // Another Get must not authorize changing already known capabilities.
            SpaceSyncTaskScope.expectSceneProgress([request], in: progress)
            node.onoffModel = nil
            precondition(!current(), "accepted capabilities cannot change again")
            node.onoffModel = Model()
            node.effectiveCctRange = 2700...6500
            precondition(!current(), "accepted product CCT range cannot roll back")
            node.effectiveCctRange = 2200...7000
            node.isCompositionDataReceived = false
            precondition(!current(), "composition completion cannot roll back")
            node.isCompositionDataReceived = true
            precondition(current())
        }

        let node = Node(1), other = Node(2), group = Group(0xC010), scene = Scene(12)
        manager.realNodes = [node, other]; manager.groups = [group]; manager.scenes = [scene]
        node.group = group; group.info.sceneExecuteDatas = [.init(sceneNumber: 12, lightness: 20000)]
        missingComposition(node); missingComposition(other)
        let progress = SceneSyncProgress()
        let current = SceneCommandBuilder.captureConfigurations(progress: progress)
        let request = MeshMessageHandle(message: ConfigCompositionDataGet(), address: node.primaryUnicastAddress)
        SpaceSyncTaskScope.expectSceneProgress([.init(message: ConfigCompositionDataGet(page: 1), address: node.primaryUnicastAddress)], in: progress)
        receiveComposition(node)
        precondition(!current(), "non-Page-0 requests cannot authorize model changes")
        missingComposition(node)
        SpaceSyncTaskScope.expectSceneProgress([request], in: progress)
        node.onoffModel = Model()
        precondition(!current(), "capability changes before completed composition stay protected")
        node.onoffModel = nil
        receiveComposition(other)
        precondition(!current(), "a request for one node cannot authorize another")
        missingComposition(other); other.effectiveCctRange = 2700...6500
        let restarted = SceneCommandBuilder.captureConfigurations(progress: SceneSyncProgress())
        receiveComposition(node)
        precondition(!restarted(), "a replacement plan cannot inherit an old request or late response")
        node.fingerprint = String(repeating: "B", count: 64)
        precondition(!current(), "initialization must not authorize identity replacement")
        node.fingerprint = String(repeating: "A", count: 64)
        let network = node.network
        node.network = Network()
        precondition(!current(), "initialization must not authorize network replacement")
        node.network = network
        node.subNetworkId = "0002"
        precondition(!current(), "initialization must not authorize Space changes")
        node.subNetworkId = "0001"
        node.group = nil
        precondition(!current(), "initialization must not authorize membership changes")
        node.group = group
        node.lightnessRange = 655...65535
        precondition(!current(), "Composition Data does not authorize lightness trim changes")
        node.lightnessRange = 0...65535
        group.info.sceneExecuteDatas[0].lightness = 30000
        precondition(!current(), "desired Scene edits stay strict during initialization")
        group.info.sceneExecuteDatas[0].lightness = 20000
        precondition(current())
        print("PASS initialization progress: empty/unrelated/group/device Scenes, retry, asynchronous follow-up and strict mutation boundaries")
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
