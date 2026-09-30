import Foundation

extension SpaceRecoveryReceiptTests {
    static func firmwareNode(_ id: Int, version: String = "0201050000000000") throws -> [String: Any] {
        var node = try membershipNode(id)
        node["firmwareID"] = version
        node["vid"] = "0003"
        node["compositionHash"] = "00000001"
        node["name"] = "L\(id)"
        return node
    }

    static func testFirmwareThreeWayMerge() throws {
        typealias F = SpaceFirmwareObservation
        let old = try firmwareNode(1)
        let new = try firmwareNode(1, version: "0201060000000000")
        let downgrade = try firmwareNode(1, version: "0200040000000000")
        func values(_ nodes: [[String: Any]]) -> [F] { F.snapshots(["nodes": nodes])! }
        let base = values([old]), cloud = values([new]), lower = values([downgrade])
        let update = F.merge(local: base, remote: cloud, baseline: base)
        precondition(update.conflicts.isEmpty && update.updates == cloud)
        precondition(F.merge(local: cloud, remote: base, baseline: base).updates.isEmpty)
        precondition(F.merge(local: base, remote: lower, baseline: base).updates == lower, "a verified downgrade is valid")
        precondition(F.merge(local: cloud, remote: lower, baseline: base).conflicts.count == 1)
        precondition(F.merge(local: base, remote: cloud, baseline: nil).conflicts.count == 1)
        precondition(F.merge(local: cloud, remote: cloud, baseline: nil).conflicts.isEmpty)
        var unknown = new; unknown.removeValue(forKey: "firmwareID"); unknown.removeValue(forKey: "compositionHash")
        let retained = F.merge(local: base, remote: values([unknown]), baseline: base)
        precondition(retained.updates.isEmpty && retained.baseline == base)
        var replacement = new; replacement["deviceKey"] = String(repeating: "B2", count: 16)
        replacement.removeValue(forKey: "custProps")
        precondition(F.merge(local: base, remote: values([replacement]), baseline: base).updates.isEmpty)
        var malformed = old; malformed["firmwareID"] = "invalid"
        precondition(F.snapshots(["nodes": [malformed]]) == nil)
        precondition(!F.confirms(cloud, remote: base, removed: []), "business readback cannot confirm stale firmware")
        print("PASS: firmware three-way observations, unknown fields, missing baseline, identity replacement and downgrade")
    }

    @MainActor static func testCloudConflictClassification() async throws {
        typealias S = SpaceConfigurationSafety
        for mode in ["firmware", "replacement", "addition", "stale", "firmwareWriteFailure", "missingFirmwareBaseline"] {
            let space = SpaceData("conflict-" + mode)
            space.nodes = try (1...3).map { try firmwareNode($0) }
            space.lastUpdate = 100; space.lastUploadCloudTimestamp = 100
            let baseline = space.payload
            var state = try S.recoveryState(space)
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(baseline)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(baseline)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(baseline)
            state.firmwareBaseline = SpaceFirmwareObservation.snapshots(baseline)
            state.firmwareBaselineTimestamp = 100
            try S.testSaveState(state, space: space)
            var remote = baseline
            var remoteNodes = space.nodes
            if mode == "firmware" || mode == "firmwareWriteFailure" || mode == "missingFirmwareBaseline" { remoteNodes[0]["firmwareID"] = "0201060000000000" }
            if mode == "addition" { remoteNodes.append(try firmwareNode(4)) }
            if mode == "replacement" {
                var replacement = try firmwareNode(4)
                replacement["uuid"] = remoteNodes[0]["uuid"]
                replacement.removeValue(forKey: "custProps")
                remoteNodes[0] = replacement
            }
            remote["nodes"] = remoteNodes; remote["updateTimestamp"] = mode == "stale" ? 99 : 110
            space.nodes.append(try firmwareNode(9)); space.lastUpdate = 120
            NetworkRequest.shared.result = .success(["data": remote])
            let calls = NetworkRequest.shared.calls, uploads = NetworkRequest.shared.uploads
            if mode == "missingFirmwareBaseline" { state.firmwareBaseline = nil; try S.testSaveState(state, space: space) }
            space.firmwareWritesSucceed = mode != "firmwareWriteFailure"
            let result = await S.resumeUpload(space)
            precondition(NetworkRequest.shared.calls == calls + 1 && NetworkRequest.shared.uploads == uploads)
            if mode == "firmware" {
                if case .failure = result { preconditionFailure("remote firmware must merge before exporting a local addition") }
                precondition(space.nodes[0]["firmwareID"] as? String == "0201060000000000")
                precondition(space.lastUpdate == 120 && space.lastUploadCloudTimestamp == 100 && space.nodes.count == 4)
                let confirmed = try S.recoveryState(space)
                precondition(confirmed.firmwareBaselineTimestamp == 110)
            } else if mode == "firmwareWriteFailure" {
                guard case .failure(.configurationUnavailable) = result else { preconditionFailure("failed Mesh writes cannot advance baseline") }
                let saved = try S.recoveryState(space)
                precondition(saved.firmwareBaselineTimestamp == 100 && saved.firmwareBaseline == state.firmwareBaseline)
                precondition(!S.needsCloudReview(space))
            } else {
                guard case .failure(let error) = result else { preconditionFailure("must reject unsafe upload") }
                precondition(error == (mode == "stale" ? .configurationUploadUnconfirmed : .configurationReviewRequired))
                precondition(S.needsCloudReview(space) == (mode != "stale"))
                precondition(space.nodes.count == 4 && space.lastUpdate == 120)
            }
        }
        print("PASS: one-GET conflict classification, firmware merge retaining local additions, stale readback remains retryable")
    }

