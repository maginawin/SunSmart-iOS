import Foundation
import SQLite
import SQLite3

@main struct SceneSaveCoordinatorTests {
    static func main() throws {
        SunSmartDataManager.shared.db = try Connection(CommandLine.arguments[1])
        let manager = MeshNetworkManager.instance
        let node = Node(1); node.sceneSetupModel!.parentElement!.observedSceneRegister = []
        let group = Group(); manager.groups = [group]; manager.realNodes = [node]; node.group = group
        let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
        var draft = try SceneDraft(scope: scope, name: "Test", imageId: 0, kind: .groups,
            groupParameters: [group.address.address: .init(isOn: true, lightness: 1000, cct: 3000)])
        let coordinator = SceneSaveCoordinator()
        var report: SceneSaveCoordinator.Report?
        coordinator.onReport = { report = $0 }
        node.fingerprint = node.fingerprint.lowercased()
        try coordinator.send(draft: draft, purpose: .preview)
        guard report?.results.count == 1 else { print("FAIL preview must report actual target result"); exit(1) }
        precondition(SyncExecutionSession.sent.count == 1 && !(SyncExecutionSession.sent[0].message is SceneStore))
        node.fingerprint = node.fingerprint.uppercased()
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).isEmpty })
        do { _ = try coordinator.confirm(revision: draft.revision); fatalError("preview cannot authorize confirmation") } catch {}
        try coordinator.send(draft: draft, purpose: .beforeSave)
        precondition(SyncExecutionSession.sent.count == 2, "DONE resends after preview")
        let added = Node(2); manager.realNodes.append(added); added.group = group
        do { _ = try coordinator.confirm(revision: draft.revision); fatalError("changed group membership accepted") } catch {}
        added.group = nil
        draft.setMetadata(name: "Changed", imageId: 0)
        do { _ = try coordinator.confirm(revision: draft.revision); fatalError("old snapshot accepted") } catch {}
        SyncExecutionSession.deferStop = true
        let count = SyncExecutionSession.sent.count
        try coordinator.send(draft: draft, purpose: .beforeSave)
        precondition(SyncExecutionSession.sent.count == count, "new send must await stop")
        SyncExecutionSession.pendingStop?(); SyncExecutionSession.deferStop = false
        Scene.sdkSaveFails = true
        let result = try coordinator.confirm(revision: draft.revision)
        guard case .projectionPending(let number) = result else { fatalError("must retain projection failure") }
        precondition(coordinator.committedNumber == number)
        _ = try coordinator.confirm(revision: draft.revision)
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == 1)
        Scene.sdkSaveFails = false
        coordinator.cancel()
        precondition(SyncExecutionSession.sent.count == count + 1, "discard never restores lamp values")
        let persisted = try SceneInfo.loadAll(meshUUID: scope.meshUUID).first!.configuration!
        _ = try coordinator.confirm(revision: draft.revision)
        let recovered = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(recovered.count == 1 && recovered[0].configuration?.revision == persisted.revision)
        precondition(recovered[0].configuration?.pendingOperations == persisted.pendingOperations,
                     "background projection retry preserves operation generations")
        var formalReports = 0
        coordinator.onFormalCompletion = { _ in formalReports += 1 }
        coordinator.cancel(); SyncExecutionSession.deferFormal = true
        _ = try coordinator.confirm(revision: draft.revision)
        let committedBeforeInvalidation = try SceneInfo.loadAll(meshUUID: scope.meshUUID).first!.configuration
        SyncExecutionSession.lateInvalidation?()
        precondition(formalReports == 1, "formal invalidation must deliver saved-pending terminal result")
        SyncExecutionSession.lateInvalidation?(); SyncExecutionSession.lateFormal?()
        precondition(formalReports == 1, "formal terminal result must be delivered once")
        precondition(coordinator.committedNumber == number && tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).first!.configuration } == committedBeforeInvalidation)
        var editedAfterCommit = draft
        editedAfterCommit.setMetadata(name: "Cannot recreate", imageId: 1)
        do { try coordinator.send(draft: editedAfterCommit, purpose: .beforeSave); fatalError("saved editor became a new scene") } catch {}
        do { _ = try coordinator.confirm(revision: editedAfterCommit.revision); fatalError("edited revision allocated another number") } catch {}
        precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == 1)
        formalReports = 0
        coordinator.cancel(); SyncExecutionSession.lateFormal?(); SyncExecutionSession.lateInvalidation?()
        precondition(formalReports == 0, "late formal completion cannot dismiss a resumed editor")
        SyncExecutionSession.deferFormal = false
        let savedScene = manager.scenes.first { $0.number == number }!
        let offlineDraft = try SceneDraft(scene: savedScene)
        node.state = false
        let offline = SceneSaveCoordinator(); var offlineReport: SceneSaveCoordinator.Report?
        offline.onReport = { offlineReport = $0 }
        let beforeOffline = SyncExecutionSession.sent.count
        try offline.send(draft: offlineDraft, purpose: .beforeSave)
        guard case .offline? = offlineReport?.results[node.timedSchedulerIdentity!] else { fatalError("offline must be reported") }
        precondition(SyncExecutionSession.sent.count == beforeOffline, "offline send does not invent success")
        _ = try offline.confirm(revision: offlineDraft.revision)
        offline.cancel()
        // Re-entry uses a new coordinator/controller, not the original in-memory draft.
        node.state = true
        func createPendingScene() throws -> Scene {
            let creator = SceneSaveCoordinator()
            let value = try SceneDraft(scope: scope, name: "Reenter pending", imageId: 0, kind: .groups,
                groupParameters: [group.address.address: .init(isOn: true, lightness: 3000, cct: 4000)])
            try creator.send(draft: value, purpose: .beforeSave)
            Scene.sdkSaveFails = true
            guard case .projectionPending(let number) = try creator.confirm(revision: value.revision) else { fatalError() }
            creator.cancel()
            return manager.scenes.first { $0.number == number }!
        }
        let pendingScene = try createPendingScene()
        let beforeReentry = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        let preserved = pendingScene.info.configuration!
        do { _ = try SceneConfigurationStore().editingDraft(for: pendingScene); fatalError("pending projection must block new editing while SDK recovery fails") } catch {}
        Scene.sdkSaveFails = false
        let reopenedDraft = try SceneConfigurationStore().editingDraft(for: pendingScene)
        let afterReentry = try SceneInfo.loadAll(meshUUID: scope.meshUUID)
        precondition(!pendingScene.info.projectionPending && pendingScene.number == reopenedDraft.number)
        precondition(afterReentry.count == beforeReentry.count && pendingScene.info.configuration == preserved,
                     "reentering Settings only restores projection, preserving revision and generations")
        precondition(reopenedDraft.sourceConfiguration == preserved)
        let empty = SceneSaveCoordinator(); var emptyReport: SceneSaveCoordinator.Report?
        empty.onReport = { emptyReport = $0 }; node.group = nil
        let emptyDraft = try SceneDraft(scope: scope, name: "Empty group", imageId: 0, kind: .groups,
            groupParameters: [group.address.address: .init(isOn: true, lightness: 65535, cct: 4500)])
        try empty.send(draft: emptyDraft, purpose: .beforeSave)
        precondition(emptyReport?.results.isEmpty == true, "empty group has no fake device results")
        _ = try empty.confirm(revision: emptyDraft.revision)
        try directSyncSave()
        try authorityContinuation()
        try metadataTaskContinuity()
        try groupDeletionLifecycle()
        print("PASS coordinator: preview, DONE, stale confirmation, membership, stop, cancel and projection retry")
    }
}
func tryValue<T>(_ value: () throws -> T) -> T { try! value() }

