func check(_ condition: @autoclosure () throws -> Bool, _ message: String = "", file: StaticString = #file, line: UInt = #line) {
    precondition((try? condition()) == true, message, file: file, line: line)
}
import Foundation
import SQLite

final class SRAlertAction {
    let title: String; let action: ((SRAlertAction) -> Void)?
    init(title: String, actionHandler: ((SRAlertAction) -> Void)?) { self.title = title; action = actionHandler }
    func invoke() { action?(self) }
}
final class SRAlertView {
    static var shown: [SRAlertAction] = []
    init(message: String, actions: [SRAlertAction]) { Self.shown = actions }
    func show() {}
}
enum XWHUDManager { static func showErrorTipHUD(_ message: String) {} }
let spaceDataChangedNotificaitonName = "changed"
enum SpaceChangeDataType { case common }
final class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
final class SyncExecutionEnvironment { var configurationIsCurrent: () -> Bool = { true } }
// Session/transport are controlled boundaries. Plans, handles, contexts, App
// transaction/SQLite persistence and finalization all execute production code.
final class SyncExecutionSession {
    enum Kind { case scene(Scene) }
    enum State { case syncSuccess, syncFailure }
    static var current: SyncExecutionSession?
    static var deferStop = false
    static var pendingStop: (() -> Void)?
    static var sent: [(Node, MeshMessageHandle)] = []
    let environment: SyncExecutionEnvironment
    var sections: [SyncDevicesSectionModel] = []
    var onSettled: ((State) -> Void)?
    var onPlanInvalidated: (() -> Void)?
    var onStopped: (() -> Void)?
    init(type: Kind, reSync: Bool, environment: SyncExecutionEnvironment) { self.environment = environment }
    func start() {
        Self.current = self; Self.sent = []
        guard environment.configurationIsCurrent() else { onPlanInvalidated?(); return }
        for section in sections {
            for device in section.devices + section.groups.flatMap(\.deviceModels) {
                let operations = device.operationType.map { [$0] } ?? device.steps.flatMap { $0.tasks.map(\.operationType) }
                for operation in operations {
                    if case .delete(let node, .scene(let number, _)) = operation, node.state,
                       let scene = MeshNetworkManager.instance.scenes.first(where: { $0.number == number }) {
                        Self.sent += scene.getDeleteMessageHandles(node: node).map { (node, $0) }
                    }
                }
            }
        }
    }
    static func complete(_ addresses: Set<UInt16>, invalidate: Bool = false) {
        guard let run = current else { fatalError("missing transport") }
        for (node, handle) in sent {
            handle.isSuccessful = addresses.contains(node.primaryUnicastAddress)
            if handle.isSuccessful, let deletion = handle.message as? SceneDelete {
                handle.model?.parentElement?.observedSceneRegister = invalidate ? nil : []
                check(deletion.scene == handle.sceneContext?.number)
            }
        }
        for (_, batch) in Dictionary(grouping: sent, by: { ObjectIdentifier($0.0) }) {
            _ = run.applySceneBatch(batch.map { $0.1 }, messageHandles: batch.map { $0.1 })
        }
        run.onSettled?(.syncSuccess)
    }
    func close() {
        if Self.deferStop { Self.pendingStop = onStopped }
        else { onStopped?(); Self.current = nil }
    }
}

