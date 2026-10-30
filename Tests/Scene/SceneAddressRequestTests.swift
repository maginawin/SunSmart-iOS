import Foundation

// Only the two marked declarations are production logic. These boundaries do
// not prove real HTTP response compatibility, SQLite durability or UIKit layout.
extension String { var localizedString: String { self }; var hex: String { self } }
struct JSON {
    let value: Any
    init(_ value: Any) { self.value = value }
    subscript(_ key: String) -> JSON { JSON((value as? [String: Any])?[key] as Any) }
    var dictionaryObject: [String: Any]? { value as? [String: Any] }
}
enum DispatchQueue {
    struct Queue { func async(_ action: () -> Void) { action() } }; static let main = Queue()
}
struct SceneScope { let meshUUID: String; let networkID: String }
enum SceneConfigurationStore {
    enum Failure: Error { case noNumber, persistence, staleDraft }
    static func validateAccess(_ scope: SceneScope) throws {
        guard scope.meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString,
              scope.networkID == MeshNetworkManager.instance.currentNetworkKey.networkId else { throw Failure.staleDraft }
    }
}
enum SpaceChangeDataType { case common }
let spaceDataChangedNotificaitonName = "fixture-space"
let sceneDataUpdateNotificationName = "fixture-scene"
final class AllocatedScene {}
final class AllocationCoordinator {
    enum CommitResult { case ready(AllocatedScene), projectionPending(Int) }
    var allocationAvailable = true
    var expectedRevision: UUID?
    var creations = 0
    func saveForSync(draft: SceneAddressRequestHarness.Draft) throws -> CommitResult {
        precondition(draft.revision == expectedRevision)
        guard allocationAvailable else { throw SceneConfigurationStore.Failure.noNumber }
        creations += 1; return .ready(AllocatedScene())
    }
}
enum XWHUDManager {
    static var errors: [String] = []
    static func showErrorTipHUD(_ message: String) { errors.append(message) }
    static func showCustomHUD(withMessage: String, isWindow: Bool) {}
    static func hide() {}
}
final class Network {
    let uuid = UUID()
    var savesSucceed = true
    func save() -> Bool { savesSucceed }
}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network()
    struct Key { var networkId = "space-A" }
    var currentNetworkKey = Key()
}
final class SiteData {
    static let site = SiteData()
    var updates = 0
    static func load(siteId: String) -> SiteData? { site }
    func setProvisioner(provisionerData: [String: Any]) { updates += 1 }
}
enum SceneCapacity {
    // PRODUCTION_VALIDATION
}
enum RequestError: Error { case offline }
enum AddressType { case scene }
enum Request { case applyAddress(siteId: String, type: AddressType, number: Int) }
final class NetworkRequest {
    static let shared = NetworkRequest()
    var count = 0
    var pending: ((Result<[String: Any], RequestError>) -> Void)?
    func request(_ request: Request, completion: @escaping (Result<[String: Any], RequestError>) -> Void) {
        count += 1
        pending = completion
    }
    func complete(_ result: Result<[String: Any], RequestError>) {
        let callback = pending
        pending = nil
        callback?(result)
    }
}
final class SceneAddressRequestHarness {
    struct Space {
        let siteId = "site"
        let meshUUID = MeshNetworkManager.instance.meshNetwork!.uuid.uuidString
        let meshNetworkId = "space-A"
    }
    final class View { var window: NSObject? = NSObject() }
    let space = Space()
    var viewIfLoaded: View? = View()
    struct Draft { var revision = UUID(); let scope: SceneScope }
    struct Selection { let draft: Draft }
    var selection: Selection?
    // PRODUCTION_LIFECYCLE
    var active = true
    private var requestedAddresses: UUID?
    private var busy = false
    var syncPagePresented = false
    func openSyncPage(_ scene: AllocatedScene) { syncPagePresented = true }
    let coordinator = AllocationCoordinator()
    init() {
        selection = .init(draft: .init(scope: .init(meshUUID: space.meshUUID, networkID: space.meshNetworkId)))
        coordinator.expectedRevision = selection!.draft.revision
    }
    func accepts(_ token: UUID, revision: UUID) -> Bool { active && lifecycle == token && selection?.draft.revision == revision && viewIfLoaded?.window != nil }
    func setBusy(_ value: Bool) { busy = value }
    func failed(_ error: Error) { setBusy(false); XWHUDManager.errors.append(String(describing: error)) }
    func tip(_ key: String) { XWHUDManager.errors.append(key) }
    var allocationAvailable: Bool { get { coordinator.allocationAvailable } set { coordinator.allocationAvailable = newValue } }
    var creationAttempts: Int { coordinator.creations }
    // PRODUCTION_COMMIT
    func abandonPendingWork() { active = false; lifecycle = UUID(); busy = false }
    func continueEditing() { active = true }
    // Simulate the exhausted-pool branch on every user tap, without allocating.
    func tapCreateWithExhaustedPool() { if !busy { requestAddresses(revision: selection!.draft.revision) } }
    // PRODUCTION_REQUEST
}

