import Foundation

// Production controller methods are injected by check_scene_creation_flow.py.
// HTTP, UIKit, HUD timing and persistence are controlled boundaries here;
// the real storage transaction is covered by SceneSaveFlowTests.
// SHARED_BOUNDARIES

struct SceneDraft { let scope: SceneScope; let revision = UUID() }
final class Scene {}
struct SceneConfigurationStore {
    enum Failure: Error { case noNumber, persistence, staleDraft }
    enum Result { case ready(Scene), projectionPending }
    static var allocated = true
    static var projectionFails = false
    static var failWrite = false
    static var rows: [UUID: Scene] = [:]
    static func validateAccess(_ scope: SceneScope) throws {
        guard scope.meshUUID == MeshNetworkManager.instance.meshNetwork?.uuid.uuidString,
              scope.networkID == MeshNetworkManager.instance.currentNetworkKey.networkId else { throw Failure.staleDraft }
    }
    func createEmpty(draft: SceneDraft) throws -> Result {
        try Self.validateAccess(draft.scope)
        if Self.failWrite { throw Failure.persistence }
        if Self.rows[draft.revision] == nil {
            guard Self.allocated else { throw Failure.noNumber }
            Self.rows[draft.revision] = Scene()
        }
        return Self.projectionFails ? .projectionPending : .ready(Self.rows[draft.revision]!)
    }
}
enum DispatchQueue {
    struct Queue {
        func async(_ action: () -> Void) { action() }
        func asyncAfter(deadline: DispatchTime, execute: @escaping () -> Void) { DispatchQueue.delayed.append(execute) }
    }
    static let main = Queue()
    static var delayed: [() -> Void] = []
    static func finishDelay() { let work = delayed; delayed = []; work.forEach { $0() } }
}
enum XWHUDManager {
    static var successes = 0
    static func showSuccessTipHUD(_ message: String, timer: Double) { successes += 1 }
    static func showCustomHUD(withMessage: String, isWindow: Bool) {}
    static func showTipHUD(_ message: String, isLineFeed: Bool) {}
    static func hide() {}
}
enum TimedSchedulerBindings { static func showFailure(_ error: Error) {} }

final class SceneCreationHarness {
    enum CreateMode { case custom, template }
    struct Space { let siteId = "site" }
    final class View { var window: NSObject? = NSObject(); func endEditing(_ force: Bool) {} }
    final class Control {
        var isUserInteractionEnabled = true
        var isEnabled = true
        var isScrollEnabled = true
    }
    final class CustomView {
        var isUserInteractionEnabled = true
        let nameField = Control(), collectionView = Control()
    }
    final class Navigation { weak var topViewController: SceneCreationHarness? }
    var createMode = CreateMode.custom
    let space = Space()
    let view = View()
    var viewIfLoaded: View? { view }
    var navigationController: Navigation? = Navigation()
    var customView: CustomView? = CustomView()
    var menuView: Control? = Control(), scrollView: Control? = Control()
    var scene: Scene?
    var creationDraft: SceneDraft?
    var creationRequest: UUID?
    var creationProjectionPending = false
    var createSceneCallback: ((Scene) -> Void)?
    var navigations = 0
    init() { navigationController?.topViewController = self }
    func makeDraft() throws -> SceneDraft? {
        .init(scope: .init(meshUUID: MeshNetworkManager.instance.meshNetwork!.uuid.uuidString, networkID: "space-A"))
    }
    func openDraftEditor(preview: Bool) { fatalError("custom CREATE entered template editor") }
    func openCreatedScene(_ scene: Scene) { navigations += 1 }
    func publishCreatedSceneChange() {}
    // PRODUCTION_CREATION
    func tapCreate() { addSceneHandle() }
    func suspend() { cancelCreationRequest() }
}