    @MainActor static func testOrdinaryFirmwareRefresh() async throws {
        typealias S = SpaceConfigurationSafety
        for mode in ["dirtyNewerCloud", "localFirmware", "sameTimestamp", "missingField"] {
            let space = SpaceData("ordinary-firmware-" + mode)
            space.nodes = [try firmwareNode(1)]
            space.lastUpdate = 100; space.lastUploadCloudTimestamp = 100
            var state = try S.recoveryState(space)
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(space.payload)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(space.payload)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(space.payload)
            state.firmwareBaseline = SpaceFirmwareObservation.snapshots(space.payload)
            state.firmwareBaselineTimestamp = 100
            try S.testSaveState(state, space: space)
            var remote = space.payload
            var remoteNodes = space.nodes
            if mode == "localFirmware" { space.nodes[0]["firmwareID"] = "0201060000000000" }
            else if mode == "missingField" { remoteNodes[0].removeValue(forKey: "firmwareID") }
            else { remoteNodes[0]["firmwareID"] = "0201060000000000" }
            remote["nodes"] = remoteNodes
            remote["updateTimestamp"] = mode == "sameTimestamp" ? 100 : 200
            if mode == "dirtyNewerCloud" { space.nodes.append(try firmwareNode(9)); space.lastUpdate = 120 }
            ProximityLightingImportPreflight.storedSpace = space
            let outcome = await space.update(spaceJsonData: remote)
            ProximityLightingImportPreflight.storedSpace = nil
            if mode == "sameTimestamp" {
                precondition(outcome == .prepared && !space.needUploadCloud)
            } else {
                precondition(outcome == .preserved("localEditsPendingUpload") && space.needUploadCloud)
            }
            precondition(space.nodes[0]["firmwareID"] as? String == (mode == "missingField" ? "0201050000000000" : "0201060000000000"))
            if mode == "dirtyNewerCloud" { precondition(space.nodes.count == 2 && space.lastUpdate == 120) }
            let saved = try S.recoveryState(space)
            precondition(saved.firmwareBaselineTimestamp == (mode == "sameTimestamp" ? 100 : 200))
        }
        print("PASS: ordinary GET preserves dirty additions against newer cloud clocks, local device observations, unknown fields and same-clock firmware updates")
    }

