import Foundation

// Unrelated storage/UI boundaries. The deletion context, journal model and
// topology commit/repair policy are compiled from their production sources.
final class Schedule {
    let id = UUID().uuidString
    var groupAddresses: [Address] = [], needDeleteGroupAddresses: [Address] = []
    var sceneNumber: UInt16?
    var needDeleteGroups: [Group] { MeshNetworkManager.instance.groups.filter { needDeleteGroupAddresses.contains($0.address.address) } }
    func needsSync(on node: Node, contextGroup: Group) -> Bool { !needDeleteGroupAddresses.contains(contextGroup.address.address) }
    func needsDelete(from node: Node, contextGroup: Group) -> Bool { needDeleteGroupAddresses.contains(contextGroup.address.address) }
    var nodeAddresses: [Address] = [], needDeleteNodeAddresses: [Address] = []
    static var stored: [String: [Schedule]] = [:]
    static func load(meshUUID: String, meshNetworkId: String) -> [Schedule] { stored[meshUUID + meshNetworkId] ?? [] }
    func save(meshUUID: String, meshNetworkId: String) -> Bool { true }
}
final class DeviceSwitchData {
    var proxyNodeAddress: Address?, deleteProxyNodeAddress: Address?
    var enOceanMacAddress: String?, enOceanSecurityKey: String?
    static func load(meshUUID: String, meshNetworkId: String) -> [DeviceSwitchData] { [] }
    func save(meshUUID: String, networkId: String) -> Bool { true }
}
final class DeviceDongleData {
    var bindNodeAddress: Address?
    static func load(meshUUID: String, meshNetworkId: String) -> [DeviceDongleData] { [] }
    func save(meshUUID: String, networkId: String) -> Bool { true }
}
enum KineticSwitchBindingPolicy {
    struct Decision { let clearsCurrent: Bool, clearsPendingRemoval: Bool, clearsCredentials: Bool }
    static func referenceCleanupDecision(node: Address, current: Address?, pendingRemoval: Address?) -> Decision {
        .init(clearsCurrent: node == current, clearsPendingRemoval: node == pendingRemoval, clearsCredentials: node == current)
    }
}
enum GatewayModel {
    static var deletions: [String] = []
    static func delete(siteId: String, macAddress: String) { deletions.append(siteId + macAddress) }
}
struct MeshDistributionData {
    var distributionAddress: Address = 0
    static func load(meshUUID: String, meshNetworkId: String, productId: UInt16) -> Self? { nil }
    func delete(meshUUID: String, networkId: String, productId: UInt16) {}
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
}
enum SpaceMeshKeyStore {
    enum Issue: Error { case missing }
    static var missing = false
    static func export(network: MeshNetwork, networkId: String) -> Result<Void, Issue> {
        missing ? .failure(.missing) : .success(())
    }
}
enum XWHUDManager {
    static func showCustomHUD(withMessage: String, isWindow: Bool) {}
    static func hide() {}
    static var lastMessage: String?
    static func showErrorTipHUD(_ message: String) { lastMessage = message }
    static func showSuccessTipHUD(_ message: String) { lastMessage = message }
}

extension ScopedImportTests {
    static func activate(_ fixture: Fixture) {
        MeshNetworkManager.instance.meshNetwork = fixture.network
        MeshNetworkManager.instance.currentNetworkKey.networkId = fixture.space.meshNetworkId
    }