@main struct SceneDeletionFlowTests {
    static let manager = MeshNetworkManager.instance
    static let store = SceneConfigurationStore()
    static var successes = 0, failures = 0
    static var scope: SceneScope { .init(meshUUID: manager.meshNetwork!.uuid.uuidString, networkID: "0001") }
    static func fixture(devices: Bool = true) throws -> (Scene, Node, Node, Node, Group) {
        SunSmartDataManager.shared.db = try Connection(":memory:")
        manager.meshNetwork = Network(); manager.currentNetworkKey.networkId = 1
        manager.scenes = []; manager.groups = []; manager.schedules = []; FixtureReferences.switches = []; FixtureReferences.observed = [:]
        SpaceConfigurationSafety.recovery = FixtureRecoveryState(); SpaceConfigurationSafety.failReceiptWrite = false; SpaceConfigurationSafety.failAppliedReceiptWrite = false
        Scene.diskNumbers = []; Network.removalFails = false; Network.didRemove = nil; GroupInfo.savingSucceeds = true
        MeshLibManager.manager.isMeshNetworkConnected = true; MeshProxyMessageCommand.shared.isBusy = false
        SyncExecutionSession.current = nil; SyncExecutionSession.sent = []; SyncExecutionSession.deferStop = false
        let a = Node(1), b = Node(2), x = Node(3), group = Group()
        manager.realNodes = [a, b, x]; manager.groups = [group]; group.nodes = [a, b, x]
        let scene = Scene(1); manager.scenes = [scene]
        let members = [a, b].map { SceneDeviceMember(identity: $0.timedSchedulerIdentity!, parameters: .init(isOn: true, lightness: 1000, cct: 4000)) }
        scene.info.configuration = .init(kind: devices ? .devices : .groups, name: scene.name, deviceMembers: devices ? members : [])
        if !devices { group.info.sceneExecuteDatas = [.init(sceneNumber: 1)]; x.group = nil }
        for node in [a, b, x] { node.sceneSetupModel!.parentElement!.observedSceneRegister = [1] }
        for node in [a, b] { node.sceneExecuteDatas = [.init(sceneNumber: 1)] }
        scene.addresses = [1, 2]
        try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        check(scene.save()); return (scene, a, b, x, group)
    }
    static func delete(_ scene: Scene) {
        SceneServer.deleteScene(scene: scene, success: { _ in successes += 1 }, failed: { _ in failures += 1 })
    }
    static func persisted(_ number: UInt16 = 1) throws -> SceneInfo? { try SceneInfo.loadAll(meshUUID: scope.meshUUID).first { $0.sceneId == number } }
    static func main() throws {
        try incrementalSceneSave()
        var (scene, a, b, x, group) = try fixture()
        // Classification is display-only: even a stale observed X is not a target.
        delete(scene)
        check(Set(SyncExecutionSession.sent.map { $0.0.primaryUnicastAddress }) == [1, 2])
        check(scene.info.configuration!.isDeleting)
        let original = scene.info.configuration!
        SyncExecutionSession.complete([1])
        check(failures == 1 && successes == 0 && scene.info.configuration!.pendingOperations.map(\.identity) == [b.timedSchedulerIdentity!])
        check(x.sceneSetupModel!.parentElement!.observedSceneRegister == [1])
        // Process/re-entry reload keeps original generation. Offline / unknown is
        // durable cleanup, never a zero-target success or reusable number.
        scene.info = try persisted()!
        b.state = false; MeshLibManager.manager.isMeshNetworkConnected = false
        delete(scene)
        check(failures == 2 && scene.info.configuration!.revision == original.revision)
        check(scene.info.configuration!.pendingOperations[0] == original.pendingOperations.first { $0.identity == b.timedSchedulerIdentity! })
        check(try! store.nextAvailableNumber() == 2)
        manager.realNodes.removeAll { $0 === b }; MeshLibManager.manager.isMeshNetworkConnected = true
        delete(scene); SyncExecutionSession.complete([])
        check(try! persisted()!.configuration!.pendingOperations.count == 1)
        manager.realNodes.append(b); b.state = true
        delete(scene)
        check(SyncExecutionSession.sent.count == 1)
        SyncExecutionSession.complete([2], invalidate: true)
        check(try! persisted()!.configuration!.pendingOperations.count == 1, "lost observation cannot release number")
        delete(scene); SyncExecutionSession.complete([2])
        check(successes == 1 && manager.scenes.isEmpty && (try! persisted()) == nil)
        check(try! store.nextAvailableNumber() == 1)

        // Legacy/group first reads no longer prevent persisting offline deletion.
        (scene, a, b, x, group) = try fixture(devices: false)
        scene.info.configuration = nil
        a.sceneSetupModel!.parentElement!.observedSceneRegister = nil
        MeshLibManager.manager.isMeshNetworkConnected = false
        delete(scene)
        check(group.info.sceneExecuteDatas[0].state == .waitDelete && (try! persisted())!.configuration!.isDeleting)
        check(scene.info.configuration!.pendingOperations.count == 3, "legacy residual outside Group must be retained")
        x.sceneSetupModel!.parentElement!.observedSceneRegister = []
        MeshLibManager.manager.isMeshNetworkConnected = true
        delete(scene); Network.removalFails = true; SyncExecutionSession.complete([1, 2, 3])
        check(manager.scenes.count == 1 && (try! persisted())!.configuration!.isDeleting)
        Network.removalFails = false; delete(scene)
        check(manager.scenes.isEmpty && (try! persisted()) == nil)

        // A late reply in another scope / identity cannot consume the old remove.
        (scene, a, b, x, group) = try fixture()
        delete(scene); manager.currentNetworkKey.networkId = 2; SyncExecutionSession.complete([1, 2])
        manager.currentNetworkKey.networkId = 1
        check(scene.info.configuration!.pendingOperations.count == 2)
        delete(scene); b.fingerprint = String(repeating: "B", count: 64); SyncExecutionSession.complete([1, 2])
        check(scene.info.configuration!.pendingOperations.map(\.identity) == [originalIdentity(b)])
        b.fingerprint = String(repeating: "A", count: 64)
        delete(scene); SyncExecutionSession.deferStop = true; SyncExecutionSession.complete([2])
        let before = failures; delete(scene)
        check(failures == before + 1 && manager.scenes.count == 1, "retry! must await old stop gate")
        SyncExecutionSession.pendingStop?(); SyncExecutionSession.deferStop = false
        check(manager.scenes.isEmpty)

        // Reference and prepare-transaction failures must produce no physical tasks.
        (scene, a, b, x, group) = try fixture(devices: false)
        manager.schedules = [Schedule(4, scene: scene)]
        delete(scene); check(!scene.info.configuration!.isDeleting && SyncExecutionSession.sent.isEmpty)
        manager.schedules = []; FixtureReferences.switches = [.init(sceneANumber: 1)]
        delete(scene); check(!scene.info.configuration!.isDeleting)
        FixtureReferences.switches = []; FixtureReferences.observed[ObjectIdentifier(a)] = [0: [0: .init(sceneNumber: 1)]]
        delete(scene); check(!scene.info.configuration!.isDeleting)
        FixtureReferences.observed = [:]; GroupInfo.savingSucceeds = false
        delete(scene)
        check(!scene.info.configuration!.isDeleting && group.info.sceneExecuteDatas[0].state == .normal)
        check((try! persisted())!.configuration!.isDeleting == false)

        // SDK row deleted, final App transaction fails: restart finishes only
        // local cleanup and never projects a callable Scene or reuses the number.
        (scene, a, b, x, group) = try fixture()
        delete(scene)
        Network.didRemove = {
            SunSmartDataManager.shared.db!.commitHook { throw SceneConfigurationStore.Failure.persistence }
        }
        SyncExecutionSession.complete([1, 2])
        SunSmartDataManager.shared.db!.commitHook(nil); Network.didRemove = nil
        check(manager.scenes.isEmpty && (try! persisted())!.configuration!.isDeleting)
        check(try! store.nextAvailableNumber() == 2)
        try store.prepareDeletionRetries()
        check(manager.scenes.isEmpty && (try! persisted()) == nil)
        let completedBefore = successes, failedBefore = failures
        delete(scene)
        check(successes == completedBefore + 1 && failures == failedBefore,
              "same deletion completed by Sync preparation must finish old detail successfully")
        let unrelatedAbsent = Scene(scene.number); unrelatedAbsent.network = nil
        unrelatedAbsent.info.configuration = .init(kind: .devices, name: "Unrelated absent", isDeleting: true)
        check(try !SceneConfigurationStore.deletionAlreadyCompleted(scene: unrelatedAbsent, scope: scope),
              "arbitrary absence is not completion evidence")
        check(try !SceneConfigurationStore.deletionAlreadyCompleted(scene: scene,
            scope: .init(meshUUID: scope.meshUUID, networkID: "0002")), "completion cannot cross scope")
        let reused = Scene(scene.number); manager.scenes = [reused]
        reused.info.configuration = .init(kind: .devices, name: "Reused", isDeleting: true)
        try reused.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        check(reused.save())
        delete(scene)
        check(failures == failedBefore + 1 && manager.scenes.first === reused,
              "old completed operation must never remove a reused number")
        // A missing SDK row with actual pending cleanup must stay reserved.
        (scene, a, b, x, group) = try fixture()
        try store.prepareDeletion(scene: scene); manager.scenes = []
        try store.restoreSceneProjections()
        check(manager.scenes.isEmpty && (try! persisted())!.configuration!.pendingOperations.count == 2)
        check(try! store.nextAvailableNumber() == 2)
        let orphanConfiguration = scene.info.configuration!
        Scene.sdkSaveFails = true
        do { try store.prepareDeletionRetries(); fatalError("cleanup projection failure ignored") } catch {}
        check(manager.scenes.count == 1 && manager.scenes[0].info.projectionPending)
        check(manager.scenes[0].info.configuration == orphanConfiguration && (try! persisted())!.configuration == orphanConfiguration)
        Scene.sdkSaveFails = false
        try store.prepareDeletionRetries()
        try store.prepareDeletionRetries()
        check(manager.scenes.count == 1 && !manager.scenes[0].info.projectionPending)
        let retryScene = manager.scenes.first!
        check(retryScene.info.configuration == orphanConfiguration && !SceneCommandBuilder.isSelectable(scene: retryScene))
        check(a.getNodeSyncSceneDatas(scene: retryScene).isEmpty && a.getNodeNeedDeleteSceneDatas(scene: retryScene).count == 1)
        delete(retryScene); SyncExecutionSession.complete([1, 2])
        check(manager.scenes.isEmpty && (try! persisted()) == nil, "explicit orphan retry must finish cleanup and release")

        try memberAndPermanentDeletion()
        try restoreReceipts()
        try verifiedRestoreReentryFailures()
        try multiElementCleanup()
        try legacySecondaryAddress()
        try referencedTombstone()
        print("PASS whole deletion: A/B not X, durable offline/restart/unknown, references, residual groups, stale/failing ACK, stop gate, transaction rollback, SDK/App interrupted finalization")
    }
    static func incrementalSceneSave() throws {
        for mode in ["confirmed", "offlineConfirmed", "pending", "missingCache", "staleCache", "added", "readded", "ackWhileEditing", "scheduleConfirmed", "schedulePending"] {
            let (scene, a, b, _, firstGroup) = try fixture(devices: false)
            let secondGroup = Group(); manager.groups.append(secondGroup); b.group = secondGroup
            if mode != "added" && mode != "readded" { secondGroup.info.sceneExecuteDatas = [.init(sceneNumber: scene.number)] }
            if mode == "offlineConfirmed" { b.state = false }
            if mode == "missingCache" { b.sceneExecuteDatas = [] }
            if mode == "staleCache" { b.sceneExecuteDatas[0].lightness = 42 }
            let prior = ScenePendingOperation(identity: b.sceneConfigurationIdentity!, action: mode == "readded" ? .remove : .write)
            if ["pending", "ackWhileEditing", "readded"].contains(mode) { scene.info.configuration!.pendingOperations = [prior] }
            var schedule: Schedule?
            if mode.hasPrefix("schedule") {
                let item = Schedule(1, scene: scene)
                item.nodeSlots = [a, b].map { .init(identity: $0.timedSchedulerIdentity!, slot: 0, state: .assigned) }
                item.testSyncNeededAddresses = mode == "schedulePending" ? [b.primaryUnicastAddress] : []
                manager.schedules = [item]; schedule = item
            }
            let slots = schedule?.nodeSlots
            try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
            var edit = try SceneDraft(scene: scene)
            if mode == "ackWhileEditing" {
                let reply = try SceneMessageContext(scene: scene, node: b, action: .write)
                check(reply.apply(node: b, successful: true))
            }
            var parameters = edit.groupParameters
            parameters[firstGroup.address.address] = .init(isOn: true, lightness: 12000, cct: 3200)
            parameters[secondGroup.address.address] = .init(isOn: true, lightness: 65535, cct: 4500)
            try edit.setGroupParameters(parameters)
            _ = try store.commit(draft: edit, expectedRevision: edit.revision)
            let needsWrite = ["pending", "missingCache", "staleCache", "added", "readded"].contains(mode)
            let expectedIdentities = Set((needsWrite ? [a, b] : [a]).map { $0.sceneConfigurationIdentity! })
            check(Set(scene.info.configuration!.pendingOperations.map(\.identity)) == expectedIdentities, "incremental intent: \(mode)")
            if mode == "pending" { check(scene.info.configuration!.pendingOperations.contains(prior), "unchanged pending write must retain generation") }
            if mode == "readded" { check(!scene.info.configuration!.pendingOperations.contains(prior), "re-add must replace old remove ownership") }
            check(schedule?.nodeSlots == slots, "unchanged Scheduler ownership must remain stable")
            let committed = scene.info.configuration
            scene.info = try persisted()!
            check(scene.info.configuration == committed, "incremental intent survives reload")
            let writes = SyncDevicesSectionModel(title: "write"), removals = SyncDevicesSectionModel(title: "remove")
            SyncSceneScheduleTaskBuilder().appendScene(to: writes, removal: removals, scene: scene)
            let needsTask = needsWrite || mode == "schedulePending"
            let expectedGroups = Set((needsTask ? [firstGroup, secondGroup] : [firstGroup]).map { $0.address.address })
            guard Set(writes.groups.map(\.address)) == expectedGroups else {
                print("FAIL changing one group must not schedule an unchanged confirmed group"); exit(1)
            }
            check(b.getNodeSyncSceneDatas(scene: scene).isEmpty == !needsTask)
            check(a.getNodeSyncSceneDatas(scene: scene).count == 1)
            check(removals.groups.isEmpty && removals.devices.isEmpty)
        }
        do {
            let (scene, a, b, _, firstGroup) = try fixture(devices: false)
            let secondGroup = Group(); manager.groups.append(secondGroup); b.group = secondGroup
            secondGroup.info.sceneExecuteDatas = [.init(sceneNumber: scene.number)]
            var edit = try SceneDraft(scene: scene)
            try edit.setGroupParameters([secondGroup.address.address: edit.groupParameters[secondGroup.address.address]!])
            _ = try store.commit(draft: edit, expectedRevision: edit.revision)
            check(scene.info.configuration!.pendingOperations.count == 1)
            check(scene.info.configuration!.pendingOperations.first?.identity == a.sceneConfigurationIdentity
                && scene.info.configuration!.pendingOperations.first?.action == .remove)
            let writes = SyncDevicesSectionModel(title: "write"), removes = SyncDevicesSectionModel(title: "remove")
            SyncSceneScheduleTaskBuilder().appendScene(to: writes, removal: removes, scene: scene)
            check(writes.groups.isEmpty && writes.devices.isEmpty, "removing one group must not rewrite the retained group")
            check(removes.groups.map(\.address) == [firstGroup.address.address])
        }
        do {
            let (scene, a, b, _, _) = try fixture()
            for node in [a, b] {
                let confirmed = try SceneMessageContext(scene: scene, node: node, action: .write)
                check(confirmed.apply(node: node, successful: true))
            }
            var edit = try SceneDraft(scene: scene)
            var members = edit.deviceMembers
            members[members.firstIndex(where: { $0.identity == a.sceneConfigurationIdentity })!].parameters.lightness = 2500
            try edit.setDeviceMembers(members)
            _ = try store.commit(draft: edit, expectedRevision: edit.revision)
            check(scene.info.configuration!.pendingOperations.map(\.identity) == [a.sceneConfigurationIdentity!])
            check(b.getNodeSyncSceneDatas(scene: scene).isEmpty, "direct device mode must use the same incremental rule")
        }
        // A deletion may complete after Settings opens. Only current durable
        // cleanup can survive another member's edit, never the stale draft copy.
        for cleanupMode in ["pending", "finishedRoom", "finishedFull", "finishedUnknown"] {
            let deletionFinished = cleanupMode != "pending"
            let (scene, a, b, _, _) = try fixture()
            scene.info.configuration!.deviceMembers.removeAll { $0.identity == b.sceneConfigurationIdentity }
            let pending = ScenePendingOperation(identity: b.sceneConfigurationIdentity!, action: .remove)
            scene.info.configuration!.pendingOperations = [pending]
            try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
            var edit = try SceneDraft(scene: scene)
            if deletionFinished {
                let reply = try SceneMessageContext(scene: scene, node: b, action: .remove)
                check(reply.apply(node: b, successful: true))
                if cleanupMode == "finishedFull" { b.sceneSetupModel!.parentElement!.observedSceneRegister = Set(2...17) }
                if cleanupMode == "finishedUnknown" { b.sceneSetupModel!.parentElement!.observedSceneRegister = nil }
            }
            try edit.setDeviceMembers([.init(identity: a.sceneConfigurationIdentity!, parameters: .init(isOn: true, lightness: 2500, cct: 4000))])
            let preflight = try SceneTargetResolver.resolve(draft: edit)
            if deletionFinished {
                guard !preflight.reservesScene(on: b) else {
                    print("FAIL completed removal must not reserve capacity in draft preflight"); exit(1)
                }
                check(!SceneCapacity.nodesRequiringRead(sceneSnapshot: preflight).contains(b))
            }
            _ = try store.commit(draft: edit, expectedRevision: edit.revision)
            check(scene.info.configuration!.pendingOperations.contains(pending) == !deletionFinished, "finished deletion must not be resurrected")
            check(b.getNodeNeedDeleteSceneDatas(scene: scene).isEmpty == deletionFinished)
        }
        print("PASS incremental save: changed group only, pending/cache/new/readded targets, ACK progress, persisted reload, Scheduler ownership and latest cleanup")
    }

