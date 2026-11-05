import Foundation
// UI, account, network and entry service are boundaries; injected methods are
// the actual controller's permission gate and task lifecycle.
enum UserData { static var currentUserId = "a", currentServerRegion = "r" }
let spacePermissionChangedNotificaitonName = "permissionChanged"
enum SpaceState { case normal, waitDeleted }
enum Permission { case owner, editor, visitor }
class SpaceData {
    var state = SpaceState.normal
    var permission = Permission.owner, disableEditorPermission = false, requiresPasswordVerification = false
    var syncCloudError: TestError?
    let id = "space", siteId = "site", meshUUID = "mesh", meshNetworkId = "network"
    func save() -> Bool { true }
    func saveCloudSyncOutcome(error: TestError?) -> Bool { syncCloudError = error; return true }
}
class SiteData {
    static var saved = SiteData()
    var meshUUID = "mesh", uploadCloud = false
    static func load(siteId: String) -> SiteData? { saved }
}
enum TestError: Error { case failed; var localizedDescription: String { "failure" } }
class View { var isUserInteractionEnabled = true }
class Item { var isEnabled = true }
class NavigationItem { var rightBarButtonItem: Item? = Item() }
enum NetworkRequest { static var shared = NetworkRequestValue() }
struct NetworkRequestValue { var networkable = true }
enum XWHUDManager { static var errors = 0; static func showErrorTipHUD(_ message: String) { errors += 1 } }
class CloudSynchronizationManager {
    static let shared = CloudSynchronizationManager()
    var calls = 0
    var held: CheckedContinuation<Result<Void, TestError>, Never>?
    var hold = false
    @MainActor func reconcileSpaceEntry(_ space: SpaceData, loadedConfiguration: [String: Any]?) async -> Result<Void, TestError> {
        calls += 1
        if hold { return await withCheckedContinuation { held = $0 } }
        return .success(())
    }
}
@MainActor class EntryController {
    var site = SiteData()
    let space = SpaceData()
    var hasStoppedPresenceTracking = false, hasHandledPermissionLoss = false
    var hasPendingTransferPermissionAlert = false
    var transferPermissionAlert: View?
    var loadNetworkData = true
    var viewIfLoaded: View? = View()
    var navigationItem = NavigationItem()
    var reloads = 0, repairs = 0
    func handleSpacePermissionLoss() { hasHandledPermissionLoss = true }
    func reloadData() { reloads += 1 }
    func updateSyncState() {}
    func reconcileLegacyProximityLightingTopology() { repairs += 1 }
    func configurationFlowGuidance() {}
    // PRODUCTION
}
@main struct SpaceEntrySyncTests {
    @MainActor static func ticks() async { for _ in 0..<30 { await Task.yield() } }
    @MainActor static func main() async {
        let manager = CloudSynchronizationManager.shared
        for role in [Permission.owner, .editor, .visitor] {
            let vc = EntryController(); vc.space.permission = role
            let before = manager.calls
            vc.reconcileEntryConfigurationIfNeeded(); await ticks()
            precondition(manager.calls == before, "role/init alone never grants editing")
            vc.resolveEntryPermission(canEdit: role != .visitor); await ticks()
            precondition(manager.calls == before + (role == .visitor ? 0 : 1))
            vc.reconcileEntryConfigurationIfNeeded(); vc.resolveEntryPermission(canEdit: true); await ticks()
            precondition(manager.calls == before + (role == .visitor ? 0 : 1), "returns/duplicate callbacks never re-enter")
        }
        for mode in ["readonly", "password", "conflict", "offline", "loading"] {
            let vc = EntryController(); let before = manager.calls
            if mode == "password" { vc.space.requiresPasswordVerification = true }
            if mode == "conflict" { vc.hasPendingTransferPermissionAlert = true }
            if mode == "loading" { vc.loadNetworkData = false }
            NetworkRequest.shared.networkable = mode != "offline"
            vc.resolveEntryPermission(canEdit: mode != "readonly"); await ticks()
            precondition(manager.calls == before, mode)
            if mode == "loading" { vc.loadNetworkData = true; vc.reconcileEntryConfigurationIfNeeded(); await ticks(); precondition(manager.calls == before + 1) }
            if mode == "offline" { NetworkRequest.shared.networkable = true; vc.reconcileEntryConfigurationIfNeeded(); await ticks(); precondition(manager.calls == before) }
        }
        manager.hold = true
        for fails in [false, true] {
        for mode in ["visitor", "password", "disabled", "revoked"] {
            let errorsBefore = XWHUDManager.errors
            let vc = EntryController(); vc.resolveEntryPermission(canEdit: true); await ticks()
            if mode == "visitor" { vc.space.permission = .visitor }
            if mode == "password" { vc.space.requiresPasswordVerification = true }
            if mode == "disabled" { vc.space.disableEditorPermission = true }
            if mode == "revoked" { vc.space.state = .waitDeleted }
            SiteData.saved = SiteData(); SiteData.saved.uploadCloud = true
            manager.held?.resume(returning: fails ? .failure(.failed) : .success(())); manager.held = nil; await ticks()
            precondition(vc.entryReconciliationTask == nil && vc.entryReconciliationFinished, "current permission failure must finish entry")
            precondition(vc.viewIfLoaded?.isUserInteractionEnabled == true && vc.navigationItem.rightBarButtonItem?.isEnabled == true)
            precondition(vc.repairs == 0 && vc.reloads == 1 && (vc.space.syncCloudError != nil) == fails)
            precondition(XWHUDManager.errors == errorsBefore + (fails ? 1 : 0))
            if mode == "revoked" { precondition(vc.hasHandledPermissionLoss) }
            precondition(vc.site.uploadCloud, "refresh active Site even if the later Space step fails")
        }
        }
        for mode in ["exit", "account", "region", "permission"] {
            let vc = EntryController(); vc.resolveEntryPermission(canEdit: true); await ticks()
            precondition(manager.held != nil)
            if mode == "exit" { vc.hasStoppedPresenceTracking = true; vc.cancelEntryReconciliation() }
            if mode == "account" { UserData.currentUserId = "b" }
            if mode == "region" { UserData.currentServerRegion = "other" }
            if mode == "permission" { vc.space.disableEditorPermission = true; vc.cancelEntryReconciliation() }
            manager.held?.resume(returning: .success(())); manager.held = nil; await ticks()
            precondition(vc.repairs == 0 && vc.reloads == 0, "late entry cannot resume editing")
            UserData.currentUserId = "a"; UserData.currentServerRegion = "r"
        }
        print("PASS: production entry permission gate/session: owner/editor once, read-only/password/conflict/offline, loading, duplicate callback, authority changes finish read-only, active Site reload, exit/account/region/permission late completion")
    }
}
