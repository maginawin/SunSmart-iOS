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


extension SpaceRecoveryReceiptTests {
    @MainActor static func testLegacyReviewedRecoverySource() async throws {
        typealias S = SpaceConfigurationSafety
        defer { ProximityLightingImportPreflight.storedSpace = nil }
        let values: [(String, Any, Any)] = [
            ("triggerZones", [["name": "Before", "items": []]], [["name": "After", "items": []]]),
            ("hdb", try HDBLightingZonePolicy.json(HDBConfiguration()),
             try HDBLightingZonePolicy.json(HDBConfiguration(lightingZones: [
                .init(zoneId: 1, name: "New zone", groupAddress: 0xC001)])))
        ]
        for (field, original, changed) in values {
            let space = SpaceData()
            space.lastUploadCloudTimestamp = space.lastUpdate
            try SpaceMembershipCoordinator.confirmConfiguration(space)
            ProximityLightingImportPreflight.storedSpace = space
            var remote = space.payload
            remote[field] = original
            // Explicit clearing is a valid recovery even when the source has
            // broken references. Its original fields must still protect retry.
            let selected = try SpaceRecoveryPayloadPolicy.clearing(remote, hdb: field == "hdb")
            precondition(S.prepareRecoveryImport(space, remote: remote, selected: selected))
            let reopened = SpaceData(space.id)
            precondition(S.canResumeReviewedRecovery(reopened, remote: remote))
            var updated = remote; updated[field] = changed
            precondition(SpaceCloudNodeRemovalPolicy.Snapshot.make(remote) != SpaceCloudNodeRemovalPolicy.Snapshot.make(updated))
            precondition(!S.canResumeReviewedRecovery(reopened, remote: updated),
                         "Same-time legacy \(field) changes must invalidate the persisted selection")
            var removed = remote; removed.removeValue(forKey: field)
            precondition(!S.canResumeReviewedRecovery(reopened, remote: removed))
            var modern = remote; modern.removeValue(forKey: field); modern["spaceData"] = [field: original]
            precondition(S.canResumeReviewedRecovery(reopened, remote: modern),
                         "Moving an unchanged legacy field into spaceData must remain compatible")
            modern["spaceData"] = [field: changed]
            precondition(!S.canResumeReviewedRecovery(reopened, remote: modern))

            let restored = await space.restoreConfiguration(spaceJsonData: remote, authoritativeGET: true)
            precondition(restored.status == .applied && space.needUploadCloud)
            NetworkRequest.shared.result = .success(["data": remote])
            if case .failure = await S.resumeUpload(space) { preconditionFailure("Unchanged legacy source must permit repair upload") }
            let localVersion = space.lastUpdate
            precondition(S.preserveDefaultConfiguration(space, remote: updated) == .rejected("recoverySourceChanged"))
            NetworkRequest.shared.result = .success(["data": updated])
            if case .success = await S.resumeUpload(space) { preconditionFailure("Changed legacy source must block repair upload") }
            precondition(space.lastUpdate == localVersion)
        }
        print("PASS: legacy Trigger Zones/HDB source persistence, same-time change/removal rejection, format compatibility and repair-upload guards")
    }

