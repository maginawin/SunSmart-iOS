import Foundation
typealias SceneNumber = UInt16

// Execute actual controller methods; UIKit, radio, cleanup I/O and Scene store
// are deterministic boundaries. Their production logic has separate suites.
extension String { var localizedString: String { self } }
enum NetworkApiError: Error { case configurationUnavailable, noSpacePermission; var localizedDescription: String { String(describing: self) } }
final class Node { var isKeybindComplete = true; func getNodeSyncProximityLighting() -> Int? { 1 } }
final class Group { var nodes: [Node] = [] }
struct Scene { var number: UInt16 = 1; var needSync = true }
enum SyncType {
    case gatewayRecovery, gatewayServerRecovery
    case devices([Node]), group(Group, [Node]? = nil, [Node]? = nil), scene(Scene), profile, schedule
}
enum SyncState { case inSync, syncFailure, syncSuccess }
enum ModelState { case none, failed, successful }
class SyncCellModel { var state = ModelState.failed; var isSelected = true }
final class SyncDevicesModel: SyncCellModel {}
final class SyncDevicesGroupModel: SyncCellModel { var deviceModels: [SyncDevicesModel] = [] }
struct Section { var devices: [SyncDevicesModel] = []; var groups: [SyncDevicesGroupModel] = []; var allModels: [SyncCellModel] { devices + groups } }
struct UIEdgeInsets { init(top: Double, left: Double, bottom: Double, right: Double) {} }
struct Frame: Equatable { static let zero = Frame() }
class View { var isHidden = false; var height = 30.0; var frame = Frame.zero; func layoutIfNeeded() {} }
final class Button: View { var isSelected = false, isEnabled = true }
final class Label: View { var text: String? }
final class Table: View { var contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 0); func reloadData() {} }
final class UIBarButtonItem { var title: String?, isEnabled = true; func withoutSharedBackground() -> Self { self } }
final class NavigationItem { var rightBarButtonItem: UIBarButtonItem? = UIBarButtonItem() }
struct UIImage { init?(named: String) {} }
enum XWHUDManager {
    static var messages: [String] = [], visible = false
    static func showCustomHUD(withMessage: String?, view: View) { visible = true }
    static func hideInView(with view: View) { visible = false }
    static func showErrorTipHUD(_ message: String) { messages.append(message) }
}
enum SpaceSyncAccess {
    static var failure: NetworkApiError?, scopeCurrent = true, recovery = 1
    static func error(checkingConfiguration: Bool = true) -> NetworkApiError? { failure }
    static func captureRecovery() -> () -> Bool { let captured = recovery; return { captured == recovery } }
}
enum SpaceSyncCleanupCoordinator {
    static var failure: NetworkApiError?, hold = false, calls = 0
    static var pending: CheckedContinuation<NetworkApiError?, Never>?
    static func prepareForDeviceSync() async -> NetworkApiError? {
        calls += 1
        if hold { return await withCheckedContinuation { pending = $0 } }
        return failure
    }
    static func release() { let callback = pending; pending = nil; callback?.resume(returning: failure) }
}
enum SceneRestoreConfirmation {
    enum Result { case ready, cancelled; case failed(Error) }
    static var result = Result.ready, hold = false
    static var pending: (() -> Void)?
    static func prepareIfNeeded(nodes: [Node]?, sceneNumber: UInt16?, isCurrent: @escaping () -> Bool,
                                completion: @escaping (Result) -> Void) {
        let callback = { if isCurrent() { completion(result) } }
        if hold { pending = callback } else { callback() }
    }
}
struct SceneConfigurationStore {
    struct DeletionRetryFailure: Error {}
    static var failure: Error?, calls = 0
    func prepareDeletionRetries() throws { Self.calls += 1; if let error = Self.failure { throw error } }
}
enum HDBDeviceSyncContext { static func resolve(node: Node) throws -> Int { throw NetworkApiError.configurationUnavailable } }
enum HDBDeviceSyncService { static func prepareIntents(nodes: [Node]) {} }
enum SpaceSyncTaskScope { static func capture() -> () -> Bool { { true } } }
final class Environment { var configurationIsCurrent: () -> Bool = { true } }
final class Session { var type = SyncType.profile; let environment = Environment(); var stops = 0; func stop() { stops += 1 } }
final class Display { func invalidateRun() {} }
struct Plan { var sections = [Section(devices: [SyncDevicesModel()])]; var initialState: SyncState }
struct SyncTaskPlanBuilder {
    static var calls = 0
    let initialState: SyncState
    init(type: SyncType, initialState: SyncState, profileSensorProtectionContext: Int?, groupProfileSyncContext: Int?,
         supplementaryProximityLightingSyncDatas: [(node: Node, syncData: Int)], imageExists: (String) -> Bool) {
        self.initialState = initialState
    }
    func build() -> Plan { Self.calls += 1; return .init(initialState: initialState) }
}
final class GatewaySyncContext {
    var failure: String?, current = true
    func prepare(for type: SyncType) -> String? { failure }
    func capturePlan(for type: SyncType) -> () -> Bool { { self.current } }
}
@MainActor final class Page {
    var gatewayContext: GatewaySyncContext?