@main enum SceneCreationFlowTests {
    static func reset() -> SceneCreationHarness {
        MeshNetworkManager.instance.meshNetwork = Network()
        MeshNetworkManager.instance.currentNetworkKey = .init()
        SiteData.site.updates = 0
        NetworkRequest.shared.count = 0; NetworkRequest.shared.pending = nil
        SceneConfigurationStore.rows = [:]; SceneConfigurationStore.allocated = true
        SceneConfigurationStore.projectionFails = false; SceneConfigurationStore.failWrite = false
        DispatchQueue.delayed = []; XWHUDManager.successes = 0
        return SceneCreationHarness()
    }
    static func main() {
        let transport = NetworkRequest.shared
        let valid: [String: Any] = ["data": ["provisioner": [
            "allocatedUnicastRange": [["lowAddress": "0001", "highAddress": "0010"]],
            "allocatedGroupRange": [["lowAddress": "C000", "highAddress": "C00F"]],
            "allocatedSceneRange": [["firstScene": "0011", "lastScene": "0020"]]
        ]]]
        var page = reset()
        page.tapCreate(); page.tapCreate()
        precondition(SceneConfigurationStore.rows.count == 1 && XWHUDManager.successes == 1 && page.navigations == 0,
                     "CREATE must persist once and show Done before navigation")
        DispatchQueue.finishDelay()
        precondition(page.navigations == 1)

        page = reset(); SceneConfigurationStore.failWrite = true
        page.tapCreate()
        precondition(page.scene == nil && XWHUDManager.successes == 0 && page.creationRequest == nil)
        SceneConfigurationStore.failWrite = false; page.tapCreate(); DispatchQueue.finishDelay()
        precondition(SceneConfigurationStore.rows.count == 1 && page.navigations == 1)

        page = reset(); SceneConfigurationStore.projectionFails = true
        page.tapCreate(); let revision = page.creationDraft!.revision
        precondition(page.navigations == 0 && XWHUDManager.successes == 0 && !page.customView!.nameField.isEnabled)
        SceneConfigurationStore.projectionFails = false; page.tapCreate(); DispatchQueue.finishDelay()
        precondition(SceneConfigurationStore.rows.count == 1 && SceneConfigurationStore.rows[revision] === page.scene)

        page = reset(); SceneConfigurationStore.allocated = false
        page.tapCreate(); page.tapCreate()
        precondition(transport.count == 1)
        SceneConfigurationStore.allocated = true; transport.complete(.success(valid)); DispatchQueue.finishDelay()
        precondition(page.navigations == 1 && SiteData.site.updates == 1)

        for invalid in [true, false] {
            page = reset(); SceneConfigurationStore.allocated = false; page.tapCreate()
            if invalid { transport.complete(.success(["data": [:]])) }
            else { transport.complete(.failure(.offline)) }
            precondition(page.scene == nil && SiteData.site.updates == 0 && page.creationRequest == nil)
            page.tapCreate(); precondition(transport.count == 2)
        }

        page = reset(); SceneConfigurationStore.allocated = false; page.tapCreate()
        let oldResponse = transport.pending
        page.suspend(); page.tapCreate()
        oldResponse?(.success(valid))
        precondition(SiteData.site.updates == 0 && page.creationRequest != nil)
        SceneConfigurationStore.allocated = true; transport.complete(.success(valid)); DispatchQueue.finishDelay()
        precondition(page.navigations == 1 && SceneConfigurationStore.rows.count == 1)

        page = reset(); SceneConfigurationStore.allocated = false; page.tapCreate()
        MeshNetworkManager.instance.currentNetworkKey.networkId = "other-space"
        transport.complete(.success(valid))
        precondition(SiteData.site.updates == 0 && SceneConfigurationStore.rows.isEmpty)

        page = reset(); SceneConfigurationStore.allocated = false; page.tapCreate()
        MeshNetworkManager.instance.meshNetwork!.savesSucceed = false
        transport.complete(.success(valid))
        precondition(page.creationRequest == nil && page.scene == nil && XWHUDManager.successes == 0,
                     "allocation persistence failure must not report a created scene")

        page = reset(); SceneConfigurationStore.allocated = false; page.tapCreate()
        transport.complete(.success(valid))
        precondition(transport.count == 1 && page.creationRequest == nil && page.scene == nil,
                     "still exhausted after allocation must stop and permit a later retry")

        page = reset(); page.tapCreate(); page.suspend(); DispatchQueue.finishDelay()
        precondition(page.navigations == 0 && SceneConfigurationStore.rows.count == 1,
                     "leaving during Done must retain the created scene without delayed navigation")
        precondition(!page.customView!.nameField.isEnabled && !page.menuView!.isUserInteractionEnabled,
                     "created metadata must stay fixed while waiting to reopen Settings")
        page.tapCreate(); precondition(page.navigations == 1 && SceneConfigurationStore.rows.count == 1)
        print("PASS creation: persist/Done/navigation order, double taps, failure/retry, allocation validation, stale replies, cancellation and projection identity")
    }
}
