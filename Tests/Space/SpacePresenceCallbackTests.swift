// Production methods are inserted by check_space_presence_callbacks.py.
// These boundaries model navigation, Window ownership, timers and queued HTTP responses;
// they do not validate UIKit animations, BLE delivery or server behavior.
import Foundation

extension String { var localizedString: String { self } }
let spacePermissionChangedNotificaitonName = "permissionChanged"
let SiteStateChangeNotificationName = "siteStateChanged"
let SitesDataRefreshNotifiacationName = "sitesRefresh"
let spacesRefreshChangeNotificationName = "spacesRefresh"
let deviceStateUpdateNotificationName = "deviceStateUpdated"
enum MeshNodeHeartbeatManager {
    static let nodePresenceDidChange = Notification.Name("sdkPresenceChanged")
}

class View { var isUserInteractionEnabled = true; var window: View? }
class UIViewController: NSObject {
    var navigationController: Navigation?
    var view = View()
    var viewIfLoaded: View? { view }
    var isMovingFromParent = false
    var presentingViewController: UIViewController?
    static func getVisibleVc() -> UIViewController? { nil }
    func dismiss(animated: Bool) {}
    func viewDidDisappear(_ animated: Bool) {}
}
final class SiteViewController: UIViewController {}
final class Navigation {
    var viewControllers: [UIViewController] = []
    let viewIfLoaded: View? = View()
    var pops = 0
    var onPop: (() -> Void)?
    func popToViewController(vcClass: AnyClass) { pops += 1; onPop?() }
}
final class SRAlertAction {
    enum Style { case normal, cancel }
    let closeAlert: Bool
    let actionHandler: ((SRAlertAction) -> Void)?
    init(title: String, style: Style = .normal, closeAlert: Bool = true,
         actionHandler: ((SRAlertAction) -> Void)? = nil) {
        self.closeAlert = closeAlert; self.actionHandler = actionHandler
    }
}
final class SRAlertView {
    static var current: SRAlertView?
    static var shown: [SRAlertView] = []
    var superview: View?
    let actions: [SRAlertAction]
    init(title: String, message: String, actions: [SRAlertAction]) { self.actions = actions }
    func show() {
        Self.current?.dismiss(animation: false)
        Self.current = self; superview = View(); Self.shown.append(self)
    }
    func dismiss(animation: Bool = true) {
        superview = nil
        if Self.current === self { Self.current = nil }
    }
    func tap(_ index: Int) {
        let action = actions[index]
        action.actionHandler?(action)
        if action.closeAlert { dismiss() }
    }
    static func getCurrentAlertView() -> SRAlertView? { current }
}

enum Permission: String {
    case owner, editor, visitor
    init?(permissionString: String) { self.init(rawValue: permissionString) }
    var dataString: String { rawValue }
}
enum SpaceState { case normal, waitDeleted }
enum MeshOperate { case edit, control }
final class SpaceData {
    var permission: Permission = .editor
    var state: SpaceState = .normal
    var disableEditorPermission = false
    var requiresPasswordVerification = false
    var uploadCloud = true
    var deviceCount = 0
    var saves = 0
    let siteId = "site", id = "space"
    var meshUUID = MeshNetworkManager.instance.meshNetwork!.uuid.uuidString
    var meshNetworkId = "network"
    var configurationProtected = false
    var deviceOperates: [MeshOperate] { configurationProtected || permission == .visitor || disableEditorPermission ? [.control] : [.edit, .control] }
    func save() { saves += 1 }
}
final class SiteData { var permission: Permission = .editor }
enum UserData { static let currentUserId = "current" }
struct JSON {
    let raw: Any
    init(_ raw: Any) { self.raw = raw }
    subscript(_ key: String) -> JSON { JSON((raw as? [String: Any])?[key] as Any) }
    var arrayObject: [Any]? { raw as? [Any] }
}
enum NetworkApiError: Error {
    case noSitePermission, noSpacePermission, userUnauthorized, incorrectPassword, spacePasswordOverdue, offline
}
enum API {
    case spaceActiveMembers(siteId: String, spaceId: String)
    case heartbeat(siteId: String, spaceId: String, permission: Permission)
}
final class NetworkRequest {
    static let shared = NetworkRequest()
    struct Request {
        let api: API
        let completion: (Result<[String: Any], NetworkApiError>) -> Void
    }
    var requests: [Request] = []
    func request(_ api: API, completion: @escaping (Result<[String: Any], NetworkApiError>) -> Void) {
        requests.append(Request(api: api, completion: completion))
    }
}
enum SpaceConfigurationSafety {
    static var errors = 0
    static func handleAuthorityError(_ error: NetworkApiError, space: SpaceData) { errors += 1 }
}
enum XWHUDManager { static func showErrorTipHUD(_ message: String) {} }

