import Foundation
import SQLite

// Only UIKit drawing/navigation is substituted. Site persistence and the extracted
// list/favourite methods run unchanged against real temporary SQLite records.
extension IndexPath {
    init(row: Int, section: Int) { self.init(indexes: [section, row]) }
}
final class UICollectionView {
    var reloads: [[IndexPath]] = []
    var fullReloads = 0
    func reloadItems(at paths: [IndexPath]) { reloads.append(paths) }
    func reloadData() { fullReloads += 1 }
}
final class TestListView { var window: Bool? = true }
final class SiteDetailFixture {
    let site: SiteData
    let siteAccount = UserData.currentUserId
    var siteReloadScheduled = false
    var title: String?
    var showFailure = false
    init(site: SiteData) { self.site = site }
    func updateSyncState() { showFailure = site.showSyncCloudError != nil }
}
enum XWHUDManager {
    static var errors = 0
    static func showErrorTipHUD(_ text: String) { errors += 1 }
}
enum CloudSynchronizationState { case wait, inProgress, successful, failure, cancel }
final class CloudSynchronizationManager {
    enum Operation { case syncSite(site: SiteData) }
    enum Level { case normal }
    static let shared = CloudSynchronizationManager()
    var state: CloudSynchronizationState?
    var enqueuedSites: [String] = []
    var callback: ((CloudSynchronizationState) -> Void)?
    func addSynchronizationHandle(operation: Operation, level: Level, result: @escaping (CloudSynchronizationState) -> Void) {
        if case let .syncSite(site) = operation { enqueuedSites.append(site.id) }
        callback = result
    }
    func getSiteCurrentSyncState(_ site: SiteData) -> CloudSynchronizationState? { state }
}
final class SitesListFixture {
    enum SectionType { case personal, received }
    var allSites: [SiteData] = [], favouriteSites: [SiteData] = []
    var allSections: [SectionType] = [.personal], favouriteSections: [SectionType] = [.personal]
    var allSitesCollectionView: UICollectionView! = UICollectionView()
    var favouritesCollectionView: UICollectionView! = UICollectionView()
    var siteAccount = UserData.currentUserId
    var pendingSiteReloads: Set<String> = []
    var syncUpdates = 0
    func updateSyncState() { syncUpdates += 1 }
    var viewIfLoaded: TestListView? = TestListView()
    func updateEmptyView() {}
}

@MainActor enum SitesListSyncStateTests {
    static func run(path: String) async throws {
        let original = try SiteData.add(name: "List target", timezone: "Asia/Shanghai")
        precondition(original.setFavourite(true, account: UserData.currentUserId))
        let favouriteCopy = SiteData.load(siteId: original.id)!
        let unrelated = try SiteData.add(name: "Unrelated", timezone: nil)
        let list = SitesListFixture()
        list.allSites = [original, unrelated]
        list.favouriteSites = [favouriteCopy]

        // Upload holds a separate instance, just as syncOperation does in production.
        let worker = SiteData.load(siteId: original.id)!
        let receipt = SiteSyncReceiptFixture(worker)
        let accepted = receipt.confirmSiteUpload(api: .siteAdd(siteData: [
            "updateTimestamp": worker.lastUpdate, "timezone": "Asia/Shanghai"
        ], useDeivceAddressNum: 0), response: ["data": ["addrLists": [
            "ownerDevicesAddress": 5000, "ownerGroupsAddress": 3200, "ownerScenesAddress": 1600
        ]]])
        precondition(accepted && worker !== original)
        let staleForFavourite = SiteData.load(siteId: unrelated.id)!
        let newer = SiteData.load(siteId: unrelated.id)!
        newer.name = "Newer saved name"
        newer.lastUpdate += 10
        newer.lastUploadCloudTimestamp = newer.lastUpdate
        precondition(newer.save())

        var failures: [String] = []
        func check(_ condition: Bool, _ name: String) {
            if !condition { failures.append(name); print("FAIL: \(name)") }
        }
        list.reloadSiteData(worker)
        check(original.lastUploadCloudTimestamp == worker.lastUpdate && original.pendingSitePropsMask.isEmpty,
              "successful upload must update the list's original object before drawing")
        check(favouriteCopy.lastUploadCloudTimestamp == worker.lastUpdate,
              "the same Site in favourites must receive the confirmed state")
        check(unrelated.name == "Unrelated" && unrelated.lastUploadCloudTimestamp == nil,
              "refreshing Site A must not update Site B's in-memory state")

        list.setSiteFavourite(staleForFavourite, isFavourite: true)
        let saved = SiteData.load(siteId: unrelated.id)!
        check(saved.isFavourite && saved.name == "Newer saved name" && saved.lastUploadCloudTimestamp == newer.lastUpdate,
              "favouriting a stale object must only write the favourite field")
        if !failures.isEmpty { exit(1) }
        print("PASS: single-Site list/favourite refresh and stale favourite write protection")
        try await asynchronousRefresh(path: path)
        try await failureAndContextProtection(path: path)
        try favouriteDuringUpload(path: path)
        try await callbackAfterListReload()
    }

