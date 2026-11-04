// The runner inserts SpaceData.update through its async guards and legacy Zone gate.
// A prepared result means those boundaries passed, not that Mesh import committed.
enum SpaceImportOutcome: Equatable {
    case prepared, skipped, rejected(String), preserved(String)
}
struct SpaceTriggerZone {
    struct Item { let groupAddress: UInt16; let deviceAddress: UInt16 }
    var items: [Item] = []
}
struct ConfigurationMeshReadSnapshot {}
enum DevicePermanentDeletionContext {
    static var onResume: (() -> Void)?
    static func resume(space: SpaceData) { onResume?() }
    static var failCloudRemoval = false
    static func cloudRemovalInstances(space: SpaceData, expected: [SpaceCloudNodeRemovalPolicy.Instance]) -> [SpaceCloudNodeRemovalPolicy.Instance]? {
        let local = SpaceCloudNodeRemovalPolicy.instances(space.payload) ?? []
        guard expected.allSatisfy({ old in
            local.allSatisfy { node in
                (node.uuid != old.uuid && node.elementAddresses.isDisjoint(with: old.elementAddresses)) || node.matches(old)
            }
        }) else { return nil }
        return expected.map { old in local.first(where: { old.matches($0) }) ?? old }
    }
    static func removeCloudInstances(space: SpaceData, instances: [SpaceCloudNodeRemovalPolicy.Instance],
                                     baselineTimestamp: Int64, remoteTimestamp: Int64, submissionID: UUID?) -> Bool {
        guard !failCloudRemoval else { return false }
        let existing = (try? SpaceConfigurationSafety.deletionJournal(space))?.entries ?? []
        let pending = instances.filter { old in !existing.contains { $0.stage == .cleaned && $0.cloudRemoval?.instance == old } }
        if pending.isEmpty { return true }
        space.nodes.removeAll { node in instances.contains { $0.matches(node) } }
        if let repaired = TimedSchedulerPayloadPolicy.repairingStaleBindings(space.payload), space.exportValues["schedules"] != nil {
            space.exportValues["schedules"] = repaired["schedules"]
        }
        space.lastUpdate = max(space.lastUpdate, remoteTimestamp) + 1
        return SpaceConfigurationSafety.updateDeletionJournal(space) { journal in
            for identity in pending {
                journal.entries.append(.init(id: UUID(), nodeUUID: identity.uuid, primaryAddress: identity.address,
                    elementAddresses: identity.elementAddresses, macAddress: nil, productId: nil,
                    stage: .cleaned, completedTimestamp: space.lastUpdate,
                    cloudRemoval: .init(baselineTimestamp: baselineTimestamp, remoteTimestamp: remoteTimestamp,
                                        submissionID: submissionID, instance: identity)))
            }
        }
    }
}
@MainActor enum ProximityLightingImportPreflight {
    static var onPrepare: (() -> Void)?
    static var onExport: (() -> Void)?
    static var storedSpace: SpaceData?
    static var lastPayload: [String: Any]?
    static var lastInitialize = false
    static var calls = 0
    static func prepare(spaceJsonData: [String: Any], initialize: Bool) async -> Bool {
        calls += 1
        lastPayload = spaceJsonData
        lastInitialize = initialize
        await Task.yield()
        onPrepare?()
        return true
    }
}
extension SpaceData {
    @MainActor static func load(siteId: String, spaceId: String) -> [SpaceData] {
        guard let space = ProximityLightingImportPreflight.storedSpace,
              space.siteId == siteId, space.id == spaceId else { return [] }
        return [space]
    }
    @MainActor func export(purpose: Purpose, readSnapshot: ConfigurationMeshReadSnapshot) async -> [String: Any]? {
        await Task.yield()
        ProximityLightingImportPreflight.onExport?()
        return payload
    }
}
extension SpaceRecoveryReceiptTests {
    static func staleTimedSchedules(node: [String: Any]) throws -> [[String: Any]] {
        let identity = TimedSchedulerPayloadPolicy.identity(node: node)!
        return try (0..<16).map { id in
            let slot = TimedSchedulerNodeSlot(identity: identity, slot: id, state: .assigned)
            return ["id": id, "name": "Retained \(id)", "enabled": true, "selectTarget": 1,
                "action": 1, "fadeTime": 0, "hour": 8, "minute": 0, "dayOfWeek": 127,
                "deviceAddresses": [identity.unicastAddress],
                "nodeSlots": [try JSONSerialization.jsonObject(with: JSONEncoder().encode(slot))]]
        }
    }

