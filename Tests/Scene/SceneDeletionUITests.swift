import Foundation

// Only UI and SceneServer are substitutes. The four controller methods below
// are injected unchanged from production by check_scene_deletion_ui.py.
extension String { var localizedString: String { self } }
func SCRXFrom(_ value: Int) -> Int { value }
func FONTS(_ value: Int) -> Int { value }
let isIPad = false, iPadPreferredContentSize = 0
let scenesRefreshNotificationName = "scenes", sceneDataUpdateNotificationName = "scene"

final class Scene {
    struct Configuration { var isDeleting = false }
    struct Info { var configuration: Configuration? = Configuration() }
    var info = Info()
}
enum SceneServer {
    enum Failure: Error { case persistence }
    static var requests = 0, completions = 0, legacyDeletes = 0
    static var requestFails = false, requestCompletes = false
    static var completionFails = false, completionSucceeds = true
    static func requestDeletion(scene: Scene) throws -> Bool {
        requests += 1
        if requestFails { throw Failure.persistence }
        scene.info.configuration?.isDeleting = true
        return requestCompletes
    }
    static func completePreparedDeletion(scene: Scene) throws -> Bool {
        completions += 1
        if completionFails { throw Failure.persistence }
        return completionSucceeds
    }
    static func deleteScene(scene: Scene, success: ((Scene) -> Void)?, failed: ((Scene) -> Void)?) {
        legacyDeletes += 1
    }
    static func reset() {
        requests = 0; completions = 0; legacyDeletes = 0
        requestFails = false; requestCompletes = false
        completionFails = false; completionSucceeds = true
    }
}
enum SceneDeletionCascade {
    static func confirmationMessage(scene: Scene) -> String { "scene_delete_cascade_message" }
}
final class MeshLibManager { static let manager = MeshLibManager(); var isMeshNetworkConnected = true }
enum XWHUDManager {
    static var errors: [String] = [], tips: [String] = [], successes: [String] = []
    static func showErrorTipHUD(_ value: String) { errors.append(value) }
    static func showTipHUD(_ value: String, isLineFeed: Bool) { tips.append(value) }
    static func showSuccessTipHUD(_ value: String) { successes.append(value) }
}
final class SRAlertAction {
    enum Style { case destructive, cancel }
    let action: ((SRAlertAction) -> Void)?
    init(title: String, style: Style, actionHandler: ((SRAlertAction) -> Void)? = nil) { action = actionHandler }
    static var cancelAction: SRAlertAction { .init(title: "Cancel", style: .cancel) }
    func invoke() { action?(self) }
}
final class SRAlertView {
    static var shown: [SRAlertView] = []
    let message: String, actions: [SRAlertAction]
    init(title: String, message: String, contentPadding: Int = 0, messageFont: Int = 0, actions: [SRAlertAction]) {
        self.message = message; self.actions = actions
    }
    func show() { Self.shown.append(self) }
}
// A future delayed navigation must be observed by the failure assertions too.
extension Double { static func now() -> Double { 0 } }
enum DispatchQueue {
    struct Queue {
        func asyncAfter(deadline: Double, execute action: @escaping () -> Void) { DispatchQueue.pending.append(action) }
        func async(execute action: @escaping () -> Void) { DispatchQueue.pending.append(action) }
    }
    static let main = Queue()
    static var pending: [() -> Void] = []
    static func drain() { let work = pending; pending = []; work.forEach { $0() } }
}
final class SyncDevicesViewController {
    enum Kind { case scene(Scene) }
    var syncSuccessCallback: ((Kind) -> Void)?, backActionCallback: (([Int]) -> Void)?
    var preferredContentSize = 0
    let type: Kind
    init(type: Kind) { self.type = type }
    func succeed() { syncSuccessCallback?(type) }
}
final class NavigationViewController {
    var pushed: [SyncDevicesViewController] = []
    var rootViewController: SyncDevicesViewController?
    var pops = 0
    init(rootViewController: SyncDevicesViewController? = nil) { self.rootViewController = rootViewController }
    func pushViewController(_ page: SyncDevicesViewController, animated: Bool) { pushed.append(page) }
    func popViewController(animated: Bool) { pops += 1 }
}
protocol DeletionScreen: AnyObject {
    var scene: Scene { get }
    var pages: [SyncDevicesViewController] { get }
    var exits: Int { get }
    var updates: Int { get }
    func trigger()
}
final class SceneViewController: DeletionScreen {
    let scene = Scene()
    var navigationController: NavigationViewController? = NavigationViewController()
    var exits = 0, updates = 0
    var pages: [SyncDevicesViewController] { navigationController!.pushed }
    func close() { exits += 1 }
    func updateDetailStatus() { updates += 1 }
    func trigger() { deleteScene() }
    // PRODUCTION_DETAIL_METHODS
}
final class ScenesViewController: DeletionScreen {
    let scene = Scene()
    var pages: [SyncDevicesViewController] = []
    var exits = 0, updates = 0
    func updateUI() { updates += 1 }
    func dismiss(animated: Bool) { exits += 1 }
    func present(_ page: NavigationViewController, animated: Bool) { pages.append(page.rootViewController!) }
    func trigger() { deleteScene(scene: scene) }
    // PRODUCTION_LIST_METHODS
}

