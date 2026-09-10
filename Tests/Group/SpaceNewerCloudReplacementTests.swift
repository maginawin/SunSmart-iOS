import Foundation

extension SpaceRecoveryReceiptTests {
    @MainActor static func testNewerCloudReplacement() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = SpaceConfigurationIntegrityPolicy
        let request = NetworkRequest.shared
        defer { ProximityLightingImportPreflight.storedSpace = nil; request.onRequest = nil }
        func detail(_ space: SpaceData, timestamp: Int64 = 100) -> [String: Any] {
            var payload = space.payload
            payload["updateTimestamp"] = timestamp
            payload["spaceName"] = "Cloud"
            for key in ["nodes", "scenes", "schedules", "switches", "emergencyFireControllers"] {
                payload[key] = [[String: Any]]()
            }
            payload["spaceData"] = ["proximityLightingSchemaVersion": 1, "triggerZones": []] as [String: Any]
            return payload
        }
        func submitted(_ space: SpaceData) -> SpaceRecoveryState {
            space.nodes = [["uuid": "old-1", "unicastAddress": "0002"], ["uuid": "old-2", "unicastAddress": "0005"]]
            let state = S.prepareSubmission(space, payload: space.payload)!
            precondition(S.markSubmissionAccepted(state, space: space))
            S.block(space, reason: "uploadReadbackConflict")
            return state
        }
        func select(_ space: SpaceData, payload: [String: Any]) {
            ProximityLightingImportPreflight.storedSpace = space
            request.responses = []
            request.result = .success(["data": payload])
        }

        let space = SpaceData()
        let original = submitted(space)
        let previousDirectory = try S.testDirectory(space)
        precondition(S.updateDeletionJournal(space) {
            $0.entries = [.init(id: UUID(), nodeUUID: "old-1", primaryAddress: 2, elementAddresses: [2],
                               macAddress: nil, productId: nil, stage: .forceRequested)]
            $0.switches = [.init(id: UUID(), switchId: "old-switch", fingerprint: "old", completedTimestamp: 50)]
        })
        let other = SpaceData()
        _ = submitted(other)
        let otherState = try S.recoveryState(other)
        let remote = detail(space)
        select(space, payload: remote)
        let calls = request.calls, uploads = request.uploads
        if case .success(.adoptedCloud(let adopted)) = await S.resumeUpload(space) {
            precondition(adopted.generation != original.generation && S.isCurrent(adopted, space: space))
        } else { preconditionFailure("newer empty cloud must replace accepted two-node upload") }
        precondition(request.calls == calls + 1 && request.uploads == uploads)
        precondition(space.nodes.isEmpty && space.lastUpdate == 100 && space.lastUploadCloudTimestamp == 100)
        precondition(!S.hasPendingUpload(space) && !S.isBlocked(space) && !S.hasPendingImport(space))
        precondition(!S.isCurrent(original, space: space), "old callbacks must be invalidated")
        let journal = try S.deletionJournal(space)
        precondition(journal.entries.isEmpty && (journal.switches ?? []).isEmpty)
        precondition(FileManager.default.fileExists(atPath: previousDirectory.appendingPathComponent("device-deletions.json").path))
        precondition(FileManager.default.fileExists(atPath: previousDirectory.appendingPathComponent("recovery-state.json").path))
        let unchangedOther = try S.recoveryState(other)
        precondition(unchangedOther == otherState)

        let residual = SpaceData()
        S.block(residual, reason: "remainingTopologyNeedsReview")
        let residualBefore = submitted(residual)
        precondition(S.updateDeletionJournal(residual) {
            $0.switches = [.init(id: UUID(), switchId: "deleted-switch", fingerprint: "old", completedTimestamp: 50)]
        })
        var incompleteResidual = detail(residual)
        incompleteResidual.removeValue(forKey: "schedules")
        select(residual, payload: incompleteResidual)
        if case .success = await S.resumeUpload(residual) { preconditionFailure("incomplete cloud must retain residual topology protection") }
        precondition(S.isBlocked(residual) && S.isCurrent(residualBefore, space: residual))
        select(residual, payload: detail(residual))
        if case .success(.adoptedCloud) = await S.resumeUpload(residual) {} else {
            preconditionFailure("validated complete cloud must resolve remaining topology review")
        }
        precondition(!S.isBlocked(residual) && !S.hasPendingUpload(residual) && !S.hasPendingImport(residual))
        precondition(residual.nodes.isEmpty && residual.lastUpdate == 100 && residual.lastUploadCloudTimestamp == 100)
        precondition(!(try! S.deletionJournal(residual).hasReceipts) && !S.isCurrent(residualBefore, space: residual))