    static func originalIdentity(_ node: Node) -> TimedSchedulerNodeIdentity {
        .init(nodeUUID: node.uuid.uuidString, unicastAddress: node.primaryUnicastAddress.hex, deviceKeyFingerprint: String(repeating: "A", count: 64))
    }
    static func memberAndPermanentDeletion() throws {
        let (scene, a, b, _, group) = try fixture()
        let initial = try scene.info.configuration!.normalized()
        a.group = nil; b.group = Group(); a.groupState = .exitFailure
        check(try! SceneTargetResolver.resolve(scene: scene).targets.count == 2)
        check(a.getNodeNeedDeleteSceneDatas(scene: scene).isEmpty, "normal group exit must not delete devices Scene")
        check(try! scene.info.configuration!.normalized() == initial && group.info.sceneExecuteDatas.isEmpty)
        // Only the confirmed old full identity is removed; a new key at the same
        // address must neither inherit old membership nor authorize its deletion.
        b.fingerprint = String(repeating: "B", count: 64)
        check(try! SceneTargetResolver.resolve(scene: scene).unresolved.count == 1)
        try SceneConfigurationStore.removeConfirmedIdentities([b.timedSchedulerIdentity!], scope: scope)
        check((try! persisted())!.configuration == initial)
        try SceneConfigurationStore.removeConfirmedIdentities([originalIdentity(b)], scope: scope)
        scene.info = try persisted()!
        check(scene.info.configuration!.deviceMembers.count == 1)
        var draft = try SceneDraft(scene: scene)
        try draft.setDeviceMembers([])
        guard case .ready = try store.commit(draft: draft, expectedRevision: draft.revision) else { fatalError() }
        var pending = try SceneDraft(scene: scene)
        do { try pending.switchKind(to: .groups); fatalError("last offline member still reserves its identity") } catch {}
        check(try! store.nextAvailableNumber() == 2)
        let cleanup = scene.getDeleteMessageHandles(node: a).first!
        check(!a.applyMessageHandle(cleanup, isSuccess: false))
        a.sceneSetupModel!.parentElement!.observedSceneRegister = []
        check(a.applyMessageHandle(cleanup))
        var clean = try SceneDraft(scene: scene); try clean.switchKind(to: .groups)
        check(clean.kind == .groups)
        print("PASS member/permanent: group exit isolation, changed-key rejection, exact old identity cleanup, last offline member type/number reservation, confirmed type switch")
    }
    static func restoreReceipts() throws {
        var (scene, a, _, _, _) = try fixture()
        a.fingerprint = a.fingerprint.lowercased()
        let old = try SceneConfiguration.identity(a.timedSchedulerIdentity!)
        let previous = try SceneMessageContext(scene: scene, node: a, action: .write)
        let receiptID = try store.prepareRestore(oldNode: a)!
        let prepared = SpaceConfigurationSafety.recovery.sceneRestoreReceipts!
        let decoded = try JSONDecoder().decode([SceneRestoreReceipt].self, from: prepared)
        check(decoded.count == 1 && decoded[0].stage == .prepared && decoded[0].oldIdentity == old)
        check(try! store.prepareRestore(oldNode: a) == receiptID, "prepared receipt must be reused")
        check(try! store.pendingRestoreConfirmations(nodes: [a]).isEmpty, "case alone must not offer identity migration")
        // SDK has persisted a new key, but App callback was never delivered.
        a.fingerprint = String(repeating: "b", count: 64)
        _ = try store.resumeVerifiedRestores()
        check(scene.info.configuration!.deviceMembers.contains { $0.identity == old }, "prepared-only cannot infer a new key")
        check(try! store.pendingRestoreConfirmations(nodes: [a]).count == 1)
        var result: Bool?
        SceneRestoreConfirmation.presentIfNeeded(nodes: [a]) { result = $0 }
        SRAlertView.shown[0].invoke()
        check(result == false && SpaceConfigurationSafety.recovery.sceneRestoreReceipts == prepared, "cancel must preserve exact receipt and intent")
        // The human's confirmation is tied to the identity shown, not an address.
        SceneRestoreConfirmation.presentIfNeeded(nodes: [a]) { result = $0 }
        a.fingerprint = String(repeating: "c", count: 64)
        SRAlertView.shown[1].invoke()
        check(result == false && SpaceConfigurationSafety.recovery.sceneRestoreReceipts == prepared)
        a.fingerprint = String(repeating: "b", count: 64)
        SceneRestoreConfirmation.presentIfNeeded(nodes: [a]) { result = $0 }
        SRAlertView.shown[1].invoke()
        check(result == true)
        check(scene.info.configuration!.deviceMembers.contains { $0.identity == (try! SceneConfiguration.identity(a.timedSchedulerIdentity!)) })
        check(scene.info.configuration!.pendingOperations.contains { $0.identity == (try! SceneConfiguration.identity(a.timedSchedulerIdentity!)) && $0.action == .write })
        check(!previous.apply(node: a, successful: true), "old ACK cannot confirm migrated identity")
        let applied = scene.info.configuration!
        _ = try store.resumeVerifiedRestores()
        check(scene.info.configuration == applied, "applied receipt must not regenerate tasks")
        // Verified receipt survives an App commit failure and process re-entry.
        (scene, a, _, _, _) = try fixture()
        a.fingerprint = a.fingerprint.lowercased()
        let sourceIdentity = try SceneConfiguration.identity(a.timedSchedulerIdentity!)
        let id = try store.prepareRestore(oldNode: a)!
        a.fingerprint = String(repeating: "b", count: 64)
        SunSmartDataManager.shared.db!.commitHook { throw SceneConfigurationStore.Failure.persistence }
        do { try store.verifyRestore(receiptID: id, newNode: a); fatalError("injected App failure was ignored") } catch {}
        SunSmartDataManager.shared.db!.commitHook(nil)
        let verified = try JSONDecoder().decode([SceneRestoreReceipt].self, from: SpaceConfigurationSafety.recovery.sceneRestoreReceipts!)
        check(verified[0].stage == .verified)
        scene.info = try persisted()!
        a.fingerprint = String(repeating: "c", count: 64)
        _ = try store.resumeVerifiedRestores()
        check(scene.info.configuration!.deviceMembers.contains { $0.identity == sourceIdentity }, "different new identity cannot consume verified receipt")
        var unresolvedAccepted: Bool?
        SceneRestoreConfirmation.presentIfNeeded(nodes: [a]) { unresolvedAccepted = $0 }
        check(unresolvedAccepted == false, "unresolved verified identity cannot be treated as an empty prepared list")
        a.fingerprint = String(repeating: "b", count: 64)
        // User already removed the member after prepare; retain remove intent,
        // never resurrect the saved member from a receipt/snapshot.
        scene.info.configuration!.deviceMembers.removeAll { $0.identity == sourceIdentity }
        scene.info.configuration!.pendingOperations.append(.init(identity: sourceIdentity, action: .remove))
        try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        _ = try store.resumeVerifiedRestores()
        check(!scene.info.configuration!.deviceMembers.contains { $0.identity == (try! SceneConfiguration.identity(a.timedSchedulerIdentity!)) })
        check(scene.info.configuration!.pendingOperations.contains { $0.identity == (try! SceneConfiguration.identity(a.timedSchedulerIdentity!)) && $0.action == .remove })
        let migrated = scene.info.configuration!
        // Scope/generation change, old journal and corrupt payload fail closed.
        // Actual applied-receipt write failure is injected below, not simulated
        // by downgrading a successfully completed receipt.
        SpaceConfigurationSafety.recovery.sceneRestoreReceipts = try JSONEncoder().encode(verified)
        SpaceConfigurationSafety.recovery.generation = UUID()
        _ = try store.resumeVerifiedRestores()
        check(scene.info.configuration == migrated)
        SpaceConfigurationSafety.recovery.sceneRestoreReceipts = nil
        _ = try store.resumeVerifiedRestores()
        check(try! store.pendingRestoreConfirmations().isEmpty, "ordinary new provisioning has no receipt")
        SpaceConfigurationSafety.recovery.sceneRestoreReceipts = Data("broken".utf8)
        do { _ = try store.resumeVerifiedRestores(); fatalError("corrupt receipt ignored") } catch {}
        print("PASS Restore: prepared/verified/applied restart, manual cancel/confirm, captured new identity, old ACK rejection, post-prepare removal, idempotent replay, changed generation and corrupt receipt")
    }

