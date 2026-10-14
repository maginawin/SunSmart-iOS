import Foundation

// Mesh transport, UIKit and storage are boundaries. Production display state,
// indicator updates and the controller's complete toggle/repair callbacks run below.
final class MeshNetwork {}
final class MeshNetworkManager {
    static let instance = MeshNetworkManager()
    var meshNetwork: MeshNetwork? = MeshNetwork()
    struct Key { var networkId = "net" }
    var currentNetworkKey = Key()
}
enum UserData { static var currentUserId = "account"; static var currentServerRegion = "region" }
extension String { var hex: String { self }; var localizedString: String { self } }
enum NodeSyncStatusGeneration {
    static var current = 0
    static func invalidate() { current += 1 }
}
struct SpacePageRevision {
    let generation = NodeSyncStatusGeneration.current
    var isCurrent: Bool { generation == NodeSyncStatusGeneration.current }
}
final class Schedule {
    let id: Int
    var enabled = false
    var existNodes = [1]
    var saves = 0
    init(_ id: Int) { self.id = id }
    func save() { saves += 1; NodeSyncStatusGeneration.invalidate() }
}
enum NodeSyncStatusRefresh {
    struct Request { let schedule: Schedule; let owner: ObjectIdentifier; let completion: (Bool) -> Void }
    static var pending: [Request] = []
    static func request(schedule: Schedule, owner: AnyObject, completion: @escaping (Bool) -> Void) {
        pending.append(.init(schedule: schedule, owner: ObjectIdentifier(owner), completion: completion))
    }
    static func cancel(owner: AnyObject) { pending.removeAll { $0.owner == ObjectIdentifier(owner) } }
    static func reply(_ schedule: Schedule, _ value: Bool) {
        let selected = pending.filter { $0.schedule === schedule }
        pending.removeAll { $0.schedule === schedule }
        precondition(!selected.isEmpty, "missing read for schedule \(schedule.id)")
        selected.forEach { $0.completion(value) }
    }
}

// PRODUCTION_DISPLAY

final class Indicator {
    var transitions: [Bool] = []
    var isHidden = true { didSet { transitions.append(isHidden) } }
}
final class SchedulesViewCell {
    var schedule: Schedule!
    let failedImageView = Indicator()
    // PRODUCTION_INDICATOR
}
final class Collection { var visibleCells: [Any] = [] }
typealias UICollectionView = Collection
typealias UICollectionViewCell = AnyObject
final class View { var window: Int? = 1 }
enum SpaceChangeDataType { case common, device }
let spaceDataChangedNotificaitonName = "test-space-change"
let isIPad = false
let iPadPreferredContentSize = 0
enum XWHUDManager {
    static func showTipHUD(_ message: String, isLineFeed: Bool) {}
    static func showCustomHUD(withMessage: String, isWindow: Bool) {}
    static func showSuccessTipHUD(_ message: String) {}
    static func showErrorTipHUD(_ message: String) {}
    static func hide() {}
}
final class MeshLibManager {
    static let manager = MeshLibManager()
    var isMeshNetworkConnected = true
}
enum ScheduleServer {
    static var success: ((Schedule) -> Void)?
    static var failed: ((Schedule) -> Void)?
    static func setEnabledState(schedule: Schedule, enabled: Bool,
                                success: @escaping (Schedule) -> Void, failed: @escaping (Schedule) -> Void) {
        schedule.enabled = enabled
        self.success = success; self.failed = failed
    }
}
final class SyncDevicesViewController {
    enum SyncType { case schedule(Schedule) }
    var syncSuccessCallback: ((Int) -> Void)?
    var backActionCallback: ((Int) -> Void)?
    var preferredContentSize = 0
    init(type: SyncType) {}
}
final class NavigationViewController {
    let root: SyncDevicesViewController
    init(rootViewController: SyncDevicesViewController) { root = rootViewController }
}
final class TimedControllerProbe {
    var syncDisplay: TimedListSyncDisplayState? = TimedListSyncDisplayState()
    var isPageVisible = true
    var viewIfLoaded: View? = View()
    var presentedViewController: NavigationViewController?
    let scheduleCollectionView = Collection()
    var reloads = 0
    func present(_ controller: NavigationViewController, animated: Bool) { presentedViewController = controller }
    func dismiss(animated: Bool) { presentedViewController = nil }
    func reloadCollectionItem(schedule: Schedule) { reloads += 1; render() }
    func toggle(_ schedule: Schedule, _ enabled: Bool) { setScheduleEnabled(schedule: schedule, enabled: enabled) }
    func render() {
        for case let cell as SchedulesViewCell in scheduleCollectionView.visibleCells {
            refreshSyncIndicator(schedule: cell.schedule, cell: cell)
        }
    }
    // PRODUCTION_OPERATION
    // PRODUCTION_WILL_DISPLAY
}

