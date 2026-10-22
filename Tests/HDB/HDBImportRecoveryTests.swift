import Foundation

let jsonEncoder = JSONEncoder(), jsonDecoder = JSONDecoder()
final class SunSmartDataManager {
    static let shared = SunSmartDataManager()
    var db: Bool? = true
}
struct Schedule: Codable {}
struct SiteImportTrace { init(_ name: String) {}; func mark(_ stage: String) {} }
enum ImportOutcome {
    case rejected(String), preserved(String)
    case prepared([String: Any], HDBConfiguration?)
}
enum SyncError { case configurationUploadUnconfirmed }
final class SpaceData {
    static var persisted: SpaceData?
    var id = "space", siteId = "site"
    var hdb: HDBConfiguration?, hdbPersistenceBaseline: HDBConfiguration?
    var hdbLoadFailed = false, triggerZonesLoadFailed = false
    var lastUpdate: Int64 = 110, lastUploadCloudTimestamp: Int64? = 110
    var timedSchemaVersion = 1
    var syncCloudError: SyncError?
    static func load(siteId: String, spaceId: String) -> [SpaceData] { persisted.map { [$0.copy()] } ?? [] }
    func copy() -> SpaceData {
        let result = SpaceData()
        result.applyConfigurationState(from: self)
        return result
    }
    func applyConfigurationState(from other: SpaceData) {
        hdb = other.hdb; hdbPersistenceBaseline = other.hdbPersistenceBaseline
        hdbLoadFailed = other.hdbLoadFailed; triggerZonesLoadFailed = other.triggerZonesLoadFailed
        lastUpdate = other.lastUpdate; lastUploadCloudTimestamp = other.lastUploadCloudTimestamp
        timedSchemaVersion = other.timedSchemaVersion
    }
    func applyRemoteSpaceMetadata(_ payload: [String: Any]) {}
    // PRODUCTION_SAVE
    func prepareImport(spaceJsonData: [String: Any], initialize: Bool = false) async -> ImportOutcome {
        // PRODUCTION_IMPORT_PREPARATION
        _ = timedReferencesChanged
        return .prepared(spaceJsonData, incomingHDB)
    }
}
enum TimedSchedulerPayloadPolicy {
    static func repairingStaleBindings(_ payload: [String: Any]) -> [String: Any]? { payload }
    static func fillingMissingBindings(_ payload: [String: Any]) -> [String: Any] { payload }
    static func schema(_ payload: [String: Any]) -> Int? { 1 }
    static func canonical(_ payload: [String: Any]) -> Data? { Data() }
}
enum SpaceSyncCleanupPolicy {
    struct Result { var payload: [String: Any] }
    static func normalize(_ payload: [String: Any]) throws -> Result { .init(payload: payload) }
}
enum DevicePermanentDeletionContext { static func resume(space: SpaceData) {} }
enum SpaceConfigurationSafety {
    enum Phase { case active }
    struct State { var phase = Phase.active }
    enum Reconciliation { case preserveLocal, failed, notApplicable }
    static var pending: [String: Any]?, reviewed: [String: Any]?
    static var unreadable = false
    static func recoveryState(_ space: SpaceData) throws -> State { State() }
    static func hasPendingImport(_ space: SpaceData) -> Bool { unreadable || pending != nil || reviewed != nil }
    static func hasReviewedCloudImport(_ space: SpaceData) -> Bool { reviewed != nil }
    static func preserveDefaultConfiguration(_ space: SpaceData, remote: [String: Any]) -> ImportOutcome? { nil }
    static func pendingImport(_ space: SpaceData) -> [String: Any]? { pending ?? reviewed }
    static func originalReferenceCleanupImport(_ space: SpaceData, candidate: [String: Any]) -> [String: Any]? { nil }
    static func isConfirmedTimedBaseline(_ space: SpaceData, remote: [String: Any]) -> Bool { false }
    static func backfillTimedUpgradeBaseline(_ space: SpaceData, remote: [String: Any]) {}
    static func requiresAuthorityImport(_ space: SpaceData) -> Bool { false }
    static func reconcileOlderCloudBaseline(_ space: SpaceData, remote: [String: Any]) async -> Reconciliation { .notApplicable }
    static func reconcileCloudProfiles(_ space: SpaceData, remote: [String: Any]) async -> Bool { true }
    static func reconcileCloudMembership(_ space: SpaceData, remote: [String: Any]) -> Bool { true }
    static func recordSyncFailure(_ space: SpaceData, error: SyncError, stage: String) {}
    static func preservesLocalChanges(_ space: SpaceData) -> Bool { false }
}

final class RecoverySpaceLists {
    struct Site { var spaces: [SpaceData] }
    var site = Site(spaces: [])
    var allSpaces: [SpaceData] = [], favouriteSpaces: [SpaceData] = []
    func reloadSpaceData(_ space: SpaceData) {
        // PRODUCTION_LIST_REFRESH
    }
}

