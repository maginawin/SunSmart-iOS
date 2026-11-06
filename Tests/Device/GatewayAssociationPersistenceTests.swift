import Foundation
import SQLite

typealias Address = UInt16
protocol Copyable {}
enum UserData { static let currentUserId = "test-account", currentServerRegion = "test-region" }
struct NetworkApiError: Error { let code: Int }
extension String { var localizedString: String { self } }
enum GatewayInformation { struct MQTTConnectInformation: Codable, Equatable {} }
class Node {}
class MeshNetwork { func node(withAddress: Address) -> Node? { nil } }
class MeshNetworkManager { static let instance = MeshNetworkManager(); var meshNetwork: MeshNetwork? }
class SpaceData { var id = "space"; var canEditGatewayAssociation = true; static func load(siteId: String, spaceId: String) -> [SpaceData] { [] } }
extension GatewaySpaceData { func updatePermission(from space: SpaceData?) {} }
class SunSmartDataManager { static let shared = SunSmartDataManager(); var db: Connection? }
let jsonEncoder = JSONEncoder(), jsonDecoder = JSONDecoder()
enum GatewayDeletionContext {
    static let lock = NSRecursiveLock()
    static func lockImport() { lock.lock() }
    static func unlockImport() { lock.unlock() }
    static func blocksSave(_ gateway: GatewayModel) -> Bool { false }
}

@main struct GatewayAssociationPersistenceTests {
    static func main() async throws {
        let database = try Connection(.inMemory)
        SunSmartDataManager.shared.db = database
        try database.run("""
        CREATE TABLE gateways (id INTEGER PRIMARY KEY, siteUUID TEXT, macAddress TEXT, name TEXT,
          address INTEGER, activate INTEGER, associatedSpaces BLOB, apn TEXT, mqttServerInfo BLOB,
          lastUpdateTimestamp INTEGER, lastUploadCloudTimestamp INTEGER, syncCloudError INTEGER,
          serverDeletionPendingLocalReset INTEGER, registrationProtectionSnapshot BLOB,
          UNIQUE(siteUUID, macAddress))
        """)
        let gateway = GatewayModel(siteId: "site", name: "Gateway", address: 2, mac: "TEST", lastUpdate: 10)
        gateway.lastUploadCloudTimestamp = 10
        precondition(gateway.save())
        let scope = GatewayOrphanGuard.Scope.current(siteID: "site")
        func response() -> [String: Any] {
            [GatewayOrphanGuard.payloadKey: GatewayOrphanGuard.capture(account: UserData.currentUserId,
                region: UserData.currentServerRegion, detailSiteID: "site")]
        }
        func stored() -> GatewayModel { GatewayModel.load(siteId: "site", macAddress: "TEST").first! }
        let oldResponse = response()
        let draft = gateway.copy()
        draft.associatedSpaces = [GatewaySpaceData(spaceId: "space", spaceName: "Space", deviceCount: 0, appKeyIndex: 1)]
        precondition(gateway.commitConfiguration(draft))
        precondition(stored().associatedSpaces.map(\.appKeyIndex) == [1])
        precondition(stored().needUploadCloud, "saving a binding must protect it before any Site refresh")
        precondition(!GatewayOrphanGuard.allowsConfigurationImport(oldResponse, scope: scope, mac: "TEST"))
        let duringUpload = response()
        gateway.lastUploadCloudTimestamp = gateway.lastUpdate
        precondition(gateway.save())
        precondition(!GatewayOrphanGuard.allowsConfigurationImport(duringUpload, scope: scope, mac: "TEST"),
            "request issued while cloud was stale must remain rejected after upload confirmation")
        precondition(GatewayOrphanGuard.allowsConfigurationImport(response(), scope: scope, mac: "TEST"))
        precondition(GatewayOrphanGuard.acceptsSnapshot(oldResponse, scope: scope), "preserve other Site fields")
        precondition(GatewayOrphanGuard.allowsConfigurationImport(oldResponse, scope: scope, mac: "UNRELATED"))
        let staleWriter = gateway.copy()
        draft.associatedSpaces = []
        precondition(gateway.commitConfiguration(draft))
        precondition(stored().associatedSpaces.isEmpty && stored().needUploadCloud, "last association removal survives reload")
        precondition(!staleWriter.save(), "late old upload must not restore removed associations")
        precondition(stored().associatedSpaces.isEmpty)
        precondition(GatewayOrphanGuard.allowsConfigurationImport([:], scope: scope, mac: "TEST"), "unstamped local/legacy imports still use normal dirty/merge policy")
        let serverReplacement = gateway.copy()
        serverReplacement.lastUpdate = 1; serverReplacement.lastUploadCloudTimestamp = 1
        precondition(serverReplacement.save(importingConfiguration: true), "explicit authoritative identity replacement may have an older timestamp")
        precondition(stored().lastUploadCloudTimestamp == 1)
        precondition(gateway.commitConfiguration(draft))
        let page = GatewaySavePage(gateway: gateway)
        let one = GatewaySpaceData(spaceId: "space", spaceName: "Space", deviceCount: 0, appKeyIndex: 1)
        let two = GatewaySpaceData(spaceId: "second", spaceName: "Second", deviceCount: 0, appKeyIndex: 2)
        page.setGatewayModel.associatedSpaces = [one, two]
        NetworkRequest.shared.results = [.success([:]), .failure(NetworkApiError(code: 1))]
        NetworkRequest.shared.beforeRequest = { request in
            if case .gatewayBindSpace(let id, _) = request, id == "second" {
                precondition(stored().associatedSpaces.map(\.appKeyIndex) == [1] && stored().needUploadCloud,
                    "first confirmed bind must be durable before the next async request")
            }
        }
        let partial = await page.saveAssociatedSpacesIfNeeded()
        precondition(!partial.succeeded && partial.topologyChanged)
        precondition(stored().associatedSpaces.map(\.appKeyIndex) == [1])
        precondition(page.setGatewayModel.associatedSpaces.count == 2, "failed reconciliation retains the unsaved remainder")
        page.references = [.success([one])]
        page.setGatewayModel.associatedSpaces = []
        NetworkRequest.shared.results = [.success([:])]; NetworkRequest.shared.beforeRequest = { _ in }
        let removal = await page.saveAssociatedSpacesIfNeeded()
        precondition(removal.succeeded && stored().associatedSpaces.isEmpty && stored().needUploadCloud)
        let beforeFailure = gateway.lastUpdate
        try database.run("CREATE TRIGGER fail_write BEFORE INSERT ON gateways BEGIN SELECT RAISE(ABORT, 'test failure'); END")
        draft.associatedSpaces = [GatewaySpaceData(spaceId: "other", spaceName: "Other", deviceCount: 0, appKeyIndex: 2)]
        precondition(!gateway.commitConfiguration(draft))
        precondition(gateway.lastUpdate == beforeFailure && gateway.associatedSpaces.isEmpty)
        precondition(stored().associatedSpaces.isEmpty, "failed persistence cannot publish new intent")
        print("PASS Gateway association JSON/SQLite: dirty save, remove last, late response/ACK, stale writer and rollback")
    }
}