    @MainActor static func testReviewedCloudRecovery() async throws {
        typealias S = SpaceConfigurationSafety
        for mode in ["include", "exclude", "localChanged", "cloudChanged", "writeFailure", "stagedCloudChanged", "stagedLocalChanged", "knownDeleted", "authorityLoss"] {
            let space = SpaceData("reviewed-" + mode)
            space.nodes = [try firmwareNode(1), try firmwareNode(9)]
            space.lastUpdate = 120; space.lastUploadCloudTimestamp = 100
            var remote = space.payload
            var replacement = try firmwareNode(4, version: "0201060000000000")
            replacement["uuid"] = space.nodes[0]["uuid"]
            replacement.removeValue(forKey: "custProps")
            remote["nodes"] = [replacement, try firmwareNode(2)]
            remote["updateTimestamp"] = 110
            NetworkRequest.shared.result = .success(["data": remote])
            if mode == "knownDeleted" {
                let removed = SpaceCloudNodeRemovalPolicy.instances(remote)!.last!
                precondition(S.updateDeletionJournal(space) { journal in
                    journal.entries.append(.init(id: UUID(), nodeUUID: removed.uuid, primaryAddress: removed.address,
                        elementAddresses: removed.elementAddresses, macAddress: nil, productId: nil, stage: .cleaned,
                        completedTimestamp: 120, cloudRemoval: .init(baselineTimestamp: 100, remoteTimestamp: 110,
                            submissionID: nil, instance: removed)))
                })
            }
            S.block(space, reason: "cloudMembershipChanged")
            let review = await S.cloudRecoveryReview(space)
            guard let review else { preconditionFailure("valid conflicting snapshots must be reviewable") }
            precondition(review.preview.retainedLocal.count == 1 && review.preview.replaced.count == 1 && review.ambiguousRemote.count == (mode == "knownDeleted" ? 0 : 1))
            precondition(!S.hasPendingImport(space) && space.nodes.count == 2, "review/cancel does not alter either database")
            if mode == "localChanged" { space.lastUpdate += 1 }
            if mode == "cloudChanged" { remote["updateTimestamp"] = 111; NetworkRequest.shared.result = .success(["data": remote]) }
            S.failStateWrite = mode == "writeFailure"
            let staged = await S.applyCloudRecovery(space, review: review, includeCloudOnly: mode != "exclude")
            S.failStateWrite = false
            if ["localChanged", "cloudChanged", "writeFailure"].contains(mode) {
                precondition(!staged && !S.hasPendingImport(space) && space.nodes.count == 2)
                continue
            }
            precondition(staged && S.hasPendingImport(space) && !S.preservesLocalChanges(space))
            precondition(!S.isCurrent(review.context, space: space), "old callbacks cannot mutate the reviewed generation")
            // Restart boundary: the candidate exists in the durable state before
            // any import file or database write, so ordinary entry can resume it.
            if mode == "stagedCloudChanged" || mode == "stagedLocalChanged" {
                if mode == "stagedCloudChanged" { remote["updateTimestamp"] = 111 }
                else { space.lastUpdate += 1 }
                let allowed = await S.prepareReviewedImport(space, remote: remote)
                precondition(!allowed && !S.hasPendingImport(space) && S.needsCloudReview(space))
                precondition(space.nodes.count == 2, "stale staged import must not change the database")
                continue
            }
            if mode == "authorityLoss" {
                space.permission = .visitor
                S.reconcileAuthority(space, remote: remote)
                let revoked = try S.recoveryState(space)
                precondition(revoked.reviewedImport == nil && revoked.firmwareBaseline == nil && !S.hasPendingImport(space))
                precondition(!S.canAutomaticallyUpload(space) && space.nodes.count == 2)
                continue
            }
            let replay = S.pendingImport(space)!
            let nodes = replay["nodes"] as! [[String: Any]]
            precondition(nodes.count == (["exclude", "knownDeleted"].contains(mode) ? 2 : 3))
            precondition(nodes.contains { $0["uuid"] as? String == space.nodes[1]["uuid"] as? String })
            ProximityLightingImportPreflight.storedSpace = space
            let outcome = await space.update(spaceJsonData: remote)
            ProximityLightingImportPreflight.storedSpace = nil
            precondition(outcome == .prepared, "reviewed candidate must pass its own protected import prefix")
            precondition(S.beginImport(space, payload: replay))
            var changedAfterStart = remote; changedAfterStart["updateTimestamp"] = 111
            let resumesStarted = await S.prepareReviewedImport(space, remote: changedAfterStart)
            precondition(resumesStarted, "an import that started must finish replaying its original candidate")
            // The actual Mesh importer is the integration boundary in this harness.
            space.nodes = nodes
            space.lastUpdate = SpaceConfigurationIntegrityPolicy.integer(replay["updateTimestamp"])!
            space.lastUploadCloudTimestamp = space.lastUpdate
            space.savesSucceed = false
            precondition(!S.finishImport(space) && S.hasPendingImport(space), "a failed DB write retains the recovery candidate")
            space.savesSucceed = true
            precondition(S.finishImport(space) && !S.hasPendingImport(space))
            precondition(space.needUploadCloud && space.lastUploadCloudTimestamp == 110)
            precondition(!S.isBlocked(space) && S.preservesLocalChanges(space))
            let state = try S.recoveryState(space)
            precondition(state.nodeIdentitiesBaseline == SpaceCloudNodeRemovalPolicy.instances(remote))
            precondition(state.reviewedImport == nil && state.submission == nil)
            NetworkRequest.shared.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
            if case .failure = await S.uploadBeforeUnbind(space) { preconditionFailure("the reviewed merged generation must upload and confirm") }
            precondition(NetworkRequest.shared.responses.isEmpty && !space.needUploadCloud && !S.preservesLocalChanges(space))
        }
        print("PASS: reviewed replacement retains local-only devices, explicit cloud-only choice, stale review, persistence failure, restart and upload confirmation")
    }
}