@main enum HDBImportRecoveryTests {
    static let nodeID = UUID()
    static func configuration(_ name: String, status: HDBSyncStatus = .pending) -> HDBConfiguration {
        var config = HDBConfiguration(lightingZones: [.init(zoneId: 1, name: name, groupAddress: 0xC000)],
            devices: [.init(nodeUuid: nodeID, nodeAddress: 1, mac: "AA:BB:CC:DD:EE:FF",
                lightingZones: [.init(zoneId: 1)])])
        config.devices[0].lightingZonesStatus = status
        config.devices[0].lightingConfiguration?.mark(fields: ["brightIntensity"], status: status)
        return config
    }
    static func payload(_ config: HDBConfiguration?, timestamp: Int64) throws -> [String: Any] {
        var result: [String: Any] = ["uuid": "space", "updateTimestamp": timestamp, "schedules": [[String: Any]](),
            "groups": [["address": "C000", "isVirtual": false]],
            "nodes": [["uuid": nodeID.uuidString, "unicastAddress": "0001"]]]
        if let config = config { result["spaceData"] = ["hdb": try HDBLightingZonePolicy.json(config)] }
        return result
    }
    static func main() async throws {
        let legacyHDB: [String: Any] = ["schemaVersion": 1, "devices": [[String: Any]](),
            "lightingZones": [["zoneId": 1, "name": "Old", "groupAddress": 0xC000]]]
        do { _ = try jsonDecoder.decode(HDBConfiguration.self, from: JSONSerialization.data(withJSONObject: legacyHDB)); fatalError("old stored HDB must not load as v2") }
        catch HDBConfigurationError.invalidData {}
        let existing = SpaceData()
        existing.hdb = configuration("Keep"); existing.hdbPersistenceBaseline = existing.hdb
        SpaceData.persisted = existing.copy()
        let legacyPayload: [String: Any] = ["uuid": "space", "updateTimestamp": 110,
            "spaceData": ["hdb": legacyHDB], "schedules": [[String: Any]](), "groups": [], "nodes": []]
        guard case .rejected("invalidHDBPayload") = await existing.prepareImport(spaceJsonData: legacyPayload) else {
            fatalError("legacy import must be rejected without replacing current configuration")
        }
        precondition(existing.hdb == SpaceData.persisted!.hdb && existing.hdb?.lightingZones.first?.name == "Keep")
        print("PASS: legacy HDB decoding/import rejected without clearing existing configuration")

        // Retain the 63-Zone, multi-node recovery coverage using the current format.
        let directory = HDBConfiguration(lightingZones: (1...63).map {
            .init(zoneId: $0, name: "Zone \($0)", groupAddress: UInt16(0xC000 + $0))
        })
        let candidate = SpaceData()
        candidate.hdb = directory; candidate.hdbPersistenceBaseline = directory
        SpaceData.persisted = candidate.copy()
        precondition(candidate.save())
        var currentPayload = try payload(directory, timestamp: 110)
        currentPayload["groups"] = directory.lightingZones.map { ["address": String(format: "%04X", $0.groupAddress), "isVirtual": false] as [String: Any] }
        currentPayload["nodes"] = (0..<4).map { ["uuid": UUID().uuidString, "unicastAddress": String(format: "%04X", 2 + $0 * 3)] }
        guard case .prepared(let selectedPayload, let selectedHDB) = await candidate.prepareImport(spaceJsonData: currentPayload),
              selectedHDB == directory else { fatalError("current HDB cloud recovery failed") }
        precondition(selectedPayload["nodes"] as? [[String: String]] == currentPayload["nodes"] as? [[String: String]])
        candidate.hdb = selectedHDB
        precondition(candidate.save(importingConfiguration: true))
        let reloaded = SpaceData.load(siteId: "site", spaceId: "space").first!
        precondition(reloaded.hdb == directory && !reloaded.hdbLoadFailed && reloaded.save())
        print("PASS: v2 HDB pre-import save/reload preserves 63 Zones and the selected 4-node payload")

        let old = configuration("Local"), cloud = configuration("Cloud", status: .synced)
        // Restoration must adopt the selected revision both with and without HDB.
        for localConfig in [old, nil] {
            let local = SpaceData()
            local.hdb = localConfig; local.hdbPersistenceBaseline = localConfig
            SpaceData.persisted = local.copy()
            let imported = local.copy()
            imported.hdb = localConfig == nil ? nil : cloud
            imported.lastUpdate = 90; imported.lastUploadCloudTimestamp = 90
            precondition(imported.save(importingConfiguration: true))
            precondition(SpaceData.persisted!.lastUpdate == 90 && SpaceData.persisted!.lastUploadCloudTimestamp == 90)
            // A subsequent ordinary topology save must not revive revision 110.
            precondition(imported.save() && SpaceData.persisted!.lastUpdate == 90)
            imported.lastUpdate = 95; imported.lastUploadCloudTimestamp = 95
            precondition(imported.save(importingConfiguration: true) && SpaceData.persisted!.lastUpdate == 95)
        }
        let corrupt = SpaceData()
        corrupt.hdbLoadFailed = true; SpaceData.persisted = corrupt.copy()
        let recovery = corrupt.copy()
        recovery.hdbLoadFailed = false; recovery.hdb = cloud
        recovery.lastUpdate = 90; recovery.lastUploadCloudTimestamp = 90
        precondition(!recovery.save(), "ordinary objects cannot erase corrupt HDB")
        recovery.hdb!.lightingZones[0].groupAddress = 1
        precondition(!recovery.save(importingConfiguration: true), "import still validates HDB")
        precondition(SpaceData.persisted!.hdbLoadFailed)
        recovery.hdb = cloud
        precondition(recovery.save(importingConfiguration: true))
        precondition(!SpaceData.persisted!.hdbLoadFailed && SpaceData.persisted!.hdb == cloud)
        SpaceData.persisted = corrupt.copy()
        recovery.hdb = nil
        precondition(recovery.save(importingConfiguration: true) && SpaceData.persisted!.hdb == nil,
                     "a valid legacy snapshot can clear corrupt HDB")
        let stale = SpaceData()
        stale.hdb = old; stale.hdbPersistenceBaseline = old; stale.lastUpdate = 80
        let latest = SpaceData()
        latest.hdb = cloud; latest.hdbPersistenceBaseline = cloud
        SpaceData.persisted = latest.copy()
        precondition(stale.save())
        precondition(stale.hdb == cloud && stale.lastUpdate == 110)
        stale.hdb = old
        SpaceData.persisted!.hdb = nil
        precondition(!stale.save(), "conflicting stale edits remain rejected")
        print("PASS: production save guards restore older revisions, recover corrupt HDB, validate imports and protect stale saves")

        let space = SpaceData(); SpaceData.persisted = space.copy()
        let request = try payload(configuration("Request", status: .synced), timestamp: 120)
        let selected = try payload(configuration("Selected"), timestamp: 90)
        for reviewed in [false, true] {
            SpaceConfigurationSafety.pending = reviewed ? nil : selected
            SpaceConfigurationSafety.reviewed = reviewed ? selected : nil
            guard case .prepared(let actual, let config) = await space.prepareImport(spaceJsonData: request) else { fatalError("valid staged import rejected") }
            precondition(actual["updateTimestamp"] as? Int64 == 90 && config == configuration("Selected"),
                         "HDB and topology must come from the same staged snapshot")
        }
        SpaceConfigurationSafety.reviewed = nil
        var invalid = selected
        invalid["nodes"] = [["uuid": UUID().uuidString, "unicastAddress": "0001"]]
        SpaceConfigurationSafety.pending = invalid
        guard case .rejected("invalidHDBPayload") = await space.prepareImport(spaceJsonData: request) else { fatalError("invalid staged references accepted") }
        SpaceConfigurationSafety.pending = try payload(nil, timestamp: 90)
        guard case .prepared(_, nil) = await space.prepareImport(spaceJsonData: request) else { fatalError("legacy snapshot mixed with request HDB") }
        SpaceConfigurationSafety.pending = nil
        guard case .prepared(_, let config) = await space.prepareImport(spaceJsonData: request),
              config == configuration("Request", status: .synced) else { fatalError("normal import changed") }
        SpaceConfigurationSafety.unreadable = true
        guard case .rejected("unreadablePendingImport") = await space.prepareImport(spaceJsonData: request) else { fatalError("unreadable staging bypassed") }
        print("PASS: production import preparation uses pending/reviewed HDB, validates selected references and preserves legacy nil")
        let lists = RecoverySpaceLists()
        let oldSite = SpaceData(), oldAll = SpaceData(), oldFavourite = SpaceData(), unrelated = SpaceData()
        unrelated.siteId = "other-site"
        for old in [oldSite, oldAll, oldFavourite, unrelated] { old.hdbLoadFailed = true }
        lists.site.spaces = [oldSite, unrelated]; lists.allSpaces = [oldAll]; lists.favouriteSpaces = [oldFavourite]
        let committed = SpaceData(); committed.hdb = configuration("Committed")
        committed.hdbPersistenceBaseline = committed.hdb; committed.lastUpdate = 200
        SpaceData.persisted = committed.copy()
        precondition(!oldSite.save(), "pre-repair page instance still reproduces the save error")
        lists.reloadSpaceData(committed)
        for reopened in [oldSite, oldAll, oldFavourite] {
            precondition(!reopened.hdbLoadFailed && reopened.hdb == committed.hdb && reopened.lastUpdate == 200)
            precondition(reopened.save(), "reentering through every retained list instance must use the committed database configuration")
        }
        precondition(unrelated.hdbLoadFailed)
        print("PASS: production Site list refresh replaces stale repair state in Site/All/Favourites before reentry; other Sites untouched")
    }
}
