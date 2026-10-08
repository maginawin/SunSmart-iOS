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
        return expected.map { old in local.first(where: { old.matches($0) }) ?? old }
    }
    static func removeCloudInstances(space: SpaceData, instances: [SpaceCloudNodeRemovalPolicy.Instance],
                                     baselineTimestamp: Int64, remoteTimestamp: Int64, submissionID: UUID?) -> Bool {
        guard !failCloudRemoval else { return false }
        space.nodes.removeAll { node in instances.contains { $0.matches(node) } }
        space.lastUpdate = max(space.lastUpdate, remoteTimestamp) + 1
        return SpaceConfigurationSafety.updateDeletionJournal(space) { journal in
            for identity in instances {
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
    static var calls = 0
    static func prepare(spaceJsonData: [String: Any], initialize: Bool) async -> Bool {
        calls += 1
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
                space.nodes = [["uuid": "locally-added", "unicastAddress": "0001"]]
                precondition(S.updateDeletionJournal(space) { journal in
                    journal.entries.append(.init(id: UUID(), nodeUUID: "removed", primaryAddress: 2,
                        elementAddresses: [2], macAddress: nil, productId: nil,
                        stage: .cleaned, completedTimestamp: space.lastUpdate))
                })
                DevicePermanentDeletionContext.onResume = {
                    precondition(!S.needsTimedUpgradeBaseline(space), "backfill must precede resumed cleanup reservations")
                }
            }
            _ = await space.update(spaceJsonData: candidate)
            DevicePermanentDeletionContext.onResume = nil
            S.failStateWrite = false
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
            precondition(reentry == .preserved("localTimedMigrationPendingUpload"))
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
                precondition(result == .preserved("localTimedMigrationPendingUpload"))
                precondition(space.timedSchemaVersion == 2 && space.lastUpdate == 51 && space.needUploadCloud)
                let after = try S.recoveryState(space)
                precondition(after.submission == before.submission && after.timedConfigurationBaseline == before.timedConfigurationBaseline)
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
                precondition(result == .rejected("timedSchemaDowngrade"), "must reject actual downgrade: \(kind)")
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
        precondition(result == .preserved("localTimedMigrationPendingUpload"))
        print("PASS: unuploaded v2 migration preserves confirmed v1 GET across pending receipts/reentry; true downgrade and authority changes remain rejected")
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
            precondition(outcome == .skipped && S.isBlocked(space), "Members or unreadable local zones must stay protected")
        }
        print("PASS: production import Zone gate accepts repeated legacy reads with empty slots and protects members/unreadable storage")
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
        precondition(downgrade == .rejected("timedSchemaDowngrade"))

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
        precondition(unchanged == .prepared && exported, "unchanged owner must pass both await boundaries")
        P.onExport = nil

        // Inject changes at each await boundary, including the optional baseline export.
        for duringExport in [false, true] {
            for change in ["authority", "removal", "account", "localVersion", "storedVersion", "cancel"] {
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
                    await space.update(spaceJsonData: space.payload)
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