        // A crash/failure after staging resumes the selected payload, without a
        // request that might pick another version or resubmit the old devices.
        let interrupted = SpaceData()
        let old = submitted(interrupted)
        let chosen = detail(interrupted, timestamp: 120)
        interrupted.failCloudCommit = true
        select(interrupted, payload: chosen)
        if case .success = await S.resumeUpload(interrupted) { preconditionFailure("failed import must not report success") }
        precondition(S.hasPendingUpload(interrupted) && S.isBlocked(interrupted) && !S.isCurrent(old, space: interrupted))
        let staged = try S.recoveryState(interrupted)
        precondition(staged.cloudReplacementTimestamp == 120)
        // Simulate the crash window after removing the transient file but before
        // committing the final recovery state; selected-cloud remains durable.
        try FileManager.default.removeItem(at: S.testDirectory(interrupted).appendingPathComponent("pending-import.json"))
        let restarted = SpaceData(interrupted.id)
        select(restarted, payload: detail(restarted, timestamp: 999))
        let beforeRestart = request.calls
        if case .success(.adoptedCloud) = await S.resumeUpload(restarted) {} else { preconditionFailure("staged import must resume") }
        precondition(request.calls == beforeRestart && restarted.lastUpdate == 120 && restarted.nodes.isEmpty)
        let explicitDeletion = SpaceData()
        _ = submitted(explicitDeletion)
        explicitDeletion.failCloudCommit = true
        select(explicitDeletion, payload: detail(explicitDeletion))
        _ = await S.resumeUpload(explicitDeletion)
        let beforeDeletion = try S.recoveryState(explicitDeletion)
        let deletionPrepared = await S.prepareForDeviceDeletion(explicitDeletion)
        let afterDeletion = try S.recoveryState(explicitDeletion)
        precondition(deletionPrepared && afterDeletion.cloudReplacementTimestamp == nil)
        precondition(!S.hasPendingImport(explicitDeletion) && !S.isCurrent(beforeDeletion, space: explicitDeletion))

        for version: Int64 in [49, 50] {
            let unchanged = SpaceData()
            let initial = submitted(unchanged)
            select(unchanged, payload: detail(unchanged, timestamp: version))
            if case .success = await S.resumeUpload(unchanged) { preconditionFailure("equal/older cloud must retain conflict") }
            precondition(S.isCurrent(initial, space: unchanged) && unchanged.nodes.count == 2)
        }
        let edited = SpaceData()
        let editedState = submitted(edited)
        select(edited, payload: detail(edited))
        request.onRequest = { edited.lastUpdate = 101 }
        if case .success = await S.resumeUpload(edited) { preconditionFailure("latest local edit must win over older cloud") }
        precondition(S.isCurrent(editedState, space: edited) && edited.nodes.count == 2)

        for missing in ["nodes", "schedules", "switches", "emergencyFireControllers", "netKey"] {
            let incomplete = SpaceData()
            let initial = submitted(incomplete)
            var payload = detail(incomplete)
            payload.removeValue(forKey: missing)
            select(incomplete, payload: payload)
            if case .success = await S.resumeUpload(incomplete) { preconditionFailure("incomplete detail cannot erase records: \(missing)") }
            precondition(S.isCurrent(initial, space: incomplete) && incomplete.nodes.count == 2)
        }
        let summarySpace = SpaceData()
        _ = submitted(summarySpace)
        select(summarySpace, payload: detail(summarySpace))
        let beforeDetail = request.calls
        let result = await summarySpace.update(spaceJsonData: ["uuid": summarySpace.id, "updateTimestamp": 100, "nodes": []])
        precondition(result == .applied && request.calls == beforeDetail + 1)