@main enum SceneDeletionUITests {
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func reset() {
        SceneServer.reset(); SRAlertView.shown = []; DispatchQueue.pending = []
        XWHUDManager.errors = []; XWHUDManager.tips = []; XWHUDManager.successes = []
        MeshLibManager.manager.isMeshNetworkConnected = true
    }
    static func confirm() { SRAlertView.shown.last!.actions[1].invoke() }
    static func exercise(_ name: String, make: () -> any DeletionScreen) {
        reset()
        let cancelled = make(); cancelled.trigger()
        check(SRAlertView.shown.count == 1 && SceneServer.requests == 0, "\(name): confirmation must precede persistence")
        check(SRAlertView.shown[0].message == "scene_delete_cascade_message", "\(name): cascade confirmation")
        SRAlertView.shown[0].actions[0].invoke(); DispatchQueue.drain()
        check(SceneServer.requests == 0 && cancelled.pages.isEmpty && cancelled.scene.info.configuration?.isDeleting == false,
              "\(name): cancel must not persist or navigate")

        reset()
        let online = make(); online.trigger(); confirm(); DispatchQueue.drain()
        check(SceneServer.requests == 1 && online.pages.count == 1 && SRAlertView.shown.count == 1,
              "\(name): one confirmation must submit once and open one Sync page")
        check(online.scene.info.configuration?.isDeleting == true, "\(name): submitted deletion remains durable")
        online.pages[0].succeed(); DispatchQueue.drain()
        check(SceneServer.completions == 1 && SceneServer.requests == 1 && SceneServer.legacyDeletes == 0,
              "\(name): Sync completion only finalizes prepared deletion")
        check(online.pages.count == 1 && SRAlertView.shown.count == 1 && online.exits == 1 && XWHUDManager.errors.isEmpty,
              "\(name): completion must not reopen confirmation or Sync")

        reset(); MeshLibManager.manager.isMeshNetworkConnected = false
        let offline = make(); offline.trigger(); confirm(); DispatchQueue.drain()
        check(SceneServer.requests == 1 && offline.scene.info.configuration?.isDeleting == true && offline.pages.isEmpty,
              "\(name): offline saves pending deletion without Sync navigation")
        check(XWHUDManager.tips == ["scene_deletion_pending"] && offline.updates == 1 && XWHUDManager.errors.isEmpty,
              "\(name): offline shows pending state, not delete failure")
        MeshLibManager.manager.isMeshNetworkConnected = true
        offline.trigger(); DispatchQueue.drain()
        check(SRAlertView.shown.count == 1 && SceneServer.requests == 2 && offline.pages.count == 1,
              "\(name): pending retry reuses intent without another confirmation")

        reset(); SceneServer.requestFails = true
        let failed = make(); failed.trigger(); confirm(); DispatchQueue.drain()
        check(SceneServer.requests == 1 && XWHUDManager.errors == ["scene_delete_failed"] && failed.pages.isEmpty,
              "\(name): admission failure must never schedule delayed Sync navigation")
        check(failed.scene.info.configuration?.isDeleting == false && SceneServer.completions == 0 && SRAlertView.shown.count == 1,
              "\(name): failed admission must not pretend deletion was saved")

        for fails in [false, true] {
            reset()
            let pending = make(); pending.trigger(); confirm()
            SceneServer.completionSucceeds = false; SceneServer.completionFails = fails
            pending.pages[0].succeed(); DispatchQueue.drain()
            check(SceneServer.completions == 1 && SceneServer.requests == 1 && SceneServer.legacyDeletes == 0
                && pending.pages.count == 1 && pending.exits == 0 && SRAlertView.shown.count == 1,
                  "\(name): incomplete/failed finalization must remain retryable without restarting deletion")
            check(fails ? XWHUDManager.errors == ["scene_delete_failed"] : XWHUDManager.tips == ["scene_deletion_pending"],
                  "\(name): finalization reports actual pending/failure state")
        }
        reset(); SceneServer.requestCompletes = true
        let immediate = make(); immediate.trigger(); confirm(); DispatchQueue.drain()
        check(SceneServer.requests == 1 && immediate.pages.isEmpty && XWHUDManager.successes == ["done!"],
              "\(name): locally completed deletion needs no empty Sync page")
        print("PASS \(name): cancel, one confirmation/Sync, offline durable intent, failure, completion and pending retry")
    }
    static func main() {
        exercise("Scene detail", make: { SceneViewController() })
        exercise("Scene list", make: { ScenesViewController() })
    }
}
