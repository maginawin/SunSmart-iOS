import Foundation

// Network and database boundaries for the production Site confirmation method.
enum NetowrkReqeustApi {
    case siteUpload(siteData: [String: Any])
    case siteAdd(siteData: [String: Any], useDeivceAddressNum: Int)
    case spaceUpload(siteId: String, spaceId: String, spaceData: [String: Any])
}

final class SiteData {
    var name = "Site", imageId = 1, timezone: String?
    var lastUpdate: Int64 = 100, lastUploadCloudTimestamp: Int64?
    var pendingSitePropsMask: SitePropsFieldMask = []
    var pendingSitePropsTimestamp: Int64?
    var syncCloudError: NetworkApiError? = .noNetwork
    var savesSucceed = true
    var resources: [String: Any]?
    func setOwnerProvisioner(addressData: [String: Any]) { resources = addressData }
    func save() -> Bool { savesSucceed }
}

enum SyncOperation {
    case syncSite(site: SiteData, syncSpaces: [SpaceData])
    case addSpaces(site: SiteData, spaces: [SpaceData])
    case syncSpace(space: SpaceData)
}

@MainActor final class SiteConfirmationHarness {
    let operation: SyncOperation
    init(_ operation: SyncOperation) { self.operation = operation }
    // SITE_CONFIRMATION_METHOD
}

extension SpaceRecoveryReceiptTests {
    @MainActor static func testCloudSiteConfirmation() async throws {
        let request = NetworkRequest.shared
        let calls = request.calls
        for addsSpaces in [false, true] {
            let site = SiteData()
            let uploaded = SpaceData("site-submitted-\(addsSpaces)")
            let untouched = SpaceData("site-untouched-\(addsSpaces)")
            let operation: SyncOperation = addsSpaces
                ? .addSpaces(site: site, spaces: [uploaded])
                : .syncSite(site: site, syncSpaces: [uploaded])
            let api = NetowrkReqeustApi.siteUpload(siteData: [
                "updateTimestamp": 100, "spaces": [uploaded.payload]
            ])
            site.lastUpdate = 101
            let handler = SiteConfirmationHarness(operation)
            precondition(handler.confirmSiteUpload(api: api, response: [:]))
            precondition(site.lastUploadCloudTimestamp == 100 && site.lastUpdate == 101)
            precondition(site.syncCloudError == nil)
            precondition(api.configurationSpacePayloads.count == 1)
            let context = SpaceConfigurationSafety.prepareSubmission(uploaded, payload: api.configurationSpacePayloads[0])!
            precondition(SpaceConfigurationSafety.markSubmissionAccepted(context, space: uploaded))
            precondition(!SpaceConfigurationSafety.finishAcceptedSubmission(context, space: uploaded))
            request.result = .success(["data": uploaded.payload])
            if case .failure = await SpaceConfigurationSafety.resumeUpload(uploaded) {
                preconditionFailure("Site Space upload requires a complete Key readback")
            }
            precondition(uploaded.lastUploadCloudTimestamp == 50 && untouched.lastUploadCloudTimestamp == nil)
            site.lastUploadCloudTimestamp = 200
            precondition(handler.confirmSiteUpload(api: api, response: [:]))
            precondition(site.lastUploadCloudTimestamp == 200)
        }
        let callsAfterSpaceReadback = request.calls
        let siteOnly = SiteData()
        let handler = SiteConfirmationHarness(.syncSite(site: siteOnly, syncSpaces: []))
        let api = NetowrkReqeustApi.siteUpload(siteData: ["updateTimestamp": 100])
        precondition(api.configurationSpacePayloads.isEmpty)
        siteOnly.savesSucceed = false
        precondition(!handler.confirmSiteUpload(api: api, response: [:]))
        precondition(siteOnly.lastUploadCloudTimestamp == nil && siteOnly.syncCloudError == .noNetwork)
        siteOnly.savesSucceed = true
        precondition(handler.confirmSiteUpload(api: api, response: [:]))
        precondition(siteOnly.lastUploadCloudTimestamp == 100)

        for newEdit in [false, true] {
            let site = SiteData()
            // Use the production storage representation.
            let timezone = SiteTimeZoneValue(ianaId: "Asia/Singapore", rawUTCOffset: "+08:00")!
            site.timezone = timezone.storageValue
            site.pendingSitePropsMask = [.timezone]
            site.pendingSitePropsTimestamp = newEdit ? 101 : 100
            site.lastUpdate = newEdit ? 101 : 100
            let api = NetowrkReqeustApi.siteAdd(siteData: [
                "updateTimestamp": Int64(100), "timezone": timezone.storageValue
            ], useDeivceAddressNum: 1)
            let handler = SiteConfirmationHarness(.syncSite(site: site, syncSpaces: []))
            precondition(handler.confirmSiteUpload(api: api, response: ["data": ["addrLists": ["marker": 7]]]))
            precondition(site.resources?["marker"] as? Int == 7 && site.lastUploadCloudTimestamp == 100)
            precondition(site.pendingSitePropsMask.isEmpty == !newEdit)
        }
        precondition(request.calls == callsAfterSpaceReadback && callsAfterSpaceReadback == calls + 2,
            "Site confirmation itself must never issue a GET")
        print("PASS: production Site-only, Site/Space versions, addSpaces, creation resources, timezone pending and save failures")
    }
}
