import Foundation

// Network and database failures are controllable boundaries; parsing, merging,
// editing, acknowledgement and rollback run the production API/coordinator.
enum NetworkApiError: Error { case unknown }
enum NetowrkReqeustApi {
    case sitePropsRetrieve(siteId: String)
    case sitePropsUpdate(siteId: String, props: [String: Any])
}
final class NetworkRequest {
    static let shared = NetworkRequest()
    var result: Result<[String: Any], NetworkApiError> = .failure(.unknown)
    var targets: [NetowrkReqeustApi] = []
    var duringRequest: (() -> Void)?
    func request(_ target: NetowrkReqeustApi) async -> Result<[String: Any], NetworkApiError> {
        targets.append(target)
        duringRequest?()
        return result
    }
}
enum UserData { static let currentServerRegion = 1 }
enum DataSourceType: Int { case create = 1 }
enum SpaceMembershipCoordinator { static func accepts(_ object: [String: Any]) -> Bool { true } }
final class SiteData {
    enum State { case normal }
    let id = "site", region = 1
    let state = State.normal
    var name = "Site", imageId = 1
    var timezone: String?
    var create: Int64 = 10
    var sourceType = DataSourceType.create
    var lastUpdate: Int64 = 10, lastUploadCloudTimestamp: Int64? = 10
    var pendingSitePropsMask: SitePropsFieldMask = []
    var pendingSitePropsTimestamp: Int64?
    var standardProperties = SiteStandardProperties(latitude: 0, longitude: -72.5,
        countryRegion: "SG", postalCode: "018983", city: "795565", address: "Street", siteDescription: "Lobby")
    var failSave = false
    var saves = 0
    func save(standardPropertiesPatch: SiteStandardProperties.Patch = .init()) -> Bool {
        saves += 1
        guard !failSave else { return false }
        standardProperties = standardPropertiesPatch.applying(to: standardProperties)
        return true
    }
}
enum SiteExtensionStore {
    static var receives = 0
    static func receive(_ site: SiteData, object: [String: Any], timestamp: Int64) throws { receives += 1 }
}
protocol SiteTimeZoneEditSubmitting: AnyObject {
    func submit(_ snapshot: SitePropsUpdateSnapshot) async -> Bool
}
protocol SiteEntryTimeZoneSyncStore: AnyObject {}

