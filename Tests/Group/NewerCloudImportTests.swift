import Foundation

extension SpaceData {
    // Execute the production importer through its asynchronous preparation.
    // SQLite/SDK commit remains a boundary; selection, receipts, archive and
    // finishImport below are the actual production implementations.
    @MainActor func restoreNewerCloudFixture(_ remote: [String: Any]) async -> RestoreOutcome {
        let previousStored = ProximityLightingImportPreflight.storedSpace
        ProximityLightingImportPreflight.storedSpace = self
        defer { ProximityLightingImportPreflight.storedSpace = previousStored }
        guard await update(spaceJsonData: remote) == .prepared else { return .init(status: .rejected) }
        let remote = CloudConfigurationDefaults.space(remote)
        let selected = SpaceConfigurationSafety.prefersNewerCloud(self, remote: remote)
            ? remote : (SpaceConfigurationSafety.pendingImport(self) ?? remote)
        guard SpaceData.canDecodeConfigurationImport(selected),
              SpaceConfigurationIntegrityPolicy.configurationData(selected) != nil else { return .init(status: .rejected) }
        if SpaceConfigurationSafety.prefersNewerCloud(self, remote: selected),
           !SpaceConfigurationSafety.beginNewerCloudImport(self, payload: selected) { return .init(status: .rejected) }
        let working = ProximityLightingImportPreflight.lastPayload!
        let original = TimedSchedulerPayloadPolicy.fillingMissingBindings(selected)
        if !NSDictionary(dictionary: original).isEqual(to: working),
           !SpaceConfigurationSafety.preserveRemoteReferenceCleanup(self, payload: original, candidate: working) {
            return .init(status: .rejected)
        }
        guard SpaceConfigurationSafety.beginImport(self, payload: working) else { return .init(status: .rejected) }
        nodes = working["nodes"] as! [[String: Any]]
        groups = working["groups"] as! [[String: Any]]
        exportValues = working.filter { !["uuid", "nodes", "groups", "updateTimestamp", "netKey", "appKey"].contains($0.key) }
        timedSchemaVersion = TimedSchedulerPayloadPolicy.schema(working)!
        lastUpdate = SpaceConfigurationIntegrityPolicy.integer(working["updateTimestamp"])!
        lastUploadCloudTimestamp = lastUpdate
        return .init(status: SpaceConfigurationSafety.finishImport(self) ? .applied : .rejected)
    }
}