// Real SQLite commitMetadata interleaved with production task snapshots and receipts.
func metadataTaskContinuity() throws {
    SunSmartDataManager.shared.db = try Connection(":memory:")
    let manager = MeshNetworkManager.instance, store = SceneConfigurationStore()
    manager.scenes = []
    let a = Node(21), removed = Node(22)
    a.sceneSetupModel!.parentElement!.observedSceneRegister = []
    removed.sceneSetupModel!.parentElement!.observedSceneRegister = []
    manager.realNodes = [a, removed]; manager.groups = []; manager.schedules = []
    for rename in [false, true] {
        let scene = Scene(rename ? 61 : 60); manager.scenes.append(scene)
        let member = SceneDeviceMember(identity: a.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 2000, cct: 3500))
        scene.info.configuration = .init(kind: .devices, name: scene.name, deviceMembers: [member], pendingOperations: [
            .init(identity: a.timedSchedulerIdentity!, action: .write), .init(identity: removed.timedSchedulerIdentity!, action: .remove)])
        removed.sceneExecuteDatas = [.init(sceneNumber: scene.number)]
        let write = try SceneMessageContext(scene: scene, node: a, action: .write)
        let delete = try SceneMessageContext(scene: scene, node: removed, action: .remove)
        let batch = SceneCommandBuilder.captureConfigurations()
        let original = scene.info.configuration!
        let competingEditor = try store.editingDraft(for: scene)
        var draft = competingEditor
        draft.setMetadata(name: rename ? "Renamed" : draft.name, imageId: rename ? draft.imageId : 3)
        _ = try store.commitMetadata(draft: draft, expectedRevision: draft.revision)
        checkMetadata(batch(), "\(rename ? "name" : "icon") edit invalidated captured batch")
        checkMetadata(scene.info.configuration!.revision == original.revision, "metadata replaced revision")
        checkMetadata(write.apply(node: a, successful: true), "metadata rejected in-flight Store")
        checkMetadata(delete.apply(node: removed, successful: true), "metadata rejected in-flight Delete")
        checkMetadata(scene.info.configuration!.pendingOperations.isEmpty && removed.sceneExecuteDatas.isEmpty && batch(), "ACK progress must clear pending without invalidating batch")
        do { _ = try store.commitMetadata(draft: competingEditor, expectedRevision: competingEditor.revision); fatalError("stale name/icon editor accepted") }
        catch SceneConfigurationStore.Failure.staleDraft {}
        // Parameter/member commits retain revision ownership and reject old receipts.
        for removeMember in [false, true] {
            let old = try SceneMessageContext(scene: scene, node: a, action: .write)
            let oldBatch = SceneCommandBuilder.captureConfigurations()
            var edit = try store.editingDraft(for: scene)
            try edit.setDeviceMembers(removeMember ? [] : [.init(identity: member.identity, parameters: .init(isOn: false, lightness: 0, cct: 3500))])
            _ = try store.commit(draft: edit, expectedRevision: edit.revision)
            checkMetadata(!old.apply(node: a, successful: true) && !oldBatch(), "real configuration edit accepted old task")
        }
    }
    let group = Group(); manager.groups = [group]; a.group = group
    let legacy = Scene(62), otherLegacy = Scene(63); manager.scenes += [legacy, otherLegacy]
    group.info.sceneExecuteDatas = [.init(sceneNumber: 62, lightness: 3000, cct: 4000),
                                   .init(sceneNumber: 63, lightness: 5000, cct: 5000)]
    let otherWrite = try SceneMessageContext(scene: otherLegacy, node: a, action: .write)
    let legacyDelete = try SceneMessageContext(scene: legacy, node: removed, action: .remove)
    removed.sceneExecuteDatas = [.init(sceneNumber: 62), .init(sceneNumber: 63)]
    let legacyWrite = try SceneMessageContext(scene: legacy, node: a, action: .write)
    let legacyBatch = SceneCommandBuilder.captureConfigurations()
    var edit = try store.editingDraft(for: legacy)
    edit.setMetadata(name: "Legacy renamed", imageId: 1)
    Scene.sdkSaveFails = true
    guard case .projectionPending = try store.commitMetadata(draft: edit, expectedRevision: edit.revision) else { fatalError() }
    let blockedBatch = SceneCommandBuilder.captureConfigurations()
    checkMetadata(!legacyWrite.apply(node: a, successful: true) && !legacyBatch(), "projection failure must block receipts and batches")
    do { _ = try store.editingDraft(for: legacy); fatalError("new edit bypassed pending projection") } catch {}
    Scene.sdkSaveFails = false
    _ = try store.editingDraft(for: legacy)
    checkMetadata(legacyBatch() && legacyWrite.apply(node: a, successful: true), "legacy metadata migration/recovery changed task identity")
    checkMetadata(!blockedBatch(), "batch captured during failed projection must never become valid")
    var otherEdit = try store.editingDraft(for: otherLegacy)
    otherEdit.setMetadata(name: "Other legacy", imageId: 2)
    _ = try store.commitMetadata(draft: otherEdit, expectedRevision: otherEdit.revision)
    checkMetadata(otherWrite.apply(node: a, successful: true) && legacyDelete.apply(node: removed, successful: true), "legacy Store/Delete lost ownership during metadata promotion")
    checkMetadata(a.sceneExecuteDatas.first { $0.sceneNumber == 62 }?.lightness == 3000
        && a.sceneExecuteDatas.first { $0.sceneNumber == 63 }?.lightness == 5000
        && removed.sceneExecuteDatas.map(\.sceneNumber) == [63], "same-Mesh legacy tasks crossed scene numbers")
    let promoted = try SceneInfo.loadAll(meshUUID: manager.meshNetwork!.uuid.uuidString)
    checkMetadata(promoted.first { $0.sceneId == 62 }?.configuration?.name == "Legacy renamed"
        && promoted.first { $0.sceneId == 63 }?.configuration?.name == "Other legacy", "metadata promotion merged scene rows")
    // Configuration drafts always get their own UUID; idempotent commit/retry
    // must select that revision, never either shared legacy initial revision.
    for scene in [otherLegacy, legacy] {
        var content = try store.editingDraft(for: scene)
        try content.setGroupParameters([group.address.address: .init(isOn: true, lightness: UInt16(scene.number) * 100, cct: 4000)])
        let first = try store.commit(draft: content, expectedRevision: content.revision)
        let retry = try store.commit(draft: content, expectedRevision: content.revision)
        guard case .ready(let firstScene) = first, case .ready(let retryScene) = retry else { fatalError() }
        checkMetadata(firstScene === scene && retryScene === scene && scene.info.configuration?.revision == content.revision,
            "configuration commit/retry confused promoted legacy scene rows")
    }
    let identityWrite = try SceneMessageContext(scene: legacy, node: a, action: .write)
    let identityBatch = SceneCommandBuilder.captureConfigurations()
    a.fingerprint = String(repeating: "B", count: 64)
    checkMetadata(!identityWrite.apply(node: a, successful: true) && !identityBatch(), "changed device identity accepted old task")
    if metadataFailures > 0 { exit(1) }
    print("PASS metadata: name/icon Store/Delete, batch continuity, source conflicts, real edits, identity and legacy projection recovery")
}
var metadataFailures = 0
func checkMetadata(_ condition: Bool, _ message: String) {
    if !condition { print("FAIL metadata: \(message)"); metadataFailures += 1 }
}