    @MainActor static func testEqualVersionRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData()
        space.lastUploadCloudTimestamp = 50
        space.nodes = [try membershipNode(1), try membershipNode(2)]
        try SpaceMembershipCoordinator.confirmConfiguration(space)
        ProximityLightingImportPreflight.storedSpace = space
        defer { ProximityLightingImportPreflight.storedSpace = nil; S.failCheckpoint = false }
        var remote = space.payload
        remote["nodes"] = [space.nodes[1]]
        remote["deviceCount"] = 3
        remote["switches"] = [["id": "logical", "name": "Switch 3", "proxyNodeAddress": "001D"]]
        var state = try S.recoveryState(space)
        state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(space.payload)
        try S.testSaveState(state, space: space)
        S.block(space, reason: "cloudConfigurationConflict")
        precondition(S.needsEqualVersionCloudImport(space, remote: remote))
        S.failCheckpoint = true
        precondition(!S.prepareRecoveryImport(space, remote: remote) && !S.hasPendingImport(space))
        S.failCheckpoint = false
        var invalid = remote; invalid["netKey"] = ["key": "different"]
        precondition(!S.prepareRecoveryImport(space, remote: invalid), "Network identity remains protected")
        precondition(S.prepareRecoveryImport(space, remote: remote))
        precondition(S.canResumeReviewedRecovery(space, remote: remote))
        var changedDuringImport = remote; changedDuringImport["spaceName"] = "Changed before retry"
        precondition(!S.canResumeReviewedRecovery(space, remote: changedDuringImport),
                     "A persisted selection must not replace a newer server source on retry")
        let selected = S.pendingImport(space)!
        precondition((selected["nodes"] as! [Any]).count == 1)
        precondition((selected["switches"] as! [[String: Any]])[0]["proxyNodeAddress"] == nil)
        precondition(selected["deviceCount"] as? Int == 1)
        let restored = await space.restoreConfiguration(spaceJsonData: remote, authoritativeGET: true)
        precondition(restored.status == .applied && space.nodes.count == 1 && !S.isBlocked(space))
        precondition(space.needUploadCloud && space.lastUploadCloudTimestamp == 50)
        NetworkRequest.shared.result = .success(["data": remote])
        if case .failure = await S.resumeUpload(space) { preconditionFailure("Original cloud source permits repaired upload") }
        let localVersion = space.lastUpdate
        precondition(!S.needsEqualVersionCloudImport(space, remote: remote), "Newer local repair must not be overwritten")
        var changed = remote; changed["spaceName"] = "Changed elsewhere"
        NetworkRequest.shared.result = .success(["data": changed])
        if case .success = await S.resumeUpload(space) { preconditionFailure("Changed source requires fresh review") }
        precondition(space.lastUpdate == localVersion && space.nodes.count == 1)
        // Explicit empty replacement bypasses a damaged old business payload,
        // but retains keys and the existing membership.
        var damaged = changed; damaged["schedules"] = "broken"
        let empty = try SpaceRecoveryPayloadPolicy.clearing(damaged, hdb: false)
        precondition(S.prepareRecoveryImport(space, remote: damaged, selected: empty))
        let prepared = await space.update(spaceJsonData: damaged)
        precondition(prepared == .prepared, "Validated selected snapshot must replace corrupt source before decoding")
        let cleared = await space.restoreConfiguration(spaceJsonData: damaged, authoritativeGET: true)
        precondition(cleared.status == .applied && space.nodes.isEmpty && space.needUploadCloud)
        print("PASS: equal-time server authority, stale proxy/count repair, backup/key rejection, newer local protection, changed-source review and corrupt-content clearing")
    }
}


extension SpaceRecoveryReceiptTests {
    @MainActor static func testEqualVersionFieldSample(_ paths: [String]) async throws {
        func read(_ path: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        }
        let local = (try read(paths[0])["spaces"] as! [[String: Any]])[0]
        var remote = try read(paths[1])["data"] as! [String: Any]
        let space = SpaceData(local["uuid"] as! String)
        space.lastUpdate = SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"])!
        space.lastUploadCloudTimestamp = space.lastUpdate
        space.nodes = local["nodes"] as! [[String: Any]]; space.groups = local["groups"] as! [[String: Any]]
        // The cryptographic key implementation is a boundary of this harness;
        // production key matching has a separate suite. Do not print sample keys.
        remote["netKey"] = ["key": space.id]; remote["appKey"] = ["key": "app"]
        ProximityLightingImportPreflight.storedSpace = space
        defer { ProximityLightingImportPreflight.storedSpace = nil }
        try SpaceMembershipCoordinator.confirmConfiguration(space)
        SpaceConfigurationSafety.block(space, reason: "cloudConfigurationConflict")
        precondition(space.nodes.count == 2 && (remote["nodes"] as! [Any]).count == 1)
        precondition(SpaceConfigurationSafety.needsEqualVersionCloudImport(space, remote: remote))
        precondition(SpaceConfigurationSafety.prepareRecoveryImport(space, remote: remote))
        let selected = SpaceConfigurationSafety.pendingImport(space)!
        precondition(selected["deviceCount"] as? Int == 1)
        precondition((selected["switches"] as! [[String: Any]]).allSatisfy { $0["proxyNodeAddress"] as? String != "001D" })
        let prepared = await space.update(spaceJsonData: remote)
        precondition(prepared == .prepared)
        let completed = await space.restoreConfiguration(spaceJsonData: remote, authoritativeGET: true)
        precondition(completed.status == .applied && space.nodes.count == 1 && !SpaceConfigurationSafety.isBlocked(space))
        NetworkRequest.shared.result = .success(["data": remote])
        if case .failure = await SpaceConfigurationSafety.resumeUpload(space) { preconditionFailure("Field repair must remain uploadable") }
        print("PASS: supplied Space 1 sample 2 -> 1, reported 3 -> 1, orphan proxy cleared, real import decoding/preparation and durable recovery; full App/SDK/HTTP remain integration boundaries")
    }
}