@main enum SiteStandardPropsIntegrationTests {
    @MainActor static func main() async throws {
        testFullImportBoundaries()
        let network = NetworkRequest.shared
        let site = SiteData()
        let coordinator = SitePropsEditCoordinator(site: site)
        let original = site.standardProperties

        network.result = .success(["data": ["props": ["siteName": "Site", "imageId": 1,
            "updateTimestamp": 10, "latitude": NSNull(), "city": "99999999"]]])
        _ = await coordinator.prepareDraft(online: true)
        precondition(site.latitude == nil && site.standardProperties.city == "99999999")
        precondition(site.standardProperties.longitude == -72.5 && site.standardProperties.postalCode == "018983")

        let beforeFailure = coordinator.currentState()
        site.failSave = true
        network.result = .success(["data": ["props": ["siteName": "Cloud", "imageId": 2,
            "updateTimestamp": 11, "longitude": "80", "address": NSNull()]]])
        _ = await coordinator.prepareDraft(online: true)
        precondition(coordinator.currentState() == beforeFailure, "Failed save must roll back properties and version")
        site.failSave = false
        _ = await coordinator.prepareDraft(online: true)
        precondition(site.standardProperties.longitude == 80 && site.standardProperties.address == nil && site.lastUpdate == 11)

        var draft = await coordinator.prepareDraft(online: false)
        draft.values.siteName = "Edited"
        site.standardProperties.city = "123456" // A separate fresh read while the editor is open.
        let plan = coordinator.makeCommitPlan(draft: draft, online: true, now: 12)
        guard case let .success(snapshot?) = coordinator.persist(plan) else { preconditionFailure() }
        precondition(site.standardProperties.city == "123456")
        let pending = coordinator.currentState()
        network.result = .failure(.unknown)
        let failed = await coordinator.submit(snapshot)
        precondition(!failed && coordinator.currentState() == pending)
        network.result = .success(["data": ["siteName": "Edited", "updateTimestamp": 12]])
        let succeeded = await coordinator.submit(snapshot)
        precondition(succeeded && site.pendingSitePropsMask.isEmpty && site.standardProperties.city == "123456")
        guard case let .sitePropsUpdate(_, props) = network.targets.last else { preconditionFailure() }
        precondition(props["siteName"] as? String == "Edited")
        precondition(SiteStandardProperties.keys.allSatisfy { props[$0] == nil }, "Existing edits must not send stale metadata")

        let accepted = coordinator.currentState()
        let receives = SiteExtensionStore.receives, saves = site.saves
        network.result = .success(["data": ["props": ["siteName": "Invalid", "imageId": 3,
            "updateTimestamp": 20, "longitude": "invalid", "countryRegion": "US"]]])
        _ = await coordinator.prepareDraft(online: true)
        precondition(coordinator.currentState() == accepted && site.saves == saves && SiteExtensionStore.receives == receives)

        network.result = .success(["data": ["props": ["siteName": "Older", "imageId": 1,
            "updateTimestamp": 1, "city": NSNull()]]])
        _ = await coordinator.prepareDraft(online: true)
        precondition(coordinator.currentState() == accepted)

        draft = await coordinator.prepareDraft(online: false)
        draft.values.imageId = 4
        let latePlan = coordinator.makeCommitPlan(draft: draft, online: true, now: 13)
        guard case let .success(lateSnapshot?) = coordinator.persist(latePlan) else { preconditionFailure() }
        network.result = .success(["data": ["imageId": 4, "updateTimestamp": 13, "city": "1"]])
        network.duringRequest = {
            site.lastUpdate = 14
            site.standardProperties = original
            site.pendingSitePropsTimestamp = 14
        }
        _ = await coordinator.submit(lateSnapshot)
        network.duringRequest = nil
        precondition(site.standardProperties == original && site.lastUpdate == 14 && site.pendingSitePropsTimestamp == 14)
        print("PASS: production Site props read/edit, same-version merge, save rollback, retry and late ACK preservation")
    }

    static func testFullImportBoundaries() {
        let site = SiteData()
        let original = site.standardProperties
        var data: [String: Any] = ["uuid": "site", "siteName": "Cloud", "imageId": 2,
            "type": 1, "createTimestamp": 1, "updateTimestamp": 10, "latitude": NSNull(), "city": "123456"]
        precondition(site.importFixture(siteJsonData: data))
        precondition(site.standardProperties.latitude == nil && site.standardProperties.city == "123456")
        precondition(site.standardProperties.longitude == original.longitude, "Same-version completion must preserve omitted fields")
        site.standardProperties = original
        data["updateTimestamp"] = 20
        site.failSave = true
        precondition(!site.importFixture(siteJsonData: data))
        precondition(site.standardProperties == original && site.lastUpdate == 10 && site.lastUploadCloudTimestamp == 10)
        precondition(site.name == "Site" && site.imageId == 1, "Failed full import must restore the base props with its version")
        site.failSave = false
        precondition(site.importFixture(siteJsonData: data, duringPreparation: { site.lastUpdate = 21 }))
        precondition(site.standardProperties.city == "123456" && site.lastUpdate == 21,
            "Import's own resource-cleanup version must not block its standard fields")
        data["updateTimestamp"] = 22
        precondition(site.importFixture(siteJsonData: data, duringSuspension: {
            site.lastUpdate = 23
            site.standardProperties.city = "795565"
        }))
        precondition(site.standardProperties.city == "795565" && site.lastUpdate == 23)
        data["updateTimestamp"] = 21
        precondition(site.importFixture(siteJsonData: data))
        precondition(site.standardProperties.city == "795565", "Late full response must not replace newer fields")
        let saves = site.saves
        data["latitude"] = true
        precondition(!site.importFixture(siteJsonData: data) && site.saves == saves)
        data["latitude"] = 0
        data["updateTimestamp"] = 24
        site.pendingSitePropsMask = [.timezone]
        precondition(site.importFixture(siteJsonData: data))
        precondition(site.standardProperties.city == "795565", "Pending local changes must remain protected")
        print("PASS: production full-import preflight, same-version metadata, cleanup version, suspension and failed-save rollback")
    }
}

private extension SiteData {
    var latitude: Double? { standardProperties.latitude }
}
