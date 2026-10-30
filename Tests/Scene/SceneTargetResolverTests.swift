import Foundation

@main struct SceneTargetResolverTests {
    static func main() throws {
        var passed = 0, failed = 0
        func test(_ name: String, _ body: () throws -> Bool) {
            do { if try body() { passed += 1 } else { failed += 1; print("FAIL targets: \(name)") } }
            catch { failed += 1; print("FAIL targets: \(name): \(error)") }
        }
        func rejects(_ body: () throws -> Void) -> Bool { do { try body(); return false } catch { return true } }
        let manager = MeshNetworkManager.instance
        let a = Node(1), b = Node(2), x = Node(3), u = Node(4)
        let g1 = Group(0xC001), g2 = Group(0xC002)
        manager.realNodes = [a, b, x, u]; manager.groups = [g1, g2]
        a.group = g1; b.group = g1; x.group = g1
        let on = SceneParameters(isOn: true, lightness: 20000, cct: 4500)
        let off = SceneParameters(isOn: false, lightness: 50000, cct: 3000)
        let scene = Scene(1)
        scene.info.configuration = .init(kind: .devices, name: "Evening", deviceMembers: [
            .init(identity: a.timedSchedulerIdentity!, parameters: on),
            .init(identity: b.timedSchedulerIdentity!, parameters: off),
            .init(identity: u.timedSchedulerIdentity!, parameters: on)])
        manager.scenes = [scene]
        let expected = Set([a.uuid, b.uuid, u.uuid])
        test("deviceTargetsIgnoreGroupChanges") {
            let before = try SceneTargetResolver.resolve(scene: scene)
            a.group = g2; b.group = nil; b.groupState = .exitFailure; x.group = g2
            let after = try SceneTargetResolver.resolve(scene: scene)
            return Set(before.targets.map { $0.node.uuid }) == expected
                && Set(after.targets.map { $0.node.uuid }) == expected && before.comparison == after.comparison
        }
        test("offlineExistingTargetsStayResolved") {
            a.state = false; defer { a.state = true }
            return try SceneTargetResolver.resolve(scene: scene).targets.contains { $0.node === a }
        }
        test("reusedAddressCannotInheritMembership") {
            a.fingerprint = String(repeating: "B", count: 64)
            defer { a.fingerprint = String(repeating: "A", count: 64) }
            let snapshot = try SceneTargetResolver.resolve(scene: scene)
            return !snapshot.targets.contains { $0.node === a } && snapshot.unresolved.count == 1
        }
        test("emptyGroupIsConfiguredButTrulyEmptySceneIsNot") {
            let groupScene = Scene(2)
            g1.info.sceneExecuteDatas = [.init(sceneNumber: 2)]; x.group = g2
            defer { g1.info.sceneExecuteDatas = [] }
            let bound = try SceneTargetResolver.resolve(scene: groupScene)
            let empty = try SceneTargetResolver.resolve(scene: Scene(3))
            return bound.targets.isEmpty && bound.hasConfiguredMembers && !empty.hasConfiguredMembers
        }
        test("cleanupSurvivesGroupChangesAndMissingNodes") {
            let cleanup = Scene(3)
            cleanup.info.configuration = .init(kind: .devices, name: "Cleanup", pendingOperations: [.init(identity: a.timedSchedulerIdentity!, action: .remove)])
            let before = try SceneTargetResolver.resolve(scene: cleanup)
            manager.realNodes.removeAll { $0 === a }; defer { manager.realNodes.append(a) }
            let after = try SceneTargetResolver.resolve(scene: cleanup)
            return before.cleanupTargets.count == 1 && after.unresolved.contains { $0.action == .remove }
                && !after.hasConfiguredMembers
        }
        test("progressDoesNotInvalidateRemainingTargetComparison") {
            scene.info.configuration!.pendingOperations = [.init(identity: a.timedSchedulerIdentity!, action: .write)]
            let before = try SceneTargetResolver.resolve(scene: scene)
            scene.info.configuration!.pendingOperations = []
            return try before.comparison == SceneTargetResolver.resolve(scene: scene).comparison
        }
        test("corruptionAndModeConflictAreRejected") {
            let invalid = Scene(9); invalid.info.loadConfiguration(Data("{}".utf8))
            let corrupt = rejects { _ = try SceneTargetResolver.resolve(scene: invalid) }
            g1.info.sceneExecuteDatas = [.init(sceneNumber: 1)]; defer { g1.info.sceneExecuteDatas = [] }
            return corrupt && rejects { _ = try SceneTargetResolver.resolve(scene: scene) }
        }
        test("scopeMismatchIsRejected") {
            scene.subNetworkId = "other"; defer { scene.subNetworkId = "0001" }
            return rejects { _ = try SceneTargetResolver.resolve(scene: scene) }
        }
        test("deviceSceneScheduleSurvivesGroupExit") {
            let schedule = Schedule(20, scene: scene)
            return schedule.targets(node: b) && schedule.targets(node: u) && !schedule.targets(node: x)
        }
        test("scheduleExistNodesIncludesDirectAndCleanupTargets") {
            let schedule = Schedule(20, scene: scene)
            return Set(schedule.existNodes.map(\.uuid)) == expected
        }
        test("sameNumberOfflineEditDoesNotRequireSceneRead") {
            a.state = false; a.sceneSetupModel?.parentElement?.observedSceneRegister = nil
            defer { a.state = true }
            return SceneCapacity.intendedScenes(on: a) == [1]
                && SceneCapacity.nodesRequiringRead(scene: scene, sceneGroups: []).isEmpty
        }
        test("pendingCleanupStillReservesCapacity") {
            let cleanup = Scene(3)
            cleanup.info.configuration = .init(kind: .devices, name: "Cleanup", pendingOperations: [.init(identity: a.timedSchedulerIdentity!, action: .remove)])
            manager.scenes.append(cleanup); defer { manager.scenes.removeLast() }
            return SceneCapacity.intendedScenes(on: a) == [1, 3]
        }
        test("topologyProjectionKeepsDeviceSceneTimedOwner") {
            let schedule = Schedule(20, scene: scene)
            schedule.nodeSlots = [a, b, u].map { .init(identity: $0.timedSchedulerIdentity!, slot: 0, state: .assigned) }
            manager.schedules = [schedule]; defer { manager.schedules = [] }
            a.observedTimedSlots = nil; b.observedTimedSlots = nil; u.observedTimedSlots = nil
            let plan = try TimedSchedulerBindings.prepareTopology(group: g2, members: [x])
            return plan.bindings[20]?.count == 3 && plan.bindings[20]?.allSatisfy { $0.state == .assigned } == true
        }
        let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
        test("draftRejectsOfflineAdditionButAllowsExistingOfflineEdit") {
            a.state = false; x.state = false; defer { a.state = true; x.state = true }
            let draft = try SceneDraft(number: 1, scope: scope, name: "edit", imageId: 0, kind: .devices,
                deviceMembers: scene.info.configuration!.deviceMembers + [.init(identity: x.timedSchedulerIdentity!, parameters: on)], sourceConfiguration: scene.info.configuration)
            let snapshot = try SceneTargetResolver.resolve(draft: draft)
            return snapshot.targets.contains { $0.node === a } && snapshot.unresolved.contains { $0.identity == x.timedSchedulerIdentity && $0.reason == .offlineAddition }
        }
        test("newUnknownSceneCapacityCannotBecomeEmpty") {
            let draft = try SceneDraft(scope: scope, name: "new", imageId: 0, kind: .devices,
                deviceMembers: [.init(identity: a.timedSchedulerIdentity!, parameters: on)])
            let snapshot = try SceneTargetResolver.resolve(draft: draft)
            return SceneCapacity.nodesRequiringRead(sceneSnapshot: snapshot) == [a]
                && rejects { try SceneCapacity.validateTopology(sceneSnapshot: snapshot) }
        }
        test("pendingCleanupDoesNotFreeTheSixteenthSlot") {
            let savedScenes = manager.scenes
            defer { manager.scenes = savedScenes }
            manager.scenes = (1...16).map { number in
                let item = Scene(UInt16(number))
                item.info.configuration = .init(kind: .devices, name: "Pending", pendingOperations: [.init(identity: a.timedSchedulerIdentity!, action: .remove)])
                return item
            }
            a.sceneSetupModel?.parentElement?.observedSceneRegister = []
            let draft = try SceneDraft(scope: scope, name: "new", imageId: 0, kind: .devices,
                deviceMembers: [.init(identity: a.timedSchedulerIdentity!, parameters: on)])
            return rejects { try SceneCapacity.validateTopology(sceneSnapshot: SceneTargetResolver.resolve(draft: draft)) }
        }
        test("parametersUseDeviceCapabilitiesWithoutChangingDraft") {
            a.lightnessRange = 1000...18000; a.effectiveCctRange = 2700...4000
            b.lightnessModel = nil; b.effectiveSupportCct = false
            defer { a.lightnessRange = 0...65535; a.effectiveCctRange = 2700...6500; b.lightnessModel = Model(); b.effectiveSupportCct = true }
            var relayOn = on; relayOn.lightness = 0
            let draft = try SceneDraft(scope: scope, name: "params", imageId: 0, kind: .devices, deviceMembers: [
                .init(identity: a.timedSchedulerIdentity!, parameters: on), .init(identity: b.timedSchedulerIdentity!, parameters: relayOn)])
            let result = try SceneTargetResolver.resolve(draft: draft)
            let first = result.targets.first { $0.node === a }!, relay = result.targets.first { $0.node === b }!
            return first.parameters.lightness == 18000 && first.parameters.cct == 4000
                && relay.parameters.isOn && relay.parameters.cct == 0 && relay.parameters.lightness == 0
                && draft.deviceMembers.first { $0.identity == a.timedSchedulerIdentity }!.parameters == on
        }
        test("noSchedulerCapabilityDoesNotAllocateFictionalSlot") {
            let schedule = Schedule(21, scene: scene)
            manager.schedules = [schedule]; defer { manager.schedules = [] }
            a.schedulerSetupModels = []; b.schedulerSetupModels = []; u.schedulerSetupModels = []
            defer { a.schedulerSetupModels = [Model()]; b.schedulerSetupModels = [Model()]; u.schedulerSetupModels = [Model()] }
            return try TimedSchedulerBindings.prepareTopology().bindings[21] == []
        }
        test("newTimedTargetRequiresKnownCapacity") {
            let schedule = Schedule(22, scene: scene)
            manager.schedules = [schedule]; defer { manager.schedules = [] }
            return rejects { _ = try TimedSchedulerBindings.prepareTopology() }
        }
        test("draftMemberRemovalKeepsOnlyRemainingTimedTargets") {
            let schedule = Schedule(23, scene: scene)
            schedule.nodeSlots = [a, b, u].map { .init(identity: $0.timedSchedulerIdentity!, slot: 0, state: .assigned) }
            manager.schedules = [schedule]; defer { manager.schedules = [] }
            let draft = try SceneDraft(number: 1, scope: scope, name: "edit", imageId: 0, kind: .devices,
                deviceMembers: scene.info.configuration!.deviceMembers.filter { $0.identity == b.timedSchedulerIdentity }, sourceConfiguration: scene.info.configuration)
            let plan = try TimedSchedulerBindings.prepareTopology(sceneSnapshot: SceneTargetResolver.resolve(draft: draft))
            let kept = plan.bindings[23]!.filter { $0.state == .assigned }
            return kept.count == 1 && kept.first?.identity == b.timedSchedulerIdentity
                && plan.bindings[23]!.filter { $0.state == .pendingRemoval }.count == 2
        }
        test("schedulerReadIsOnlyForNewOccupancy") {
            let schedule = Schedule(24, scene: scene)
            schedule.nodeSlots = [a, b, u].map { .init(identity: $0.timedSchedulerIdentity!, slot: 0, state: .assigned) }
            manager.schedules = [schedule]; defer { manager.schedules = [] }
            x.observedTimedSlots = nil; defer { x.observedTimedSlots = [] }
            let existing = try SceneTargetResolver.resolve(scene: scene)
            let same = try TimedSchedulerBindings.nodesRequiringTopologyRead(sceneSnapshot: existing)
            let draft = try SceneDraft(number: 1, scope: scope, name: "edit", imageId: 0, kind: .devices,
                deviceMembers: scene.info.configuration!.deviceMembers + [.init(identity: x.timedSchedulerIdentity!, parameters: on)], sourceConfiguration: scene.info.configuration)
            let added = try TimedSchedulerBindings.nodesRequiringTopologyRead(sceneSnapshot: SceneTargetResolver.resolve(draft: draft))
            return same.isEmpty && added == [x]
        }
        test("staleIdentityOrScopeRejectsCapturedCapacitySnapshot") {
            let draft = try SceneDraft(scope: scope, name: "new", imageId: 0, kind: .devices,
                deviceMembers: [.init(identity: a.timedSchedulerIdentity!, parameters: on)])
            let snapshot = try SceneTargetResolver.resolve(draft: draft)
            a.fingerprint = String(repeating: "B", count: 64)
            let identityRejected = rejects { try SceneCapacity.validateTopology(sceneSnapshot: snapshot) }
            a.fingerprint = String(repeating: "A", count: 64)
            manager.currentNetworkKey.networkId = 2
            defer { manager.currentNetworkKey.networkId = 1 }
            return identityRejected && rejects { try SceneCapacity.validateTopology(sceneSnapshot: snapshot) }
        }
        test("deletingSceneHasNoWriteTargetsAndKeepsCleanup") {
            let deleting = Scene(25)
            deleting.info.configuration = .init(kind: .devices, name: "Deleting", deviceMembers: scene.info.configuration!.deviceMembers,
                pendingOperations: scene.info.configuration!.deviceMembers.map { .init(identity: $0.identity, action: .remove) }, isDeleting: true)
            let snapshot = try SceneTargetResolver.resolve(scene: deleting)
            return snapshot.targets.isEmpty && snapshot.cleanupTargets.count == 3
        }
        test("existingOfflineGroupDraftRetainsTargetsAndCanValidate") {
            let groupScene = Scene(30)
            a.group = g1; a.state = false
            g1.info.sceneExecuteDatas = [.init(sceneNumber: 30, lightness: 20000)]
            defer { a.state = true; g1.info.sceneExecuteDatas = [] }
            let draft = try SceneDraft(number: 30, scope: scope, name: "group", imageId: 0, kind: .groups,
                groupParameters: [g1.address.address: on])
            let snapshot = try SceneTargetResolver.resolve(draft: draft)
            try SceneCapacity.validateTopology(scene: groupScene, sceneGroups: [g1], sceneSnapshot: snapshot)
            return snapshot.targets.contains { $0.node === a } && snapshot.unresolved.isEmpty
        }
        test("legacyGroupUsesExistingDeviceTargetTrimSemantics") {
            a.group = g1; a.lightnessRange = 1000...18000
            let data = SceneExecuteData(sceneNumber: 31, lightness: 65535)
            g1.info.sceneExecuteDatas = [data]
            defer { a.lightnessRange = 0...65535; g1.info.sceneExecuteDatas = [] }
            let snapshot = try SceneTargetResolver.resolve(scene: Scene(31))
            return snapshot.targets.first { $0.node === a }?.parameters.lightness == 65535
                && data.lightness == 65535
        }
        test("legacyPendingRemovalReservesSceneCapacity") {
            a.group = g1
            let data = SceneExecuteData(sceneNumber: 32); data.state = .waitDelete
            g1.info.sceneExecuteDatas = [data]
            defer { g1.info.sceneExecuteDatas = [] }
            return SceneCapacity.intendedScenes(on: a).contains(32)
        }
        test("deletingGroupSceneDeduplicatesCleanupWithoutParameters") {
            a.group = g1
            g1.info.sceneExecuteDatas = [.init(sceneNumber: 33)]
            defer { g1.info.sceneExecuteDatas = [] }
            let deleting = Scene(33)
            deleting.info.configuration = .init(kind: .groups, name: "Deleting", pendingOperations: [.init(identity: a.timedSchedulerIdentity!, action: .remove)], isDeleting: true)
            let result = try SceneTargetResolver.resolve(scene: deleting)
            return result.targets.isEmpty && result.cleanupTargets.count == 1 && result.cleanupTargets.first?.node === a
        }
        test("legacyCleanupSurvivesDraftAndPreventsConversion") {
            a.group = g1
            let data = SceneExecuteData(sceneNumber: 34); data.state = .waitDelete
            g1.info.sceneExecuteDatas = [data]
            defer { g1.info.sceneExecuteDatas = [] }
            var draft = try SceneDraft(scene: Scene(34))
            a.group = nil
            let snapshot = try SceneTargetResolver.resolve(draft: draft)
            return snapshot.cleanupTargets.count == 1 && snapshot.cleanupTargets.first?.node === a
                && rejects { try draft.switchKind(to: .devices) }
        }
        print("targets: \(passed) passed, \(failed) failed")
        if failed > 0 { exit(1) }
    }
}