    /// Both pages call this exact production presentation/preparation entry.
    /// Do not substitute direct replay or manually downgrade a completed receipt.
    static func verifiedRestoreReentryFailures() throws {
        var failures: [String] = []
        func expect(_ value: Bool, _ description: String) { if !value { failures.append(description) } }
        for appliedReceiptFailure in [false, true] {
            for action in [ScenePendingOperation.Action.write, .remove] {
                let failureCount = failures.count
                let (scene, node, _, _, _) = try fixture()
                let oldIdentity = node.timedSchedulerIdentity!
                if action == .remove {
                    scene.info.configuration!.deviceMembers.removeAll { $0.identity == oldIdentity }
                    scene.info.configuration!.pendingOperations.append(.init(identity: oldIdentity, action: .remove))
                    try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
                }
                let oldACK = try SceneMessageContext(scene: scene, node: node, action: action)
                let receiptID = try store.prepareRestore(oldNode: node)!
                node.fingerprint = String(repeating: "b", count: 64)
                let newIdentity = try SceneConfiguration.identity(node.timedSchedulerIdentity!)
                let db = SunSmartDataManager.shared.db!
                var commitFailures = 0
                if appliedReceiptFailure { SpaceConfigurationSafety.failAppliedReceiptWrite = true }
                else { db.commitHook { commitFailures += 1; throw SceneConfigurationStore.Failure.persistence } }
                var threw = false
                do { try store.verifyRestore(receiptID: receiptID, newNode: node) } catch { threw = true }
                let label = "\(appliedReceiptFailure ? "applied receipt" : "App COMMIT") / \(action)"
                expect(threw, label + " must expose injected failure")
                let receipts = try JSONDecoder().decode([SceneRestoreReceipt].self, from: SpaceConfigurationSafety.recovery.sceneRestoreReceipts!)
                expect(receipts.first?.stage == .verified, label + " must retain verified evidence")
                let firstDatabaseValue = try persisted()!.configuration!
                expect(firstDatabaseValue.pendingOperations.contains { $0.identity == newIdentity } == appliedReceiptFailure,
                       label + " failed at the wrong boundary")
                if appliedReceiptFailure {
                    expect(scene.info.configuration == firstDatabaseValue, label + " receipt failure left committed identity stale in memory")
                }
                var accepted: Bool?
                SceneRestoreConfirmation.presentIfNeeded(nodes: [node]) { accepted = $0 }
                expect(accepted == false, label + " persistent failure incorrectly accepted shared re-entry")
                if !appliedReceiptFailure { expect(commitFailures >= 2, label + " shared re-entry did not attempt real App replay") }
                db.commitHook(nil); SpaceConfigurationSafety.failAppliedReceiptWrite = false
                // The load callback may finish before its Space VC is available.
                // It must load projections and retain verified work for re-entry.
                SpaceViewController.available = false
                expect(try store.resumeVerifiedRestores(), label + " unavailable UI owner lost verified intent")
                try store.restoreSceneProjections()
                expect(try JSONDecoder().decode([SceneRestoreReceipt].self, from: SpaceConfigurationSafety.recovery.sceneRestoreReceipts!).first?.stage == .verified,
                    label + " load without active Space changed authorization evidence")
                SpaceViewController.available = true
                accepted = nil
                SceneRestoreConfirmation.presentIfNeeded(nodes: [node]) { accepted = $0 }
                let recoveredReceipts = try JSONDecoder().decode([SceneRestoreReceipt].self, from: SpaceConfigurationSafety.recovery.sceneRestoreReceipts!)
                let recovered = try persisted()!.configuration!
                expect(accepted == true && recoveredReceipts.first?.stage == .applied,
                       label + " shared re-entry did not finish verified receipt")
                expect(scene.info.configuration == recovered, label + " memory does not match committed App rows")
                expect(recovered.pendingOperations.contains { $0.identity == newIdentity && $0.action == action },
                       label + " lost restored write/remove intent")
                expect(!recovered.pendingOperations.contains { $0.identity == oldIdentity }, label + " retained obsolete identity")
                expect(!oldACK.apply(node: node, successful: true), label + " accepted obsolete ACK")
                if appliedReceiptFailure {
                    expect(recovered == firstDatabaseValue, label + " regenerated revision/generation after already committed migration")
                }
                if action == .write {
                    let targets = node.getNodeSyncSceneDatas(scene: scene)
                    let handles = targets.first.map { scene.getSyncMessageHandles(node: node, data: $0.data) } ?? []
                    expect(handles.contains { $0.message is SceneStore }, label + " cannot build restored write")
                } else {
                    expect(node.getNodeNeedDeleteSceneDatas(scene: scene).count == 1
                        && scene.getDeleteMessageHandles(node: node).contains { $0.message is SceneDelete }, label + " cannot build restored remove")
                }
                accepted = nil
                SceneRestoreConfirmation.presentIfNeeded(nodes: [node]) { accepted = $0 }
                expect(accepted == true && scene.info.configuration == recovered
                    && (try! persisted()!.configuration) == recovered, label + " repeated re-entry is not idempotent")
                if failures.count == failureCount {
                    print("PASS verified re-entry \(label): failure blocked, retry applied, memory/DB aligned, old ACK rejected, task built, repeated entry stable")
                }
            }
        }
        check(failures.isEmpty, failures.joined(separator: "\n"))
        print("PASS verified Restore re-entry: production shared page entry, real COMMIT/applied-receipt failures, persistent failure gate, memory/readback, stable revision/generation, old ACK and write/remove plans")
    }

