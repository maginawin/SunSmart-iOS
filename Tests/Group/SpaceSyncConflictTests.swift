import Foundation

extension SpaceRecoveryReceiptTests {
    @MainActor static func testSpaceSyncConflict() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = SpaceConfigurationIntegrityPolicy
        typealias Snapshot = SpaceCloudNodeRemovalPolicy.Snapshot
        defer {
            ProximityLightingImportPreflight.storedSpace = nil
            S.failStateWrite = false
        }
        let sample = SpaceData("empty-scene-comparison")
        sample.nodes = try (1...3).map(membershipNode)
        sample.exportValues = ["spaceData": ["sceneConfigurations": [], "timedSchemaVersion": 1]]
        let submitted = sample.payload
        var absent = submitted
        absent["spaceData"] = ["timedSchemaVersion": 1]
        precondition(P.configurationsMatch(P.configurationData(submitted), P.configurationData(absent)),
                     "empty Scene extension and legacy omission must compare equally")
        precondition(Snapshot.make(submitted) == Snapshot.make(absent))
        // Persisted v4 logical receipts must normalize too, without losing nonempty intent.
        var old = try JSONSerialization.jsonObject(with: P.configurationData(absent)!) as! [String: Any]
        old["sceneConfigurations"] = [Any]()
        precondition(P.configurationsMatch(try! JSONSerialization.data(withJSONObject: old), P.configurationData(absent)))
        var invalid = absent
        invalid["spaceData"] = ["sceneConfigurations": NSNull()]
        precondition(P.configurationData(invalid) == nil && Snapshot.make(invalid) == nil)

        // Only representations which the importer treats as empty are equivalent.
        for mode in ["emptyDefaults", "nonzeroCalibration", "powerUpZero", "beaconFalse", "lostRange"] {
            var local = absent, remote = absent
            var nodes = sample.nodes
            nodes[0].removeValue(forKey: "custProps")
            if mode == "lostRange" { nodes[0]["lightCTLTemperatureRangeMin"] = 2700; nodes[0]["lightCTLTemperatureRangeMax"] = 5000 }
            local["nodes"] = nodes
            nodes.removeLast()
            if mode == "emptyDefaults" {
                nodes[0].merge(["groupAddress": "", "enOceanMacAddress": "", "enOceanKeyScenes": [],
                    "custProps": [:], "lightControlSceneExecuteDatas": [], "pirEnabled": NSNull(),
                    "calibrationRatedPower": 0]) { _, new in new }
            }
            if mode == "nonzeroCalibration" { nodes[0]["calibrationRatedPower"] = 62258 }
            if mode == "powerUpZero" { nodes[0]["powerUpState"] = 0 }
            if mode == "beaconFalse" { nodes[0]["secureNetworkBeacon"] = false }
            if mode == "lostRange" { nodes[0].removeValue(forKey: "lightCTLTemperatureRangeMin"); nodes[0].removeValue(forKey: "lightCTLTemperatureRangeMax") }
            remote["nodes"] = nodes
            precondition((Snapshot.make(local)!.removals(in: Snapshot.make(remote)!) != nil) == (mode == "emptyDefaults"), mode)
        }

        for mode in ["savedV4", "missingV4Proof", "wrongV4Proof", "wrongV4Key", "wrongV4Configuration", "normalReadback"] {
            let space = SpaceData("empty-scene-receipt-" + mode)
            space.lastUploadCloudTimestamp = 49
            space.nodes = sample.nodes
            space.exportValues = sample.exportValues
            let payload = space.payload
            var remote = payload
            remote["spaceData"] = ["timedSchemaVersion": 1]
            if mode != "normalReadback" { remote["nodes"] = Array(space.nodes.prefix(2)) }
            let receipt = S.prepareSubmission(space, payload: payload)!
            precondition(S.markSubmissionAccepted(receipt, space: space))
            if mode != "normalReadback" {
                var state = try S.recoveryState(space)
                state.submission?.removalSnapshot?.comparisonVersion = 4
                try S.testSaveState(state, space: space)
                if mode != "missingV4Proof" {
                    var saved = payload
                    if mode == "wrongV4Proof" { saved["updateTimestamp"] = 48 }
                    if mode == "wrongV4Key" { saved["netKey"] = ["key": "different"] }
                    if mode == "wrongV4Configuration" {
                        var nodes = space.nodes
                        nodes[0]["groupAddress"] = "C001"
                        saved["nodes"] = nodes
                    }
                    precondition(S.recordSnapshot(space, payload: saved))
                }
            }
            ProximityLightingImportPreflight.storedSpace = space
            NetworkRequest.shared.result = .success(["data": remote])
            let outcome = await S.resumeUpload(space)
            if mode == "savedV4" || mode == "normalReadback" {
                guard case .success = outcome else { preconditionFailure("compatible receipt: " + mode) }
                precondition(!S.hasPendingUpload(space) && !S.isBlocked(space))
                precondition(space.nodes.count == (mode == "savedV4" ? 2 : 3))
            } else {
                guard case .failure = outcome else { preconditionFailure("unproven old hashes must not delete") }
                precondition(space.nodes.count == 3 && S.hasPendingUpload(space) && S.isBlocked(space))
            }
        }
        print("PASS: empty Scene compatibility, precise optional-node semantics, strict parameter retention and exact v4 snapshot migration")

