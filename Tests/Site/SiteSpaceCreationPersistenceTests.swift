import Foundation
import SQLite

// The script extracts actual addSpace, Site/Space SQL, receipt and display methods.
// Mesh allocation, Keychain and optional HDB/Zone content remain boundaries here;
// the HDB creation suite separately exercises its real initialization and cleanup.
final class SpaceData {
    enum State: Int { case normal = 1 }
    enum Sort: Int { case create = 0 }
    static var loadCount = 0
    var id = UUID().uuidString, siteId = "", meshUUID = "", meshNetworkId = "", name = ""
    var imageId = 1, create: Int64 = 0, lastUpdate: Int64 = 0
    var isFavourite = false, permission = Permission.owner, sourceType = DataSourceType.create
    var deviceSortType = Sort.create, deviceCount = 0, luminairesCount = 0, groupCount = 0
    var sceneCount = 0, scheheduleCount = 0, switchesCount = 0
    var lastUploadCloudTimestamp: Int64?, syncCloudError: NetworkApiError?
    var state = State.normal
    var editorPassword: String?, vistorPassword: String?, authorizationPassword: String?, shareCode: String?
    var requiresPasswordVerification = false, vistorPasswordEnable = false, releaseAddress = false
    var applyDeviceAddressCount: Int?, applyGroupAddressCount: Int?
    var editor: UserData?, visitors: [UserData] = []
    var displayDeviceNamePrefix = true, showCCTQuickButtons = false
    var controlType = SpaceControlType.simple, deviceBlinkMode = DeviceBlinkMode.breathing
    var timedSchemaVersion = 1
    var hdb: HDBConfiguration?, hdbPersistenceBaseline: HDBConfiguration?, hdbLoadFailed = false
    var triggerZones: [SpaceTriggerZone] = [], triggerZonesLoadFailed = false
    init() {}
    init(name: String, id: String, siteId: String, imageId: Int, create: Int64, lastUpdate: Int64? = nil,
         isFavourite: Bool, permission: Permission, sourceType: DataSourceType, meshUUID: String, meshNetworkId: String) {
        self.name = name; self.id = id; self.siteId = siteId; self.imageId = imageId
        self.create = create; self.lastUpdate = lastUpdate ?? create; self.isFavourite = isFavourite
        self.permission = permission; self.sourceType = sourceType; self.meshUUID = meshUUID; self.meshNetworkId = meshNetworkId
    }
    func copy() -> SpaceData {
        let copy = SpaceData(name: name, id: id, siteId: siteId, imageId: imageId, create: create,
            lastUpdate: lastUpdate, isFavourite: isFavourite, permission: permission, sourceType: sourceType,
            meshUUID: meshUUID, meshNetworkId: meshNetworkId)
        copy.lastUploadCloudTimestamp = lastUploadCloudTimestamp
        return copy
    }
    func cloneData() -> SpaceData { let result = copy(); result.id = UUID().uuidString; return result }
    func delete() -> Bool {
        _ = try? SunSmartDataManager.shared.db?.run("DELETE FROM spaces WHERE uuid = ? AND siteUUID = ?", id, siteId)
        MeshNetworkManager.subnets.remove(meshNetworkId)
        return true
    }
}
enum SpaceControlType: String { case simple }
enum DeviceBlinkMode: Int { case breathing = 1 }
enum SpaceContentDisplayDefaults { static let showCCTQuickButtons = false; static let controlType = SpaceControlType.simple }
struct HDBConfiguration: Codable {}
struct SpaceTriggerZone: Codable {}
enum HDBConfigurationError: Error { case addressUnavailable, persistenceFailed }
enum HDBLightingZonePolicy {
    static func validate(_ value: HDBConfiguration) throws {}
    static func configurationForSave(current: HDBConfiguration?, baseline: HDBConfiguration?, persisted: HDBConfiguration?, rowExists: Bool) throws -> HDBConfiguration? { current }
}
enum HDBConfigurationStore {
    static func availableLightingZoneAddresses(meshUUID: String) -> [Int] { [] }
    static func initializeLightingZones(space: SpaceData, addresses: [Int]) throws {}
}
final class FeatureVisibility {
    enum Feature { case spaceHDBConfiguration }
    static let shared = FeatureVisibility()
    func isVisible(_ feature: Feature, permission: Permission) -> Bool { false }
}
enum Keychain {
    static func saveSpacePassword(_ value: String?, siteId: String, spaceId: String) -> Bool { true }
    static func getSpacePassword(siteId: String, spaceId: String) -> String? { nil }
}
enum SpaceConfigurationSafety {
    static func block(_ space: SpaceData, reason: String) {}
    static func hasPendingUpload(_ space: SpaceData) -> Bool { false }
}
extension NetworkApiError { static let configurationUploadUnconfirmed = NetworkApiError(code: -2) }
extension MeshNetworkManager {
    struct Subnetwork { let networkKey: SubnetworkKey }
    struct SubnetworkKey { let networkId: String }
    static var subnets = Set<String>()
    static func addSubnetwork(meshUUID: String, networkKeyName: String, applicationKeyName: String) -> Subnetwork? {
        let id = UUID().uuidString
        subnets.insert(id)
        return Subnetwork(networkKey: SubnetworkKey(networkId: id))
    }
}
extension CloudSynchronizationManager {
    struct SpaceHandle { let state: CloudSynchronizationState }
    func getSpaceCurrentSyncState(_ space: SpaceData) -> SpaceHandle? { state.map { SpaceHandle(state: $0) } }
}

