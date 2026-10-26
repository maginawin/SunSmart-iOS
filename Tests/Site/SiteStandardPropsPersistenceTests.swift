import Foundation
import SQLite

// Real SQLite and production import/coordinator/receipt code. Transport and Mesh
// allocation are boundaries; prepareBatch's fresh-instance handoff is replayed by load.
enum SpaceMembershipCoordinator {
    static func accepts(_ object: [String: Any]) -> Bool { true }
}
enum NetowrkReqeustApi {
    case sitePropsRetrieve(siteId: String)
    case sitePropsUpdate(siteId: String, props: [String: Any])
    case siteUpload(siteData: [String: Any])
    case siteAdd(siteData: [String: Any], useDeivceAddressNum: Int)
}
final class NetworkRequest {
    static let shared = NetworkRequest()
    var result: Swift.Result<[String: Any], NetworkApiError> = .failure(.unknown)
    func request(_ target: NetowrkReqeustApi) async -> Swift.Result<[String: Any], NetworkApiError> { result }
}
protocol SiteTimeZoneEditSubmitting: AnyObject {
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}
protocol SiteEntryTimeZoneSyncStore: AnyObject {}
final class SiteSyncReceiptFixture {
    enum Operation {
        case syncSite(SiteData, [SpaceData])
        case addSpaces(SiteData, [SpaceData])
        case other
    }
    let operation: Operation
    init(_ site: SiteData, addingSpaces: Bool = false) {
        operation = addingSpaces ? .addSpaces(site, []) : .syncSite(site, [])
    }
}
extension SiteData {
    func setOwnerProvisioner(addressData: [String: Any]) {}
}

@MainActor enum SiteStandardPropsPersistenceTests {
    static func run(path: String) async throws {
        try transferCacheLifetime(path: path)
        try coordinateStringImport(path: path)
        let site = try SiteData.add(name: "Interleaved", timezone: nil)
        let oldTaskSite = SiteData.load(siteId: site.id)!
        let importer = SiteData.load(siteId: site.id)!
        var payload: [String: Any] = ["uuid": site.id, "siteName": site.name,
            "imageId": 1, "type": 1, "createTimestamp": site.create,
            "updateTimestamp": site.lastUpdate, "city": "795565", "latitude": 0,
            "longitude": -72.5, "countryRegion": "SG", "postalCode": "018983",
            "address": "Street", "description": "Lobby"]
        precondition(importer.importFixture(siteJsonData: payload))
        let imported = importer.standardProperties
        let prepared = SiteData.load(siteId: site.id)!
        precondition(prepared.city == "795565" && oldTaskSite.city == nil)
        // The request exports the reloaded instance; its receipt still owns oldTaskSite.
        var submitted = prepared.standardProperties.jsonObject
        submitted["updateTimestamp"] = prepared.lastUpdate
        let api = NetowrkReqeustApi.siteUpload(siteData: submitted)
        let receipt = SiteSyncReceiptFixture(oldTaskSite)
        precondition(receipt.confirmSiteUpload(api: api, response: [:]))
        precondition(SiteData.load(siteId: site.id)!.standardProperties == imported,
                     "A stale upload receipt must preserve metadata imported by another Site instance")
        precondition(oldTaskSite.standardProperties == imported, "Successful save must refresh the caller's metadata")
        SunSmartDataManager.shared.db = try Connection(path)
        precondition(SiteData.load(siteId: site.id)!.standardProperties == imported)
        // A partial detail response from another old instance preserves omitted fields.
        payload = ["uuid": site.id, "siteName": site.name, "updateTimestamp": site.lastUpdate,
                   "city": NSNull()]
        precondition(site.importFixture(siteJsonData: payload))
        precondition(site.city == nil && site.latitude == 0 && site.longitude == -72.5)
        precondition(oldTaskSite.save())
        precondition(SiteData.load(siteId: site.id)!.city == nil, "Stale non-nil values must not resurrect a clear")
        try await propsReadbackAndReceipts(siteID: site.id, path: path)
        try failedImportAndRetry(siteID: site.id, path: path)
        print("PASS: SQLite detail import -> fresh export -> stale upload receipt -> restart, partial fields and explicit null")
    }