    static func multiElementCleanup() throws {
        let (scene, a, _, _, _) = try fixture()
        let second = Model(); second.parentElement!.observedSceneRegister = [scene.number]
        a.additionalSceneSetupModels = [second]
        try store.prepareDeletion(scene: scene)
        let handles = scene.getDeleteMessageHandles(node: a)
        check(handles.count == 2)
        let run = SyncExecutionSession(type: .scene(scene), reSync: false, environment: .init())
        a.sceneSetupModel!.parentElement!.observedSceneRegister = []
        check(!run.applySceneBatch(handles, messageHandles: handles), "other Element still registered cannot release identity")
        check(scene.info.configuration!.pendingOperations.count == 2)
        second.parentElement!.observedSceneRegister = []
        check(run.applySceneBatch(handles, messageHandles: handles), "one batch must commit the Node once after all Elements succeed")
        check(scene.info.configuration!.pendingOperations.count == 1)
        check(!run.applySceneBatch(handles, messageHandles: handles), "replayed old batch cannot consume a new generation")
        print("PASS multi-Element: production SyncExecutionSession result branch, all-model evidence and one generation commit")
    }

    static func legacySecondaryAddress() throws {
        let (scene, _, _, x, _) = try fixture(devices: false)
        scene.addresses = [4]
        x.addressAliases = [4]
        x.sceneSetupModel!.parentElement!.observedSceneRegister = nil
        try store.prepareDeletion(scene: scene)
        check(scene.info.configuration!.pendingOperations.contains { $0.identity == x.timedSchedulerIdentity! },
            "Legacy secondary Element address must resolve to its original Node even without cached/register data")
        print("PASS legacy secondary address: unresolved cache retains the registered Node cleanup identity")
    }