struct Gateway { let mac = "TEST" }
class SiteData { enum Permission { case owner }; var permission = Permission.owner; var spaces = [SpaceData()] }
enum Request { case gatewayBindSpace(spaceId: String, gatewayId: String), gatewayUnbindSpace(spaceId: String, gatewayId: String) }
class NetworkRequest {
    static let shared = NetworkRequest(); var networkable = true
    var results: [Swift.Result<[String: Any], NetworkApiError>] = []
    var beforeRequest: (Request) -> Void = { _ in }
    func request(_ request: Request) async -> Swift.Result<[String: Any], NetworkApiError> {
        beforeRequest(request); await Task.yield(); return results.removeFirst()
    }
}
enum XWHUDManager {
    static func showTipHUD(_ text: String, isLineFeed: Bool, afterDelay: Double) {}
    static func showCustomHUD(withMessage: String?, isWindow: Bool) {}
    static func showErrorTipHUD(_ text: String) {}
    static func hide() {}
}
class GatewaySavePage {
    let gatewayModel: GatewayModel, setGatewayModel: GatewayModel
    let site = SiteData(), gateway = Gateway()
    var references: [Swift.Result<[GatewaySpaceData], Error>] = [.success([]), .failure(NetworkApiError(code: 1))]
    enum Section { case associatedSpaces, name }
    init(gateway: GatewayModel) { gatewayModel = gateway; setGatewayModel = gateway.copy() }
    func loadAssociatedSpaces() async -> Swift.Result<[GatewaySpaceData], Error> { references.removeFirst() }
    func reloadSection(_ section: Section) {}
    func updateSaveBtnState() {}
    // PRODUCTION_SAVE_METHODS
}