        for mode in ["complete", "restart", "stateWrite", "finishWrite", "remoteChanged", "localChanged", "revoked", "cancelled", "activeWrite"] {
            let space = SpaceData("reviewed-same-version-" + mode)
            space.lastUploadCloudTimestamp = 49
            space.nodes = try (1...7).map(membershipNode)
            space.exportValues = ["spaceData": ["sceneConfigurations": [], "timedSchemaVersion": 1]]
            ProximityLightingImportPreflight.storedSpace = space
            var state = try S.recoveryState(space)
            state.prefersLocalMembership = true
            try S.testSaveState(state, space: space)
            let old = SpaceCloudNodeRemovalPolicy.instances(["nodes": [try membershipNode(9)]])![0]
            precondition(S.updateDeletionJournal(space) { journal in
                journal.entries.append(.init(id: UUID(), nodeUUID: old.uuid, primaryAddress: old.address,
                    elementAddresses: old.elementAddresses, macAddress: nil, productId: nil,
                    stage: .cleaned, completedTimestamp: 49))
            })
            let original = space.payload
            precondition(S.recordSnapshot(space, payload: original))
            let originalProofURL = try S.testDirectory(space).appendingPathComponent("last-complete-export.json")
            let originalProof = try Data(contentsOf: originalProofURL)
            let receipt = S.prepareSubmission(space, payload: original)!
            precondition(S.markSubmissionAccepted(receipt, space: space))
            // Observations can change after submission without a new Space timestamp.
            space.nodes[0]["defaultCct"] = 3000
            var remote = original
            var nodes = Array(space.nodes.prefix(6))
            nodes[0]["calibrationRatedPower"] = 62258
            remote["nodes"] = nodes
            remote["spaceData"] = ["timedSchemaVersion": 1]
            NetworkRequest.shared.result = .success(["data": remote])
            guard case .failure = await S.resumeUpload(space) else { preconditionFailure("actual parameter difference requires review") }
            precondition(!space.canEditing)
            guard let preview = await S.cloudBaselineReview(space, local: space.payload) else {
                preconditionFailure("same-version accepted conflict needs a reviewable cloud choice")
            }
            precondition(preview.message.contains("7") && preview.message.contains("6"))
            precondition(S.hasPendingUpload(space) && !S.hasPendingImport(space), "preview/cancel cannot mutate upload authority")
            if mode == "remoteChanged" { nodes[0]["calibrationRatedPower"] = 123; remote["nodes"] = nodes }
            if mode == "localChanged" { space.nodes[0]["calibrationRatedPower"] = 123 }
            if mode == "revoked" { remote["role"] = "visitor" }
            if mode == "stateWrite" { S.failStateWrite = true }
            let write = mode == "activeWrite" ? S.beginCloudWrite([space]) : []
            let prepared: Bool
            if mode == "cancelled" {
                let task = Task { @MainActor in await S.prepareReviewedCloudImport(space, review: preview, remote: remote) }
                task.cancel(); prepared = await task.value
            } else { prepared = await S.prepareReviewedCloudImport(space, review: preview, remote: remote) }
            if !write.isEmpty { S.finishCloudWrite(write) }
            S.failStateWrite = false
            // Revocation switches the active directory; evidence stays in the retired generation.
            let retainedProof = try Data(contentsOf: originalProofURL)
            precondition(retainedProof == originalProof, "review staging/failure cannot replace the accepted generation's proof")
            if !["complete", "restart", "finishWrite"].contains(mode) {
                precondition(!prepared && !S.hasPendingImport(space), mode)
                precondition(mode == "revoked" || S.hasPendingUpload(space), "only authority revocation may retire the receipt")
                precondition(space.nodes.count == 7)
                continue
            }
            precondition(prepared && S.hasPendingImport(space) && S.hasPendingUpload(space))
            precondition(try! S.deletionJournal(space).entries.count == 1)
            precondition(!S.isCurrent(receipt, space: space), "selected cloud invalidates late upload callbacks")
            precondition(!S.markSubmissionAccepted(receipt, space: space))
            precondition(!S.finishAcceptedSubmission(receipt, space: space))
            let reopened = SpaceData(space.id)
            reopened.lastUpdate = space.lastUpdate; reopened.lastUploadCloudTimestamp = space.lastUploadCloudTimestamp
            reopened.nodes = space.nodes; reopened.exportValues = space.exportValues
            ProximityLightingImportPreflight.storedSpace = reopened
            let ready = await reopened.update(spaceJsonData: remote)
            precondition(ready == .prepared, "explicit same-version selection must reach importer after reopening")
            precondition(S.beginImport(reopened, payload: S.pendingImport(reopened)!))
            // Mesh/SQLite replacement is the existing fixture boundary.
            reopened.nodes = remote["nodes"] as! [[String: Any]]
            reopened.exportValues = ["spaceData": remote["spaceData"]!]
            reopened.lastUploadCloudTimestamp = reopened.lastUpdate
            if mode == "finishWrite" {
                S.failStateWrite = true
                precondition(!S.finishImport(reopened) && S.hasPendingImport(reopened))
                S.failStateWrite = false
            }
            precondition(S.finishImport(reopened))
            precondition(try! S.deletionJournal(reopened).entries.isEmpty)
            precondition(reopened.nodes.count == 6 && reopened.canEditing && !S.hasPendingUpload(reopened) && !S.hasPendingImport(reopened))
            precondition(try! S.recoveryState(reopened).prefersLocalMembership != true)
            NetworkRequest.shared.result = .success(["data": reopened.payload])
            guard case .success = await S.resumeUpload(reopened) else { preconditionFailure("reopened recovery must stay clean") }
            // A subsequent addition gets a new receipt; the removed seventh instance never returns.
            reopened.nodes.append(try membershipNode(8)); reopened.lastUpdate += 1
            let next = S.prepareSubmission(reopened, payload: reopened.payload)!
            precondition(S.markSubmissionAccepted(next, space: reopened))
            NetworkRequest.shared.result = .success(["data": reopened.payload])
            guard case .success = await S.resumeUpload(reopened) else { preconditionFailure("post-recovery addition must confirm") }
            precondition(!S.hasPendingUpload(reopened) && !reopened.needUploadCloud && reopened.canEditing)
        }
        print("PASS: accepted same-version cloud recovery, cancellation, changed snapshots, authority, persistence/restart, late callbacks and next device addition")
    }

    @MainActor static func testSpaceSyncConflictFieldSample(_ paths: [String]) async throws {
        func read(_ path: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
        }
        let local = (try read(paths[1])["spaces"] as! [[String: Any]])[0]
        var remote = try read(paths[0])["data"] as! [String: Any]
        typealias S = SpaceConfigurationSafety
        let space = SpaceData(local["uuid"] as! String)
        space.nodes = local["nodes"] as! [[String: Any]]
        space.groups = local["groups"] as! [[String: Any]]
        space.lastUpdate = SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"])!
        space.lastUploadCloudTimestamp = space.lastUpdate - 1
        space.exportValues = local.filter { !["uuid", "nodes", "groups", "updateTimestamp", "netKey", "appKey"].contains($0.key) }
        remote["netKey"] = ["key": space.id]; remote["appKey"] = ["key": "app"]
        ProximityLightingImportPreflight.storedSpace = space
        defer { ProximityLightingImportPreflight.storedSpace = nil }
        var state = try S.recoveryState(space); state.prefersLocalMembership = true
        try S.testSaveState(state, space: space)
        let receipt = S.prepareSubmission(space, payload: space.payload)!
        precondition(S.markSubmissionAccepted(receipt, space: space))
        NetworkRequest.shared.result = .success(["data": remote])
        guard case .failure = await S.resumeUpload(space) else { preconditionFailure("sample's actual parameter differences still require review") }
        let preview = await S.cloudBaselineReview(space, local: space.payload)!
        let selected = await S.prepareReviewedCloudImport(space, review: preview, remote: remote)
        precondition(selected)
        let ready = await space.update(spaceJsonData: remote)
        precondition(ready == .prepared, "field sample must reach the existing importer")
        precondition(S.beginImport(space, payload: S.pendingImport(space)!))
        space.nodes = remote["nodes"] as! [[String: Any]]
        space.groups = remote["groups"] as! [[String: Any]]
        space.exportValues = remote.filter { !["uuid", "nodes", "groups", "updateTimestamp", "netKey", "appKey"].contains($0.key) }
        space.lastUploadCloudTimestamp = space.lastUpdate
        precondition(S.finishImport(space) && space.canEditing && !S.hasPendingUpload(space))
        precondition((local["nodes"] as! [Any]).count == 7 && space.nodes.count == 6)
        precondition(!space.nodes.contains { $0["unicastAddress"] as? String == "49C9" })
        guard case .success = await S.resumeUpload(space) else { preconditionFailure("sample must remain clean after cloud selection") }
        precondition(!space.needUploadCloud && !S.isBlocked(space))
        print("PASS: supplied 7-to-6 field sample reaches reviewed import, retires the reconstructed receipt and keeps the deleted device absent (SDK/network/database boundaries)")
    }
}