    static func referencedTombstone() throws {
        let (scene, _, _, _, _) = try fixture()
        try store.prepareDeletion(scene: scene)
        scene.info.configuration!.pendingOperations = []
        try scene.info.saveConfiguration(meshUUID: scope.meshUUID, subnetworkId: scope.networkID)
        manager.schedules = [Schedule(9, scene: scene)]
        do { try store.finishDeletion(info: scene.info, scope: scope); fatalError("Referenced tombstone must retain its record and number") } catch {}
        check(manager.scenes.count == 1 && (try! persisted()) != nil)
        // A retained reference cannot prevent entering the very Sync page that
        // clears Scheduler references. Neither load nor preparation releases it.
        try store.restoreSceneProjections()
        try store.prepareDeletionRetries()
        check(manager.scenes.count == 1 && (try! persisted()) != nil)
        manager.schedules = []
        FixtureReferences.switches = [.init(sceneANumber: scene.number)]
        do { try store.finishDeletion(info: scene.info, scope: scope); fatalError("Switch reference bypassed finalization guard") } catch {}
        FixtureReferences.switches = []
        try store.finishDeletion(info: scene.info, scope: scope)
        check(manager.scenes.isEmpty && (try! persisted()) == nil)
        print("PASS finalization references: interrupted/imported tombstone cannot bypass Schedule/Switch protection")
    }

}