    var hasLeftSyncPage = false, isPreparingTaskPlan = false, needsTaskPreparation = true
    var preparationID = UUID(), preparationTask: Task<Void, Never>?
    let preparationScopeIsCurrent = { SpaceSyncAccess.scopeCurrent }
    var syncState = SyncState.inSync, type = SyncType.devices([Node()])
    let view = View(), tableView = Table(), bottomView = View(), backBtn = Button(), selectAllBtn = Button(), progressLabel = Label()
    let navigationItem = NavigationItem(), executionSession = Session(), syncDisplayContext = Display()
    var sections: [Section] = [], hdbAwaitingInitialization: [Node] = []
    var profileSensorProtectionContext: Int?, groupProfileSyncContext: Int?
    var supplementaryProximityLightingSyncDatas: [(node: Node, syncData: Int)] = []
    var installs = 0, starts = 0, rowRetries = 0
    func currentNode(_ node: Node) -> Node? { node }
    func currentSyncType() -> SyncType { type }
    // The actual installation method is independently exercised by
    // check_sync_run_lifecycle.py, including closed-page and STOP boundaries.
    func installTaskPlan(_ result: Plan) {
        installs += 1; sections = result.sections; isPreparingTaskPlan = false; needsTaskPreparation = false
        syncState = result.initialState; XWHUDManager.hideInView(with: view)
        if syncState == .inSync { startSync() }; updateSyncStateUI()
    }
    func selectedFailedDevicesForResync() -> [SyncDevicesModel] { sections.flatMap(\.devices).filter { $0.state == .failed && $0.isSelected } }
    func containsBatteryPowerSwitchConfiguration(_ model: SyncDevicesModel) -> Bool { false }
    func startBatteryPowerSwitchConfigurationResyncAfterActivation() { fatalError("unrelated path") }
    func prepareDeviceForResync(_ model: SyncDevicesModel) { rowRetries += 1 }
    func startSync() { starts += 1 }
    // PRODUCTION_METHODS
}