@main
struct TimedListSyncDisplayTests {
    static func require(_ condition: @autoclosure () -> Bool, _ message: String) {
        precondition(condition(), message)
    }

    static func main() {
        let first = Schedule(1), other = Schedule(2)
        let page = TimedControllerProbe()
        let cell = SchedulesViewCell(), otherCell = SchedulesViewCell()
        cell.schedule = first; otherCell.schedule = other
        page.scheduleCollectionView.visibleCells = [cell, otherCell]
        page.render()
        require(cell.failedImageView.isHidden && otherCell.failedImageView.isHidden, "pending displayed warning")
        NodeSyncStatusRefresh.reply(first, false)
        NodeSyncStatusRefresh.reply(other, true)

        // A prefetched Cell can receive its result before UIKit makes it visible.
        let prefetched = Schedule(3), prefetchedCell = SchedulesViewCell()
        prefetchedCell.schedule = prefetched
        page.syncDisplay?.refresh(schedule: prefetched) { _ in }
        NodeSyncStatusRefresh.reply(prefetched, true)
        page.collectionView(page.scheduleCollectionView, willDisplay: prefetchedCell, forItemAt: IndexPath(index: 2))
        require(!prefetchedCell.failedImageView.isHidden, "prefetched Cell missed its completed warning")
        require(cell.failedImageView.transitions.isEmpty, "clean initial read flashed")

        // Rebinding after a cloud revision retains both clean and warning results.
        NodeSyncStatusGeneration.invalidate(); page.render()
        let oldRead = NodeSyncStatusRefresh.pending.first { $0.schedule === first }!.completion
        page.toggle(first, true)
        oldRead(true)
        page.render()
        require(NodeSyncStatusRefresh.pending.isEmpty, "read submitted during operation")
        require(cell.failedImageView.isHidden && !otherCell.failedImageView.isHidden, "operation changed icons")
        let success = ScheduleServer.success!
        ScheduleServer.success?(first)
        require(cell.failedImageView.isHidden && !otherCell.failedImageView.isHidden, "completion reset icons")
        NodeSyncStatusRefresh.reply(first, false); NodeSyncStatusRefresh.reply(other, true)
        require(cell.failedImageView.transitions.isEmpty, "successful toggle flashed")
        require(otherCell.failedImageView.transitions == [false], "existing warning blinked")

        // A repeated terminal callback cannot finish a newer operation.
        page.toggle(first, false)
        success(first)
        page.render()
        require(NodeSyncStatusRefresh.pending.isEmpty, "old completion ended new operation")
        ScheduleServer.failed?(first)
        let repair = page.presentedViewController!.root
        page.render()
        require(NodeSyncStatusRefresh.pending.isEmpty, "initial failure published before repair exit")
        repair.backActionCallback?(0)
        NodeSyncStatusRefresh.reply(first, true); NodeSyncStatusRefresh.reply(other, true)
        require(!cell.failedImageView.isHidden, "partial failure missing final warning")

        // Repair success and complete failure with rollback use final reads.
        page.toggle(first, true); ScheduleServer.failed?(first)
        page.presentedViewController!.root.syncSuccessCallback?(0)
        NodeSyncStatusRefresh.reply(first, false); NodeSyncStatusRefresh.reply(other, true)
        require(cell.failedImageView.isHidden && first.enabled, "repair success not settled")
        page.toggle(first, false)
        first.enabled = true // server's complete-failure rollback
        ScheduleServer.failed?(first)
        page.presentedViewController!.root.backActionCallback?(0)
        NodeSyncStatusRefresh.reply(first, false); NodeSyncStatusRefresh.reply(other, true)
        require(cell.failedImageView.isHidden && first.enabled, "rollback forced a warning")

        // Empty target completes locally; a rejected disconnected operation leaves no lock.
        first.existNodes = []; page.toggle(first, false)
        NodeSyncStatusRefresh.reply(first, false); NodeSyncStatusRefresh.reply(other, true)
        first.existNodes = [1]; MeshLibManager.manager.isMeshNetworkConnected = false
        page.toggle(first, true)
        NodeSyncStatusGeneration.invalidate(); page.render()
        NodeSyncStatusRefresh.reply(first, false); NodeSyncStatusRefresh.reply(other, true)
        MeshLibManager.manager.isMeshNetworkConnected = true

        // Offscreen completion defers reads, but never leaves the operation frozen.
        page.toggle(first, true); page.isPageVisible = false; page.syncDisplay?.cancelReads()
        ScheduleServer.failed?(first)
        require(page.presentedViewController == nil && NodeSyncStatusRefresh.pending.isEmpty, "offscreen failure presented repair")
        page.isPageVisible = true; page.render()
        NodeSyncStatusRefresh.reply(first, true); NodeSyncStatusRefresh.reply(other, true)

        // Reuse while reading publishes to the current visible schedule, not the old Cell.
        NodeSyncStatusGeneration.invalidate(); page.render()
        let obsolete = NodeSyncStatusRefresh.pending.first { $0.schedule === first }!.completion
        cell.schedule = other; page.render()
        NodeSyncStatusRefresh.reply(first, false)
        require(!cell.failedImageView.isHidden, "old Cell read overwrote reused warning")
        NodeSyncStatusRefresh.reply(other, true)

        // Same id with a new object and a changed account must not reuse old results.
        let replacement = Schedule(1)
        page.syncDisplay?.retain(schedules: [replacement, other])
        cell.schedule = replacement; page.render(); obsolete(true)
        require(cell.failedImageView.isHidden, "replacement reused old warning")
        NodeSyncStatusRefresh.reply(replacement, false)
        NodeSyncStatusGeneration.invalidate(); page.render()
        let staleScope = NodeSyncStatusRefresh.pending.first { $0.schedule === replacement }!.completion
        UserData.currentUserId = "another-account"
        staleScope(true); page.render()
        require(cell.failedImageView.isHidden && otherCell.failedImageView.isHidden, "prior scope displayed state")

        // Explicit cancellation and network replacement invalidate pending publications.
        page.syncDisplay?.cancelReads()
        page.syncDisplay = TimedListSyncDisplayState(); page.render()
        let cancelled = NodeSyncStatusRefresh.pending.first!.completion
        page.syncDisplay?.cancelReads(); cancelled(true)
        require(page.syncDisplay?.displayedValue(for: replacement) == nil, "cancelled read published")
        page.render()
        MeshNetworkManager.instance.meshNetwork = MeshNetwork()
        let oldNetwork = NodeSyncStatusRefresh.pending.first!.completion
        oldNetwork(true)
        require(page.syncDisplay?.displayedValue(for: replacement) == nil, "old network published")

        // UI lifetime must not swallow a successful operation's cloud notification.
        var cloudNotified = false
        let observer = NotificationCenter.default.addObserver(forName: .init(spaceDataChangedNotificaitonName), object: nil, queue: nil) { _ in
            cloudNotified = true
        }
        var releasedPage: TimedControllerProbe? = TimedControllerProbe()
        weak var weakPage = releasedPage
        releasedPage?.toggle(replacement, true)
        releasedPage = nil
        require(weakPage == nil, "operation retained its page")
        ScheduleServer.success?(replacement)
        NotificationCenter.default.removeObserver(observer)
        require(cloudNotified, "page release swallowed cloud notification")
        print("PASS: Timed initial/reload stability, operation freeze, success, partial failure, rollback, repair, empty/offline, hidden page, reuse, cancellation, stale callbacks and scope changes")
    }
}