        // The selected snapshot is validated again at the mutation boundary.
        let raced = SpaceData()
        _ = submitted(raced)
        let racedRemote = detail(raced)
        select(raced, payload: racedRemote)
        ProximityLightingImportPreflight.onPrepare = { raced.lastUpdate = 101 }
        let outcome = await raced.update(spaceJsonData: racedRemote, authoritativeCloud: true)
        ProximityLightingImportPreflight.onPrepare = nil
        precondition(outcome == .rejected("staleImportPreparation") && raced.nodes.count == 2)
        let asynchronousEdit = SpaceData()
        _ = submitted(asynchronousEdit)
        select(asynchronousEdit, payload: detail(asynchronousEdit))
        ProximityLightingImportPreflight.onPrepare = { asynchronousEdit.lastUpdate = 101 }
        if case .success(.superseded) = await S.resumeUpload(asynchronousEdit) {} else { preconditionFailure("stale import must cancel its sync completion") }
        ProximityLightingImportPreflight.onPrepare = nil
        precondition(asynchronousEdit.nodes.count == 2 && asynchronousEdit.lastUpdate == 101)

        let populated = SpaceData()
        _ = submitted(populated)
        var populatedCloud = detail(populated)
        populatedCloud["nodes"] = [["uuid": "cloud-device", "unicastAddress": "0007"]]
        select(populated, payload: populatedCloud)
        if case .success(.adoptedCloud) = await S.resumeUpload(populated) {} else { preconditionFailure("nonempty cloud must replace the old membership too") }
        precondition(populated.nodes.count == 1 && populated.nodes.first?["uuid"] as? String == "cloud-device")
        let deleting = SpaceData()
        let deletionContext = submitted(deleting)
        select(deleting, payload: detail(deleting))
        DevicePermanentDeletionContext.activeOperation = true
        if case .success = await S.resumeUpload(deleting) { preconditionFailure("active device removal must finish before replacement") }
        DevicePermanentDeletionContext.activeOperation = false
        precondition(S.isCurrent(deletionContext, space: deleting) && deleting.nodes.count == 2)
        if case .success(.adoptedCloud) = await S.resumeUpload(deleting) {} else { preconditionFailure("retry after removal must adopt cloud") }

        let finishFailure = SpaceData()
        _ = submitted(finishFailure)
        select(finishFailure, payload: detail(finishFailure))
        finishFailure.savesSucceed = false
        if case .success = await S.resumeUpload(finishFailure) { preconditionFailure("failed final save cannot finish recovery") }
        precondition(S.hasPendingUpload(finishFailure) && S.isBlocked(finishFailure))
        finishFailure.savesSucceed = true
        if case .success(.adoptedCloud) = await S.resumeUpload(finishFailure) {} else { preconditionFailure("final save must be retryable") }

        let visitor = SpaceData()
        _ = submitted(visitor)
        var visitorPayload = detail(visitor)
        visitorPayload["role"] = "visitor"
        select(visitor, payload: visitorPayload)
        if case .success(.adoptedCloud) = await S.resumeUpload(visitor) {} else { preconditionFailure("readable newer cloud may be adopted after authority downgrade") }
        precondition(visitor.permission == .visitor && visitor.nodes.isEmpty)

        let localFile = SpaceData()
        _ = submitted(localFile)
        select(localFile, payload: detail(localFile))
        let fileRequests = request.calls
        _ = await localFile.update(spaceJsonData: detail(localFile), allowsCloudReplacement: false)
        precondition(request.calls == fileRequests && localFile.nodes.count == 2, "file import must not silently substitute server data")

        let independent = SpaceData()
        S.block(independent, reason: "unrelatedFailure")
        _ = submitted(independent)
        select(independent, payload: detail(independent))
        if case .success = await S.resumeUpload(independent) { preconditionFailure("independent failure must remain visible") }
        precondition(S.isBlocked(independent))
        precondition(P.cloudIsNewer(remote, localTimestamp: 50, submittedTimestamp: 99))
        precondition(!P.cloudIsNewer(remote, localTimestamp: 101, submittedTimestamp: 50))
        precondition(!P.cloudIsNewer(remote, localTimestamp: 50, submittedTimestamp: 100))
        precondition(!P.cloudIsNewer(["updateTimestamp": true], localTimestamp: 0, submittedTimestamp: nil))
        print("PASS: newer cloud replacement, old generation/journal isolation, empty membership, detail fetch, version races, incomplete payload rejection and durable interrupted import recovery")
        CloudRecordReplacementTests.run()
    }
}

