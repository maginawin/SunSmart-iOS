import Foundation

// Unrelated storage/UI boundaries. The deletion context, journal model and
// topology commit/repair policy are compiled from their production sources.
final class Schedule {
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
enum KineticSwitchBindingPolicy {
    struct Decision { let clearsCurrent: Bool, clearsPendingRemoval: Bool, clearsCredentials: Bool }
    static func referenceCleanupDecision(node: Address, current: Address?, pendingRemoval: Address?) -> Decision {
        .init(clearsCurrent: node == current, clearsPendingRemoval: node == pendingRemoval, clearsCredentials: node == current)
    }
}
enum GatewayModel { static func delete(siteId: String, macAddress: String) {} }
struct MeshDistributionData {
    var distributionAddress: Address = 0
    static func load(meshUUID: String, meshNetworkId: String, productId: UInt16) -> Self? { nil }
    func delete(meshUUID: String, networkId: String, productId: UInt16) {}
}
enum XWHUDManager {
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
        require(unrelatedContext.commit() == nil, "confirmed deletion cannot remove unknown address 99")
        require(unrelated.group.info.proximityLightingPath!.paths[0].items.last!.address == 99, "unreviewed reference remains for review")

        // Automatic cleanup owns the complete, unchanged source snapshot. It
        // can remove both the explicit deletion and other confirmed stale refs.
        let automatic = ProximityLightingLifecycleCoordinator.begin(space: unrelated.space).prepare()
        let observation = unrelated.nodes[1].proximityLightingNeighborAddresses
        let automaticResult = ProximityLightingLifecycleCoordinator.commit(automatic,
            automaticCleanupSnapshot: automatic.sourceSnapshot)
        require(automaticResult != nil, "validated complete source permits automatic historical cleanup")
        DevicePermanentDeletionContext.resume(space: unrelated.space)
        require(!SpaceConfigurationSafety.hasPendingDeletionCleanup(unrelated.space), "automatic cleanup unblocks real deletion receipts")
        require(unrelated.nodes[1].proximityLightingNeighborAddresses == observation,
                "logical repair preserves surviving device observations and needed hardware cleanup")
        require(unrelated.nodes[1].getNodeSyncProximityLighting(topologyPlan: automaticResult!.plan) != nil,
                "surviving device still has a real synchronization task")
        var otherSnapshot = automatic.sourceSnapshot
        otherSnapshot.spaceZones = []
        require(ProximityLightingLifecycleCoordinator.commit(automatic, automaticCleanupSnapshot: otherSnapshot) == nil,
                "a different version cannot authorize automatic cleanup")


        // Authoritative current-Space removal does not require a destination
        // Space, a local provisioning callback, or a physical Reset.
        let cloud = try fixture(networkId: "CLOUD-REMOVAL")
        activate(cloud)
        let secondary = Element(3); secondary.parentNode = cloud.nodes[0]; cloud.nodes[0].elements.append(secondary)
        let cloudSchedule = Schedule(); cloudSchedule.nodeAddresses = [2, 3, 5]
        cloudSchedule.needDeleteNodeAddresses = [2, 3, 5]
        Schedule.stored[cloud.space.meshUUID + cloud.space.meshNetworkId] = [cloudSchedule]
        let cloudIdentity = SpaceCloudNodeRemovalPolicy.Instance(uuid: cloud.nodes[0].uuid.uppercased(), address: 2,
            keyFingerprint: try SchedulerModelSnapshot.keyFingerprint(["deviceKey": cloud.nodes[0].deviceKey!.hex]))
        let resolved = DevicePermanentDeletionContext.cloudRemovalInstances(space: cloud.space, expected: [cloudIdentity])!
        cloud.nodes[0].deletionFails = true
        require(!DevicePermanentDeletionContext.removeCloudInstances(space: cloud.space, instances: resolved,
            baselineTimestamp: 10, remoteTimestamp: 40, submissionID: nil), "failed removal keeps its durable cloud intent")
        require(cloud.network.nodes.count == 2 && SpaceConfigurationSafety.hasPendingDeletionCleanup(cloud.space), "failure cannot change peers")
        cloud.nodes[0].deletionFails = false
        require(DevicePermanentDeletionContext.removeCloudInstances(space: cloud.space, instances: resolved,
            baselineTimestamp: 10, remoteTimestamp: 40, submissionID: nil), "retry completes without looking up destination")
        require(cloud.network.nodes.count == 1 && cloud.space.deviceCount == 1 && cloud.space.lastUpdate > 40, "counts and cleanup version cover cloud version")
        require(cloudSchedule.nodeAddresses == [5] && cloudSchedule.needDeleteNodeAddresses == [5], "clear active and pending old references")
        require(cloud.group.info.proximityLightingPath!.paths[0].items[0].address == nil, "clear only old Sequence slot")
        require(cloud.space.triggerZones[1].items.map(\.deviceAddress) == [5], "retain peer Space Zone")
        let cloudReceipt = try SpaceConfigurationSafety.deletionJournal(cloud.space)
        require(cloudReceipt.entries.count == 1 && cloudReceipt.entries[0].cloudRemoval != nil && cloudReceipt.entries[0].stage == .cleaned, "completed cloud receipt remains pending upload")
        require(DevicePermanentDeletionContext.removeCloudInstances(space: cloud.space, instances: resolved,
            baselineTimestamp: 10, remoteTimestamp: 40, submissionID: nil), "replay is idempotent")
        let replacement = try fixture(networkId: "CLOUD-NEW-KEY")
        let oldKeyIdentity = SpaceCloudNodeRemovalPolicy.Instance(uuid: replacement.nodes[0].uuid.uppercased(), address: 2,
            keyFingerprint: try SchedulerModelSnapshot.keyFingerprint(["deviceKey": String(repeating: "B2", count: 16)]))
        require(DevicePermanentDeletionContext.cloudRemovalInstances(space: replacement.space, expected: [oldKeyIdentity]) == nil,
            "same UUID/address with a different key cannot authorize deleting a new instance")

        let reprovisioned = try fixture(networkId: "CLOUD-NEW-ADDRESS")
        let oldIdentity = SpaceCloudNodeRemovalPolicy.Instance(uuid: reprovisioned.nodes[0].uuid.uppercased(), address: 2,
            keyFingerprint: cloudIdentity.keyFingerprint, elementAddresses: [2])
        var newPayload = (payload()["nodes"] as! [[String: Any]])[0]
        newPayload["unicastAddress"] = "0046"
        let newNode = try jsonDecoder.decode(Node.self, from: JSONSerialization.data(withJSONObject: newPayload))
        newNode.network = reprovisioned.network; newNode.subNetworkId = reprovisioned.space.meshNetworkId
        reprovisioned.network.nodes = [newNode, reprovisioned.nodes[1]]
        activate(reprovisioned)
        require(DevicePermanentDeletionContext.removeCloudInstances(space: reprovisioned.space, instances: [oldIdentity],
            baselineTimestamp: 10, remoteTimestamp: 40, submissionID: nil), "old absent instance can finish its reference cleanup")
        require(reprovisioned.network.nodes.contains { $0 === newNode }, "same UUID at a new provisioning address must survive")

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