@main enum SceneAddressRequestTests {
    static var failures = 0
    static func expect(_ condition: Bool, _ message: String) {
        print("\(condition ? "PASS" : "FAIL"): \(message)")
        if !condition { failures += 1 }
    }
    static func fixture() -> SceneAddressRequestHarness {
        MeshNetworkManager.instance.meshNetwork = Network()
        MeshNetworkManager.instance.currentNetworkKey = .init()
        NetworkRequest.shared.count = 0
        NetworkRequest.shared.pending = nil
        SiteData.site.updates = 0
        XWHUDManager.errors = []
        return SceneAddressRequestHarness()
    }
    static func main() {
        let transport = NetworkRequest.shared
        let valid: [String: Any] = ["data": ["provisioner": [
            "allocatedUnicastRange": [["lowAddress": "0001", "highAddress": "0010"]],
            "allocatedGroupRange": [["lowAddress": "C000", "highAddress": "C00F"]],
            "allocatedSceneRange": [["firstScene": "0011", "lastScene": "0020"]]
        ]]]
        var page = fixture()
        page.tapCreateWithExhaustedPool()
        page.tapCreateWithExhaustedPool()
        expect(transport.count == 1, "Repeated taps do not duplicate an in-flight allocation")
        transport.complete(.success(valid))
        expect(page.creationAttempts == 1 && SiteData.site.updates == 1,
               "A valid allocation resumes creation once")

        page = fixture()
        page.tapCreateWithExhaustedPool()
        transport.complete(.failure(.offline))
        page.tapCreateWithExhaustedPool()
        expect(transport.count == 2, "Transport failure allows retry on the same page")

        page = fixture()
        page.tapCreateWithExhaustedPool()
        transport.complete(.success(["code": 200, "data": [:]]))
        expect(page.creationAttempts == 0 && SiteData.site.updates == 0,
               "An incomplete successful response must not persist or create")
        page.tapCreateWithExhaustedPool()
        expect(transport.count == 2, "Invalid allocation response allows retry without discarding page input")

        page = fixture()
        page.tapCreateWithExhaustedPool()
        MeshNetworkManager.instance.currentNetworkKey.networkId = "space-B"
        transport.complete(.success(valid))
        expect(page.creationAttempts == 0 && SiteData.site.updates == 0,
               "A response for a previous Space cannot change the current allocation")
        page = fixture()
        let revision = page.selection!.draft.revision
        page.tapCreateWithExhaustedPool()
        page.active = false; page.lifecycle = UUID()
        transport.complete(.success(valid))
        expect(page.creationAttempts == 0 && SiteData.site.updates == 0 && page.selection?.draft.revision == revision,
               "Background/abandoned page does not apply allocation or replace the draft")
        page = fixture(); page.tapCreateWithExhaustedPool()
        page.abandonPendingWork(); transport.complete(.success(valid)); page.continueEditing()
        page.tapCreateWithExhaustedPool(); transport.complete(.success(valid))
        expect(transport.count == 2 && page.creationAttempts == 1, "old response before foreground retry also releases the draft")
        for path in ["background", "close then keep editing"] {
            page = fixture(); page.tapCreateWithExhaustedPool()
            let oldResponse = transport.pending
            page.abandonPendingWork(); page.continueEditing()
            page.tapCreateWithExhaustedPool()
            expect(transport.count == 2, "\(path) releases abandoned allocation ownership")
            oldResponse?(.success(valid))
            page.tapCreateWithExhaustedPool()
            expect(transport.count == 2 && SiteData.site.updates == 0, "old response cannot release or apply over new request")
            transport.complete(.success(valid))
            expect(page.creationAttempts == 1, "new allocation resumes the same draft after \(path)")
        }
        page = fixture(); page.allocationAvailable = false; page.tapCreateWithExhaustedPool()
        transport.complete(.success(valid))
        expect(transport.count == 1 && page.creationAttempts == 0, "valid exhausted allocation does not recursively request or create")
        // A valid interval can contain only reserved numbers. The next user attempt must not be locked.
        page.tapCreateWithExhaustedPool()
        expect(transport.count == 2, "valid response followed by exhausted allocation permits a later retry")
        if failures > 0 { exit(1) }
    }
}