// Enter through production handle construction and Node.applyMessageHandle, not
// context.apply alone: the last ACK also owns legacy group/schedule completion.
func groupDeletionLifecycle() throws {
    SunSmartDataManager.shared.db = try Connection(":memory:")
    let manager = MeshNetworkManager.instance, store = SceneConfigurationStore()
    manager.scenes = []; manager.groups = []; manager.schedules = []
    for mode in 0..<3 {
        let promote = mode == 1, explicit = mode == 2
        let a = Node(41), b = Node(42), group = Group()
        a.group = group; b.group = group; manager.realNodes = [a, b]; manager.groups = [group]
        let scene = Scene(UInt16(81 + mode)); manager.scenes.append(scene)
        if explicit { scene.info.configuration = .init(kind: .groups, name: scene.name) }
        let relationship = SceneExecuteData(sceneNumber: scene.number)
        relationship.state = .waitDelete; group.info.sceneExecuteDatas = [relationship]
        let indirect = Schedule(81, scene: scene), unrelated = Schedule(82)
        manager.schedules = [indirect, unrelated]; group.info.bindSchedules = [indirect, unrelated]
        for node in [a, b] {
            node.sceneExecuteDatas = [.init(sceneNumber: scene.number)]
            node.sceneSetupModel!.parentElement!.observedSceneRegister = [scene.number]
        }
        precondition(group.info.save())
        let first = scene.getDeleteMessageHandles(node: a).first!
        let last = scene.getDeleteMessageHandles(node: b).first!
        if promote {
            var metadata = try store.editingDraft(for: scene)
            metadata.setMetadata(name: "Removing group", imageId: 2)
            Scene.sdkSaveFails = true
            guard case .projectionPending = try store.commitMetadata(draft: metadata, expectedRevision: metadata.revision) else { fatalError() }
            checkMetadata(!a.applyMessageHandle(first) && group.info.sceneExecuteDatas.count == 1,
                "projection failure allowed relation cleanup")
            Scene.sdkSaveFails = false
            _ = try store.editingDraft(for: scene)
        }
        checkMetadata(!a.applyMessageHandle(first, isSuccess: false) && a.sceneExecuteDatas.count == 1 && group.info.bindSchedules.count == 2,
            "failed ACK cleared group relationship")
        manager.currentNetworkKey.networkId = 2
        checkMetadata(!a.applyMessageHandle(first), "wrong-scope ACK accepted")
        manager.currentNetworkKey.networkId = 1
        b.fingerprint = String(repeating: "B", count: 64)
        checkMetadata(!b.applyMessageHandle(last) && group.info.sceneExecuteDatas.count == 1, "stale identity ACK cleaned group")
        b.fingerprint = String(repeating: "A", count: 64)
        // A pending group operation still requires its own ACK even if cached
        // values/register observations already look clear.
        if explicit { b.sceneExecuteDatas = []; b.sceneSetupModel!.parentElement!.observedSceneRegister = [] }
        // SDK Scene Register observation reflects the successful device response.
        a.sceneSetupModel!.parentElement!.observedSceneRegister = []
        checkMetadata(a.applyMessageHandle(first), "first valid Delete rejected")
        checkMetadata(a.sceneExecuteDatas.isEmpty && (explicit || !b.sceneExecuteDatas.isEmpty)
            && group.info.sceneExecuteDatas.count == 1 && group.info.bindSchedules.count == 2,
            "first ACK prematurely removed unfinished group")
        b.sceneSetupModel!.parentElement!.observedSceneRegister = []
        GroupInfo.savingSucceeds = false
        let nodeSaves = b.propertySaves
        checkMetadata(!b.applyMessageHandle(last), "failed GroupInfo save reported successful deletion")
        checkMetadata(group.info.sceneExecuteDatas.count == 1 && group.info.bindSchedules.count == 2
            && b.propertySaves == nodeSaves && !b.getNodeNeedDeleteSceneDatas(scene: scene).isEmpty,
            "failed relationship save lost retry work or persisted cleared Node cache")
        GroupInfo.savingSucceeds = true
        guard let retry = scene.getDeleteMessageHandles(node: b).first else { checkMetadata(false, "failed cleanup could not rebuild Delete task"); continue }
        // Real SQLite COMMIT failure after SDK node persistence: the databases
        // are independent, so retry must follow the retained Group intent.
        enum CommitFailure: Error { case injected }
        let db = SunSmartDataManager.shared.db!
        var hookCalls = 0
        db.commitHook { hookCalls += 1; throw CommitFailure.injected }
        let commitResult = b.applyMessageHandle(retry)
        checkMetadata(!commitResult, "App commit failure reported successful deletion")
        db.commitHook(nil)
        checkMetadata(hookCalls == 1 && sqlite3_get_autocommit(db.handle) == 1, "failed App commit left a transaction open")
        checkMetadata(b.persistedSceneExecuteDatas.isEmpty && group.info.sceneExecuteDatas.count == 1,
            "commit-failure fixture did not reach independent SDK cache write")
        b.sceneExecuteDatas = b.persistedSceneExecuteDatas
        let row = try db.scalar("SELECT value FROM fixture_group_scene WHERE id = ?", Int(group.address.address)) as! Blob
        group.info.sceneExecuteDatas = try JSONDecoder().decode([SceneExecuteData].self, from: Data(row.bytes))
        if let persisted = try SceneInfo.loadAll(meshUUID: manager.meshNetwork!.uuid.uuidString).first(where: { $0.sceneId == scene.number }) {
            scene.info.configuration = persisted.configuration
        }
        checkMetadata(!b.getNodeNeedDeleteSceneDatas(scene: scene).isEmpty,
            "retained waitDelete vanished from planning with empty Node cache")
        guard let afterCommitFailure = scene.getDeleteMessageHandles(node: b).first else { checkMetadata(false, "commit failure lost Delete retry"); continue }
        let saves = group.info.saves, refreshes = a.cacheClears
        checkMetadata(b.applyMessageHandle(afterCommitFailure), "last valid Delete retry rejected")
        checkMetadata(sqlite3_get_autocommit(db.handle) == 1, "Delete retry remained inside a leaked transaction")
        checkMetadata(group.info.sceneExecuteDatas.isEmpty && group.info.bindSchedules.map(\.id) == [unrelated.id]
            && group.info.saves == saves + 1 && a.cacheClears > refreshes,
            "\(promote ? "promoted" : "legacy") last ACK left waitDelete/schedule relationship or skipped persistence/refresh")
        checkMetadata(manager.scenes.contains { $0 === scene }, "group cleanup removed Scene itself")
    }
    // Device cleanup never owns a Group's legacy relationship.
    let a = manager.realNodes[0], group = manager.groups[0]
    let deviceScene = Scene(84); manager.scenes.append(deviceScene)
    deviceScene.info.configuration = .init(kind: .devices, name: "Device", pendingOperations: [.init(identity: a.timedSchedulerIdentity!, action: .remove)])
    let directHandle = deviceScene.getDeleteMessageHandles(node: a).first!
    let foreignRelationship = SceneExecuteData(sceneNumber: 84); foreignRelationship.state = .waitDelete
    // The wrapper must reject a now-conflicting Scene rather than clear Group data.
    group.info.sceneExecuteDatas = [foreignRelationship]
    checkMetadata(!a.applyMessageHandle(directHandle) && group.info.sceneExecuteDatas.count == 1,
        "device context cleaned a foreign Group relationship")
    group.info.sceneExecuteDatas = []
    checkMetadata(a.applyMessageHandle(directHandle) && deviceScene.info.configuration!.pendingOperations.isEmpty,
        "ordinary device Delete regressed")
    let active = Scene(85); manager.scenes.append(active)
    active.info.configuration = .init(kind: .groups, name: "Active group")
    group.info.sceneExecuteDatas = [.init(sceneNumber: 85)]
    a.groupState = .exitFailure
    a.sceneExecuteDatas = [.init(sceneNumber: 85)]
    let exitHandle = active.getDeleteMessageHandles(node: a).first!
    a.sceneSetupModel!.parentElement!.observedSceneRegister = []
    checkMetadata(a.applyMessageHandle(exitHandle) && group.info.sceneExecuteDatas.first?.state == .normal,
        "member exit deleted an active Group relationship")
    // Empty caches do not prove an unobserved member was deleted. A genuine
    // non-Scene device is not a target, while a lost identity cannot be skipped.
    let unknown = Scene(86); manager.scenes.append(unknown)
    let b = manager.realNodes[1], nonScene = Node(43)
    a.groupState = .normal; nonScene.group = group; nonScene.sceneSetupModel = nil; nonScene.hasIdentity = false
    manager.realNodes.append(nonScene)
    let pendingRelationship = SceneExecuteData(sceneNumber: 86); pendingRelationship.state = .waitDelete
    group.info.sceneExecuteDatas = [pendingRelationship]
    a.sceneExecuteDatas = []; b.sceneExecuteDatas = []
    a.sceneSetupModel!.parentElement!.observedSceneRegister = []
    b.sceneSetupModel!.parentElement!.observedSceneRegister = nil
    let aEmpty = unknown.getDeleteMessageHandles(node: a).first!
    let bUnknown = unknown.getDeleteMessageHandles(node: b).first!
    checkMetadata(a.applyMessageHandle(aEmpty) && group.info.sceneExecuteDatas.count == 1,
        "empty cache hid a member with unknown register")
    b.hasIdentity = false; b.sceneSetupModel!.parentElement!.observedSceneRegister = []
    checkMetadata(!a.applyMessageHandle(aEmpty) && group.info.sceneExecuteDatas.count == 1,
        "lost target identity was mistaken for unsupported non-target")
    b.hasIdentity = true
    checkMetadata(b.applyMessageHandle(bUnknown) && group.info.sceneExecuteDatas.isEmpty,
        "confirmed absence could not complete alongside a genuine non-Scene member")
    if metadataFailures > 0 { exit(1) }
    print("PASS Delete lifecycle: production handles/wrapper, first/last ACK, legacy promotion/recovery, stale/failed replies and device isolation")
}