@MainActor enum SiteSpaceCreationPersistenceTests {
    static func run(path: String) async throws {
        try createdSiteWithSpace(path: path)
        try await pendingEditsAndOldReceipt(path: path)
        try atomicFailuresAndRetry(path: path)
        print("PASS: real addSpace, Site/Space SQLite transaction, parent revision, pending edits, receipt/display and failure rollback")
    }

    static func createdSiteWithSpace(path: String) throws {
        for alreadyUploaded in [false, true] {
            let site = try SiteData.add(name: "Site with Space", timezone: "Asia/Shanghai")
            // A genuine earlier creation time: force the original cross-second mismatch without sleeping.
            site.create -= 2; site.lastUpdate -= 2; site.pendingSitePropsTimestamp = site.lastUpdate
            if alreadyUploaded { site.lastUploadCloudTimestamp = site.lastUpdate; site.pendingSitePropsMask = []; site.pendingSitePropsTimestamp = nil }
            precondition(site.save())
            let before = site.lastUpdate
            let space = try site.addSpace(name: "Space 1")!
            let stored = SiteData.load(siteId: site.id)!
            precondition(stored.lastUpdate == site.lastUpdate && stored.lastUpdate > before,
                         "Adding a Space must persist the same new parent revision the page displays")
            precondition(stored.spaces.count == 1 && stored.spaces[0].id == space.id)
            if !alreadyUploaded { precondition(stored.pendingSitePropsTimestamp == stored.lastUpdate) }
            let api: NetowrkReqeustApi = alreadyUploaded
                ? .siteUpload(siteData: ["updateTimestamp": stored.lastUpdate])
                : .siteAdd(siteData: ["updateTimestamp": stored.lastUpdate, "timezone": "Asia/Shanghai"], useDeivceAddressNum: 0)
            precondition(SiteSyncReceiptFixture(stored, addingSpaces: alreadyUploaded).confirmSiteUpload(
                api: api, response: SiteSyncReceiptFixture.validAddResponse))
            precondition(space.saveCloudSyncOutcome(confirmedTimestamp: space.lastUpdate, error: nil))
            let list = SitesListFixture()
            list.allSites = [site]
            list.reloadSiteData(stored)
            precondition(site.showSyncCloudError == nil && space.showSyncCloudError == nil)
            precondition(site.pendingSitePropsMask.isEmpty && site.lastUploadCloudTimestamp == site.lastUpdate)
            SunSmartDataManager.shared.db = try Connection(path)
            let restarted = SiteData.load(siteId: site.id)!
            precondition(!restarted.needUploadCloud && !restarted.spaces[0].needUploadCloud)
        }
        let rapid = try SiteData.add(name: "Rapid spaces", timezone: nil)
        // A clock that has not advanced must still create distinct revisions.
        rapid.lastUpdate += 60
        precondition(rapid.save())
        let firstVersion = rapid.lastUpdate
        _ = try rapid.addSpace(name: "One")!
        precondition(rapid.lastUpdate == firstVersion + 1)
        _ = try rapid.addSpace(name: "Two")!
        precondition(rapid.lastUpdate == firstVersion + 2)
        precondition(SiteData.load(siteId: rapid.id)!.lastUpdate == rapid.lastUpdate)
    }