typealias Address = UInt16
extension Address { static let localClientGroupAddress: Address = 0xC000 }
final class Node { let primaryUnicastAddress: Address = 1 }
struct Provisioner { let node: Node? = Node() }
final class Network {
    let uuid = UUID(); let localProvisioner: Provisioner? = Provisioner()
    let node = Node()
    func node(withAddress address: Address) -> Node? { address == node.primaryUnicastAddress ? node : nil }
}
struct NetworkID { var hex = "network" }
struct NetworkKey { var networkId = NetworkID() }
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: Network? = Network()
    var currentNetworkKey = NetworkKey()
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
    weak var externalVendorMessageDelegate: SpaceViewController?
}
struct ExternalVendorMessage {
    enum Event { case ask, reply(permission: Permission) }
    enum Operation { case userPermission(Event) }
    let operation: Operation
    func unmarshal() -> Operation? { operation }
}
enum MeshAPI {
    static var sends = 0
    static func sendMessage(message: ExternalVendorMessage, address: Address) { sends += 1 }
}

final class Timer {
    var invalidated = false
    var onFire: (() -> Void)?
    func invalidate() { invalidated = true }
    func fire() { if !invalidated { onFire?() } }
}
enum LCWeakTimer {
    static func scheduledTimer(timeInterval: Double, aTarget: SpaceViewController, selector: String,
                               userInfo: Any?, repeats: Bool) -> Timer {
        let timer = Timer()
        timer.onFire = { [weak aTarget] in
            if selector == "heartbeatRequest" { aTarget?.heartbeatRequest() }
            else { aTarget?.userPermissionAskTimeout() }
        }
        return timer
    }
}
final class RunLoop {
    enum Mode { case common }
    static let current = RunLoop()
    func add(_ timer: Timer, forMode: Mode) {}
}
enum NodeSyncStatusRefresh { static func endSession(owner: AnyObject) {} }
final class Scheduler { func stop() {} }

final class SpaceViewController: UIViewController {
    let space: SpaceData
    let site = SiteData()
    var heartbeatTimer: Timer?
    var userAskTimer: Timer?
    var schedulerReadCoordinator: Scheduler?
    var guidance = 0
    var monitoringStops = 0
    init(space: SpaceData = SpaceData()) { self.space = space; super.init() }
    func configurationFlowGuidance() { if space.deviceOperates.contains(.edit) { guidance += 1 } }
    func stopEmergencyFireSceneMonitoring() { monitoringStops += 1 }
    func removeFromWindowSubviews() { SRAlertView.current?.dismiss() }
    var entryCloudEditingGranted = false
    var navigationItem = FixtureNavigationItem()
    var entryPermissionDecisions: [Bool] = []
    func resolveEntryPermission(canEdit: Bool) { entryPermissionDecisions.append(canEdit) }
    func cancelEntryReconciliation() {}
    func grantEntryEditingIfReady() {}
    // INSERT_PRODUCTION_MEMBERS
}