func authorityContinuation() throws {
    SunSmartDataManager.shared.db = try Connection(":memory:")
    let manager = MeshNetworkManager.instance
    manager.scenes = []; manager.groups = []; manager.schedules = []
    let node = Node(90); manager.realNodes = [node]
    node.sceneSetupModel!.parentElement!.observedSceneRegister = []
    let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
    let draft = try SceneDraft(scope: scope, name: "Authority", imageId: 0, kind: .devices,
        deviceMembers: [.init(identity: node.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 1234, cct: 4000))])
    let coordinator = SceneSaveCoordinator(), authority = SpaceData.value
    authority.permission = .editor
    try coordinator.send(draft: draft, purpose: .beforeSave)
    precondition(authority.applyRemoteSpaceAuthorityRestrictions(["uuid": authority.id, "role": "editor", "userEvents": ["EditorPasswdChanged"], "spaceData": ["sceneConfigurations": "broken"]]))
    do { _ = try coordinator.confirm(revision: draft.revision); fatalError("revoked confirmation accepted") } catch {}
    do { try SceneSaveCoordinator().send(draft: draft, purpose: .preview); fatalError("revoked preview accepted") } catch {}
    precondition(coordinator.committedNumber == nil)
    authority.requiresPasswordVerification = false; SpaceConfigurationSafety.recovery.authority = .writable
    guard case .ready(let scene) = try coordinator.confirm(revision: draft.revision) else { fatalError() }
    let committed = scene.info.configuration!
    let context = try SceneMessageContext(scene: scene, node: node, action: .write)
    authority.permission = .visitor
    precondition(!context.matches(node: node) && !context.apply(node: node, successful: true), "role downgrade must reject direct result")
    precondition(scene.info.configuration == committed)
    precondition(tryValue { try SceneCommandBuilder.recallHandles(scene: scene).count } == 1,
                 "write revocation must not take away separately permitted Recall")
    authority.permission = .editor
    SpaceConfigurationSafety.recovery.authority = .waitingForAuthorization
    precondition(!context.apply(node: node, successful: true))
    SpaceConfigurationSafety.recovery.authority = .writable
    precondition(context.apply(node: node, successful: true))
    precondition(scene.number == coordinator.committedNumber && scene.info.configuration!.revision == committed.revision
        && scene.info.configuration!.pendingOperations.isEmpty)
    coordinator.cancel(); authority.permission = .owner
    print("PASS effective authorization: real remote restriction, confirmation/preview, running role/authority downgrade, pending Recall and same-number continuation")
}