    static func pendingEditsAndOldReceipt(path: String) async throws {
        let page = try SiteData.add(name: "Older page", timezone: nil)
        let fresh = SiteData.load(siteId: page.id)!
        let editor = SitePropsEditCoordinator(site: fresh)
        var draft = await editor.prepareDraft(online: false)
        draft.values.siteName = "Saved new name"
        draft.values.timezone = SiteTimeZoneValue.preservingStorageValue("Europe/London")
        draft.standardProperties.city = "Saved city"
        let plan = editor.makeCommitPlan(draft: draft, online: false, now: fresh.lastUpdate + 1)
        guard case .success = editor.persist(plan) else { preconditionFailure() }
        let oldTask = SiteData.load(siteId: page.id)!
        let oldTimestamp = oldTask.lastUpdate
        let originalFields = oldTask.pendingSitePropsMask
        let savedProps = oldTask.standardProperties
        let submittedValues: [String: Any] = ["updateTimestamp": oldTimestamp, "timezone": "Europe/London"]
        precondition(oldTask.setFavourite(true, account: UserData.currentUserId))
        _ = try page.addSpace(name: "Space after edit")!
        let newTimestamp = page.lastUpdate
        precondition(page.name == "Saved new name" && page.timezone == "Europe/London" && page.isFavourite)
        precondition(page.standardProperties == savedProps && page.pendingSitePropsMask == originalFields)
        precondition(page.pendingSitePropsTimestamp == newTimestamp && newTimestamp > oldTimestamp)
        precondition(SiteSyncReceiptFixture(oldTask).confirmSiteUpload(api: .siteAdd(siteData: submittedValues,
            useDeivceAddressNum: 0), response: SiteSyncReceiptFixture.validAddResponse))
        page.refreshPersistedDisplayState(account: UserData.currentUserId)
        precondition(page.lastUpdate == newTimestamp && page.lastUploadCloudTimestamp == oldTimestamp)
        precondition(page.pendingSitePropsMask == originalFields && page.pendingSitePropsTimestamp == newTimestamp)
        precondition(page.needUploadCloud && page.showSyncCloudError != nil)
        // A real unsaved newer Site object must not be overwritten by adding a Space.
        let beforeSpaces = page.spaces.count
        page.lastUpdate += 1; page.name = "Unsaved newer name"
        do { _ = try page.addSpace(name: "Rejected"); preconditionFailure("Newer unsaved Site was overwritten") }
        catch HDBConfigurationError.persistenceFailed {}
        precondition(page.name == "Unsaved newer name" && page.spaces.count == beforeSpaces)
        precondition(SiteData.load(siteId: page.id)!.name == "Saved new name")
    }

    static func atomicFailuresAndRetry(path: String) throws {
        let site = try SiteData.add(name: "Atomic creation", timezone: "Asia/Shanghai")
        let unrelated = try SiteData.add(name: "Unrelated", timezone: nil)
        let db = SunSmartDataManager.shared.db!
        let original = site.persistedPropsState()!
        let networkIDs = MeshNetworkManager.subnets
        for phase in ["space", "site", "commit"] {
            if phase == "space" {
                try db.execute("CREATE TRIGGER fail_new_space BEFORE INSERT ON spaces BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
            } else if phase == "site" {
                try db.execute("CREATE TRIGGER fail_site_revision BEFORE UPDATE OF lastUpdateTimestamp ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
            } else {
                var reject = true
                db.commitHook { if reject { reject = false; throw CocoaError(.fileWriteUnknown) } }
            }
            do { _ = try site.addSpace(name: "Failed \(phase)"); preconditionFailure("Failed creation succeeded") }
            catch HDBConfigurationError.persistenceFailed {}
            db.commitHook(nil)
            if phase == "space" { try db.execute("DROP TRIGGER fail_new_space") }
            if phase == "site" { try db.execute("DROP TRIGGER fail_site_revision") }
            precondition(site.spaces.isEmpty && site.persistedPropsState() == original)
            precondition(site.lastUpdate == original.lastUpdate && site.pendingSitePropsTimestamp == original.pending.timestamp)
            precondition(SpaceData.load(siteId: site.id).isEmpty && MeshNetworkManager.subnets == networkIDs)
            // Reopen a second connection to verify durability, not only visibility on the writer.
            let count = try Connection(path).scalar("SELECT count(*) FROM spaces WHERE siteUUID = ?", site.id) as! Int64
            precondition(count == 0)
        }
        let unrelatedBefore = unrelated.persistedPropsState()
        let retry = try site.addSpace(name: "Retry")!
        precondition(site.spaces.count == 1 && SpaceData.load(siteId: site.id).first?.id == retry.id)
        precondition(unrelated.persistedPropsState() == unrelatedBefore)
        let allocated = MeshNetworkManager.subnets
        do { _ = try site.addSpace(name: "Duplicate", id: retry.id); preconditionFailure("Reused Space identity was accepted") }
        catch HDBConfigurationError.persistenceFailed {}
        precondition(MeshNetworkManager.subnets == allocated && SpaceData.load(siteId: site.id).first?.id == retry.id)
        let snapshot = site.persistedPropsState()
        let siteState = SiteData.load(siteId: site.id)!
        siteState.permission = .visitor
        precondition(siteState.save())
        do { _ = try site.addSpace(name: "Revoked"); preconditionFailure("Revoked owner can add Space") }
        catch HDBConfigurationError.persistenceFailed {}
        precondition(site.spaces.count == 1 && site.persistedPropsState() == snapshot)
    }
}