@main
struct SpacePresenceCallbackTests {
    static var scenarios = 0
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }
    static func reset() {
        SRAlertView.current?.dismiss(); SRAlertView.shown.removeAll()
        NetworkRequest.shared.requests.removeAll(); MeshAPI.sends = 0
        SpaceConfigurationSafety.errors = 0
        MeshLibManager.manager.externalVendorMessageDelegate = nil
        MeshNetworkManager.instance.currentNetworkKey = NetworkKey()
    }
    static func make(visible: Bool = true, permission: Permission = .editor) -> SpaceViewController {
        let vc = SpaceViewController()
        vc.space.permission = permission
        let nav = Navigation()
        nav.viewControllers = [vc]
        nav.viewIfLoaded?.window = visible ? View() : nil
        vc.navigationController = nav
        return vc
    }
    static func members(_ vc: SpaceViewController) -> (Result<[String: Any], NetworkApiError>) -> Void {
        vc.checkTheSpaceMembersRequest()
        return NetworkRequest.shared.requests.last!.completion
    }
    static func cloud(_ conflict: Bool) -> Result<[String: Any], NetworkApiError> {
        .success(["data": ["activeUsers": conflict ? [["role": "owner", "userId": "other"]] : []]])
    }
    static func mesh(_ vc: SpaceViewController) {
        vc.meshNetworkManager(.instance, didReceiveMessage: .init(operation: .userPermission(.reply(permission: .owner))),
                              sentFrom: 2, to: .localClientGroupAddress)
    }
    static func main() {
        for role in [Permission.owner, .editor] {
            reset()
            let vc = make(permission: role)
            vc.space.configurationProtected = true
            vc.checkTheSpaceMembersRequest()
            require(NetworkRequest.shared.requests.count == 1, "configuration protection must not block cloud identity check")
            vc.checkMeshMemberPermissions()
            require(MeshAPI.sends == 1, "configuration protection must not block Mesh identity check")
            scenarios += 1
        }
        for mode in ["password", "disabled", "visitor"] {
            reset()
            let vc = make(permission: mode == "visitor" ? .visitor : .editor)
            vc.space.configurationProtected = true
            vc.space.requiresPasswordVerification = mode == "password"
            vc.space.disableEditorPermission = mode == "disabled"
            vc.checkTheSpaceMembersRequest(); vc.checkMeshMemberPermissions()
            require(NetworkRequest.shared.requests.isEmpty && MeshAPI.sends == 0, "identity restrictions still block permission probes")
            require(vc.entryPermissionDecisions == [false], "restricted current entry finishes read-only")
            scenarios += 1
        }
        do {
            let vc = make()
            var updates = 0
            let observer = NotificationCenter.default.addObserver(forName: .init(deviceStateUpdateNotificationName),
                object: nil, queue: .main) { _ in updates += 1 }
            defer { NotificationCenter.default.removeObserver(observer) }
            let node = MeshNetworkManager.instance.meshNetwork!.node
            func report(_ node: Node) {
                NotificationCenter.default.post(name: MeshNodeHeartbeatManager.nodePresenceDidChange, object: node)
            }
            vc.startNodePresenceObservation(); vc.startNodePresenceObservation()
            report(node)
            require(updates == 1, "one Space bridge must update pages without a message delegate")
            report(Node())
            require(updates == 1, "detached same-address node must be ignored")
            vc.space.meshNetworkId = "other"
            report(node)
            require(updates == 1, "other subnet must be ignored")
            vc.space.meshNetworkId = "network"
            vc.stopSpacePresenceTracking(reason: .leavingSpaceFlow)
            vc.startNodePresenceObservation(); report(node)
            require(updates == 1 && vc.nodePresenceObservation == nil, "leaving Space removes the bridge and rejects late reports")
            scenarios += 1
        }
        // Both independent sources, before and after a Cancel. Keep the old VC alive on purpose.
        for cloudFirst in [true, false] {
            for cancelBeforeSecond in [true, false] {
                reset()
                let vc = make(), response = members(vc)
                vc.checkMeshMemberPermissions()
                if cloudFirst { response(cloud(true)) } else { mesh(vc) }
                require(SRAlertView.shown.count == 1, "first conflict must show")
                let first = SRAlertView.shown[0]
                vc.navigationController!.onPop = {
                    require(vc.hasStoppedPresenceTracking, "Cancel must invalidate before navigation")
                    response(cloud(true)); mesh(vc)
                }
                if cancelBeforeSecond { first.tap(0) }
                if cloudFirst { mesh(vc) } else { response(cloud(true)) }
                require(SRAlertView.shown.count == 1, "both conflict sources must share one prompt")
                if !cancelBeforeSecond { first.tap(0) }
                require(vc.navigationController!.pops == 1, "Cancel navigates exactly once")
                require(!vc.space.disableEditorPermission, "Cancel must not change Editor identity")
                require(SRAlertView.current == nil, "Cancel closes its prompt")
                let sends = MeshAPI.sends, requestCount = NetworkRequest.shared.requests.count
                vc.checkMeshMemberPermissions(); vc.startHeartbeatTimer(); vc.userPermissionAskTimeout()
                response(cloud(false)); response(.failure(.offline)); mesh(vc)
                require(MeshAPI.sends == sends && NetworkRequest.shared.requests.count == requestCount,
                        "late KVO, HTTP and timers must not restart presence")
                require(vc.guidance == 0 && SRAlertView.shown.count == 1, "late results must not guide or prompt")
                first.tap(0); first.tap(1)
                require(vc.navigationController!.pops == 1 && !vc.space.disableEditorPermission,
                        "old actions cannot act after Cancel")
                scenarios += 1
            }
        }

        reset()
        let confirmed = make(), confirmResponse = members(confirmed)
        confirmed.checkMeshMemberPermissions(); mesh(confirmed)
        SRAlertView.current!.tap(1)
        confirmResponse(cloud(true)); confirmed.showTransferPermissionAlert()
        require(confirmed.space.disableEditorPermission && !confirmed.hasStoppedPresenceTracking,
                "Confirm stays in the active read-only session")
        require(SRAlertView.shown.count == 1, "Confirm suppresses subsequent conflicts")
        confirmed.startHeartbeatTimer()
        require(confirmed.heartbeatTimer != nil, "read-only session still allows existing heartbeat lifecycle")
        scenarios += 1

        // A stopped old controller must neither change a shared Space object nor clear the new delegate/alert.
        reset()
        let old = make(), oldResponse = members(old)
        old.checkMeshMemberPermissions(); mesh(old)
        let oldAlert = SRAlertView.current!
        oldAlert.tap(0)
        let fresh = SpaceViewController(space: old.space)
        fresh.navigationController = Navigation()
        fresh.navigationController!.viewControllers = [fresh]
        fresh.navigationController!.viewIfLoaded?.window = View()
        let freshResponse = members(fresh)
        fresh.checkMeshMemberPermissions(); freshResponse(cloud(true))
        let freshAlert = SRAlertView.current!
        oldResponse(cloud(true)); oldAlert.tap(1); mesh(old)
        old.stopSpacePresenceTracking(reason: .sitesVisibleCleanup)
        require(SRAlertView.current === freshAlert && !fresh.space.disableEditorPermission,
                "old responses and actions cannot affect re-entry")
        require(MeshLibManager.manager.externalVendorMessageDelegate === fresh, "old cleanup must preserve new delegate")
        require(SRAlertView.shown.count == 2, "re-entry can prompt normally")
        scenarios += 1

        reset()
        let entering = make(visible: false), earlyResponse = members(entering)
        earlyResponse(cloud(true))
        require(SRAlertView.shown.isEmpty && entering.hasPendingTransferPermissionAlert,
                "pre-appearance conflict must remain pending")
        entering.navigationController!.viewIfLoaded?.window = View()
        entering.presentPendingTransferPermissionAlert()
        require(SRAlertView.shown.count == 1, "first appearance delivers pending conflict")
        scenarios += 1

        reset()
        let abandoned = make(visible: false), abandonedResponse = members(abandoned)
        abandonedResponse(cloud(true))
        abandoned.stopSpacePresenceTracking(reason: .leavingSpaceFlow)
        abandoned.navigationController!.viewIfLoaded?.window = View()
        abandoned.presentPendingTransferPermissionAlert()
        require(SRAlertView.shown.isEmpty, "deferred conflict must be cleared when entry is abandoned")
        scenarios += 1

        reset()
        let replaced = make()
        replaced.showTransferPermissionAlert()
        let replacedAlert = SRAlertView.current!
        let unrelated = SRAlertView(title: "other", message: "other", actions: [])
        unrelated.show()
        replacedAlert.tap(1)
        require(!replaced.space.disableEditorPermission, "replaced prompt must not mutate the session")
        replaced.showTransferPermissionAlert()
        require(SRAlertView.current !== unrelated, "replacement must not permanently lock future conflict prompts")
        unrelated.show()
        replaced.stopSpacePresenceTracking(reason: .leavingSpaceFlow)
        require(SRAlertView.current === unrelated, "stop must dismiss only its own alert")
        scenarios += 1

        for result in [cloud(false), .failure(.offline)] {
            reset()
            let normal = make()
            members(normal)(result)
            require(normal.heartbeatTimer != nil && normal.guidance == 1 && SRAlertView.shown.isEmpty,
                    "no-conflict and offline paths retain existing entry behavior")
            scenarios += 1
        }
        for result in [cloud(false), .failure(.offline)] {
            reset()
            let pending = make(), response = members(pending)
            pending.checkMeshMemberPermissions(); mesh(pending)
            response(result)
            require(pending.guidance == 0 && pending.heartbeatTimer == nil,
                    "other source must not resume editor presence while a conflict choice is pending")
            scenarios += 1
        }

        reset()
        let visitor = make(permission: .visitor)
        visitor.checkTheSpaceMembersRequest(); visitor.checkMeshMemberPermissions(); visitor.startHeartbeatTimer()
        require(MeshAPI.sends == 0 && visitor.heartbeatTimer != nil && SRAlertView.shown.isEmpty,
                "Visitor heartbeat entry remains available without editor probe")
        let local = make()
        local.space.uploadCloud = false
        local.checkMeshMemberPermissions(); mesh(local)
        require(SRAlertView.shown.count == 1, "local-only Space can still detect Mesh conflicts")
        scenarios += 1

        reset()
        let child = make(), childResponse = members(child)
        child.navigationController!.viewControllers.append(UIViewController())
        child.viewDidDisappear(true)
        require(!child.hasStoppedPresenceTracking && child.canHandleSpacePresenceCallbacks,
                "pushing a child must not stop Space presence")
        childResponse(cloud(true))
        require(SRAlertView.shown.count == 1, "active Space can handle conflict while on its child")
        child.navigationController!.viewControllers.removeAll()
        child.viewDidDisappear(true)
        require(child.hasStoppedPresenceTracking && SRAlertView.current == nil, "leaving clears owned alert")
        scenarios += 1

        for error: NetworkApiError in [.noSpacePermission, .incorrectPassword, .userUnauthorized, .noSitePermission] {
            reset()
            let stale = make()
            stale.startHeartbeatTimer()
            let reply = NetworkRequest.shared.requests.last!.completion
            stale.stopSpacePresenceTracking(reason: .leavingSpaceFlow)
            reply(.failure(error))
            require(SpaceConfigurationSafety.errors == 0 && SRAlertView.shown.isEmpty && stale.space.saves == 0,
                    "late heartbeat authority failure must not mutate or prompt")
            scenarios += 1
        }
        reset()
        let live = make()
        live.view.window = View()
        live.startHeartbeatTimer()
        NetworkRequest.shared.requests.last!.completion(.failure(.noSpacePermission))
        require(live.hasHandledPermissionLoss && live.space.state == .waitDeleted && live.space.saves == 1,
                "active-session permission loss must still be handled")
        require(SRAlertView.shown.count == 1, "active-session permission loss still informs the user")
        scenarios += 1

        for error: NetworkApiError in [.incorrectPassword, .noSpacePermission] {
            reset()
            let departed = make()
            departed.view.window = View()
            departed.startHeartbeatTimer()
            NetworkRequest.shared.requests.last!.completion(.failure(error))
            let staleAlert = SRAlertView.current!
            departed.navigationController!.viewControllers.removeAll()
            let other = SRAlertView(title: "new flow", message: "new flow", actions: [])
            other.show(); staleAlert.tap(0)
            require(departed.navigationController!.pops == 0 && SRAlertView.current === other,
                    "old permission-loss actions cannot dismiss or navigate a new flow")
            scenarios += 1
        }
        reset()
        let expiredPassword = make()
        expiredPassword.startHeartbeatTimer()
        NetworkRequest.shared.requests.last!.completion(.failure(.incorrectPassword))
        require(expiredPassword.space.requiresPasswordVerification, "active password failure is retained")
        SRAlertView.current!.tap(0)
        require(expiredPassword.hasStoppedPresenceTracking && expiredPassword.navigationController!.pops == 1,
                "active password confirmation still exits and stops presence")
        scenarios += 1

        reset()
        let delayedExit = make()
        delayedExit.startHeartbeatTimer()
        NetworkRequest.shared.requests.last!.completion(.failure(.noSitePermission))
        delayedExit.navigationController!.viewControllers.removeAll()
        Foundation.RunLoop.current.run(until: Date().addingTimeInterval(1.7))
        require(delayedExit.navigationController!.pops == 0, "delayed old permission exit cannot navigate a new flow")
        scenarios += 1

        reset()
        let mismatched = make()
        MeshNetworkManager.instance.currentNetworkKey.networkId.hex = "other-network"
        mismatched.checkMeshMemberPermissions()
        require(MeshAPI.sends == 0, "old Space cannot probe the new Mesh network")
        MeshLibManager.manager.externalVendorMessageDelegate = mismatched
        mesh(mismatched)
        require(SRAlertView.shown.isEmpty, "mismatched Mesh network cannot prompt")
        scenarios += 1

        reset()
        let displaced = make(), owner = make()
        displaced.checkMeshMemberPermissions()
        owner.checkMeshMemberPermissions()
        mesh(displaced)
        displaced.stopSpacePresenceTracking(reason: .leavingSpaceFlow)
        require(SRAlertView.shown.isEmpty && MeshLibManager.manager.externalVendorMessageDelegate === owner,
                "same-network old callbacks and cleanup must respect delegate ownership")
        scenarios += 1
        print("PASS: \(scenarios) Space presence callback scenarios (production bodies, UI/transport substitutes).")
    }
}

final class FixtureNavigationItem { var rightBarButtonItem: FixtureBarItem? = FixtureBarItem() }
final class FixtureBarItem { var isEnabled = true }