    @MainActor static func testStaleTimedImport() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; P.lastPayload = nil }
        for role in ["owner", "editor", "visitor"] {
            for resume in [false, true] {
                let space = SpaceData()
                space.lastUploadCloudTimestamp = space.lastUpdate; space.timedSchemaVersion = 2
                P.storedSpace = space
                var remote = space.payload
                remote["role"] = role; remote["spaceData"] = ["timedSchemaVersion": 2]
                // This test retains the newer-version stale-reference repair policy.
                remote["updateTimestamp"] = space.lastUpdate + 1
                remote["schedules"] = try staleTimedSchedules(node: membershipNode(1))
                if resume { precondition(S.beginImport(space, payload: remote)) }
                for _ in 0..<2 {
                    let outcome = await space.update(spaceJsonData: remote, initialize: !resume)
                    precondition(outcome == .prepared, "stale reservations must not block entry or interrupted-import retry")
                    let working = P.lastPayload!, rows = working["schedules"] as! [[String: Any]]
                    precondition(rows.count == 16 && rows.allSatisfy {
                        ($0["nodeSlots"] as? [Any])?.isEmpty == true && ($0["deviceAddresses"] as? [Any])?.isEmpty == true
                    })
                }
                var working = P.lastPayload!
                precondition(S.preserveRemoteReferenceCleanup(space, payload: remote, candidate: working))
                precondition(S.beginImport(space, payload: working))
                let before = space.lastUpdate
                precondition(S.finishImport(space))
                precondition(!S.isBlocked(space) && !S.hasPendingImport(space))
                precondition(space.lastUpdate == before + (role == "visitor" ? 0 : 1))
                let restored = try S.recoveryState(space)
                precondition(restored.timedConfigurationBaseline == TimedSchedulerPayloadPolicy.canonical(remote))
                if role == "visitor" { continue }
                working["updateTimestamp"] = space.lastUpdate
                let submission = S.prepareSubmission(space, payload: working)!
                precondition(S.markSubmissionAccepted(submission, space: space))
                remote["updateTimestamp"] = space.lastUpdate
                NetworkRequest.shared.result = .success(["data": remote])
                if case .failure = await S.resumeUpload(space) { preconditionFailure("equivalent stale remote references must not prevent readback") }
                precondition(!S.hasPendingUpload(space))
            }
        }
        print("PASS: stale Timed entry for owner/editor/visitor, interrupted replay, repair upload intent and canonical readback")
    }

    @MainActor static func testStaleTimedCloudRemoval() async throws {
        typealias S = SpaceConfigurationSafety
        for accepted in [false, true] {
            let space = SpaceData()
            let old = try membershipNode(1)
            space.nodes = [old]; space.lastUploadCloudTimestamp = accepted ? 49 : 50
            space.exportValues = ["spaceData": ["timedSchemaVersion": 2], "schedules": try staleTimedSchedules(node: old)]
            var remote = space.payload
            if accepted {
                let receipt = S.prepareSubmission(space, payload: remote)!
                precondition(S.markSubmissionAccepted(receipt, space: space))
            } else {
                var state = try S.recoveryState(space)
                state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(remote)
                state.removalSnapshot = SpaceCloudNodeRemovalPolicy.Snapshot.make(remote)
                state.nodeIdentitiesBaseline = SpaceCloudNodeRemovalPolicy.instances(remote)
                state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(remote)
                state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(remote)
                try S.testSaveState(state, space: space)
            }
            remote["nodes"] = [[String: Any]]() // Server removed the old node, but retained its slots.
            var replacement = old
            replacement["unicastAddress"] = "0009"; replacement["deviceKey"] = String(repeating: "B2", count: 16)
            replacement.removeValue(forKey: "custProps")
            space.nodes = [replacement]; space.lastUpdate = 55
            NetworkRequest.shared.result = .success(["data": remote])
            if case .success = await S.resumeUpload(space) { preconditionFailure("old deletion must not clean UUID-scoped references of a new local instance") }
            precondition(space.nodes.count == 1 && space.nodes[0]["unicastAddress"] as? String == "0009")
            precondition(space.nodes[0]["deviceKey"] as? String == replacement["deviceKey"] as? String)
            precondition(space.needUploadCloud && S.hasPendingUpload(space) == accepted)
            precondition(space.lastUploadCloudTimestamp == (accepted ? 49 : 50))
        }
        print("PASS: old cloud deletion cannot clean references belonging to a same-UUID newly provisioned local instance")
    }

    @MainActor static func testProfileTimedImport() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; P.lastPayload = nil }
        for role in ["owner", "editor", "visitor"] {
            for resume in [false, true] {
                let space = SpaceData()
                space.lastUploadCloudTimestamp = space.lastUpdate
                P.storedSpace = space
                var remote = space.payload
                remote["role"] = role; remote["spaceData"] = ["timedSchemaVersion": 1]
                let rows: [[String: Any]] = (0..<2).map { id in
                    ["id": id, "name": "Profile \(id)", "enabled": true, "selectTarget": 3,
                     "action": 2, "fadeTime": 2, "hour": 14 + id, "minute": 28, "dayOfWeek": 127,
                     "sceneAddress": "", "profiles": [["groupAddress": "C000", "profileSceneNumber": "FF00", "groupName": "Group 1", "type": 3]]]
                }
                remote["schedules"] = rows
                if resume { precondition(S.beginImport(space, payload: remote)) }
                for _ in 0..<2 {
                    let outcome = await space.update(spaceJsonData: remote, initialize: !resume)
                    precondition(outcome == .prepared, "Profile sentinel must pass initial and interrupted import preparation")
                    precondition((P.lastPayload?["schedules"] as? [[String: Any]])?.count == 2)
                }
                precondition(S.beginImport(space, payload: remote))
                let pending = S.pendingImport(space)!
                precondition(TimedSchedulerPayloadPolicy.canonical(pending) == TimedSchedulerPayloadPolicy.canonical(remote))
                precondition(S.finishImport(space))
                precondition(!S.hasPendingImport(space))
                if role != "visitor" {
                    var submitted = remote
                    submitted["schedules"] = rows.map { row -> [String: Any] in var row = row; row["sceneAddress"] = NSNull(); return row }
                    let receipt = S.prepareSubmission(space, payload: submitted)!
                    precondition(S.markSubmissionAccepted(receipt, space: space))
                    NetworkRequest.shared.result = .failure(.noNetwork)
                    if case .success = await S.resumeUpload(space) { preconditionFailure("offline readback") }
                    precondition(S.hasPendingUpload(space))
                    NetworkRequest.shared.result = .success(["data": remote])
                    if case .failure = await S.resumeUpload(space) { preconditionFailure("legacy sentinel must confirm equivalent exported null") }
                    precondition(!S.hasPendingUpload(space))
                }
            }
        }
        print("PASS: Profile owner/editor/visitor import preparation, interrupted retry, receipt persistence and legacy/null cloud confirmation")
    }

    @MainActor static func testDefaultedTimedImport() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; P.lastPayload = nil }
        let cases = ["owner", "editor"].flatMap { role in [1, 2].map { (role, $0) } }
        for (role, version) in cases {
            for resume in [false, true] {
                let space = SpaceData()
                space.lastUploadCloudTimestamp = space.lastUpdate
                space.timedSchemaVersion = 2
                if version == 2 { space.nodes = [try membershipNode(1)] }
                P.storedSpace = space
                var remote = space.payload
                remote["role"] = role
                remote["spaceData"] = ["timedSchemaVersion": version]
                remote["schedules"] = (0..<17).map { id -> [String: Any] in
                    var row: [String: Any] = ["id": id, "name": "Retained \(id)", "enabled": true, "selectTarget": 1,
                     "action": 1, "fadeTime": 0, "hour": 8, "minute": 0, "dayOfWeek": 127]
                    if version == 2, id % 3 == 1 { row["nodeSlots"] = NSNull() }
                    if version == 2, id % 3 == 2 { row["nodeSlots"] = [[String: Any]]() }
                    return row
                }
                if version == 2 {
                    let binding = TimedSchedulerNodeSlot(identity: TimedSchedulerPayloadPolicy.identity(node: space.nodes[0])!, slot: 0, state: .assigned)
                    var rows = remote["schedules"] as! [[String: Any]]
                    rows[0]["nodeSlots"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode([binding]))
                    remote["schedules"] = rows
                }
                if resume { precondition(S.beginImport(space, payload: remote)) }
                for _ in 0..<2 {
                    let outcome = await space.update(spaceJsonData: remote, initialize: !resume)
                    precondition(outcome == .prepared, "missing bindings must not block owner/editor or retry")
                    let working = P.lastPayload!
                    let rows = working["schedules"] as! [[String: Any]]
                    precondition(rows.count == 17 && rows.enumerated().allSatisfy { index, row in
                        (row["nodeSlots"] as? [Any])?.count == (version == 2 && index == 0 ? 1 : 0)
                    })
                    precondition(TimedSchedulerPayloadPolicy.schema(working) == 2)
                    precondition(TimedSchedulerPayloadPolicy.canonical(working) == TimedSchedulerPayloadPolicy.canonical(remote))
                }
                let working = P.lastPayload!
                precondition(S.beginImport(space, payload: working))
                precondition(S.finishImport(space))
                precondition(!S.isBlocked(space) && !S.hasPendingImport(space))
                let baseline = try S.recoveryState(space)
                precondition(baseline.timedConfigurationBaseline == TimedSchedulerPayloadPolicy.canonical(remote))
                let submission = S.prepareSubmission(space, payload: working)!
                precondition(S.markSubmissionAccepted(submission, space: space))
                // Equal versions now select the cloud; this receipt check covers
                // an older readback while a newer local revision is pending.
                space.lastUpdate += 1
                if version == 2 {
                    for null in [false, true] {
                        var stripped = remote, rows = remote["schedules"] as! [[String: Any]]
                        rows[0]["nodeSlots"] = null ? NSNull() : nil
                        stripped["schedules"] = rows
                        NetworkRequest.shared.result = .success(["data": stripped])
                        let matches = await S.verifyUploadedConfiguration(space, payload: working)
                        precondition(!matches, "lost assigned bindings cannot acknowledge an upload; conflict recovery is a separate import")
                        precondition(S.hasPendingUpload(space))
                    }
                }
                NetworkRequest.shared.result = .success(["data": remote])
                let confirmation = await S.resumeUpload(space)
                if case .failure = confirmation { preconditionFailure("raw GET must confirm equivalent defaulted Timed data") }
                precondition(!S.hasPendingUpload(space))
            }
        }
        print("PASS: legacy/v2 mixed Timed owner/editor import, pending retry, baseline, lost-binding rejection and upload readback")
    }

    @MainActor static func testLegacyTimedBaselineBackfill() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil; S.failStateWrite = false; DevicePermanentDeletionContext.onResume = nil }
        for failure in ["none", "write", "identity", "topology", "pendingCleanup"] {
            let space = SpaceData()
            P.storedSpace = space
            space.lastUploadCloudTimestamp = space.lastUpdate
            let remote = space.payload
            S.verifyUpgradeBaseline(space, local: remote, remote: remote)
            precondition(S.testMigrated(space))
            // Real old on-disk receipts omit the new optional field while
            // retaining the previously written generic migration marker.
            var old = try S.recoveryState(space)
            old.timedConfigurationBaseline = nil
            try S.testSaveState(old, space: space)
            precondition(!S.needsUpgradeBaseline(space) && S.needsTimedUpgradeBaseline(space))
            var candidate = remote
            if failure == "write" { S.failStateWrite = true }
            if failure == "identity" { candidate["appKey"] = ["key": "changed"] }
            if failure == "topology" { candidate["groups"] = [["address": "C001"]] }
            if failure == "pendingCleanup" {
                space.lastUpdate += 1
                space.nodes = [try membershipNode(1)]
                precondition(S.updateDeletionJournal(space) { journal in
                    journal.entries.append(.init(id: UUID(), nodeUUID: "removed", primaryAddress: 2,
                        elementAddresses: [2], macAddress: nil, productId: nil,
                        stage: .cleaned, completedTimestamp: space.lastUpdate))
                })
            }
            let outcome = await space.update(spaceJsonData: candidate)
            DevicePermanentDeletionContext.onResume = nil
            S.failStateWrite = false
            if failure == "pendingCleanup" {
                precondition(outcome == .preserved("newerLocalConfiguration"))
                precondition(S.needsTimedUpgradeBaseline(space), "selection must not fabricate a confirmed Timed baseline")
                NetworkRequest.shared.responses = [.success(["data": remote]), .success([:]), .success(["data": space.payload])]
                guard case .success = await S.uploadBeforeUnbind(space) else { preconditionFailure("newer local version must establish its baseline through confirmed upload") }
            }
            if ["write", "identity", "topology"].contains(failure) {
                precondition(S.needsTimedUpgradeBaseline(space), "failed backfill must not authorize migration")
                _ = await space.update(spaceJsonData: remote)
            }
            precondition(!S.needsTimedUpgradeBaseline(space))
            let saved = try S.recoveryState(space)
            precondition(saved.timedConfigurationBaseline == TimedSchedulerPayloadPolicy.canonical(remote))
            space.timedSchemaVersion = 2
            space.lastUpdate += 1
            let reentry = await space.update(spaceJsonData: remote)
            precondition(reentry == .preserved("newerLocalConfiguration"))
        }
        let local = SpaceData()
        precondition(!S.needsTimedUpgradeBaseline(local), "never-uploaded Spaces do not need a cloud baseline")
        print("PASS: old receipts with migration marker backfill Timed baseline before migration; identity/topology/write failure retry and v1 reentry")
    }

    @MainActor static func testUnuploadedTimedMigration() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil }
        for submission in ["none", "prepared", "accepted"] {
            let space = SpaceData()
            P.storedSpace = space
            space.lastUploadCloudTimestamp = space.lastUpdate
            var baseline = space.payload
            baseline["role"] = "owner"
            var state = try S.recoveryState(space)
            state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(baseline)
            state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(baseline)
            state.schedulerModelStatesBaseline = SchedulerModelSnapshot.spaceData(baseline)
            try S.testSaveState(state, space: space)
            // First local edit upgrades the schema before any cloud acknowledgement.
            space.timedSchemaVersion = 2
            space.lastUpdate += 1
            if submission != "none" {
                var v2 = space.payload
                v2["spaceData"] = ["timedSchemaVersion": 2]
                let receipt = S.prepareSubmission(space, payload: v2)!
                if submission == "accepted" { precondition(S.markSubmissionAccepted(receipt, space: space)) }
            }
            let before = try S.recoveryState(space)
            let calls = P.calls
            for _ in 0..<2 {
                let result = await space.update(spaceJsonData: baseline)
                precondition(result == .preserved("newerLocalConfiguration"))
                precondition(space.timedSchemaVersion == 2 && space.lastUpdate == 51 && space.needUploadCloud)
                let after = try S.recoveryState(space)
                precondition(after.submission == nil && after.timedConfigurationBaseline == before.timedConfigurationBaseline)
            }
            precondition(P.calls == calls, "confirmed legacy GET must never start the replacing importer")

            for kind in ["newer", "older", "differentTimed", "differentTopology", "differentKeys", "initialize"] {
                var changed = baseline
                switch kind {
                case "newer": changed["updateTimestamp"] = 52
                case "older": changed["updateTimestamp"] = 49
                case "differentTimed":
                    changed["schedules"] = [["id": 0, "name": "Unexpected", "enabled": true,
                        "selectTarget": 1, "action": 1, "fadeTime": 0, "hour": 8, "minute": 0, "dayOfWeek": 1]]
                case "differentTopology": changed["groups"] = [["address": "C001"]]
                case "differentKeys": changed["appKey"] = ["key": "changed"]
                default: break
                }
                let result = await space.update(spaceJsonData: changed, initialize: kind == "initialize")
                if kind == "newer" {
                    precondition(result == .prepared, "higher cloud version owns even a supported legacy Timed schema")
                } else if ["older", "differentTimed", "differentTopology"].contains(kind) {
                    precondition(result == .preserved("newerLocalConfiguration"))
                    precondition(space.timedSchemaVersion == 2 && space.lastUpdate == 51,
                                 "an older cloud cannot import or downgrade local Timed data")
                } else if kind == "differentKeys" {
                    precondition(result == .preserved("newerLocalConfigurationUnavailable"))
                } else {
                    precondition(result == .rejected("timedSchemaDowngrade"), "must reject actual downgrade: \(kind)")
                }
            }
            var visitor = baseline; visitor["role"] = "visitor"
            let revoked = await space.update(spaceJsonData: visitor)
            precondition(revoked == .rejected("timedSchemaDowngrade"), "baseline exception cannot bypass authority import")
        }
        // A failed first toggle can migrate slots without changing the timestamp.
        let rolledBack = SpaceData()
        P.storedSpace = rolledBack
        rolledBack.lastUploadCloudTimestamp = rolledBack.lastUpdate
        var state = try S.recoveryState(rolledBack)
        state.authorizationBaseline = SpaceConfigurationIntegrityPolicy.configurationData(rolledBack.payload)
        state.timedConfigurationBaseline = TimedSchedulerPayloadPolicy.canonical(rolledBack.payload)
        try S.testSaveState(state, space: rolledBack)
        rolledBack.timedSchemaVersion = 2
        let result = await rolledBack.update(spaceJsonData: rolledBack.payload)
        precondition(result == .prepared, "equal cloud also replaces a local migration with no newer version")
        print("PASS: unuploaded v2 migration preserves older baseline GETs; equal cloud replaces local schema and authority changes remain enforced")
    }

    @MainActor static func testEmptyZoneImportGate() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.storedSpace = nil }
        for count in [0, 1, 5] {
            let space = SpaceData()
            space.lastUploadCloudTimestamp = space.lastUpdate
            space.triggerZones = Array(repeating: SpaceTriggerZone(), count: count)
            P.storedSpace = space
            var remote = space.payload
            remote["spaceData"] = [String: Any]()
            for _ in 0..<2 {
                let outcome = await space.update(spaceJsonData: remote)
                precondition(outcome == .prepared && !S.isBlocked(space),
                             "Repeated legacy GETs must not block empty Zone slots")
                precondition(space.triggerZones.count == count && space.triggerZones.allSatisfy { $0.items.isEmpty })
            }
        }
        for malformedLocal in [false, true] {
            let space = SpaceData()
            space.lastUploadCloudTimestamp = space.lastUpdate
            space.triggerZonesLoadFailed = malformedLocal
            space.triggerZones = malformedLocal ? [] : [.init(items: [.init(groupAddress: 49160, deviceAddress: 554)])]
            P.storedSpace = space
            var remote = space.payload
            remote["spaceData"] = [String: Any]()
            let outcome = await space.update(spaceJsonData: remote)
            precondition(outcome == .prepared && !S.isBlocked(space),
                         "Equal-version cloud must replace local Zone members or unreadable storage")
        }
        print("PASS: production import Zone gate accepts repeated legacy reads and equal-version cloud over local members/unreadable storage")
    }

    @MainActor static func testImportPreparation() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.onPrepare = nil; P.onExport = nil; P.storedSpace = nil }

        let invalid = SpaceData()
        P.storedSpace = invalid
        let identity = try S.recoveryState(invalid)
        var badPayload = invalid.payload
        badPayload["role"] = "visitor"
        badPayload["schedules"] = [["id": 300, "nodeSlots": []]]
        let invalidResult = await invalid.update(spaceJsonData: badPayload)
        precondition(invalidResult == .rejected("invalidTimedPayload"))
        let afterInvalid = try S.recoveryState(invalid)
        precondition(invalid.permission == .owner && afterInvalid.generation == identity.generation,
                     "invalid schedules must reject before metadata, authority or database replacement")
        invalid.timedSchemaVersion = 2
        let downgrade = await invalid.update(spaceJsonData: invalid.payload)
        precondition(downgrade == .prepared, "equal cloud selects its supported Timed schema")

        // Fresh visitor recovery starts writable despite the model's visitor role.
        // Existing owner/editor spaces also change generation on downgrade.
        for initialRole in [Permission.visitor, .owner, .editor] {
            let space = SpaceData()
            space.permission = initialRole
            let initialize = initialRole == .visitor
            P.storedSpace = initialize ? nil : space
            let before = try S.recoveryState(space)
            precondition(before.authority == .writable)
            let result = await space.update(spaceJsonData: space.payload.merging(["role": "visitor"], uniquingKeysWith: { _, new in new }), initialize: initialize)
            precondition(result == .prepared, "visitor import must survive its own authority transition")
            let after = try S.recoveryState(space)
            precondition(after.authority == .readOnly && after.generation != before.generation)
            let repeated = await space.update(spaceJsonData: space.payload.merging(["role": "visitor"], uniquingKeysWith: { _, new in new }), initialize: initialize)
            precondition(repeated == .prepared, "unchanged visitor authority must also prepare")
        }

        let owner = SpaceData()
        owner.lastUploadCloudTimestamp = 50
        P.storedSpace = SpaceData(owner.id)
        var exported = false
        P.onExport = { exported = true }
        let unchanged = await owner.update(spaceJsonData: owner.payload)
        precondition(unchanged == .prepared && !exported, "equal cloud bypasses the local upgrade baseline")
        P.onExport = nil

        // Inject changes at each await boundary, including the optional baseline export.
        for duringExport in [false, true] {
            for change in ["authority", "removal", "account", "localVersion", "storedVersion", "cancel"] {
                // Initial import still exports a baseline but has no existing
                // stored-row contract. That race is covered at preparation below.
                if duringExport && change == "storedVersion" { continue }
                let space = SpaceData()
                let stored = SpaceData(space.id)
                space.lastUploadCloudTimestamp = 50
                P.storedSpace = stored
                let mutate: () -> Void = {
                    switch change {
                    case "authority": space.applyRemoteSpaceMetadata(["uuid": space.id, "role": "visitor"])
                    case "removal": precondition(S.beginRemoval(space))
                    case "account": UserData.currentUserId = "changed-during-import"
                    case "localVersion": space.lastUpdate += 1
                    case "storedVersion": stored.lastUpdate += 1
                    default: withUnsafeCurrentTask { $0?.cancel() }
                    }
                }
                P.onPrepare = duringExport ? nil : mutate
                P.onExport = duringExport ? mutate : nil
                let task = Task { @MainActor in
                    await space.update(spaceJsonData: space.payload, initialize: duringExport)
                }
                let result = await task.value
                UserData.currentUserId = "test-account"
                P.onPrepare = nil; P.onExport = nil
                precondition(result == .rejected("staleImportPreparation"), "stale preparation must fail: \(change), export=\(duringExport)")
            }
        }

        let removing = SpaceData()
        precondition(S.beginRemoval(removing))
        let calls = P.calls
        let rejected = await removing.update(spaceJsonData: ["uuid": removing.id, "role": "visitor"], initialize: true)
        precondition(rejected == .rejected("spaceRemovalPending") && P.calls == calls)
        precondition(removing.permission == .owner, "removal guard must still run before metadata")
        print("PASS: production import preparation accepts fresh/repeated visitors and owner/editor downgrade; both awaits reject authority, removal, account, version changes and cancellation")
    }
}