@main struct SyncPreparationTests {
    @MainActor static func reset() {
        SpaceSyncAccess.failure = nil; SpaceSyncAccess.scopeCurrent = true; SpaceSyncAccess.recovery = 1
        SpaceSyncCleanupCoordinator.failure = nil; SpaceSyncCleanupCoordinator.hold = false; SpaceSyncCleanupCoordinator.calls = 0
        SceneRestoreConfirmation.result = .ready; SceneRestoreConfirmation.hold = false; SceneRestoreConfirmation.pending = nil
        SceneConfigurationStore.failure = nil; SceneConfigurationStore.calls = 0
        SyncTaskPlanBuilder.calls = 0; XWHUDManager.messages = []; XWHUDManager.visible = false
    }
    @MainActor static func waitForCleanup() async {
        for _ in 0..<1000 { if SpaceSyncCleanupCoordinator.pending != nil { return }; await Task.yield() }
        fatalError("preparation did not reach cleanup")
    }
    @MainActor static func main() async {
        for type in [SyncType.devices([Node()]), .group(Group()), .scene(Scene()), .profile, .schedule] {
            reset(); let page = Page(); page.type = type
            page.rebuildTaskPlan(resume: true); await page.preparationTask?.value
            precondition(page.installs == 1 && page.starts == 1 && XWHUDManager.messages.isEmpty)
        }
        for type in [SyncType.gatewayRecovery, .gatewayServerRecovery, .devices([Node()])] {
            reset(); let page = Page(); page.type = type; page.gatewayContext = GatewaySyncContext()
            SpaceSyncAccess.scopeCurrent = false; SpaceSyncAccess.failure = .configurationUnavailable
            SceneRestoreConfirmation.result = .failed(NetworkApiError.configurationUnavailable)
            page.rebuildTaskPlan(resume: false)
            precondition(page.installs == 1 && page.starts == 0 && XWHUDManager.messages.isEmpty)
            precondition(SpaceSyncCleanupCoordinator.calls == 0 && SceneConfigurationStore.calls == 0)
            page.rightItemAction(); precondition(page.starts == 1)
            let denied = Page(); denied.gatewayContext = GatewaySyncContext()
            denied.gatewayContext!.failure = "no_permission"
            denied.rebuildTaskPlan(resume: true)
            precondition(denied.installs == 0 && denied.needsTaskPreparation)
            denied.gatewayContext!.failure = nil; denied.rightItemAction()
            precondition(denied.installs == 1 && denied.starts == 1)
        }
        reset(); let permission = Page(); SpaceSyncAccess.failure = .noSpacePermission
        permission.rebuildTaskPlan(resume: true)
        precondition(permission.installs == 0 && SpaceSyncCleanupCoordinator.calls == 0 && SceneConfigurationStore.calls == 0)
        precondition(XWHUDManager.messages == ["noSpacePermission"] && !permission.backBtn.isHidden && permission.navigationItem.rightBarButtonItem!.isEnabled)
        SpaceSyncAccess.failure = nil; permission.rightItemAction(); await permission.preparationTask?.value
        precondition(permission.installs == 1 && !permission.needsTaskPreparation)
        permission.syncState = .syncFailure; permission.rightItemAction()
        precondition(permission.rowRetries == 1 && permission.starts == 2 && SpaceSyncCleanupCoordinator.calls == 1,
                     "installed ordinary failures must keep existing row retry")

        reset(); let cancelled = Page(); SceneRestoreConfirmation.result = .cancelled
        cancelled.rebuildTaskPlan(resume: true)
        precondition(cancelled.needsTaskPreparation && !cancelled.isPreparingTaskPlan && cancelled.installs == 0)
        precondition(XWHUDManager.messages.isEmpty && SpaceSyncCleanupCoordinator.calls == 0 && SceneConfigurationStore.calls == 0)
        SceneRestoreConfirmation.result = .ready; cancelled.rightItemAction(); await cancelled.preparationTask?.value
        precondition(cancelled.installs == 1)
        reset(); let restoreFailed = Page(); SceneRestoreConfirmation.result = .failed(NetworkApiError.configurationUnavailable)
        restoreFailed.rebuildTaskPlan(resume: true)
        precondition(XWHUDManager.messages == ["scene_restore_pending"] && SceneConfigurationStore.calls == 0)

        for deleting in [false, true] {
            reset(); let page = Page()
            SceneConfigurationStore.failure = deleting ? SceneConfigurationStore.DeletionRetryFailure() : NetworkApiError.configurationUnavailable
            page.rebuildTaskPlan(resume: true); await page.preparationTask?.value
            precondition(XWHUDManager.messages == [deleting ? "scene_delete_failed" : "configurationUnavailable"])
            precondition(page.installs == 0 && page.needsTaskPreparation && !XWHUDManager.visible)
            SceneConfigurationStore.failure = nil; page.rightItemAction(); await page.preparationTask?.value
            precondition(page.installs == 1)
        }
        reset(); let cleanupFailed = Page(); SpaceSyncCleanupCoordinator.failure = .configurationUnavailable
        cleanupFailed.rebuildTaskPlan(resume: true); await cleanupFailed.preparationTask?.value
        precondition(SceneConfigurationStore.calls == 0 && XWHUDManager.messages == ["configurationUnavailable"])

        for mode in ["stop", "leave", "space", "recovery"] {
            reset(); let page = Page(); SpaceSyncCleanupCoordinator.hold = true
            page.rebuildTaskPlan(resume: true); let task = page.preparationTask
            await waitForCleanup()
            switch mode {
            case "stop": page.rightItemAction()
            case "leave": page.hasLeftSyncPage = true; page.cancelTaskPreparation()
            case "space": SpaceSyncAccess.scopeCurrent = false
            default: SpaceSyncAccess.recovery += 1
            }
            SpaceSyncCleanupCoordinator.release(); await task?.value
            precondition(page.installs == 0 && SceneConfigurationStore.calls == 0)
            precondition(XWHUDManager.messages == ((mode == "stop" || mode == "leave") ? [] : ["configurationUnavailable"]))
        }
        reset(); let oldAlert = Page(); SceneRestoreConfirmation.hold = true
        oldAlert.rebuildTaskPlan(resume: true); oldAlert.rightItemAction(); SceneRestoreConfirmation.pending?()
        precondition(oldAlert.installs == 0 && SpaceSyncCleanupCoordinator.calls == 0 && XWHUDManager.messages.isEmpty)
        reset(); let stoppedPlan = Page()
        stoppedPlan.rebuildTaskPlan(resume: false); await stoppedPlan.preparationTask?.value
        precondition(stoppedPlan.installs == 1 && stoppedPlan.starts == 0 && stoppedPlan.syncState == .syncFailure)
        print("PASS production sync page: generic types, one error, cancelled Restore, preparation retry, installed-row retry, STOP/leave/Space/generation late results")
    }
}
