import Foundation
import SQLite

func tryValue<T>(_ value: () throws -> T) -> T { try! value() }

@main struct SceneSaveFlowTests {
    static func main() throws {
        SunSmartDataManager.shared.db = try Connection(CommandLine.arguments[1])
        let manager = MeshNetworkManager.instance
        let group = Group(); manager.groups = [group]
        let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
        let draft = try SceneDraft(scope: scope, name: "Empty group", imageId: 2, kind: .groups,
            groupParameters: [group.address.address: .init(isOn: true, lightness: 12000, cct: 4000)])
        let store = SceneConfigurationStore()
        let backgroundFinished = DispatchSemaphore(value: 0)
        DispatchQueue.global().async {
            do { try SceneConfigurationStore.validateAccess(scope); fatalError("background must not use DB-only authorization") } catch {}
            backgroundFinished.signal()
        }
        backgroundFinished.wait()
        let authority = SpaceData.value
        authority.permission = .editor
        checkAuthority: do {
            let payload: [String: Any] = ["uuid": authority.id, "role": "editor", "userEvents": ["EditorPasswdChanged"], "spaceData": ["sceneConfigurations": "broken"]]
            precondition(authority.applyRemoteSpaceAuthorityRestrictions(payload))
            precondition(authority.requiresPasswordVerification && SpaceConfigurationSafety.recovery.authority == .waitingForAuthorization)
            do { _ = try store.commit(draft: draft, expectedRevision: draft.revision); fatalError("revoked editor confirmation committed a scene") } catch {}
            precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).isEmpty })
            authority.requiresPasswordVerification = false
            do { try SceneConfigurationStore.validateAccess(scope); fatalError("waiting authority accepted") } catch {}
            SpaceConfigurationSafety.recovery.authority = .writable
            let active = SpaceData(); SpaceViewController.active = active
            for mode in 0..<3 {
                active.disableEditorPermission = mode == 0; active.meshOTADistribution = mode == 1
                SpaceMembershipCoordinator.allowed = mode != 2
                do { try SceneConfigurationStore.validateAccess(scope); fatalError("transient edit/OTA/leaving restriction ignored") } catch {}
            }
            SpaceMembershipCoordinator.allowed = true; SpaceViewController.active = nil
            try SceneConfigurationStore.validateAccess(scope)
            authority.permission = .owner
        }

        do {
            let result = try store.commit(draft: draft, expectedRevision: draft.revision)
            guard case .ready(let scene) = result, scene.number == 1 else { fatalError("empty group must commit") }
        } catch { print("FAIL legal empty group cannot commit: \(error)"); exit(1) }
        let first = manager.scenes[0]
        var empty = try SceneDraft(scene: first)
        try empty.setGroupParameters([:])
        do { _ = try store.commit(draft: empty, expectedRevision: empty.revision) }
        catch { print("FAIL existing scene must allow removing last member"); exit(1) }
        // Restore a group for subsequent transaction cases.
        var rebound = try SceneDraft(scene: first)
        try rebound.setGroupParameters([group.address.address: .init(isOn: true, lightness: 12000, cct: 4000)])
        _ = try store.commit(draft: rebound, expectedRevision: rebound.revision)
        let legacy = group.info.sceneExecuteDatas.first { $0.sceneNumber == first.number }!
        legacy.hue = 99; legacy.saturation = 88; legacy.lightControlData = 7
        var auxiliaryEdit = try SceneDraft(scene: first)
        auxiliaryEdit.setMetadata(name: "Auxiliary", imageId: 2)
        legacy.hue = 100
        do { _ = try store.commit(draft: auxiliaryEdit, expectedRevision: auxiliaryEdit.revision); fatalError("changed original HSL must invalidate draft") }
        catch SceneConfigurationStore.Failure.staleDraft {}
        var edit = try SceneDraft(scene: first)
        edit.setMetadata(name: "New name", imageId: 3)
        first.info.configuration!.revision = UUID()
        do { _ = try store.commit(draft: edit, expectedRevision: edit.revision); fatalError("stale source accepted") }
        catch SceneConfigurationStore.Failure.staleDraft {}
        let pendingDraft = try SceneDraft(scope: scope, name: "Pending", imageId: 0, kind: .groups,
            groupParameters: [group.address.address: .init(isOn: false, lightness: 1000, cct: 3500)])
        Scene.sdkSaveFails = true
        let pending = try store.commit(draft: pendingDraft, expectedRevision: pendingDraft.revision)
        guard case .projectionPending(let number) = pending else { fatalError("projection failure was not distinguished") }
        precondition(number == 2)
        let reserved = try store.nextAvailableNumber(); precondition(reserved == 3)
        manager.scenes = []; Scene.diskNumbers = []
        SunSmartDataManager.shared.db = try Connection(CommandLine.arguments[1])
        let restarted = SceneConfigurationStore()
        precondition(tryValue { try restarted.nextAvailableNumber() } == 3, "App row reserves pending number after restart")
        _ = try restarted.commit(draft: pendingDraft, expectedRevision: pendingDraft.revision)
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == 2)
        Scene.sdkSaveFails = false
        try restarted.restoreSceneProjections()
        precondition(manager.scenes.count == 2)
        let resumed = try restarted.commit(draft: pendingDraft, expectedRevision: pendingDraft.revision)
        guard case .ready(let recovered) = resumed else { fatalError("retry must repair original") }
        precondition(recovered.number == 2)
        let db = SunSmartDataManager.shared.db!
        try db.run("CREATE TRIGGER reject_scene BEFORE INSERT ON sceneInfos BEGIN SELECT RAISE(ABORT, 'injected'); END")
        let failDraft = try SceneDraft(scope: scope, name: "Failure", imageId: 0, kind: .groups,
            groupParameters: [group.address.address: .init(isOn: true, lightness: 500, cct: 4000)])
        let oldGroups = group.info.sceneExecuteDatas.map(\.sceneNumber)
        do { _ = try restarted.commit(draft: failDraft, expectedRevision: failDraft.revision); fatalError("App failure accepted") }
        catch {}
        precondition(group.info.sceneExecuteDatas.map(\.sceneNumber) == oldGroups)
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == 2)
        try db.run("DROP TRIGGER reject_scene")
        GroupInfo.savingSucceeds = false
        do { _ = try restarted.commit(draft: failDraft, expectedRevision: failDraft.revision); fatalError("Group save failure accepted") } catch {}
        GroupInfo.savingSucceeds = true
        precondition(group.info.sceneExecuteDatas.map(\.sceneNumber) == oldGroups)
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == 2)
        // Same-Mesh, other-Space tombstones also reserve their numbers.
        let tombstone = SceneInfo(sceneId: 3)
        tombstone.configuration = .init(kind: .devices, name: "Deleted", isDeleting: true)
        try tombstone.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: "other")
        precondition(tryValue { try restarted.nextAvailableNumber() } == 4)
        let zero = SceneInfo(sceneId: 0)
        do { try zero.saveConfiguration(); fatalError("zero persisted") } catch {}
        let lamp = Node(10); manager.realNodes = [lamp]
        lamp.sceneSetupModel!.parentElement!.observedSceneRegister = []
        let member = SceneDeviceMember(identity: lamp.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 1234, cct: 4000))
        let deviceDraft = try SceneDraft(scope: scope, name: "Offline", imageId: 0, kind: .devices, deviceMembers: [member])
        guard case .ready(let deviceScene) = try restarted.commit(draft: deviceDraft, expectedRevision: deviceDraft.revision) else { fatalError() }
        lamp.state = false
        var offline = try SceneDraft(scene: deviceScene)
        try offline.setDeviceMembers([.init(identity: member.identity, parameters: .init(isOn: false, lightness: 0, cct: 5000))])
        _ = try restarted.commit(draft: offline, expectedRevision: offline.revision)
        precondition(deviceScene.info.configuration!.deviceMembers[0].parameters.isOn == false)
        precondition(deviceScene.info.configuration!.pendingOperations.count == 1)
        let beforeMetadata = deviceScene.info.configuration!
        var metadata = try restarted.editingDraft(for: deviceScene)
        metadata.setMetadata(name: "Only name", imageId: 4)
        _ = try restarted.commitMetadata(draft: metadata, expectedRevision: metadata.revision)
        precondition(deviceScene.info.configuration!.deviceMembers == beforeMetadata.deviceMembers,
            "metadata save must preserve direct members and parameters")
        precondition(deviceScene.info.configuration!.pendingOperations == beforeMetadata.pendingOperations,
            "metadata save must preserve pending operation generation")
        var changedMembers = try restarted.editingDraft(for: deviceScene)
        try changedMembers.setDeviceMembers([])
        do { _ = try restarted.commitMetadata(draft: changedMembers, expectedRevision: changedMembers.revision); fatalError("metadata entry changed membership") }
        catch SceneConfigurationStore.Failure.invalidTargets {}
        let protectedMetadata = try restarted.editingDraft(for: deviceScene)
        SpaceData.value.permission = .viewer
        do { _ = try restarted.commitMetadata(draft: protectedMetadata, expectedRevision: protectedMetadata.revision); fatalError("viewer edited metadata") }
        catch SceneConfigurationStore.Failure.unavailable {}
        SpaceData.value.permission = .owner
        deviceScene.info.projectionPending = true
        do { _ = try restarted.commitMetadata(draft: protectedMetadata, expectedRevision: protectedMetadata.revision); fatalError("pending projection made new metadata revision") }
        catch SceneConfigurationStore.Failure.staleDraft {}
        deviceScene.info.projectionPending = false
        let schedule = Schedule(90, scene: deviceScene); manager.schedules = [schedule]
        try TimedSchedulerBindings.commit(TimedSchedulerBindings.prepare(schedules: [schedule]))
        let slots = schedule.nodeSlots
        let removalSelection = SceneDraftSelection(draft: try SceneDraft(scene: deviceScene))
        try removalSelection.removeMembers([member.identity], confirmed: true)
        precondition(removalSelection.canFinishDeviceSelection, "existing empty selection can finish before saving cleanup")
        let remove = removalSelection.draft
        try db.run("CREATE TRIGGER reject_scene BEFORE INSERT ON sceneInfos BEGIN SELECT RAISE(ABORT, 'injected'); END")
        do { _ = try restarted.commit(draft: remove, expectedRevision: remove.revision); fatalError("failure swallowed") } catch {}
        precondition(schedule.nodeSlots == slots, "production Timed commit restores slots on Scene write failure")
        let persistedSlots = try db.scalar("SELECT value FROM fixture_slots WHERE id = 90") as! Blob
        precondition(tryValue { try JSONDecoder().decode([TimedSchedulerNodeSlot]?.self, from: Data(persistedSlots.bytes)) } == slots)
        try db.run("DROP TRIGGER reject_scene")
        _ = try restarted.commit(draft: remove, expectedRevision: remove.revision)
        precondition(deviceScene.info.configuration!.deviceMembers.isEmpty)
        precondition(deviceScene.info.configuration!.pendingOperations.first?.action == .remove)
        precondition(schedule.nodeSlots?.first?.state == .pendingRemoval)
        let savedCleanup = try SceneInfo.loadAll(meshUUID: scope.meshUUID).first { $0.sceneId == deviceScene.number }!
        precondition(savedCleanup.configuration!.pendingOperations.first?.identity == member.identity)
        precondition(SceneCapacity.intendedScenes(on: lamp).contains(deviceScene.number), "last-member removal retains its physical reservation")
        do { try removalSelection.switchKind(to: .groups, confirmed: true); fatalError("unconfirmed cleanup cannot release type lock") } catch {}
        let absentScene = Scene(77)
        absentScene.info.configuration = .init(kind: .devices, name: "Absent",
            deviceMembers: [member], pendingOperations: [.init(identity: member.identity, action: .write)])
        manager.scenes.append(absentScene); manager.realNodes = []
        try absentScene.info.saveConfiguration()
        var removeAbsent = try SceneDraft(scene: absentScene)
        try removeAbsent.setDeviceMembers([])
        _ = try restarted.commit(draft: removeAbsent, expectedRevision: removeAbsent.revision)
        precondition(absentScene.info.configuration?.pendingOperations.first?.identity == member.identity
            && absentScene.info.configuration?.pendingOperations.first?.action == .remove,
            "missing original Node must retain cleanup identity")
        // CREATE persists an empty scene before Settings exists. Ordinary draft
        // confirmation retains its guard against accidentally saving no selection.
        let createdDraft = try SceneDraft(scope: scope, name: "Created before settings", imageId: 5, kind: .groups)
        do { _ = try restarted.commit(draft: createdDraft, expectedRevision: createdDraft.revision); fatalError("ordinary empty draft accepted") }
        catch SceneConfigurationStore.Failure.invalidTargets {}
        let beforeCreate = try SceneInfo.loadAll(meshUUID: scope.meshUUID).count
        SpaceData.value.permission = .viewer
        do { _ = try restarted.createEmpty(draft: createdDraft); fatalError("viewer created an empty scene") }
        catch SceneConfigurationStore.Failure.unavailable {}
        SpaceData.value.permission = .owner
        try db.run("CREATE TRIGGER reject_scene BEFORE INSERT ON sceneInfos BEGIN SELECT RAISE(ABORT, 'injected'); END")
        do { _ = try restarted.createEmpty(draft: createdDraft); fatalError("failed creation was reported as success") } catch {}
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == beforeCreate)
        try db.run("DROP TRIGGER reject_scene")
        Scene.sdkSaveFails = true
        guard case .projectionPending(let createdNumber) = try restarted.createEmpty(draft: createdDraft) else { fatalError() }
        precondition(tryValue { try restarted.nextAvailableNumber() } != createdNumber)
        _ = try SceneConfigurationStore().createEmpty(draft: createdDraft)
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == beforeCreate + 1)
        Scene.sdkSaveFails = false
        guard case .ready(let createdScene) = try SceneConfigurationStore().createEmpty(draft: createdDraft) else { fatalError() }
        precondition(createdScene.number == createdNumber && createdScene.name == createdDraft.name)
        precondition(createdScene.info.imageId == 5 && createdScene.info.configuration!.pendingOperations.isEmpty)
        var settings = try restarted.editingDraft(for: createdScene)
        try settings.switchKind(to: .devices)
        try settings.switchKind(to: .groups)
        precondition(settings.number == createdNumber, "empty created scene must remain editable in either mode")
        // Closing without saving discards only Settings edits, never the created row.
        let reopened = try restarted.editingDraft(for: createdScene)
        precondition(reopened.number == createdNumber && reopened.groupParameters.isEmpty)
        try settings.setGroupParameters([group.address.address: .init(isOn: true, lightness: 12000, cct: 4000)])
        guard case .ready(let configured) = try restarted.commit(draft: settings, expectedRevision: settings.revision) else { fatalError() }
        precondition(configured.number == createdNumber)
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == beforeCreate + 1)
        do { _ = try restarted.createEmpty(draft: settings); fatalError("creation entry accepted an existing configured scene") }
        catch SceneConfigurationStore.Failure.invalidTargets {}
        try displayOrderSaveFlow(path: CommandLine.arguments[1] + ".display-order")
        print("PASS save: transaction rollback, offline edits, cleanup, projection repair, restart, empty CREATE and Settings reuse")
    }
}

