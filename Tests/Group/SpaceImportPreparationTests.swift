// The runner inserts SpaceData.update through its two async freshness guards.
// A prepared result means that boundary passed, not that Mesh import committed.
enum SpaceImportOutcome: Equatable {
    case prepared, rejected(String), preserved(String)
}
struct ConfigurationMeshReadSnapshot {}
enum DevicePermanentDeletionContext {
    static func resume(space: SpaceData) {}
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
    @MainActor static func testImportPreparation() async throws {
        typealias S = SpaceConfigurationSafety
        typealias P = ProximityLightingImportPreflight
        defer { P.onPrepare = nil; P.onExport = nil; P.storedSpace = nil }

        // Fresh visitor recovery starts writable despite the model's visitor role.
        // Existing owner/editor spaces also change generation on downgrade.
        for initialRole in [Permission.visitor, .owner, .editor] {
            let space = SpaceData()
            space.permission = initialRole
            let initialize = initialRole == .visitor
            P.storedSpace = initialize ? nil : space
            let before = try S.recoveryState(space)
            precondition(before.authority == .writable)
            let result = await space.update(spaceJsonData: ["uuid": space.id, "role": "visitor"], initialize: initialize)
            precondition(result == .prepared, "visitor import must survive its own authority transition")
            let after = try S.recoveryState(space)
            precondition(after.authority == .readOnly && after.generation != before.generation)
            let repeated = await space.update(spaceJsonData: ["uuid": space.id, "role": "visitor"], initialize: initialize)
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