extension SpaceRecoveryReceiptTests {
    @MainActor static func testEqualCloudImports() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; P.onPrepare = nil; S.failStateWrite = false }
        for mode in ["clean", "prepared", "accepted", "blocked", "deletion", "preferred", "empty", "retry", "cloudReferences", "legacyFields", "legacyEmpty", "legacyRetry"] {
            let space = SpaceData()
            space.lastUploadCloudTimestamp = 40
            space.nodes = try (1...3).map(membershipNode)
            P.storedSpace = space
            if mode == "prepared" || mode == "accepted" {
                let receipt = S.prepareSubmission(space, payload: space.payload)!
                if mode == "accepted" { precondition(S.markSubmissionAccepted(receipt, space: space)) }
            }
            if mode == "blocked" { S.block(space, reason: "cloudConfigurationConflict") }
            if mode == "preferred" {
                var state = try S.recoveryState(space)
                state.prefersLocalMembership = true; state.localReplacementVersion = 50
                try S.testSaveState(state, space: space)
            }
            if mode == "deletion" {
                precondition(S.updateDeletionJournal(space) {
                    $0.entries.append(.init(id: UUID(), nodeUUID: "old", primaryAddress: 1,
                        elementAddresses: [1], macAddress: nil, productId: nil, stage: .removed))
                })
            }
            let previous = try S.recoveryState(space)
            var remote = space.payload
            remote["spaceName"] = "Web configuration"
            remote["nodes"] = mode == "empty" ? [] : [try membershipNode(2), try membershipNode(4)]
            if mode == "cloudReferences" {
                remote["spaceData"] = ["timedSchemaVersion": 2]
                remote["schedules"] = try staleTimedSchedules(node: membershipNode(1))
                precondition(S.beginNewerCloudImport(space, payload: remote))
                let reopenedState = try S.recoveryState(space)
                precondition(reopenedState.cloudImport?.replacesEqualVersion == true)
            }
            if mode == "legacyFields" || mode == "legacyRetry" {
                remote["groups"] = [["address": "C001", "profile": ["id": "legacy-profile", "type": 1]]]
                remote["schedules"] = [["id": 0]]
                remote.removeValue(forKey: "scenes")
            }
            if mode == "legacyEmpty" {
                for key in ["groups", "scenes", "schedules"] { remote.removeValue(forKey: key) }
            }
            var selectedGeneration: UUID?
            if mode == "legacyRetry" {
                precondition(S.beginNewerCloudImport(space, payload: remote))
                selectedGeneration = try S.recoveryState(space).generation
            }
            NetworkRequest.shared.result = .success(["data": remote])
            if mode == "retry" {
                S.failStateWrite = true
                guard case .failure = await S.resumeUpload(space) else { preconditionFailure("failed staging cannot complete") }
                precondition(space.nodes.count == 3)
                S.failStateWrite = false
            }
            guard case .success = await S.resumeUpload(space) else {
                preconditionFailure("Equal-version Web snapshot must replace local state: \(mode)")
            }
            precondition(space.nodes.count == (mode == "empty" ? 0 : 2), mode)
            precondition(space.payload["spaceName"] as? String == "Web configuration", mode)
            if mode == "cloudReferences" {
                precondition(NSDictionary(dictionary: ["schedules": space.payload["schedules"]!])
                    .isEqual(to: ["schedules": TimedSchedulerPayloadPolicy.fillingMissingBindings(remote)["schedules"]!]))
            }
            if mode == "legacyFields" || mode == "legacyRetry" {
                let profile = space.groups[0]["profile"] as! [String: Any]
                precondition(profile["highEndTrim"] as? Int == 100 && profile["manualOverrideTimeout"] as? Int == 600)
                precondition(space.groups[0]["parentAddress"] as? String == "0000")
                let schedule = (space.payload["schedules"] as! [[String: Any]])[0]
                precondition(schedule["enabled"] as? Bool == false && schedule["action"] as? Int == 15)
                precondition(SpaceConfigurationIntegrityPolicy.configurationsMatch(
                    SpaceConfigurationIntegrityPolicy.configurationData(remote),
                    SpaceConfigurationIntegrityPolicy.configurationData(space.payload)))
            }
            if let selectedGeneration { precondition(try! S.recoveryState(space).generation == selectedGeneration) }
            if mode == "legacyEmpty" { precondition(space.groups.isEmpty) }
            precondition(space.lastUpdate == 50 && space.lastUploadCloudTimestamp == 50 && !space.needUploadCloud)
            precondition(!S.hasPendingUpload(space) && !S.isBlocked(space) && !S.hasPendingImport(space))
            precondition(try! S.deletionJournal(space).entries.isEmpty)
            precondition(!S.markSubmissionAccepted(previous, space: space), "superseded callbacks must stay obsolete")
        }
        print("PASS: equal-version cloud replacement for mixed/empty members, prepared/accepted receipts, local preference, deletion, conflict and failed staging retry")
        if let raw = ProcessInfo.processInfo.environment["SUNSMART_EQUAL_CLOUD_SAMPLES"] {
            let paths = try JSONDecoder().decode([String].self, from: Data(raw.utf8))
            func read(_ path: String) throws -> [String: Any] {
                try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
            }
            let local = (try read(paths[0])["spaces"] as! [[String: Any]])[0]
            var remote = try read(paths[1])["data"] as! [String: Any]
            let space = SpaceData("equal-version-field-sample")
            space.nodes = local["nodes"] as! [[String: Any]]
            space.groups = local["groups"] as! [[String: Any]]
            space.lastUpdate = SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"])!
            space.lastUploadCloudTimestamp = space.lastUpdate - 1
            space.exportValues = local.filter { !["uuid", "nodes", "groups", "updateTimestamp", "netKey", "appKey"].contains($0.key) }
            remote["uuid"] = space.id
            remote["netKey"] = space.payload["netKey"]; remote["appKey"] = space.payload["appKey"]
            P.storedSpace = space
            precondition(S.prepareSubmission(space, payload: space.payload) != nil)
            NetworkRequest.shared.result = .success(["data": remote])
            guard case .success = await S.resumeUpload(space) else { preconditionFailure("field prepared receipt must yield to equal cloud") }
            precondition(space.nodes.count == 9 && space.nodes.contains { $0["unicastAddress"] as? String == "1152" })
            precondition(!space.nodes.contains { ["113A", "115B"].contains($0["unicastAddress"] as? String ?? "") })
            precondition((space.groups.first { $0["address"] as? String == "C002" }?["profile"] as? [String: Any])?["calibrationMode"] as? String == "planeCal")
            precondition(NSDictionary(dictionary: ["schedules": space.payload["schedules"]!])
                .isEqual(to: ["schedules": TimedSchedulerPayloadPolicy.fillingMissingBindings(remote)["schedules"]!]), "equal-version import retains cloud schedule fields")
            precondition(!S.hasPendingUpload(space) && !S.isBlocked(space) && !space.needUploadCloud)
            print("PASS: supplied equal-version 10-to-9 sample imports cloud L11 and C002 calibration, removes local-only L9/L10 and retires prepared receipt")
        }
    }

    @MainActor static func testNewerCloudImports() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; P.onPrepare = nil; S.failCheckpoint = false; S.failStateWrite = false }
        for mode in ["clean", "dirty", "prepared", "accepted", "preferred", "deletion", "blocked", "pending",
                     "downgrade", "empty", "checkpointFailure", "stateFailure", "badKey", "badTimed", "concurrentEdit"] {
            let space = SpaceData()
            space.permission = .editor
            space.nodes = try (1...3).map(membershipNode)
            space.lastUploadCloudTimestamp = 50
            P.storedSpace = space
            let baseline = space.payload
            var state = try S.recoveryState(space)
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(baseline)
            state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(baseline)
            state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(baseline)
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(baseline)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(baseline)
            if mode == "preferred" { state.prefersLocalMembership = true; state.localReplacementVersion = 50 }
            state.sceneRestoreReceipts = Data("[]".utf8)
            try S.testSaveState(state, space: space)
            if ["dirty", "prepared", "accepted", "deletion"].contains(mode) { space.lastUpdate = 55 }
            if ["prepared", "accepted"].contains(mode) {
                let submission = S.prepareSubmission(space, payload: space.payload)!
                if mode == "accepted" { precondition(S.markSubmissionAccepted(submission, space: space)) }
            }
            if mode == "deletion" {
                precondition(S.updateDeletionJournal(space) {
                    $0.entries.append(.init(id: UUID(), nodeUUID: "old", primaryAddress: 1, elementAddresses: [1],
                        macAddress: nil, productId: nil, stage: .removed))
                })
            }
            if mode == "blocked" { S.block(space, reason: "cloudConfigurationConflict") }
            if mode == "pending" { precondition(S.beginImport(space, payload: baseline)) }
            if mode == "downgrade" { space.timedSchemaVersion = 2 }
            var remote = baseline
            remote["role"] = "editor"
            remote["updateTimestamp"] = 60
            remote["nodes"] = mode == "empty" ? [] : Array(space.nodes.prefix(2))
            remote["spaceData"] = ["timedSchemaVersion": mode == "downgrade" ? 1 : 2]
            remote["schedules"] = [["id": 0, "name": "New schedule", "enabled": true, "selectTarget": 1,
                "action": 1, "fadeTime": 0, "hour": 8, "minute": 0, "dayOfWeek": 4,
                "deviceAddresses": [], "nodeSlots": []]]
            if mode == "downgrade" {
                remote["schedules"] = (remote["schedules"] as! [[String: Any]]).map { $0.filter { $0.key != "nodeSlots" } }
            }
            if mode == "badKey" { remote["netKey"] = ["key": "other-network"] }
            if mode == "badTimed" { remote["spaceData"] = ["timedSchemaVersion": 99] }
            if mode == "concurrentEdit" { P.onPrepare = { space.lastUpdate = 70 } }
            S.failCheckpoint = mode == "checkpointFailure"
            S.failStateWrite = mode == "stateFailure"
            let original = try S.recoveryState(space)
            let outcome = await space.restoreNewerCloudFixture(remote)
            S.failCheckpoint = false; S.failStateWrite = false; P.onPrepare = nil
            let failed = ["checkpointFailure", "stateFailure", "badKey", "badTimed", "concurrentEdit"].contains(mode)
            if failed {
                precondition(outcome.status == .rejected, mode)
                precondition(space.nodes.count == 3 && S.isCurrent(original, space: space), mode)
                continue
            }
            precondition(outcome.status == .applied, mode)
            precondition(space.nodes.count == (mode == "empty" ? 0 : 2), mode)
            precondition((space.payload["schedules"] as! [Any]).count == 1, mode)
            precondition(space.lastUpdate == 60 && space.lastUploadCloudTimestamp == 60 && !space.needUploadCloud)
            precondition(!S.isCurrent(original, space: space) && !S.hasPendingUpload(space) && !S.isBlocked(space))
            precondition(!S.markSubmissionAccepted(original, space: space), "late upload cannot confirm")
            precondition(try! S.deletionJournal(space).entries.isEmpty)
            let current = try S.recoveryState(space)
            precondition(current.prefersLocalMembership != true && current.sceneRestoreReceipts == nil)
            precondition(current.cloudImport?.timestamp == 60 && current.nodeIdentitiesBaseline?.count == space.nodes.count)
            precondition(space.timedSchemaVersion == (mode == "downgrade" ? 1 : 2))
        }

        // Higher than last acknowledgement is not necessarily higher than local work.
        let versions = SpaceData(); versions.lastUpdate = 120; versions.lastUploadCloudTimestamp = 100
        P.storedSpace = versions
        for version in [99, 100, 110, 120, 130] {
            var remote = versions.payload; remote["updateTimestamp"] = version
            precondition(S.prefersNewerCloud(versions, remote: remote) == (version >= 120))
        }
        var pending = versions.payload; pending["updateTimestamp"] = 140
        precondition(S.beginImport(versions, payload: pending))
        var middle = versions.payload; middle["updateTimestamp"] = 130
        precondition(!S.prefersNewerCloud(versions, remote: middle))
        middle["updateTimestamp"] = 140
        precondition(!S.prefersNewerCloud(versions, remote: middle), "equal staging version must resume the selected import")
        middle["updateTimestamp"] = 150
        precondition(S.prefersNewerCloud(versions, remote: middle))

        // A durable selection survives an interrupted commit and ignores an older GET.
        let restarting = SpaceData(); restarting.lastUploadCloudTimestamp = 50
        restarting.triggerZones = [.init(items: [.init(groupAddress: 49160, deviceAddress: 554)])]
        P.storedSpace = restarting
        var selected = restarting.payload; selected["updateTimestamp"] = 60
        precondition(S.beginNewerCloudImport(restarting, payload: selected))
        let generation = try S.recoveryState(restarting).generation
        precondition(S.hasNewerCloudImport(restarting))
        let scope = "\(UserData.currentUserId)|\(UserData.currentServerRegion)|\(restarting.meshUUID)|\(restarting.meshNetworkId)"
        let oldMarker = "spaceConfigurationLocalRecoveryPending." + SHA256.hash(data: Data(scope.utf8)).map { String(format: "%02x", $0) }.joined()
        S.testDefaults.set(50, forKey: oldMarker) // interruption before old defaults were removed
        let result = await restarting.restoreNewerCloudFixture(restarting.payload)
        precondition(result.status == .applied && restarting.lastUpdate == 60)
        precondition(P.lastInitialize, "pending newer-cloud import must resolve legacy zones as a whole replacement")
        precondition(!S.preservesLocalChanges(restarting) && S.testDefaults.object(forKey: oldMarker) == nil)
        precondition(try! S.recoveryState(restarting).generation == generation)

        // Both upload readback branches must import the server rather than merge local intent.
        for receipt in [false, true] {
            for normalization in [false, true] {
                let space = SpaceData(); space.lastUploadCloudTimestamp = 40; P.storedSpace = space
                if receipt { _ = S.prepareSubmission(space, payload: space.payload)! }
                var remote = space.payload; remote["updateTimestamp"] = 60; remote["spaceName"] = "Server"
                if normalization {
                    remote["spaceData"] = ["timedSchemaVersion": 2]
                    remote["schedules"] = try staleTimedSchedules(node: membershipNode(1))
                }
                NetworkRequest.shared.result = .success(["data": remote])
                if case .failure = await S.resumeUpload(space) { preconditionFailure("newer cloud readback") }
                precondition(space.lastUpdate == (normalization ? 61 : 60) && space.needUploadCloud == normalization
                    && space.lastUploadCloudTimestamp == 60 && !S.hasPendingUpload(space))
                if normalization {
                    precondition((space.payload["schedules"] as! [[String: Any]]).allSatisfy { ($0["nodeSlots"] as? [Any])?.isEmpty == true })
                }
            }
        }

        let writeSpace = SpaceData()
        let writes = S.beginCloudWrite([writeSpace])
        var released = false
        let waiter = Task { @MainActor in
            let waited = await S.waitForCloudWrite(writeSpace)
            precondition(waited); released = true
        }
        await Task.yield()
        precondition(!released && S.hasCloudWrite(writeSpace))
        S.finishCloudWrite(writes)
        await waiter.value
        precondition(released && !S.hasCloudWrite(writeSpace))
        if let raw = ProcessInfo.processInfo.environment["SUNSMART_NEWER_CLOUD_SAMPLE"],
           let data = raw.data(using: .utf8) {
            let paths = try JSONDecoder().decode([String].self, from: data)
            func read(_ path: String) throws -> [String: Any] {
                try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String: Any]
            }
            let inspection = try read(paths[0])
            let local = (inspection["spaces"] as! [[String: Any]])[0]
            var remote = try read(paths[1])["data"] as! [String: Any]
            let sample = SpaceData(local["uuid"] as! String)
            sample.permission = .editor
            sample.nodes = local["nodes"] as! [[String: Any]]; sample.groups = local["groups"] as! [[String: Any]]
            sample.lastUpdate = SpaceConfigurationIntegrityPolicy.integer(local["updateTimestamp"])!
            sample.lastUploadCloudTimestamp = sample.lastUpdate
            sample.exportValues = local.filter { !["uuid", "nodes", "groups", "updateTimestamp", "netKey", "appKey"].contains($0.key) }
            remote["netKey"] = sample.payload["netKey"]; remote["appKey"] = sample.payload["appKey"]
            S.block(sample, reason: "cloudConfigurationConflict")
            let outcome = await sample.restoreNewerCloudFixture(remote)
            precondition(outcome.status == .applied)
            precondition(sample.nodes.count == 2 && !sample.nodes.contains { $0["name"] as? String == "L1" })
            precondition((sample.payload["schedules"] as! [Any]).count == 1 && sample.timedSchemaVersion == 2)
            precondition(!S.isBlocked(sample) && !S.hasPendingUpload(sample) && !sample.needUploadCloud)
            print("PASS: private Editor sample imports server L2/L3 and Schedule 1, clears historical conflict without uploading the old configuration")
        }
        print("PASS: newer cloud replaces clean/dirty/receipt/deletion/blocked state, versions, legacy Timed, restart, readback and write serialization")
        try testArchivedCheckpointRetention()
    }

    @MainActor static func testArchivedCheckpointRetention() throws {
        typealias S = SpaceConfigurationSafety
        let space = SpaceData(); space.lastUploadCloudTimestamp = space.lastUpdate
        let manager = FileManager.default
        let initial = try S.testDirectory(space)
        let prefix = "archived-" + initial.lastPathComponent + "-"
        func archives() throws -> [URL] {
            try manager.contentsOfDirectory(at: S.testRoot, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix(prefix) }
        }
        func writeSnapshots(_ root: URL, index: Int) throws {
            // Database creation/backup is covered by the SQLite checkpoint suite;
            // use identifiable bytes here to exercise the real retention/move IO.
            for folder in [root, root.appendingPathComponent("checkpoint-one"), root.appendingPathComponent("checkpoint-two")] {
                try manager.createDirectory(at: folder, withIntermediateDirectories: true)
                for file in ["sunsmart.sqlite3", "mesh.sqlite3", "checkpoint-ready"] {
                    try Data("snapshot-\(index)".utf8).write(to: folder.appendingPathComponent(file))
                }
            }
            try Data("checkpoint-two".utf8).write(to: root.appendingPathComponent("latest-checkpoint"))
            try Data("journal-\(index)".utf8).write(to: root.appendingPathComponent("diagnostic.json"))
        }
        func snapshotCount() throws -> Int {
            try archives().filter { manager.fileExists(atPath: $0.appendingPathComponent("sunsmart.sqlite3").path) }.count
        }
        let other = SpaceData()
        let otherRoot = try S.testDirectory(other)
        let unrelated = S.testRoot.appendingPathComponent("archived-" + otherRoot.lastPathComponent + "-unrelated")
        try writeSnapshots(unrelated, index: -1)
        defer { S.failArchiveMove = false; S.failArchivePrune = false; space.savesSucceed = true }
        for index in 0..<5 {
            let current = try S.testDirectory(space)
            try writeSnapshots(current, index: index)
            var remote = space.payload; remote["updateTimestamp"] = space.lastUpdate + 10
            S.failArchiveMove = index == 4
            precondition(S.beginNewerCloudImport(space, payload: remote))
            let before = try archives()
            for archive in before {
                // Stable ordering independent of filesystem creation-time granularity.
                let journal = try String(contentsOf: archive.appendingPathComponent("diagnostic.json"), encoding: .utf8)
                let version = Int(journal.split(separator: "-").last!)!
                try manager.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(version))],
                                          ofItemAtPath: archive.appendingPathComponent("recovery-state.json").path)
            }
            let pendingCount = try snapshotCount()
            if index == 3 { precondition(pendingCount == 3, "pending import must retain the last recoverable databases") }
            space.lastUpdate += 10; space.lastUploadCloudTimestamp = space.lastUpdate
            space.savesSucceed = false
            precondition(!S.finishImport(space) && S.hasPendingImport(space))
            precondition(try! snapshotCount() == pendingCount, "failed finalization cannot prune archives")
            space.savesSucceed = true
            S.failArchivePrune = index == 2
            precondition(S.finishImport(space))
            if index == 2 {
                precondition(try! snapshotCount() == 3, "pruning failure must not fail the successful import")
                S.failArchivePrune = false
                S.retryArchiveMoves(space)
            }
            if index == 4 {
                precondition(manager.fileExists(atPath: current.appendingPathComponent("sunsmart.sqlite3").path),
                             "failed archive moves must preserve the source databases")
                S.failArchiveMove = false
                S.retryArchiveMoves(space)
                precondition(try! S.recoveryState(space).pendingArchives?.isEmpty == true)
            }
            precondition(try! snapshotCount() == min(index + 1, 2), "completed imports must bound historical database snapshots")
            let all = try archives()
            precondition(all.count == index + 1 && all.allSatisfy {
                manager.fileExists(atPath: $0.appendingPathComponent("diagnostic.json").path)
                    && manager.fileExists(atPath: $0.appendingPathComponent("recovery-state.json").path)
            }, "retention must preserve journals and state for every generation")
            for archive in all where manager.fileExists(atPath: archive.appendingPathComponent("sunsmart.sqlite3").path) {
                let snapshot = try String(contentsOf: archive.appendingPathComponent("sunsmart.sqlite3"), encoding: .utf8)
                precondition(["snapshot-\(index)", "snapshot-\(index - 1)"].contains(snapshot),
                             "retention must keep the newest two generations, not arbitrary archives")
                for name in ["mesh.sqlite3", "checkpoint-one/sunsmart.sqlite3", "checkpoint-two/mesh.sqlite3"] {
                    precondition(try! String(contentsOf: archive.appendingPathComponent(name), encoding: .utf8) == snapshot)
                }
            }
            for archive in all where !manager.fileExists(atPath: archive.appendingPathComponent("sunsmart.sqlite3").path) {
                precondition(!manager.fileExists(atPath: archive.appendingPathComponent("mesh.sqlite3").path)
                    && !manager.fileExists(atPath: archive.appendingPathComponent("checkpoint-one/sunsmart.sqlite3").path)
                    && !manager.fileExists(atPath: archive.appendingPathComponent("checkpoint-two/mesh.sqlite3").path)
                    && !manager.fileExists(atPath: archive.appendingPathComponent("latest-checkpoint").path))
            }
        }
        let current = try S.testDirectory(space)
        try writeSnapshots(current, index: 99)
        S.retryArchiveMoves(space)
        precondition(manager.fileExists(atPath: current.appendingPathComponent("sunsmart.sqlite3").path)
            && manager.fileExists(atPath: unrelated.appendingPathComponent("sunsmart.sqlite3").path),
            "startup cleanup must not touch current checkpoints or other Space/account identities")
        print("PASS: archive database retention is bounded after commit, preserves diagnostics and retries failed moves")
    }
}