// The runner inserts the production record-removal loops and the persisted Node
// set comparison. The SDK is a storage boundary; no BLE requests are available.
final class CloudRecordReplacementTests {
    struct Node {
        let uuid: String
        let subNetworkId: String
        var isLocalProvisioner = false
        var macAddress: String? = nil
    }
    struct Group { let subNetworkId: String; let address: Int }
    struct Scene { let subNetworkId: String; let number: Int }
    final class Network {
        var nodes: [Node] = []
        var groups: [Group] = []
        var scenes: [Scene] = []
        var failNodeDelete = false
        func forceRemove(node: Node) { if !failNodeDelete { nodes.removeAll { $0.uuid == node.uuid } } }
        func forceRemove(group: Group) { groups.removeAll { $0.address == group.address && $0.subNetworkId == group.subNetworkId } }
        func forceRemove(scene: Int) { scenes.removeAll { $0.number == scene } }
    }
    enum GatewayModel { static func delete(siteId: String, macAddress: String) {} }
    let meshNetworkId = "target", siteId = "site"
    func removeNodes(_ network: Network) {
        // CLOUD_REMOVE_NODES
    }
    func removeGroups(_ network: Network) {
        // CLOUD_REMOVE_GROUPS
    }
    func removeScenes(_ network: Network) {
        // CLOUD_REMOVE_SCENES
    }
    func matches(_ persistedNetwork: Network, nodes: [Node]) -> Bool {
        // CLOUD_PERSISTED_NODES
    }
    static func uploadIDs(_ syncSpaces: [SpaceData], excludingAdoptedSpaces: Set<String>) -> [String] {
        // CLOUD_UPLOAD_SELECTION
        return uploadSpaces.map { $0.id }
    }
    static func run() {
        let harness = CloudRecordReplacementTests(), network = Network()
        let old = Node(uuid: "old", subNetworkId: "target")
        let peer = Node(uuid: "peer", subNetworkId: "other")
        let provisioner = Node(uuid: "provisioner", subNetworkId: "target", isLocalProvisioner: true)
        network.nodes = [old, peer, provisioner]
        network.groups = [.init(subNetworkId: "target", address: 1), .init(subNetworkId: "other", address: 2)]
        network.scenes = [.init(subNetworkId: "target", number: 1), .init(subNetworkId: "other", number: 2)]
        network.failNodeDelete = true
        harness.removeNodes(network)
        precondition(!harness.matches(network, nodes: []), "empty import must detect failed persistent removal")
        network.failNodeDelete = false
        harness.removeNodes(network)
        harness.removeGroups(network)
        harness.removeScenes(network)
        precondition(harness.matches(network, nodes: []))
        precondition(network.nodes.map(\.uuid) == ["peer", "provisioner"])
        precondition(network.groups.map(\.subNetworkId) == ["other"] && network.scenes.map(\.subNetworkId) == ["other"])
        let added = Node(uuid: "new", subNetworkId: "target")
        network.nodes.append(added)
        precondition(harness.matches(network, nodes: [added]))
        precondition(!harness.matches(network, nodes: [old]))
        let adopted = SpaceData(), dirty = SpaceData()
        adopted.lastUploadCloudTimestamp = adopted.lastUpdate
        precondition(uploadIDs([adopted, dirty], excludingAdoptedSpaces: [adopted.id]) == [dirty.id])
        adopted.lastUpdate += 1
        precondition(uploadIDs([adopted, dirty], excludingAdoptedSpaces: [adopted.id]) == [adopted.id, dirty.id])
        print("PASS: production Node/Group/Scene removal loops preserve other Spaces/provisioner; persisted membership check rejects stale records and missing new Nodes")
    }
}