    static func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async { continuation.resume() }
        }
    }

    static func asynchronousRefresh(path: String) async throws {
        let original = try SiteData.add(name: "Hidden list", timezone: "Asia/Shanghai")
        let unrelated = try SiteData.add(name: "Do not touch", timezone: nil)
        let space = SpaceData()
        original.spaces = [space]
        original.gatewayPresence = true
        let list = SitesListFixture()
        list.allSites = [original, unrelated]
        list.viewIfLoaded?.window = nil
        let detail = SiteDetailFixture(site: original)
        let manager = CloudSynchronizationManager.shared
        manager.enqueuedSites = []
        list.startCreatedSiteSynchronization(original)
        let worker = SiteData.load(siteId: original.id)!
        let receipt = SiteSyncReceiptFixture(worker)
        let submitted = worker.lastUpdate
        precondition(receipt.confirmSiteUpload(api: .siteAdd(siteData: [
            "updateTimestamp": submitted, "timezone": "Asia/Shanghai"
        ], useDeivceAddressNum: 0), response: SiteSyncReceiptFixture.validAddResponse))
        manager.state = .successful
        manager.callback?(.successful)
        // The detail has the delegate; the hidden list has only its per-task callback.
        detail.scheduleSiteStateReload()
        list.scheduleSiteReload(worker)
        precondition(original.lastUploadCloudTimestamp == nil, "Refresh must wait until terminal handle removal")
        manager.state = nil
        var sql: [String] = []
        SunSmartDataManager.shared.db!.trace { sql.append($0) }
        let spaceLoads = SpaceData.loadCount
        await drainMainQueue()
        SunSmartDataManager.shared.db!.trace(nil)
        precondition(original.lastUploadCloudTimestamp == submitted && original.showSyncCloudError == nil)
        precondition(!detail.showFailure && detail.title == original.name)
        precondition(original.spaces.first === space && original.gatewayPresence)
        precondition(SpaceData.loadCount == spaceLoads)
        let reads = sql.filter { $0.uppercased().hasPrefix("SELECT") }
        precondition(reads.count == 2 && reads.allSatisfy { $0.contains(original.id) && !$0.contains(unrelated.id) },
                     "One row read per page; duplicate list callbacks coalesce, unrelated Site is never read")
        precondition(list.allSitesCollectionView.reloads.isEmpty && list.allSitesCollectionView.fullReloads == 0)
        precondition(manager.enqueuedSites == [original.id], "Display updates must never enqueue another upload")

        // A late receipt reads today's saved edits, not the old callback's copy.
        let editor = SitePropsEditCoordinator(site: SiteData.load(siteId: original.id)!)
        var draft = await editor.prepareDraft(online: false)
        draft.values.siteName = "Newer edit"
        draft.standardProperties.city = "Later city"
        let plan = editor.makeCommitPlan(draft: draft, online: false, now: submitted + 10)
        guard case .success = editor.persist(plan) else { preconditionFailure() }
        list.viewIfLoaded?.window = true
        manager.callback?(.cancel)
        await drainMainQueue()
        precondition(original.name == "Newer edit" && original.city == "Later city")
        precondition(original.lastUpdate == submitted + 10 && original.lastUploadCloudTimestamp == submitted)
        precondition(!original.pendingSitePropsMask.isEmpty && original.showSyncCloudError != nil)
        // Protect an even later in-memory edit; an independent editor draft is never touched.
        original.name = "Unsaved newer edit"
        original.lastUpdate += 1
        let pending = original.pendingSitePropsMask
        list.reloadSiteData(worker)
        precondition(original.name == "Unsaved newer edit" && original.pendingSitePropsMask == pending && original.needUploadCloud)

        // Received/editor rows can be section zero, without a personal section.
        let received = try SiteData.add(name: "Received", timezone: nil)
        received.permission = .editor
        precondition(received.save() && received.setFavourite(true, account: UserData.currentUserId))
        let receivedList = SitesListFixture()
        receivedList.allSites = [received]
        receivedList.favouriteSites = [received]
        receivedList.setupSectionsData()
        receivedList.reloadSiteData(received)
        precondition(receivedList.allSitesCollectionView.reloads.last == [IndexPath(row: 0, section: 0)])
        precondition(receivedList.favouritesCollectionView.reloads.last == [IndexPath(row: 0, section: 0)])
        print("PASS: hidden list callback, deferred/coalesced refresh, current edits, runtime objects, SQL scope and received rows")
    }

    static func failureAndContextProtection(path: String) async throws {
        let site = try SiteData.add(name: "Retry", timezone: nil)
        let worker = SiteData.load(siteId: site.id)!
        let list = SitesListFixture()
        list.allSites = [site]
        list.startCreatedSiteSynchronization(site)
        let manager = CloudSynchronizationManager.shared
        worker.syncCloudError = .unknown
        precondition(worker.save())
        manager.callback?(.failure)
        await drainMainQueue()
        precondition(site.showSyncCloudError?.code == NetworkApiError.unknown.code && site.needUploadCloud)
        manager.callback?(.cancel)
        await drainMainQueue()
        precondition(site.showSyncCloudError != nil)
        precondition(SiteSyncReceiptFixture(worker).confirmSiteUpload(
            api: .siteUpload(siteData: ["updateTimestamp": worker.lastUpdate]), response: [:]))
        manager.callback?(.successful)
        manager.callback?(.cancel) // stale cancellation must not undo a saved success
        await drainMainQueue()
        precondition(site.showSyncCloudError == nil && !site.needUploadCloud)
        SunSmartDataManager.shared.db = try Connection(path)
        precondition(!SiteData.load(siteId: site.id)!.needUploadCloud, "Restart must see the same confirmed state")

        // SQLite errors keep model/list membership and restore the already-toggled cell by redraw.
        let db = SunSmartDataManager.shared.db!
        try db.execute("CREATE TRIGGER fail_favourite BEFORE UPDATE OF favourite ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let errors = XWHUDManager.errors
        list.setSiteFavourite(site, isFavourite: true)
        precondition(!site.isFavourite && list.favouriteSites.isEmpty && XWHUDManager.errors == errors + 1)
        precondition(list.allSitesCollectionView.fullReloads == 1)
        precondition(!SiteData.load(siteId: site.id)!.isFavourite)
        try db.execute("DROP TRIGGER fail_favourite")
        list.setSiteFavourite(site, isFavourite: true)
        precondition(site.isFavourite && list.favouriteSites.count == 1)
        list.setSiteFavourite(site, isFavourite: true)
        precondition(list.favouriteSites.count == 1, "A repeated callback cannot duplicate a favourite")
        list.setSiteFavourite(site, isFavourite: false)
        precondition(!site.isFavourite && list.favouriteSites.isEmpty)

        let newer = SiteData.load(siteId: site.id)!
        newer.name = "Saved after page"
        newer.lastUpdate += 10
        precondition(newer.save())
        list.scheduleSiteReload(site)
        UserData.currentUserId = "other account"
        await drainMainQueue()
        manager.callback?(.successful)
        precondition(site.name == "Retry" && !site.setFavourite(true, account: list.siteAccount))
        UserData.currentUserId = list.siteAccount
        list.scheduleSiteReload(site)
        UserData.currentServerRegion = .second
        await drainMainQueue()
        precondition(site.name == "Retry" && !site.setFavourite(true, account: list.siteAccount))
        UserData.currentServerRegion = .first
        let connection = SunSmartDataManager.shared.db
        SunSmartDataManager.shared.db = nil
        list.reloadSiteData(site)
        precondition(site.name == "Retry" && !site.setFavourite(true, account: list.siteAccount))
        SunSmartDataManager.shared.db = connection

        // Same UUID with a different creation identity must not accept the old page's changes.
        let replacement = SiteData.load(siteId: site.id)!
        replacement.create += 1
        precondition(replacement.save())
        list.reloadSiteData(site)
        precondition(site.name == "Retry" && !site.setFavourite(true, account: list.siteAccount))
        list.scheduleSiteReload(site)
        try db.run(Table("sites").filter(Expression<String>("uuid") == site.id).delete())
        await drainMainQueue()
        precondition(SiteData.load(siteId: site.id) == nil && !site.setFavourite(true, account: list.siteAccount))
        weak var releasedList: SitesListFixture?
        do {
            let temporary = SitesListFixture()
            releasedList = temporary
            temporary.allSites = [site]
            temporary.startCreatedSiteSynchronization(site)
        }
        precondition(releasedList == nil, "The queued task must not retain its page")
        manager.callback?(.successful)
        await drainMainQueue()
        print("PASS: failure/retry/cancel, restart, favourite rollback, account/region change, deletion and released page")
    }

    static func favouriteDuringUpload(path: String) throws {
        let site = try SiteData.add(name: "Favourite in flight", timezone: nil)
        let worker = SiteData.load(siteId: site.id)!
        precondition(site.setFavourite(true, account: UserData.currentUserId))
        precondition(SiteSyncReceiptFixture(worker).confirmSiteUpload(
            api: .siteUpload(siteData: ["updateTimestamp": worker.lastUpdate]), response: [:]))
        guard SiteData.load(siteId: site.id)!.isFavourite else {
            print("FAIL: an upload receipt must preserve a favourite changed while uploading")
            exit(1)
        }
        print("PASS: upload receipt preserves an in-flight favourite change")
    }
    static func callbackAfterListReload() async throws {
        let list = SitesListFixture()
        list.viewIfLoaded?.window = nil
        weak var releasedOriginal: SiteData?
        var worker: SiteData!
        do {
            let original = try SiteData.add(name: "Rebuilt list", timezone: nil)
            releasedOriginal = original
            list.allSites = [original]
            list.startCreatedSiteSynchronization(original)
            worker = SiteData.load(siteId: original.id)!
            // A list fetch replaces the array, then another detail page takes the delegate.
            list.allSites = [SiteData.load(siteId: original.id)!]
        }
        precondition(releasedOriginal == nil)
        precondition(SiteSyncReceiptFixture(worker).confirmSiteUpload(
            api: .siteUpload(siteData: ["updateTimestamp": worker.lastUpdate]), response: [:]))
        CloudSynchronizationManager.shared.callback?(.successful)
        await drainMainQueue()
        guard !list.allSites[0].needUploadCloud else {
            print("FAIL: the per-task callback must survive replacement of the original list object")
            exit(1)
        }
        print("PASS: hidden list refresh after its original Site object is released")
    }

}