private func displayOrderSaveFlow(path: String) throws {
    SunSmartDataManager.shared.db = try Connection(path)
    let manager = MeshNetworkManager.instance
    manager.meshNetwork = Network()
    manager.scenes = []; manager.groups = []; manager.realNodes = []; manager.schedules = []
    Scene.diskNumbers = []; Scene.sdkSaveFails = false
    Network.removalFails = false; Network.didRemove = nil
    SpaceData.value = SpaceData(); SpaceViewController.active = nil
    SpaceConfigurationSafety.recovery = FixtureRecoveryState()
    SpaceConfigurationSafety.currentConfigurationAvailable = true
    let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
    let store = SceneConfigurationStore()
    func draft(_ name: String) throws -> SceneDraft {
        try SceneDraft(scope: scope, name: name, imageId: 1, kind: .groups)
    }
    func created(_ name: String) throws -> Scene {
        guard case .ready(let scene) = try store.createEmpty(draft: draft(name)) else { fatalError("expected committed scene") }
        return scene
    }
    let first = try created("Scene 1"), second = try created("Scene 2")
    precondition(first.number == 1 && first.info.displayOrder == 1)
    precondition(second.number == 2 && second.info.displayOrder == 2)
    try store.prepareDeletion(scene: first)
    precondition(first.info.displayOrder == 1 && first.info.configuration?.isDeleting == true)
    precondition(tryValue { try store.nextAvailableNumber() } == 3, "pending deletion still reserves its number")
    try store.finishDeletion(info: first.info, scope: scope)
    var renamed = try store.editingDraft(for: second)
    renamed.setMetadata(name: "Scene 1", imageId: 4)
    _ = try store.commitMetadata(draft: renamed, expectedRevision: renamed.revision)
    precondition(second.info.displayOrder == 2)
    let reused = try created("Scene 2")
    precondition(reused.number == 1 && reused.info.displayOrder == 3, "reused Mesh number must receive a new trailing display order")
    precondition(Scene.sortedForDisplay(manager.scenes).map(\.name) == ["Scene 1", "Scene 2"])

    manager.scenes = []
    SunSmartDataManager.shared.db = try Connection(path)
    try store.restoreSceneProjections()
    precondition(manager.scenes.map(\.number) == [1, 2], "fixture must reload SDK projections in number order")
    precondition(Scene.sortedForDisplay(manager.scenes).map(\.number) == [2, 1])
    precondition(Scene.sortedForDisplay(Array(manager.scenes.reversed())).map(\.name) == ["Scene 1", "Scene 2"], "reloaded input order cannot change display order")
    let reloaded = manager.scenes.first { $0.number == 1 }!
    let configuration = reloaded.info.configuration!
    reloaded.info.displayOrder = 9999 // durable metadata, not a stale projection, owns the value.
    var icon = try store.editingDraft(for: reloaded)
    icon.setMetadata(name: "Scene 2", imageId: 8)
    _ = try store.commitMetadata(draft: icon, expectedRevision: icon.revision)
    precondition(reloaded.info.displayOrder == 3 && reloaded.info.configuration == configuration)

    // Legacy SDK-only rows use their number as the baseline. Another Space's
    // high display order must not influence this Space's next appended scene.
    let legacy = Scene(60); legacy.name = "Legacy"; manager.scenes.append(legacy)
    let foreign = Scene(90); foreign.subNetworkId = "other"; foreign.info.displayOrder = 9000
    manager.scenes.append(foreign)
    let foreignRow = SceneInfo(sceneId: 85)
    foreignRow.displayOrder = 9000; foreignRow.configuration = .init(kind: .groups, name: "Other Space")
    try foreignRow.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: "other")
    let afterLegacy = try created("After legacy")
    precondition(afterLegacy.info.displayOrder == 61, "SDK-only legacy order counts; another Space does not")
    let orphan = SceneInfo(sceneId: 80)
    orphan.displayOrder = 100; orphan.configuration = .init(kind: .groups, name: "Projection pending")
    try orphan.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
    let tombstone = SceneInfo(sceneId: 81)
    tombstone.displayOrder = 101; tombstone.configuration = .init(kind: .groups, name: "Deletion pending", isDeleting: true)
    try tombstone.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
    let afterPending = try created("After pending")
    precondition(afterPending.info.displayOrder == 102, "unprojected App rows and tombstones must participate in allocation")
    precondition(SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 85)?.displayOrder == 9000)

    let pendingDraft = try draft("Retry same order")
    Scene.sdkSaveFails = true
    guard case .projectionPending(let pendingNumber) = try store.createEmpty(draft: pendingDraft) else { fatalError("expected SDK projection failure") }
    precondition(SceneInfo.load(meshUUID: scope.meshUUID, sceneId: pendingNumber)?.displayOrder == 103)
    let count = try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID).count
    manager.scenes.removeAll { $0.number == pendingNumber }
    SunSmartDataManager.shared.db = try Connection(path)
    _ = try SceneConfigurationStore().createEmpty(draft: pendingDraft)
    Scene.sdkSaveFails = false
    guard case .ready(let recovered) = try SceneConfigurationStore().createEmpty(draft: pendingDraft) else { fatalError("retry must repair original scene") }
    precondition(recovered.number == pendingNumber && recovered.info.displayOrder == 103)
    precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID).count } == count)

    let failedDraft = try draft("Rollback order")
    let db = SunSmartDataManager.shared.db!
    try db.run("CREATE TRIGGER reject_order BEFORE INSERT ON sceneInfos BEGIN SELECT RAISE(ABORT, 'injected creation failure'); END")
    do { _ = try store.createEmpty(draft: failedDraft); fatalError("failed order transaction committed") } catch {}
    precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID, subnetworkId: scope.networkID).count } == count)
    precondition(!manager.scenes.contains { $0.name == failedDraft.name })
    try db.run("DROP TRIGGER reject_order")
    guard case .ready(let retried) = try store.createEmpty(draft: failedDraft) else { fatalError("retry should succeed") }
    precondition(retried.info.displayOrder == 104, "failed transaction must not consume or reset display order")
    precondition(SceneInfo.load(meshUUID: scope.meshUUID, sceneId: 85)?.displayOrder == 9000)
    print("PASS display order save: rename/delete/number reuse, reload, legacy/orphan/tombstone allocation, Space isolation, projection retry and rollback")
}
