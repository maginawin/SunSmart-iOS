// Production recovery files/state machine; App/SDK import and HTTP are explicit doubles.
extension SpaceRecoveryReceiptTests {
    @MainActor static func testDefaultConfigurationRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        defer {
            S.failStateWrite = false
            S.failCheckpoint = false
            request.responses = []
            ProximityLightingImportPreflight.storedSpace = nil
        }
        func fixture() throws -> (SpaceData, [String: Any]) {
            let space = SpaceData()
            space.lastUpdate = 100; space.lastUploadCloudTimestamp = 100
            space.nodes = [try membershipNode(9)]
            try SpaceMembershipCoordinator.confirmConfiguration(space)
            var remote = space.payload
            remote["updateTimestamp"] = 90
            remote["nodes"] = [[String: Any]]()
            let removed = HDBDeviceConfiguration(nodeUuid: UUID(), nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF")
            remote["spaceData"] = ["hdb": try HDBLightingZonePolicy.json(.init(devices: [removed]))]
            S.block(space, reason: "invalidStoredHDB")
            ProximityLightingImportPreflight.storedSpace = space
            return (space, remote)
        }
        let (space, remote) = try fixture()
        let previous = try S.recoveryState(space)
        precondition(S.prepareDefaultConfigurationImport(space, remote: remote))
        let selected = S.pendingImport(space)!
        let hdb = try HDBLightingZonePolicy.decode(payload: selected)!
        precondition(hdb.devices.isEmpty && (selected["nodes"] as! [Any]).isEmpty)
        precondition(!S.preservesLocalChanges(space), "reviewed cloud copy must bypass local preservation")
        let staged = try S.recoveryState(space)
        precondition(staged.generation != previous.generation && staged.submission == nil)
        let prepared = await space.update(spaceJsonData: remote)
        precondition(prepared == .prepared, "production preparation must select reviewed cloud over local reconciliation")
        precondition(S.beginImport(space, payload: selected))
        space.nodes = []; space.exportValues = ["spaceData": selected["spaceData"]!]
        space.lastUpdate = 90; space.lastUploadCloudTimestamp = 90
        S.failStateWrite = true
        precondition(!S.finishImport(space) && S.hasPendingImport(space), "failed finalization must remain resumable")
        S.failStateWrite = false
        precondition(S.finishImport(space))
        let restored = try S.recoveryState(space)
        precondition(!S.hasPendingImport(space) && !S.isBlocked(space) && space.needUploadCloud)
        precondition(restored.defaultRecoverySource != nil && restored.nodeIdentitiesBaseline?.isEmpty == true)
        precondition(S.preservesLocalChanges(space), "repair upload intent survives restart")
        request.result = .success(["data": remote])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("selected old raw snapshot must permit first repair upload") }
        precondition(space.nodes.isEmpty && space.defaultRestoreCalls == 0)
        let payload = space.payload
        let submission = S.prepareSubmission(space, payload: payload)!
        precondition(S.markSubmissionAccepted(submission, space: space))
        if case .success = await S.resumeUpload(space) { preconditionFailure("unrepaired GET must never confirm POST") }
        precondition(S.hasPendingUpload(space))
        request.result = .success(["data": payload])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("exact repaired GET must finish") }
        let completed = try S.recoveryState(space)
        precondition(completed.defaultRecoverySource == nil && !S.hasPendingUpload(space) && !S.preservesLocalChanges(space))
        print("PASS: default recovery persists cloud-empty selection, resumes failed finalization, uploads repair and requires strict GET confirmation")

        for pendingSubmission in [false, true] {
            let (changed, original) = try fixture()
            let applied = await changed.restoreConfiguration(spaceJsonData: original, authoritativeGET: true, fixWithDefaults: true)
            precondition(applied.status == .applied)
            if pendingSubmission {
                let receipt = S.prepareSubmission(changed, payload: changed.payload)!
                precondition(S.markSubmissionAccepted(receipt, space: changed))
            }
            var newer = original
            newer["nodes"] = [try membershipNode(1)]
            newer["updateTimestamp"] = 120
            request.result = .success(["data": newer])
            if case .failure = await S.resumeUpload(changed) { preconditionFailure("changed cloud Nodes must replace waiting repair") }
            precondition(changed.defaultRestoreCalls == 2 && changed.nodes.count == 1)
            precondition(changed.nodes.first?["uuid"] as? String == (newer["nodes"] as! [[String: Any]])[0]["uuid"] as? String)
            precondition(!S.hasPendingImport(changed) && !S.hasPendingUpload(changed))
        }
        print("PASS: newer cloud Nodes supersede both unsent repair and accepted old submission")

        let (denied, deniedRemote) = try fixture()
        denied.permission = .visitor
        precondition(!S.prepareDefaultConfigurationImport(denied, remote: deniedRemote))
        denied.permission = .owner; denied.requiresPasswordVerification = true
        precondition(!S.prepareDefaultConfigurationImport(denied, remote: deniedRemote))
        denied.requiresPasswordVerification = false
        S.failCheckpoint = true
        precondition(!S.prepareDefaultConfigurationImport(denied, remote: deniedRemote))
        precondition(!S.hasPendingImport(denied), "backup failure must not stage a destructive replacement")
        S.failCheckpoint = false
        var missing = deniedRemote; missing.removeValue(forKey: "nodes")
        precondition(!S.prepareDefaultConfigurationImport(denied, remote: missing))
        precondition(!S.hasPendingImport(denied))
        print("PASS: default repair rejects revoked editing/password, missing Nodes and backup failure without staging")

        var snapshots = [RecoveryMeshFactory.legacyPayload()]
        for path in CommandLine.arguments.dropFirst() {
            let response = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
            snapshots.append(response["data"] as? [String: Any] ?? response)
        }
        for snapshot in snapshots {
            let (legacy, _) = try fixture()
            var cloud = legacy.payload
            for field in ["nodes", "groups", "spaceData"] { cloud[field] = snapshot[field] }
            cloud["updateTimestamp"] = 120
            let staged = S.prepareDefaultConfigurationImport(legacy, remote: cloud)
            let stages = S.testDefaults.dictionaryRepresentation().filter { $0.key.hasPrefix("spaceConfigurationLastSyncDiagnostic.") }
                .values.compactMap { ($0 as? [String: Any])?["stage"] as? String }
            precondition(staged, "legacy recovery staging failed: \(stages)")
            let selected = S.pendingImport(legacy)!
            let configuration = try HDBLightingZonePolicy.decode(payload: selected)!
            let preparation = await legacy.update(spaceJsonData: cloud)
            precondition(preparation == .prepared)
            precondition(S.beginImport(legacy, payload: selected))
            legacy.nodes = selected["nodes"] as! [[String: Any]]
            legacy.exportValues = ["groups": selected["groups"]!, "spaceData": selected["spaceData"]!]
            legacy.lastUpdate = 120; legacy.lastUploadCloudTimestamp = 120
            precondition(S.finishImport(legacy) && !S.isBlocked(legacy) && legacy.needUploadCloud)
            legacy.syncCloudError = nil
            let beforeReentry = legacy.payload
            let reentered = await legacy.update(spaceJsonData: cloud)
            precondition(reentered == .preserved("localDefaultRecoveryPendingUpload")
                && legacy.syncCloudError == nil && !S.isBlocked(legacy),
                "reentering a committed repair must not revalidate the selected old HDB as an ordinary cloud conflict")
            precondition(NSDictionary(dictionary: beforeReentry).isEqual(to: legacy.payload))
            let reopened = SpaceData(legacy.id)
            reopened.lastUpdate = legacy.lastUpdate; reopened.lastUploadCloudTimestamp = legacy.lastUploadCloudTimestamp
            reopened.nodes = legacy.nodes; reopened.exportValues = legacy.exportValues
            ProximityLightingImportPreflight.storedSpace = reopened
            S.block(reopened, reason: "cloudConfigurationConflict")
            let afterRestart = await reopened.update(spaceJsonData: cloud)
            precondition(afterRestart == .preserved("localDefaultRecoveryPendingUpload") && !S.isBlocked(reopened),
                "persisted recovery receipt must retain the committed data after restart and clear only its obsolete cloud conflict")
            reopened.savesSucceed = false
            precondition(S.preserveDefaultConfiguration(reopened, remote: cloud) == .rejected("configurationPersistenceFailed"))
            reopened.savesSucceed = true; reopened.hdbLoadFailed = true
            precondition(S.preserveDefaultConfiguration(reopened, remote: cloud) == .rejected("configurationPersistenceFailed"))
            reopened.hdbLoadFailed = false; reopened.permission = .visitor
            precondition(S.preserveDefaultConfiguration(reopened, remote: cloud) == nil)
            ProximityLightingImportPreflight.storedSpace = legacy
            request.result = .success(["data": cloud])
            if case .failure = await S.resumeUpload(legacy) { preconditionFailure("legacy source must allow the first repaired upload") }
            let submission = S.prepareSubmission(legacy, payload: legacy.payload)!
            precondition(S.markSubmissionAccepted(submission, space: legacy))
            let awaitingReadback = await legacy.update(spaceJsonData: cloud)
            precondition(awaitingReadback == .preserved("localDefaultRecoveryPendingUpload") && S.hasPendingUpload(legacy))
            request.result = .success(["data": legacy.payload])
            if case .failure = await S.resumeUpload(legacy) { preconditionFailure("current-format readback must complete legacy recovery") }
            precondition(!S.hasPendingUpload(legacy) && !S.hasPendingImport(legacy))
            print("PASS: legacy/sample staging, reentry/restart while upload pending, failure/authority gates and strict readback; Zones=\(configuration.lightingZones.count), devices=\(configuration.devices.count)")
        }
    }
}