    static func testDeviceDeletionRecovery() throws {
        defer { SpaceConfigurationSafety.testDefaults.removePersistentDomain(forName: SpaceConfigurationSafety.defaultsSuite) }
        // Batch Reset removes all Nodes before callbacks. Every confirmed address
        // must be cleaned in one target snapshot; the Groups/Profiles stay intact.
        let all = try fixture(networkId: "DELETE-ALL")
        activate(all)
        let contexts = all.nodes.map { DevicePermanentDeletionContext(node: $0, space: all.space) }
        require(contexts.allSatisfy(\.isPrepared), "record all deletion intents before Reset")
        require(SpaceConfigurationSafety.hasPendingDeletionCleanup(all.space), "prepared deletion blocks incomplete uploads")
        all.nodes.forEach { all.network.remove(node: $0) }
        contexts[0].cancel()
        require(contexts[0].isPrepared, "timeout cancellation must retain an already removed Node's intent")
        require(contexts[0].commit() != nil, "batch cleanup must include every already removed Node")
        _ = contexts[1].commit()
        require(!SpaceConfigurationSafety.hasPendingDeletionCleanup(all.space), "batch must finish cleanup")
        require(all.space.triggerZones.allSatisfy { $0.items.isEmpty }, "all Space Zone members removed")
        require(all.group.info.proximityLightingPath!.paths.allSatisfy { $0.items.allSatisfy { $0.address == nil } }, "Path slots preserved and cleared")
        require(all.network.groups.count == 1 && all.group.info.profile.type == .proximityLighting, "deletion retains Group and Profile")
        require(all.space.deviceCount == 0 && all.space.luminairesCount == 0, "zero node counts persisted")
        let timestamp = all.space.lastUpdate
        _ = contexts[0].commit()
        require(all.space.lastUpdate == timestamp, "repeated completion is idempotent")

        let scheduled = try fixture(networkId: "DELETE-SCHEDULE-CACHE")
        let active = MeshNetwork(scheduled.network.uuid)
        let activeGroup = Group(scheduled.group.address.address)
        activeGroup.subNetworkId = scheduled.space.meshNetworkId; activeGroup.network = active
        active.groups = [activeGroup]; active.nodes = scheduled.nodes
        let groupSchedule = Schedule(), sceneSchedule = Schedule(), pendingSchedule = Schedule(), unrelatedSchedule = Schedule()
        groupSchedule.groupAddresses = [activeGroup.address.address]
        sceneSchedule.sceneNumber = 7
        pendingSchedule.needDeleteGroupAddresses = [activeGroup.address.address]
        unrelatedSchedule.groupAddresses = [0xC123]
        scheduled.group.info.sceneExecuteDatas = [.init(sceneNumber: 7)]
        activeGroup.info.bindSchedules = [groupSchedule, sceneSchedule, pendingSchedule]
        Schedule.stored[scheduled.space.meshUUID + scheduled.space.meshNetworkId] = [groupSchedule, sceneSchedule, pendingSchedule, unrelatedSchedule]
        MeshNetworkManager.instance.meshNetwork = active
        MeshNetworkManager.instance.currentNetworkKey.networkId = scheduled.space.meshNetworkId
        let scheduleContext = DevicePermanentDeletionContext(node: scheduled.nodes[0], space: scheduled.space)
        scheduled.network.remove(node: scheduled.nodes[0]); active.nodes.removeFirst()
        require(scheduleContext.commit() != nil, "deletion with detached persisted GroupInfo completes")
        require(activeGroup.info.bindSchedules.map(\.id) == [groupSchedule, sceneSchedule, pendingSchedule].map(\.id), "rebuild Group, Scene and pending-delete bindings only")
        require(MeshNetworkManager.instance.schedules.count == 4, "manager and binding caches use the same loaded schedules")
        // These UI consumers intentionally read active members. Keep their
        // reads separate from the suite's scoped topology adapter invariant.
        let lifecycleMemberReads = Group.globalMemberReads
        require(activeGroup.getNeedSyncScheduleDataNodes(groupSchedule).syncNodes.count == 1, "remaining Group schedule task survives deletion")
        require(activeGroup.getNeedSyncScheduleDataNodes(sceneSchedule).syncNodes.count == 1, "remaining Scene schedule task survives deletion")
        require(activeGroup.getNeedSyncScheduleDataNodes(pendingSchedule).deleteNodes.count == 1, "pending schedule deletion task survives")
        require(activeGroup.getNeedSyncScheduleDataNodes(unrelatedSchedule).syncNodes.isEmpty, "unrelated schedule is not bound")
        Group.globalMemberReads = lifecycleMemberReads
        activate(all)
        var pendingUpload = try SpaceConfigurationSafety.deletionJournal(all.space)
        require(pendingUpload.entries.allSatisfy { $0.stage == .cleaned }, "cleaned receipts remain until cloud confirmation")
        pendingUpload.confirmUpload(timestamp: timestamp - 1)
        require(!pendingUpload.entries.isEmpty, "old upload completion cannot acknowledge a newer deletion")
        pendingUpload.confirmUpload(timestamp: timestamp)
        require(pendingUpload.entries.isEmpty, "matching verified upload acknowledges deletion")
        var unfinished = try SpaceConfigurationSafety.deletionJournal(all.space)
        unfinished.entries[0].stage = .removed
        unfinished.confirmUpload(timestamp: timestamp + 100)
        require(unfinished.entries.count == 1, "verified upload never acknowledges unfinished cleanup")
        let originalJournal = try SpaceConfigurationSafety.deletionJournal(all.space)
        for (uuid, address) in [(originalJournal.entries[0].nodeUUID, "0070"), ("new-device", "0002")] {
            _ = SpaceConfigurationSafety.updateDeletionJournal(all.space) { $0 = originalJournal }
            SpaceConfigurationSafety.confirmLocalChanges(all.space, payload: ["updateTimestamp": timestamp + 1,
                "nodes": [["uuid": uuid, "unicastAddress": address]]])
            require(!SpaceConfigurationSafety.preservesLocalChanges(all.space), "verified re-provisioning or address reuse supersedes completed deletion")
        }
        _ = SpaceConfigurationSafety.updateDeletionJournal(all.space) { $0 = originalJournal }
        require(SpaceConfigurationSafety.preservesLocalChanges(all.space), "a stale remote cannot replace a pending deletion")
        SpaceConfigurationSafety.confirmLocalChanges(all.space, payload: ["updateTimestamp": timestamp - 1, "nodes": [[String: Any]]()])
        require(SpaceConfigurationSafety.preservesLocalChanges(all.space), "an old readback cannot release import protection")
        SpaceConfigurationSafety.confirmLocalChanges(all.space, payload: ["updateTimestamp": timestamp, "nodes": [[String: Any]]()])
        require(!SpaceConfigurationSafety.preservesLocalChanges(all.space), "verified empty readback releases import protection")
        let receiptKey = "spaceConfigurationLocalRecoveryPending." + all.space.id
        SpaceConfigurationSafety.testDefaults.set(timestamp + 10, forKey: receiptKey)
        SpaceConfigurationSafety.confirmLocalChanges(all.space, payload: ["updateTimestamp": timestamp, "nodes": [[String: Any]]()])
        require(SpaceConfigurationSafety.preservesLocalChanges(all.space), "a newer reviewed recovery survives an old upload callback")
        SpaceConfigurationSafety.confirmLocalChanges(all.space, payload: ["updateTimestamp": timestamp + 10, "nodes": [[String: Any]]()])
        require(!SpaceConfigurationSafety.preservesLocalChanges(all.space), "recovery receipt clears only at its verified generation")

        // Failed Reset cancellation retains the Node and its valid topology.
        let partial = try fixture(networkId: "PARTIAL")
        activate(partial)
        let succeeded = DevicePermanentDeletionContext(node: partial.nodes[0])
        let failed = DevicePermanentDeletionContext(node: partial.nodes[1])
        failed.cancel()
        partial.network.remove(node: partial.nodes[0])
        require(succeeded.commit() != nil, "partial success commits only the absent Node")
        require(partial.space.triggerZones[1].items.map(\.deviceAddress) == [5], "failed Node retains membership")
        require(failed.prepareForForceRemoval(), "force removal creates a new durable intent")
        _ = failed.forceRemove()
        require(partial.network.nodes.isEmpty && !SpaceConfigurationSafety.hasPendingDeletionCleanup(partial.space), "force removal finishes remaining cleanup")

        // A protection barrier must not reject an exact, confirmed deletion.
        let protected = try fixture(networkId: "PROTECTED")
        activate(protected)
        let protectedContexts = protected.nodes.map { DevicePermanentDeletionContext(node: $0) }
        protected.nodes.forEach { protected.network.remove(node: $0) }
        SpaceConfigurationSafety.blocked = true
        require(protectedContexts[0].commit() != nil, "confirmed deletion can complete under remote-review protection")
        SpaceConfigurationSafety.blocked = false

        // Failure after physical deletion is replayable, without the old Node or
        // its weak network link and while another Site with identical IDs is active.
        let interrupted = try fixture(networkId: "SAME-NETWORK-ID")
        activate(interrupted)
        var interruptedContext: DevicePermanentDeletionContext? = DevicePermanentDeletionContext(node: interrupted.nodes[0])
        interrupted.network.remove(node: interrupted.nodes[0])
        SunSmartDataManager.shared.failTransactions = true
        require(interruptedContext!.commit() == nil, "persistence failure must retain cleanup")
        DevicePermanentDeletionContext.showCompletion(space: interrupted.space)
        require(XWHUDManager.lastMessage == "configuration_deletion_cleanup_pending", "failed cleanup must not show Done")
        interruptedContext = nil
        let other = try fixture(networkId: "SAME-NETWORK-ID")
        activate(other)
        SunSmartDataManager.shared.failTransactions = false
        DevicePermanentDeletionContext.resume(space: interrupted.space)
        require(!SpaceConfigurationSafety.hasPendingDeletionCleanup(interrupted.space), "restart retries the removed Node")
        require(other.network.nodes.count == 2 && other.space.triggerZones[1].items.count == 2, "same UUID/address/Network ID in another Site remains unchanged")
        require(interrupted.space.triggerZones[1].items.map(\.deviceAddress) == [5], "cleanup targets the original Site")

        // Journal failure occurs before Reset and must not authorize removal.
        activate(other)
        SpaceConfigurationSafety.journalWritesFail = true
        let unavailable = DevicePermanentDeletionContext(node: other.nodes[0])
        require(!unavailable.isPrepared && unavailable.forceRemove() == nil && other.network.nodes.count == 2,
                "unrecorded deletion cannot remove a Node")
        SpaceConfigurationSafety.journalWritesFail = false

        // Reviewed historical cleanup is separate from authoritative import.
        let historical = try fixture(networkId: "HISTORICAL")
        historical.network.nodes = []
        activate(historical)
        let repair = ProximityLightingLifecycleCoordinator.begin(space: historical.space).prepare()
        SpaceConfigurationSafety.blocked = true
        require(repair.normalized.canReviewReferenceRepair, "dangling references can be reviewed")
        require(ProximityLightingLifecycleCoordinator.commit(repair, isImportApplication: true) == nil,
                "ordinary cloud import still cannot drop references")
        SpaceConfigurationSafety.pendingImport = true
        require(ProximityLightingLifecycleCoordinator.commit(repair, reviewedReferenceSnapshot: repair.sourceSnapshot) == nil,
                "unfinished imports cannot be bypassed by repair")
        SpaceConfigurationSafety.pendingImport = false
        require(ProximityLightingLifecycleCoordinator.commit(repair, reviewedReferenceSnapshot: repair.sourceSnapshot) != nil,
                "explicitly reviewed repair can normalize local references")
        SpaceConfigurationSafety.blocked = false

        // Intent cleanup must never silently repair unrelated stale references.
        let unrelated = try fixture(networkId: "UNRELATED")
        activate(unrelated)
        unrelated.group.info.proximityLightingPath!.paths[0].items.append(.init(address: 99))
        let unrelatedContext = DevicePermanentDeletionContext(node: unrelated.nodes[0])
        unrelated.network.remove(node: unrelated.nodes[0])
        require(unrelatedContext.commit() != nil, "unrelated dangling reference must not block scoped deletion")
        require(unrelated.group.info.proximityLightingPath!.paths[0].items.last!.address == 99, "unreviewed reference remains for review")

        let offline = try fixture(networkId: "OFFLINE-DELETION")
        activate(other)
        let offlineContext = DevicePermanentDeletionContext(node: offline.nodes[0], space: offline.space)
        require(offlineContext.isPrepared, "local deletion must not require the active Mesh network")
        _ = offlineContext.forceRemove()
        require(offline.network.nodes.count == 1 && other.network.nodes.count == 2,
                "force removal targets the selected Space while another network is active")

        require(offlineContext.outcome == .cleaned && !offlineContext.canReset, "local result is independent of communication")
        let cleanJournal = try SpaceConfigurationSafety.deletionJournal(offline.space)
        _ = offlineContext.forceRemove()
        let afterDuplicate = try SpaceConfigurationSafety.deletionJournal(offline.space)
        require(afterDuplicate.entries == cleanJournal.entries,
                "duplicate Force Delete must not downgrade a cleaned receipt")

        let keyless = try fixture(networkId: "KEYLESS")
        activate(keyless)
        SpaceMeshKeyStore.missing = true
        let keylessContext = DevicePermanentDeletionContext(node: keyless.nodes[0], space: keyless.space)
        require(keylessContext.isPrepared && !keylessContext.canReset, "missing keys prohibit Reset but allow local preparation")
        _ = keylessContext.forceRemove()
        require(keylessContext.outcome == .cleaned, "missing keys cannot prevent forced cleanup")
        SpaceMeshKeyStore.missing = false

        let replay = try fixture(networkId: "FORCE-REPLAY")
        var replayContext: DevicePermanentDeletionContext? = DevicePermanentDeletionContext(node: replay.nodes[0], space: replay.space)
        require(replayContext!.isPrepared, "prepare forced crash fixture")
        _ = SpaceConfigurationSafety.updateDeletionJournal(replay.space) { $0.entries[0].stage = .forceRequested }
        replayContext = nil // Process exits after confirmation, before removing the Node.
        DevicePermanentDeletionContext.resume(space: replay.space)
        require(replay.network.nodes.count == 1 && !SpaceConfigurationSafety.hasPendingDeletionCleanup(replay.space),
                "confirmed force intent replays even when its node still exists")

        let reused = try fixture(networkId: "REUSED-ADDRESS")
        let stale = DevicePermanentDeletionContext(node: reused.nodes[0], space: reused.space)
        reused.nodes[0].createdTimestamp += 100 // Same UUID/address, a different provisioning instance.
        _ = stale.forceRemove()
        require(stale.outcome == .notRemoved && reused.network.nodes.count == 2,
                "stale intent cannot delete a new incarnation at the same address")

        let gatewayOwner = try fixture(networkId: "GATEWAY-OLD")
        let gatewayPeer = try fixture(networkId: "GATEWAY-PEER", uuid: gatewayOwner.network.uuid)
        gatewayPeer.network.nodes = [gatewayPeer.nodes[0]]
        gatewayOwner.nodes[1].macAddress = "AA:BB:CC:DD:EE:22"
        gatewayPeer.nodes[0].macAddress = "aabbccddee22"
        let gatewayCalls = GatewayModel.deletions.count
        let oldGateway = DevicePermanentDeletionContext(node: gatewayOwner.nodes[1], space: gatewayOwner.space)
        _ = oldGateway.forceRemove()
        require(oldGateway.outcome == .cleaned && GatewayModel.deletions.count == gatewayCalls,
                "removing an old instance retains Site-wide gateway association used by another Space")
        require(gatewayPeer.network.nodes.count == 1, "peer gateway node remains")

        // Real durable model: round trip, scope isolation and corrupted data.
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("journal.json")
        let journal = try SpaceConfigurationSafety.deletionJournal(protected.space)
        try journal.write(to: url)
        let reloaded = try SpaceDeletionJournal.read(from: url, scope: journal.scope)
        require(reloaded.entries == journal.entries, "durable deletion state must round trip")
        let wrongScope = SpaceDeletionJournal.Scope(siteId: "other", spaceId: journal.scope.spaceId,
            meshUUID: journal.scope.meshUUID, networkId: journal.scope.networkId)
        do { _ = try SpaceDeletionJournal.read(from: url, scope: wrongScope); require(false, "scope mismatch must fail") } catch {}
        try Data("broken".utf8).write(to: url)
        do { _ = try SpaceDeletionJournal.read(from: url, scope: journal.scope); require(false, "corrupt journal must fail closed") } catch {}
        print("PASS: production deletion lifecycle, batch/partial/forced deletion, protected cleanup, restart, scope collision, reviewed repair and durable journal")
    }
}
