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
    private var preparingScene = false
    private var requestedSceneAddresses = false
    var creationAttempts = 0
    func addSceneHandle() { creationAttempts += 1 }
    // Simulate the exhausted-pool branch on every user tap, without allocating.
    func tapCreateWithExhaustedPool() { requestSceneAddresses() }
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
        if failures > 0 { exit(1) }
    }
}
