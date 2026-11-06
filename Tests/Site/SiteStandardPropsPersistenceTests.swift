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
    static let validAddResponse: [String: Any] = ["data": ["addrLists": [
        "ownerDevicesAddress": 5000, "ownerGroupsAddress": 3200, "ownerScenesAddress": 1600
    ]]]
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
        try cityIdentityPersistence(path: path)
        try await editedMetadataPersistence(path: path)
        try await cityPendingSurvivesFullUploadReceipt(path: path)
        try transferCacheLifetime(path: path)
        try coordinateStringImport(path: path)
        try coordinateFallbackImport(path: path)
        try postalCodeImportPersistence(path: path)
        try equalVersionReplacement(path: path)
        try legacyMissingFields(path: path)
        try listSummaryPreservesMissingFields(path: path)
        try await invalidTimeZonePersistence(path: path)
        let site = try SiteData.add(name: "Interleaved", timezone: nil)
        let oldTaskSite = SiteData.load(siteId: site.id)!
        let importer = SiteData.load(siteId: site.id)!
        var payload: [String: Any] = ["uuid": site.id, "siteName": site.name,
            "imageId": 1, "type": 1, "createTimestamp": site.create,
            "updateTimestamp": site.lastUpdate, "city": "Singapore", "cityId": 795565, "latitude": 0,
            "longitude": -72.5, "countryRegion": "SG", "postalCode": "018983",
            "address": "Street", "description": "Lobby"]
        precondition(importer.importFixture(siteJsonData: payload))
        let imported = importer.standardProperties
        let prepared = SiteData.load(siteId: site.id)!
        precondition(prepared.city == "Singapore" && prepared.cityId == 795565 && oldTaskSite.city == nil)
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
        // A complete legacy detail response defaults omitted fields, even on an old instance.
        payload = ["uuid": site.id, "siteName": site.name, "updateTimestamp": site.lastUpdate,
                   "city": NSNull()]
        precondition(site.importFixture(siteJsonData: payload))
        precondition(site.city == nil && site.cityId == nil && site.latitude == nil && site.longitude == nil)
        precondition(oldTaskSite.save())
        precondition(SiteData.load(siteId: site.id)!.city == nil, "Stale non-nil values must not resurrect a clear")
        try await propsReadbackAndReceipts(siteID: site.id, path: path)
        try failedImportAndRetry(siteID: site.id, path: path)
        print("PASS: SQLite detail import -> fresh export -> stale upload receipt -> restart, partial fields and explicit null")
    }

    static func postalCodeImportPersistence(path: String) throws {
        for source in [SiteImportSource.completeDetail, .listSummary] {
            let site = try SiteData.add(name: "Postal Code", timezone: nil,
                                       standardProperties: .init(postalCode: "00123"))
            let expected = String(repeating: "中", count: 32)
            let bytes = try JSONSerialization.data(withJSONObject: ["uuid": site.id, "siteName": site.name,
                "updateTimestamp": site.lastUpdate + 1, "postalCode": expected + "extra"])
            let payload = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            let db = SunSmartDataManager.shared.db!
            try db.execute("CREATE TRIGGER fail_postal BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
            precondition(!site.importFixture(siteJsonData: payload, source: source))
            precondition(site.postalCode == "00123" && SiteData.load(siteId: site.id)!.postalCode == "00123")
            try db.execute("DROP TRIGGER fail_postal")
            precondition(site.importFixture(siteJsonData: payload, source: source))
            SunSmartDataManager.shared.db = try Connection(path)
            let restarted = SiteData.load(siteId: site.id)!
            precondition(restarted.postalCode == expected && restarted.pendingSitePropsMask.isEmpty)
            let exported = try JSONSerialization.data(withJSONObject: restarted.standardProperties.jsonObject)
            let object = try JSONSerialization.jsonObject(with: exported) as! [String: Any]
            precondition(object["postalCode"] as? String == expected)
        }
        print("PASS: Postal Code list/detail import, failed-save retry, SQLite restart and JSON export")
    }

    static func invalidTimeZonePersistence(path: String) async throws {
        let site = try SiteData.add(name: "Invalid timezone", timezone: "Asia/Singapore")
        let raw = "invalid timezone from legacy data"
        precondition(site.importFixture(siteJsonData: ["uuid": site.id, "siteName": site.name,
            "updateTimestamp": site.lastUpdate, "timezone": raw]))
        SunSmartDataManager.shared.db = try Connection(path)
        let loaded = SiteData.load(siteId: site.id)!
        precondition(loaded.timezone == raw && loaded.persistedPropsState()?.values.timezone?.storageValue == raw)
        let coordinator = SitePropsEditCoordinator(site: loaded)
        let draft = await coordinator.prepareDraft(online: false)
        precondition(draft.values.timezone?.storageValue == raw)
        let unchanged = coordinator.makeCommitPlan(draft: draft, online: true, now: loaded.lastUpdate + 1)
        precondition(!unchanged.hasNewChanges && !unchanged.includesTimezone,
                     "Reading an invalid timezone must not create a timezone edit")
        let remoteRaw = "another invalid timezone"
        NetworkRequest.shared.result = .success(["data": ["props": [
            "updateTimestamp": loaded.lastUpdate + 1, "timezone": remoteRaw,
            "siteName": "Remote name", "imageId": loaded.imageId]]])
        let remote = await coordinator.prepareDraft(online: true)
        precondition(remote.values.timezone?.storageValue == remoteRaw && remote.values.siteName == "Remote name")
        SunSmartDataManager.shared.db = try Connection(path)
        let restarted = SiteData.load(siteId: site.id)!
        precondition(restarted.timezone == remoteRaw && restarted.name == "Remote name")
        precondition(restarted.pendingSitePropsMask.isEmpty,
                     "Invalid timezone readback must remain data, not a phone-timezone write")
        print("PASS: invalid timezone survives actual import, SQLite restart and props merge without a synthetic edit")
    }

    static func listSummaryPreservesMissingFields(path: String) throws {
        for delta: Int64 in [0, 1] {
            let site = try SiteData.add(name: "Local", timezone: "Asia/Singapore (UTC+08:00)",
                standardProperties: .init(city: "Singapore", cityId: 123, address: "Street"))
            site.imageId = 7
            site.sourceType = .share
            site.pendingSitePropsMask = [.siteName, .timezone, .city, .address]
            site.pendingSitePropsTimestamp = site.lastUpdate
            site.lastUploadCloudTimestamp = site.lastUpdate - 1
            precondition(site.save())
            let oldUpload = site.lastUploadCloudTimestamp
            let oldPending = site.pendingSitePropsTimestamp
            let oldCreate = site.create
            try SiteExtensionStore.update(site) { state in
                var data = SiteExtensionData()
                data.siteType = .hdb
                data.replaceZones([SiteTriggerZone()])
                state.receive(data, timestamp: site.lastUpdate)
                data.fields["draft"] = .bool(true)
                state.commit(data, now: site.lastUpdate, siteTimestamp: site.lastUpdate)
            }
            let oldExtension = try SiteExtensionStore.load(site)
            let summary: [String: Any] = ["uuid": site.id, "siteName": "List name",
                "updateTimestamp": site.lastUpdate + delta]
            precondition(site.importFixture(siteJsonData: summary, source: .listSummary))
            SunSmartDataManager.shared.db = try Connection(path)
            let loaded = SiteData.load(siteId: site.id)!
            precondition(loaded.name == "List name")
            precondition(loaded.timezone == "Asia/Singapore" && loaded.city == "Singapore"
                && loaded.address == "Street" && loaded.cityId == 123,
                "List summaries must not clear missing timezone/standard properties after SQLite reload")
            precondition(loaded.imageId == 7 && loaded.create == oldCreate && loaded.sourceType == .share)
            precondition(loaded.pendingSitePropsMask == [.timezone, .city, .address]
                && loaded.pendingSitePropsTimestamp == oldPending && loaded.lastUploadCloudTimestamp == oldUpload,
                "A summary cannot acknowledge omitted pending properties")
            precondition(loaded.isHdbSite && (try! SiteExtensionStore.load(loaded)) == oldExtension,
                "List refresh must retain HDB, Trigger Zones and the exact extension draft")
            // Explicit clear is still a patch; omitted address/extension stay untouched.
            let clear: [String: Any] = ["uuid": site.id, "siteName": "Cleared fields",
                "updateTimestamp": loaded.lastUpdate, "timezone": NSNull(), "city": NSNull(), "imageId": 0]
            try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER fail_list_import BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
            precondition(!loaded.importFixture(siteJsonData: clear, source: .listSummary))
            precondition(loaded.name == "List name" && loaded.timezone == "Asia/Singapore"
                && loaded.city == "Singapore" && loaded.pendingSitePropsMask == [.timezone, .city, .address])
            try SunSmartDataManager.shared.db!.execute("DROP TRIGGER fail_list_import")
            precondition(loaded.importFixture(siteJsonData: clear, source: .listSummary))
            SunSmartDataManager.shared.db = try Connection(path)
            let cleared = SiteData.load(siteId: site.id)!
            precondition(cleared.timezone == nil && cleared.city == nil && cleared.imageId == 0)
            precondition(cleared.address == "Street" && cleared.cityId == 123 && cleared.pendingSitePropsMask == [.address])
            precondition(cleared.lastUploadCloudTimestamp == oldUpload && (try! SiteExtensionStore.load(cleared)) == oldExtension)
        }
        print("PASS: same/newer Site list summaries retain omitted properties, pending edits, HDB, Zones and extension draft across SQLite restart")
    }

    static func legacyMissingFields(path: String) throws {
        let site = try SiteData.add(name: "Old local name", timezone: "Asia/Singapore",
                                   standardProperties: .init(city: "Old city", cityId: 123))
        try SiteExtensionStore.update(site) { state in
            var extensionData = SiteExtensionData()
            extensionData.siteType = .hdb
            extensionData.fields["localOnly"] = .bool(true)
            state.receive(extensionData, timestamp: site.lastUpdate)
            extensionData.fields["localDraft"] = .bool(true)
            state.commit(extensionData, now: site.lastUpdate, siteTimestamp: site.lastUpdate)
        }
        let legacy: [String: Any] = ["uuid": site.id, "updateTimestamp": site.lastUpdate]
        precondition(site.importFixture(siteJsonData: legacy))
        SunSmartDataManager.shared.db = try Connection(path)
        let loaded = SiteData.load(siteId: site.id)!
        precondition(loaded.name.isEmpty && loaded.imageId == 0 && loaded.timezone == nil)
        precondition(loaded.standardProperties == SiteStandardProperties())
        let extensionState = try SiteExtensionStore.load(loaded)
        precondition(extensionState.data == SiteExtensionData() && extensionState.pending == nil)
        precondition(loaded.importFixture(siteJsonData: legacy), "Legacy replacement remains retryable after reopening SQLite")
        print("PASS: complete legacy Site defaults missing base/standard/extension fields across SQLite restart")
    }

    static func equalVersionReplacement(path: String) throws {
        let site = try SiteData.add(name: "Local pending", timezone: nil,
                                   standardProperties: .init(city: "Local city"))
        site.pendingSitePropsMask = [.siteName, .city]
        site.pendingSitePropsTimestamp = site.lastUpdate
        precondition(site.save())
        var cloudExtension = SiteExtensionData()
        cloudExtension.replaceZones([])
        try SiteExtensionStore.update(site) { state in
            state.receive(cloudExtension, timestamp: site.lastUpdate)
            var local = cloudExtension
            local.fields["localOnly"] = .bool(true)
            state.commit(local, now: site.lastUpdate + 1, siteTimestamp: site.lastUpdate)
        }
        let extensionObject = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cloudExtension))
        let payload: [String: Any] = ["uuid": site.id, "siteName": "Web name", "imageId": 2,
            "updateTimestamp": site.lastUpdate, "city": "Web city", "extensionData": extensionObject]
        let importer = SiteData.load(siteId: site.id)!
        try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER fail_equal_import BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        precondition(!importer.importFixture(siteJsonData: payload))
        precondition(importer.name == "Local pending" && importer.pendingSitePropsMask == [.siteName, .city])
        try SunSmartDataManager.shared.db!.execute("DROP TRIGGER fail_equal_import")
        precondition(importer.importFixture(siteJsonData: payload))
        SunSmartDataManager.shared.db = try Connection(path)
        let restored = SiteData.load(siteId: site.id)!
        precondition(restored.name == "Web name" && restored.city == "Web city" && restored.imageId == 2)
        precondition(restored.pendingSitePropsMask.isEmpty && restored.pendingSitePropsTimestamp == nil)
        let extensionState = try SiteExtensionStore.load(restored)
        precondition(extensionState.data == cloudExtension && extensionState.pending == nil && !extensionState.needsArchivedReview)
        print("PASS: SQLite equal-version Web Site replaces pending name/city, rolls back failure and survives restart")
    }

    static func cityIdentityPersistence(path: String) throws {
        let legacy = try SiteData.add(name: "Legacy city", timezone: nil,
                                      standardProperties: .init(city: "1880252"))
        let database = SunSmartDataManager.shared.db!
        try database.execute("ALTER TABLE sites DROP COLUMN cityId")
        SiteData.initDatabase()
        SunSmartDataManager.shared.db = try Connection(path)
        let upgraded = SiteData.load(siteId: legacy.id)!
        precondition(upgraded.city == "1880252" && upgraded.standardProperties.jsonObject["cityId"] is NSNull)
        precondition(upgraded.pendingSitePropsMask.isEmpty, "Adding the nullable column must not migrate/upload old city strings")
        let stale = SiteData.load(siteId: legacy.id)!
        let identity = try SiteStandardProperties.Patch(["city": "shenzhen", "cityId": 1880252])
        precondition(upgraded.save(standardPropertiesPatch: identity))
        precondition(stale.save())
        SunSmartDataManager.shared.db = try Connection(path)
        let fresh = SiteData.load(siteId: legacy.id)!
        precondition(fresh.city == "shenzhen" && fresh.standardProperties.jsonObject["cityId"] as? Int == 1880252)
        precondition(SiteData.loadAll().first { $0.id == legacy.id }!.standardProperties == fresh.standardProperties)
        precondition(fresh.copy().standardProperties == fresh.standardProperties)
        precondition(fresh.persistedPropsState()!.standardProperties == fresh.standardProperties)
        let before = fresh.standardProperties
        try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER fail_city BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let clear = try SiteStandardProperties.Patch(["city": NSNull(), "cityId": NSNull()])
        precondition(!fresh.save(standardPropertiesPatch: clear))
        precondition(SiteData.load(siteId: legacy.id)!.standardProperties == before)
        try SunSmartDataManager.shared.db!.execute("DROP TRIGGER fail_city")
        precondition(fresh.save(standardPropertiesPatch: clear) && stale.save())
        let cleared = SiteData.load(siteId: legacy.id)!
        precondition(cleared.city == nil && cleared.standardProperties.jsonObject["cityId"] is NSNull)
        print("PASS: SQLite cityId add-column without legacy conversion, paired save/restart/copy, stale save and rollback")
    }

    static func editedMetadataPersistence(path: String) async throws {
        let original = SiteStandardProperties(latitude: 0, longitude: -1.25, countryRegion: "SG", postalCode: "00123",
                                              city: "Singapore", cityId: 795565, address: "Street", siteDescription: "Lobby")
        let site = try SiteData.add(name: "Editable", timezone: nil, standardProperties: original)
        let other = try SiteData.add(name: "Other project", timezone: nil)
        precondition(!SiteData.isTautonym(siteName: site.name, excludingSiteID: site.id))
        precondition(SiteData.isTautonym(siteName: other.name, excludingSiteID: site.id))
        precondition(SiteData.isTautonym(siteName: site.name), "CREATE still rejects an existing name")
        let coordinator = SitePropsEditCoordinator(site: site)
        var draft = await coordinator.prepareDraft(online: false)
        draft.standardProperties.address = nil
        draft.standardProperties.postalCode = "00001"
        draft.standardProperties.latitude = -2.5
        // A second Site instance changes another field while this form remains open.
        let fresh = SiteData.load(siteId: site.id)!
        fresh.lastUpdate += 1
        fresh.standardProperties.city = "new city"
        precondition(fresh.save(standardPropertiesPatch: fresh.standardProperties.patch(for: .city)))
        let plan = coordinator.makeCommitPlan(draft: draft, online: false, now: fresh.lastUpdate + 1)
        let db = SunSmartDataManager.shared.db!
        try db.execute("CREATE TRIGGER fail_edit BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        guard case .failure = coordinator.persist(plan) else { preconditionFailure() }
        precondition(site.address == "Street" && site.city == "new city" && site.pendingSitePropsMask.isEmpty)
        try db.execute("DROP TRIGGER fail_edit")
        guard case .success = coordinator.persist(plan) else { preconditionFailure() }
        SunSmartDataManager.shared.db = try Connection(path)
        let restarted = SiteData.load(siteId: site.id)!
        precondition(restarted.address == nil && restarted.postalCode == "00001" && restarted.latitude == -2.5)
        precondition(restarted.longitude == -1.25 && restarted.city == "new city" && restarted.siteDescription == "Lobby")
        precondition(restarted.pendingSitePropsMask == [.address, .postalCode, .latitude])
        let retryCoordinator = SitePropsEditCoordinator(site: restarted)
        let retryDraft = await retryCoordinator.prepareDraft(online: false)
        let retry = retryCoordinator.makeCommitPlan(draft: retryDraft, online: true, now: restarted.lastUpdate + 1)
        let snapshot = retry.updateSnapshot!
        precondition(snapshot.timestamp == plan.targetState.lastUpdate && !retry.hasNewChanges)
        // A newer editor saves before the old ACK returns through its stale Site object.
        var later = retryDraft
        later.standardProperties.postalCode = "00002"
        let laterPlan = retryCoordinator.makeCommitPlan(draft: later, online: false, now: restarted.lastUpdate + 1)
        guard case .success = retryCoordinator.persist(laterPlan) else { preconditionFailure() }
        NetworkRequest.shared.result = .success(["data": ["updateTimestamp": snapshot.timestamp,
            "address": NSNull(), "postalCode": "00001", "latitude": "-2.5"]])
        _ = await coordinator.submit(snapshot)
        SunSmartDataManager.shared.db = try Connection(path)
        let preserved = SiteData.load(siteId: site.id)!
        precondition(preserved.postalCode == "00002" && preserved.pendingSitePropsTimestamp == laterPlan.targetState.lastUpdate)
        precondition(preserved.pendingSitePropsMask == [.address, .postalCode, .latitude])
        print("PASS: SQLite edit clears, duplicate identity, disjoint updates, rollback, restart retry and stale-instance ACK")
    }

    static func cityPendingSurvivesFullUploadReceipt(path: String) async throws {
        for addingSite in [false, true] {
            let site = try SiteData.add(name: "City receipt \(addingSite)", timezone: nil,
                standardProperties: .init(countryRegion: "US", city: "Before", cityId: 1))
            let oldTask = SiteData.load(siteId: site.id)!
            let submitted = oldTask.lastUpdate
            let editor = SitePropsEditCoordinator(site: SiteData.load(siteId: site.id)!)
            var draft = await editor.prepareDraft(online: false)
            draft.standardProperties.city = "After"
            draft.standardProperties.cityId = 2
            let plan = editor.makeCommitPlan(draft: draft, online: false, now: submitted + 1)
            guard case .success = editor.persist(plan) else { preconditionFailure() }
            let expected = plan.targetState
            let receipt = SiteSyncReceiptFixture(oldTask)
            let payload: [String: Any] = ["updateTimestamp": submitted, "city": "Before", "cityId": 1]
            let api: NetowrkReqeustApi = addingSite ? .siteAdd(siteData: payload, useDeivceAddressNum: 0) : .siteUpload(siteData: payload)
            try SunSmartDataManager.shared.db!.execute("CREATE TRIGGER fail_old_receipt BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
            precondition(!receipt.confirmSiteUpload(api: api, response: SiteSyncReceiptFixture.validAddResponse))
            precondition(SiteData.load(siteId: site.id)!.persistedPropsState() == expected)
            try SunSmartDataManager.shared.db!.execute("DROP TRIGGER fail_old_receipt")
            precondition(receipt.confirmSiteUpload(api: api, response: SiteSyncReceiptFixture.validAddResponse))
            SunSmartDataManager.shared.db = try Connection(path)
            let restarted = SiteData.load(siteId: site.id)!
            precondition(restarted.city == "After" && restarted.cityId == 2)
            precondition(restarted.pendingSitePropsMask == [.city, .cityId]
                && restarted.pendingSitePropsTimestamp == submitted + 1 && restarted.lastUpdate == submitted + 1,
                "An older full-upload ACK must preserve the newer city's pending identity and version")
            precondition(restarted.lastUploadCloudTimestamp == submitted)
            let retryEditor = SitePropsEditCoordinator(site: restarted)
            let retryDraft = await retryEditor.prepareDraft(online: false)
            let retry = retryEditor.makeCommitPlan(draft: retryDraft, online: true, now: submitted + 2).updateSnapshot!
            precondition(retry.fields == [.city, .cityId] && retry.timestamp == submitted + 1)
            NetworkRequest.shared.result = .success(["data": ["updateTimestamp": retry.timestamp, "city": "After", "cityId": 2]])
            let accepted = await retryEditor.submit(retry)
            precondition(accepted && SiteData.load(siteId: site.id)!.pendingSitePropsMask.isEmpty)
        }
        print("PASS: SQLite new city pending/version survives old full-upload/Add ACK, failure rollback, restart and paired retry")
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
        precondition(exported["latitude"] as? String == "22.54554" && exported["longitude"] as? String == "114.0683")
        print("PASS: string-coordinate Site import -> SQLite reopen -> string JSON export")
    }

    static func coordinateFallbackImport(path: String) throws {
        let site = try SiteData.add(name: "Coordinate fallback", timezone: nil)
        let initial: [String: Any] = ["uuid": site.id, "siteName": site.name,
            "updateTimestamp": site.lastUpdate, "latitude": "22.5", "longitude": "113.5", "city": "Keep"]
        precondition(site.importFixture(siteJsonData: initial))
        for (json, source, expectedLatitude, expectedLongitude) in [
            (#"{"latitude":"","longitude":"114"}"#, SiteImportSource.listSummary, nil as Double?, 114.0 as Double?),
            (#"{}"#, .listSummary, nil, 114.0),
            (#"{"latitude":"22.5","longitude":false}"#, .listSummary, 22.5, nil),
            (#"{"latitude":"","longitude":""}"#, .completeDetail, nil, nil)
        ] {
            let importer = SiteData.load(siteId: site.id)!
            var payload = try JSONSerialization.jsonObject(with: Data(json.utf8)) as! [String: Any]
            payload["uuid"] = site.id
            payload["siteName"] = site.name
            payload["updateTimestamp"] = importer.lastUpdate + 1
            precondition(importer.importFixture(siteJsonData: payload, source: source))
            SunSmartDataManager.shared.db = try Connection(path)
            let reopened = SiteData.load(siteId: site.id)!
            precondition(reopened.latitude == expectedLatitude && reopened.longitude == expectedLongitude,
                         "Coordinate fallback and omitted-field handling must survive SQLite reopen")
            if source == .listSummary { precondition(reopened.city == "Keep") }
            precondition(SiteData.loadAll().contains(where: { $0.id == site.id }))
            let bytes = try JSONSerialization.data(withJSONObject: reopened.standardProperties.jsonObject)
            let exported = try JSONSerialization.jsonObject(with: bytes) as! [String: Any]
            for (key, expected) in [("latitude", expectedLatitude), ("longitude", expectedLongitude)] {
                if let expected { precondition(exported[key] as? String == String(expected)) }
                else { precondition(exported[key] is NSNull) }
            }
        }
        print("PASS: invalid-coordinate JSON import, independent fallback, partial omission, SQLite reopen and string/null export")
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
            "updateTimestamp": readerSite.lastUpdate, "city": "New city", "cityId": 123456, "longitude": "80"]]])
        _ = await reader.prepareDraft(online: true)
        let fresh = readerSite.standardProperties
        precondition(fresh.city == "New city" && fresh.cityId == 123456 && fresh.longitude == 80 && fresh.latitude == nil)
        // Both receipt operations must preserve a props read that arrived in flight.
        let addSpaces = SiteSyncReceiptFixture(oldAddSpaces, addingSpaces: true)
        precondition(addSpaces.confirmSiteUpload(api: .siteUpload(siteData: ["updateTimestamp": readerSite.lastUpdate]), response: [:]))
        let addSite = SiteSyncReceiptFixture(oldAddSite)
        precondition(addSite.confirmSiteUpload(api: .siteAdd(siteData: [
            "updateTimestamp": oldAddSite.lastUpdate, "timezone": oldAddSite.timezone!], useDeivceAddressNum: 0), response: SiteSyncReceiptFixture.validAddResponse))
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
        let confirmedTimestamp = SiteData.load(siteId: siteID)!.lastUploadCloudTimestamp
        oldAddSpaces.syncCloudError = .unknown
        try db.execute("CREATE TRIGGER fail_site BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let retryAPI = NetowrkReqeustApi.siteUpload(siteData: ["updateTimestamp": snapshot.timestamp])
        for _ in 0..<2 {
            precondition(!addSpaces.confirmSiteUpload(api: retryAPI, response: [:]))
            precondition(oldAddSpaces.lastUploadCloudTimestamp == confirmedTimestamp && oldAddSpaces.syncCloudError?.code == -1)
            precondition(SiteData.load(siteId: siteID)!.standardProperties == fresh)
        }
        try db.execute("DROP TRIGGER fail_site")
        precondition(addSpaces.confirmSiteUpload(api: retryAPI, response: [:]))
        SunSmartDataManager.shared.db = try Connection(path)
        let restarted = SiteData.load(siteId: siteID)!
        precondition(restarted.standardProperties == fresh && restarted.lastUploadCloudTimestamp == snapshot.timestamp)
        precondition(restarted.syncCloudError == nil && restarted.name == "Renamed" && restarted.lastUpdate == snapshot.timestamp)
        print("PASS: SQLite props readback with Site Add/addSpaces receipts, stale editor save, failed ACK and durable retry")
    }

    static func failedImportAndRetry(siteID: String, path: String) throws {
        let importer = SiteData.load(siteId: siteID)!
        let previous = importer.standardProperties
        let timestamp = importer.lastUpdate
        let db = SunSmartDataManager.shared.db!
        try db.execute("CREATE TRIGGER fail_site BEFORE INSERT ON sites BEGIN SELECT RAISE(FAIL, 'fixture'); END;")
        let payload: [String: Any] = ["uuid": siteID, "siteName": "Imported",
            "updateTimestamp": timestamp + 2, "city": NSNull(), "latitude": "", "longitude": "invalid"]
        precondition(!importer.importFixture(siteJsonData: payload))
        precondition(importer.standardProperties == previous && importer.lastUpdate == timestamp)
        precondition(SiteData.load(siteId: siteID)!.standardProperties == previous)
        try db.execute("DROP TRIGGER fail_site")
        precondition(importer.importFixture(siteJsonData: payload))
        let cleared = importer.standardProperties
        precondition(cleared.city == nil && cleared.latitude == nil && cleared.longitude == nil)
        SunSmartDataManager.shared.db = try Connection(path)
        precondition(SiteData.load(siteId: siteID)!.standardProperties == cleared)
        print("PASS: SQLite failed coordinate-fallback import rollback, retry and restart")
    }
}
