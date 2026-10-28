// Synthetic data only. HTTP, SDK loading and App DB are the receipt harness boundaries.
extension SpaceRecoveryReceiptTests {
    @MainActor static func olderCloudFixture() throws -> (SpaceData, [String: Any]) {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData()
        space.lastUpdate = 100; space.lastUploadCloudTimestamp = 100
        space.nodes = try (1...3).map(membershipNode)
        space.groups = [["name": "Group", "address": "C003", "parentAddress": "0000", "profile": ["id": "profile", "type": 1,
            "highEndTrim": 100, "lowEndTrim": 1, "occupancyLevel": 734, "vacantLevel": 100,
            "taskLevel": 100, "timeT1": 2, "timeT2": 10, "timeT3": 2, "timeT4": 0,
            "timeT5": 2, "manualOverrideTimeout": 60, "powerUpState": 255]]]
        var remote = space.payload
        S.verifyUpgradeBaseline(space, local: remote, remote: remote)
        try SpaceMembershipCoordinator.confirmConfiguration(space)
        remote["updateTimestamp"] = 90
        let removed = SpaceCloudNodeRemovalPolicy.instances(remote)!.last!
        space.nodes.removeLast(); space.lastUpdate = 110
        precondition(S.updateDeletionJournal(space) {
            $0.entries.append(.init(id: UUID(), nodeUUID: removed.uuid, primaryAddress: removed.address,
                elementAddresses: removed.elementAddresses, macAddress: nil, productId: nil,
                stage: .cleaned, completedTimestamp: 110))
        })
        ProximityLightingImportPreflight.storedSpace = space
        return (space, remote)
    }