    static func transferCacheLifetime(path: String) throws {
        let site = try SiteData.add(name: "Transfer cache", timezone: nil)
        let old = SiteTransferCredentials(code: "old-task", password: "old-password")
        let next = SiteTransferCredentials(code: "new-task", password: "new-password")
        precondition(site.replaceTransferCredentials(old, expected: .empty))
        let staleSync = SiteData.load(siteId: site.id)!
        let staleLookup = SiteData.load(siteId: site.id)!
        let timestamp = site.lastUpdate
        let db = SunSmartDataManager.shared.db!
        try db.execute("CREATE TRIGGER fail_site BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        precondition(!site.save(clearTransferCredentials: true))
        precondition(SiteTransferCredentials(site: SiteData.load(siteId: site.id)!) == old)
        try db.execute("DROP TRIGGER fail_site")
        precondition(site.save(clearTransferCredentials: true))
        precondition(staleSync.save(), "Ordinary saves must preserve the cleared credentials")
        SunSmartDataManager.shared.db = try Connection(path)
        let reopened = SiteData.load(siteId: site.id)!
        precondition(SiteTransferCredentials(site: reopened) == .empty && reopened.lastUpdate == timestamp)
        precondition(!staleLookup.replaceTransferCredentials(next, expected: old), "Old callback cannot replace a cleared task")
        precondition(reopened.replaceTransferCredentials(next, expected: .empty))
        precondition(staleLookup.save(), "Old Site objects must not overwrite the new task")
        SunSmartDataManager.shared.db = try Connection(path)
        precondition(SiteTransferCredentials(site: SiteData.load(siteId: site.id)!) == next)
        precondition(!staleLookup.replaceTransferCredentials(.empty, expected: old))
        let currentDB = SunSmartDataManager.shared.db!
        try currentDB.execute("CREATE TRIGGER fail_transfer BEFORE UPDATE ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        precondition(!reopened.replaceTransferCredentials(.empty, expected: next))
        precondition(SiteTransferCredentials(site: SiteData.load(siteId: site.id)!) == next)
        try currentDB.execute("DROP TRIGGER fail_transfer")
        precondition(reopened.replaceTransferCredentials(.empty, expected: next))
        print("PASS: SQLite receipt cache reset, restart, stale-save preservation, conditional updates and write-failure retry")
    }

    static func coordinateStringImport(path: String) throws {
        let site = try SiteData.add(name: "Coordinate receipt", timezone: nil)
        let payload: [String: Any] = ["uuid": site.id, "siteName": site.name,
            "updateTimestamp": site.lastUpdate, "latitude": "22.545540", "longitude": "114.068300"]
        precondition(site.importFixture(siteJsonData: payload))
        SunSmartDataManager.shared.db = try Connection(path)
        let reloaded = SiteData.load(siteId: site.id)!
        precondition(reloaded.latitude == 22.54554 && reloaded.longitude == 114.0683,
                     "String coordinates must be durable numeric values after reopening SQLite")
        let exportedData = try JSONSerialization.data(withJSONObject: reloaded.standardProperties.jsonObject)
        let exported = try JSONSerialization.jsonObject(with: exportedData) as! [String: Any]
        precondition(exported["latitude"] is NSNumber && exported["longitude"] is NSNumber)
        print("PASS: string-coordinate Site import -> SQLite reopen -> numeric JSON export")
    }

    static func propsReadbackAndReceipts(siteID: String, path: String) async throws {
        let staleEditorSite = SiteData.load(siteId: siteID)!
        let staleEditor = SitePropsEditCoordinator(site: staleEditorSite)
        let oldAddSpaces = SiteData.load(siteId: siteID)!
        let oldAddSite = SiteData.load(siteId: siteID)!
        oldAddSite.timezone = "Asia/Singapore (UTC+08:00)"
        oldAddSite.pendingSitePropsMask = [.timezone]
        oldAddSite.pendingSitePropsTimestamp = oldAddSite.lastUpdate
        let readerSite = SiteData.load(siteId: siteID)!
        let reader = SitePropsEditCoordinator(site: readerSite)
        NetworkRequest.shared.result = .success(["data": ["props": [
            "siteName": readerSite.name, "imageId": readerSite.imageId,
            "updateTimestamp": readerSite.lastUpdate, "city": "123456", "longitude": "80"]]])
        _ = await reader.prepareDraft(online: true)
        let fresh = readerSite.standardProperties
        precondition(fresh.city == "123456" && fresh.longitude == 80 && fresh.latitude == 0)
        // Both receipt operations must preserve a props read that arrived in flight.
        let addSpaces = SiteSyncReceiptFixture(oldAddSpaces, addingSpaces: true)
        precondition(addSpaces.confirmSiteUpload(api: .siteUpload(siteData: ["updateTimestamp": readerSite.lastUpdate]), response: [:]))
        let addSite = SiteSyncReceiptFixture(oldAddSite)
        precondition(addSite.confirmSiteUpload(api: .siteAdd(siteData: [
            "updateTimestamp": oldAddSite.lastUpdate, "timezone": oldAddSite.timezone!], useDeivceAddressNum: 0), response: [:]))
        precondition(oldAddSite.pendingSitePropsMask.isEmpty && oldAddSite.pendingSitePropsTimestamp == nil)
        precondition(SiteData.load(siteId: siteID)!.standardProperties == fresh)

        // Editing a base prop from an older instance is not a metadata write.
        var draft = await staleEditor.prepareDraft(online: false)
        draft.values.siteName = "Renamed"
        let plan = staleEditor.makeCommitPlan(draft: draft, online: true, now: staleEditorSite.lastUpdate + 1)
        guard case let .success(snapshot?) = staleEditor.persist(plan) else { preconditionFailure() }
        precondition(staleEditorSite.standardProperties == fresh)
        NetworkRequest.shared.result = .failure(.unknown)
        let failed = await staleEditor.submit(snapshot)
        precondition(!failed && !staleEditorSite.pendingSitePropsMask.isEmpty)
        NetworkRequest.shared.result = .success(["data": ["siteName": "Renamed", "updateTimestamp": snapshot.timestamp]])
        let succeeded = await staleEditor.submit(snapshot)
        precondition(succeeded && staleEditorSite.pendingSitePropsMask.isEmpty)
        precondition(SiteData.load(siteId: siteID)!.standardProperties == fresh)

        // Repeated receipt save failure rolls back and releases the transaction;
        // a later retry must be durable, not just visible on this connection.
        let db = SunSmartDataManager.shared.db!
        let oldTimestamp = oldAddSpaces.lastUploadCloudTimestamp
        oldAddSpaces.syncCloudError = .unknown
        try db.execute("CREATE TRIGGER fail_site BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let retryAPI = NetowrkReqeustApi.siteUpload(siteData: ["updateTimestamp": snapshot.timestamp])
        for _ in 0..<2 {
            precondition(!addSpaces.confirmSiteUpload(api: retryAPI, response: [:]))
            precondition(oldAddSpaces.lastUploadCloudTimestamp == oldTimestamp && oldAddSpaces.syncCloudError?.code == -1)
            precondition(SiteData.load(siteId: siteID)!.standardProperties == fresh)
        }
        try db.execute("DROP TRIGGER fail_site")
        precondition(addSpaces.confirmSiteUpload(api: retryAPI, response: [:]))
        SunSmartDataManager.shared.db = try Connection(path)
        let restarted = SiteData.load(siteId: siteID)!
        precondition(restarted.standardProperties == fresh && restarted.lastUploadCloudTimestamp == snapshot.timestamp)
        precondition(restarted.syncCloudError == nil)
        print("PASS: SQLite props readback with Site Add/addSpaces receipts, stale editor save, failed ACK and durable retry")
    }

    static func failedImportAndRetry(siteID: String, path: String) throws {
        let importer = SiteData.load(siteId: siteID)!
        let previous = importer.standardProperties
        let timestamp = importer.lastUpdate
        let db = SunSmartDataManager.shared.db!
        try db.execute("CREATE TRIGGER fail_site BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let payload: [String: Any] = ["uuid": siteID, "siteName": "Imported",
            "updateTimestamp": timestamp + 2, "city": NSNull(), "latitude": NSNull()]
        precondition(!importer.importFixture(siteJsonData: payload))
        precondition(importer.standardProperties == previous && importer.lastUpdate == timestamp)
        precondition(SiteData.load(siteId: siteID)!.standardProperties == previous)
        try db.execute("DROP TRIGGER fail_site")
        precondition(importer.importFixture(siteJsonData: payload))
        let cleared = importer.standardProperties
        precondition(cleared.city == nil && cleared.latitude == nil && cleared.longitude == previous.longitude)
        SunSmartDataManager.shared.db = try Connection(path)
        precondition(SiteData.load(siteId: siteID)!.standardProperties == cleared)
        print("PASS: SQLite failed metadata import rollback, explicit clear retry and restart")
    }
}