// DONE persists intent without sending parameters or launching a hidden sync session.
func directSyncSave() throws {
    SunSmartDataManager.shared.db = try Connection(":memory:")
    let manager = MeshNetworkManager.instance
    manager.scenes = []; manager.groups = []; manager.schedules = []
    let node = Node(81); manager.realNodes = [node]
    node.sceneSetupModel!.parentElement!.observedSceneRegister = []
    let scope = SceneScope(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001")
    var draft = try SceneDraft(scope: scope, name: "Direct save", imageId: 0, kind: .devices,
        deviceMembers: [.init(identity: node.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 2500, cct: 4000))])
    let coordinator = SceneSaveCoordinator()
    let sent = SyncExecutionSession.sent.count
    SyncExecutionSession.formalStarts = 0
    Scene.sdkSaveFails = true
    guard case .projectionPending(let number) = try coordinator.saveForSync(draft: draft) else { fatalError("projection must stay retryable") }
    let pending = try SceneInfo.loadAll(meshUUID: scope.meshUUID).first!.configuration!
    precondition(pending.pendingOperations.count == 1 && pending.pendingOperations[0].action == .write)
    coordinator.cancel()
    Scene.sdkSaveFails = false
    guard case .ready(let scene) = try coordinator.saveForSync(draft: draft) else { fatalError("projection recovery must hand off scene") }
    precondition(scene.number == number && scene.info.configuration == pending)
    _ = try coordinator.saveForSync(draft: draft)
    let reopened = try SceneDraft(scene: scene)
    let beforeUnchanged = scene.info.configuration!
    _ = try SceneSaveCoordinator().saveForSync(draft: reopened)
    guard scene.info.configuration == beforeUnchanged else {
        print("FAIL unchanged Settings must preserve existing revision and pending generations"); exit(1)
    }
    let write = try SceneMessageContext(scene: scene, node: node, action: .write)
    precondition(write.apply(node: node, successful: true))
    let settled = scene.info.configuration!
    var reverted = try SceneDraft(scene: scene)
    let enteredRevision = reverted.revision
    reverted.setMetadata(name: "Temporary", imageId: 9)
    try reverted.setDeviceMembers([])
    reverted.setMetadata(name: reverted.sourceName, imageId: reverted.sourceImageId)
    try reverted.setDeviceMembers(settled.deviceMembers)
    precondition(reverted.revision != enteredRevision)
    let store = SceneConfigurationStore()
    precondition(tryValue { try store.sceneIfUnchanged(draft: reverted) === scene }, "reverting edits must compare content, not draft revision")
    Scene.sdkSaveFails = true
    guard case .ready = try SceneSaveCoordinator().saveForSync(draft: reverted) else { fatalError("unchanged save must not rewrite SDK projection") }
    Scene.sdkSaveFails = false
    precondition(scene.info.configuration == settled && settled.pendingOperations.isEmpty, "completed writes must not reappear")
    precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).first!.configuration } == settled)
    var changed = try SceneDraft(scene: scene)
    changed.setMetadata(name: changed.name, imageId: changed.imageId + 1)
    precondition(tryValue { try store.sceneIfUnchanged(draft: changed) == nil }, "icon edits must not be discarded")
    scene.info.projectionPending = true
    do { _ = try store.sceneIfUnchanged(draft: reverted); fatalError("pending projection bypassed recovery") } catch {}
    scene.info.projectionPending = false
    scene.info.configuration!.revision = UUID()
    do { _ = try store.sceneIfUnchanged(draft: reverted); fatalError("stale source accepted by no-change shortcut") } catch {}
    scene.info.configuration = settled
    let group = Group(), legacy = Scene(82)
    legacy.name = "Legacy"; group.info.sceneExecuteDatas = [.init(sceneNumber: 82, lightness: 3200)]
    manager.groups = [group]; node.group = group; manager.scenes.append(legacy)
    var groupDraft = try SceneDraft(scene: legacy)
    try groupDraft.setGroupParameters([:]); try groupDraft.setGroupParameters(groupDraft.sourceGroupParameters)
    let beforeGroupSaves = group.info.saves
    guard case .ready = try store.commit(draft: groupDraft, expectedRevision: groupDraft.revision) else { fatalError() }
    precondition(legacy.info.configuration == nil && group.info.saves == beforeGroupSaves,
                 "unchanged legacy group must not be promoted or rewritten")
    print("PASS unchanged save: completed/pending intent, reverted edits, icon changes, stale source, projection gate and legacy groups")
    precondition(tryValue { try SceneInfo.loadAll(meshUUID: scope.meshUUID).count } == 1)
    precondition(SyncExecutionSession.sent.count == sent, "DONE must not send preview parameters")
    precondition(SyncExecutionSession.formalStarts == 0, "only the sync page may start formal sync")
    draft.setMetadata(name: "Changed after commit", imageId: 1)
    do { _ = try coordinator.saveForSync(draft: draft); fatalError("committed editor must not create a new revision") } catch {}
    let revoked = try SceneDraft(scene: scene)
    SpaceData.value.permission = .visitor
    do { _ = try SceneSaveCoordinator().saveForSync(draft: revoked); fatalError("revoked save accepted") } catch {}
    SpaceData.value.permission = .editor
    print("PASS direct sync save: no send, durable pending, idempotence, projection retry, frozen revision and permission")
}