    @MainActor static func testOlderCloudBaseline() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        defer {
            ProximityLightingImportPreflight.storedSpace = nil
            ProximityLightingImportPreflight.onExport = nil
            S.failStateWrite = false
            request.responses = []
        }
        for mode in ["complete", "missingTimed", "snapshotIdentity", "snapshotModels", "emptyTimed", "emptySpace", "reordered", "import", "timedMigration"] {
            let (space, original) = try olderCloudFixture()
            var remote = original
            var state = try S.recoveryState(space)
            if mode == "missingTimed" || mode == "emptyTimed" { state.timedConfigurationBaseline = nil }
            if mode == "snapshotIdentity" { state.nodeIdentitiesBaseline = nil }
            if mode == "snapshotModels" { state.schedulerModelStatesBaseline = nil }
            if mode == "emptyTimed" {
                try FileManager.default.removeItem(at: S.testDirectory(space).appendingPathComponent("last-complete-export.json"))
            }
            if mode == "emptySpace" {
                remote["nodes"] = [[String: Any]](); space.nodes = []
                state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
                state.nodeIdentitiesBaseline = []
                state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
            }
            if mode == "reordered" { remote["nodes"] = (remote["nodes"] as! [[String: Any]]).reversed().map { $0 } }
            if mode == "timedMigration" {
                space.timedSchemaVersion = 2
                space.exportValues["spaceData"] = ["timedSchemaVersion": 2]
            }
            try S.testSaveState(state, space: space)
            request.result = .success(["data": remote])
            let uploads = request.uploads
            if mode == "import" || mode == "timedMigration" {
                let result = await space.update(spaceJsonData: remote)
                precondition(result == .preserved("unchangedOlderCloudBaseline"), "old baseline must never import missing nodes")
            }
            if case .failure = await S.resumeUpload(space) { preconditionFailure("unchanged older baseline must allow upload: " + mode) }
            precondition(space.lastUploadCloudTimestamp == 100 && space.needUploadCloud && !S.hasPendingUpload(space))
            precondition(request.uploads == uploads, "baseline validation alone cannot POST or confirm")
            let recovered = try S.recoveryState(space)
            precondition(recovered.timedConfigurationBaseline != nil)
            request.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
            if case .failure = await S.uploadBeforeUnbind(space) { preconditionFailure("normal POST and readback must finish: " + mode) }
            precondition(request.responses.isEmpty && request.uploads == uploads + 1)
            precondition(space.lastUploadCloudTimestamp == 110 && !space.needUploadCloud && !S.hasPendingUpload(space))
            let journal = try S.deletionJournal(space)
            precondition(journal.entries.isEmpty)
            let reopened = SpaceData(space.id)
            reopened.lastUpdate = space.lastUpdate; reopened.lastUploadCloudTimestamp = space.lastUploadCloudTimestamp
            reopened.nodes = space.nodes; reopened.groups = space.groups
            if case .failure = await S.resumeUpload(reopened) { preconditionFailure("confirmed state must survive reloading") }
        }
        for mode in ["profile", "deviceKey", "elements", "models", "missingNodes", "missingBaseline", "unknownRemoval", "nonemptyTimed", "missingIdentities", "pending", "revoked", "key", "write", "localChanged", "membershipChanged", "cancelled"] {
            let (space, original) = try olderCloudFixture()
            var remote = original
            var state = try S.recoveryState(space)
            switch mode {
            case "profile":
                var groups = remote["groups"] as! [[String: Any]]
                var profile = groups[0]["profile"] as! [String: Any]
                profile["occupancyLevel"] = 400; groups[0]["profile"] = profile; remote["groups"] = groups
            case "deviceKey", "elements", "models":
                var nodes = remote["nodes"] as! [[String: Any]]
                if mode == "deviceKey" { nodes[0]["deviceKey"] = String(repeating: "B2", count: 16) }
                if mode == "elements" { nodes[0]["elements"] = [["index": 0, "models": [["modelId": "1207", "subscribe": []]]], ["index": 1, "models": []]] }
                if mode == "models" { nodes[0].removeValue(forKey: "custProps") }
                remote["nodes"] = nodes
            case "missingNodes": remote.removeValue(forKey: "nodes")
            case "missingBaseline": state.authorizationBaseline = nil
            case "unknownRemoval": precondition(S.updateDeletionJournal(space) { $0.entries = [] })
            case "nonemptyTimed": state.timedConfigurationBaseline = Data("nonempty-or-corrupt-baseline".utf8)
            case "missingIdentities":
                state.nodeIdentitiesBaseline = nil; state.schedulerModelStatesBaseline = nil
                try FileManager.default.removeItem(at: S.testDirectory(space).appendingPathComponent("last-complete-export.json"))
            case "revoked": remote["role"] = "visitor"
            case "key": remote["netKey"] = ["key": "different"]
            default: break
            }
            try S.testSaveState(state, space: space)
            if mode == "pending" {
                let context = S.prepareSubmission(space, payload: space.payload)!
                precondition(S.markSubmissionAccepted(context, space: space))
            }
            if mode == "write" { S.failStateWrite = true }
            if mode == "localChanged" { ProximityLightingImportPreflight.onExport = { space.lastUpdate += 1 } }
            if mode == "membershipChanged" { ProximityLightingImportPreflight.onExport = { SpaceMembershipResponseContext.invalidate() } }
            request.result = .success(["data": remote])
            let result: Swift.Result<Void, NetworkApiError>
            if mode == "cancelled" {
                let task = Task { @MainActor in await S.resumeUpload(space) }; task.cancel(); result = await task.value
            } else { result = await S.resumeUpload(space) }
            ProximityLightingImportPreflight.onExport = nil; S.failStateWrite = false
            if case .success = result { preconditionFailure("unsafe old baseline must remain protected: " + mode) }
            precondition(space.nodes.count == 2 && space.lastUploadCloudTimestamp == 100)
            if mode == "unknownRemoval" {
                precondition(!S.requiresConfigurationReview(space), "one failed observation is still retryable")
                _ = await S.resumeUpload(space)
                precondition(S.requiresConfigurationReview(space), "repeated missing evidence must expose recovery")
            }
            if mode == "write" {
                if case .failure = await S.resumeUpload(space) { preconditionFailure("failed baseline persistence must be retryable") }
            }
        }
        try await testRecoveredCloudVersionArbitration()
        try await testOlderCloudAuthorityRecovery()
        try await testReviewedLocalInstanceReplacement()
        try await testReviewedImportDecodeRejection()
        try await testOlderCloudBaselineReview()
        try await testReviewedCloudImport()
        print("PASS: older equivalent cloud baseline, legacy empty Timed/snapshot recovery, import preservation, upload/readback and strict conflict/lifecycle boundaries")
    }

    @MainActor static func testRecoveredCloudVersionArbitration() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = SpaceConfigurationIntegrityPolicy
        let request = NetworkRequest.shared
        defer { request.responses = []; request.lastSpaceUpload = nil; S.failStateWrite = false }
        for mode in ["upload", "import", "caughtUp", "sameTime", "newProfile", "writeRetry", "missingFailure", "unrelatedBlock"] {
            let (space, baseline) = try olderCloudFixture()
            var localProfile = space.groups[0]["profile"] as! [String: Any]
            localProfile["occupancyLevel"] = 500
            space.groups[0]["profile"] = localProfile
            var stale = baseline
            var staleGroups = baseline["groups"] as! [[String: Any]]
            var staleProfile = staleGroups[0]["profile"] as! [String: Any]
            staleProfile["occupancyLevel"] = 400
            staleGroups[0]["profile"] = staleProfile; stale["groups"] = staleGroups
            if mode == "unrelatedBlock" { S.block(space, reason: "incompleteImportedTopology") }
            request.result = .success(["data": stale])
            for _ in 0..<2 {
                if case .success = await S.resumeUpload(space) {
                    preconditionFailure("conflicting stale responses must not authorize upload")
                }
            }
            precondition(S.needsOlderCloudBaselineReview(space) == (mode != "unrelatedBlock"))
            let blockedState = try S.recoveryState(space)
            if mode == "missingFailure" {
                // A restart can occur between the receipt write and defaults cleanup.
                var saved = blockedState; saved.olderCloudBaselineFailure = nil
                try S.testSaveState(saved, space: space)
            }
            let protectionRequest = SpaceProtectionReadRequest(scope: .init(account: UserData.currentUserId,
                region: String(describing: UserData.currentServerRegion), meshUUID: space.meshUUID,
                networkID: space.meshNetworkId), root: S.testRoot, defaults: S.testDefaults)
            let protectionBefore = protectionRequest.read()
            var recovered = baseline
            recovered["updateTimestamp"] = ["caughtUp", "missingFailure"].contains(mode) ? 100 : mode == "sameTime" ? 110 : 120
            if mode == "newProfile" {
                staleProfile["occupancyLevel"] = 414
                staleGroups[0]["profile"] = staleProfile; recovered["groups"] = staleGroups
            }
            request.result = .success(["data": recovered])
            let uploads = request.uploads
            if mode == "writeRetry" {
                S.failStateWrite = true
                if case .success = await S.resumeUpload(space) {
                    preconditionFailure("failed marker persistence cannot resume version arbitration")
                }
                S.failStateWrite = false
                let retained = try S.recoveryState(space)
                precondition(retained == blockedState && S.needsOlderCloudBaselineReview(space))
                precondition(space.lastUpdate == 110 && request.uploads == uploads)
            }
            if mode == "import" {
                let result = await space.update(spaceJsonData: recovered)
                precondition(result == .preserved("localDeletionOrRecoveryPendingUpload"),
                             "ordinary GET must leave the stale-baseline exemption and arbitrate Profiles")
            } else {
                let result = await S.resumeUpload(space)
                if mode == "sameTime" {
                    if case .success = result { preconditionFailure("equal-version Profile differences require review") }
                } else if case .failure = result { preconditionFailure("recovered version must resume: " + mode) }
            }
            precondition(!S.needsOlderCloudBaselineReview(space))
            if mode == "missingFailure" {
                precondition(!protectionBefore.isCurrent && !protectionRequest.read().isBlocked,
                             "clearing only the review marker must also invalidate cached protection")
            }
            let state = try S.recoveryState(space)
            precondition(state.olderCloudBaselineFailure == nil && state.submission == nil)
            precondition(space.lastUploadCloudTimestamp == 100 && request.uploads == uploads)
            if mode == "sameTime" || mode == "unrelatedBlock" {
                precondition(S.isBlocked(space) && space.lastUpdate == 110)
                precondition(S.debugSnapshotStatus(space)["blockedReason"] as? String
                    == (mode == "sameTime" ? "profileTimestampConflict" : "incompleteImportedTopology"))
                continue
            }
            let cloudWins = !["caughtUp", "missingFailure"].contains(mode)
            let expectedLevel = cloudWins ? (mode == "newProfile" ? 414 : 734) : 500
            precondition(space.lastUpdate == (cloudWins ? 121 : 110) && !S.isBlocked(space))
            precondition(P.integer((space.groups[0]["profile"] as! [String: Any])["occupancyLevel"]) == Int64(expectedLevel))
            precondition(space.nodes.count == 2 && space.needUploadCloud)
            // Reopen before the POST to verify both persisted markers were cleared.
            let reopened = SpaceData(space.id)
            reopened.lastUpdate = space.lastUpdate; reopened.lastUploadCloudTimestamp = 100
            reopened.nodes = space.nodes; reopened.groups = space.groups
            ProximityLightingImportPreflight.storedSpace = reopened
            request.responses = [.success(["data": recovered]), .success([:]), .success(["data": reopened.payload])]
            if case .failure = await S.uploadBeforeUnbind(reopened) {
                preconditionFailure("recovered version must upload and confirm after reopening: " + mode)
            }
            let uploaded = request.lastSpaceUpload!
            precondition(P.integer(uploaded["updateTimestamp"]) == (cloudWins ? 121 : 110))
            precondition(P.sharedProfilesMatch(P.configurationData(uploaded)!, P.configurationData(reopened.payload)!) == true)
            precondition(request.responses.isEmpty && request.uploads == uploads + 1)
            precondition(reopened.lastUploadCloudTimestamp == reopened.lastUpdate && !reopened.needUploadCloud && !S.hasPendingUpload(reopened))
        }
        print("PASS: recovered cloud versions leave stale-review state; upload/import arbitrate Profiles, preserve equal-version/unrelated blocks and retry failed persistence")
    }

    @MainActor static func testOlderCloudAuthorityRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.onPrepare = nil }
        for role in ["owner", "editor"] {
            let (space, original) = try olderCloudFixture()
            var remote = original; remote["role"] = "visitor"
            P.onPrepare = { withUnsafeCurrentTask { $0?.cancel() } }
            let interrupted = await Task { @MainActor in await space.update(spaceJsonData: remote) }.value
            P.onPrepare = nil
            precondition(interrupted == .rejected("staleImportPreparation") && S.requiresAuthorityImport(space))
            // Reopening must retain the interrupted authority import requirement.
            let reopened = SpaceData(space.id)
            reopened.lastUpdate = space.lastUpdate; reopened.lastUploadCloudTimestamp = space.lastUploadCloudTimestamp
            reopened.nodes = space.nodes; reopened.groups = space.groups; reopened.permission = .visitor
            P.storedSpace = reopened
            remote["role"] = role
            let resumed = await reopened.update(spaceJsonData: remote)
            precondition(resumed == .prepared, "old cloud must reach the authority importer after restoring " + role)
            precondition(S.requiresAuthorityImport(reopened) && !S.canAutomaticallyUpload(reopened),
                "import preparation alone cannot restore upload authority")
            // Mesh/SQLite commit is outside this harness; exercise real receipt finalization.
            precondition(S.beginImport(reopened, payload: remote))
            reopened.nodes = remote["nodes"] as! [[String: Any]]
            reopened.lastUpdate = 90; reopened.lastUploadCloudTimestamp = 90
            precondition(S.finishImport(reopened))
            precondition(!S.requiresAuthorityImport(reopened) && S.canAutomaticallyUpload(reopened))
        }
        print("PASS: interrupted visitor import resumes older cloud after owner/editor restoration; upload remains blocked until import finishes")
    }

    @MainActor static func testReviewedLocalInstanceReplacement() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for mode in ["deviceKey", "address", "laterLocalEdit"] {
            let (space, remote) = try olderCloudFixture()
            if mode == "address" { space.nodes[0]["unicastAddress"] = "0030" }
            else { space.nodes[0]["deviceKey"] = String(repeating: "B2", count: 16) }
            space.nodes[0].removeValue(forKey: "custProps")
            request.result = .success(["data": remote])
            for _ in 0..<2 {
                if case .success = await S.resumeUpload(space) {
                    preconditionFailure("automatic upload cannot replace a provisioning instance")
                }
            }
            precondition(S.needsOlderCloudBaselineReview(space))
            let review = await S.cloudBaselineReview(space, local: space.payload)!
            let approved = await S.authorizeLocalRecovery(space, reviewed: review.local, reviewedRemote: review.remote)
            precondition(approved)
            let approvedVersion = space.lastUpdate
            let reopened = SpaceData(space.id)
            reopened.lastUpdate = approvedVersion; reopened.lastUploadCloudTimestamp = space.lastUploadCloudTimestamp
            reopened.nodes = space.nodes; reopened.groups = space.groups
            ProximityLightingImportPreflight.storedSpace = reopened
            if mode == "laterLocalEdit" {
                reopened.lastUpdate += 1
            }
            request.responses = [.success(["data": remote]), .success([:]), .success(["data": reopened.payload])]
            if case .failure = await S.uploadBeforeUnbind(reopened) {
                preconditionFailure("reviewed replacement must upload and confirm after reopening: " + mode)
            }
            precondition(request.responses.isEmpty && reopened.lastUploadCloudTimestamp == reopened.lastUpdate)
            let state = try S.recoveryState(reopened)
            precondition(state.localReplacementVersion == nil && state.prefersLocalMembership == true && !S.hasPendingUpload(reopened))
        }
        print("PASS: reviewed same-UUID Device Key/address replacement uploads after reopening and later edits; unreviewed replacement stays blocked")
    }

    @MainActor static func testReviewedImportDecodeRejection() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for mode in ["groupName", "virtualGroup", "parentAddress", "node", "scheduler"] {
            let (space, valid) = try olderCloudFixture()
            var remote = valid
            if ["groupName", "virtualGroup", "parentAddress"].contains(mode) {
                var groups = remote["groups"] as! [[String: Any]]
                groups[0][mode == "parentAddress" ? "parentAddress" : "name"] = 1
                if mode == "virtualGroup" { groups[0]["isVirtual"] = true }
                remote["groups"] = groups
            } else {
                var nodes = remote["nodes"] as! [[String: Any]]
                if mode == "node" { nodes[0]["vid"] = 1 }
                else { nodes[0]["testSchedulerValid"] = false }
                remote["nodes"] = nodes
            }
            S.block(space, reason: "cloudBaselineNeedsReview")
            request.result = .success(["data": remote])
            let review = await S.cloudBaselineReview(space, local: space.payload)!
            let before = try S.recoveryState(space)
            let journal = try S.deletionJournal(space)
            let prepared = await S.prepareReviewedCloudImport(space, review: review, remote: remote)
            precondition(!prepared && !S.hasPendingImport(space), "undecodable reviewed payload cannot become durable: " + mode)
            let after = try S.recoveryState(space)
            let retained = try S.deletionJournal(space)
            precondition(before == after && retained.entries == journal.entries && space.lastUpdate == 110)
            request.result = .success(["data": valid])
            let corrected = await S.cloudBaselineReview(space, local: space.payload)!
            if mode == "groupName" {
                let local = await S.authorizeLocalRecovery(space, reviewed: corrected.local, reviewedRemote: corrected.remote)
                precondition(local, "decode rejection must keep local recovery available")
            } else {
                let retried = await S.prepareReviewedCloudImport(space, review: corrected, remote: valid)
                precondition(retried && S.hasPendingImport(space), "corrected cloud must be reviewable without replaying invalid input")
            }
        }
        print("PASS: Group/Node/scheduler decode rejection preserves receipts and permits corrected-cloud or local recovery")
    }

    @MainActor static func testOlderCloudBaselineReview() async throws {
        typealias S = SpaceConfigurationSafety
        let request = NetworkRequest.shared
        for mode in ["complete", "remoteChanged", "localChanged", "membershipChanged", "keyChanged", "permission", "write"] {
            let (space, original) = try olderCloudFixture()
            var remote = original
            remote["switches"] = [["id": "switch", "name": "Switch", "proxyNodeAddress": "0009"]]
            space.exportValues["switches"] = [["id": "switch", "name": "Switch"]]
            precondition(S.updateDeletionJournal(space) { $0.entries = [] })
            request.result = .success(["data": remote])
            _ = await S.resumeUpload(space)
            // Observation caches do not turn a repeated business conflict into a new one.
            remote["gatewayOnline"] = true
            request.result = .success(["data": remote])
            _ = await S.resumeUpload(space)
            precondition(S.needsOlderCloudBaselineReview(space))
            let local = space.payload
            let preview = await S.cloudBaselineReview(space, local: local)
            precondition(preview != nil && preview!.message.contains("0009") && preview!.message.contains("→"))
            let withoutPreview = await S.authorizeLocalRecovery(space, reviewed: local)
            precondition(!withoutPreview, "baseline recovery requires a reviewed cloud snapshot")
            switch mode {
            case "remoteChanged": remote["switches"] = [["id": "switch", "name": "Switch", "proxyNodeAddress": "0006"]]
            case "localChanged": request.onRequest = { space.lastUpdate += 1 }
            case "membershipChanged": request.onRequest = { SpaceMembershipResponseContext.invalidate() }
            case "keyChanged": remote["appKey"] = ["key": "changed"]
            case "permission": remote["role"] = "visitor"
            case "write": S.failStateWrite = true
            default: break
            }
            request.result = .success(["data": remote])
            let approved = await S.authorizeLocalRecovery(space, reviewed: local, reviewedRemote: preview!.remote)
            S.failStateWrite = false
            if mode != "complete" {
                precondition(!approved && space.lastUploadCloudTimestamp == 100 && !S.hasPendingUpload(space), "stale/failed review cannot authorize upload: " + mode)
                if mode != "write" { continue }
                let retry = await S.cloudBaselineReview(space, local: space.payload)
                precondition(retry != nil)
                let recovered = await S.authorizeLocalRecovery(space, reviewed: space.payload, reviewedRemote: retry!.remote)
                precondition(recovered, "failed state write must allow a new review after reloading")
            } else { precondition(approved) }
            precondition(!S.isBlocked(space) && space.lastUploadCloudTimestamp == 100 && space.needUploadCloud)
            let approvedVersion = space.lastUpdate
            request.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
            if case .failure = await S.uploadBeforeUnbind(space) { preconditionFailure("explicit replacement must not be blocked again by the old cloud version") }
            precondition(space.lastUploadCloudTimestamp == approvedVersion && !space.needUploadCloud && request.responses.isEmpty)
            let finished = try S.recoveryState(space)
            precondition(finished.localReplacementVersion == nil)
        }
        print("PASS: repeated old-baseline review, device/proxy preview, explicit replacement roundtrip and fresh identity/permission/persistence checks")
    }

    @MainActor static func testReviewedCloudImport() async throws {
        typealias S = SpaceConfigurationSafety
        let (space, remote) = try olderCloudFixture()
        S.block(space, reason: "cloudBaselineNeedsReview")
        NetworkRequest.shared.result = .success(["data": remote])
        let preview = await S.cloudBaselineReview(space, local: space.payload)!
        var changed = remote; changed["updateTimestamp"] = 91
        let rejected = await S.prepareReviewedCloudImport(space, review: preview, remote: changed)
        precondition(!rejected && !S.hasPendingImport(space))
        ProximityLightingImportPreflight.onExport = { SpaceMembershipResponseContext.invalidate() }
        let staleMembership = await S.prepareReviewedCloudImport(space, review: preview, remote: remote)
        ProximityLightingImportPreflight.onExport = nil
        precondition(!staleMembership && !S.hasPendingImport(space))
        let prepared = await S.prepareReviewedCloudImport(space, review: preview, remote: remote)
        precondition(prepared && S.hasPendingImport(space) && S.isBlocked(space))
        precondition(!S.preservesLocalChanges(space), "approved cloud import must not be vetoed by local deletion receipts")
        let unconfirmed = try S.deletionJournal(space)
        precondition(unconfirmed.entries.count == 1, "staging cannot discard local receipts before import completes")
        let reopened = SpaceData(space.id)
        reopened.lastUpdate = space.lastUpdate; reopened.lastUploadCloudTimestamp = space.lastUploadCloudTimestamp
        reopened.nodes = space.nodes; reopened.groups = space.groups
        ProximityLightingImportPreflight.storedSpace = reopened
        precondition(S.pendingImport(reopened)?["updateTimestamp"] as? Int64 == 90)
        let ready = await reopened.update(spaceJsonData: remote)
        precondition(ready == .prepared, "reviewed cloud recovery must reach the existing importer after reopening")
        // The receipt harness stops at the importer boundary. Commit completion
        // is exercised here; actual Mesh/SQLite replacement requires integration.
        precondition(S.beginImport(reopened, payload: remote))
        S.failStateWrite = true
        precondition(!S.finishImport(reopened) && S.hasPendingImport(reopened))
        S.failStateWrite = false
        reopened.nodes = remote["nodes"] as! [[String: Any]]
        reopened.lastUpdate = 90; reopened.lastUploadCloudTimestamp = 90
        precondition(S.finishImport(reopened))
        let finished = try S.deletionJournal(reopened)
        precondition(finished.entries.isEmpty && !S.hasPendingImport(reopened) && !S.isBlocked(reopened))
        for mode in ["referenceCleanup", "invalidTopology", "corruptReceipt"] {
            let (space, remote) = try olderCloudFixture()
            S.block(space, reason: "cloudBaselineNeedsReview")
            NetworkRequest.shared.result = .success(["data": remote])
            let review = await S.cloudBaselineReview(space, local: space.payload)!
            let staged = await S.prepareReviewedCloudImport(space, review: review, remote: remote)
            precondition(staged)
            if mode == "corruptReceipt" {
                precondition(S.updateDeletionJournal(space) { $0.entries = [] })
                try Data("broken".utf8).write(to: S.testDirectory(space).appendingPathComponent("reviewed-cloud-import.json"))
                let result = await space.update(spaceJsonData: remote)
                precondition(result == .rejected("unreadablePendingImport") && S.hasPendingImport(space),
                    "corrupt reviewed intent must not authorize a different GET as replacement")
                continue
            }
            var candidate = remote
            if mode == "referenceCleanup" {
                candidate["nodes"] = space.nodes
                precondition(S.preserveRemoteReferenceCleanup(space, payload: remote, candidate: candidate))
            }
            precondition(S.beginImport(space, payload: candidate))
            space.lastUpdate = 90; space.lastUploadCloudTimestamp = 90
            precondition(S.finishImport(space, validatedTopology: mode != "invalidTopology"))
            precondition(!S.hasPendingImport(space))
            let journal = try S.deletionJournal(space)
            if mode == "referenceCleanup" {
                precondition(journal.entries.isEmpty && S.preservesLocalChanges(space) && space.needUploadCloud,
                    "discarding a newer local version must preserve the imported cleanup's new upload intent")
            } else {
                precondition(journal.entries.count == 1 && S.isBlocked(space),
                    "invalid topology must retain local evidence and stop replaying the reviewed input")
            }
        }
        print("PASS: reviewed cloud choice, stale-preview rejection, durable import resumption and receipt cleanup only after successful import")
    }
}
